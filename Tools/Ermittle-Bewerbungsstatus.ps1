[CmdletBinding()]
param(
  [string]$Arbeitsordner,

  [switch]$AlsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

function Test-IsApplicationWorkFolder {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
  $full = [System.IO.Path]::GetFullPath($Path)
  return ($full -match '[\\/]Private[\\/]Bewerbungen[\\/].+[\\/]_Arbeitsdateien[\\/][^\\/]+$')
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
    $_.FullName -match '[\\/]Kandidat[\\/]' -or $activityNames -contains $_.Name
  })
  if ($items.Count -eq 0) { return [datetime]::MinValue }
  return ($items | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).LastWriteTimeUtc
}

function Test-ArtifactRecord {
  param([object]$Record)
  $path = [string](Get-JsonProperty -Object $Record -Name 'path')
  $sha = [string](Get-JsonProperty -Object $Record -Name 'sha256')
  if ([string]::IsNullOrWhiteSpace($path) -or $sha -notmatch '^[A-Fa-f0-9]{64}$') { return $false }
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
  return ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ceq $sha.ToUpperInvariant())
}

function Test-ArtifactRecordSetExact {
  param([object[]]$Records, [string]$Folder, [string]$Filter = '*')
  if (-not (Test-Path -LiteralPath $Folder -PathType Container)) { return $false }
  $recordsArray = @($Records)
  $currentFiles = @(Get-ChildItem -LiteralPath $Folder -File -Filter $Filter | Sort-Object FullName)
  if ($recordsArray.Count -ne $currentFiles.Count) { return $false }
  foreach ($record in $recordsArray) {
    if (-not (Test-ArtifactRecord -Record $record)) { return $false }
  }
  $recordPaths = @($recordsArray | ForEach-Object {
    [System.IO.Path]::GetFullPath([string](Get-JsonProperty -Object $_ -Name 'path'))
  } | Sort-Object)
  $currentPaths = @($currentFiles | ForEach-Object { [System.IO.Path]::GetFullPath($_.FullName) } | Sort-Object)
  return (@(Compare-Object -ReferenceObject $recordPaths -DifferenceObject $currentPaths -CaseSensitive).Count -eq 0)
}

function Test-FinalReportArtifacts {
  param([object]$Report, [string]$CandidateFolder)
  foreach ($sourceName in @('stammdaten', 'profil', 'bewerbungsauftrag', 'anforderungsmatrix')) {
    $sources = Get-JsonProperty -Object $Report -Name 'sourceInputs'
    if (-not (Test-ArtifactRecord -Record (Get-JsonProperty -Object $sources -Name $sourceName))) { return $false }
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
    if (-not (Test-ArtifactRecord -Record (Get-JsonProperty -Object $Report -Name $reportField))) { return $false }
  }
  $layoutReportPath = [string](Get-JsonProperty -Object (Get-JsonProperty -Object $Report -Name 'layoutReportArtifact') -Name 'path')
  $layoutFolder = Split-Path -Path $layoutReportPath -Parent
  if (-not (Test-ArtifactRecordSetExact -Records @((Get-JsonProperty -Object $artifacts -Name 'screenshots')) -Folder $layoutFolder -Filter '*.png')) { return $false }
  return $true
}

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..'))
if ([string]::IsNullOrWhiteSpace($Arbeitsordner)) {
  $applicationsRoot = Join-Path -Path $repoRoot -ChildPath 'Private/Bewerbungen'
  if (-not (Test-Path -LiteralPath $applicationsRoot -PathType Container)) {
    Stop-Status "Private/Bewerbungen existiert nicht."
  }
  $candidates = @(Get-ChildItem -LiteralPath $applicationsRoot -Directory -Recurse -ErrorAction SilentlyContinue | Where-Object {
    (Test-Path -LiteralPath (Join-Path $_.FullName 'Arbeitsnotizen.md') -PathType Leaf) -and
    (Test-Path -LiteralPath (Join-Path $_.FullName 'Bewerbungsauftrag.json') -PathType Leaf) -and
    (Test-IsApplicationWorkFolder -Path $_.FullName)
  } | ForEach-Object {
    [pscustomobject]@{ Path = $_.FullName; ActivityUtc = Get-ActivityUtc -Path $_.FullName }
  } | Sort-Object ActivityUtc -Descending)
  if ($candidates.Count -eq 0) { Stop-Status "Kein gültiger Bewerbungsarbeitsordner gefunden." }
  if ($candidates.Count -gt 1 -and $candidates[0].ActivityUtc -eq $candidates[1].ActivityUtc) {
    Stop-Status "Mehrere Bewerbungen besitzen denselben letzten Aktivitätszeitpunkt. Firma oder Rolle muss angegeben werden." 2
  }
  $resolvedWork = $candidates[0].Path
} else {
  if (-not (Test-IsApplicationWorkFolder -Path $Arbeitsordner)) {
    Stop-Status "Arbeitsordner ist kein sicherer Bewerbungsarbeitsordner: $Arbeitsordner"
  }
  $resolvedWork = (Resolve-Path -LiteralPath $Arbeitsordner).Path
}

$orderPath = Join-Path -Path $resolvedWork -ChildPath 'Bewerbungsauftrag.json'
$notesPath = Join-Path -Path $resolvedWork -ChildPath 'Arbeitsnotizen.md'
if (-not (Test-Path -LiteralPath $orderPath -PathType Leaf) -or -not (Test-Path -LiteralPath $notesPath -PathType Leaf)) {
  Stop-Status "Arbeitsnotizen.md oder Bewerbungsauftrag.json fehlt."
}

try {
  $order = Get-Content -LiteralPath $orderPath -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
  Stop-Status "Bewerbungsauftrag.json ist nicht lesbar: $($_.Exception.Message)"
}

$scope = Get-JsonProperty -Object $order -Name 'dokumentumfang'
$dialog = Get-JsonProperty -Object $order -Name 'dialog'
$candidateFolder = [string](Get-JsonProperty -Object $order -Name 'kandidatOrdner')
if ([string]::IsNullOrWhiteSpace($candidateFolder)) {
  $candidateFolder = Join-Path -Path $resolvedWork -ChildPath 'Kandidat'
}
$candidateFolder = [System.IO.Path]::GetFullPath($candidateFolder)

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
  if (-not (Test-Path -LiteralPath $candidateFolder -PathType Container) -or @(Get-ChildItem -LiteralPath $candidateFolder -File -Filter $pattern -ErrorAction SilentlyContinue).Count -ne 1) {
    $missingFiles.Add($pattern)
  }
}

$matrixPath = Join-Path -Path $resolvedWork -ChildPath 'Anforderungsmatrix.json'
$finalReportPath = Join-Path -Path $resolvedWork -ChildPath 'Finalisierungsbericht.json'
$finalReportValid = $false
$finalStatus = ''
$targetFolder = [string](Get-JsonProperty -Object $order -Name 'zielOrdner')
if (Test-Path -LiteralPath $finalReportPath -PathType Leaf) {
  try {
    $finalReport = Get-Content -LiteralPath $finalReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $finalStatus = [string](Get-JsonProperty -Object $finalReport -Name 'status')
    $finalReportValid = Test-FinalReportArtifacts -Report $finalReport -CandidateFolder $candidateFolder
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
} elseif ($finalReportValid -and $finalStatus -eq 'veroeffentlicht' -and (Test-Path -LiteralPath (Join-Path $targetFolder 'Manifest.json') -PathType Leaf)) {
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
