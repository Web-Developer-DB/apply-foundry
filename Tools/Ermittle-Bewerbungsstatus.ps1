#requires -Version 7.6
#requires -PSEdition Core

[CmdletBinding()]
param(
  [string]$Arbeitsordner,

  [switch]$AlsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/OrderPaths.psm1") -Force
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/Platform.psm1") -Force

function Stop-Status {
  param([string]$Message, [int]$Code = 1)
  Write-Host "[FEHLER] $Message" -ForegroundColor Red
  exit $Code
}

function Get-JsonProperty {
  param([object]$Object, [string]$Name)
  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

function Resolve-ApplicationWorkFolder {
  param(
    [Parameter(Mandatory)][string]$Path,
    [string]$ApplicationsRoot
  )

  $full = [System.IO.Path]::GetFullPath($Path).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
  )
  $workFilesFolder = [System.IO.Path]::GetDirectoryName($full)
  $companyFolder = if ([string]::IsNullOrWhiteSpace($workFilesFolder)) { $null } else { [System.IO.Path]::GetDirectoryName($workFilesFolder) }
  $derivedApplicationsRoot = if ([string]::IsNullOrWhiteSpace($companyFolder)) { $null } else { [System.IO.Path]::GetDirectoryName($companyFolder) }
  $privateFolder = if ([string]::IsNullOrWhiteSpace($derivedApplicationsRoot)) { $null } else { [System.IO.Path]::GetDirectoryName($derivedApplicationsRoot) }
  $comparison = Get-PathStringComparison
  if (
    [string]::IsNullOrWhiteSpace($privateFolder) -or
    -not [string]::Equals([System.IO.Path]::GetFileName($workFilesFolder), '_Arbeitsdateien', $comparison) -or
    -not [string]::Equals([System.IO.Path]::GetFileName($derivedApplicationsRoot), 'Bewerbungen', $comparison) -or
    -not [string]::Equals([System.IO.Path]::GetFileName($privateFolder), 'Private', $comparison)
  ) {
    throw "Arbeitsordner besitzt nicht die erwartete Private/Bewerbungen/<Firma>/_Arbeitsdateien/<Auftrag>-Struktur: $full"
  }

  $root = if ([string]::IsNullOrWhiteSpace($ApplicationsRoot)) {
    $derivedApplicationsRoot
  } else {
    [System.IO.Path]::GetFullPath($ApplicationsRoot).TrimEnd(
      [System.IO.Path]::DirectorySeparatorChar,
      [System.IO.Path]::AltDirectorySeparatorChar
    )
  }
  if (-not [string]::Equals($root, $derivedApplicationsRoot, $comparison)) {
    throw "Arbeitsordner gehört nicht zum erwarteten Bewerbungen-Root: $root"
  }

  $safePath = Resolve-SafePath -Candidate $full -Root $root -MustExist -ForWrite -PathType Container
  return [pscustomobject][ordered]@{
    Path = $safePath
    ApplicationsRoot = $root
  }
}

function Test-IsApplicationWorkFolder {
  param([string]$Path, [string]$ApplicationsRoot)
  try {
    $null = Resolve-ApplicationWorkFolder -Path $Path -ApplicationsRoot $ApplicationsRoot
    return $true
  } catch {
    return $false
  }
}

function Get-ActivityUtc {
  param([string]$Path)
  $activityNames = @(
    'Arbeitsnotizen.md',
    'Bewerbungsauftrag.json',
    'Anforderungsmatrix.json',
    'Stammdaten-Pruefbericht.json',
    'Inhalts-Pruefbericht.json',
    'ATS-Pruefbericht.json',
    'Finalisierungsbericht.json',
    'Layoutcheck-Bericht.json',
    'PDF-Export-Bericht.json'
  )
  $items = @(Get-ChildItem -LiteralPath $Path -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
    if ($_.FullName -notmatch '[\\/]Kandidat[\\/]' -and $activityNames -notcontains $_.Name) { return $false }
    try {
      $null = Resolve-SafePath -Candidate $_.FullName -Root $Path -MustExist -PathType Leaf
      return $true
    } catch {
      return $false
    }
  })
  if ($items.Count -eq 0) { return [datetime]::MinValue }
  return ($items | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).LastWriteTimeUtc
}

function Test-ArtifactRecord {
  param([object]$Record, [string]$Root)
  $path = [string](Get-JsonProperty -Object $Record -Name 'path')
  $sha = [string](Get-JsonProperty -Object $Record -Name 'sha256')
  if ([string]::IsNullOrWhiteSpace($path) -or $sha -notmatch '^[A-Fa-f0-9]{64}$') { return $false }
  try {
    $path = Resolve-SafePath -Candidate $path -Root $Root -MustExist -ForWrite -PathType Leaf
  } catch {
    return $false
  }
  return ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ceq $sha.ToUpperInvariant())
}

function Test-ArtifactRecordSetExact {
  param([object[]]$Records, [string]$Folder, [string]$Filter = '*')
  if (-not (Test-Path -LiteralPath $Folder -PathType Container)) { return $false }
  $recordsArray = @($Records)
  $currentFiles = @(Get-ChildItem -LiteralPath $Folder -File -Filter $Filter | Sort-Object FullName)
  if ($recordsArray.Count -ne $currentFiles.Count) { return $false }
  foreach ($record in $recordsArray) {
    if (-not (Test-ArtifactRecord -Record $record -Root $Folder)) { return $false }
  }
  $recordPaths = @($recordsArray | ForEach-Object {
    [System.IO.Path]::GetFullPath([string](Get-JsonProperty -Object $_ -Name 'path'))
  } | Sort-Object)
  $currentPaths = @($currentFiles | ForEach-Object { [System.IO.Path]::GetFullPath($_.FullName) } | Sort-Object)
  return (@(Compare-Object -ReferenceObject $recordPaths -DifferenceObject $currentPaths -CaseSensitive).Count -eq 0)
}

function Test-FinalReportArtifacts {
  param([object]$Report, [string]$CandidateFolder, [string]$WorkFolder, [string]$ApplicationsRoot)
  $privateRoot = Split-Path -Path $ApplicationsRoot -Parent
  foreach ($sourceName in @('stammdaten', 'profil', 'bewerbungsauftrag', 'anforderungsmatrix')) {
    $sources = Get-JsonProperty -Object $Report -Name 'sourceInputs'
    $sourceRoot = if ($sourceName -in @('stammdaten', 'profil')) { $privateRoot } else { $WorkFolder }
    if (-not (Test-ArtifactRecord -Record (Get-JsonProperty -Object $sources -Name $sourceName) -Root $sourceRoot)) { return $false }
  }
  $artifacts = Get-JsonProperty -Object $Report -Name 'artifacts'
  foreach ($groupName in @('candidate', 'html', 'pdf', 'screenshots')) {
    if ($null -eq $artifacts -or $null -eq $artifacts.PSObject.Properties[$groupName]) { return $false }
  }
  $candidateRecords = @((Get-JsonProperty -Object $artifacts -Name 'candidate'))
  if ($candidateRecords.Count -eq 0 -or -not (Test-ArtifactRecordSetExact -Records $candidateRecords -Folder $CandidateFolder)) { return $false }
  if (-not (Test-ArtifactRecordSetExact -Records @((Get-JsonProperty -Object $artifacts -Name 'html')) -Folder $CandidateFolder -Filter '*.html')) { return $false }
  if (-not (Test-ArtifactRecordSetExact -Records @((Get-JsonProperty -Object $artifacts -Name 'pdf')) -Folder $CandidateFolder -Filter '*.pdf')) { return $false }
  foreach ($reportField in @('layoutReportArtifact', 'pdfReportArtifact', 'atsReportArtifact')) {
    if (-not (Test-ArtifactRecord -Record (Get-JsonProperty -Object $Report -Name $reportField) -Root $WorkFolder)) { return $false }
  }
  $layoutReportPath = [string](Get-JsonProperty -Object (Get-JsonProperty -Object $Report -Name 'layoutReportArtifact') -Name 'path')
  try {
    $layoutFolder = Resolve-SafePath -Candidate (Split-Path -Path $layoutReportPath -Parent) -Root $WorkFolder -MustExist -ForWrite -PathType Container
  } catch {
    return $false
  }
  if (-not (Test-ArtifactRecordSetExact -Records @((Get-JsonProperty -Object $artifacts -Name 'screenshots')) -Folder $layoutFolder -Filter '*.png')) { return $false }
  return $true
}

function Test-FinalReportRuntimeCurrent {
  param([object]$Report)

  $schema = Get-JsonProperty -Object $Report -Name 'schemaVersion'
  if (($schema -isnot [int] -and $schema -isnot [long]) -or [int]$schema -ne 5) { return $false }
  $runtime = Get-JsonProperty -Object $Report -Name 'runtime'
  if ($null -eq $runtime) { return $false }
  $runtimeSchema = Get-JsonProperty -Object $runtime -Name 'schemaVersion'
  if (($runtimeSchema -isnot [int] -and $runtimeSchema -isnot [long]) -or [int]$runtimeSchema -ne 1) { return $false }
  $current = Get-RuntimeFingerprint
  $matches = (
    [string](Get-JsonProperty -Object $runtime -Name 'os') -ceq [string]$current.os -and
    [string](Get-JsonProperty -Object $runtime -Name 'architecture') -ceq [string]$current.architecture -and
    [string](Get-JsonProperty -Object $runtime -Name 'psEdition') -ceq 'Core'
  )
  if ($matches -and [string]$current.os -ceq 'linux') {
    $matches = (
      [string](Get-JsonProperty -Object $runtime -Name 'distributionId') -ceq [string]$current.distributionId -and
      [string](Get-JsonProperty -Object $runtime -Name 'distributionVersion') -ceq [string]$current.distributionVersion -and
      [string](Get-JsonProperty -Object $runtime -Name 'wsl') -ceq [string]$current.wsl
    )
  }
  return $matches
}

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..'))
if ([string]::IsNullOrWhiteSpace($Arbeitsordner)) {
  $applicationsRoot = Join-Path -Path $repoRoot -ChildPath 'Private/Bewerbungen'
  if (-not (Test-Path -LiteralPath $applicationsRoot -PathType Container)) {
    Stop-Status "Private/Bewerbungen existiert nicht."
  }
  $applicationsRoot = [System.IO.Path]::GetFullPath($applicationsRoot)
  $candidates = @(Get-ChildItem -LiteralPath $applicationsRoot -Directory -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    try {
      $context = Resolve-ApplicationWorkFolder -Path $_.FullName -ApplicationsRoot $applicationsRoot
      $safeNotes = Resolve-SafePath -Candidate (Join-Path $context.Path 'Arbeitsnotizen.md') -Root $context.Path -MustExist -PathType Leaf
      $safeOrder = Resolve-SafePath -Candidate (Join-Path $context.Path 'Bewerbungsauftrag.json') -Root $context.Path -MustExist -PathType Leaf
      if ([string]::IsNullOrWhiteSpace($safeNotes) -or [string]::IsNullOrWhiteSpace($safeOrder)) { return }
      [pscustomobject]@{ Path = $context.Path; ActivityUtc = Get-ActivityUtc -Path $context.Path }
    } catch {
      # Ungültige oder aus dem Root ausbrechende Kandidaten werden bei der automatischen Suche ignoriert.
    }
  } | Sort-Object ActivityUtc -Descending)
  if ($candidates.Count -eq 0) { Stop-Status "Kein gültiger Bewerbungsarbeitsordner gefunden." }
  if ($candidates.Count -gt 1 -and $candidates[0].ActivityUtc -eq $candidates[1].ActivityUtc) {
    Stop-Status "Mehrere Bewerbungen besitzen denselben letzten Aktivitätszeitpunkt. Firma oder Rolle muss angegeben werden." 2
  }
  $resolvedWork = $candidates[0].Path
  $applicationsRootForWork = $applicationsRoot
} else {
  try {
    $context = Resolve-ApplicationWorkFolder -Path $Arbeitsordner
  } catch {
    Stop-Status "Arbeitsordner ist kein sicherer Bewerbungsarbeitsordner: $Arbeitsordner ($($_.Exception.Message))" 2
  }
  $resolvedWork = $context.Path
  $applicationsRootForWork = $context.ApplicationsRoot
}

try {
  $orderPath = Resolve-SafePath -Candidate (Join-Path $resolvedWork 'Bewerbungsauftrag.json') -Root $resolvedWork -MustExist -PathType Leaf
  $notesPath = Resolve-SafePath -Candidate (Join-Path $resolvedWork 'Arbeitsnotizen.md') -Root $resolvedWork -MustExist -PathType Leaf
} catch {
  Stop-Status "Arbeitsnotizen.md oder Bewerbungsauftrag.json fehlt oder ist nicht sicher: $($_.Exception.Message)" 2
}

try {
  $order = Get-Content -LiteralPath $orderPath -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
  Stop-Status "Bewerbungsauftrag.json ist nicht lesbar: $($_.Exception.Message)"
}

$scope = Get-JsonProperty -Object $order -Name 'dokumentumfang'
$dialog = Get-JsonProperty -Object $order -Name 'dialog'
try {
  $orderPaths = Resolve-BewerbungsauftragPathSet -Auftrag $order -Arbeitsordner $resolvedWork -BewerbungenRoot $applicationsRootForWork
  $safeCandidateFolder = Resolve-SafePath -Candidate $orderPaths.KandidatOrdner -Root $applicationsRootForWork -ForWrite -PathType Container
  $safeTargetFolder = Resolve-SafePath -Candidate $orderPaths.ZielOrdner -Root $applicationsRootForWork -ForWrite -PathType Container
} catch {
  Stop-Status "Auftragspfade sind nicht sicher auflösbar: $($_.Exception.Message)" 2
}
$candidateFolder = $safeCandidateFolder

$blockers = [System.Collections.Generic.List[string]]::new()
foreach ($question in @((Get-JsonProperty -Object $dialog -Name 'rueckfragen'))) {
  if ($null -eq $question) { continue }
  if ([string](Get-JsonProperty -Object $question -Name 'status') -eq 'offen' -and [bool](Get-JsonProperty -Object $question -Name 'blockiertDokumenterstellung')) {
    $blockers.Add([string](Get-JsonProperty -Object $question -Name 'id'))
  }
}
foreach ($fact in @((Get-JsonProperty -Object $dialog -Name 'angaben'))) {
  if ($null -ne $fact -and [string](Get-JsonProperty -Object $fact -Name 'speicherentscheidung') -eq 'ausstehend') {
    $blockers.Add([string](Get-JsonProperty -Object $fact -Name 'id'))
  }
}

$expectedFiles = [System.Collections.Generic.List[string]]::new()
if ([string](Get-JsonProperty -Object $scope -Name 'lebenslauf') -ne 'nicht_enthalten') {
  $expectedFiles.Add('Lebenslauf - *.html')
}
if ([bool](Get-JsonProperty -Object $scope -Name 'anschreiben')) {
  $expectedFiles.Add('Anschreiben - *.html')
}
if ([bool](Get-JsonProperty -Object $scope -Name 'emailNachricht')) {
  $expectedFiles.Add('Email-Nachricht--*.md')
}
$expectedFiles.Add('Stellenbeschreibung.md')
$expectedFiles.Add('Analyse.md')
$expectedFiles.Add('Qualitaetscheck.md')
$expectedFiles.Add('Druck-Hinweis.md')

$missingFiles = [System.Collections.Generic.List[string]]::new()
foreach ($pattern in $expectedFiles) {
  $matchingFiles = @()
  if (Test-Path -LiteralPath $candidateFolder -PathType Container) {
    $matchingFiles = @(Get-ChildItem -LiteralPath $candidateFolder -File -Filter $pattern -ErrorAction SilentlyContinue)
  }
  $matchingSafe = if ($matchingFiles.Count -eq 1) {
    try {
      $null = Resolve-SafePath -Candidate $matchingFiles[0].FullName -Root $candidateFolder -MustExist -ForWrite -PathType Leaf
      $true
    } catch { $false }
  } else { $false }
  if (-not $matchingSafe) {
    $missingFiles.Add($pattern)
  }
}

$matrixPath = Resolve-SafePath -Candidate (Join-Path $resolvedWork 'Anforderungsmatrix.json') -Root $resolvedWork
$finalReportPath = Resolve-SafePath -Candidate (Join-Path $resolvedWork 'Finalisierungsbericht.json') -Root $resolvedWork
$finalReportValid = $false
$finalStatus = ''
$targetFolder = $safeTargetFolder
if (Test-Path -LiteralPath $finalReportPath -PathType Leaf) {
  try {
    $finalReport = Get-Content -LiteralPath $finalReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $finalStatus = [string](Get-JsonProperty -Object $finalReport -Name 'status')
    $finalReportValid = (Test-FinalReportArtifacts -Report $finalReport -CandidateFolder $candidateFolder -WorkFolder $resolvedWork -ApplicationsRoot $applicationsRootForWork) -and (Test-FinalReportRuntimeCurrent -Report $finalReport)
  } catch {
    $finalReportValid = $false
  }
}

$scopeConfirmed = [bool](Get-JsonProperty -Object $scope -Name 'bestaetigt')
$dialogStatus = [string](Get-JsonProperty -Object $dialog -Name 'status')
$phase = ''
$nextAction = ''
$requiredPrompts = @()

if (-not $scopeConfirmed) {
  $phase = 'umfangsklaerung'
  $nextAction = 'Dokumentumfang nach Prompt 01 eindeutig bestätigen.'
  $requiredPrompts = @('Prompts/01_DOKUMENTMODI_UND_UNIVERSALER_LEBENSLAUF.md')
} elseif ($blockers.Count -gt 0 -or $dialogStatus -in @('profilabgleich_ausstehend', 'rueckfragen_offen', 'speicherentscheidung_offen')) {
  $phase = 'profilabgleich'
  $nextAction = 'Nur die gespeicherten offenen Blocker bearbeiten und den Dialogstatus validieren.'
  $requiredPrompts = @('Prompts/01_DOKUMENTMODI_UND_UNIVERSALER_LEBENSLAUF.md', 'Prompts/07_WAHRHEIT_UND_GRENZEN.md')
} elseif (-not (Test-Path -LiteralPath $matrixPath -PathType Leaf)) {
  $phase = 'strategie_und_matrix'
  $nextAction = 'Profilstrategie festlegen und die deduplizierte Anforderungsmatrix finalisieren.'
  $requiredPrompts = @('Prompts/02_VORPRUEFUNG_UND_ANFORDERUNGSMATRIX.md', 'Prompts/06_ROLLENLOGIK.md', 'Prompts/07_WAHRHEIT_UND_GRENZEN.md')
} elseif ($missingFiles.Count -gt 0) {
  $phase = 'dokumenterstellung'
  $nextAction = 'Nur die laut Dokumentumfang noch fehlenden Kandidatendateien erstellen.'
  $requiredPrompts = @()
  if ([string](Get-JsonProperty -Object $scope -Name 'lebenslauf') -ne 'nicht_enthalten') { $requiredPrompts += 'Prompts/03_LEBENSLAUF_REGELN.md' }
  if ([bool](Get-JsonProperty -Object $scope -Name 'anschreiben')) { $requiredPrompts += 'Prompts/04_ANSCHREIBEN_REGELN.md' }
  if ([bool](Get-JsonProperty -Object $scope -Name 'emailNachricht')) { $requiredPrompts += 'Prompts/05_EMAIL_NACHRICHT_REGELN.md' }
  if ([string](Get-JsonProperty -Object $scope -Name 'lebenslauf') -ne 'nicht_enthalten' -or [bool](Get-JsonProperty -Object $scope -Name 'anschreiben')) { $requiredPrompts += 'Prompts/08_HTML_CSS_DESIGNREGELN.md' }
} elseif ($finalReportValid -and $finalStatus -eq 'bereit_zur_sichtpruefung') {
  $phase = 'persoenliche_pruefung'
  $nextAction = 'Jede gebundene PNG-Seite beziehungsweise ausgewählte Textdatei persönlich prüfen und danach eindeutig bestätigen.'
  $requiredPrompts = @('Prompts/11_TECHNISCHER_CHECK_WORKFLOW.md')
} elseif ($finalReportValid -and $finalStatus -eq 'veroeffentlicht' -and (& {
  try {
    $null = Resolve-SafePath -Candidate (Join-Path $targetFolder 'Manifest.json') -Root $targetFolder -MustExist -ForWrite -PathType Leaf
    $true
  } catch { $false }
})) {
  $phase = 'veroeffentlicht'
  $nextAction = 'Keine weitere Aktion erforderlich; veröffentlichte Dateien nur nach neuem Auftrag ändern.'
  $requiredPrompts = @()
} else {
  $phase = 'technische_vorbereitung'
  $nextAction = 'Fachlichen Kandidatenstand prüfen und den verbindlichen Finalisierungslauf vorbereiten.'
  $requiredPrompts = @('Prompts/09_QUALITAETSCHECK.md', 'Prompts/11_TECHNISCHER_CHECK_WORKFLOW.md')
}

$result = [ordered]@{
  schemaVersion = 1
  workFolder = $resolvedWork
  candidateFolder = $candidateFolder
  phase = $phase
  dialogStatus = $dialogStatus
  blockers = @($blockers)
  missingCandidateFiles = @($missingFiles)
  finalReportValid = $finalReportValid
  finalStatus = if ([string]::IsNullOrWhiteSpace($finalStatus)) { $null } else { $finalStatus }
  requiredPrompts = @($requiredPrompts)
  nextAction = $nextAction
}

if ($AlsJson) {
  $result | ConvertTo-Json -Depth 6
} else {
  Write-Host "[OK] Arbeitsordner: $resolvedWork"
  Write-Host "Phase: $phase"
  if ($blockers.Count -gt 0) { Write-Host "Blocker: $($blockers -join ', ')" }
  if ($missingFiles.Count -gt 0) { Write-Host "Fehlende Kandidatendateien: $($missingFiles -join ', ')" }
  if ($requiredPrompts.Count -gt 0) { Write-Host "Jetzt benötigte Promptmodule: $($requiredPrompts -join ', ')" }
  Write-Host "Nächster Schritt: $nextAction"
}
