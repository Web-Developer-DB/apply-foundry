#requires -Version 7.6
#requires -PSEdition Core

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Arbeitsordner,

  [ValidateSet('auto', 'chrome', 'edge', 'chromium')]
  [string]$Browser = 'auto',

  [string]$BrowserExecutablePath,

  [string]$StammdatenPath = (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'Private', 'Daten', '01_PERSOENLICHE_DATEN.md'),

  [string]$ProfilPath = (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'Private', 'Daten', '02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md'),

  [switch]$Veroeffentlichen,

  [switch]$VisuellGeprueft,

  [string]$VisuelleFreigabeNotiz,

  [switch]$Ersetzen,

  [ValidateRange(1, 600)]
  [int]$TimeoutSeconds = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath 'Common/Platform.psm1') -Force
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath 'Common/ApprovalContract.psm1') -Force
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath 'Common/JsonContract.psm1') -Force
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath 'Common/AtomicFile.psm1') -Force

function Stop-UniversalFinalization {
  param([string]$Message, [int]$Code = 1)
  Write-Host "[FEHLER] $Message" -ForegroundColor Red
  exit $Code
}

function Get-JsonProperty {
  param([object]$Object, [string]$Name)
  if ($null -eq $Object) { return $null }
  if ($Object -is [System.Collections.IDictionary]) {
    if ($Object.Contains($Name)) { return $Object[$Name] }
    return $null
  }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

function Invoke-UniversalChildTool {
  param([string]$ScriptPath, [string[]]$Arguments)
  $powerShellExe = (Get-Process -Id $PID).Path
  $result = Invoke-NativeProcess `
    -FilePath $powerShellExe `
    -ArgumentList (@('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $ScriptPath) + @($Arguments)) `
    -TimeoutSeconds ([math]::Min(3600, [math]::Max(120, $TimeoutSeconds * 8))) `
    -MaxStdoutChars 262144 `
    -MaxStderrChars 262144
  foreach ($line in @($result.StandardOutput -split '\r?\n' | Where-Object { $_.Length -gt 0 })) { Write-Host $line }
  foreach ($line in @($result.StandardError -split '\r?\n' | Where-Object { $_.Length -gt 0 })) { Write-Host $line }
  if ($result.TimedOut) { throw "Unterwerkzeug überschritt sein Zeitlimit: $ScriptPath" }
  if ($result.ExitCode -ne 0) { throw "Unterwerkzeug schlug mit Exitcode $($result.ExitCode) fehl: $ScriptPath" }
}

function Get-ArtifactRecord {
  param([System.IO.FileInfo]$File, [string]$Root)
  return [ordered]@{
    path = [IO.Path]::GetRelativePath($Root, $File.FullName).Replace('\', '/')
    name = $File.Name
    bytes = $File.Length
    sha256 = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash
  }
}

function Test-ArtifactRecords {
  param([array]$Records, [string]$Root)
  foreach ($record in $Records) {
    $relative = [string](Get-JsonProperty -Object $record -Name 'path')
    if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $relative -match '(^|/|\\)\.\.($|/|\\)') {
      throw "Ungültiger Artefaktpfad im Freigabenachweis: $relative"
    }
    $path = Resolve-SafePath -Candidate (Join-Path $Root $relative) -Root $Root -MustExist -ForWrite -PathType Leaf
    $file = Get-Item -LiteralPath $path
    if ($file.Length -ne [long](Get-JsonProperty -Object $record -Name 'bytes') -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine [string](Get-JsonProperty -Object $record -Name 'sha256')) {
      throw "Artefakt wurde nach der Vorbereitung verändert: $relative"
    }
  }
}

function Get-UniversalPageMatches {
  param([string]$Html)
  return [regex]::Matches($Html, '(?is)<main\b(?=[^>]*\bclass\s*=\s*["''][^"'']*\bpage\b[^"'']*["''])[^>]*>(?<body>.*?)</main\s*>')
}

function Test-UniversalSectionPlan {
  param([string]$Html, [object]$Order)
  $pages = @(Get-UniversalPageMatches -Html $Html)
  if ($pages.Count -ne 2) { throw 'Der universelle Softwareentwicklungs-Lebenslauf muss genau zwei explizite A4-Seiten enthalten.' }
  $seen = @{}
  $idsByPage = @()
  for ($index = 0; $index -lt $pages.Count; $index++) {
    $body = $pages[$index].Groups['body'].Value
    if ($body -notmatch '(?is)<header\b[^>]*\bdata-cv-page-header(?:\s*=|\s|>)') {
      throw "Seite $($index + 1) enthält keinen mit data-cv-page-header markierten Seitenkopf."
    }
    $ids = @([regex]::Matches($body, '(?is)<section\b[^>]*\bdata-cv-section\s*=\s*["''](?<id>[a-z0-9]+(?:-[a-z0-9]+)*)["'']') | ForEach-Object { $_.Groups['id'].Value })
    if ($ids.Count -eq 0) { throw "Seite $($index + 1) enthält keine semantisch markierten CV-Abschnitte." }
    foreach ($id in $ids) {
      if ($seen.ContainsKey($id)) { throw "CV-Abschnitt '$id' ist über mehrere Seiten verteilt oder doppelt vorhanden." }
      $seen[$id] = $index + 1
    }
    $idsByPage += ,$ids
  }
  $strategy = Get-JsonProperty -Object $Order -Name 'seitenstrategie'
  foreach ($pageNumber in 1..2) {
    $expected = @((Get-JsonProperty -Object $strategy -Name "seite$pageNumber") | ForEach-Object { [string]$_ })
    $actual = @($idsByPage[$pageNumber - 1])
    if (($actual -join ',') -cne ($expected -join ',')) {
      throw "Seite $pageNumber muss exakt die Abschnitte '$($expected -join ', ')' in dieser Reihenfolge enthalten; gefunden: '$($actual -join ', ')'."
    }
  }
}

function Remove-DirectoryWithRetry {
  param([string]$Path, [string]$Root, [int]$Attempts = 8)
  if (-not (Test-Path -LiteralPath $Path)) { return $true }
  for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
    try {
      $safe = Resolve-SafePath -Candidate $Path -Root $Root -MustExist -ForWrite -PathType Container
      Remove-Item -LiteralPath $safe -Recurse -Force -ErrorAction Stop
    } catch {
      if ($attempt -lt $Attempts) { Start-Sleep -Milliseconds 250 }
    }
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
  }
  return $false
}

try {
  $workInput = [IO.Path]::GetFullPath($Arbeitsordner)
  if (-not (Test-Path -LiteralPath $workInput -PathType Container)) { throw "Arbeitsordner fehlt: $workInput" }
  $workCollection = Split-Path $workInput -Parent
  $namespace = Split-Path $workCollection -Parent
  $applicationsRoot = Split-Path $namespace -Parent
  $privateRoot = Split-Path $applicationsRoot -Parent
  if ((Split-Path $workCollection -Leaf) -cne '_Arbeitsdateien' -or
      (Split-Path $namespace -Leaf) -cne '_Universal-Lebenslauf' -or
      (Split-Path $applicationsRoot -Leaf) -cne 'Bewerbungen' -or
      (Split-Path $privateRoot -Leaf) -cne 'Private') {
    throw 'Arbeitsordner muss unter Private/Bewerbungen/_Universal-Lebenslauf/_Arbeitsdateien liegen.'
  }
  $applicationsRoot = Resolve-SafePath -Candidate $applicationsRoot -Root $applicationsRoot -AllowRoot -MustExist -ForWrite -PathType Container
  $work = Resolve-SafePath -Candidate $workInput -Root $applicationsRoot -MustExist -ForWrite -PathType Container
  $candidate = Resolve-SafePath -Candidate (Join-Path $work 'Kandidat') -Root $applicationsRoot -MustExist -ForWrite -PathType Container
  $orderPath = Resolve-SafePath -Candidate (Join-Path $work 'Universalauftrag.json') -Root $applicationsRoot -MustExist -ForWrite -PathType Leaf
  $active = Resolve-SafePath -Candidate (Join-Path $namespace 'Aktiv') -Root $applicationsRoot -ForWrite -PathType Container
  $layoutDir = Resolve-SafePath -Candidate (Join-Path $work 'Layoutcheck') -Root $applicationsRoot -ForWrite -PathType Container
  $pdfDir = Resolve-SafePath -Candidate (Join-Path $work 'PDF-Export') -Root $applicationsRoot -ForWrite -PathType Container
  $layoutReport = Resolve-SafePath -Candidate (Join-Path $layoutDir 'Layoutcheck-Bericht.json') -Root $applicationsRoot -ForWrite -PathType Leaf
  $pdfReport = Resolve-SafePath -Candidate (Join-Path $pdfDir 'PDF-Export-Bericht.json') -Root $applicationsRoot -ForWrite -PathType Leaf
  $atsReport = Resolve-SafePath -Candidate (Join-Path $work 'ATS-Pruefbericht.json') -Root $applicationsRoot -ForWrite -PathType Leaf
  $finalReport = Resolve-SafePath -Candidate (Join-Path $work 'Universal-Finalisierungsbericht.json') -Root $applicationsRoot -ForWrite -PathType Leaf
} catch {
  Stop-UniversalFinalization "Unsicherer Universal-Lebenslauf-Pfad: $($_.Exception.Message)" 2
}

$order = Get-Content -LiteralPath $orderPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([int](Get-JsonProperty -Object $order -Name 'schemaVersion') -ne 5 -or
    [string](Get-JsonProperty -Object $order -Name 'auftragsart') -cne 'universal_lebenslauf' -or
    [string](Get-JsonProperty -Object $order -Name 'fachrichtung') -cne 'softwareentwicklung') {
  Stop-UniversalFinalization 'Universalauftrag besitzt nicht den unterstützten Softwareentwicklungsvertrag.' 2
}
$personFileName = [string](Get-JsonProperty -Object $order -Name 'bewerberDateiname')
$expectedHtmlName = "Lebenslauf - $personFileName.html"
$htmlFiles = @(Get-ChildItem -LiteralPath $candidate -File -Filter 'Lebenslauf - *.html')
if ($htmlFiles.Count -ne 1 -or $htmlFiles[0].Name -cne $expectedHtmlName) {
  Stop-UniversalFinalization "Kandidat muss genau die Datei '$expectedHtmlName' enthalten."
}
$htmlPath = $htmlFiles[0].FullName
$pdfPath = [IO.Path]::ChangeExtension($htmlPath, '.pdf')

$stammdaten = Resolve-SafePath -Candidate $StammdatenPath -Root $privateRoot -MustExist -PathType Leaf
$profil = Resolve-SafePath -Candidate $ProfilPath -Root $privateRoot -MustExist -PathType Leaf
$sourceInputs = Get-JsonProperty -Object $order -Name 'sourceInputs'
foreach ($binding in @(
  @{ Name = 'stammdaten'; Path = $stammdaten },
  @{ Name = 'profil'; Path = $profil }
)) {
  $record = Get-JsonProperty -Object $sourceInputs -Name $binding.Name
  if ($null -eq $record -or (Get-FileHash -LiteralPath $binding.Path -Algorithm SHA256).Hash -ine [string](Get-JsonProperty -Object $record -Name 'sha256')) {
    Stop-UniversalFinalization "Private Quelle '$($binding.Name)' wurde seit Anlage verändert. Universalauftrag neu anlegen oder bewusst neu vorbereiten."
  }
}

$browserArgs = if ([string]::IsNullOrWhiteSpace($BrowserExecutablePath)) { @() } else { @('-BrowserExecutablePath', $BrowserExecutablePath) }
$staticTool = Join-Path $PSScriptRoot 'Pruefe-Bewerbung.ps1'
$layoutTool = Join-Path $PSScriptRoot 'Layoutcheck-Bewerbung.ps1'
$pdfTool = Join-Path $PSScriptRoot 'Exportiere-PDF.ps1'
$atsTool = Join-Path $PSScriptRoot 'Pruefe-ATS.ps1'

if (-not $Veroeffentlichen) {
  try {
    foreach ($name in @('Stellenbeschreibung.md', 'Analyse.md', 'Qualitaetscheck.md', 'Druck-Hinweis.md')) {
      $path = Resolve-SafePath -Candidate (Join-Path $candidate $name) -Root $candidate -MustExist -ForWrite -PathType Leaf
      $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
      if ($text.Length -lt 80 -or $text -match '(?i)\[ergänzen|TODO|DOKUMENT NOCH NICHT FINAL') {
        throw "Interner Nachweis ist noch nicht fachlich abgeschlossen: $name"
      }
    }
    $html = Get-Content -LiteralPath $htmlPath -Raw -Encoding UTF8
    Test-UniversalSectionPlan -Html $html -Order $order
    Invoke-UniversalChildTool -ScriptPath $staticTool -Arguments @('-Ordner', $candidate, '-AuftragPath', $orderPath)
    Invoke-UniversalChildTool -ScriptPath $pdfTool -Arguments (@('-Ordner', $candidate, '-AuftragPath', $orderPath, '-Browser', $Browser, '-TimeoutSeconds', "$TimeoutSeconds", '-OutputRoot', $pdfDir, '-BerichtPath', $pdfReport) + $browserArgs)
    Invoke-UniversalChildTool -ScriptPath $layoutTool -Arguments (@('-Ordner', $candidate, '-Browser', $Browser, '-TimeoutSeconds', "$TimeoutSeconds", '-OutputRoot', $layoutDir, '-BerichtPath', $layoutReport) + $browserArgs)
    Invoke-UniversalChildTool -ScriptPath $atsTool -Arguments @('-Ordner', $candidate, '-StammdatenPath', $stammdaten, '-AuftragPath', $orderPath, '-BerichtPath', $atsReport, '-PdfExportBerichtPath', $pdfReport)
    Invoke-UniversalChildTool -ScriptPath $staticTool -Arguments @('-Ordner', $candidate, '-AuftragPath', $orderPath)

    $screenshots = @(Get-ChildItem -LiteralPath $layoutDir -File -Filter '*.png' | Sort-Object Name)
    if ($screenshots.Count -ne 2) { throw "Erwartet werden genau zwei aktuelle Seitenscreenshots; gefunden: $($screenshots.Count)." }
    $layoutData = Get-Content -LiteralPath $layoutReport -Raw -Encoding UTF8 | ConvertFrom-Json
    $warnings = @($layoutData.results | ForEach-Object { [string]$_.densityWarning } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $candidateRecords = @(Get-ChildItem -LiteralPath $candidate -File | Sort-Object Name | ForEach-Object { Get-ArtifactRecord -File $_ -Root $work })
    $report = [ordered]@{
      schemaVersion = 2
      status = 'bereit_zur_sichtpruefung'
      preparedAtUtc = [datetime]::UtcNow.ToString('o')
      workId = Split-Path $work -Leaf
      order = Get-ArtifactRecord -File (Get-Item $orderPath) -Root $work
      sources = [ordered]@{
        stammdaten = [ordered]@{ name = [IO.Path]::GetFileName($stammdaten); sha256 = (Get-FileHash $stammdaten -Algorithm SHA256).Hash }
        profil = [ordered]@{ name = [IO.Path]::GetFileName($profil); sha256 = (Get-FileHash $profil -Algorithm SHA256).Hash }
      }
      candidate = $candidateRecords
      screenshots = @($screenshots | ForEach-Object { Get-ArtifactRecord -File $_ -Root $work })
      reports = @(
        Get-ArtifactRecord -File (Get-Item $layoutReport) -Root $work
        Get-ArtifactRecord -File (Get-Item $pdfReport) -Root $work
        Get-ArtifactRecord -File (Get-Item $atsReport) -Root $work
      )
      layoutWarnings = $warnings
    }
    $approvalRecords = @(Get-ContractApprovalRecords -Report $report)
    $report.approvalRequest = [ordered]@{
      approvalId = New-ContractApprovalId
      reviewKind = 'png_sichtpruefung'
      artifactSetSha256 = Get-ContractArtifactSetHash -Records $approvalRecords -Root $work
      artifactCount = $approvalRecords.Count
      createdAtUtc = [datetime]::UtcNow.ToString('o')
    }
    Write-AtomicJson -Path $finalReport -Value $report -Depth 10
  } catch {
    Stop-UniversalFinalization "Vorbereitung fehlgeschlagen: $($_.Exception.Message)"
  }
  Write-Host '[OK] Universeller Lebenslauf ist technisch bereit zur persönlichen Sichtprüfung.' -ForegroundColor Green
  foreach ($png in Get-ChildItem -LiteralPath $layoutDir -File -Filter '*.png' | Sort-Object Name) { Write-Host "- $($png.FullName)" }
  Write-Host "Nach vollständiger Sichtprüfung die Freigabe-ID im Chat bestätigen und speichern:"
  Write-Host ".\Tools\bewerbung.ps1 freigabe --arbeitsordner `"$work`" --freigabe-id $($report.approvalRequest.approvalId) --bestaetigt"
  exit 0
}

if (-not (Test-Path -LiteralPath $finalReport -PathType Leaf)) { Stop-UniversalFinalization 'Vorbereitungsbericht fehlt; zuerst ohne --veroeffentlichen vorbereiten.' }

try {
  $prepared = Get-Content -LiteralPath $finalReport -Raw -Encoding UTF8 | ConvertFrom-Json
  if ([int]$prepared.schemaVersion -ne 2 -or [string]$prepared.status -cne 'bereit_zur_sichtpruefung') { throw 'Vorbereitungsbericht besitzt keinen aktuellen Freigabestatus; Altstände müssen neu vorbereitet werden.' }
  $approvalPath = Join-Path $work 'Sichtfreigabe.json'
  if (-not (Test-Path -LiteralPath $approvalPath -PathType Leaf)) { throw 'Sichtfreigabe.json fehlt. Zuerst die im Chat bestätigte Freigabe-ID speichern.' }
  $approval = Read-ContractJson -Path $approvalPath
  if ([int](Get-ContractJsonProperty $approval 'schemaVersion') -ne 1 -or [string](Get-ContractJsonProperty $approval 'kind') -cne 'sichtfreigabe' -or
      (Get-ContractJsonProperty $approval 'humanConfirmation') -isnot [bool] -or -not [bool](Get-ContractJsonProperty $approval 'humanConfirmation')) { throw 'Sichtfreigabe besitzt kein gültiges bestätigtes Schema.' }
  $request = Get-ContractJsonProperty $prepared 'approvalRequest'
  if ($null -eq $request -or [string](Get-ContractJsonProperty $approval 'approvalId') -cne [string](Get-ContractJsonProperty $request 'approvalId') -or [string](Get-ContractJsonProperty $approval 'artifactSetSha256') -cne [string](Get-ContractJsonProperty $request 'artifactSetSha256')) { throw 'Sichtfreigabe ist nicht an die aktuelle Freigabe-ID oder den aktuellen Artefaktsatz gebunden.' }
  $preparedHash = (Get-FileHash -LiteralPath $finalReport -Algorithm SHA256).Hash
  if ([string](Get-ContractJsonProperty (Get-ContractJsonProperty $approval 'preparedReport') 'sha256') -ine $preparedHash) { throw 'Sichtfreigabe gehört nicht zum aktuellen Universal-Finalisierungsbericht.' }
  $approvalRecords = @(Get-ContractApprovalRecords -Report $prepared)
  Test-ContractArtifactRecordsCurrent -Records $approvalRecords -Root $work
  if ((Get-ContractArtifactSetHash -Records $approvalRecords -Root $work) -cne [string](Get-ContractJsonProperty $approval 'artifactSetSha256')) { throw 'Artefaktsatz wurde seit der Sichtfreigabe verändert.' }
  $boundApprovalRecords = @(Get-ContractJsonProperty $approval 'artifacts')
  if ($boundApprovalRecords.Count -ne $approvalRecords.Count) { throw 'Sichtfreigabe enthält nicht genau den vorbereiteten Artefaktsatz.' }
  Test-ContractArtifactRecordsCurrent -Records $boundApprovalRecords -Root $work
  $boundRecordsForHash = @($boundApprovalRecords | ForEach-Object {
    $boundPath = [string](Get-ContractJsonProperty $_ 'path')
    $absoluteBoundPath = if ([IO.Path]::IsPathRooted($boundPath)) { [IO.Path]::GetFullPath($boundPath) } else { [IO.Path]::GetFullPath((Join-Path $work $boundPath)) }
    $normalized = [ordered]@{ path = $absoluteBoundPath; bytes = Get-ContractJsonProperty $_ 'bytes'; sha256 = Get-ContractJsonProperty $_ 'sha256' }
    $normalized
  })
  if ((Get-ContractArtifactSetHash -Records $boundRecordsForHash -Root $work) -cne [string](Get-ContractJsonProperty $approval 'artifactSetSha256')) { throw 'Sichtfreigabe-Artefakthashes stimmen nicht mit dem gebundenen Satz überein.' }
  Test-ArtifactRecords -Records @($prepared.order) -Root $work
  Test-ArtifactRecords -Records @($prepared.candidate) -Root $work
  Test-ArtifactRecords -Records @($prepared.screenshots) -Root $work
  Test-ArtifactRecords -Records @($prepared.reports) -Root $work
  foreach ($binding in @(@{ Record = $prepared.sources.stammdaten; Path = $stammdaten }, @{ Record = $prepared.sources.profil; Path = $profil })) {
    if ((Get-FileHash -LiteralPath $binding.Path -Algorithm SHA256).Hash -ine [string]$binding.Record.sha256) { throw 'Private Quelle wurde nach der Vorbereitung verändert.' }
  }
  $warnings = @($prepared.layoutWarnings)
  $freigabeNotiz = [regex]::Replace(([string](Get-ContractJsonProperty $approval 'note')).Trim(), '\s+', ' ')
  if ($warnings.Count -gt 0 -and [string]::IsNullOrWhiteSpace($freigabeNotiz)) {
    throw 'Layoutwarnungen erfordern eine konkrete Notiz in der Chat-bestätigten Sichtfreigabe.'
  }
  $html = Get-Content -LiteralPath $htmlPath -Raw -Encoding UTF8
  Test-UniversalSectionPlan -Html $html -Order $order

  $alreadyActivated = $false
  if (Test-Path -LiteralPath (Join-Path $active 'Manifest.json') -PathType Leaf) {
    $currentManifest = $null
    try { $currentManifest = Get-Content -LiteralPath (Join-Path $active 'Manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $currentManifest = $null }
    $currentFiles = if ($null -eq $currentManifest) { @() } else { @($currentManifest.files) }
    $currentReview = Get-JsonProperty -Object $currentManifest -Name 'personalReview'
    $currentReviewConfirmed = Get-JsonProperty -Object $currentReview -Name 'confirmed'
    if ($null -ne $currentManifest -and [int]$currentManifest.schemaVersion -eq 1 -and [string]$currentManifest.auftragsart -ceq 'universal_lebenslauf' -and
        $currentReviewConfirmed -is [bool] -and [bool]$currentReviewConfirmed -and
        [string]$currentManifest.workId -ceq [string]$prepared.workId -and $currentFiles.Count -eq 2) {
      $expectedActiveHashes = @{
        "Intern/$expectedHtmlName" = (Get-FileHash -LiteralPath $htmlPath -Algorithm SHA256).Hash
        "Versand/$([IO.Path]::GetFileName($pdfPath))" = (Get-FileHash -LiteralPath $pdfPath -Algorithm SHA256).Hash
      }
      foreach ($record in $currentFiles) {
        $recordPath = ([string]$record.path).Replace('\', '/')
        if (-not $expectedActiveHashes.ContainsKey($recordPath) -or [string]$record.sha256 -ine [string]$expectedActiveHashes[$recordPath]) {
          throw 'Bereits aktive Dateien mit gleicher Arbeits-ID stimmen nicht mit dem vorbereiteten Kandidaten überein.'
        }
      }
      Test-ArtifactRecords -Records $currentFiles -Root $active
      $actualActivePaths = @(Get-ChildItem -LiteralPath $active -Recurse -File | Where-Object { $_.Name -cne 'Manifest.json' } | ForEach-Object { [IO.Path]::GetRelativePath($active, $_.FullName).Replace('\', '/') } | Sort-Object)
      if (($actualActivePaths -join "`n") -cne (($currentFiles.path | ForEach-Object { ([string]$_).Replace('\', '/') } | Sort-Object) -join "`n")) {
        throw 'Bereits aktive Fassung enthält nicht nachgewiesene Restdateien.'
      }
      $alreadyActivated = $true
    }
  }

  if (-not $alreadyActivated) {
    $stage = Resolve-SafePath -Candidate (Join-Path $namespace ('.publish-' + [guid]::NewGuid().ToString('N'))) -Root $applicationsRoot -ForWrite -PathType Container
    $backup = Resolve-SafePath -Candidate (Join-Path $namespace ('.backup-' + [guid]::NewGuid().ToString('N'))) -Root $applicationsRoot -ForWrite -PathType Container
    $activeMovedToBackup = $false
    $stageActivated = $false
    New-Item -Path (Join-Path $stage 'Versand') -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $stage 'Intern') -ItemType Directory -Force | Out-Null
    Copy-Item -LiteralPath $pdfPath -Destination (Join-Path (Join-Path $stage 'Versand') ([IO.Path]::GetFileName($pdfPath)))
    Copy-Item -LiteralPath $htmlPath -Destination (Join-Path (Join-Path $stage 'Intern') ([IO.Path]::GetFileName($htmlPath)))
    $publishedFiles = @(Get-ChildItem -LiteralPath $stage -Recurse -File | Sort-Object FullName | ForEach-Object { Get-ArtifactRecord -File $_ -Root $stage })
    $manifest = [ordered]@{
      schemaVersion = 1
      auftragsart = 'universal_lebenslauf'
      fachrichtung = 'softwareentwicklung'
      zielrollen = @('Frontend-Entwickler', 'Backend-Entwickler', 'Fullstack-Entwickler')
      activatedAtUtc = [datetime]::UtcNow.ToString('o')
      workId = [string]$prepared.workId
      personalReview = [ordered]@{ kind = 'png_sichtpruefung'; confirmed = $true; approvalId = [string](Get-ContractJsonProperty $approval 'approvalId'); note = $freigabeNotiz }
      layoutWarnings = $warnings
      sourceInputs = $prepared.sources
      files = $publishedFiles
    }
    Write-AtomicJson -Path (Join-Path $stage 'Manifest.json') -Value $manifest -Depth 10
    Test-ArtifactRecords -Records $publishedFiles -Root $stage

    if (Test-Path -LiteralPath $active) {
      if (-not $Ersetzen) { throw 'Es existiert bereits ein aktiver Universal-Lebenslauf; für eine bewusst neu geprüfte Fassung --ersetzen verwenden.' }
      Move-Item -LiteralPath $active -Destination $backup
      $activeMovedToBackup = $true
    }
    Move-Item -LiteralPath $stage -Destination $active
    $stageActivated = $true
    $activeManifest = Get-Content -LiteralPath (Join-Path $active 'Manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$activeManifest.workId -cne [string]$prepared.workId) { throw 'Aktives Manifest gehört nicht zum vorbereiteten Arbeitsstand.' }
    Test-ArtifactRecords -Records @($activeManifest.files) -Root $active
    if ((Test-Path -LiteralPath $backup) -and -not (Remove-DirectoryWithRetry -Path $backup -Root $applicationsRoot)) {
      throw 'Die gesicherte vorherige Aktivfassung konnte nach dem Austausch nicht entfernt werden.'
    }
  }
} catch {
  $activationError = $_.Exception.Message
  if (Get-Variable -Name stage -ErrorAction SilentlyContinue) {
    if ($null -ne $stage -and (Test-Path -LiteralPath $stage)) { $null = Remove-DirectoryWithRetry -Path $stage -Root $applicationsRoot }
  }
  if ((Get-Variable -Name stageActivated -ErrorAction SilentlyContinue) -and $stageActivated -and (Test-Path -LiteralPath $active)) {
    $null = Remove-DirectoryWithRetry -Path $active -Root $applicationsRoot
  }
  if ((Get-Variable -Name activeMovedToBackup -ErrorAction SilentlyContinue) -and $activeMovedToBackup -and
      (Get-Variable -Name backup -ErrorAction SilentlyContinue) -and $null -ne $backup -and
      (Test-Path -LiteralPath $backup) -and -not (Test-Path -LiteralPath $active)) {
    Move-Item -LiteralPath $backup -Destination $active -ErrorAction SilentlyContinue
  }
  Stop-UniversalFinalization "Aktivierung fehlgeschlagen: $activationError"
}

if (-not (Remove-DirectoryWithRetry -Path $work -Root $applicationsRoot)) {
  Stop-UniversalFinalization "Universal-Lebenslauf wurde aktiviert, aber der Arbeitsordner konnte nicht vollständig entfernt werden: $work"
}
if ((Test-Path -LiteralPath $workCollection -PathType Container) -and @(Get-ChildItem -LiteralPath $workCollection -Force).Count -eq 0) {
  Remove-Item -LiteralPath $workCollection -Force -ErrorAction SilentlyContinue
}
Write-Host "[OK] Universeller Lebenslauf aktiviert: $active" -ForegroundColor Green
Write-Host "Versand-PDF: $(Join-Path $active 'Versand' ([IO.Path]::GetFileName($pdfPath)))"
Write-Host 'Der zugehörige datierte Arbeitsordner wurde vollständig entfernt.'
