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

  [string]$VisuelleFreigabeNotiz,

  [switch]$Ersetzen,

  [ValidateRange(1, 600)]
  [int]$TimeoutSeconds = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

trap {
  Write-Host "[FEHLER] Unerwarteter Finalisierungsfehler: $($_.Exception.Message)" -ForegroundColor Red
  if (-not [string]::IsNullOrWhiteSpace($_.InvocationInfo.PositionMessage)) {
    Write-Host $_.InvocationInfo.PositionMessage
  }
  if (-not [string]::IsNullOrWhiteSpace($_.ScriptStackTrace)) {
    Write-Host $_.ScriptStackTrace
  }
  exit 1
}

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
  if ($null -eq $Object) { return $null }
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

function Update-TokenReportNonBlocking {
  param(
    [string]$ScriptPath,
    [string]$WorkFolder,
    [string]$ReportPath
  )

  $reference = [ordered]@{
    path = $ReportPath
    availability = "unavailable"
    purpose = "Diagnose- und Kostenartefakt; kein Qualitätsnachweis"
    blocksFinalization = $false
    includedInManifest = $false
  }
  if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
    Write-Host "[WARNUNG] Tokenbericht-Werkzeug fehlt; die Finalisierung wird dadurch nicht blockiert: $ScriptPath" -ForegroundColor Yellow
    return $reference
  }

  try {
    $powerShellExe = (Get-Process -Id $PID).Path
    $output = & $powerShellExe -NoProfile -File $ScriptPath -Arbeitsordner $WorkFolder -Messbereich "technische_vorbereitung" 2>&1
    foreach ($line in @($output)) { Write-Host $line }
    if ($LASTEXITCODE -ne 0) {
      Write-Host "[WARNUNG] Tokenbericht konnte nicht aktualisiert werden; die Finalisierung wird fortgesetzt." -ForegroundColor Yellow
      return $reference
    }
    if (Test-Path -LiteralPath $ReportPath -PathType Leaf) {
      $tokenReport = Get-Content -LiteralPath $ReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
      $reference.availability = [string](Get-JsonProperty -Object $tokenReport -Name "availability")
    }
  } catch {
    Write-Host "[WARNUNG] Tokenbericht konnte nicht gelesen werden; die Finalisierung wird fortgesetzt: $($_.Exception.Message)" -ForegroundColor Yellow
  }
  return $reference
}

function Update-TechnicalSection {
  param(
    [string]$QualityPath,
    [ValidateSet("vorbereitet", "bestaetigt")]
    [string]$State,
    [string]$LayoutReportPath,
    [string]$PdfReportPath,
    [string]$AtsReportPath,
    [array]$LayoutWarnings,
    [string]$VisualApprovalNote
  )

  $visualLine = if ($State -eq "bestaetigt") {
    $noteSuffix = if ([string]::IsNullOrWhiteSpace($VisualApprovalNote)) { "" } else { " Freigabenotiz: $VisualApprovalNote" }
    "- Visuelle Prüfung: bestätigt; jede gerenderte A4-Seite wurde auf Überlappungen, abgeschnittene Inhalte und problematische Leerflächen geprüft.$noteSuffix"
  } else {
    "- Visuelle Prüfung: noch nicht bestätigt; die Veröffentlichung bleibt bis zur Sichtprüfung gesperrt."
  }
  $warningLine = if (@($LayoutWarnings).Count -gt 0) {
    "- Automatische Layoutwarnungen: " + (@($LayoutWarnings) -join " | ")
  } else {
    "- Automatische Layoutwarnungen: keine."
  }
  $section = @"
## Technischer Prüfbericht (automatisch)

- Stammdatenprüfung, statischer Strukturcheck und fachlicher Inhaltsabgleich: erfolgreich.
- Chrome-/Edge-Layoutcheck: für jede explizite A4-Seite wurde ein frischer Screenshot mit HTML-Hashnachweis erzeugt.
- PDF-Export: beide Versand-PDFs frisch erzeugt sowie auf Dateistruktur, Seitenzahl und DIN-A4-MediaBox geprüft.
- ATS-Prüfung: Unicode-Textschicht, Pflichttexte, Textabdeckung und grundlegende Lesereihenfolge wurden geprüft.
$warningLine
$visualLine
- Maschinenlesbare Nachweise: Layoutcheck-, PDF-Export- und ATS-Prüfbericht im zugehörigen privaten Arbeitsordner.
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
  $candidate = @(Get-ChildItem -LiteralPath $CandidateFolder -File | Sort-Object Name | ForEach-Object { Get-ArtifactRecord -File $_ })
  return [ordered]@{ html = $html; pdf = $pdf; screenshots = $screenshots; candidate = $candidate }
}

function Get-ExpectedScreenshotCount {
  param([string]$CandidateFolder)
  $count = 0
  foreach ($html in Get-ChildItem -LiteralPath $CandidateFolder -File -Filter "*.html") {
    $text = Get-Content -LiteralPath $html.FullName -Raw -Encoding UTF8
    $count += [regex]::Matches($text, '(?is)<main\b[^>]*class\s*=\s*["''][^"'']*\bpage\b[^"'']*["'']').Count
  }
  return $count
}

function Get-LayoutWarnings {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
  $layout = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
  return @($layout.results | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.densityWarning) } | ForEach-Object {
    "$($_.htmlFile), Seite $($_.pageNumber) von $($_.pageCount): $($_.densityWarning)"
  })
}

function New-PublicationManifest {
  param([string]$Root, [object]$Auftrag, [object]$SourceInputs)
  $records = @()
  foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object { $_.Name -ne "Manifest.json" } | Sort-Object FullName) {
    $relative = [System.IO.Path]::GetRelativePath($Root, $file.FullName).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
    $records += [ordered]@{
      path = $relative
      bytes = $file.Length
      sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
  }
  $manifest = [ordered]@{
    schemaVersion = 1
    createdAtUtc = [datetime]::UtcNow.ToString("o")
    firma = [string](Get-JsonProperty -Object $Auftrag -Name "firma")
    rolle = [string](Get-JsonProperty -Object $Auftrag -Name "rolle")
    struktur = [ordered]@{
      versand = "nur PDF-Anlagen und E-Mail-Nachricht"
      intern = "HTML-Quellen, Analyse und Prüfdokumente"
    }
    sourceInputs = [ordered]@{}
    files = $records
  }
  if ($null -ne $SourceInputs) {
    foreach ($sourceProperty in $SourceInputs.PSObject.Properties) {
      $sourceRecord = $sourceProperty.Value
      $manifest.sourceInputs[$sourceProperty.Name] = [ordered]@{
        name = [System.IO.Path]::GetFileName([string](Get-JsonProperty -Object $sourceRecord -Name "path"))
        sha256 = [string](Get-JsonProperty -Object $sourceRecord -Name "sha256")
      }
    }
  }
  $manifestPath = Join-Path -Path $Root -ChildPath "Manifest.json"
  Set-Content -LiteralPath $manifestPath -Encoding UTF8 -Value ($manifest | ConvertTo-Json -Depth 8)
  return $manifestPath
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

function Test-ArtifactSetExact {
  param([array]$Records, [string]$Folder, [string]$Filter = "*")
  Test-ArtifactSetUnchanged -Records $Records
  $recordPaths = @($Records | ForEach-Object { [System.IO.Path]::GetFullPath([string](Get-JsonProperty -Object $_ -Name "path")) })
  $currentPaths = @(Get-ChildItem -LiteralPath $Folder -File -Filter $Filter | ForEach-Object { [System.IO.Path]::GetFullPath($_.FullName) })
  if ($recordPaths.Count -ne $currentPaths.Count) {
    Stop-Finalization -Message "Artefaktmenge wurde nach der Vorbereitung verändert: $Folder ($($recordPaths.Count) erwartet, $($currentPaths.Count) gefunden)."
  }
  foreach ($currentPath in $currentPaths) {
    if ($recordPaths -notcontains $currentPath) {
      Stop-Finalization -Message "Neues oder nicht geprüftes Artefakt seit der Vorbereitung gefunden: $currentPath"
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
$atsReportPath = Join-Path -Path $resolvedWork -ChildPath "ATS-Pruefbericht.json"
$finalReportPath = Join-Path -Path $resolvedWork -ChildPath "Finalisierungsbericht.json"
$tokenReportPath = Join-Path -Path $resolvedWork -ChildPath "Tokenverbrauch.json"

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
$atsTool = Join-Path -Path $PSScriptRoot -ChildPath "Pruefe-ATS.ps1"
$tokenReportTool = Join-Path -Path $PSScriptRoot -ChildPath "Aktualisiere-Tokenbericht.ps1"
$stammdatenReportPath = Join-Path -Path $resolvedWork -ChildPath "Stammdaten-Pruefbericht.json"
$contentReportPath = Join-Path -Path $resolvedWork -ChildPath "Inhalts-Pruefbericht.json"

if (-not $Veroeffentlichen) {
  Add-Info "Finalisierung wird vorbereitet: $resolvedWork"
  Invoke-ChildTool -ScriptPath $stammdatenTool -Arguments @("-StammdatenPath", $StammdatenPath, "-BewerbungsauftragPath", $auftragPath, "-UngeklaerteLogistikAlsFehler", "-BerichtPath", $stammdatenReportPath)
  Invoke-ChildTool -ScriptPath $staticTool -Arguments @("-Ordner", $candidateDir)
  Invoke-ChildTool -ScriptPath $contentTool -Arguments @("-Ordner", $candidateDir, "-StammdatenPath", $StammdatenPath, "-ProfilPath", $ProfilPath, "-AuftragPath", $auftragPath, "-AnforderungsmatrixPath", $matrixPath, "-BerichtPath", $contentReportPath)
  Invoke-ChildTool -ScriptPath $layoutTool -Arguments @("-Ordner", $candidateDir, "-Browser", $Browser, "-TimeoutSeconds", "$TimeoutSeconds", "-OutputRoot", $layoutDir, "-BerichtPath", $layoutReportPath)
  Invoke-ChildTool -ScriptPath $exportTool -Arguments @("-Ordner", $candidateDir, "-Browser", $Browser, "-TimeoutSeconds", "$TimeoutSeconds", "-OutputRoot", $pdfWorkDir, "-BerichtPath", $pdfReportPath)
  Invoke-ChildTool -ScriptPath $atsTool -Arguments @("-Ordner", $candidateDir, "-StammdatenPath", $StammdatenPath, "-AuftragPath", $auftragPath, "-BerichtPath", $atsReportPath)

  $qualityPath = Join-Path -Path $candidateDir -ChildPath "Qualitaetscheck.md"
  if (-not (Test-Path -LiteralPath $qualityPath -PathType Leaf)) {
    Stop-Finalization -Message "Qualitaetscheck.md fehlt im Kandidatenordner."
  }
  $layoutWarnings = @(Get-LayoutWarnings -Path $layoutReportPath)
  Update-TechnicalSection -QualityPath $qualityPath -State "vorbereitet" -LayoutReportPath $layoutReportPath -PdfReportPath $pdfReportPath -AtsReportPath $atsReportPath -LayoutWarnings $layoutWarnings -VisualApprovalNote ""
  Invoke-ChildTool -ScriptPath $staticTool -Arguments @("-Ordner", $candidateDir)
  Invoke-ChildTool -ScriptPath $contentTool -Arguments @("-Ordner", $candidateDir, "-StammdatenPath", $StammdatenPath, "-ProfilPath", $ProfilPath, "-AuftragPath", $auftragPath, "-AnforderungsmatrixPath", $matrixPath, "-BerichtPath", $contentReportPath)

  $artifacts = Get-ReportArtifacts -CandidateFolder $candidateDir -LayoutFolder $layoutDir
  $expectedScreenshots = Get-ExpectedScreenshotCount -CandidateFolder $candidateDir
  if ($artifacts.html.Count -ne 2 -or $artifacts.pdf.Count -ne 2 -or $artifacts.screenshots.Count -ne $expectedScreenshots) {
    Stop-Finalization -Message "Vorbereitung erzeugte nicht genau zwei HTML-Dateien, zwei PDFs und einen Screenshot pro A4-Seite (erwartet: $expectedScreenshots, erzeugt: $($artifacts.screenshots.Count))."
  }
  $tokenUsageReference = Update-TokenReportNonBlocking -ScriptPath $tokenReportTool -WorkFolder $resolvedWork -ReportPath $tokenReportPath
  $report = [ordered]@{
    schemaVersion = 3
    status = "bereit_zur_sichtpruefung"
    preparedAtUtc = [datetime]::UtcNow.ToString("o")
    workFolder = $resolvedWork
    candidateFolder = $candidateDir
    targetFolder = $targetDir
    layoutReport = $layoutReportPath
    pdfReport = $pdfReportPath
    atsReport = $atsReportPath
    expectedScreenshots = $expectedScreenshots
    layoutWarnings = $layoutWarnings
    tokenUsageReport = $tokenUsageReference
    sourceInputs = [ordered]@{
      stammdaten = Get-ArtifactRecord -File (Get-Item -LiteralPath $StammdatenPath)
      profil = Get-ArtifactRecord -File (Get-Item -LiteralPath $ProfilPath)
      bewerbungsauftrag = Get-ArtifactRecord -File (Get-Item -LiteralPath $auftragPath)
      anforderungsmatrix = Get-ArtifactRecord -File (Get-Item -LiteralPath $matrixPath)
    }
    artifacts = $artifacts
  }
  Set-Content -LiteralPath $finalReportPath -Encoding UTF8 -Value ($report | ConvertTo-Json -Depth 10)
  Add-Ok "Technische Vorbereitung erfolgreich."
  Write-Host ""
  Write-Host "Öffne jetzt die Screenshots unter: $layoutDir"
  if ($layoutWarnings.Count -gt 0) {
    Write-Host "Layoutwarnungen müssen visuell bewertet und bei der Veröffentlichung mit -VisuelleFreigabeNotiz begründet werden."
  }
  Write-Host "Nach bestätigter Sichtprüfung veröffentlichen mit:"
  $noteExample = if ($layoutWarnings.Count -gt 0) { ' -VisuelleFreigabeNotiz "Warnungen je Seite geprüft; kein Beschnitt und keine Überlappung."' } else { "" }
  Write-Host ".\Tools\Finalisiere-Bewerbung.ps1 -Arbeitsordner `"$resolvedWork`" -Veroeffentlichen -VisuellGeprueft$noteExample"
  exit 0
}

if (-not $VisuellGeprueft) {
  Stop-Finalization -Message "Veröffentlichung erfordert den Schalter -VisuellGeprueft nach tatsächlicher Sichtprüfung."
}
if (-not (Test-Path -LiteralPath $finalReportPath -PathType Leaf)) {
  Stop-Finalization -Message "Finalisierungsbericht fehlt. Zuerst Vorbereitung ohne -Veroeffentlichen ausführen."
}
$report = Get-Content -LiteralPath $finalReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
$reportSchema = [int](Get-JsonProperty -Object $report -Name "schemaVersion")
if ([string](Get-JsonProperty -Object $report -Name "status") -ne "bereit_zur_sichtpruefung") {
  Stop-Finalization -Message "Finalisierungsbericht befindet sich nicht im veröffentlichbaren Zustand."
}
if ([string](Get-JsonProperty -Object $report -Name "workFolder") -ne $resolvedWork -or
    [string](Get-JsonProperty -Object $report -Name "candidateFolder") -ne $candidateDir -or
    [string](Get-JsonProperty -Object $report -Name "targetFolder") -ne $targetDir) {
  Stop-Finalization -Message "Finalisierungsbericht gehört nicht zum aktuellen Arbeits- oder Zielordner."
}
$rawLayoutWarnings = Get-JsonProperty -Object $report -Name "layoutWarnings"
[array]$reportLayoutWarnings = @()
if ($null -ne $rawLayoutWarnings) { $reportLayoutWarnings = @($rawLayoutWarnings) }
if ($reportLayoutWarnings.Count -gt 0 -and [string]::IsNullOrWhiteSpace($VisuelleFreigabeNotiz)) {
  Stop-Finalization -Message "Automatische Layoutwarnungen liegen vor. Die Sichtprüfung muss mit -VisuelleFreigabeNotiz nachvollziehbar begründet werden."
}
$normalizedVisualNote = if ([string]::IsNullOrWhiteSpace($VisuelleFreigabeNotiz)) {
  ""
} else {
  ([regex]::Replace($VisuelleFreigabeNotiz.Trim(), '\s+', ' '))
}

Invoke-ChildTool -ScriptPath $stammdatenTool -Arguments @("-StammdatenPath", $StammdatenPath, "-BewerbungsauftragPath", $auftragPath, "-UngeklaerteLogistikAlsFehler", "-BerichtPath", $stammdatenReportPath)
$artifactGroups = Get-JsonProperty -Object $report -Name "artifacts"
$rawCandidateArtifacts = Get-JsonProperty -Object $artifactGroups -Name "candidate"
[array]$candidateArtifactRecords = @()
if ($null -ne $rawCandidateArtifacts) { $candidateArtifactRecords = @($rawCandidateArtifacts) }
if ($candidateArtifactRecords.Count -gt 0) {
  Test-ArtifactSetExact -Records $candidateArtifactRecords -Folder $candidateDir
} else {
  Test-ArtifactSetUnchanged -Records @((Get-JsonProperty -Object $artifactGroups -Name "html"))
  Test-ArtifactSetUnchanged -Records @((Get-JsonProperty -Object $artifactGroups -Name "pdf"))
}
$screenshotRecords = @((Get-JsonProperty -Object $artifactGroups -Name "screenshots"))
Test-ArtifactSetExact -Records $screenshotRecords -Folder $layoutDir -Filter "*.png"
$sourceInputs = Get-JsonProperty -Object $report -Name "sourceInputs"
if ($null -ne $sourceInputs) {
  $expectedSourcePaths = [ordered]@{
    stammdaten = [System.IO.Path]::GetFullPath($StammdatenPath)
    profil = [System.IO.Path]::GetFullPath($ProfilPath)
    bewerbungsauftrag = [System.IO.Path]::GetFullPath($auftragPath)
    anforderungsmatrix = [System.IO.Path]::GetFullPath($matrixPath)
  }
  foreach ($sourceProperty in $sourceInputs.PSObject.Properties) {
    if ($expectedSourcePaths.Contains($sourceProperty.Name)) {
      $preparedSourcePath = [System.IO.Path]::GetFullPath([string](Get-JsonProperty -Object $sourceProperty.Value -Name "path"))
      if ($preparedSourcePath -ne $expectedSourcePaths[$sourceProperty.Name]) {
        Stop-Finalization -Message "Beim Veröffentlichungslauf wurde eine andere Quelldatei übergeben: $($sourceProperty.Name)"
      }
    }
    Test-ArtifactSetUnchanged -Records @($sourceProperty.Value)
  }
}

$qualityPath = Join-Path -Path $candidateDir -ChildPath "Qualitaetscheck.md"
Update-TechnicalSection -QualityPath $qualityPath -State "bestaetigt" -LayoutReportPath $layoutReportPath -PdfReportPath $pdfReportPath -AtsReportPath $atsReportPath -LayoutWarnings $reportLayoutWarnings -VisualApprovalNote $normalizedVisualNote
Invoke-ChildTool -ScriptPath $staticTool -Arguments @("-Ordner", $candidateDir)
Invoke-ChildTool -ScriptPath $contentTool -Arguments @("-Ordner", $candidateDir, "-StammdatenPath", $StammdatenPath, "-ProfilPath", $ProfilPath, "-AuftragPath", $auftragPath, "-AnforderungsmatrixPath", $matrixPath, "-BerichtPath", $contentReportPath)
if ($reportSchema -ge 2) {
  Invoke-ChildTool -ScriptPath $atsTool -Arguments @("-Ordner", $candidateDir, "-StammdatenPath", $StammdatenPath, "-AuftragPath", $auftragPath, "-BerichtPath", $atsReportPath)
}

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
  $stageShippingDir = Join-Path -Path $stageDir -ChildPath "Versand"
  $stageInternalDir = Join-Path -Path $stageDir -ChildPath "Intern"
  New-Item -Path $stageShippingDir -ItemType Directory | Out-Null
  New-Item -Path $stageInternalDir -ItemType Directory | Out-Null
  foreach ($file in $candidateFiles) {
    $destinationFolder = if ($file.Extension -ieq ".pdf" -or $file.Name -match '^Email-Nachricht--.+\.md$') {
      $stageShippingDir
    } else {
      $stageInternalDir
    }
    Copy-Item -LiteralPath $file.FullName -Destination (Join-Path -Path $destinationFolder -ChildPath $file.Name)
  }
  $manifestPath = New-PublicationManifest -Root $stageDir -Auftrag $auftrag -SourceInputs $sourceInputs
  Invoke-ChildTool -ScriptPath $staticTool -Arguments @("-Ordner", $stageDir)
  Invoke-ChildTool -ScriptPath $contentTool -Arguments @("-Ordner", $stageDir, "-StammdatenPath", $StammdatenPath, "-ProfilPath", $ProfilPath, "-AuftragPath", $auftragPath, "-AnforderungsmatrixPath", $matrixPath)
  if ($reportSchema -ge 2) {
    Invoke-ChildTool -ScriptPath $atsTool -Arguments @("-Ordner", $stageDir, "-StammdatenPath", $StammdatenPath, "-AuftragPath", $auftragPath)
  }

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
$publishedManifestPath = Join-Path -Path $targetDir -ChildPath "Manifest.json"
$report | Add-Member -NotePropertyName publishedManifest -NotePropertyValue ([ordered]@{
  path = $publishedManifestPath
  sha256 = (Get-FileHash -LiteralPath $publishedManifestPath -Algorithm SHA256).Hash
}) -Force
$report | Add-Member -NotePropertyName visualApprovalNote -NotePropertyValue $normalizedVisualNote -Force
Set-Content -LiteralPath $finalReportPath -Encoding UTF8 -Value ($report | ConvertTo-Json -Depth 10)
Add-Ok "Bewerbung vollständig und atomar veröffentlicht: $targetDir"
Write-Host "Versandfertige Dateien: $(Join-Path -Path $targetDir -ChildPath 'Versand')"
exit 0
