#requires -Version 7.6
#requires -PSEdition Core

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Ordner,

  [string]$StammdatenPath = (Join-Path -Path $PSScriptRoot -ChildPath ".." -AdditionalChildPath "Private", "Daten", "01_PERSOENLICHE_DATEN.md"),

  [string]$ProfilPath = (Join-Path -Path $PSScriptRoot -ChildPath ".." -AdditionalChildPath "Private", "Daten", "02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md"),

  [Parameter(Mandatory = $true)]
  [string]$AuftragPath,

  [Parameter(Mandatory = $true)]
  [string]$AnforderungsmatrixPath,

  [string]$EvidenzindexPath,

  [switch]$WarnungenAlsFehler,

  [string]$BerichtPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/Platform.psm1") -Force
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/Passfoto.psm1") -Force
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/AtomicFile.psm1") -Force -Global
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/TextContract.psm1") -Force -DisableNameChecking
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/MatrixContract.psm1") -Force
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/EvidenceIndexContract.psm1") -Force
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/AtomicFile.psm1") -Force -Global

$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$oks = New-Object System.Collections.Generic.List[string]
$script:PathComparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
$script:ApplicationsRoot = $null
$script:WorkRoot = $null
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

function ConvertTo-SafeFileList {
  param([object[]]$Files, [string]$Root, [string]$Context)

  $safeFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
  foreach ($file in @($Files)) {
    try {
      $safePath = Resolve-SafePath -Candidate $file.FullName -Root $Root -MustExist -PathType Leaf
      $safeFiles.Add((Get-Item -LiteralPath $safePath -Force))
    } catch {
      Write-Host "[FEHLER] $Context enthält einen unsicheren Dateipfad: $($file.FullName): $($_.Exception.Message)" -ForegroundColor Red
      exit 2
    }
  }
  return $safeFiles.ToArray()
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

function Get-MarkdownFields {
  param([string]$Path)
  $result = [ordered]@{}
  foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
    if ($line -match '^\s*-\s*(?<key>[^:]+):\s*(?<value>.*)$') {
      $key = $Matches.key.Trim()
      if (-not $result.Contains($key)) {
        $result[$key] = $Matches.value.Trim()
      }
    }
  }
  return $result
}

function Get-JsonProperty {
  param([object]$Object, [string]$Name)
  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return $null
  }
  return $property.Value
}

function Convert-ToSlug {
  param([string]$Value)
  return ConvertTo-ContractSlug -Text $Value
}

function Get-TextSha256 {
  param([Parameter(Mandatory)][string]$Text)

  $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Text)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '')
  } finally {
    $sha.Dispose()
  }
}

function Get-NormalizedSourceText {
  param([AllowNull()][string]$Text)
  if ($null -eq $Text) { return '' }
  return ([regex]::Replace($Text.Trim(), '\s+', ' '))
}

function Get-SourceRangeText {
  param(
    [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines,
    [int]$From,
    [int]$To
  )
  if ($From -lt 1 -or $To -lt $From -or $To -gt $Lines.Count) { return $null }
  return [string]::Join(' ', @($Lines[($From - 1)..($To - 1)]))
}

function Test-TechnicalReferenceId {
  param([string]$Value)
  return -not [string]::IsNullOrWhiteSpace($Value) -and $Value -match '^[a-z0-9][a-z0-9._-]{0,79}$'
}

function Get-ExplicitJobSignalLineNumbers {
  param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines)

  $result = [System.Collections.Generic.HashSet[int]]::new()
  $inTaskSection = $false
  for ($index = 0; $index -lt $Lines.Count; $index++) {
    $line = $Lines[$index].Trim()
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $heading = ($line -replace '^#{1,6}\s*', '').Trim().TrimEnd(':').ToLowerInvariant()
    $isHeading = $line -match '^#{1,6}\s+' -or $heading -match '^(ihre|deine|unsere)\s+(aufgaben|tätigkeiten|verantwortlichkeiten)$'
    if ($isHeading) {
      $inTaskSection = $heading -match '(aufgaben|tätigkeiten|verantwortlichkeiten)'
      continue
    }
    $isExplicitRequirement = $line -match '(?i)\b(muss|müssen|must|required|zwingend|mindestens|erforderlich|voraussetzung|voraussetzungen|wir erwarten|sie bringen mit|dein profil|ihr profil|kenntnisse (?:in|mit)|erfahrung (?:in|mit)|sicherer umgang)\b'
    $isTaskBullet = $inTaskSection -and $line -match '^(?:[-*•]|\d+[.)])\s+'
    if ($isExplicitRequirement -or $isTaskBullet) { $null = $result.Add($index + 1) }
  }
  return @($result | Sort-Object)
}

function Add-DocumentCountResult {
  param(
    [array]$Files,
    [bool]$Expected,
    [string]$Label
  )
  if ($Expected -and $Files.Count -eq 1) {
    Add-OkMessage "$Label ist laut Dokumentumfang genau einmal vorhanden."
  } elseif ($Expected -and $Files.Count -eq 0) {
    Add-ErrorMessage "$Label ist ausgewählt, fehlt aber im Kandidatensatz."
  } elseif ($Expected) {
    Add-ErrorMessage "$Label ist ausgewählt, aber mehrfach vorhanden: $($Files.Name -join ', ')"
  } elseif ($Files.Count -gt 0) {
    Add-ErrorMessage "$Label ist nicht ausgewählt, aber im Kandidatensatz vorhanden: $($Files.Name -join ', ')"
  } else {
    Add-OkMessage "$Label ist laut Dokumentumfang nicht erforderlich."
  }
}

function Convert-HtmlToText {
  param([string]$Html)
  $withoutStyle = [regex]::Replace($Html, '(?is)<style\b[^>]*>.*?</style>', ' ')
  $withoutTags = [regex]::Replace($withoutStyle, '(?is)<[^>]+>', ' ')
  return [System.Net.WebUtility]::HtmlDecode($withoutTags)
}

function Get-FirstHtmlPageText {
  param([string]$Html)
  if ([string]::IsNullOrWhiteSpace($Html)) { return "" }
  $pageMatch = [regex]::Match($Html, '(?is)<main\b[^>]*class\s*=\s*["''][^"'']*\bpage\b[^"'']*["''][^>]*>(?<body>.*?)</main>')
  if (-not $pageMatch.Success) { return "" }
  return Convert-HtmlToText -Html $pageMatch.Groups['body'].Value
}

function Normalize-Text {
  param([AllowEmptyString()][string]$Text)
  if ($null -eq $Text) { return "" }
  $normalized = $Text.Replace([char]0x2013, '-').Replace([char]0x2014, '-').Replace([char]0x00A0, ' ')
  $normalized = [regex]::Replace($normalized, '\s+', ' ')
  return $normalized.Trim().ToLowerInvariant()
}

function Test-ContainsText {
  param([string]$Haystack, [AllowEmptyString()][string]$Needle)
  if ([string]::IsNullOrWhiteSpace($Needle)) { return $false }
  return (Normalize-Text -Text $Haystack).Contains((Normalize-Text -Text $Needle))
}

function Write-JsonReport {
  param(
    [string]$Path,
    [array]$Periods,
    [array]$RequiredPeriods,
    [array]$CompactSchoolPeriods,
    [object]$FitAssessment,
    [string]$SchoolMode,
    [string]$ProfileLinksMode,
    [string]$DocumentMode,
    [object]$DocumentScope,
    [object]$Passfoto,
    [object]$RecruiterCoverage,
    [object]$EvidenceCoverage,
    [object]$LetterCoverage,
    [object]$ExternalSourceCoverage,
    [object]$EvidenceDisposition,
    [object]$LanguageQuality
  )
  if ([string]::IsNullOrWhiteSpace($Path)) { return }
  $fullPath = $script:ResolvedReportPath
  if ([string]::IsNullOrWhiteSpace($fullPath)) {
    throw 'Berichtspfad wurde nicht als sicherer Arbeitsbereich validiert.'
  }
  $parent = Split-Path -Path $fullPath -Parent
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -Path $parent -ItemType Directory -Force | Out-Null
  }
  $null = Resolve-SafePath -Candidate $parent -Root $script:WorkRoot -AllowRoot -MustExist -PathType Container
  $fullPath = Resolve-SafePath -Candidate $fullPath -Root $script:WorkRoot -ForWrite -PathType Leaf
  $report = [ordered]@{
    schemaVersion = 6
    checkedAtUtc = [datetime]::UtcNow.ToString("o")
    applicationFolder = [System.IO.Path]::GetFullPath($Ordner)
    status = if ($errors.Count -gt 0) { "fehler" } elseif ($warnings.Count -gt 0) { "warnung" } else { "ok" }
    errors = @($errors)
    warnings = @($warnings)
    oks = @($oks)
    checkedFormalPeriods = $Periods
    requiredFormalPeriods = $RequiredPeriods
    compactedSchoolPeriods = $CompactSchoolPeriods
    schoolMode = $SchoolMode
    profileLinksMode = $ProfileLinksMode
    documentMode = $DocumentMode
    documentScope = $DocumentScope
    passfoto = $Passfoto
    fitAssessment = $FitAssessment
    recruiterCoverage = $RecruiterCoverage
    evidenceCoverage = $EvidenceCoverage
    anschreibenCoverage = $LetterCoverage
    externalSourceCoverage = $ExternalSourceCoverage
    evidenzDisposition = $EvidenceDisposition
    sprachqualitaet = $LanguageQuality
  }
  Write-AtomicJson -Path $fullPath -Value $report -Depth 6
}

try {
  $script:ApplicationsRoot = Get-ApplicationsRootFromPath -Path $AuftragPath
  if ([string]::IsNullOrWhiteSpace($script:ApplicationsRoot)) {
    throw 'AuftragPath muss unter <Projektwurzel>/Private/Bewerbungen liegen.'
  }
  $script:ApplicationsRoot = Resolve-SafePath -Candidate $script:ApplicationsRoot -Root $script:ApplicationsRoot -AllowRoot -MustExist -PathType Container
  $AuftragPath = Resolve-SafePath -Candidate $AuftragPath -Root $script:ApplicationsRoot -MustExist -PathType Leaf
  $script:WorkRoot = Resolve-SafePath -Candidate (Split-Path -Path $AuftragPath -Parent) -Root $script:ApplicationsRoot -MustExist -PathType Container
  $workCollection = Split-Path -Path $script:WorkRoot -Parent
  if (-not [string]::Equals((Split-Path -Path $workCollection -Leaf), '_Arbeitsdateien', $script:PathComparison)) {
    throw 'Bewerbungsauftrag muss direkt in einem Arbeitsordner unter _Arbeitsdateien liegen.'
  }

  $privateRoot = Split-Path -Path $script:ApplicationsRoot -Parent
  $dataRoot = Resolve-SafePath -Candidate (Join-Path -Path $privateRoot -ChildPath 'Daten') -Root $privateRoot -MustExist -PathType Container
  $StammdatenPath = Resolve-SafePath -Candidate $StammdatenPath -Root $dataRoot -MustExist -PathType Leaf
  $ProfilPath = Resolve-SafePath -Candidate $ProfilPath -Root $dataRoot -MustExist -PathType Leaf
  $AnforderungsmatrixPath = Resolve-SafePath -Candidate $AnforderungsmatrixPath -Root $script:WorkRoot -MustExist -PathType Leaf
  $resolvedFolder = Resolve-SafePath -Candidate $Ordner -Root $script:ApplicationsRoot -MustExist -PathType Container

  $readInputs = @($StammdatenPath, $ProfilPath, $AuftragPath, $AnforderungsmatrixPath)
  for ($left = 0; $left -lt $readInputs.Count; $left++) {
    for ($right = $left + 1; $right -lt $readInputs.Count; $right++) {
      if (Test-SamePath -Left $readInputs[$left] -Right $readInputs[$right]) {
        throw "Eingabedateien dürfen keine Aliase derselben Datei sein: $($readInputs[$left]) und $($readInputs[$right])"
      }
    }
  }
  if (-not [string]::IsNullOrWhiteSpace($BerichtPath)) {
    $script:ResolvedReportPath = Resolve-SafePath -Candidate $BerichtPath -Root $script:WorkRoot -ForWrite -PathType Leaf
    foreach ($inputPath in $readInputs) {
      if (Test-SamePath -Left $script:ResolvedReportPath -Right $inputPath) {
        throw "Berichtspfad darf keine Eingabedatei aliasieren: $inputPath"
      }
    }
  }
} catch {
  Write-Host "[FEHLER] Unsicherer Eingabe- oder Berichtspfad: $($_.Exception.Message)" -ForegroundColor Red
  exit 2
}

try {
  $internalFolder = Resolve-SafePath -Candidate (Join-Path -Path $resolvedFolder -ChildPath "Intern") -Root $resolvedFolder -PathType Container
  $shippingFolder = Resolve-SafePath -Candidate (Join-Path -Path $resolvedFolder -ChildPath "Versand") -Root $resolvedFolder -PathType Container
} catch {
  Write-Host "[FEHLER] Unsicherer Intern- oder Versandpfad: $($_.Exception.Message)" -ForegroundColor Red
  exit 2
}
$isStructuredPublication = (Test-Path -LiteralPath $internalFolder -PathType Container) -and (Test-Path -LiteralPath $shippingFolder -PathType Container)
$documentFolder = if ($isStructuredPublication) { $internalFolder } else { $resolvedFolder }
$emailFolder = if ($isStructuredPublication) { $shippingFolder } else { $resolvedFolder }
$profileText = Get-Content -LiteralPath $ProfilPath -Raw -Encoding UTF8
$fields = Get-MarkdownFields -Path $StammdatenPath
$auftrag = Get-Content -LiteralPath $AuftragPath -Raw -Encoding UTF8 | ConvertFrom-Json
$matrix = Get-Content -LiteralPath $AnforderungsmatrixPath -Raw -Encoding UTF8 | ConvertFrom-Json
try {
  $matrixSchema = Get-MatrixSchemaVersion -Matrix $matrix
} catch {
  Write-Host "[FEHLER] $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}
$auftragSchemaValue = Get-JsonProperty -Object $auftrag -Name "schemaVersion"
if ($auftragSchemaValue -isnot [int] -and $auftragSchemaValue -isnot [long]) {
  Write-Host "[FEHLER] Bewerbungsauftrag enthält keine ganzzahlige schemaVersion." -ForegroundColor Red
  exit 1
}
$auftragSchema = [int]$auftragSchemaValue
$documentMode = [string](Get-JsonProperty -Object $auftrag -Name "dokumentmodus")
$configuredScope = Get-JsonProperty -Object $auftrag -Name "dokumentumfang"
$expectedCv = $true
$expectedLetter = $true
$expectedEmail = $true
$cvKind = if ($documentMode -eq "anschreiben_mit_universalem_lebenslauf") { "universal_unveraendert" } else { "individuell" }
if ($auftragSchema -lt 1 -or $auftragSchema -gt 5) {
  Write-Host "[FEHLER] Bewerbungsauftrag verwendet keine unterstützte schemaVersion 1 bis 5." -ForegroundColor Red
  exit 1
}
if ($auftragSchema -ge 4) {
  if ($null -eq $configuredScope) {
    Write-Host "[FEHLER] Bewerbungsauftrag mit schemaVersion $auftragSchema enthält keinen dokumentumfang." -ForegroundColor Red
    exit 1
  }
  $cvKind = [string](Get-JsonProperty -Object $configuredScope -Name "lebenslauf")
  $letterValue = Get-JsonProperty -Object $configuredScope -Name "anschreiben"
  $emailValue = Get-JsonProperty -Object $configuredScope -Name "emailNachricht"
  if ($cvKind -notin @("individuell", "universal_unveraendert", "nicht_enthalten") -or
      $letterValue -isnot [bool] -or $emailValue -isnot [bool]) {
    Write-Host "[FEHLER] dokumentumfang enthält ungültige oder nicht typisierte Werte." -ForegroundColor Red
    exit 1
  }
  $expectedCv = $cvKind -ne "nicht_enthalten"
  $expectedLetter = [bool]$letterValue
  $expectedEmail = [bool]$emailValue
  if (-not ($expectedCv -or $expectedLetter -or $expectedEmail)) {
    Write-Host "[FEHLER] dokumentumfang wählt kein Dokument aus." -ForegroundColor Red
    exit 1
  }
}
$effectiveScope = [ordered]@{
  lebenslauf = $cvKind
  anschreiben = $expectedLetter
  emailNachricht = $expectedEmail
}

$letterCoverage = [ordered]@{
  applicable = ($matrixSchema -ge 5 -and $expectedLetter)
  status = if ($matrixSchema -ge 5 -and $expectedLetter) { 'ausstehend' } elseif ($matrixSchema -ge 5) { 'nicht_erforderlich' } else { 'legacy_oder_nicht_erforderlich' }
  argumente = @()
}
$externalSourceCoverage = [ordered]@{
  applicable = ($matrixSchema -ge 5)
  status = if ($matrixSchema -ge 5) { 'ausstehend' } else { 'legacy_oder_nicht_erforderlich' }
  sources = @()
}
$evidenceDisposition = [ordered]@{
  applicable = ($matrixSchema -ge 5)
  status = if ($matrixSchema -ge 5) { 'ausstehend' } else { 'legacy_oder_nicht_erforderlich' }
  used = @()
  omitted = @()
  unclassified = @()
  conflicts = @()
}
$languageQuality = [ordered]@{
  applicable = $expectedLetter
  status = if ($expectedLetter) { 'ausstehend' } else { 'nicht_erforderlich' }
  findings = @()
  metrics = [ordered]@{}
}

# Schema 4 bindet die Matrix unabhängig an die Stellenanzeige und die privaten
# Fachquellen. Ältere Matrixschemata bleiben bewusst lesbar, damit bestehende
# veröffentlichte Bewerbungen nicht nachträglich ihre Gültigkeit verlieren.
$evidenceCoverage = [ordered]@{
  applicable = ($matrixSchema -ge 4)
  matrixSchemaVersion = $matrixSchema
  status = if ($matrixSchema -ge 4) { 'ausstehend' } else { 'legacy_oder_nicht_erforderlich' }
  stellenbeschreibungSha256 = $null
  evidenzindexSha256 = $null
  explicitJobSignalLines = @()
  uncoveredJobSignalLines = @()
  sourceAnchors = @()
  profileEvidence = @()
}
$sourceAnchorById = @{}
$profileEvidenceById = @{}
$schema4ErrorStart = $errors.Count
if ($matrixSchema -ge 4) {
  $jobDescriptionPath = Join-Path -Path $documentFolder -ChildPath 'Stellenbeschreibung.md'
  try {
    $jobDescriptionPath = Resolve-SafePath -Candidate $jobDescriptionPath -Root $documentFolder -MustExist -PathType Leaf
    $jobText = Get-Content -LiteralPath $jobDescriptionPath -Raw -Encoding UTF8
    $jobLines = @([regex]::Split($jobText, '\r\n|\n'))
    $jobHash = (Get-FileHash -LiteralPath $jobDescriptionPath -Algorithm SHA256).Hash
    $evidenceCoverage.stellenbeschreibungSha256 = $jobHash
  } catch {
    Add-ErrorMessage "Schema-4-Matrix benötigt eine sicher lesbare Stellenbeschreibung.md: $($_.Exception.Message)"
    $jobText = ''
    $jobLines = @()
    $jobHash = ''
  }

  $jobCoverage = Get-JsonProperty -Object $matrix -Name 'stellenanzeigeAbdeckung'
  if ($null -eq $jobCoverage) {
    Add-ErrorMessage 'Schema-4-Anforderungsmatrix enthält keine stellenanzeigeAbdeckung.'
  } else {
    $storedJobHash = [string](Get-JsonProperty -Object $jobCoverage -Name 'sourceSha256')
    if ([string]::IsNullOrWhiteSpace($jobHash) -or $storedJobHash -ine $jobHash) {
      Add-ErrorMessage 'stellenanzeigeAbdeckung.sourceSha256 stimmt nicht mit der gespeicherten Stellenbeschreibung überein.'
    }
    $sourceRecords = @()
    foreach ($anchor in @((Get-JsonProperty -Object $jobCoverage -Name 'fundstellen') | Where-Object { $null -ne $_ })) {
      $anchorId = [string](Get-JsonProperty -Object $anchor -Name 'id')
      $from = Get-JsonProperty -Object $anchor -Name 'zeileVon'
      $to = Get-JsonProperty -Object $anchor -Name 'zeileBis'
      $quotedText = [string](Get-JsonProperty -Object $anchor -Name 'text')
      $classification = [string](Get-JsonProperty -Object $anchor -Name 'klassifikation')
      $reason = [string](Get-JsonProperty -Object $anchor -Name 'begruendung')
      $linkedRequirementIds = @((Get-JsonProperty -Object $anchor -Name 'anforderungIds') | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
      $recordValid = $true
      if (-not (Test-TechnicalReferenceId -Value $anchorId) -or $sourceAnchorById.ContainsKey($anchorId)) { Add-ErrorMessage "Stellen-Fundstelle besitzt eine leere oder doppelte ID: '$anchorId'."; $recordValid = $false }
      if (($from -isnot [int] -and $from -isnot [long]) -or ($to -isnot [int] -and $to -isnot [long])) { Add-ErrorMessage "Stellen-Fundstelle '$anchorId' benötigt ganzzahlige zeileVon und zeileBis."; $recordValid = $false }
      $actualRangeText = if ($recordValid) { Get-SourceRangeText -Lines $jobLines -From ([int]$from) -To ([int]$to) } else { $null }
      if ([string]::IsNullOrWhiteSpace($actualRangeText) -or (Get-NormalizedSourceText -Text $actualRangeText) -cne (Get-NormalizedSourceText -Text $quotedText)) { Add-ErrorMessage "Stellen-Fundstelle '$anchorId' stimmt nicht mit dem angegebenen Zeilenbereich überein."; $recordValid = $false }
      if ($classification -notin @('anforderung', 'aufgabe', 'nicht_anforderung')) { Add-ErrorMessage "Stellen-Fundstelle '$anchorId' hat eine ungültige klassifikation: $classification"; $recordValid = $false }
      if ($classification -eq 'nicht_anforderung' -and [string]::IsNullOrWhiteSpace($reason)) { Add-ErrorMessage "Nicht als Anforderung klassifizierte Fundstelle '$anchorId' benötigt eine begruendung."; $recordValid = $false }
      if ($classification -in @('anforderung', 'aufgabe') -and $linkedRequirementIds.Count -eq 0 -and [string]::IsNullOrWhiteSpace($reason)) { Add-ErrorMessage "Fundstelle '$anchorId' benötigt mindestens eine Anforderungs-ID oder eine begründete strategische Einordnung."; $recordValid = $false }
      if ($recordValid) { $sourceAnchorById[$anchorId] = $anchor }
      $sourceRecords += [ordered]@{ id=$anchorId; zeileVon=$from; zeileBis=$to; klassifikation=$classification; anforderungIds=@($linkedRequirementIds); valid=$recordValid }
    }
    if ($sourceRecords.Count -eq 0) { Add-ErrorMessage 'stellenanzeigeAbdeckung.fundstellen enthält keine prüfbaren Fundstellen.' }
    $signalLines = @(Get-ExplicitJobSignalLineNumbers -Lines $jobLines)
    $uncoveredSignals = @($signalLines | Where-Object {
      $signalLine = $_
      @($sourceRecords | Where-Object { $_.valid -and [int]$_.zeileVon -le $signalLine -and [int]$_.zeileBis -ge $signalLine }).Count -eq 0
    })
    foreach ($lineNumber in $uncoveredSignals) { Add-ErrorMessage "Explizites Stellenanforderungs- oder Aufgaben-Signal in Zeile $lineNumber ist nicht in stellenanzeigeAbdeckung erfasst." }
    $evidenceCoverage.explicitJobSignalLines = @($signalLines)
    $evidenceCoverage.uncoveredJobSignalLines = @($uncoveredSignals)
    $evidenceCoverage.sourceAnchors = @($sourceRecords)
  }

  if ([string]::IsNullOrWhiteSpace($EvidenzindexPath)) {
    $EvidenzindexPath = Join-Path -Path $script:WorkRoot -ChildPath 'Evidenzindex.json'
  }
  try {
    $EvidenzindexPath = Resolve-SafePath -Candidate $EvidenzindexPath -Root $script:WorkRoot -MustExist -PathType Leaf
    if (Test-SamePath -Left $EvidenzindexPath -Right $AnforderungsmatrixPath) { throw 'Evidenzindex darf nicht die Anforderungsmatrix selbst sein.' }
    $evidenceIndexText = Get-Content -LiteralPath $EvidenzindexPath -Raw -Encoding UTF8
    $evidenceIndex = $evidenceIndexText | ConvertFrom-Json
    $evidenceCoverage.evidenzindexSha256 = (Get-FileHash -LiteralPath $EvidenzindexPath -Algorithm SHA256).Hash
  } catch {
    Add-ErrorMessage "Schema-4-Matrix benötigt einen sicheren Evidenzindex.json: $($_.Exception.Message)"
    $evidenceIndex = $null
  }
  if ($null -ne $evidenceIndex) {
    try {
      $indexSchema = Get-EvidenceIndexSchemaVersion -Index $evidenceIndex
    } catch {
      Add-ErrorMessage $_.Exception.Message
      $indexSchema = 0
    }
    $allEvidence = @((Get-JsonProperty -Object $evidenceIndex -Name 'belege') | Where-Object { $null -ne $_ })
    $hasProfileEvidence = @($allEvidence | Where-Object { [string](Get-JsonProperty -Object $_ -Name 'quelle') -eq 'profil' }).Count -gt 0
    $hasDialogEvidence = @($allEvidence | Where-Object { [string](Get-JsonProperty -Object $_ -Name 'quelle') -eq 'auftrag_angabe' }).Count -gt 0
    $profileHash = (Get-FileHash -LiteralPath $ProfilPath -Algorithm SHA256).Hash
    if ($hasProfileEvidence -and [string](Get-JsonProperty -Object $evidenceIndex -Name 'profilSha256') -ine $profileHash) { Add-ErrorMessage 'Evidenzindex.profilSha256 stimmt nicht mit der fachlichen Profildatei überein.' }
    $orderHash = (Get-FileHash -LiteralPath $AuftragPath -Algorithm SHA256).Hash
    if ($hasDialogEvidence -and [string](Get-JsonProperty -Object $evidenceIndex -Name 'auftragSha256') -ine $orderHash) { Add-ErrorMessage 'Evidenzindex.auftragSha256 stimmt nicht mit dem Bewerbungsauftrag überein.' }
    $profileLines = @([regex]::Split($profileText, '\r\n|\n'))
    $dialogFactsById = @{}
    foreach ($fact in @((Get-JsonProperty -Object (Get-JsonProperty -Object $auftrag -Name 'dialog') -Name 'angaben') | Where-Object { $null -ne $_ })) {
      $factId = [string](Get-JsonProperty -Object $fact -Name 'id')
      if (-not [string]::IsNullOrWhiteSpace($factId)) { $dialogFactsById[$factId] = $fact }
    }
    $evidenceRecords = @()
    foreach ($evidence in $allEvidence) {
      $evidenceId = [string](Get-JsonProperty -Object $evidence -Name 'id')
      $source = [string](Get-JsonProperty -Object $evidence -Name 'quelle')
      $from = Get-JsonProperty -Object $evidence -Name 'zeileVon'
      $to = Get-JsonProperty -Object $evidence -Name 'zeileBis'
      $quotedText = [string](Get-JsonProperty -Object $evidence -Name 'text')
      $evidenceType = [string](Get-JsonProperty -Object $evidence -Name 'belegart')
      $factId = [string](Get-JsonProperty -Object $evidence -Name 'angabeId')
      $recordValid = $true
      if (-not (Test-TechnicalReferenceId -Value $evidenceId) -or $profileEvidenceById.ContainsKey($evidenceId)) { Add-ErrorMessage "Evidenzindex enthält eine leere oder doppelte Beleg-ID: '$evidenceId'."; $recordValid = $false }
      if ($source -notin @('profil', 'auftrag_angabe')) { Add-ErrorMessage "Evidenz '$evidenceId' verwendet eine nicht unterstützte Quelle: $source."; $recordValid = $false }
      if ($source -eq 'profil') {
        if (($from -isnot [int] -and $from -isnot [long]) -or ($to -isnot [int] -and $to -isnot [long])) { Add-ErrorMessage "Evidenz '$evidenceId' benötigt ganzzahlige zeileVon und zeileBis."; $recordValid = $false }
        $actualRangeText = if ($recordValid) { Get-SourceRangeText -Lines $profileLines -From ([int]$from) -To ([int]$to) } else { $null }
        if ([string]::IsNullOrWhiteSpace($actualRangeText) -or (Get-NormalizedSourceText -Text $actualRangeText) -cne (Get-NormalizedSourceText -Text $quotedText)) { Add-ErrorMessage "Evidenz '$evidenceId' stimmt nicht mit dem Profil-Zeilenbereich überein."; $recordValid = $false }
      } elseif ($source -eq 'auftrag_angabe') {
        if (-not $dialogFactsById.ContainsKey($factId)) { Add-ErrorMessage "Dialog-Evidenz '$evidenceId' verweist auf keine bestätigte Dialogangabe: $factId"; $recordValid = $false }
        else {
          $fact = $dialogFactsById[$factId]
          if ([string](Get-JsonProperty -Object $fact -Name 'wahrheitsstatus') -ne 'bestaetigt') { Add-ErrorMessage "Dialog-Evidenz '$evidenceId' verwendet keine bestätigte Dialogangabe: $factId"; $recordValid = $false }
          if ((Get-NormalizedSourceText -Text ([string](Get-JsonProperty -Object $fact -Name 'normalisierteAngabe'))) -cne (Get-NormalizedSourceText -Text $quotedText)) { Add-ErrorMessage "Dialog-Evidenz '$evidenceId' stimmt nicht mit der normalisierten Dialogangabe überein."; $recordValid = $false }
        }
      }
      if ($evidenceType -notin @('BERUFLICH BELEGT', 'ÜBERTRAGBAR', 'WEITERBILDUNG', 'PROJEKTPRAXIS', 'PRIVATE PRAXIS / HOME-LAB', 'GRUNDLAGEN / VERSTÄNDNIS', 'EINARBEITUNGSZIEL', 'NICHT BEHAUPTEN')) { Add-ErrorMessage "Evidenz '$evidenceId' enthält eine ungültige belegart: $evidenceType"; $recordValid = $false }
      if ($recordValid) { $profileEvidenceById[$evidenceId] = $evidence }
      $evidenceRecords += [ordered]@{ id=$evidenceId; quelle=$source; angabeId=$factId; zeileVon=$from; zeileBis=$to; belegart=$evidenceType; valid=$recordValid }
    }
    if ($evidenceRecords.Count -eq 0) { Add-ErrorMessage 'Evidenzindex.belege enthält keine prüfbaren Profilbelege.' }
    $evidenceCoverage.profileEvidence = @($evidenceRecords)
  }
}
$cvFiles = @(ConvertTo-SafeFileList -Files @(Get-ChildItem -LiteralPath $documentFolder -File -Filter "Lebenslauf - *.html") -Root $documentFolder -Context 'Lebenslaufdateien')
$letterFiles = @(ConvertTo-SafeFileList -Files @(Get-ChildItem -LiteralPath $documentFolder -File -Filter "Anschreiben - *.html") -Root $documentFolder -Context 'Anschreibendateien')
$emailFiles = @(ConvertTo-SafeFileList -Files @(Get-ChildItem -LiteralPath $emailFolder -File -Filter "Email-Nachricht--*.md") -Root $emailFolder -Context 'E-Mail-Dateien')
if (-not [string]::IsNullOrWhiteSpace($script:ResolvedReportPath)) {
  foreach ($candidateInput in @($cvFiles + $letterFiles + $emailFiles)) {
    if (Test-SamePath -Left $script:ResolvedReportPath -Right $candidateInput.FullName) {
      Write-Host "[FEHLER] Berichtspfad darf keine Kandidatendatei aliasieren: $($candidateInput.FullName)" -ForegroundColor Red
      exit 2
    }
  }
}
Add-DocumentCountResult -Files $cvFiles -Expected $expectedCv -Label "Lebenslauf"
Add-DocumentCountResult -Files $letterFiles -Expected $expectedLetter -Label "Anschreiben"
Add-DocumentCountResult -Files $emailFiles -Expected $expectedEmail -Label "E-Mail-Nachricht"

$cvHtml = if ($expectedCv -and $cvFiles.Count -eq 1) { Get-Content -LiteralPath $cvFiles[0].FullName -Raw -Encoding UTF8 } else { "" }
$letterHtml = if ($expectedLetter -and $letterFiles.Count -eq 1) { Get-Content -LiteralPath $letterFiles[0].FullName -Raw -Encoding UTF8 } else { "" }
$emailText = if ($expectedEmail -and $emailFiles.Count -eq 1) { Get-Content -LiteralPath $emailFiles[0].FullName -Raw -Encoding UTF8 } else { "" }
$cvText = Convert-HtmlToText -Html $cvHtml
$cvFirstPageText = Get-FirstHtmlPageText -Html $cvHtml
$letterText = Convert-HtmlToText -Html $letterHtml

$passfotoReport = [ordered]@{
  applicable = ($expectedCv -and $cvKind -eq 'individuell')
  status = if ($expectedCv -and $cvKind -eq 'individuell') { 'ausstehend' } else { 'nicht_erforderlich' }
  sourceExists = $false
  embeddedCount = 0
  sourceSha256 = $null
  embeddedSha256 = $null
}
if ($passfotoReport.applicable) {
  try {
    $passfotoSource = Get-PassfotoSourceState -DataRoot $dataRoot
    $passfotoValidation = Test-PassfotoEmbedding -Html $cvHtml -SourceState $passfotoSource
    $passfotoReport.sourceExists = [bool]$passfotoSource.Exists
    $passfotoReport.embeddedCount = [int]$passfotoValidation.EmbeddedCount
    $passfotoReport.sourceSha256 = $passfotoValidation.SourceSha256
    $passfotoReport.embeddedSha256 = $passfotoValidation.EmbeddedSha256
    if ($passfotoValidation.Valid) {
      $passfotoReport.status = if ($passfotoSource.Exists) { 'eingebettet' } else { 'nicht_vorhanden' }
      if ($passfotoSource.Exists) {
        Add-OkMessage "Passfoto.png ist als genau ein bytegleiches eingebettetes Bewerbungsfoto im individuellen Lebenslauf enthalten."
      } else {
        Add-OkMessage "Passfoto.png ist nicht vorhanden; der individuelle Lebenslauf enthält folgerichtig kein Bewerbungsfoto."
      }
    } else {
      $passfotoReport.status = 'fehler'
      Add-ErrorMessage $passfotoValidation.Error
    }
  } catch {
    $passfotoReport.status = 'fehler'
    Add-ErrorMessage "Passfoto-Prüfung fehlgeschlagen: $($_.Exception.Message)"
  }
}

Write-Host "Pruefe Bewerbungsinhalt: $resolvedFolder"

$fullName = if ($fields.Contains("Vollständiger Name")) { [string]$fields["Vollständiger Name"] } else { "" }
$fileNamePerson = if ($fields.Contains("Dateiname-Name")) { [string]$fields["Dateiname-Name"] } else { "" }
$firma = [string](Get-JsonProperty -Object $auftrag -Name "firma")
$firmaSlug = [string](Get-JsonProperty -Object $auftrag -Name "firmaSlug")
if ([string]::IsNullOrWhiteSpace($firmaSlug) -and -not [string]::IsNullOrWhiteSpace($firma)) {
  $firmaSlug = Convert-ToSlug -Value $firma
}
$rolle = [string](Get-JsonProperty -Object $auftrag -Name "rolle")
$pageStrategy = [string](Get-JsonProperty -Object $auftrag -Name "seitenstrategie")
$applicationLogistics = Get-JsonProperty -Object $auftrag -Name "bewerbungslogistik"
$displayOptions = Get-JsonProperty -Object $auftrag -Name "darstellungsoptionen"
$schoolMode = [string](Get-JsonProperty -Object $displayOptions -Name "schulbildungsmodus")
$profileLinksMode = [string](Get-JsonProperty -Object $displayOptions -Name "profillinksModus")
$profileLinksSelection = @((Get-JsonProperty -Object $displayOptions -Name "profillinksAuswahl"))
$applicationDecision = [string](Get-JsonProperty -Object $auftrag -Name "bewerbungsentscheidung")
$documentMode = [string](Get-JsonProperty -Object $auftrag -Name "dokumentmodus")
$universalCv = Get-JsonProperty -Object $auftrag -Name "universalLebenslauf"

if ($auftragSchema -lt 3 -and [string]::IsNullOrWhiteSpace($documentMode)) {
  $documentMode = "vollbewerbung"
}

if ($auftragSchema -ge 2) {
  if ($applicationDecision -notin @("bewerben", "nicht_bewerben")) {
    Add-ErrorMessage "Bewerbungsauftrag enthält keine endgültige Bewerbungsentscheidung. Erlaubt: bewerben oder nicht_bewerben."
  } elseif ($applicationDecision -eq "nicht_bewerben") {
    Add-ErrorMessage "Bewerbungsauftrag ist auf nicht_bewerben gesetzt und darf nicht finalisiert werden."
  } else {
    Add-OkMessage "Bewerbungsentscheidung ist ausdrücklich auf bewerben gesetzt."
  }
  if ($expectedCv) {
    if ($schoolMode -notin @("vollstaendig", "recruiter_kompakt")) {
      Add-ErrorMessage "Schulbildungsmodus ist nicht endgültig festgelegt. Erlaubt: vollstaendig oder recruiter_kompakt."
    }
    if ($profileLinksMode -notin @("alle", "rollenrelevant", "keine")) {
      Add-ErrorMessage "Profillinks-Modus ist nicht endgültig festgelegt. Erlaubt: alle, rollenrelevant oder keine."
    }
  } elseif ($auftragSchema -ge 4 -and ($schoolMode -ne "nicht_erforderlich" -or $profileLinksMode -ne "nicht_erforderlich")) {
    Add-ErrorMessage "Ohne ausgewählten Lebenslauf müssen CV-Darstellungsoptionen auf nicht_erforderlich stehen."
  }
} else {
  if ([string]::IsNullOrWhiteSpace($schoolMode)) { $schoolMode = "vollstaendig" }
  if ([string]::IsNullOrWhiteSpace($profileLinksMode)) { $profileLinksMode = "legacy_ungeprueft" }
}

if ($auftragSchema -ge 3) {
  $allowedModes = if ($auftragSchema -ge 4) { @("vollbewerbung", "anschreiben_mit_universalem_lebenslauf", "individuelle_auswahl") } else { @("vollbewerbung", "anschreiben_mit_universalem_lebenslauf") }
  if ($documentMode -notin $allowedModes) {
    Add-ErrorMessage "Dokumentmodus ist für das Auftragsschema ungültig."
  } else {
    Add-OkMessage "Dokumentmodus ist eindeutig festgelegt: $documentMode."
  }
}

if ($expectedCv) {
  $cvPageCount = [regex]::Matches($cvHtml, '(?is)<main\b[^>]*class\s*=\s*["''][^"'']*\bpage\b[^"'']*["'']').Count
  if ($pageStrategy -eq "eine_seite" -and $cvPageCount -eq 1) {
    Add-OkMessage "Seitenstrategie stimmt mit einem Lebenslauf-Seitencontainer überein."
  } elseif ($pageStrategy -eq "zwei_seiten" -and $cvPageCount -eq 2) {
    Add-OkMessage "Seitenstrategie stimmt mit zwei Lebenslauf-Seitencontainern überein."
  } elseif ($pageStrategy -notin @("eine_seite", "zwei_seiten")) {
    Add-ErrorMessage "Bewerbungsauftrag enthält keine final festgelegte Seitenstrategie. Erlaubt: eine_seite oder zwei_seiten."
  } else {
    Add-ErrorMessage "Seitenstrategie im Bewerbungsauftrag stimmt nicht mit den Lebenslauf-Seitencontainern überein."
  }
} elseif ($auftragSchema -ge 4 -and $pageStrategy -ne "nicht_erforderlich") {
  Add-ErrorMessage "Ohne ausgewählten Lebenslauf muss die Seitenstrategie nicht_erforderlich sein."
} else {
  Add-OkMessage "Lebenslauf-Seitenstrategie ist laut Dokumentumfang nicht erforderlich."
}

$selectedDocuments = @()
if ($expectedCv) { $selectedDocuments += [pscustomobject]@{ Name = "Lebenslauf"; Text = $cvText } }
if ($expectedLetter) { $selectedDocuments += [pscustomobject]@{ Name = "Anschreiben"; Text = $letterText } }
if ($expectedEmail) { $selectedDocuments += [pscustomobject]@{ Name = "E-Mail-Nachricht"; Text = $emailText } }
foreach ($document in $selectedDocuments) {
  if (Test-ContainsText -Haystack $document.Text -Needle $fullName) {
    Add-OkMessage "$($document.Name) enthält den Bewerbernamen."
  } else {
    Add-ErrorMessage "$($document.Name) enthält den Bewerbernamen aus den Stammdaten nicht."
  }
}

if ($expectedCv -and $cvFiles.Count -eq 1 -and $cvFiles[0].BaseName -ne "Lebenslauf - $fileNamePerson") {
  Add-ErrorMessage "Lebenslauf-Dateiname stimmt nicht mit Dateiname-Name aus den Stammdaten überein."
}
if ($expectedLetter -and $letterFiles.Count -eq 1 -and $letterFiles[0].BaseName -ne "Anschreiben - $fileNamePerson") {
  Add-ErrorMessage "Anschreiben-Dateiname stimmt nicht mit Dateiname-Name aus den Stammdaten überein."
}

if ($expectedCv -and $cvKind -eq "universal_unveraendert" -and $cvFiles.Count -eq 1) {
  $expectedUniversalHash = [string](Get-JsonProperty -Object $universalCv -Name "sourceHtmlSha256BeiAnlage")
  $expectedUniversalName = [string](Get-JsonProperty -Object $universalCv -Name "kandidatDatei")
  if ([string]::IsNullOrWhiteSpace($expectedUniversalHash) -or [string]::IsNullOrWhiteSpace($expectedUniversalName)) {
    Add-ErrorMessage "Der Anschreiben-Modus enthält keinen vollständigen Hashnachweis für den universellen Lebenslauf."
  } elseif ($cvFiles[0].Name -ne $expectedUniversalName) {
    Add-ErrorMessage "Der Kandidaten-Lebenslauf stimmt nicht mit dem im Auftrag eingefrorenen Universaldateinamen überein."
  } else {
    $actualUniversalHash = (Get-FileHash -LiteralPath $cvFiles[0].FullName -Algorithm SHA256).Hash
    if ($actualUniversalHash -eq $expectedUniversalHash) {
      Add-OkMessage "Universeller Lebenslauf wurde unverändert aus dem eingefrorenen Snapshot übernommen."
    } else {
      Add-ErrorMessage "Universeller Lebenslauf wurde für die konkrete Stelle verändert; Anschreiben-Modus verletzt."
    }
  }
}

if ($expectedLetter) {
  if (Test-ContainsText -Haystack $letterText -Needle $firma) {
    Add-OkMessage "Anschreiben enthält die Firma aus dem Bewerbungsauftrag."
  } else {
    Add-ErrorMessage "Anschreiben enthält die Firma aus dem Bewerbungsauftrag nicht."
  }
}
if ($expectedEmail -and $emailFiles.Count -eq 1) {
  $emailSubject = ($emailText -split "`r?`n", 2)[0].TrimStart([char]0xFEFF)
  if (Test-ContainsText -Haystack $emailSubject -Needle $rolle) {
    Add-OkMessage "E-Mail-Betreff enthält die Zielrolle."
  } else {
    Add-ErrorMessage "E-Mail-Betreff enthält die Zielrolle aus dem Bewerbungsauftrag nicht."
  }
  if (Test-ContainsText -Haystack $emailSubject -Needle $fullName) {
    Add-OkMessage "E-Mail-Betreff enthält den Bewerbernamen."
  } else {
    Add-ErrorMessage "E-Mail-Betreff enthält den Bewerbernamen aus den Stammdaten nicht."
  }
  if (Test-ContainsText -Haystack $emailText -Needle $firma) {
    Add-OkMessage "E-Mail-Nachricht enthält die Firma aus dem Bewerbungsauftrag."
  } else {
    Add-ErrorMessage "E-Mail-Nachricht enthält die Firma aus dem Bewerbungsauftrag nicht."
  }
  if (-not [string]::IsNullOrWhiteSpace($firmaSlug) -and $emailFiles[0].Name -cne "Email-Nachricht--$firmaSlug.md") {
    Add-ErrorMessage "E-Mail-Dateiname stimmt nicht mit dem Firmen-Slug aus dem Bewerbungsauftrag überein."
  }
}
$roleDocuments = @()
if ($expectedLetter) { $roleDocuments += [pscustomobject]@{ Name = "Anschreiben"; Text = $letterText } }
if ($expectedCv -and $cvKind -eq "individuell") {
  $roleDocuments = @([pscustomobject]@{ Name = "Lebenslauf"; Text = $cvText }) + $roleDocuments
} elseif ($expectedCv) {
  Add-OkMessage "Zielrollenprüfung im universellen Lebenslauf ist im Anschreiben-Modus bewusst ausgenommen."
}
foreach ($document in $roleDocuments) {
  if (Test-ContainsText -Haystack $document.Text -Needle $rolle) {
    Add-OkMessage "$($document.Name) enthält die Zielrolle."
  } else {
    Add-WarningMessage "$($document.Name) enthält die Zielrolle nicht in der im Auftrag gespeicherten Form."
  }
}

$periodMatches = [regex]::Matches($profileText, '(?im)\b(?:0[1-9]|1[0-2])/\d{4}\s*[-–—]\s*(?:(?:0[1-9]|1[0-2])/\d{4}|fortlaufend)\b')
$periods = @($periodMatches | ForEach-Object { Normalize-Text -Text $_.Value } | Sort-Object -Unique)
$schoolSectionMatch = [regex]::Match($profileText, '(?ims)^##\s+Schulbildung\s*$\s*(?<body>.*?)(?=^##\s+|\z)')
$schoolPeriods = if ($schoolSectionMatch.Success) {
  @([regex]::Matches($schoolSectionMatch.Groups["body"].Value, '(?im)\b(?:0[1-9]|1[0-2])/\d{4}\s*[-–—]\s*(?:(?:0[1-9]|1[0-2])/\d{4}|fortlaufend)\b') | ForEach-Object { Normalize-Text -Text $_.Value } | Sort-Object -Unique)
} else {
  @()
}
$requiredPeriods = if (-not $expectedCv) {
  @()
} elseif ($schoolMode -eq "recruiter_kompakt") {
  @($periods | Where-Object { $_ -notin $schoolPeriods })
} else {
  @($periods)
}
$compactedSchoolPeriods = if ($schoolMode -eq "recruiter_kompakt") { @($schoolPeriods) } else { @() }
$normalizedCv = Normalize-Text -Text $cvText
foreach ($period in $requiredPeriods) {
  if ($normalizedCv.Contains($period)) {
    Add-OkMessage "Formaler Zeitraum im Lebenslauf gefunden: $period"
  } else {
    Add-ErrorMessage "Formaler Zeitraum aus dem Profil fehlt im Lebenslauf: $period"
  }
}
if ($expectedCv -and $schoolMode -eq "recruiter_kompakt") {
  if ($cvText -match '(?i)Schulbildung|Schule|Hochschulzugangsberechtigung') {
    Add-OkMessage "Recruiter-kompakter Schulbildungsmodus ist gewählt und eine zusammengefasste Schulbildungsangabe bleibt sichtbar."
  } else {
    Add-ErrorMessage "Recruiter-kompakter Schulbildungsmodus erfordert weiterhin eine sichtbare zusammengefasste Schulbildungsangabe."
  }
}

$requirements = @((Get-JsonProperty -Object $matrix -Name "requirements"))
$requirementById = @{}
$weightPoints = @{ kritisch = 4.0; hoch = 3.0; mittel = 2.0; niedrig = 1.0 }
$statusFactors = @{ erfuellt = 1.0; teilweise = 0.5; nicht_belegt = 0.0; unklar = 0.0 }
$fitMaximum = 0.0
$fitAchieved = 0.0
$criticalGaps = New-Object System.Collections.Generic.List[string]
$weightedRequirements = @()
if ($requirements.Count -eq 0 -or $null -eq $requirements[0]) {
  Add-ErrorMessage "Anforderungsmatrix enthält keine Anforderungen."
} else {
  $allowedStatuses = @("erfuellt", "teilweise", "nicht_belegt", "unklar", "nicht_relevant")
  $allowedCategories = @("fachlich", "erfahrung", "formal", "arbeitsweise", "logistik")
  foreach ($requirement in $requirements) {
    $requirementId = [string](Get-JsonProperty -Object $requirement -Name "id")
    $description = [string](Get-JsonProperty -Object $requirement -Name "anforderung")
    $kind = [string](Get-JsonProperty -Object $requirement -Name "typ")
    $status = [string](Get-JsonProperty -Object $requirement -Name "status")
    $handling = [string](Get-JsonProperty -Object $requirement -Name "behandlung")
    $weight = [string](Get-JsonProperty -Object $requirement -Name "gewichtung")
    $category = [string](Get-JsonProperty -Object $requirement -Name "kategorie")
    $evidenceType = [string](Get-JsonProperty -Object $requirement -Name "belegart")
    $evidence = [string](Get-JsonProperty -Object $requirement -Name "beleg")
    if ([string]::IsNullOrWhiteSpace($requirementId) -or [string]::IsNullOrWhiteSpace($description) -or [string]::IsNullOrWhiteSpace($kind)) {
      Add-ErrorMessage "Anforderungsmatrix enthält einen Eintrag ohne ID, Anforderung oder Typ."
      continue
    }
    if ($requirementById.ContainsKey($requirementId)) {
      Add-ErrorMessage "Anforderungsmatrix enthält eine doppelte ID: $requirementId"
      continue
    }
    $requirementById[$requirementId] = $requirement
    if ($kind -notin @("muss", "kann")) {
      Add-ErrorMessage "Anforderung '$description' enthält einen ungültigen Typ: $kind"
    }
    if ($status -notin $allowedStatuses) {
      Add-ErrorMessage "Ungültiger Matrixstatus bei '$description': $status"
      continue
    }
    if ([string]::IsNullOrWhiteSpace($weight)) {
      $weight = if ($kind -eq "muss") { "hoch" } else { "niedrig" }
      if ($matrixSchema -ge 2) {
        Add-ErrorMessage "Anforderung '$description' enthält keine Gewichtung."
      }
    } elseif (-not $weightPoints.ContainsKey($weight)) {
      Add-ErrorMessage "Anforderung '$description' enthält eine ungültige Gewichtung: $weight"
      continue
    }
    if ($matrixSchema -ge 2 -and [string]::IsNullOrWhiteSpace($category)) {
      Add-ErrorMessage "Anforderung '$description' enthält keine Kategorie."
    } elseif ($matrixSchema -ge 2 -and $category -notin $allowedCategories) {
      Add-ErrorMessage "Anforderung '$description' enthält eine ungültige Kategorie: $category"
    }
    if ($matrixSchema -ge 2 -and $status -in @("erfuellt", "teilweise") -and
        ([string]::IsNullOrWhiteSpace($evidenceType) -or [string]::IsNullOrWhiteSpace($evidence))) {
      Add-ErrorMessage "Belegte oder teilweise belegte Anforderung benötigt Belegart und konkreten Beleg: $description"
    }
    if ($matrixSchema -ge 4) {
      $sourceReferenceIds = @((Get-JsonProperty -Object $requirement -Name 'stellenFundstellen') | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
      $evidenceReferenceIds = @((Get-JsonProperty -Object $requirement -Name 'belegRefIds') | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
      if ($sourceReferenceIds.Count -eq 0) {
        Add-ErrorMessage "Schema-4-Anforderung '$description' benötigt mindestens eine stellenFundstellen-Referenz."
      }
      foreach ($sourceReferenceId in $sourceReferenceIds) {
        if (-not $sourceAnchorById.ContainsKey($sourceReferenceId)) {
          Add-ErrorMessage "Anforderung '$description' verweist auf eine unbekannte oder ungültige Stellen-Fundstelle: $sourceReferenceId"
        }
      }
      if ($status -in @('erfuellt', 'teilweise')) {
        if ($evidenceReferenceIds.Count -eq 0) { Add-ErrorMessage "Belegte oder teilweise belegte Schema-4-Anforderung '$description' benötigt belegRefIds." }
        foreach ($evidenceReferenceId in $evidenceReferenceIds) {
          if (-not $profileEvidenceById.ContainsKey($evidenceReferenceId)) {
            Add-ErrorMessage "Anforderung '$description' verweist auf eine unbekannte oder ungültige Profilevidenz: $evidenceReferenceId"
            continue
          }
          $indexedEvidenceType = [string](Get-JsonProperty -Object $profileEvidenceById[$evidenceReferenceId] -Name 'belegart')
          if ($indexedEvidenceType -eq 'NICHT BEHAUPTEN') { Add-ErrorMessage "Anforderung '$description' darf NICHT-BEHAUPTEN-Evidenz nicht als Beleg verwenden." }
          elseif ($indexedEvidenceType -ne $evidenceType) { Add-ErrorMessage "Anforderung '$description' verwendet Belegart '$evidenceType', die referenzierte Evidenz '$evidenceReferenceId' ist jedoch '$indexedEvidenceType'." }
        }
      } elseif ($evidenceReferenceIds.Count -gt 0) {
        Add-ErrorMessage "Nicht direkt belegte Schema-4-Anforderung '$description' darf keine belegRefIds als Direktbeleg führen. Verwende gegebenenfalls eine Transferbrücke."
      }
    }
    if (($status -ne "erfuellt") -and [string]::IsNullOrWhiteSpace($handling)) {
      Add-ErrorMessage "Nicht vollständig erfüllte Anforderung hat keine dokumentierte Behandlung: $description"
    }
    if (($kind -eq "muss") -and ($status -in @("teilweise", "nicht_belegt", "unklar"))) {
      Add-WarningMessage "Muss-Anforderung ist nicht vollständig belegt: $description ($status)"
    } else {
      Add-OkMessage "Anforderung ist klassifiziert: $description ($status)"
    }

    if ($status -ne "nicht_relevant" -and $weightPoints.ContainsKey($weight)) {
      $points = [double]$weightPoints[$weight]
      $factor = if ($statusFactors.ContainsKey($status)) { [double]$statusFactors[$status] } else { 0.0 }
      $fitMaximum += $points
      $fitAchieved += ($points * $factor)
      if ($weight -eq "kritisch" -and $status -ne "erfuellt") {
        $criticalGaps.Add($description) | Out-Null
      }
      $weightedRequirements += [ordered]@{
        id = [string](Get-JsonProperty -Object $requirement -Name "id")
        anforderung = $description
        typ = $kind
        kategorie = $category
        gewichtung = $weight
        status = $status
        beitrag = [math]::Round(($points * $factor), 2)
        maximum = $points
      }
    }
  }
}

$fitPercent = if ($fitMaximum -gt 0) { [math]::Round(($fitAchieved / $fitMaximum) * 100.0, 1) } else { 0.0 }
$fitClassification = if ($criticalGaps.Count -eq 0 -and $fitPercent -ge 80) {
  "stark"
} elseif ($criticalGaps.Count -le 1 -and $fitPercent -ge 55) {
  "vertretbar_mit_risiken"
} else {
  "stretch"
}
$fitAssessment = [ordered]@{
  scorePercent = $fitPercent
  classification = $fitClassification
  achievedPoints = [math]::Round($fitAchieved, 2)
  maximumPoints = [math]::Round($fitMaximum, 2)
  criticalGaps = @($criticalGaps)
  requirements = $weightedRequirements
}
if ($fitClassification -eq "stretch") {
  Add-WarningMessage "Gewichtete Eignungsbewertung: Stretch-Bewerbung ($fitPercent %, kritische Lücken: $($criticalGaps.Count))."
} else {
  Add-OkMessage "Gewichtete Eignungsbewertung: $fitClassification ($fitPercent %)."
}

$recruiterCoverage = [ordered]@{
  applicable = ($matrixSchema -ge 3 -and ($expectedCv -or $expectedLetter))
  matrixSchemaVersion = $matrixSchema
  status = if ($matrixSchema -ge 3 -and ($expectedCv -or $expectedLetter)) { 'ausstehend' } else { 'legacy_oder_nicht_erforderlich' }
  kernbotschaft = $null
  profilSubstanz = $null
  requiredPriorityRequirementIds = @()
  configuredPriorityRequirementIds = @()
  firstPageRequirementIds = @()
  highlights = @()
  transferBridges = @()
  omissions = @()
}

if ($recruiterCoverage.applicable) {
  $recruiterErrorStart = $errors.Count
  $strategy = Get-JsonProperty -Object $matrix -Name 'recruiterStrategie'
  if ($null -eq $strategy) {
    Add-ErrorMessage "Schema-$matrixSchema-Anforderungsmatrix enthält keine recruiterStrategie."
  } else {
    $kernbotschaft = [string](Get-JsonProperty -Object $strategy -Name 'kernbotschaft')
    $profileSubstance = [string](Get-JsonProperty -Object $strategy -Name 'profilSubstanz')
    $profileSubstanceReason = [string](Get-JsonProperty -Object $strategy -Name 'profilSubstanzBegruendung')
    $priorityIds = @((Get-JsonProperty -Object $strategy -Name 'prioritaetsAnforderungen') | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $highlights = @((Get-JsonProperty -Object $strategy -Name 'profilHighlights') | Where-Object { $null -ne $_ })
    $transferBridges = @((Get-JsonProperty -Object $strategy -Name 'transferbruecken') | Where-Object { $null -ne $_ })
    $omissions = @((Get-JsonProperty -Object $strategy -Name 'auslassungen') | Where-Object { $null -ne $_ })
    $recruiterCoverage.kernbotschaft = $kernbotschaft
    $recruiterCoverage.profilSubstanz = $profileSubstance
    $recruiterCoverage.configuredPriorityRequirementIds = @($priorityIds)

    if ([string]::IsNullOrWhiteSpace($kernbotschaft) -or $kernbotschaft.Trim().Length -lt 20) {
      Add-ErrorMessage 'recruiterStrategie.kernbotschaft muss eine konkrete Positionierung mit mindestens 20 Zeichen enthalten.'
    }
    if ($profileSubstance -notin @('ausreichend', 'schmal')) {
      Add-ErrorMessage 'recruiterStrategie.profilSubstanz muss ausreichend oder schmal sein.'
    }
    if ([string]::IsNullOrWhiteSpace($profileSubstanceReason)) {
      Add-ErrorMessage 'recruiterStrategie.profilSubstanzBegruendung fehlt.'
    }

    $requiredPriorityIds = @($requirements | Where-Object {
      $null -ne $_ -and
      [string](Get-JsonProperty -Object $_ -Name 'gewichtung') -in @('kritisch', 'hoch') -and
      [string](Get-JsonProperty -Object $_ -Name 'kategorie') -in @('fachlich', 'erfahrung') -and
      [string](Get-JsonProperty -Object $_ -Name 'status') -ne 'nicht_relevant'
    } | ForEach-Object { [string](Get-JsonProperty -Object $_ -Name 'id') })
    $recruiterCoverage.requiredPriorityRequirementIds = @($requiredPriorityIds)
    if (@($priorityIds | Sort-Object -Unique).Count -ne $priorityIds.Count) {
      Add-ErrorMessage 'recruiterStrategie.prioritaetsAnforderungen enthält doppelte IDs.'
    }
    foreach ($priorityId in $priorityIds) {
      if (-not $requirementById.ContainsKey($priorityId)) {
        Add-ErrorMessage "recruiterStrategie verweist auf eine unbekannte Prioritätsanforderung: $priorityId"
      }
    }
    foreach ($requiredPriorityId in $requiredPriorityIds) {
      if ($requiredPriorityId -notin $priorityIds) {
        Add-ErrorMessage "Kritische oder hoch gewichtete fachliche Anforderung fehlt in prioritaetsAnforderungen: $requiredPriorityId"
      }
    }

    $documentTexts = @{ lebenslauf = $cvText; anschreiben = $letterText; email_nachricht = $emailText }
    $selectedDocumentNames = @()
    if ($expectedCv) { $selectedDocumentNames += 'lebenslauf' }
    if ($expectedLetter) { $selectedDocumentNames += 'anschreiben' }
    if ($expectedEmail) { $selectedDocumentNames += 'email_nachricht' }
    $allowedEvidenceTypes = @('BERUFLICH BELEGT', 'ÜBERTRAGBAR', 'WEITERBILDUNG', 'PROJEKTPRAXIS', 'PRIVATE PRAXIS / HOME-LAB', 'GRUNDLAGEN / VERSTÄNDNIS', 'EINARBEITUNGSZIEL')
    $highlightIds = @{}
    $highlightRecords = @()

    foreach ($highlight in $highlights) {
      $highlightId = [string](Get-JsonProperty -Object $highlight -Name 'id')
      $linkedRequirementIds = @((Get-JsonProperty -Object $highlight -Name 'anforderungIds') | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
      $evidenceType = [string](Get-JsonProperty -Object $highlight -Name 'belegart')
      $relevance = [string](Get-JsonProperty -Object $highlight -Name 'relevanz')
      $targetDocument = [string](Get-JsonProperty -Object $highlight -Name 'zielDokument')
      $placement = [string](Get-JsonProperty -Object $highlight -Name 'platzierung')
      $anchors = @((Get-JsonProperty -Object $highlight -Name 'sichtbareAnker') | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
      $evidenceReferenceIds = @((Get-JsonProperty -Object $highlight -Name 'belegRefIds') | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
      $recordValid = $true
      if ([string]::IsNullOrWhiteSpace($highlightId) -or $highlightIds.ContainsKey($highlightId)) { Add-ErrorMessage "profilHighlights enthält eine leere oder doppelte ID: $highlightId"; $recordValid = $false } else { $highlightIds[$highlightId] = $highlight }
      if ($linkedRequirementIds.Count -eq 0) { Add-ErrorMessage "Profilhighlight '$highlightId' enthält keine anforderungIds."; $recordValid = $false }
      foreach ($linkedRequirementId in $linkedRequirementIds) {
        if (-not $requirementById.ContainsKey($linkedRequirementId)) { Add-ErrorMessage "Profilhighlight '$highlightId' verweist auf eine unbekannte Anforderung: $linkedRequirementId"; $recordValid = $false }
        elseif ([string](Get-JsonProperty -Object $requirementById[$linkedRequirementId] -Name 'status') -in @('nicht_belegt', 'unklar')) { Add-ErrorMessage "Profilhighlight '$highlightId' darf eine nicht belegte oder unklare Anforderung nicht als Direktbeleg führen: $linkedRequirementId"; $recordValid = $false }
      }
      if ($evidenceType -notin $allowedEvidenceTypes) { Add-ErrorMessage "Profilhighlight '$highlightId' enthält eine ungültige Belegart: $evidenceType"; $recordValid = $false }
      if ($matrixSchema -ge 4) {
        if ($evidenceReferenceIds.Count -eq 0) { Add-ErrorMessage "Schema-4-Profilhighlight '$highlightId' benötigt belegRefIds."; $recordValid = $false }
        foreach ($evidenceReferenceId in $evidenceReferenceIds) {
          if (-not $profileEvidenceById.ContainsKey($evidenceReferenceId)) { Add-ErrorMessage "Profilhighlight '$highlightId' verweist auf eine unbekannte oder ungültige Profilevidenz: $evidenceReferenceId"; $recordValid = $false; continue }
          $indexedEvidenceType = [string](Get-JsonProperty -Object $profileEvidenceById[$evidenceReferenceId] -Name 'belegart')
          if ($indexedEvidenceType -eq 'NICHT BEHAUPTEN' -or $indexedEvidenceType -eq 'EINARBEITUNGSZIEL') { Add-ErrorMessage "Profilhighlight '$highlightId' darf '$indexedEvidenceType' nicht als sichtbaren Direktbeleg verwenden."; $recordValid = $false }
          elseif ($indexedEvidenceType -ne $evidenceType) { Add-ErrorMessage "Profilhighlight '$highlightId' verwendet Belegart '$evidenceType', Evidenz '$evidenceReferenceId' ist jedoch '$indexedEvidenceType'."; $recordValid = $false }
        }
      }
      if ($relevance -notin @('hoch', 'mittel', 'niedrig')) { Add-ErrorMessage "Profilhighlight '$highlightId' enthält eine ungültige Relevanz: $relevance"; $recordValid = $false }
      if ($targetDocument -notin $selectedDocumentNames) { Add-ErrorMessage "Profilhighlight '$highlightId' verweist auf ein nicht ausgewähltes Zieldokument: $targetDocument"; $recordValid = $false }
      if ($placement -notin @('seite_1', 'beliebig') -or ($placement -eq 'seite_1' -and $targetDocument -ne 'lebenslauf')) { Add-ErrorMessage "Profilhighlight '$highlightId' enthält eine ungültige Platzierung: $placement"; $recordValid = $false }
      if ($anchors.Count -eq 0) { Add-ErrorMessage "Profilhighlight '$highlightId' enthält keine sichtbaren Textanker."; $recordValid = $false }
      $targetText = if ($targetDocument -eq 'lebenslauf' -and $placement -eq 'seite_1') { $cvFirstPageText } elseif ($documentTexts.ContainsKey($targetDocument)) { [string]$documentTexts[$targetDocument] } else { '' }
      $missingAnchors = @($anchors | Where-Object { -not (Test-ContainsText -Haystack $targetText -Needle $_) })
      if ($missingAnchors.Count -gt 0) { Add-ErrorMessage "Profilhighlight '$highlightId' fehlt im vorgesehenen Dokument oder auf der vorgesehenen Seite: $($missingAnchors -join ', ')"; $recordValid = $false }
      $highlightRecords += [ordered]@{ id=$highlightId; anforderungIds=@($linkedRequirementIds); belegart=$evidenceType; belegRefIds=@($evidenceReferenceIds); relevanz=$relevance; zielDokument=$targetDocument; platzierung=$placement; sichtbareAnker=@($anchors); missingAnchors=@($missingAnchors); valid=$recordValid }
    }

    $omissionRecords = @()
    foreach ($omission in $omissions) {
      $topic = [string](Get-JsonProperty -Object $omission -Name 'thema'); $reason = [string](Get-JsonProperty -Object $omission -Name 'begruendung'); $requirementId = [string](Get-JsonProperty -Object $omission -Name 'anforderungId'); $recordValid = $true
      if ([string]::IsNullOrWhiteSpace($topic) -or [string]::IsNullOrWhiteSpace($reason)) { Add-ErrorMessage 'Jede recruiterStrategie.auslassung benötigt thema und begruendung.'; $recordValid = $false }
      if (-not [string]::IsNullOrWhiteSpace($requirementId) -and -not $requirementById.ContainsKey($requirementId)) { Add-ErrorMessage "Auslassung verweist auf eine unbekannte Anforderung: $requirementId"; $recordValid = $false }
      $omissionRecords += [ordered]@{ thema=$topic; begruendung=$reason; anforderungId=$requirementId; valid=$recordValid }
    }

    $transferRecords = @()
    foreach ($bridge in $transferBridges) {
      $requirementId = [string](Get-JsonProperty -Object $bridge -Name 'anforderungId'); $targetTechnology = [string](Get-JsonProperty -Object $bridge -Name 'zieltechnologie'); $basisIds = @((Get-JsonProperty -Object $bridge -Name 'basisHighlightIds') | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }); $wordingLevel = [string](Get-JsonProperty -Object $bridge -Name 'formulierungsebene'); $targetDocument = [string](Get-JsonProperty -Object $bridge -Name 'zielDokument'); $placement = [string](Get-JsonProperty -Object $bridge -Name 'platzierung'); $anchors = @((Get-JsonProperty -Object $bridge -Name 'sichtbareAnker') | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }); $recordValid = $true
      if (-not $requirementById.ContainsKey($requirementId)) { Add-ErrorMessage "Transferbrücke verweist auf eine unbekannte Anforderung: $requirementId"; $recordValid = $false }
      elseif ([string](Get-JsonProperty -Object $requirementById[$requirementId] -Name 'status') -notin @('teilweise', 'nicht_belegt', 'unklar')) { Add-ErrorMessage "Transferbrücke ist nur für teilweise, nicht belegte oder unklare Anforderungen zulässig: $requirementId"; $recordValid = $false }
      if ([string]::IsNullOrWhiteSpace($targetTechnology)) { Add-ErrorMessage "Transferbrücke '$requirementId' enthält keine zieltechnologie."; $recordValid = $false }
      if ($basisIds.Count -eq 0) { Add-ErrorMessage "Transferbrücke '$requirementId' enthält keine basisHighlightIds."; $recordValid = $false }
      foreach ($basisId in $basisIds) { if (-not $highlightIds.ContainsKey($basisId)) { Add-ErrorMessage "Transferbrücke '$requirementId' verweist auf ein unbekanntes Profilhighlight: $basisId"; $recordValid=$false } elseif ([string](Get-JsonProperty -Object $highlightIds[$basisId] -Name 'belegart') -eq 'EINARBEITUNGSZIEL') { Add-ErrorMessage "Transferbrücke '$requirementId' darf kein bloßes Einarbeitungsziel als Grundlage verwenden: $basisId"; $recordValid=$false } }
      if ($wordingLevel -notin @('ÜBERTRAGBAR', 'GRUNDLAGEN / VERSTÄNDNIS', 'EINARBEITUNGSZIEL')) { Add-ErrorMessage "Transferbrücke '$requirementId' enthält eine ungültige formulierungsebene: $wordingLevel"; $recordValid=$false }
      if ($targetDocument -notin $selectedDocumentNames) { Add-ErrorMessage "Transferbrücke '$requirementId' verweist auf ein nicht ausgewähltes Zieldokument: $targetDocument"; $recordValid=$false }
      if ($placement -notin @('seite_1','beliebig') -or ($placement -eq 'seite_1' -and $targetDocument -ne 'lebenslauf')) { Add-ErrorMessage "Transferbrücke '$requirementId' enthält eine ungültige Platzierung: $placement"; $recordValid=$false }
      if ($anchors.Count -eq 0) { Add-ErrorMessage "Transferbrücke '$requirementId' enthält keine sichtbaren Textanker."; $recordValid=$false }
      $targetText = if ($targetDocument -eq 'lebenslauf' -and $placement -eq 'seite_1') { $cvFirstPageText } elseif ($documentTexts.ContainsKey($targetDocument)) { [string]$documentTexts[$targetDocument] } else { '' }
      $missingAnchors = @($anchors | Where-Object { -not (Test-ContainsText -Haystack $targetText -Needle $_) })
      if ($missingAnchors.Count -gt 0) { Add-ErrorMessage "Transferbrücke '$requirementId' fehlt im vorgesehenen Dokument oder auf der vorgesehenen Seite: $($missingAnchors -join ', ')"; $recordValid=$false }
      $transferRecords += [ordered]@{ anforderungId=$requirementId; zieltechnologie=$targetTechnology; basisHighlightIds=@($basisIds); formulierungsebene=$wordingLevel; zielDokument=$targetDocument; platzierung=$placement; sichtbareAnker=@($anchors); missingAnchors=@($missingAnchors); valid=$recordValid }
    }

    foreach ($priorityId in $priorityIds) {
      if (-not $requirementById.ContainsKey($priorityId)) { continue }
      $priorityStatus = [string](Get-JsonProperty -Object $requirementById[$priorityId] -Name 'status')
      $directMatches = @($highlightRecords | Where-Object { $_.valid -and $priorityId -in @($_.anforderungIds) })
      $bridgeMatches = @($transferRecords | Where-Object { $_.valid -and $_.anforderungId -eq $priorityId })
      $omissionMatches = @($omissionRecords | Where-Object { $_.valid -and $_.anforderungId -eq $priorityId })
      if ($priorityStatus -in @('erfuellt','teilweise') -and $directMatches.Count -eq 0) { Add-ErrorMessage "Prioritätsanforderung '$priorityId' besitzt keinen sichtbaren belegten Profilhighlight." }
      elseif ($priorityStatus -in @('nicht_belegt','unklar') -and $bridgeMatches.Count -eq 0 -and $omissionMatches.Count -eq 0) { Add-ErrorMessage "Nicht belegte Prioritätsanforderung '$priorityId' benötigt eine wahre Transferbrücke oder begründete Auslassung." }
    }

    if ($expectedCv -and $cvKind -eq 'individuell') {
      $validCvHighlights = @($highlightRecords | Where-Object { $_.valid -and $_.zielDokument -eq 'lebenslauf' -and $_.relevanz -in @('hoch','mittel') })
      if ($profileSubstance -eq 'ausreichend' -and $validCvHighlights.Count -lt 2) { Add-ErrorMessage 'Ein individuelles Profil mit ausreichender Substanz benötigt mindestens zwei sichtbare personenspezifische Profilhighlights im Lebenslauf.' }
      if ($profileSubstance -eq 'schmal' -and $omissionRecords.Count -eq 0) { Add-ErrorMessage 'Ein als schmal eingestuftes Profil benötigt mindestens eine begründete Auslassung beziehungsweise Substanzgrenze.' }
      $scannablePriorityIds = @($priorityIds | Where-Object { $candidateId=$_; @($highlightRecords | Where-Object { $_.valid -and $candidateId -in @($_.anforderungIds) }).Count -gt 0 -or @($transferRecords | Where-Object { $_.valid -and $_.anforderungId -eq $candidateId }).Count -gt 0 } | Select-Object -First 3)
      $recruiterCoverage.firstPageRequirementIds = @($scannablePriorityIds)
      foreach ($scanId in $scannablePriorityIds) {
        $pageOneDirect = @($highlightRecords | Where-Object { $_.valid -and $_.zielDokument -eq 'lebenslauf' -and $_.platzierung -eq 'seite_1' -and $scanId -in @($_.anforderungIds) })
        $pageOneBridge = @($transferRecords | Where-Object { $_.valid -and $_.zielDokument -eq 'lebenslauf' -and $_.platzierung -eq 'seite_1' -and $_.anforderungId -eq $scanId })
        if ($pageOneDirect.Count -eq 0 -and $pageOneBridge.Count -eq 0) { Add-ErrorMessage "Wichtiges Recruiter-Signal ist nicht auf der ersten Lebenslaufseite verankert: $scanId" }
      }
    }
    $recruiterCoverage.highlights=@($highlightRecords); $recruiterCoverage.transferBridges=@($transferRecords); $recruiterCoverage.omissions=@($omissionRecords)
    if ($errors.Count -eq $recruiterErrorStart) { $recruiterCoverage.status='ok'; Add-OkMessage "Recruiter-Abdeckung ist vollständig: $($highlightRecords.Count) Profilhighlights, $($transferRecords.Count) Transferbrücken." } else { $recruiterCoverage.status='fehler' }
  }
}

# Phase 3: externe Quellen und maschinenlesbare Anschreibenstrategie.
$analysePath = Join-Path -Path $documentFolder -ChildPath 'Analyse.md'
$analyseText = if (Test-Path -LiteralPath $analysePath -PathType Leaf) { Get-Content -LiteralPath $analysePath -Raw -Encoding UTF8 } else { '' }
$externalSources = @((Get-JsonProperty -Object $matrix -Name 'externeQuellen') | Where-Object { $null -ne $_ })
$externalById = @{}
$externalSourceRecords = @()
$referencedExternalIds = [System.Collections.Generic.HashSet[string]]::new()
if ($matrixSchema -ge 5) {
  if ($null -eq $matrix.PSObject.Properties['externeQuellen']) {
    Add-ErrorMessage 'Schema-5-Anforderungsmatrix enthält keine externe Quellenliste externeQuellen.'
  }
  foreach ($source in $externalSources) {
    $sourceId = [string](Get-JsonProperty -Object $source -Name 'id')
    $sourceType = [string](Get-JsonProperty -Object $source -Name 'typ')
    $title = [string](Get-JsonProperty -Object $source -Name 'titel')
    $publisher = [string](Get-JsonProperty -Object $source -Name 'herausgeber')
    $url = [string](Get-JsonProperty -Object $source -Name 'url')
    $accessed = [string](Get-JsonProperty -Object $source -Name 'abgerufenAmUtc')
    $sourceDate = [string](Get-JsonProperty -Object $source -Name 'quellenstand')
    $claim = [string](Get-JsonProperty -Object $source -Name 'aussage')
    $usages = @((Get-JsonProperty -Object $source -Name 'verwendungen') | Where-Object { $null -ne $_ })
    $recordValid = $true
    if (-not (Test-TechnicalReferenceId -Value $sourceId) -or $externalById.ContainsKey($sourceId)) { Add-ErrorMessage "Externe Quelle besitzt eine leere oder doppelte ID: '$sourceId'."; $recordValid = $false } else { $externalById[$sourceId] = $source }
    if ($sourceType -notin @('unternehmen', 'gehalt')) { Add-ErrorMessage "Externe Quelle '$sourceId' verwendet einen ungültigen Typ: $sourceType"; $recordValid = $false }
    if ([string]::IsNullOrWhiteSpace($title) -or [string]::IsNullOrWhiteSpace($publisher) -or [string]::IsNullOrWhiteSpace($claim)) { Add-ErrorMessage "Externe Quelle '$sourceId' benötigt Titel, Herausgeber und Aussage."; $recordValid = $false }
    if ($url -notmatch '^https?://[^\s]+$') { Add-ErrorMessage "Externe Quelle '$sourceId' benötigt eine absolute HTTP(S)-URL."; $recordValid = $false }
    $accessDate = [datetime]::MinValue
    if (-not [datetime]::TryParse($accessed, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$accessDate) -or $accessDate.ToUniversalTime() -gt [datetime]::UtcNow.AddMinutes(5)) { Add-ErrorMessage "Externe Quelle '$sourceId' benötigt einen gültigen, nicht zukünftigen Abrufzeitpunkt."; $recordValid = $false }
    if (-not [string]::IsNullOrWhiteSpace($sourceDate)) {
      $parsedSourceDate = [datetime]::MinValue
      if (-not [datetime]::TryParse($sourceDate, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AllowWhiteSpaces, [ref]$parsedSourceDate) -or $parsedSourceDate.Date -gt [datetime]::UtcNow.Date.AddDays(1)) { Add-ErrorMessage "Externe Quelle '$sourceId' enthält keinen gültigen Quellenstand."; $recordValid = $false }
    }
    if ($usages.Count -eq 0) { Add-ErrorMessage "Externe Quelle '$sourceId' enthält keine Verwendung."; $recordValid = $false }
    $usageRecords = @()
    foreach ($usage in $usages) {
      $purpose = [string](Get-JsonProperty -Object $usage -Name 'zweck')
      $targetDocument = [string](Get-JsonProperty -Object $usage -Name 'zielDokument')
      $anchors = @((Get-JsonProperty -Object $usage -Name 'sichtbareAnker') | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
      $usageValid = $true
      if ($purpose -notin @('arbeitgeberbezug', 'gehaltsschaetzung', 'sonstiges')) { Add-ErrorMessage "Externe Quelle '$sourceId' enthält einen ungültigen Verwendungszweck: $purpose"; $usageValid = $false }
      if ($targetDocument -notin @('anschreiben', 'analyse')) { Add-ErrorMessage "Externe Quelle '$sourceId' verweist auf ein ungültiges Zieldokument: $targetDocument"; $usageValid = $false }
      if ($targetDocument -eq 'anschreiben' -and -not $expectedLetter) { Add-ErrorMessage "Externe Quelle '$sourceId' verweist auf ein nicht ausgewähltes Anschreiben."; $usageValid = $false }
      if ($anchors.Count -eq 0) { Add-ErrorMessage "Externe Quelle '$sourceId' benötigt sichtbare Textanker."; $usageValid = $false }
      $targetText = if ($targetDocument -eq 'anschreiben') { $letterText } else { $analyseText }
      $missing = @($anchors | Where-Object { -not (Test-ContainsText -Haystack $targetText -Needle $_) })
      if ($missing.Count -gt 0) { Add-ErrorMessage "Externe Quelle '$sourceId' fehlt im Zieldokument: $($missing -join ', ')"; $usageValid = $false }
      if ($purpose -eq 'gehaltsschaetzung' -and $sourceType -ne 'gehalt') { Add-ErrorMessage "Gehaltsverwendung '$sourceId' benötigt eine Quelle vom Typ gehalt."; $usageValid = $false }
      $usageRecords += [ordered]@{ zweck=$purpose; zielDokument=$targetDocument; sichtbareAnker=@($anchors); fehlendeAnker=@($missing); valid=$usageValid }
      $null = $referencedExternalIds.Add($sourceId)
    }
    $externalSourceRecords += [ordered]@{ id=$sourceId; typ=$sourceType; url=$url; verwendungen=@($usageRecords); valid=$recordValid -and (@($usageRecords | Where-Object { -not $_.valid }).Count -eq 0) }
  }
  $externalSourceCoverage.sources = @($externalSourceRecords)
  $externalSourceCoverage.status = if ($errors.Count -eq $schema4ErrorStart) { 'ok' } else { 'fehler' }
  $applicationLogistics = Get-JsonProperty -Object $auftrag -Name 'bewerbungslogistik'
  $salaryLogic = [string](Get-JsonProperty -Object $applicationLogistics -Name 'gehaltslogik')
  $automaticSalary = $salaryLogic -match '(?i)(automatisch|schätz|marktüblich|benchmark)'
  if ($automaticSalary -and @($externalSourceRecords | Where-Object { $_.valid -and $_.typ -eq 'gehalt' }).Count -eq 0) { Add-ErrorMessage 'Eine automatische Gehaltsschätzung benötigt mindestens eine gültige externe Gehaltsquelle.' }
  $letterStrategy = Get-JsonProperty -Object $matrix -Name 'anschreibenStrategie'
  if ($expectedLetter) {
    if ($null -eq $letterStrategy) { Add-ErrorMessage 'Schema-5-Anforderungsmatrix enthält keine anschreibenStrategie.' }
    else {
      $letterStatus = [string](Get-JsonProperty -Object $letterStrategy -Name 'status')
      $arguments = @((Get-JsonProperty -Object $letterStrategy -Name 'argumente') | Where-Object { $null -ne $_ })
      $substance = [string](Get-JsonProperty -Object $strategy -Name 'profilSubstanz')
      $argumentLimitValid = ($arguments.Count -ge 2 -and $arguments.Count -le 4) -or ($substance -eq 'schmal' -and $arguments.Count -eq 1)
      if ($letterStatus -ne 'final') { Add-ErrorMessage 'anschreibenStrategie.status muss bei ausgewähltem Anschreiben final sein.' }
      if (-not $argumentLimitValid) { Add-ErrorMessage 'anschreibenStrategie benötigt zwei bis vier Argumente; bei schmalem Profil ist genau eines zulässig.' }
      $argumentRecords = @()
      $argumentIdsSeen = [System.Collections.Generic.HashSet[string]]::new()
      foreach ($argument in $arguments) {
        $argumentId = [string](Get-JsonProperty -Object $argument -Name 'id')
        $requirementIds = @((Get-JsonProperty -Object $argument -Name 'anforderungIds') | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $evidenceIds = @((Get-JsonProperty -Object $argument -Name 'belegRefIds') | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $jobAnchorIds = @((Get-JsonProperty -Object $argument -Name 'stellenFundstellen') | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $sourceIds = @((Get-JsonProperty -Object $argument -Name 'externeQuellenIds') | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $employerRelation = [string](Get-JsonProperty -Object $argument -Name 'arbeitgeberbezug')
        $benefit = [string](Get-JsonProperty -Object $argument -Name 'nutzenargument')
        $anchors = @((Get-JsonProperty -Object $argument -Name 'sichtbareAnker') | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $recordValid = $true
        if (-not (Test-TechnicalReferenceId -Value $argumentId) -or -not $argumentIdsSeen.Add($argumentId)) { Add-ErrorMessage "Anschreibenargument besitzt eine leere, ungültige oder doppelte ID: '$argumentId'."; $recordValid = $false }
        if ($requirementIds.Count -eq 0 -or $evidenceIds.Count -eq 0) { Add-ErrorMessage "Anschreibenargument '$argumentId' benötigt Anforderungs- und Evidenz-IDs."; $recordValid = $false }
        foreach ($requirementId in $requirementIds) {
          if (-not $requirementById.ContainsKey($requirementId)) { Add-ErrorMessage "Anschreibenargument '$argumentId' verweist auf unbekannte Anforderung: $requirementId"; $recordValid = $false }
          elseif ([string](Get-JsonProperty -Object $requirementById[$requirementId] -Name 'status') -in @('nicht_belegt','unklar')) { Add-ErrorMessage "Anschreibenargument '$argumentId' darf keine unbelegte Anforderung als Direktargument führen: $requirementId"; $recordValid = $false }
        }
        foreach ($evidenceId in $evidenceIds) {
          if (-not $profileEvidenceById.ContainsKey($evidenceId)) { Add-ErrorMessage "Anschreibenargument '$argumentId' verweist auf unbekannte Profilevidenz: $evidenceId"; $recordValid = $false }
          else {
            $evidenceType = [string](Get-JsonProperty -Object $profileEvidenceById[$evidenceId] -Name 'belegart')
            if ($evidenceType -in @('NICHT BEHAUPTEN','EINARBEITUNGSZIEL')) { Add-ErrorMessage "Anschreibenargument '$argumentId' darf Evidenzart '$evidenceType' nicht direkt verwenden."; $recordValid = $false }
            $evidenceLinkedToRequirement = @($requirementIds | Where-Object { $req = $requirementById[$_]; [string]$evidenceId -in @((Get-JsonProperty -Object $req -Name 'belegRefIds')) }).Count -gt 0
            $evidenceLinkedToHighlight = @($highlights | Where-Object { $highlightRequirementIds = @((Get-JsonProperty -Object $_ -Name 'anforderungIds') | ForEach-Object { [string]$_ }); $evidenceLinkedToRequirement -or ($_.PSObject.Properties['belegRefIds'] -and [string]$evidenceId -in @((Get-JsonProperty -Object $_ -Name 'belegRefIds')) -and @($highlightRequirementIds | Where-Object { $_ -in $requirementIds }).Count -gt 0) }).Count -gt 0
            if (-not $evidenceLinkedToRequirement -and -not $evidenceLinkedToHighlight) { Add-ErrorMessage "Anschreibenargument '$argumentId' verwendet Evidenz '$evidenceId' ohne Bezug zu seiner Anforderung oder einem passenden Profilhighlight."; $recordValid = $false }
          }
        }
        foreach ($jobAnchorId in $jobAnchorIds) { if (-not $sourceAnchorById.ContainsKey($jobAnchorId)) { Add-ErrorMessage "Anschreibenargument '$argumentId' verweist auf unbekannte Stellen-Fundstelle: $jobAnchorId"; $recordValid = $false } }
        foreach ($sourceId in $sourceIds) { if (-not $externalById.ContainsKey($sourceId) -or [string](Get-JsonProperty -Object $externalById[$sourceId] -Name 'typ') -ne 'unternehmen') { Add-ErrorMessage "Anschreibenargument '$argumentId' verweist auf keine gültige Unternehmensquelle: $sourceId"; $recordValid = $false } }
        if ($jobAnchorIds.Count -eq 0 -and $sourceIds.Count -eq 0) { Add-ErrorMessage "Anschreibenargument '$argumentId' benötigt Stellen- oder Unternehmensbezug."; $recordValid = $false }
        if ($employerRelation.Trim().Length -lt 20 -or $benefit.Trim().Length -lt 20) { Add-ErrorMessage "Anschreibenargument '$argumentId' benötigt konkreten Arbeitgeberbezug und Nutzen."; $recordValid = $false }
        if ($anchors.Count -eq 0) { Add-ErrorMessage "Anschreibenargument '$argumentId' benötigt sichtbare Textanker."; $recordValid = $false }
        $missingAnchors = @($anchors | Where-Object { -not (Test-ContainsText -Haystack $letterText -Needle $_) })
        if ($missingAnchors.Count -gt 0) { Add-ErrorMessage "Anschreibenargument '$argumentId' fehlt im Anschreiben: $($missingAnchors -join ', ')"; $recordValid = $false }
        $argumentRecords += [ordered]@{ id=$argumentId; anforderungIds=@($requirementIds); belegRefIds=@($evidenceIds); stellenFundstellen=@($jobAnchorIds); externeQuellenIds=@($sourceIds); sichtbareAnker=@($anchors); fehlendeAnker=@($missingAnchors); valid=$recordValid }
      }
      $letterCoverage.argumente = @($argumentRecords)
    }
  } elseif ($matrixSchema -ge 5) {
    $letterStatus = if ($null -eq $letterStrategy) { '' } else { [string](Get-JsonProperty -Object $letterStrategy -Name 'status') }
    $argumentCount = if ($null -eq $letterStrategy) { 0 } else { @((Get-JsonProperty -Object $letterStrategy -Name 'argumente') | Where-Object { $null -ne $_ }).Count }
    if ($letterStatus -ne 'nicht_erforderlich' -or $argumentCount -ne 0) { Add-ErrorMessage 'Anschreibenstrategie muss ohne ausgewähltes Anschreiben nicht_erforderlich und leer sein.' }
  }
  $letterCoverage.status = if ($errors.Count -eq $schema4ErrorStart) { 'ok' } else { 'fehler' }
}

# Vollständige Evidenzdisposition: jede Index-ID muss verwendet oder begründet ausgelassen werden.
if ($matrixSchema -ge 5 -and $null -ne $evidenceIndex) {
  $usedEvidence = [System.Collections.Generic.HashSet[string]]::new()
  foreach ($requirement in @($requirements)) { foreach ($id in @((Get-JsonProperty -Object $requirement -Name 'belegRefIds'))) { if (-not [string]::IsNullOrWhiteSpace([string]$id)) { $null = $usedEvidence.Add([string]$id) } } }
  foreach ($highlight in @($highlights)) { foreach ($id in @((Get-JsonProperty -Object $highlight -Name 'belegRefIds'))) { if (-not [string]::IsNullOrWhiteSpace([string]$id)) { $null = $usedEvidence.Add([string]$id) } } }
  $letterStrategyForEvidence = Get-JsonProperty -Object $matrix -Name 'anschreibenStrategie'
  foreach ($argument in @((Get-JsonProperty -Object $letterStrategyForEvidence -Name 'argumente'))) { foreach ($id in @((Get-JsonProperty -Object $argument -Name 'belegRefIds'))) { if (-not [string]::IsNullOrWhiteSpace([string]$id)) { $null = $usedEvidence.Add([string]$id) } } }
  $strategyForDisposition = Get-JsonProperty -Object $matrix -Name 'recruiterStrategie'
  $omissionItems = @((Get-JsonProperty -Object $strategyForDisposition -Name 'auslassungen') | Where-Object { $null -ne $_ })
  $omittedEvidence = [System.Collections.Generic.HashSet[string]]::new()
  foreach ($omission in $omissionItems) {
    foreach ($idValue in @((Get-JsonProperty -Object $omission -Name 'belegRefIds'))) {
      $id = [string]$idValue
      if ([string]::IsNullOrWhiteSpace($id)) { continue }
      if (-not $profileEvidenceById.ContainsKey($id)) { Add-ErrorMessage "Auslassung verweist auf unbekannte Profilevidenz: $id"; continue }
      if (-not $omittedEvidence.Add($id)) { Add-ErrorMessage "Profilevidenz wird mehrfach als Auslassung geführt: $id" }
    }
  }
  $usedRecords = @($usedEvidence | ForEach-Object { [string]$_ })
  $omittedRecords = @($omittedEvidence | ForEach-Object { [string]$_ })
  $conflicts = @($usedRecords | Where-Object { $_ -in $omittedRecords })
  foreach ($id in $conflicts) { Add-ErrorMessage "Profilevidenz ist zugleich verwendet und ausgelassen: $id" }
  $allIds = @($profileEvidenceById.Keys)
  $unclassified = @($allIds | Where-Object { $_ -notin $usedRecords -and $_ -notin $omittedRecords })
  foreach ($id in $unclassified) { Add-ErrorMessage "Profilevidenz bleibt ohne Verwendung oder begründete Auslassung: $id" }
  $evidenceDisposition.used = @($usedRecords)
  $evidenceDisposition.omitted = @($omittedRecords)
  $evidenceDisposition.unclassified = @($unclassified)
  $evidenceDisposition.conflicts = @($conflicts)
  $evidenceDisposition.status = if ($unclassified.Count -eq 0 -and $conflicts.Count -eq 0) { 'ok' } else { 'fehler' }
} elseif ($matrixSchema -ge 5) {
  $evidenceDisposition.status = 'fehler'
}

# Konservative Sprachwarnungen, ohne automatische Textänderung.
if ($expectedLetter) {
  $findings = [System.Collections.Generic.List[object]]::new()
  $floskelPatterns = @(
    '(?i)hiermit bewerbe ich mich',
    '(?i)mit großem interesse habe ich',
    '(?i)ich bin davon überzeugt',
    '(?i)über eine einladung zum persönlichen gespräch freue ich mich'
  )
  foreach ($pattern in $floskelPatterns) { foreach ($match in [regex]::Matches($letterText, $pattern)) { $findings.Add([ordered]@{ code='floskel'; dokument='anschreiben'; text=$match.Value; count=1 }) | Out-Null; Add-WarningMessage "Anschreiben enthält eine mögliche Floskel: $($match.Value)" } }
  $sentences = @([regex]::Split($letterText, '(?<=[.!?])\s+') | ForEach-Object { $_.Trim() } | Where-Object { @(ConvertTo-ContractTokens $_).Count -ge 6 })
  $sentenceGroups = @($sentences | Group-Object { Normalize-Text $_ } | Where-Object { $_.Count -gt 1 })
  foreach ($group in $sentenceGroups) { $findings.Add([ordered]@{ code='wiederholter_satz'; dokument='anschreiben'; text=$group.Name; count=$group.Count }) | Out-Null; Add-WarningMessage "Anschreiben wiederholt einen Satz: $($group.Name)" }
  $startGroups = @($sentences | Group-Object { ([string]((ConvertTo-ContractTokens $_) | Select-Object -First 1)) } | Where-Object { $_.Count -ge 3 -and -not [string]::IsNullOrWhiteSpace($_.Name) })
  foreach ($group in $startGroups) { $findings.Add([ordered]@{ code='wiederholter_satzanfang'; dokument='anschreiben'; text=$group.Name; count=$group.Count }) | Out-Null; Add-WarningMessage "Anschreiben beginnt mehrere Sätze gleich: $($group.Name)" }
  foreach ($sentence in $sentences) { if (@(ConvertTo-ContractTokens $sentence).Count -gt 35) { $findings.Add([ordered]@{ code='langer_satz'; dokument='anschreiben'; text=$sentence.Substring(0, [math]::Min(180, $sentence.Length)); count=1 }) | Out-Null; Add-WarningMessage 'Anschreiben enthält einen ungewöhnlich langen Satz.' } }
  $letterTokens = @(ConvertTo-ContractTokens $letterText)
  $letterNgrams = @{}
  for ($i = 0; $i -le $letterTokens.Count - 8; $i++) { $ngram = $letterTokens[$i..($i + 7)] -join ' '; if (-not $letterNgrams.ContainsKey($ngram)) { $letterNgrams[$ngram] = 0 }; $letterNgrams[$ngram]++ }
  foreach ($entry in $letterNgrams.GetEnumerator() | Where-Object { $_.Value -gt 1 }) { $findings.Add([ordered]@{ code='wiederholte_textfolge'; dokument='anschreiben'; text=$entry.Key; count=$entry.Value }) | Out-Null; Add-WarningMessage 'Anschreiben wiederholt eine längere Textfolge.' }
  $otherDocuments = @([pscustomobject]@{ Name='lebenslauf'; Text=$cvText }, [pscustomobject]@{ Name='email_nachricht'; Text=$emailText })
  foreach ($other in $otherDocuments) {
    if ([string]::IsNullOrWhiteSpace($other.Text)) { continue }
    $otherSentences = @([regex]::Split($other.Text, '(?<=[.!?])\s+') | ForEach-Object { $_.Trim() } | Where-Object { @(ConvertTo-ContractTokens $_).Count -ge 8 })
    foreach ($sentence in $sentences) { $normalizedSentence = Normalize-Text $sentence; if ($otherSentences | Where-Object { (Normalize-Text $_) -eq $normalizedSentence }) { $findings.Add([ordered]@{ code='dokumentwiederholung'; dokument='anschreiben'; text=$sentence; count=1; vergleich=$other.Name }) | Out-Null; Add-WarningMessage "Anschreiben wiederholt einen längeren Satz aus $($other.Name)." } }
    $otherTokens = @(ConvertTo-ContractTokens $other.Text)
    $otherNgrams = [System.Collections.Generic.HashSet[string]]::new()
    for ($i = 0; $i -le $otherTokens.Count - 8; $i++) { $null = $otherNgrams.Add(($otherTokens[$i..($i + 7)] -join ' ')) }
    foreach ($entry in $letterNgrams.GetEnumerator() | Where-Object { $_.Key -in $otherNgrams }) { $findings.Add([ordered]@{ code='dokument_textwiederholung'; dokument='anschreiben'; text=$entry.Key; count=1; vergleich=$other.Name }) | Out-Null; Add-WarningMessage "Anschreiben wiederholt eine längere Textfolge aus $($other.Name)." }
  }
  $languageQuality.findings = @($findings)
  $languageQuality.metrics = [ordered]@{ satzAnzahl=$sentences.Count; wortAnzahl=$letterTokens.Count; floskelAnzahl=@($findings | Where-Object { $_.code -eq 'floskel' }).Count; wiederholungsAnzahl=@($findings | Where-Object { $_.code -like '*wiederhol*' }).Count }
  $languageQuality.status = if ($findings.Count -gt 0) { 'warnung' } else { 'ok' }
}

$fitScorePattern = '(?im)(?:Eignung|Passung|gewichtete\s+(?:Eignungsbewertung|Anforderungsmatrix))[^\r\n]{0,100}?(?<score>\d+(?:[\.,]\d+)?)\s*(?:%|Prozent)|(?<scoreBefore>\d+(?:[\.,]\d+)?)\s*(?:%|Prozent)[^\r\n]{0,70}?(?:Eignung|Passung)'
foreach ($scoreDocumentName in @("Analyse.md", "Qualitaetscheck.md")) {
  $scoreDocumentPath = Join-Path -Path $documentFolder -ChildPath $scoreDocumentName
  if (-not (Test-Path -LiteralPath $scoreDocumentPath -PathType Leaf)) { continue }
  try {
    $scoreDocumentPath = Resolve-SafePath -Candidate $scoreDocumentPath -Root $documentFolder -MustExist -PathType Leaf
  } catch {
    Add-ErrorMessage "$scoreDocumentName liegt nicht sicher im Dokumentenordner: $($_.Exception.Message)"
    continue
  }
  $scoreDocumentText = Get-Content -LiteralPath $scoreDocumentPath -Raw -Encoding UTF8
  foreach ($scoreMatch in [regex]::Matches($scoreDocumentText, $fitScorePattern)) {
    $scoreText = if ($scoreMatch.Groups["score"].Success) { $scoreMatch.Groups["score"].Value } else { $scoreMatch.Groups["scoreBefore"].Value }
    $documentScore = 0.0
    if ([double]::TryParse($scoreText.Replace(',', '.'), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$documentScore)) {
      if ([math]::Abs($documentScore - $fitPercent) -gt 0.11) {
        Add-ErrorMessage "$scoreDocumentName nennt eine Eignungskennzahl von $scoreText Prozent, berechnet wurden $fitPercent Prozent."
      } else {
        Add-OkMessage "$scoreDocumentName verwendet die berechnete Eignungskennzahl von $fitPercent Prozent."
      }
    }
  }
}

if ($matrixSchema -ge 4) {
  $evidenceCoverage.status = if ($errors.Count -eq $schema4ErrorStart) { 'ok' } else { 'fehler' }
  if ($evidenceCoverage.status -eq 'ok') {
    Add-OkMessage "Schema-4-Beweiskette ist vollständig: $($evidenceCoverage.sourceAnchors.Count) Stellen-Fundstellen und $($evidenceCoverage.profileEvidence.Count) Profilevidenzen."
  }
}

function Get-EffectiveLogisticsValue {
  param([string]$ApplicationProperty, [string]$MasterField)
  $applicationValue = [string](Get-JsonProperty -Object $applicationLogistics -Name $ApplicationProperty)
  if (-not [string]::IsNullOrWhiteSpace($applicationValue) -and $applicationValue -notmatch '^(?i:nicht festgelegt|offen|noch offen|unbekannt)$') {
    return $applicationValue
  }
  if ($fields.Contains($MasterField)) {
    return [string]$fields[$MasterField]
  }
  return ""
}

$selectedCombinedText = ($selectedDocuments | ForEach-Object { $_.Text }) -join " "
$availability = Get-EffectiveLogisticsValue -ApplicationProperty "verfuegbarkeit" -MasterField "Verfügbarkeit"
if (-not [string]::IsNullOrWhiteSpace($availability)) {
  if (Test-ContainsText -Haystack $selectedCombinedText -Needle $availability) {
    Add-OkMessage "Verfügbarkeit ist konsistent sichtbar."
  } else {
    Add-WarningMessage "Verfügbarkeit aus den Stammdaten ist in den ausgewählten Unterlagen nicht sichtbar."
  }
}

$employmentType = Get-EffectiveLogisticsValue -ApplicationProperty "stellenart" -MasterField "Gewünschte Stellenart"
if (-not [string]::IsNullOrWhiteSpace($employmentType)) {
  if ($employmentType -notmatch '(?i)^\s*(\[|nicht festgelegt|offen|unbekannt)') {
    if (Test-ContainsText -Haystack $selectedCombinedText -Needle $employmentType) {
      Add-OkMessage "Gewünschte Stellenart ist in den Unterlagen berücksichtigt."
    } else {
      Add-WarningMessage "Gewünschte Stellenart ist in den ausgewählten Unterlagen nicht erkennbar."
    }
  }
}

$profileFieldNames = @("GitHub", "Portfolio", "LinkedIn", "Xing")
$availableProfileLinks = [ordered]@{}
foreach ($profileFieldName in $profileFieldNames) {
  if ($fields.Contains($profileFieldName)) {
    $profileValue = [string]$fields[$profileFieldName]
    if (-not [string]::IsNullOrWhiteSpace($profileValue) -and $profileValue -notmatch '^(?i:nicht angegeben|nicht festgelegt|offen|unbekannt)$') {
      $availableProfileLinks[$profileFieldName] = $profileValue
    }
  }
}
if ($expectedCv -and $auftragSchema -ge 2 -and $profileLinksMode -in @("alle", "rollenrelevant", "keine")) {
  $selectedNames = @($profileLinksSelection | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  if ($profileLinksMode -eq "alle") {
    $selectedNames = @($availableProfileLinks.Keys)
  } elseif ($profileLinksMode -eq "keine" -and $selectedNames.Count -gt 0) {
    Add-ErrorMessage "Profillinks-Modus 'keine' darf keine profillinksAuswahl enthalten."
  }
  foreach ($selectedName in $selectedNames) {
    if (-not $availableProfileLinks.Contains($selectedName)) {
      Add-ErrorMessage "Ausgewählter Profillink ist in den Stammdaten nicht gepflegt: $selectedName"
      continue
    }
    if (-not (Test-ContainsText -Haystack $cvText -Needle ([string]$availableProfileLinks[$selectedName]))) {
      Add-ErrorMessage "Ausgewählter Profillink fehlt im Lebenslauf: $selectedName"
    }
  }
  foreach ($profileName in $availableProfileLinks.Keys) {
    $linkIsVisible = Test-ContainsText -Haystack $cvText -Needle ([string]$availableProfileLinks[$profileName])
    if ($linkIsVisible -and $profileName -notin $selectedNames) {
      Add-ErrorMessage "Nicht ausgewählter Profillink ist im Lebenslauf sichtbar: $profileName"
    }
  }
  Add-OkMessage "Rollenabhängige Profillink-Regel wurde geprüft: $profileLinksMode."
}

$defensivePatterns = @(
  '(?i)\bnicht belegt\b',
  '(?i)\bnoch keine (?:Berufs-?|Praxis-?)?erfahrung\b',
  '(?i)\bkeine Erfahrung\b',
  '(?i)ohne daraus .*Berufserfahrung abzuleiten',
  '(?i)ich erfülle .* nicht'
)
foreach ($pattern in $defensivePatterns) {
  if ($expectedLetter -and $letterText -match $pattern) {
    Add-WarningMessage "Anschreiben enthält eine potenziell defensive Metaformulierung: $($Matches[0])"
  }
}

Write-JsonReport -Path $BerichtPath -Periods $periods -RequiredPeriods $requiredPeriods -CompactSchoolPeriods $compactedSchoolPeriods -FitAssessment $fitAssessment -SchoolMode $schoolMode -ProfileLinksMode $profileLinksMode -DocumentMode $documentMode -DocumentScope $effectiveScope -Passfoto $passfotoReport -RecruiterCoverage $recruiterCoverage -EvidenceCoverage $evidenceCoverage -LetterCoverage $letterCoverage -ExternalSourceCoverage $externalSourceCoverage -EvidenceDisposition $evidenceDisposition -LanguageQuality $languageQuality

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
