#requires -Version 7.6
#requires -PSEdition Core

[CmdletBinding()]
param(
  [string]$StammdatenPath = (Join-Path -Path $PSScriptRoot -ChildPath ".." -AdditionalChildPath "Private", "Daten", "01_PERSOENLICHE_DATEN.md"),

  [switch]$WarnungenAlsFehler,

  [switch]$UngeklaerteLogistikAlsFehler,

  [string]$BewerbungsauftragPath,

  [string]$BerichtPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/Platform.psm1") -Force

$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$oks = New-Object System.Collections.Generic.List[string]
$script:PathComparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
$script:ReportWorkRoot = $null
$script:ResolvedReportPath = $null

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

function Get-WorkRootFromPath {
  param([string]$Path)

  $directory = [System.IO.DirectoryInfo]::new((Split-Path -Path ([System.IO.Path]::GetFullPath($Path)) -Parent))
  while ($null -ne $directory.Parent) {
    if ([string]::Equals($directory.Parent.Name, '_Arbeitsdateien', $script:PathComparison)) {
      return $directory.FullName
    }
    $directory = $directory.Parent
  }
  return $null
}

function Add-ErrorMessage {
  param([string]$Message)
  $errors.Add($Message) | Out-Null
  Write-Host "[FEHLER] $Message" -ForegroundColor Red
}

function Add-WarningMessage {
  param([string]$Message)
  $warnings.Add($Message) | Out-Null
  Write-Host "[WARNUNG] $Message" -ForegroundColor Yellow
}

function Add-OkMessage {
  param([string]$Message)
  $oks.Add($Message) | Out-Null
  Write-Host "[OK] $Message" -ForegroundColor Green
}

function Add-LogisticsIssue {
  param([string]$Message)
  if ($UngeklaerteLogistikAlsFehler) {
    Add-ErrorMessage -Message $Message
  } else {
    Add-WarningMessage -Message $Message
  }
}

function Test-IsPlaceholderValue {
  param([AllowEmptyString()][string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return $true
  }

  return $Value -match '(?i)\{\{|\}\}|\[[^\]]*(optional|z\.\s*B\.|ergänzen|Vollzeit|Teilzeit|vor Ort|hybrid|remote|ja\s*/\s*nein|manuelle Angabe)[^\]]*\]|TODO|DOKUMENT NOCH NICHT FINAL'
}

function Test-IsUnresolvedChoice {
  param([AllowEmptyString()][string]$Value)

  if (Test-IsPlaceholderValue -Value $Value) {
    return $true
  }

  return $Value.Trim() -match '^(?i:nicht festgelegt|offen|noch offen|unbekannt)$'
}

function Get-JsonProperty {
  param([object]$Object, [string]$Name)
  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

function Write-JsonReport {
  param([string]$Path, [hashtable]$Fields, [string]$LogisticsSource, [object]$ResolvedLogistics)

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return
  }

  $fullPath = $script:ResolvedReportPath
  if ([string]::IsNullOrWhiteSpace($fullPath) -or [string]::IsNullOrWhiteSpace($script:ReportWorkRoot)) {
    throw 'Berichtspfad wurde nicht als sicherer Arbeitsbereich validiert.'
  }
  $parent = Split-Path -Path $fullPath -Parent
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -Path $parent -ItemType Directory -Force | Out-Null
  }
  $null = Resolve-SafePath -Candidate $parent -Root $script:ReportWorkRoot -AllowRoot -MustExist -PathType Container
  $fullPath = Resolve-SafePath -Candidate $fullPath -Root $script:ReportWorkRoot -ForWrite -PathType Leaf

  $fieldStates = [ordered]@{}
  foreach ($fieldName in $Fields.Keys) {
    $value = [string]$Fields[$fieldName]
    $fieldStates[$fieldName] = if (Test-IsPlaceholderValue -Value $value) {
      "platzhalter_oder_leer"
    } elseif (Test-IsUnresolvedChoice -Value $value) {
      "nicht_festgelegt"
    } else {
      "gepflegt"
    }
  }

  $report = [ordered]@{
    schemaVersion = 2
    checkedAtUtc = [datetime]::UtcNow.ToString("o")
    source = [System.IO.Path]::GetFullPath($StammdatenPath)
    applicationOrder = if ([string]::IsNullOrWhiteSpace($BewerbungsauftragPath)) { $null } else { [System.IO.Path]::GetFullPath($BewerbungsauftragPath) }
    logisticsSource = $LogisticsSource
    resolvedCoreLogistics = $ResolvedLogistics
    status = if ($errors.Count -gt 0) { "fehler" } elseif ($warnings.Count -gt 0) { "warnung" } else { "ok" }
    errors = @($errors)
    warnings = @($warnings)
    oks = @($oks)
    fieldStates = $fieldStates
  }
  Set-Content -LiteralPath $fullPath -Encoding UTF8 -Value ($report | ConvertTo-Json -Depth 6)
}

try {
  $stammdatenFull = [System.IO.Path]::GetFullPath($StammdatenPath)
  $dataRoot = Split-Path -Path $stammdatenFull -Parent
  $privateRoot = Split-Path -Path $dataRoot -Parent
  if (-not [string]::Equals((Split-Path -Path $dataRoot -Leaf), 'Daten', $script:PathComparison) -or
      -not [string]::Equals((Split-Path -Path $privateRoot -Leaf), 'Private', $script:PathComparison)) {
    throw 'StammdatenPath muss unter <Projektwurzel>/Private/Daten liegen.'
  }
  $privateRoot = Resolve-SafePath -Candidate $privateRoot -Root $privateRoot -AllowRoot -MustExist -PathType Container
  $dataRoot = Resolve-SafePath -Candidate $dataRoot -Root $privateRoot -MustExist -PathType Container
  $resolvedPath = Resolve-SafePath -Candidate $StammdatenPath -Root $dataRoot -MustExist -PathType Leaf
  $StammdatenPath = $resolvedPath

  $resolvedOrderPath = $null
  $applicationsRoot = Resolve-SafePath -Candidate (Join-Path -Path $privateRoot -ChildPath 'Bewerbungen') -Root $privateRoot -PathType Container
  if (-not [string]::IsNullOrWhiteSpace($BewerbungsauftragPath)) {
    $orderApplicationsRoot = Get-ApplicationsRootFromPath -Path $BewerbungsauftragPath
    if ([string]::IsNullOrWhiteSpace($orderApplicationsRoot) -or -not (Test-SamePath -Left $orderApplicationsRoot -Right $applicationsRoot)) {
      throw 'BewerbungsauftragPath muss unter demselben Private/Bewerbungen-Root wie die Stammdaten liegen.'
    }
    $applicationsRoot = Resolve-SafePath -Candidate $applicationsRoot -Root $privateRoot -MustExist -PathType Container
    $resolvedOrderPath = Resolve-SafePath -Candidate $BewerbungsauftragPath -Root $applicationsRoot -MustExist -PathType Leaf
    $script:ReportWorkRoot = Resolve-SafePath -Candidate (Split-Path -Path $resolvedOrderPath -Parent) -Root $applicationsRoot -MustExist -PathType Container
    $workCollection = Split-Path -Path $script:ReportWorkRoot -Parent
    if (-not [string]::Equals((Split-Path -Path $workCollection -Leaf), '_Arbeitsdateien', $script:PathComparison)) {
      throw 'Bewerbungsauftrag muss direkt in einem Arbeitsordner unter _Arbeitsdateien liegen.'
    }
    $BewerbungsauftragPath = $resolvedOrderPath
  }

  if (-not [string]::IsNullOrWhiteSpace($BerichtPath)) {
    if ($null -eq $script:ReportWorkRoot) {
      $reportApplicationsRoot = Get-ApplicationsRootFromPath -Path $BerichtPath
      $script:ReportWorkRoot = Get-WorkRootFromPath -Path $BerichtPath
      if ([string]::IsNullOrWhiteSpace($reportApplicationsRoot) -or
          [string]::IsNullOrWhiteSpace($script:ReportWorkRoot) -or
          -not (Test-SamePath -Left $reportApplicationsRoot -Right $applicationsRoot)) {
        throw 'BerichtPath muss in einem Arbeitsordner unter demselben Private/Bewerbungen-Root liegen.'
      }
      $applicationsRoot = Resolve-SafePath -Candidate $applicationsRoot -Root $privateRoot -MustExist -PathType Container
      $script:ReportWorkRoot = Resolve-SafePath -Candidate $script:ReportWorkRoot -Root $applicationsRoot -MustExist -PathType Container
    }
    $script:ResolvedReportPath = Resolve-SafePath -Candidate $BerichtPath -Root $script:ReportWorkRoot -ForWrite -PathType Leaf
    if (Test-SamePath -Left $script:ResolvedReportPath -Right $resolvedPath) {
      throw 'BerichtPath darf die Stammdatendatei nicht aliasieren.'
    }
    if ($null -ne $resolvedOrderPath -and (Test-SamePath -Left $script:ResolvedReportPath -Right $resolvedOrderPath)) {
      throw 'BerichtPath darf den Bewerbungsauftrag nicht aliasieren.'
    }
  }
} catch {
  Write-Host "[FEHLER] Unsicherer Stammdaten-, Auftrags- oder Berichtspfad: $($_.Exception.Message)" -ForegroundColor Red
  exit 2
}

$lines = @(Get-Content -LiteralPath $resolvedPath -Encoding UTF8)
$fields = [ordered]@{}
foreach ($line in $lines) {
  if ($line -match '^\s*-\s*(?<key>[^:]+):\s*(?<value>.*)$') {
    $key = $Matches.key.Trim()
    $value = $Matches.value.Trim()
    if (-not $fields.Contains($key)) {
      $fields[$key] = $value
    }
  }
}

$auftrag = $null
$applicationLogistics = $null
if (-not [string]::IsNullOrWhiteSpace($BewerbungsauftragPath)) {
  if (-not (Test-Path -LiteralPath $BewerbungsauftragPath -PathType Leaf)) {
    Add-ErrorMessage "Bewerbungsauftrag fehlt oder ist keine Datei: $BewerbungsauftragPath"
  } else {
    try {
      $auftrag = Get-Content -LiteralPath $BewerbungsauftragPath -Raw -Encoding UTF8 | ConvertFrom-Json
      $applicationLogistics = Get-JsonProperty -Object $auftrag -Name "bewerbungslogistik"
    } catch {
      Add-ErrorMessage "Bewerbungsauftrag ist kein gültiges JSON: $($_.Exception.Message)"
    }
  }
}

Write-Host "Pruefe Stammdaten: $resolvedPath"

$requiredIdentity = @(
  "Vollständiger Name",
  "Vorname",
  "Nachname",
  "Dateiname-Name",
  "Adresse",
  "Telefon",
  "E-Mail",
  "Verfügbarkeit"
)

foreach ($fieldName in $requiredIdentity) {
  if (-not $fields.Contains($fieldName)) {
    Add-ErrorMessage "Pflichtfeld fehlt: $fieldName"
    continue
  }
  $value = [string]$fields[$fieldName]
  if (Test-IsPlaceholderValue -Value $value) {
    Add-ErrorMessage "Pflichtfeld ist leer oder enthält einen Beispielplatzhalter: $fieldName"
  } else {
    Add-OkMessage "Pflichtfeld ist gepflegt: $fieldName"
  }
}

if ($fields.Contains("E-Mail") -and -not (Test-IsPlaceholderValue -Value ([string]$fields["E-Mail"]))) {
  if ([string]$fields["E-Mail"] -notmatch '^[^\s@]+@[^\s@]+\.[^\s@]+$') {
    Add-ErrorMessage "E-Mail hat kein plausibles Format."
  }
}

if ($fields.Contains("Dateiname-Name") -and -not (Test-IsPlaceholderValue -Value ([string]$fields["Dateiname-Name"]))) {
  if ([string]$fields["Dateiname-Name"] -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z0-9][A-Za-z0-9.-]*$') {
    Add-ErrorMessage "Dateiname-Name entspricht nicht dem Schema Nachname.Vorname."
  }
}

$coreChoices = @(
  [pscustomobject]@{ Field = "Gewünschte Stellenart"; Property = "stellenart" },
  [pscustomobject]@{ Field = "Gewünschtes Arbeitsmodell"; Property = "arbeitsmodell" },
  [pscustomobject]@{ Field = "Wunschgehalt verwenden"; Property = "wunschgehaltVerwenden" },
  [pscustomobject]@{ Field = "Gehaltslogik"; Property = "gehaltslogik" }
)
$resolvedCoreLogistics = [ordered]@{}
$usedApplicationLogistics = $false
foreach ($choice in $coreChoices) {
  $fieldName = $choice.Field
  $applicationValue = [string](Get-JsonProperty -Object $applicationLogistics -Name $choice.Property)
  $masterValue = if ($fields.Contains($fieldName)) { [string]$fields[$fieldName] } else { "" }
  $value = if (-not (Test-IsUnresolvedChoice -Value $applicationValue)) {
    $usedApplicationLogistics = $true
    $applicationValue
  } else {
    $masterValue
  }
  $resolvedCoreLogistics[$choice.Property] = $value

  if ([string]::IsNullOrWhiteSpace($value)) {
    Add-LogisticsIssue "Zentrale Bewerbungslogistik fehlt: $fieldName"
    continue
  }
  if (Test-IsUnresolvedChoice -Value $value) {
    Add-LogisticsIssue "Zentrale Bewerbungslogistik ist noch nicht eindeutig festgelegt: $fieldName"
  } else {
    $sourceLabel = if (-not (Test-IsUnresolvedChoice -Value $applicationValue)) { "Bewerbungsauftrag" } else { "Stammdaten" }
    Add-OkMessage "Bewerbungslogistik ist gepflegt: $fieldName ($sourceLabel)"
  }
}
$logisticsSource = if ($usedApplicationLogistics) { "bewerbungsauftrag_mit_stammdaten_fallback" } else { "stammdaten" }

$optionalLogistics = @(
  "Frühester Eintrittstermin",
  "Gewünschter Stundenumfang",
  "Gewünschte Region",
  "Maximale Pendeldistanz",
  "Reisebereitschaft",
  "Schicht- oder Wochenendbereitschaft",
  "Befristung",
  "Umzugsbereitschaft",
  "Wunschgehalt manuell",
  "Gehaltsmodell",
  "Gehaltsregion"
)
foreach ($fieldName in $optionalLogistics) {
  if ($fields.Contains($fieldName) -and (Test-IsPlaceholderValue -Value ([string]$fields[$fieldName]))) {
    Add-WarningMessage "Optionales Feld enthält noch Beispieltext statt eines eindeutigen Werts: $fieldName"
  }
}

Write-JsonReport -Path $BerichtPath -Fields $fields -LogisticsSource $logisticsSource -ResolvedLogistics $resolvedCoreLogistics

Write-Host ""
Write-Host "Zusammenfassung:"
Write-Host "OK: $($oks.Count)"
Write-Host "Warnungen: $($warnings.Count)"
Write-Host "Fehler: $($errors.Count)"

if ($errors.Count -gt 0) {
  Write-Host "ERGEBNIS: FEHLER" -ForegroundColor Red
  exit 1
}
if (($warnings.Count -gt 0) -and $WarnungenAlsFehler) {
  Write-Host "ERGEBNIS: WARNUNGEN ALS FEHLER" -ForegroundColor Red
  exit 1
}

Write-Host "ERGEBNIS: OK" -ForegroundColor Green
exit 0
