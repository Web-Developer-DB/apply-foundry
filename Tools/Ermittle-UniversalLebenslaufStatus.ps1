#requires -Version 7.6
#requires -PSEdition Core

[CmdletBinding()]
param(
  [string]$Arbeitsordner,
  [string]$BewerbungenRoot = (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'Private', 'Bewerbungen'),
  [switch]$AlsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath 'Common/Platform.psm1') -Force

function Stop-UniversalStatus {
  param([string]$Message, [int]$Code = 1)
  Write-Host "[FEHLER] $Message" -ForegroundColor Red
  exit $Code
}

function Test-ActiveManifest {
  param([string]$ActiveFolder)
  $manifestPath = Join-Path $ActiveFolder 'Manifest.json'
  if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return $false }
  try {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$manifest.schemaVersion -ne 1 -or [string]$manifest.auftragsart -cne 'universal_lebenslauf' -or
        $manifest.personalReview.confirmed -isnot [bool] -or -not [bool]$manifest.personalReview.confirmed) { return $false }
    $records = @($manifest.files)
    $recordPaths = @($records | ForEach-Object { ([string]$_.path).Replace('\', '/') })
    $htmlRecord = @($records | Where-Object { ([string]$_.path).Replace('\', '/') -match '^Intern/Lebenslauf - [A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z0-9][A-Za-z0-9.-]*\.html$' })
    $pdfRecord = @($records | Where-Object { ([string]$_.path).Replace('\', '/') -match '^Versand/Lebenslauf - [A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z0-9][A-Za-z0-9.-]*\.pdf$' })
    if ($records.Count -ne 2 -or
        $htmlRecord.Count -ne 1 -or $pdfRecord.Count -ne 1 -or
        [IO.Path]::GetFileNameWithoutExtension([string]$htmlRecord[0].name) -cne [IO.Path]::GetFileNameWithoutExtension([string]$pdfRecord[0].name)) { return $false }
    foreach ($record in $records) {
      $relative = [string]$record.path
      if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $relative -match '(^|/|\\)\.\.($|/|\\)') { return $false }
      $path = Resolve-SafePath -Candidate (Join-Path $ActiveFolder $relative) -Root $ActiveFolder -MustExist -PathType Leaf
      $file = Get-Item -LiteralPath $path
      if ($file.Length -ne [long]$record.bytes -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine [string]$record.sha256) { return $false }
    }
    $actualPaths = @(Get-ChildItem -LiteralPath $ActiveFolder -Recurse -File | Where-Object { $_.Name -cne 'Manifest.json' } | ForEach-Object { [IO.Path]::GetRelativePath($ActiveFolder, $_.FullName).Replace('\', '/') } | Sort-Object)
    return (($actualPaths -join "`n") -ceq (($recordPaths | Sort-Object) -join "`n"))
  } catch {
    return $false
  }
}

$applicationsRoot = [IO.Path]::GetFullPath($BewerbungenRoot)
if (-not (Test-Path -LiteralPath $applicationsRoot -PathType Container)) { Stop-UniversalStatus 'Private/Bewerbungen existiert nicht.' }
$privateRoot = Split-Path -Path $applicationsRoot -Parent
if ((Split-Path -Path $applicationsRoot -Leaf) -cne 'Bewerbungen' -or (Split-Path -Path $privateRoot -Leaf) -cne 'Private') {
  Stop-UniversalStatus 'BewerbungenRoot muss auf einen Private/Bewerbungen-Ordner zeigen.' 2
}
$applicationsRoot = Resolve-SafePath -Candidate $applicationsRoot -Root $applicationsRoot -AllowRoot -MustExist -PathType Container
$namespace = Resolve-SafePath -Candidate (Join-Path $applicationsRoot '_Universal-Lebenslauf') -Root $applicationsRoot -PathType Container
$active = Resolve-SafePath -Candidate (Join-Path $namespace 'Aktiv') -Root $applicationsRoot -PathType Container
$workCollection = Resolve-SafePath -Candidate (Join-Path $namespace '_Arbeitsdateien') -Root $applicationsRoot -PathType Container

$work = $null
if (-not [string]::IsNullOrWhiteSpace($Arbeitsordner)) {
  try {
    $work = Resolve-SafePath -Candidate $Arbeitsordner -Root $applicationsRoot -MustExist -PathType Container
    if ((Split-Path (Split-Path $work -Parent) -Leaf) -cne '_Arbeitsdateien' -or (Split-Path (Split-Path (Split-Path $work -Parent) -Parent) -Leaf) -cne '_Universal-Lebenslauf') {
      throw 'Pfad gehört nicht zum Universal-Lebenslauf.'
    }
  } catch {
    Stop-UniversalStatus "Ungültiger Arbeitsordner: $($_.Exception.Message)" 2
  }
} elseif (Test-Path -LiteralPath $workCollection -PathType Container) {
  $candidates = @(Get-ChildItem -LiteralPath $workCollection -Directory | Sort-Object LastWriteTimeUtc -Descending)
  if ($candidates.Count -gt 0) { $work = $candidates[0].FullName }
}

$activeValid = (Test-Path -LiteralPath $active -PathType Container) -and (Test-ActiveManifest -ActiveFolder $active)
$activeWorkId = $null
if ($activeValid) {
  try { $activeWorkId = [string](Get-Content -LiteralPath (Join-Path $active 'Manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json).workId } catch { $activeWorkId = $null }
}
$phase = if ($null -ne $work) {
  if ($activeValid -and (Split-Path $work -Leaf) -ceq $activeWorkId) {
    'aktiv_bereinigung_ausstehend'
  } else {
  $reportPath = Join-Path $work 'Universal-Finalisierungsbericht.json'
  if (Test-Path -LiteralPath $reportPath -PathType Leaf) {
    try {
      $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
      if ([string]$report.status -ceq 'bereit_zur_sichtpruefung') { 'persoenliche_pruefung' } else { 'dokumenterstellung' }
    } catch { 'dokumenterstellung' }
  } else { 'dokumenterstellung' }
  }
} elseif ($activeValid) {
  'aktiv'
} elseif (Test-Path -LiteralPath $active -PathType Container) {
  'aktiv_ungueltig'
} else {
  'nicht_angelegt'
}
$nextAction = switch ($phase) {
  'persoenliche_pruefung' { 'Beide aktuellen PNG-Seiten persönlich prüfen und danach eindeutig aktivieren.' }
  'dokumenterstellung' { 'Kandidat und interne Nachweise fertigstellen, danach universal-finalisieren vorbereiten.' }
  'aktiv' { 'Keine Aktion erforderlich; aktive Quelle kann unverändert in Bewerbungen verwendet werden.' }
  'aktiv_bereinigung_ausstehend' { 'Aktivierung ist gültig; universal-finalisieren erneut mit denselben Freigabeparametern aufrufen, um nur den Arbeitsordner zu bereinigen.' }
  'aktiv_ungueltig' { 'Aktiver Manifest-Satz ist unvollständig oder verändert und muss neu erzeugt werden.' }
  default { 'Mit universal-neu einen neuen Universal-Lebenslauf-Arbeitsstand anlegen.' }
}
$result = [ordered]@{
  phase = $phase
  workFolder = $work
  activeFolder = if (Test-Path -LiteralPath $active -PathType Container) { $active } else { $null }
  activeManifestValid = $activeValid
  nextAction = $nextAction
}
if ($AlsJson) {
  $result | ConvertTo-Json -Depth 5
} else {
  Write-Host "[OK] Phase: $phase" -ForegroundColor Green
  if ($work) { Write-Host "Arbeitsordner: $work" }
  if (Test-Path -LiteralPath $active -PathType Container) { Write-Host "Aktiver Ordner: $active" }
  Write-Host "Nächster Schritt: $nextAction"
}
