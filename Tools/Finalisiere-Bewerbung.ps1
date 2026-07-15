[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Arbeitsordner,

  [ValidateSet("auto", "chrome", "edge")]
  [string]$Browser = "auto",

  [string]$StammdatenPath = (Join-Path -Path $PSScriptRoot -ChildPath "..\Private\Daten\01_PERSOENLICHE_DATEN.md"),

  [string]$ProfilPath = (Join-Path -Path $PSScriptRoot -ChildPath "..\Private\Daten\02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md"),

  [switch]$Veroeffentlichen,

  [switch]$VisuellGeprueft,

  [switch]$Ersetzen,

  [ValidateRange(1, 600)]
  [int]$TimeoutSeconds = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Stop-Finalization {
  param([string]$Message)
  Write-Host "[FEHLER] $Message" -ForegroundColor Red
  exit 1
}

function Add-Info {
  param([string]$Message)
  Write-Host "[INFO] $Message"
}

function Add-Ok {
  param([string]$Message)
  Write-Host "[OK] $Message" -ForegroundColor Green
}

function Test-IsSafeChildPath {
  param([string]$Candidate, [string]$Root)
  $candidateFull = [System.IO.Path]::GetFullPath($Candidate).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  return $candidateFull.StartsWith($rootFull + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-JsonProperty {
  param([object]$Object, [string]$Name)
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

function Invoke-ChildTool {
  param([string]$ScriptPath, [string[]]$Arguments)

  if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
    Stop-Finalization -Message "Werkzeug fehlt: $ScriptPath"
  }
  $powerShellExe = (Get-Process -Id $PID).Path
  $output = & $powerShellExe -NoProfile -File $ScriptPath @Arguments 2>&1
  foreach ($line in @($output)) { Write-Host $line }
  if ($LASTEXITCODE -ne 0) {
    Stop-Finalization -Message "Werkzeuglauf fehlgeschlagen: $([System.IO.Path]::GetFileName($ScriptPath))"
  }
}

function Update-TechnicalSection {
  param(
    [string]$QualityPath,
    [ValidateSet("vorbereitet", "bestaetigt")]
    [string]$State,
    [string]$LayoutReportPath,
    [string]$PdfReportPath
  )

  $visualLine = if ($State -eq "bestaetigt") {
    "- Visuelle Prüfung: bestätigt; die gerenderten A4-Seiten wurden auf Überlappungen, abgeschnittene Inhalte und problematische Leerflächen geprüft."
  } else {
    "- Visuelle Prüfung: noch nicht bestätigt; die Veröffentlichung bleibt bis zur Sichtprüfung gesperrt."
  }
  $section = @"
## Technischer Prüfbericht (automatisch)

- Stammdatenprüfung, statischer Strukturcheck und fachlicher Inhaltsabgleich: erfolgreich.
- Chrome-/Edge-Layoutcheck: frische Screenshots mit HTML-Hashnachweis erzeugt.
- PDF-Export: beide Versand-PDFs frisch erzeugt sowie auf Dateistruktur, Seitenzahl und DIN-A4-MediaBox geprüft.
$visualLine
- Maschinenlesbare Nachweise: Layoutcheck-Bericht und PDF-Export-Bericht im zugehörigen privaten Arbeitsordner.
"@

  $text = Get-Content -LiteralPath $QualityPath -Raw -Encoding UTF8
  $pattern = '(?ms)^## Technischer Prüfbericht \(automatisch\)\s*.*?(?=^## |\z)'
  if ([regex]::IsMatch($text, $pattern)) {
    $updated = [regex]::Replace($text, $pattern, $section.TrimEnd() + "`r`n`r`n")
  } else {
    $updated = $text.TrimEnd() + "`r`n`r`n" + $section.TrimEnd() + "`r`n"
  }
  Set-Content -LiteralPath $QualityPath -Encoding UTF8 -Value $updated
}

function Get-ArtifactRecord {
  param([System.IO.FileInfo]$File)
  return [ordered]@{
    name = $File.Name
    path = $File.FullName
    bytes = $File.Length
    sha256 = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash
  }
}

function Get-ReportArtifacts {
  param([string]$CandidateFolder, [string]$LayoutFolder)
  $html = @(Get-ChildItem -LiteralPath $CandidateFolder -File -Filter "*.html" | Sort-Object Name | ForEach-Object { Get-ArtifactRecord -File $_ })
  $pdf = @(Get-ChildItem -LiteralPath $CandidateFolder -File -Filter "*.pdf" | Sort-Object Name | ForEach-Object { Get-ArtifactRecord -File $_ })
  $screenshots = @(Get-ChildItem -LiteralPath $LayoutFolder -File -Filter "*.png" | Sort-Object Name | ForEach-Object { Get-ArtifactRecord -File $_ })
  return [ordered]@{ html = $html; pdf = $pdf; screenshots = $screenshots }
}

function Test-ArtifactSetUnchanged {
  param([array]$Records)
  foreach ($record in $Records) {
    $path = [string](Get-JsonProperty -Object $record -Name "path")
    $expectedHash = [string](Get-JsonProperty -Object $record -Name "sha256")
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
      Stop-Finalization -Message "Prüfartefakt fehlt seit der Vorbereitung: $path"
    }
    $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($actualHash -ne $expectedHash) {
      Stop-Finalization -Message "Prüfartefakt wurde nach der Vorbereitung verändert; erneute Vorbereitung erforderlich: $path"
    }
  }
}

if (-not (Test-Path -LiteralPath $Arbeitsordner -PathType Container)) {
  Stop-Finalization -Message "Arbeitsordner fehlt oder ist kein Verzeichnis: $Arbeitsordner"
}

$resolvedWork = (Resolve-Path -LiteralPath $Arbeitsordner).Path
if (($resolvedWork -notmatch '[\\/]Private[\\/]Bewerbungen[\\/]+') -or ($resolvedWork -notmatch '[\\/]_Arbeitsdateien[\\/]')) {
  Stop-Finalization -Message "Arbeitsordner muss unter Private/Bewerbungen/.../_Arbeitsdateien liegen: $resolvedWork"
}

$auftragPath = Join-Path -Path $resolvedWork -ChildPath "Bewerbungsauftrag.json"
$matrixPath = Join-Path -Path $resolvedWork -ChildPath "Anforderungsmatrix.json"
$candidateDir = Join-Path -Path $resolvedWork -ChildPath "Kandidat"
$layoutDir = Join-Path -Path $resolvedWork -ChildPath "Layoutcheck"
$pdfWorkDir = Join-Path -Path $resolvedWork -ChildPath "PDF-Export"
$layoutReportPath = Join-Path -Path $layoutDir -ChildPath "Layoutcheck-Bericht.json"
$pdfReportPath = Join-Path -Path $pdfWorkDir -ChildPath "PDF-Export-Bericht.json"
$finalReportPath = Join-Path -Path $resolvedWork -ChildPath "Finalisierungsbericht.json"

foreach ($requiredPath in @($auftragPath, $matrixPath, $candidateDir, $StammdatenPath, $ProfilPath)) {
  if (-not (Test-Path -LiteralPath $requiredPath)) {
    Stop-Finalization -Message "Erforderlicher Pfad fehlt: $requiredPath"
  }
}

$auftrag = Get-Content -LiteralPath $auftragPath -Raw -Encoding UTF8 | ConvertFrom-Json
$targetDir = [System.IO.Path]::GetFullPath([string](Get-JsonProperty -Object $auftrag -Name "zielOrdner"))
$manifestCandidate = [System.IO.Path]::GetFullPath([string](Get-JsonProperty -Object $auftrag -Name "kandidatOrdner"))
$companyDir = Split-Path -Path (Split-Path -Path $resolvedWork -Parent) -Parent
$expectedTarget = [System.IO.Path]::GetFullPath((Join-Path -Path $companyDir -ChildPath (Split-Path -Path $resolvedWork -Leaf)))
if ($manifestCandidate -ne [System.IO.Path]::GetFullPath($candidateDir)) {
  Stop-Finalization -Message "Kandidatenordner stimmt nicht mit dem Bewerbungsauftrag überein."
}
if ($targetDir -ne $expectedTarget -or -not (Test-IsSafeChildPath -Candidate $targetDir -Root $companyDir)) {
  Stop-Finalization -Message "Zielordner stimmt nicht mit der sicheren Projektstruktur überein."
}

$stammdatenTool = Join-Path -Path $PSScriptRoot -ChildPath "Pruefe-Stammdaten.ps1"
$staticTool = Join-Path -Path $PSScriptRoot -ChildPath "Pruefe-Bewerbung.ps1"
$contentTool = Join-Path -Path $PSScriptRoot -ChildPath "Pruefe-Bewerbungsinhalt.ps1"
$layoutTool = Join-Path -Path $PSScriptRoot -ChildPath "Layoutcheck-Bewerbung.ps1"
$exportTool = Join-Path -Path $PSScriptRoot -ChildPath "Exportiere-PDF.ps1"
$stammdatenReportPath = Join-Path -Path $resolvedWork -ChildPath "Stammdaten-Pruefbericht.json"
$contentReportPath = Join-Path -Path $resolvedWork -ChildPath "Inhalts-Pruefbericht.json"

if (-not $Veroeffentlichen) {
  Add-Info "Finalisierung wird vorbereitet: $resolvedWork"
  Invoke-ChildTool -ScriptPath $stammdatenTool -Arguments @("-StammdatenPath", $StammdatenPath, "-UngeklaerteLogistikAlsFehler", "-BerichtPath", $stammdatenReportPath)
  Invoke-ChildTool -ScriptPath $staticTool -Arguments @("-Ordner", $candidateDir)
  Invoke-ChildTool -ScriptPath $contentTool -Arguments @("-Ordner", $candidateDir, "-StammdatenPath", $StammdatenPath, "-ProfilPath", $ProfilPath, "-AuftragPath", $auftragPath, "-AnforderungsmatrixPath", $matrixPath, "-BerichtPath", $contentReportPath)
  Invoke-ChildTool -ScriptPath $layoutTool -Arguments @("-Ordner", $candidateDir, "-Browser", $Browser, "-TimeoutSeconds", "$TimeoutSeconds", "-OutputRoot", $layoutDir, "-BerichtPath", $layoutReportPath)
  Invoke-ChildTool -ScriptPath $exportTool -Arguments @("-Ordner", $candidateDir, "-Browser", $Browser, "-TimeoutSeconds", "$TimeoutSeconds", "-OutputRoot", $pdfWorkDir, "-BerichtPath", $pdfReportPath)

  $qualityPath = Join-Path -Path $candidateDir -ChildPath "Qualitaetscheck.md"
  if (-not (Test-Path -LiteralPath $qualityPath -PathType Leaf)) {
    Stop-Finalization -Message "Qualitaetscheck.md fehlt im Kandidatenordner."
  }
  Update-TechnicalSection -QualityPath $qualityPath -State "vorbereitet" -LayoutReportPath $layoutReportPath -PdfReportPath $pdfReportPath
  Invoke-ChildTool -ScriptPath $staticTool -Arguments @("-Ordner", $candidateDir)
  Invoke-ChildTool -ScriptPath $contentTool -Arguments @("-Ordner", $candidateDir, "-StammdatenPath", $StammdatenPath, "-ProfilPath", $ProfilPath, "-AuftragPath", $auftragPath, "-AnforderungsmatrixPath", $matrixPath, "-BerichtPath", $contentReportPath)

  $artifacts = Get-ReportArtifacts -CandidateFolder $candidateDir -LayoutFolder $layoutDir
  if ($artifacts.html.Count -ne 2 -or $artifacts.pdf.Count -ne 2 -or $artifacts.screenshots.Count -ne 2) {
    Stop-Finalization -Message "Vorbereitung erzeugte nicht genau zwei HTML-Dateien, zwei PDFs und zwei Screenshots."
  }
  $report = [ordered]@{
    schemaVersion = 1
    status = "bereit_zur_sichtpruefung"
    preparedAtUtc = [datetime]::UtcNow.ToString("o")
    workFolder = $resolvedWork
    candidateFolder = $candidateDir
    targetFolder = $targetDir
    layoutReport = $layoutReportPath
    pdfReport = $pdfReportPath
    artifacts = $artifacts
  }
  Set-Content -LiteralPath $finalReportPath -Encoding UTF8 -Value ($report | ConvertTo-Json -Depth 10)
  Add-Ok "Technische Vorbereitung erfolgreich."
  Write-Host ""
  Write-Host "Öffne jetzt die Screenshots unter: $layoutDir"
  Write-Host "Nach bestätigter Sichtprüfung veröffentlichen mit:"
  Write-Host ".\Tools\Finalisiere-Bewerbung.ps1 -Arbeitsordner `"$resolvedWork`" -Veroeffentlichen -VisuellGeprueft"
  exit 0
}

if (-not $VisuellGeprueft) {
  Stop-Finalization -Message "Veröffentlichung erfordert den Schalter -VisuellGeprueft nach tatsächlicher Sichtprüfung."
}
if (-not (Test-Path -LiteralPath $finalReportPath -PathType Leaf)) {
  Stop-Finalization -Message "Finalisierungsbericht fehlt. Zuerst Vorbereitung ohne -Veroeffentlichen ausführen."
}
$report = Get-Content -LiteralPath $finalReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string](Get-JsonProperty -Object $report -Name "status") -ne "bereit_zur_sichtpruefung") {
  Stop-Finalization -Message "Finalisierungsbericht befindet sich nicht im veröffentlichbaren Zustand."
}
Invoke-ChildTool -ScriptPath $stammdatenTool -Arguments @("-StammdatenPath", $StammdatenPath, "-UngeklaerteLogistikAlsFehler", "-BerichtPath", $stammdatenReportPath)
$artifactGroups = Get-JsonProperty -Object $report -Name "artifacts"
Test-ArtifactSetUnchanged -Records @((Get-JsonProperty -Object $artifactGroups -Name "html"))
Test-ArtifactSetUnchanged -Records @((Get-JsonProperty -Object $artifactGroups -Name "pdf"))
Test-ArtifactSetUnchanged -Records @((Get-JsonProperty -Object $artifactGroups -Name "screenshots"))

$qualityPath = Join-Path -Path $candidateDir -ChildPath "Qualitaetscheck.md"
Update-TechnicalSection -QualityPath $qualityPath -State "bestaetigt" -LayoutReportPath $layoutReportPath -PdfReportPath $pdfReportPath
Invoke-ChildTool -ScriptPath $staticTool -Arguments @("-Ordner", $candidateDir)
Invoke-ChildTool -ScriptPath $contentTool -Arguments @("-Ordner", $candidateDir, "-StammdatenPath", $StammdatenPath, "-ProfilPath", $ProfilPath, "-AuftragPath", $auftragPath, "-AnforderungsmatrixPath", $matrixPath, "-BerichtPath", $contentReportPath)

$allowedExtensions = @(".md", ".html", ".pdf")
$candidateFiles = @(Get-ChildItem -LiteralPath $candidateDir -File)
$unexpected = @($candidateFiles | Where-Object { $_.Extension -notin $allowedExtensions -or $_.Name -match 'ENTWURF|TODO' })
if ($unexpected.Count -gt 0) {
  Stop-Finalization -Message "Kandidatenordner enthält nicht veröffentlichbare Dateien: $($unexpected.Name -join ', ')"
}

$stageDir = Join-Path -Path $companyDir -ChildPath (".publish-" + [guid]::NewGuid().ToString("N"))
$backupDir = Join-Path -Path $companyDir -ChildPath (".backup-" + [guid]::NewGuid().ToString("N"))
if (-not (Test-IsSafeChildPath -Candidate $stageDir -Root $companyDir) -or -not (Test-IsSafeChildPath -Candidate $backupDir -Root $companyDir)) {
  Stop-Finalization -Message "Interne Veröffentlichungsordner liegen außerhalb des Firmenordners."
}

$targetBackedUp = $false
$targetWasEmpty = $false
try {
  New-Item -Path $stageDir -ItemType Directory | Out-Null
  foreach ($file in $candidateFiles) {
    Copy-Item -LiteralPath $file.FullName -Destination (Join-Path -Path $stageDir -ChildPath $file.Name)
  }
  Invoke-ChildTool -ScriptPath $staticTool -Arguments @("-Ordner", $stageDir)
  Invoke-ChildTool -ScriptPath $contentTool -Arguments @("-Ordner", $stageDir, "-StammdatenPath", $StammdatenPath, "-ProfilPath", $ProfilPath, "-AuftragPath", $auftragPath, "-AnforderungsmatrixPath", $matrixPath)

  if (Test-Path -LiteralPath $targetDir) {
    if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) {
      throw "Zielpfad ist kein Ordner: $targetDir"
    }
    $targetEntries = @(Get-ChildItem -LiteralPath $targetDir -Force)
    if ($targetEntries.Count -gt 0 -and -not $Ersetzen) {
      throw "Finaler Zielordner ist nicht leer. Verwende -Ersetzen nur für eine bewusst neu geprüfte Veröffentlichung."
    }
    if ($targetEntries.Count -gt 0) {
      Move-Item -LiteralPath $targetDir -Destination $backupDir
      $targetBackedUp = $true
    } else {
      $targetWasEmpty = $true
      Remove-Item -LiteralPath $targetDir -Force
    }
  }

  Move-Item -LiteralPath $stageDir -Destination $targetDir
  if ($targetBackedUp -and (Test-Path -LiteralPath $backupDir -PathType Container)) {
    Remove-Item -LiteralPath $backupDir -Recurse -Force
  }
} catch {
  if (Test-Path -LiteralPath $stageDir -PathType Container) {
    Remove-Item -LiteralPath $stageDir -Recurse -Force -ErrorAction SilentlyContinue
  }
  if ($targetBackedUp -and -not (Test-Path -LiteralPath $targetDir) -and (Test-Path -LiteralPath $backupDir -PathType Container)) {
    Move-Item -LiteralPath $backupDir -Destination $targetDir -ErrorAction SilentlyContinue
  } elseif ($targetWasEmpty -and -not (Test-Path -LiteralPath $targetDir)) {
    New-Item -Path $targetDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
  }
  Stop-Finalization -Message "Atomare Veröffentlichung fehlgeschlagen: $($_.Exception.Message)"
}

$report.status = "veroeffentlicht"
$report | Add-Member -NotePropertyName publishedAtUtc -NotePropertyValue ([datetime]::UtcNow.ToString("o")) -Force
$report | Add-Member -NotePropertyName publishedFolder -NotePropertyValue $targetDir -Force
Set-Content -LiteralPath $finalReportPath -Encoding UTF8 -Value ($report | ConvertTo-Json -Depth 10)
Add-Ok "Bewerbung vollständig und atomar veröffentlicht: $targetDir"
exit 0
