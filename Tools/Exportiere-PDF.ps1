#requires -Version 7.6
#requires -PSEdition Core

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Ordner,

  [string]$AuftragPath,

  [ValidateSet("auto", "chrome", "edge", "chromium")]
  [string]$Browser = "auto",

  [string]$BrowserExecutablePath,

  [switch]$MitLayoutcheck,

  [switch]$NichtUeberschreiben,

  [ValidateRange(100, 100000000)]
  [int]$MinPdfBytes = 5000,

  [ValidateRange(1, 600)]
  [int]$TimeoutSeconds = 60,

  [string]$OutputRoot,

  [string]$BerichtPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/Platform.psm1") -Force
$script:ToolTimeoutSeconds = [math]::Min(3600, [math]::Max(120, $TimeoutSeconds * 8))

function Add-Info {
  param([string]$Message)
  Write-Host "[INFO] $Message"
}

function Add-Ok {
  param([string]$Message)
  Write-Host "[OK] $Message" -ForegroundColor Green
}

function Add-Warn {
  param([string]$Message)
  Write-Host "[WARNUNG] $Message" -ForegroundColor Yellow
}

function Add-Fail {
  param([string]$Message)
  Write-Host "[FEHLER] $Message" -ForegroundColor Red
}

function Get-BewerbungenRootFromPath {
  param([Parameter(Mandatory)][string]$Path)

  $comparison = Get-PathStringComparison
  $current = [System.IO.Path]::GetFullPath($Path)
  while (-not [string]::IsNullOrWhiteSpace($current)) {
    $leaf = [System.IO.Path]::GetFileName($current.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar))
    $parent = [System.IO.Path]::GetDirectoryName($current)
    if ([string]::Equals($leaf, "Bewerbungen", $comparison) -and -not [string]::IsNullOrWhiteSpace($parent)) {
      $parentLeaf = [System.IO.Path]::GetFileName($parent.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar))
      if ([string]::Equals($parentLeaf, "Private", $comparison)) { return $current }
    }
    if ([string]::IsNullOrWhiteSpace($parent) -or [string]::Equals($parent, $current, $comparison)) { break }
    $current = $parent
  }
  throw "Pfad liegt nicht unter einem Private/Bewerbungen-Root: $Path"
}

function Convert-ToSafeFilePart {
  param([string]$Value)
  $safe = $Value -replace '[\\/:*?"<>|]+', '-'
  $safe = $safe -replace '\s+', '-'
  return $safe.Trim('-')
}

function Write-ExportReport {
  param(
    [string]$Path,
    [pscustomobject]$BrowserInfo,
    [array]$PdfSet
  )

  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $parent = Split-Path -Path $fullPath -Parent
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -Path $parent -ItemType Directory -Force | Out-Null
  }
  $items = @()
  foreach ($item in $PdfSet) {
    $pdfInfo = Get-Item -LiteralPath $item.FinalPath
    $items += [ordered]@{
      htmlFile = $item.HtmlFile.Name
      htmlSha256 = $item.HtmlSha256Snapshot
      pdfFile = [System.IO.Path]::GetFileName($item.FinalPath)
      pdfPath = $item.FinalPath
      pdfSha256 = (Get-FileHash -LiteralPath $item.FinalPath -Algorithm SHA256).Hash
      pdfBytes = $pdfInfo.Length
      pages = Get-PdfPageCount -Path $item.FinalPath
      mediaBox = Format-PdfMediaBoxSummary -Path $item.FinalPath
    }
  }
  $report = [ordered]@{
    schemaVersion = 1
    exportedAtUtc = [datetime]::UtcNow.ToString("o")
    runtime = Get-RuntimeFingerprint -BrowserInfo $BrowserInfo
    browser = $BrowserInfo.Name
    sourceFolder = $resolvedFolder
    results = $items
  }
  Set-Content -LiteralPath $fullPath -Encoding UTF8 -Value ($report | ConvertTo-Json -Depth 8)
}

function Get-HtmlSnapshotError {
  param(
    [System.IO.FileInfo]$HtmlFile,
    [string]$ExpectedSha256
  )

  if (-not (Test-Path -LiteralPath $HtmlFile.FullName -PathType Leaf)) {
    return "HTML-Datei fehlt seit Beginn des Exportlaufs: $($HtmlFile.FullName)"
  }
  try {
    $actualSha256 = (Get-FileHash -LiteralPath $HtmlFile.FullName -Algorithm SHA256).Hash
  } catch {
    return "HTML-Datei konnte nicht erneut gehasht werden: $($HtmlFile.FullName) ($($_.Exception.Message))"
  }
  if ($actualSha256 -ne $ExpectedSha256) {
    return "HTML-Datei wurde während des Exportlaufs verändert; PDF und Bericht wurden nicht veröffentlicht: $($HtmlFile.FullName)"
  }
  return $null
}

function Assert-PdfSetHtmlSnapshotsUnchanged {
  param([object[]]$PdfSet)

  foreach ($item in $PdfSet) {
    $snapshotError = Get-HtmlSnapshotError -HtmlFile $item.HtmlFile -ExpectedSha256 $item.HtmlSha256Snapshot
    if ($snapshotError) {
      throw $snapshotError
    }
  }
}

function Get-PowerShellExecutable {
  $currentProcess = Get-Process -Id $PID
  if ($currentProcess.Path -and (Test-Path -LiteralPath $currentProcess.Path -PathType Leaf)) {
    return $currentProcess.Path
  }

  $pwsh = Get-Command "pwsh" -ErrorAction SilentlyContinue
  if ($pwsh) {
    return $pwsh.Source
  }

  throw "PowerShell 7 Core wurde nicht gefunden."
}

function Invoke-ToolScript {
  param(
    [string]$ScriptPath,
    [string[]]$Arguments
  )

  $powerShellExe = Get-PowerShellExecutable
  Add-Info "Starte Tool: $ScriptPath"
  $nativeArguments = @("-NoLogo", "-NoProfile", "-NonInteractive", "-File", $ScriptPath) + @($Arguments)
  $result = Invoke-NativeProcess `
    -FilePath $powerShellExe `
    -ArgumentList $nativeArguments `
    -TimeoutSeconds $script:ToolTimeoutSeconds `
    -MaxStdoutChars 1048576 `
    -MaxStderrChars 1048576
  foreach ($line in @($result.StandardOutput -split '\r?\n' | Where-Object { $_.Length -gt 0 })) { Write-Host $line }
  foreach ($line in @($result.StandardError -split '\r?\n' | Where-Object { $_.Length -gt 0 })) { Write-Host $line }

  if ($result.TimedOut) {
    Add-Fail "Tool überschritt das Zeitlimit; der gesamte Prozessbaum wurde beendet: $ScriptPath"
    exit 1
  }
  if ($result.StdoutTruncated -or $result.StderrTruncated) {
    Add-Fail "Tool erzeugte mehr Ausgabe als sicher verarbeitet werden kann: $ScriptPath"
    exit 1
  }
  if ($result.ExitCode -ne 0) {
    Add-Fail "Tool fehlgeschlagen: $ScriptPath (Exitcode $($result.ExitCode))"
    exit ([int]$result.ExitCode)
  }
}

function Get-BrowserCandidates {
  param([string]$RequestedBrowser, [string]$ExecutablePath)
  return @(Platform\Get-BrowserCandidates -RequestedBrowser $RequestedBrowser -ExecutablePath $ExecutablePath -RequireChromium)
}

function Get-PdfMediaBoxes {
  param([string]$Path)

  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $text = [System.Text.Encoding]::ASCII.GetString($bytes)
  $pattern = '/MediaBox\s*\[\s*([-+]?[0-9]*\.?[0-9]+)\s+([-+]?[0-9]*\.?[0-9]+)\s+([-+]?[0-9]*\.?[0-9]+)\s+([-+]?[0-9]*\.?[0-9]+)\s*\]'
  $matches = [System.Text.RegularExpressions.Regex]::Matches($text, $pattern)
  $culture = [System.Globalization.CultureInfo]::InvariantCulture
  $boxes = @()

  foreach ($match in $matches) {
    $left = [double]::Parse($match.Groups[1].Value, $culture)
    $bottom = [double]::Parse($match.Groups[2].Value, $culture)
    $right = [double]::Parse($match.Groups[3].Value, $culture)
    $top = [double]::Parse($match.Groups[4].Value, $culture)
    $boxes += [pscustomobject]@{
      Left = $left
      Bottom = $bottom
      Right = $right
      Top = $top
      Width = [Math]::Abs($right - $left)
      Height = [Math]::Abs($top - $bottom)
    }
  }

  return $boxes
}

function Get-PdfPageCount {
  param([string]$Path)

  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $text = [System.Text.Encoding]::ASCII.GetString($bytes)
  return [regex]::Matches($text, '/Type\s*/Page(?!s)').Count
}

function Get-HtmlPageCount {
  param([string]$Path)

  $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
  return [regex]::Matches(
    $text,
    '<main\b(?=[^>]*\bclass\s*=\s*["''][^"'']*\bpage\b[^"'']*["''])[^>]*>',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
  ).Count
}

function Test-PdfA4MediaBox {
  param([string]$Path)

  $boxes = @(Get-PdfMediaBoxes -Path $Path)
  if ($boxes.Count -eq 0) {
    return "PDF enthält keine lesbare MediaBox: $Path"
  }

  foreach ($box in $boxes) {
    $isA4Portrait = ($box.Width -ge 590 -and $box.Width -le 600 -and $box.Height -ge 838 -and $box.Height -le 846)
    if (-not $isA4Portrait) {
      return ("PDF ist nicht DIN A4. MediaBox: {0:N2} x {1:N2} pt, erwartet ca. 595 x 842 pt: {2}" -f $box.Width, $box.Height, $Path)
    }
  }

  return $null
}

function Test-PdfFile {
  param(
    [string]$Path,
    [int]$MinBytes,
    [int]$ExpectedPageCount,
    [datetime]$RunStartedUtc
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return "PDF wurde nicht erzeugt: $Path"
  }

  $info = Get-Item -LiteralPath $Path
  if ($info.LastWriteTimeUtc -lt $RunStartedUtc.AddSeconds(-1)) {
    return "PDF ist älter als der aktuelle Browserlauf: $Path"
  }
  if ($info.Length -lt $MinBytes) {
    return "PDF ist zu klein ($($info.Length) Bytes): $Path"
  }

  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -lt 8 -or [System.Text.Encoding]::ASCII.GetString($bytes, 0, 5) -ne "%PDF-") {
    return "PDF-Datei hat keinen PDF-Header: $Path"
  }

  $tailLength = [Math]::Min(4096, $bytes.Length)
  $tail = [System.Text.Encoding]::ASCII.GetString($bytes, $bytes.Length - $tailLength, $tailLength)
  if ($tail -notmatch '%%EOF\s*$') {
    return "PDF-Datei hat keinen gültigen EOF-Marker: $Path"
  }

  $a4Error = Test-PdfA4MediaBox -Path $Path
  if ($a4Error) {
    return $a4Error
  }

  $actualPageCount = Get-PdfPageCount -Path $Path
  if ($actualPageCount -eq 0) {
    return "PDF-Seitenzahl konnte nicht zuverlässig gelesen werden: $Path"
  }
  if ($actualPageCount -ne $ExpectedPageCount) {
    return "PDF-Seitenzahl stimmt nicht mit dem HTML überein ($actualPageCount statt $ExpectedPageCount): $Path"
  }

  return $null
}

function Format-PdfMediaBoxSummary {
  param([string]$Path)

  $boxes = @(Get-PdfMediaBoxes -Path $Path)
  if ($boxes.Count -eq 0) {
    return $null
  }

  $first = $boxes[0]
  return ("{0:N2} x {1:N2} pt" -f $first.Width, $first.Height)
}

function Export-HtmlToPdf {
  param(
    [pscustomobject]$BrowserInfo,
    [System.IO.FileInfo]$HtmlFile,
    [string]$TemporaryPdfPath,
    [string]$BrowserTempRoot,
    [int]$MinPdfBytes,
    [int]$TimeoutSeconds
  )

  $browserRunRoot = Resolve-SafePath -Candidate (Join-Path -Path $BrowserTempRoot -ChildPath ("P-" + [guid]::NewGuid().ToString("N"))) -Root $BrowserTempRoot -ForWrite -PathType Container
  $profileDir = Join-Path -Path $browserRunRoot -ChildPath "profile"
  $browserPdfPath = Join-Path -Path $browserRunRoot -ChildPath "output.pdf"
  try {
    if (Test-Path -LiteralPath $TemporaryPdfPath) {
      Remove-Item -LiteralPath $TemporaryPdfPath -Force
    }
    New-Item -Path $browserRunRoot -ItemType Directory | Out-Null
    New-Item -Path $ProfileDir -ItemType Directory -Force | Out-Null

    $uri = [System.Uri]::new($HtmlFile.FullName).AbsoluteUri
    $arguments = @(
      "--headless=new",
      "--disable-gpu",
      "--disable-gpu-sandbox",
      "--no-sandbox",
      "--disable-dev-shm-usage",
      "--no-first-run",
      "--disable-background-networking",
      "--disable-extensions",
      "--user-data-dir=$ProfileDir",
      "--print-to-pdf=$browserPdfPath",
      "--print-to-pdf-no-header",
      "--no-pdf-header-footer",
      $uri
    )

    $runStartedUtc = [datetime]::UtcNow
    $process = Invoke-NativeProcess -FilePath $BrowserInfo.Path -ArgumentList $arguments -TimeoutSeconds $TimeoutSeconds -MaxStdoutChars 4096 -MaxStderrChars 8192
    if ($process.TimedOut) {
      return "Browser $($BrowserInfo.Name) überschritt das Zeitlimit von $TimeoutSeconds Sekunden für $($HtmlFile.Name)."
    }
    if ($process.ExitCode -ne 0) {
      $stderr = $process.StandardError.Trim()
      $suffix = if ([string]::IsNullOrWhiteSpace($stderr)) { "" } else { " stderr: $stderr" }
      return "Browser $($BrowserInfo.Name) beendete mit Exitcode $($process.ExitCode) für $($HtmlFile.Name).$suffix"
    }

    $expectedPageCount = Get-HtmlPageCount -Path $HtmlFile.FullName
    if ($expectedPageCount -eq 0) {
      return "HTML enthält keine expliziten A4-Seitencontainer: $($HtmlFile.Name)"
    }
    $pdfError = Test-PdfFile -Path $browserPdfPath -MinBytes $MinPdfBytes -ExpectedPageCount $expectedPageCount -RunStartedUtc $runStartedUtc
    if ($pdfError) { return $pdfError }
    Copy-Item -LiteralPath $browserPdfPath -Destination $TemporaryPdfPath
    return Test-PdfFile -Path $TemporaryPdfPath -MinBytes $MinPdfBytes -ExpectedPageCount $expectedPageCount -RunStartedUtc $runStartedUtc
  } catch {
    return $_.Exception.Message
  } finally {
    if (Test-Path -LiteralPath $browserRunRoot -PathType Container) {
      try {
        $safeBrowserRunRoot = Resolve-SafePath -Candidate $browserRunRoot -Root $BrowserTempRoot -MustExist -ForWrite -PathType Container
        Remove-Item -LiteralPath $safeBrowserRunRoot -Recurse -Force -ErrorAction SilentlyContinue
      } catch {
        Add-Warn "Temporärer Browserordner konnte nicht sicher bereinigt werden: $browserRunRoot"
      }
    }
  }
}

function Publish-PdfSet {
  param(
    [object[]]$PdfSet,
    [string]$RunDirectory,
    [string]$ReportPath,
    [string]$CandidateFolder,
    [string]$WorkDirectory,
    [pscustomobject]$BrowserInfo
  )

  $backups = New-Object System.Collections.Generic.List[object]
  $published = New-Object System.Collections.Generic.List[string]
  $reportFullPath = Resolve-SafePath -Candidate $ReportPath -Root $WorkDirectory -ForWrite -PathType Leaf
  $reportTemporaryPath = Join-Path -Path $RunDirectory -ChildPath ("Report--" + [guid]::NewGuid().ToString("N") + ".json")
  $reportBackupPath = Join-Path -Path $RunDirectory -ChildPath ("Backup--Report--" + [guid]::NewGuid().ToString("N") + ".json")
  $reportBackedUp = $false
  $reportPublished = $false
  try {
    Assert-PdfSetHtmlSnapshotsUnchanged -PdfSet $PdfSet

    foreach ($item in $PdfSet) {
      $item.FinalPath = Resolve-SafePath -Candidate $item.FinalPath -Root $CandidateFolder -ForWrite -PathType Leaf
      $item.TemporaryPath = Resolve-SafePath -Candidate $item.TemporaryPath -Root $RunDirectory -MustExist -ForWrite -PathType Leaf
      if (Test-Path -LiteralPath $item.FinalPath -PathType Leaf) {
        $backupPath = Join-Path -Path $RunDirectory -ChildPath ("Backup--" + [System.IO.Path]::GetFileName($item.FinalPath))
        Move-Item -LiteralPath $item.FinalPath -Destination $backupPath -Force
        $backups.Add([pscustomobject]@{ FinalPath = $item.FinalPath; BackupPath = $backupPath }) | Out-Null
      }
    }

    foreach ($item in $PdfSet) {
      Move-Item -LiteralPath $item.TemporaryPath -Destination $item.FinalPath -Force
      $published.Add($item.FinalPath) | Out-Null
    }

    Write-ExportReport -Path $reportTemporaryPath -BrowserInfo $BrowserInfo -PdfSet $PdfSet
    $preparedReport = Get-Content -LiteralPath $reportTemporaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$preparedReport.schemaVersion -ne 1 -or @($preparedReport.results).Count -ne $PdfSet.Count) {
      throw "Temporärer PDF-Export-Bericht ist unvollständig."
    }
    Assert-PdfSetHtmlSnapshotsUnchanged -PdfSet $PdfSet
    $reportFullPath = Resolve-SafePath -Candidate $reportFullPath -Root $WorkDirectory -ForWrite -PathType Leaf
    $reportParent = Split-Path -Path $reportFullPath -Parent
    if ((Test-Path -LiteralPath $reportFullPath) -and -not (Test-Path -LiteralPath $reportFullPath -PathType Leaf)) {
      throw "PDF-Export-Berichtspfad existiert, ist aber keine reguläre Datei: $reportFullPath"
    }
    if (-not (Test-Path -LiteralPath $reportParent -PathType Container)) {
      New-Item -Path $reportParent -ItemType Directory -Force | Out-Null
    }
    if (Test-Path -LiteralPath $reportFullPath -PathType Leaf) {
      Move-Item -LiteralPath $reportFullPath -Destination $reportBackupPath -Force
      $reportBackedUp = $true
    }
    Move-Item -LiteralPath $reportTemporaryPath -Destination $reportFullPath -Force
    $reportPublished = $true
  } catch {
    $publishError = $_.Exception.Message
    $rollbackErrors = New-Object System.Collections.Generic.List[string]
    if ($reportPublished -and (Test-Path -LiteralPath $reportFullPath -PathType Leaf)) {
      try { Remove-Item -LiteralPath $reportFullPath -Force } catch { $rollbackErrors.Add("neuer Bericht: $($_.Exception.Message)") | Out-Null }
    }
    if ($reportBackedUp -and (Test-Path -LiteralPath $reportBackupPath -PathType Leaf)) {
      try { Move-Item -LiteralPath $reportBackupPath -Destination $reportFullPath -Force } catch { $rollbackErrors.Add("alter Bericht: $($_.Exception.Message)") | Out-Null }
    }
    foreach ($path in $published) {
      if (Test-Path -LiteralPath $path -PathType Leaf) {
        try { Remove-Item -LiteralPath $path -Force } catch { $rollbackErrors.Add("neue PDF: $path ($($_.Exception.Message))") | Out-Null }
      }
    }
    foreach ($backup in $backups) {
      if (Test-Path -LiteralPath $backup.BackupPath -PathType Leaf) {
        try { Move-Item -LiteralPath $backup.BackupPath -Destination $backup.FinalPath -Force } catch { $rollbackErrors.Add("alte PDF: $($backup.FinalPath) ($($_.Exception.Message))") | Out-Null }
      }
    }
    if (Test-Path -LiteralPath $reportTemporaryPath -PathType Leaf) {
      try { Remove-Item -LiteralPath $reportTemporaryPath -Force } catch { $rollbackErrors.Add("temporärer Bericht: $($_.Exception.Message)") | Out-Null }
    }
    $rollbackSuffix = if ($rollbackErrors.Count -gt 0) { " Rollback unvollständig: $($rollbackErrors -join ' | ')" } else { " Alte PDFs und der vorherige Bericht wurden wiederhergestellt." }
    throw "PDF-/Berichtstransaktion fehlgeschlagen: $publishError.$rollbackSuffix"
  }

  foreach ($backupPath in @($backups | ForEach-Object { $_.BackupPath }) + @($reportBackupPath)) {
    if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
      try {
        Remove-Item -LiteralPath $backupPath -Force
      } catch {
        Add-Warn "PDF-Export war erfolgreich, aber eine Sicherungsdatei konnte nicht entfernt werden: $backupPath ($($_.Exception.Message))"
      }
    }
  }
}

function Remove-PdfRunDirectory {
  param([string]$Path, [string]$WorkDirectory)
  if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
  $safePath = Resolve-SafePath -Candidate $Path -Root $WorkDirectory -MustExist -ForWrite -PathType Container
  Remove-Item -LiteralPath $safePath -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path -LiteralPath $Ordner -PathType Container)) {
  Add-Fail "Ordner existiert nicht oder ist kein Verzeichnis: $Ordner"
  exit 1
}

$resolvedFolder = (Resolve-Path -LiteralPath $Ordner).Path
try {
  $applicationsRoot = Get-BewerbungenRootFromPath -Path $resolvedFolder
  $resolvedFolder = Resolve-SafePath -Candidate $resolvedFolder -Root $applicationsRoot -MustExist -PathType Container
} catch {
  Add-Fail $_.Exception.Message
  exit 2
}
$checkerPath = Join-Path -Path $PSScriptRoot -ChildPath "Pruefe-Bewerbung.ps1"
$layoutcheckPath = Join-Path -Path $PSScriptRoot -ChildPath "Layoutcheck-Bewerbung.ps1"

if (-not (Test-Path -LiteralPath $checkerPath -PathType Leaf)) {
  Add-Fail "Statischer Prüfer nicht gefunden: $checkerPath"
  exit 1
}

$checkerArguments = @("-Ordner", $resolvedFolder)
if (-not [string]::IsNullOrWhiteSpace($AuftragPath)) {
  $checkerArguments += @("-AuftragPath", $AuftragPath)
}
Invoke-ToolScript -ScriptPath $checkerPath -Arguments $checkerArguments

if ($MitLayoutcheck) {
  if (-not (Test-Path -LiteralPath $layoutcheckPath -PathType Leaf)) {
    Add-Fail "Layoutcheck-Tool nicht gefunden: $layoutcheckPath"
    exit 1
  }
  $layoutArguments = @("-Ordner", $resolvedFolder, "-Browser", $Browser, "-TimeoutSeconds", "$TimeoutSeconds")
  if (-not [string]::IsNullOrWhiteSpace($BrowserExecutablePath)) {
    $layoutArguments += @("-BrowserExecutablePath", $BrowserExecutablePath)
  }
  Invoke-ToolScript -ScriptPath $layoutcheckPath -Arguments $layoutArguments
}

$htmlFiles = @(Get-ChildItem -LiteralPath $resolvedFolder -File -Filter "*.html" | Where-Object {
  $_.Name -match '^(Lebenslauf|Anschreiben) - .+\.html$'
} | Sort-Object Name)
try {
  $htmlFiles = @($htmlFiles | ForEach-Object {
    $safeHtmlPath = Resolve-SafePath -Candidate $_.FullName -Root $resolvedFolder -MustExist -PathType Leaf
    Get-Item -LiteralPath $safeHtmlPath
  })
} catch {
  Add-Fail "Unsichere HTML-Quelldatei: $($_.Exception.Message)"
  exit 2
}

if ($htmlFiles.Count -lt 1 -or $htmlFiles.Count -gt 2) {
  Add-Fail "Es werden ein oder zwei laut Dokumentumfang ausgewählte finale HTML-Dateien erwartet; gefunden: $($htmlFiles.Count)."
  exit 1
}

$roleDir = Split-Path -Path $resolvedFolder -Leaf
$companyDir = Split-Path -Path $resolvedFolder -Parent
$companyName = Split-Path -Path $companyDir -Leaf
if ($companyName -eq "_Arbeitsdateien") {
  Add-Fail "Der angegebene Ordner scheint ein Arbeitsordner zu sein. Bitte finalen Bewerbungsordner angeben."
  exit 1
}

$workDir = if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $defaultWorkDir = Join-Path -Path $companyDir -ChildPath "_Arbeitsdateien"
  $defaultWorkDir = Join-Path -Path $defaultWorkDir -ChildPath $roleDir
  Join-Path -Path $defaultWorkDir -ChildPath "PDF-Export"
} else {
  [System.IO.Path]::GetFullPath($OutputRoot)
}
if (($workDir -notmatch '[\\/]Private[\\/]Bewerbungen[\\/]+') -or ($workDir -notmatch '[\\/]_Arbeitsdateien(?:[\\/]|$)')) {
  Add-Fail "PDF-Export-Arbeitsordner muss unter Private/Bewerbungen/.../_Arbeitsdateien liegen: $workDir"
  exit 1
}
try {
  $workDir = Resolve-SafePath -Candidate $workDir -Root $applicationsRoot -PathType Container
} catch {
  Add-Fail "Unsicherer PDF-Export-Arbeitsordner: $($_.Exception.Message)"
  exit 2
}
New-Item -Path $workDir -ItemType Directory -Force | Out-Null
try {
  $workDir = Resolve-SafePath -Candidate $workDir -Root $applicationsRoot -MustExist -ForWrite -PathType Container
} catch {
  Add-Fail "PDF-Export-Arbeitsordner ist nicht sicher beschreibbar: $($_.Exception.Message)"
  exit 2
}
if ([string]::IsNullOrWhiteSpace($BerichtPath)) {
  $BerichtPath = Join-Path -Path $workDir -ChildPath "PDF-Export-Bericht.json"
}
try {
  if ([System.IO.Path]::GetExtension($BerichtPath) -cne ".json") {
    throw "PDF-Export-Bericht muss eine JSON-Datei sein."
  }
  $BerichtPath = Resolve-SafePath -Candidate $BerichtPath -Root $workDir -ForWrite -PathType Leaf
} catch {
  Add-Fail "Unsicherer PDF-Export-Berichtspfad: $($_.Exception.Message)"
  exit 2
}

$finalPdfPaths = @($htmlFiles | ForEach-Object { [System.IO.Path]::ChangeExtension($_.FullName, ".pdf") })
for ($pdfIndex = 0; $pdfIndex -lt $finalPdfPaths.Count; $pdfIndex++) {
  try {
    $finalPdfPaths[$pdfIndex] = Resolve-SafePath -Candidate $finalPdfPaths[$pdfIndex] -Root $resolvedFolder -ForWrite -PathType Leaf
  } catch {
    Add-Fail "Unsicherer finaler PDF-Pfad: $($_.Exception.Message)"
    exit 2
  }
  $finalPdfPath = $finalPdfPaths[$pdfIndex]
  if ((Test-Path -LiteralPath $finalPdfPath) -and -not (Test-Path -LiteralPath $finalPdfPath -PathType Leaf)) {
    Add-Fail "Finaler PDF-Pfad existiert, ist aber keine reguläre Datei: $finalPdfPath"
    exit 1
  }
}
if ($NichtUeberschreiben) {
  $existing = @($finalPdfPaths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
  if ($existing.Count -gt 0) {
    Add-Fail "Mindestens eine PDF existiert bereits und `-NichtUeberschreiben` ist gesetzt: $($existing -join ', ')"
    exit 1
  }
}

$htmlSnapshots = @($htmlFiles | ForEach-Object {
  [pscustomobject]@{
    HtmlFile = $_
    Sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
  }
})
foreach ($snapshot in $htmlSnapshots) {
  if ($snapshot.Sha256 -notmatch '^[A-Fa-f0-9]{64}$') {
    Add-Fail "HTML-Datei konnte vor dem Browserlauf nicht mit gültigem SHA-256 gebunden werden: $($snapshot.HtmlFile.FullName)"
    exit 1
  }
}

Add-Info "Finaler Bewerbungsordner: $resolvedFolder"
Add-Info "PDF-Export-Arbeitsordner: $workDir"
Add-Info "HTML-Dateien: $($htmlFiles.Name -join ', ')"

$browserCandidates = @(Get-BrowserCandidates -RequestedBrowser $Browser -ExecutablePath $BrowserExecutablePath)
if ($browserCandidates.Count -eq 0) {
  Add-Fail "Kein Chromium-Browser gefunden. Unterstützt werden Chrome, Edge oder Chromium."
  exit 1
}

try {
  $browserTempRoot = Resolve-SafePath -Candidate (Join-Path -Path $applicationsRoot -ChildPath ".browser-tmp") -Root $applicationsRoot -ForWrite -PathType Container
  if (-not (Test-Path -LiteralPath $browserTempRoot)) {
    New-Item -Path $browserTempRoot -ItemType Directory | Out-Null
  }
  $browserTempRoot = Resolve-SafePath -Candidate $browserTempRoot -Root $applicationsRoot -MustExist -ForWrite -PathType Container
} catch {
  Add-Fail "Privater Browser-Temporärordner ist unsicher oder nicht anlegbar: $($_.Exception.Message)"
  exit 2
}

Add-Info "Browser-Kandidaten: $($browserCandidates.Name -join ', ')"
$browserErrors = New-Object System.Collections.Generic.List[string]

foreach ($candidate in $browserCandidates) {
  # Kurze interne Namen vermeiden Chromes Windows-Pfadgrenze bei tiefen
  # Bewerbungsordnern. Der Lauf bleibt durch die GUID trotzdem eindeutig.
  $runId = [guid]::NewGuid().ToString("N").Substring(0, 8)
  $runDir = Join-Path -Path $workDir -ChildPath "R-$runId"
  $runDir = Resolve-SafePath -Candidate $runDir -Root $workDir -ForWrite -PathType Container
  New-Item -Path $runDir -ItemType Directory -Force | Out-Null
  Add-Info "Teste PDF-Export mit Browser: $($candidate.Name) ($($candidate.Path))"

  $pdfSet = @()
  $candidateOk = $true
  foreach ($snapshot in $htmlSnapshots) {
    $html = $snapshot.HtmlFile
    $safeBase = Convert-ToSafeFilePart -Value $html.BaseName
    $temporaryPdfPath = Join-Path -Path $runDir -ChildPath "$safeBase.pdf"
    $finalPdfPath = Resolve-SafePath -Candidate ([System.IO.Path]::ChangeExtension($html.FullName, ".pdf")) -Root $resolvedFolder -ForWrite -PathType Leaf
    $errorMessage = Export-HtmlToPdf -BrowserInfo $candidate -HtmlFile $html -TemporaryPdfPath $temporaryPdfPath -BrowserTempRoot $browserTempRoot -MinPdfBytes $MinPdfBytes -TimeoutSeconds $TimeoutSeconds

    $snapshotError = Get-HtmlSnapshotError -HtmlFile $html -ExpectedSha256 $snapshot.Sha256
    if ($snapshotError) {
      $candidateOk = $false
      $browserErrors.Add("$($candidate.Name): $snapshotError") | Out-Null
      break
    }

    if ($errorMessage) {
      $candidateOk = $false
      $browserErrors.Add("$($candidate.Name): $errorMessage") | Out-Null
      break
    }

    $pdfSet += [pscustomobject]@{
      HtmlFile = $html
      HtmlSha256Snapshot = $snapshot.Sha256
      TemporaryPath = $temporaryPdfPath
      FinalPath = $finalPdfPath
    }
    $pdfInfo = Get-Item -LiteralPath $temporaryPdfPath
    Add-Ok "$($candidate.Name): temporäre PDF validiert: $($html.Name) ($($pdfInfo.Length) Bytes, $(Get-PdfPageCount -Path $temporaryPdfPath) Seite(n))"
  }

  if ($candidateOk -and ($pdfSet.Count -eq $htmlFiles.Count)) {
    try {
      Publish-PdfSet -PdfSet $pdfSet -RunDirectory $runDir -ReportPath $BerichtPath -CandidateFolder $resolvedFolder -WorkDirectory $workDir -BrowserInfo $candidate
      Add-Ok "PDF-Export vollständig und atomar veröffentlicht mit Browser: $($candidate.Name)"
      Write-Host ""
      Write-Host "Erzeugte PDFs:"
      foreach ($item in $pdfSet) {
        $pdfInfo = Get-Item -LiteralPath $item.FinalPath
        $mediaBoxSummary = Format-PdfMediaBoxSummary -Path $item.FinalPath
        Write-Host "- $($item.FinalPath) ($($pdfInfo.Length) Bytes, $(Get-PdfPageCount -Path $item.FinalPath) Seite(n), $mediaBoxSummary)"
      }
      Remove-PdfRunDirectory -Path $runDir -WorkDirectory $workDir
      Add-Ok "PDF-Export-Bericht geschrieben: $BerichtPath"
      Write-Host ""
      Write-Host "ERGEBNIS: OK" -ForegroundColor Green
      exit 0
    } catch {
      $recoveryFiles = @(Get-ChildItem -LiteralPath $runDir -File -Filter "Backup--*" -ErrorAction SilentlyContinue)
      if ($recoveryFiles.Count -eq 0) {
        Remove-PdfRunDirectory -Path $runDir -WorkDirectory $workDir
      } else {
        Add-Warn "Rollback-Sicherungen bleiben zur manuellen Wiederherstellung erhalten: $runDir"
      }
      Add-Fail "$($candidate.Name): Veröffentlichung der validierten PDFs fehlgeschlagen: $($_.Exception.Message)"
      exit 1
    }
  }

  Remove-PdfRunDirectory -Path $runDir -WorkDirectory $workDir
  Add-Warn "Browser $($candidate.Name) konnte kein vollständig validiertes PDF-Set erzeugen. Nächster Kandidat wird versucht."
}

foreach ($message in $browserErrors) {
  Add-Fail $message
}
Add-Fail "PDF-Export fehlgeschlagen: Kein Browser hat den laut Dokumentumfang ausgewählten PDF-Satz frisch, seitenrichtig und vollständig erzeugt."
exit 1
