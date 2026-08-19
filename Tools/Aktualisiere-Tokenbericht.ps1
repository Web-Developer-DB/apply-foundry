#requires -Version 7.6
#requires -PSEdition Core

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Arbeitsordner,

  [Parameter(Mandatory = $true)]
  [ValidateSet("lebenslauf", "gesamte_bewerbung", "technische_vorbereitung")]
  [string]$Messbereich,

  [ValidateSet("abschnitt", "gesamte_agentensitzung")]
  [string]$Messumfang = "abschnitt",

  [switch]$NutzungsdatenVerfuegbar,

  [string]$Anbieter,

  [string]$Modell,

  [string]$VorgangsId,

  [string]$Messquelle = "runtime",

  [Nullable[datetime]]$Beginn,

  [Nullable[datetime]]$Ende,

  [Nullable[long]]$EingabeTokens,

  [Nullable[long]]$AusgabeTokens,

  [Nullable[long]]$CacheLeseTokens,

  [Nullable[long]]$CacheSchreibTokens,

  [Nullable[long]]$ReasoningTokens,

  [Nullable[long]]$GesamtTokens
)

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/AtomicFile.psm1") -Force

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/Platform.psm1") -Force

$script:PathComparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }

function Get-ApplicationsRootFromPath {
  param([string]$Path, [switch]$Container)

  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $directory = if ($Container) { [System.IO.DirectoryInfo]::new($fullPath) } else { [System.IO.DirectoryInfo]::new((Split-Path -Path $fullPath -Parent)) }
  while ($null -ne $directory) {
    if ([string]::Equals($directory.Name, 'Bewerbungen', $script:PathComparison) -and
        $null -ne $directory.Parent -and
        [string]::Equals($directory.Parent.Name, 'Private', $script:PathComparison)) {
      return $directory.FullName
    }
    $directory = $directory.Parent
  }
  return $null
}

trap {
  Write-Host "[FEHLER] Tokenbericht konnte nicht aktualisiert werden: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}

function ConvertTo-NormalizedMetadataValue {
  param([string]$Value, [string]$Name)

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return $null
  }
  $normalized = [regex]::Replace($Value.Trim(), '\s+', ' ')
  if ($normalized.Length -gt 200) {
    throw "$Name darf höchstens 200 Zeichen enthalten."
  }
  return $normalized
}

function Get-JsonProperty {
  param([object]$Object, [string]$Name)

  if ($null -eq $Object) { return $null }
  if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Name)) {
    return $Object[$Name]
  }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

function Format-TokenValue {
  param([object]$Value)
  if ($null -eq $Value) { return "nicht verfügbar" }
  return [string]$Value
}

if (-not (Test-Path -LiteralPath $Arbeitsordner -PathType Container)) {
  throw "Arbeitsordner fehlt oder ist kein Verzeichnis: $Arbeitsordner"
}

try {
  $applicationsRoot = Get-ApplicationsRootFromPath -Path $Arbeitsordner -Container
  if ([string]::IsNullOrWhiteSpace($applicationsRoot)) {
    throw 'Arbeitsordner muss unter <Projektwurzel>/Private/Bewerbungen liegen.'
  }
  $applicationsRoot = Resolve-SafePath -Candidate $applicationsRoot -Root $applicationsRoot -AllowRoot -MustExist -PathType Container
  $resolvedWork = Resolve-SafePath -Candidate $Arbeitsordner -Root $applicationsRoot -MustExist -PathType Container
  $workFilesFolder = Split-Path -Path $resolvedWork -Parent
  if (-not [string]::Equals((Split-Path -Path $workFilesFolder -Leaf), '_Arbeitsdateien', $script:PathComparison)) {
    throw 'Arbeitsordner muss direkt unter _Arbeitsdateien liegen.'
  }
  $reportPath = Resolve-SafePath -Candidate (Join-Path -Path $resolvedWork -ChildPath "Tokenverbrauch.json") -Root $resolvedWork -ForWrite -PathType Leaf
} catch {
  Write-Host "[FEHLER] Unsicherer Tokenberichtspfad: $($_.Exception.Message)" -ForegroundColor Red
  exit 2
}
$providerValue = ConvertTo-NormalizedMetadataValue -Value $Anbieter -Name "Anbieter"
$modelValue = ConvertTo-NormalizedMetadataValue -Value $Modell -Name "Modell"
$sessionValue = ConvertTo-NormalizedMetadataValue -Value $VorgangsId -Name "VorgangsId"
$sourceValue = ConvertTo-NormalizedMetadataValue -Value $Messquelle -Name "Messquelle"
if ([string]::IsNullOrWhiteSpace($sourceValue)) {
  throw "Messquelle darf nicht leer sein."
}

$tokenValues = [ordered]@{
  inputTokens = $EingabeTokens
  outputTokens = $AusgabeTokens
  cachedInputTokens = $CacheLeseTokens
  cacheWriteTokens = $CacheSchreibTokens
  reasoningTokens = $ReasoningTokens
  totalTokens = $GesamtTokens
}
$suppliedTokenCount = 0
foreach ($entry in $tokenValues.GetEnumerator()) {
  if ($null -ne $entry.Value) {
    if ([long]$entry.Value -lt 0) {
      throw "Tokenwerte dürfen nicht negativ sein: $($entry.Key)"
    }
    $suppliedTokenCount++
  }
}

if ($NutzungsdatenVerfuegbar) {
  if ([string]::IsNullOrWhiteSpace($providerValue) -or [string]::IsNullOrWhiteSpace($modelValue)) {
    throw "Bei verfügbaren Nutzungsdaten müssen Anbieter und Modell angegeben werden."
  }
  if ($suppliedTokenCount -eq 0) {
    throw "Bei verfügbaren Nutzungsdaten muss mindestens ein maschinenlesbarer Tokenwert angegeben werden."
  }
} elseif ($suppliedTokenCount -gt 0) {
  throw "Tokenwerte dürfen nur mit -NutzungsdatenVerfuegbar gespeichert werden."
}

if ($null -ne $Beginn -and $null -ne $Ende -and $Ende.Value -lt $Beginn.Value) {
  throw "Ende darf nicht vor Beginn liegen."
}

$existing = $null
$existingSections = @()
if (Test-Path -LiteralPath $reportPath -PathType Leaf) {
  $existing = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
  if ([int](Get-JsonProperty -Object $existing -Name "schemaVersion") -ne 1) {
    throw "Nicht unterstützte Schema-Version in Tokenverbrauch.json."
  }
  $rawSections = Get-JsonProperty -Object $existing -Name "sections"
  if ($null -ne $rawSections) {
    $existingSections = @($rawSections)
  }
}

$previousSection = @($existingSections | Where-Object { [string](Get-JsonProperty -Object $_ -Name "name") -eq $Messbereich } | Select-Object -First 1)
$preserveAvailableSection = (-not $NutzungsdatenVerfuegbar) -and $previousSection.Count -eq 1 -and ([string](Get-JsonProperty -Object $previousSection[0] -Name "availability") -eq "available")

if ($preserveAvailableSection) {
  $section = $previousSection[0]
} else {
  $reason = if ($NutzungsdatenVerfuegbar) {
    $null
  } else {
    "Von dieser Agentenumgebung nicht bereitgestellt."
  }
  $section = [ordered]@{
    name = $Messbereich
    availability = if ($NutzungsdatenVerfuegbar) { "available" } else { "unavailable" }
    reason = $reason
    measurementScope = $Messumfang
    startedAt = if ($null -eq $Beginn) { $null } else { $Beginn.Value.ToUniversalTime().ToString("o") }
    finishedAt = if ($null -eq $Ende) { $null } else { $Ende.Value.ToUniversalTime().ToString("o") }
    inputTokens = if ($NutzungsdatenVerfuegbar) { $EingabeTokens } else { $null }
    outputTokens = if ($NutzungsdatenVerfuegbar) { $AusgabeTokens } else { $null }
    cachedInputTokens = if ($NutzungsdatenVerfuegbar) { $CacheLeseTokens } else { $null }
    cacheWriteTokens = if ($NutzungsdatenVerfuegbar) { $CacheSchreibTokens } else { $null }
    reasoningTokens = if ($NutzungsdatenVerfuegbar) { $ReasoningTokens } else { $null }
    totalTokens = if ($NutzungsdatenVerfuegbar) { $GesamtTokens } else { $null }
  }
}

$sections = @($existingSections | Where-Object { [string](Get-JsonProperty -Object $_ -Name "name") -ne $Messbereich })
$sections += $section
$anyAvailable = @($sections | Where-Object { [string](Get-JsonProperty -Object $_ -Name "availability") -eq "available" }).Count -gt 0

$existingProvider = Get-JsonProperty -Object $existing -Name "provider"
$existingModel = Get-JsonProperty -Object $existing -Name "model"
$existingSession = Get-JsonProperty -Object $existing -Name "sessionId"
$report = [ordered]@{
  schemaVersion = 1
  provider = if ($null -ne $providerValue) { $providerValue } else { $existingProvider }
  model = if ($null -ne $modelValue) { $modelValue } else { $existingModel }
  sessionId = if ($null -ne $sessionValue) { $sessionValue } else { $existingSession }
  measurementSource = $sourceValue
  availability = if ($anyAvailable) { "available" } else { "unavailable" }
  reason = if ($anyAvailable) { $null } else { "Von dieser Agentenumgebung nicht bereitgestellt." }
  sections = $sections
}

$reportPath = Resolve-SafePath -Candidate $reportPath -Root $resolvedWork -ForWrite -PathType Leaf
Write-AtomicJson -Path $reportPath -Value $report -Depth 8

$heading = switch ($Messbereich) {
  "lebenslauf" { "Lebenslauf" }
  "gesamte_bewerbung" { "Gesamte Bewerbung" }
  "technische_vorbereitung" { "Technische Vorbereitung" }
}
$storedAvailability = [string](Get-JsonProperty -Object $section -Name "availability")
if ($storedAvailability -ne "available") {
  Write-Host "Tokenverbrauch: Von dieser Agentenumgebung nicht bereitgestellt."
}
Write-Host "Tokenverbrauch – $heading"
Write-Host "Anbieter: $(Format-TokenValue -Value $report.provider)"
Write-Host "Modell: $(Format-TokenValue -Value $report.model)"
Write-Host "Eingabe: $(Format-TokenValue -Value (Get-JsonProperty -Object $section -Name 'inputTokens'))"
Write-Host "Ausgabe: $(Format-TokenValue -Value (Get-JsonProperty -Object $section -Name 'outputTokens'))"
Write-Host "Gesamt: $(Format-TokenValue -Value (Get-JsonProperty -Object $section -Name 'totalTokens'))"
Write-Host "Messquelle: $($report.measurementSource)"
if ([string](Get-JsonProperty -Object $section -Name "measurementScope") -eq "gesamte_agentensitzung") {
  if ($Messbereich -eq "lebenslauf") {
    Write-Host "Messbereich: gesamte Agentensitzung; eine isolierte Messung nur für den Lebenslauf ist nicht verfügbar."
  } else {
    Write-Host "Messbereich: gesamte Agentensitzung; eine isolierte Messung für den gewählten Abschnitt ist nicht verfügbar."
  }
}
Write-Host "Bericht: $reportPath"
exit 0
