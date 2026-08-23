#requires -Version 7.6
#requires -PSEdition Core

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Ordner,

  [ValidateSet("auto", "chrome", "edge", "chromium", "firefox")]
  [string]$Browser = "auto",

  [string]$BrowserExecutablePath,

  [switch]$NurVorbereiten,

  [switch]$Pdf,

  [switch]$ErlaubeFirefoxFallback,

  [ValidateRange(320, 10000)]
  [int]$Width = 794,

  [ValidateRange(320, 10000)]
  [int]$Height = 1123,

  [ValidateRange(1, 600)]
  [int]$TimeoutSeconds = 60,

  [string]$OutputRoot,

  [string]$BerichtPath,

  [switch]$DichtepruefungDeaktivieren
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/Platform.psm1") -Force
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/PngTools.psm1") -Force
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/AtomicFile.psm1") -Force
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/PdfPrintValidation.psm1") -Force

$a4Ratio = 210.0 / 297.0
if ([math]::Abs(($Width / [double]$Height) - $a4Ratio) -gt 0.01) {
  Write-Host "[FEHLER] Screenshot-Abmessungen müssen dem DIN-A4-Seitenverhältnis entsprechen: $Width x $Height." -ForegroundColor Red
  exit 2
}

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
      if ([string]::Equals($parentLeaf, "Private", $comparison)) {
        return $current
      }
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

function Get-BrowserCandidates {
  param(
    [string]$RequestedBrowser,
    [string]$ExecutablePath,
    [switch]$AllowFirefoxFallback
  )
  return @(Platform\Get-BrowserCandidates `
    -RequestedBrowser $RequestedBrowser `
    -ExecutablePath $ExecutablePath `
    -AllowFirefox:($AllowFirefoxFallback -or $RequestedBrowser -eq "firefox"))
}

function Test-PngFile {
  param(
    [string]$Path,
    [int]$ExpectedWidth,
    [int]$ExpectedHeight,
    [datetime]$RunStartedUtc
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return "Screenshot wurde nicht erzeugt: $Path"
  }

  $info = Get-Item -LiteralPath $Path
  if ($info.LastWriteTimeUtc -lt $RunStartedUtc.AddSeconds(-1)) {
    return "Screenshot ist älter als der aktuelle Browserlauf: $Path"
  }
  if ($info.Length -le 5000) {
    return "Screenshot ist zu klein ($($info.Length) Bytes): $Path"
  }

  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -lt 24) {
    return "Screenshot ist keine vollständige PNG-Datei: $Path"
  }

  $signature = @(137, 80, 78, 71, 13, 10, 26, 10)
  for ($index = 0; $index -lt $signature.Count; $index++) {
    if ($bytes[$index] -ne $signature[$index]) {
      return "Screenshot hat keine gültige PNG-Signatur: $Path"
    }
  }

  $actualWidth = ([int]$bytes[16] -shl 24) -bor ([int]$bytes[17] -shl 16) -bor ([int]$bytes[18] -shl 8) -bor [int]$bytes[19]
  $actualHeight = ([int]$bytes[20] -shl 24) -bor ([int]$bytes[21] -shl 16) -bor ([int]$bytes[22] -shl 8) -bor [int]$bytes[23]
  if (($actualWidth -ne $ExpectedWidth) -or ($actualHeight -ne $ExpectedHeight)) {
    return "Screenshot hat unerwartete Abmessungen ($actualWidth x $actualHeight statt $ExpectedWidth x $ExpectedHeight): $Path"
  }

  return $null
}

function Test-BasicPdfFile {
  param(
    [string]$Path,
    [datetime]$RunStartedUtc
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return "PDF wurde nicht erzeugt: $Path"
  }
  $info = Get-Item -LiteralPath $Path
  if ($info.LastWriteTimeUtc -lt $RunStartedUtc.AddSeconds(-1)) {
    return "PDF ist älter als der aktuelle Browserlauf: $Path"
  }
  if ($info.Length -le 5000) {
    return "PDF ist zu klein ($($info.Length) Bytes): $Path"
  }
  $stream = [System.IO.File]::OpenRead($Path)
  try {
    $buffer = New-Object byte[] 5
    $read = $stream.Read($buffer, 0, 5)
    if ([System.Text.Encoding]::ASCII.GetString($buffer, 0, $read) -ne "%PDF-") {
      return "Datei hat keinen PDF-Header: $Path"
    }
  } finally {
    $stream.Dispose()
  }
  return $null
}

function Get-HtmlPageMatches {
  param([string]$Html)

  return [regex]::Matches(
    $Html,
    '(?is)<main\b(?=[^>]*\bclass\s*=\s*["''][^"'']*\bpage\b[^"'']*["''])[^>]*>(?<body>.*?)</main\s*>'
  )
}

function New-PageCaptureHtml {
  param(
    [System.IO.FileInfo]$HtmlFile,
    [Parameter(Mandatory)][string]$HtmlText,
    [int]$PageNumber,
    [string]$TargetPath
  )

  $html = $HtmlText
  $pageMatches = @(Get-HtmlPageMatches -Html $html)
  if ($PageNumber -lt 1 -or $PageNumber -gt $pageMatches.Count) {
    throw "A4-Seite $PageNumber ist in $($HtmlFile.Name) nicht vorhanden."
  }
  $selectedPage = $pageMatches[$PageNumber - 1].Value
  $captureCss = @"
<style id="layoutcheck-page-capture">
  html, body {
    width: 210mm !important;
    height: 297mm !important;
    min-height: 297mm !important;
    margin: 0 !important;
    padding: 0 !important;
    overflow: hidden !important;
    background: #fff !important;
  }
  body > main.page {
    width: 210mm !important;
    height: 297mm !important;
    margin: 0 !important;
    box-shadow: none !important;
    break-after: auto !important;
    break-before: auto !important;
  }
</style>
"@
  $geometryScript = @"
<script id="layoutcheck-geometry-audit">
(() => {
  const page = document.querySelector('body > main.page');
  const result = { available: true, pageOverflowX: false, pageOverflowY: false, outsideElements: [], pageClientWidth: 0, pageClientHeight: 0, pageScrollWidth: 0, pageScrollHeight: 0 };
  if (!page) {
    result.available = false;
    result.error = 'isolierter page-Container fehlt';
  } else {
    const pageRect = page.getBoundingClientRect();
    result.pageClientWidth = page.clientWidth;
    result.pageClientHeight = page.clientHeight;
    result.pageScrollWidth = page.scrollWidth;
    result.pageScrollHeight = page.scrollHeight;
    result.pageOverflowX = page.scrollWidth > page.clientWidth + 1;
    result.pageOverflowY = page.scrollHeight > page.clientHeight + 1;
    for (const element of Array.from(page.querySelectorAll('*'))) {
      if (['SCRIPT', 'STYLE', 'META', 'LINK'].includes(element.tagName)) continue;
      const style = window.getComputedStyle(element);
      if (style.display === 'none' || style.visibility === 'hidden') continue;
      const rect = element.getBoundingClientRect();
      if (rect.width <= 0 || rect.height <= 0) continue;
      if (rect.left < pageRect.left - 1 || rect.top < pageRect.top - 1 || rect.right > pageRect.right + 1 || rect.bottom > pageRect.bottom + 1) {
        result.outsideElements.push({ tag: element.tagName.toLowerCase(), left: Math.round(rect.left - pageRect.left), top: Math.round(rect.top - pageRect.top), right: Math.round(rect.right - pageRect.left), bottom: Math.round(rect.bottom - pageRect.top) });
        if (result.outsideElements.length >= 12) break;
      }
    }
  }
  document.documentElement.setAttribute('data-layoutcheck-geometry-b64', btoa(JSON.stringify(result)));
})();
</script>
"@

  if ($html -notmatch '(?is)</head\s*>') {
    throw "HTML enthält kein schließendes head-Element: $($HtmlFile.Name)"
  }
  $captureHtml = [regex]::Replace($html, '(?is)</head\s*>', $captureCss + "`r`n</head>", 1)
  $bodyPattern = [regex]::new('(?is)(?<open><body\b[^>]*>).*?(?<close></body\s*>)')
  if (-not $bodyPattern.IsMatch($captureHtml)) {
    throw "HTML enthält kein vollständiges body-Element: $($HtmlFile.Name)"
  }
  $captureHtml = $bodyPattern.Replace(
    $captureHtml,
    [System.Text.RegularExpressions.MatchEvaluator]{
      param($match)
      return $match.Groups['open'].Value + "`r`n" + $selectedPage + "`r`n" + $geometryScript + "`r`n" + $match.Groups['close'].Value
    },
    1
  )
  Write-AtomicText -Path $TargetPath -Content $captureHtml
}

function Remove-TemporaryDirectoryWithRetry {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Root,
    [int]$Attempts = 5
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $true }
  for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
    try {
      $safePath = Resolve-SafePath -Candidate $Path -Root $Root -MustExist -ForWrite -PathType Container
      Remove-Item -LiteralPath $safePath -Recurse -Force -ErrorAction Stop
    } catch {
      if ($attempt -lt $Attempts) { Start-Sleep -Milliseconds 200 }
    }
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
  }
  return $false
}

function Get-HtmlSnapshotError {
  param(
    [System.IO.FileInfo]$HtmlFile,
    [string]$ExpectedSha256
  )

  if (-not (Test-Path -LiteralPath $HtmlFile.FullName -PathType Leaf)) {
    return "HTML-Datei fehlt seit Beginn des Layoutchecks: $($HtmlFile.FullName)"
  }
  $actualSha256 = (Get-FileHash -LiteralPath $HtmlFile.FullName -Algorithm SHA256).Hash
  if ($actualSha256 -ine $ExpectedSha256) {
    return "HTML-Datei wurde während des Layoutchecks geändert: $($HtmlFile.FullName)"
  }
  return $null
}

function Get-LayoutDensity {
  param(
    [string]$Path,
    [string]$DocumentName,
    [int]$ExpectedHeight,
    [int]$PageNumber,
    [int]$PageCount,
    [double]$BottomReserveMm
  )

  return PngTools\Measure-PngBottomWhitespace `
    -LiteralPath $Path `
    -DocumentName $DocumentName `
    -PageNumber $PageNumber `
    -PageCount $PageCount `
    -BottomReserveMm $BottomReserveMm
}

function Get-AdjacentPagePrintDiagnostics {
  param([Parameter(Mandatory)][string]$HtmlText)

  $diagnostics = [System.Collections.Generic.List[string]]::new()
  $selectorMatches = [regex]::Matches($HtmlText, '(?is)\.page\s*\+\s*\.page\s*\{(?<rules>[^}]*)\}')
  foreach ($match in $selectorMatches) {
    $rules = [string]$match.Groups['rules'].Value
    if ($rules -match '(?i)margin(?:-top)?\s*:\s*(?!0(?:[a-z%]+)?\s*(?:;|$))[^;}]+' -or $rules -match '(?i)padding-top\s*:\s*(?!0(?:[a-z%]+)?\s*(?:;|$))[^;}]+') {
      $diagnostics.Add('Seitenabstand über `.page + .page` gefunden. Vertikale Vorschauabstände müssen in `@media screen` stehen oder im Druckmodus mit demselben Selektor explizit auf 0 zurückgesetzt werden.')
    }
  }
  return @($diagnostics | Select-Object -Unique)
}

function Write-LayoutReport {
  param(
    [string]$Path,
    [pscustomobject]$BrowserInfo,
    [array]$Results,
    [array]$DocumentPreflights,
    [int]$ExpectedWidth,
    [int]$ExpectedHeight
  )

  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $parent = Split-Path -Path $fullPath -Parent
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -Path $parent -ItemType Directory -Force | Out-Null
  }
  $report = [ordered]@{
    schemaVersion = 3
    checkedAtUtc = [datetime]::UtcNow.ToString("o")
    runtime = Get-RuntimeFingerprint -BrowserInfo $BrowserInfo
    browser = $BrowserInfo.Name
    sourceFolder = $resolvedFolder
    captureMode = "eine_png_pro_a4_seite"
    pageWidth = $ExpectedWidth
    pageHeight = $ExpectedHeight
    expectedScreenshots = @($Results).Count
    printPreflight = [ordered]@{
      mode = "vollstaendiges_original_html"
      documents = @($DocumentPreflights)
    }
    results = $Results
  }
  Write-AtomicJson -Path $fullPath -Value $report -Depth 8
}

function Invoke-BrowserScreenshot {
  param(
    [pscustomobject]$BrowserInfo,
    [System.IO.FileInfo]$SourceHtmlFile,
    [System.IO.FileInfo]$CaptureHtmlFile,
    [string]$OutputBaseName,
    [int]$PageNumber,
    [int]$PageCount,
    [string]$TargetDir,
    [string]$BrowserTempRoot,
    [string]$RunId,
    [int]$Width,
    [int]$Height,
    [int]$TimeoutSeconds,
    [switch]$Pdf
  )

  $safeBase = Convert-ToSafeFilePart -Value $OutputBaseName
  $pagePart = "seite-$PageNumber-von-$PageCount"
  $pngPath = Join-Path -Path $TargetDir -ChildPath "$safeBase--$pagePart--$($BrowserInfo.Name).png"
  $pdfPath = Join-Path -Path $TargetDir -ChildPath "$safeBase--$pagePart--$($BrowserInfo.Name).pdf"
  $browserRunRoot = Resolve-SafePath -Candidate (Join-Path -Path $BrowserTempRoot -ChildPath ("L-" + $RunId)) -Root $BrowserTempRoot -ForWrite -PathType Container
  $profilePath = Join-Path -Path $browserRunRoot -ChildPath "profile"
  $browserHtmlPath = Join-Path -Path $browserRunRoot -ChildPath "capture.html"
  $browserPngPath = Join-Path -Path $browserRunRoot -ChildPath "capture.png"
  $browserPdfPath = Join-Path -Path $browserRunRoot -ChildPath "capture.pdf"
  $pendingPngPath = "$pngPath.pending-$RunId"
  $pendingPdfPath = "$pdfPath.pending-$RunId"

  $result = [pscustomobject]@{
    Browser = $BrowserInfo.Name
    File = $SourceHtmlFile.Name
    PageNumber = $PageNumber
    PageCount = $PageCount
    ExitCode = $null
    TimedOut = $false
    ErrorMessage = $null
    Screenshot = $pngPath
    ScreenshotOk = $false
    Pdf = $pdfPath
    PdfOk = $false
  }

  try {
    foreach ($oldOutput in @($pngPath, $pdfPath, $pendingPngPath, $pendingPdfPath)) {
      $oldOutput = Resolve-SafePath -Candidate $oldOutput -Root $TargetDir -ForWrite -PathType Leaf
      if (Test-Path -LiteralPath $oldOutput) {
        Remove-Item -LiteralPath $oldOutput -Force
      }
      if (Test-Path -LiteralPath $oldOutput) {
        throw "Alte Ausgabedatei konnte nicht entfernt werden: $oldOutput"
      }
    }

    New-Item -Path $browserRunRoot -ItemType Directory | Out-Null
    New-Item -Path $profilePath -ItemType Directory | Out-Null
    Copy-Item -LiteralPath $CaptureHtmlFile.FullName -Destination $browserHtmlPath
    $uri = [System.Uri]::new($browserHtmlPath).AbsoluteUri

    if ($BrowserInfo.Engine -eq "chromium") {
      $arguments = @(
        "--headless=new",
        "--disable-gpu",
        "--disable-dev-shm-usage",
        "--no-first-run",
        "--disable-background-networking",
        "--disable-extensions",
        "--hide-scrollbars",
        "--user-data-dir=$profilePath",
        "--window-size=$Width,$Height",
        "--screenshot=$browserPngPath"
      )

      if ($Pdf) {
        $arguments += "--print-to-pdf=$browserPdfPath"
        $arguments += "--print-to-pdf-no-header"
        $arguments += "--no-pdf-header-footer"
      }
      $arguments += $uri
    } else {
      $arguments = @(
        "--headless",
        "--profile",
        $profilePath,
        "--window-size",
        "$Width,$Height",
        "--screenshot",
        $browserPngPath,
        $uri
      )
    }

    $runStartedUtc = [datetime]::UtcNow
    $process = Invoke-NativeProcess -FilePath $BrowserInfo.Path -ArgumentList $arguments -TimeoutSeconds $TimeoutSeconds -MaxStdoutChars 4096 -MaxStderrChars 8192
    if ($process.TimedOut) {
      $result.TimedOut = $true
      $result.ErrorMessage = "Browserlauf hat das Zeitlimit von $TimeoutSeconds Sekunden überschritten."
      return $result
    }

    $result.ExitCode = $process.ExitCode
    if ($process.ExitCode -ne 0) {
      $stderr = $process.StandardError.Trim()
      $suffix = if ([string]::IsNullOrWhiteSpace($stderr)) { "" } else { " stderr: $stderr" }
      $result.ErrorMessage = "Browser beendete den Lauf mit Exitcode $($process.ExitCode).$suffix"
      return $result
    }

    $pngError = Test-PngFile -Path $browserPngPath -ExpectedWidth $Width -ExpectedHeight $Height -RunStartedUtc $runStartedUtc
    if ($pngError) {
      $result.ErrorMessage = $pngError
      return $result
    }
    Copy-Item -LiteralPath $browserPngPath -Destination $pendingPngPath
    Move-Item -LiteralPath $pendingPngPath -Destination $pngPath
    $pngError = Test-PngFile -Path $pngPath -ExpectedWidth $Width -ExpectedHeight $Height -RunStartedUtc $runStartedUtc
    if ($pngError) {
      $result.ErrorMessage = $pngError
      return $result
    }
    $result.ScreenshotOk = $true

    if ($Pdf) {
      if ($BrowserInfo.Engine -ne "chromium") {
        $result.ErrorMessage = "PDF-Export ist für Browser $($BrowserInfo.Name) nicht unterstützt."
        return $result
      }
      $pdfError = Test-BasicPdfFile -Path $browserPdfPath -RunStartedUtc $runStartedUtc
      if ($pdfError) {
        $result.ErrorMessage = $pdfError
        return $result
      }
      Copy-Item -LiteralPath $browserPdfPath -Destination $pendingPdfPath
      Move-Item -LiteralPath $pendingPdfPath -Destination $pdfPath
      $pdfError = Test-BasicPdfFile -Path $pdfPath -RunStartedUtc $runStartedUtc
      if ($pdfError) {
        $result.ErrorMessage = $pdfError
        return $result
      }
      $result.PdfOk = $true
    }
  } catch {
    $result.ErrorMessage = $_.Exception.Message
  } finally {
    foreach ($pendingPath in @($pendingPngPath, $pendingPdfPath)) {
      if (Test-Path -LiteralPath $pendingPath -PathType Leaf) {
        Remove-Item -LiteralPath $pendingPath -Force -ErrorAction SilentlyContinue
      }
    }
    if (-not (Remove-TemporaryDirectoryWithRetry -Path $browserRunRoot -Root $BrowserTempRoot)) {
      Add-Warn "Temporärer Browserordner konnte nicht vollständig bereinigt werden: $browserRunRoot"
    }
  }

  return $result
}

function Invoke-BrowserGeometryAudit {
  param(
    [pscustomobject]$BrowserInfo,
    [System.IO.FileInfo]$CaptureHtmlFile,
    [string]$BrowserTempRoot,
    [string]$RunId,
    [int]$Width,
    [int]$Height,
    [int]$TimeoutSeconds
  )

  $result = [pscustomobject]@{ Available = $false; ErrorMessage = $null; Geometry = $null }
  if ($BrowserInfo.Engine -ne 'chromium') {
    $result.ErrorMessage = "Browser $($BrowserInfo.Name) unterstützt keine verbindliche DOM-Geometrieprüfung."
    return $result
  }
  $auditRoot = Resolve-SafePath -Candidate (Join-Path -Path $BrowserTempRoot -ChildPath ('G-' + $RunId)) -Root $BrowserTempRoot -ForWrite -PathType Container
  $profilePath = Join-Path -Path $auditRoot -ChildPath 'profile'
  $browserHtmlPath = Join-Path -Path $auditRoot -ChildPath 'capture.html'
  try {
    New-Item -Path $auditRoot -ItemType Directory | Out-Null
    New-Item -Path $profilePath -ItemType Directory | Out-Null
    Copy-Item -LiteralPath $CaptureHtmlFile.FullName -Destination $browserHtmlPath
    $uri = [System.Uri]::new($browserHtmlPath).AbsoluteUri
    $arguments = @(
      '--headless=new', '--disable-gpu', '--disable-dev-shm-usage',
      '--no-first-run', '--disable-background-networking', '--disable-extensions', '--hide-scrollbars',
      "--user-data-dir=$profilePath", "--window-size=$Width,$Height", '--dump-dom', $uri
    )
    $process = Invoke-NativeProcess -FilePath $BrowserInfo.Path -ArgumentList $arguments -TimeoutSeconds $TimeoutSeconds -MaxStdoutChars 262144 -MaxStderrChars 8192
    if ($process.TimedOut) { $result.ErrorMessage = "DOM-Geometrieprüfung überschritt das Zeitlimit von $TimeoutSeconds Sekunden."; return $result }
    if ($process.ExitCode -ne 0) {
      $stderr = $process.StandardError.Trim()
      $result.ErrorMessage = "DOM-Geometrieprüfung endete mit Exitcode $($process.ExitCode)." + $(if ($stderr) { " stderr: $stderr" } else { '' })
      return $result
    }
    if ($process.StdoutTruncated) { $result.ErrorMessage = 'DOM-Geometrieprüfung erzeugte zu viel Ausgabe.'; return $result }
    $match = [regex]::Match($process.StandardOutput, 'data-layoutcheck-geometry-b64="(?<payload>[A-Za-z0-9+/=]+)"')
    if (-not $match.Success) { $result.ErrorMessage = 'DOM-Geometrieprüfung lieferte keinen auswertbaren Messwert.'; return $result }
    try {
      $json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($match.Groups['payload'].Value))
      $geometry = $json | ConvertFrom-Json
    } catch {
      $result.ErrorMessage = "DOM-Geometrieprüfung lieferte ungültige Messdaten: $($_.Exception.Message)"
      return $result
    }
    if ($geometry.available -ne $true) { $result.ErrorMessage = "DOM-Geometrieprüfung konnte die A4-Seite nicht messen: $($geometry.error)"; return $result }
    $result.Available = $true
    $result.Geometry = $geometry
  } catch {
    $result.ErrorMessage = $_.Exception.Message
  } finally {
    if (-not (Remove-TemporaryDirectoryWithRetry -Path $auditRoot -Root $BrowserTempRoot)) {
      Add-Warn "Temporärer DOM-Prüfordner konnte nicht vollständig bereinigt werden: $auditRoot"
    }
  }
  return $result
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
$cvFiles = @(Get-ChildItem -LiteralPath $resolvedFolder -File -Filter "Lebenslauf - *.html")
$letterFiles = @(Get-ChildItem -LiteralPath $resolvedFolder -File -Filter "Anschreiben - *.html")
if (($cvFiles.Count -gt 1) -or ($letterFiles.Count -gt 1) -or (($cvFiles.Count + $letterFiles.Count) -eq 0)) {
  Add-Fail "Für den Layoutcheck werden ein oder zwei laut Dokumentumfang ausgewählte HTML-Dokumente erwartet; gefunden: $($cvFiles.Count) Lebenslauf, $($letterFiles.Count) Anschreiben."
  exit 1
}
$htmlFiles = @($letterFiles + $cvFiles | Sort-Object Name)
try {
  $htmlFiles = @($htmlFiles | ForEach-Object {
    $safeHtmlPath = Resolve-SafePath -Candidate $_.FullName -Root $applicationsRoot -MustExist -PathType Leaf
    Get-Item -LiteralPath $safeHtmlPath
  })
} catch {
  Add-Fail "Unsichere HTML-Quelldatei: $($_.Exception.Message)"
  exit 2
}

if ($OutputRoot) {
  $layoutDir = [System.IO.Path]::GetFullPath($OutputRoot)
} else {
  $candidateParent = Split-Path -Path $resolvedFolder -Parent
  $candidateWorkRoot = Split-Path -Path $candidateParent -Parent
  if ([string]::Equals((Split-Path -Path $resolvedFolder -Leaf), 'Kandidat', (Get-PathStringComparison)) -and
      [string]::Equals((Split-Path -Path $candidateWorkRoot -Leaf), '_Arbeitsdateien', (Get-PathStringComparison))) {
    # Kanonischer Kandidatenordner: .../_Arbeitsdateien/<Auftrag>/Kandidat.
    $layoutDir = Join-Path -Path $candidateParent -ChildPath 'Layoutcheck'
  } else {
    # Historischer Diagnoseaufruf mit finalem Rollenordner.
    $roleDir = Split-Path -Path $resolvedFolder -Leaf
    $companyDir = Split-Path -Path $resolvedFolder -Parent
    $layoutDir = Join-Path -Path (Join-Path -Path $companyDir -ChildPath '_Arbeitsdateien') -ChildPath $roleDir
    $layoutDir = Join-Path -Path $layoutDir -ChildPath 'Layoutcheck'
  }
}

Add-Info "Finaler Bewerbungsordner: $resolvedFolder"
Add-Info "Layoutcheck-Ausgabe: $layoutDir"
Add-Info "HTML-Dateien: $($htmlFiles.Name -join ', ')"

if (($layoutDir -notmatch '[\\/]Private[\\/]Bewerbungen[\\/]+') -or ($layoutDir -notmatch '[\\/]_Arbeitsdateien(?:[\\/]|$)')) {
  Add-Fail "Layoutcheck-Ausgabe muss unter `Private/Bewerbungen/.../_Arbeitsdateien` liegen: $layoutDir"
  exit 1
}
try {
  $layoutDir = Resolve-SafePath -Candidate $layoutDir -Root $applicationsRoot -PathType Container
} catch {
  Add-Fail "Unsicherer Layoutcheck-Ausgabepfad: $($_.Exception.Message)"
  exit 2
}

New-Item -Path $layoutDir -ItemType Directory -Force | Out-Null
try {
  $layoutDir = Resolve-SafePath -Candidate $layoutDir -Root $applicationsRoot -MustExist -ForWrite -PathType Container
} catch {
  Add-Fail "Layoutcheck-Ausgabe ist kein sicherer beschreibbarer Ordner: $($_.Exception.Message)"
  exit 2
}
if ([string]::IsNullOrWhiteSpace($BerichtPath)) {
  $BerichtPath = Join-Path -Path $layoutDir -ChildPath "Layoutcheck-Bericht.json"
} elseif (-not [System.IO.Path]::IsPathFullyQualified($BerichtPath)) {
  $BerichtPath = [System.IO.Path]::GetFullPath($BerichtPath)
}
try {
  if ([System.IO.Path]::GetExtension($BerichtPath) -cne ".json") {
    throw "Layoutbericht muss eine JSON-Datei sein."
  }
  $BerichtPath = Resolve-SafePath -Candidate $BerichtPath -Root $layoutDir -ForWrite -PathType Leaf
} catch {
  Add-Fail "Unsicherer Layoutberichtspfad: $($_.Exception.Message)"
  exit 2
}

$documents = @()
foreach ($html in $htmlFiles) {
  $htmlSha256 = (Get-FileHash -LiteralPath $html.FullName -Algorithm SHA256).Hash
  $htmlText = Get-Content -LiteralPath $html.FullName -Raw -Encoding UTF8
  $snapshotError = Get-HtmlSnapshotError -HtmlFile $html -ExpectedSha256 $htmlSha256
  if ($snapshotError) {
    Add-Fail $snapshotError
    exit 1
  }
  $pageMatches = @(Get-HtmlPageMatches -Html $htmlText)
  if ($pageMatches.Count -eq 0) {
    Add-Fail "HTML enthält keine expliziten A4-Seitencontainer: $($html.Name)"
    exit 1
  }
  $safeBase = Convert-ToSafeFilePart -Value $html.BaseName
  foreach ($oldOutput in @(Get-ChildItem -LiteralPath $layoutDir -File | Where-Object {
    $_.Name -like "$safeBase--*.png" -or $_.Name -like "$safeBase--*.pdf" -or $_.Name -like ".capture-$safeBase--*.html"
  })) {
    Remove-Item -LiteralPath $oldOutput.FullName -Force
  }
  $documents += [pscustomobject]@{
    HtmlFile = $html
    HtmlText = $htmlText
    HtmlSha256 = $htmlSha256
    PageMatches = $pageMatches
    PageCount = $pageMatches.Count
    SafeBase = $safeBase
    PrintCssDiagnostics = @(Get-AdjacentPagePrintDiagnostics -HtmlText $htmlText)
  }
}

if ($NurVorbereiten) {
  $expectedPages = (@($documents | ForEach-Object { $_.PageCount }) | Measure-Object -Sum).Sum
  Add-Ok "Vorbereitung erfolgreich. $expectedPages A4-Seitenscreenshot(s) sind vorgesehen; es wurde kein Browser gestartet."
  exit 0
}

$browserCandidates = @(Get-BrowserCandidates -RequestedBrowser $Browser -ExecutablePath $BrowserExecutablePath -AllowFirefoxFallback:$ErlaubeFirefoxFallback)
if ($browserCandidates.Count -eq 0) {
  Add-Fail "Kein passender Browser gefunden. Erlaubt: Chrome, Edge, Chromium oder Firefox für die Layoutdiagnose."
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
$runId = [guid]::NewGuid().ToString("N")

foreach ($candidate in $browserCandidates) {
  Add-Info "Teste Browser: $($candidate.Name) ($($candidate.Path))"
  $candidateOk = $true
  $candidateResults = @()
  $candidateDocumentPreflights = @()
  foreach ($document in $documents) {
    foreach ($diagnostic in @($document.PrintCssDiagnostics)) {
      Add-Warn "$($document.HtmlFile.Name): $diagnostic"
    }
    $snapshotError = Get-HtmlSnapshotError -HtmlFile $document.HtmlFile -ExpectedSha256 $document.HtmlSha256
    if ($snapshotError) {
      $candidateOk = $false
      $browserErrors.Add("$($candidate.Name): $snapshotError") | Out-Null
      break
    }
    $printPreflight = Invoke-HtmlPrintPreflight -BrowserInfo $candidate -HtmlFile $document.HtmlFile -BrowserTempRoot $browserTempRoot -TimeoutSeconds $TimeoutSeconds
    if (-not $printPreflight.succeeded) {
      $candidateOk = $false
      $browserErrors.Add("$($candidate.Name): Druckvorprüfung fehlgeschlagen für $($document.HtmlFile.Name): $($printPreflight.error)") | Out-Null
    }
    for ($pageIndex = 0; $pageIndex -lt $document.PageCount; $pageIndex++) {
      $snapshotError = Get-HtmlSnapshotError -HtmlFile $document.HtmlFile -ExpectedSha256 $document.HtmlSha256
      if ($snapshotError) {
        $candidateOk = $false
        $browserErrors.Add("$($candidate.Name): $snapshotError") | Out-Null
        break
      }
      $pageNumber = $pageIndex + 1
      $runId = [guid]::NewGuid().ToString("N")
      $capturePath = Join-Path -Path $layoutDir -ChildPath ".capture-$($document.SafeBase)--$runId.html"
      $capturePath = Resolve-SafePath -Candidate $capturePath -Root $layoutDir -ForWrite -PathType Leaf
      try {
        New-PageCaptureHtml -HtmlFile $document.HtmlFile -HtmlText $document.HtmlText -PageNumber $pageNumber -TargetPath $capturePath
        $captureFile = Get-Item -LiteralPath $capturePath
        $geometryAudit = Invoke-BrowserGeometryAudit -BrowserInfo $candidate -CaptureHtmlFile $captureFile -BrowserTempRoot $browserTempRoot -RunId $runId -Width $Width -Height $Height -TimeoutSeconds $TimeoutSeconds
        $geometryFailure = $null
        if (-not $geometryAudit.Available) {
          $geometryFailure = $geometryAudit.ErrorMessage
        } elseif ($geometryAudit.Geometry.pageOverflowX -eq $true -or $geometryAudit.Geometry.pageOverflowY -eq $true -or @($geometryAudit.Geometry.outsideElements).Count -gt 0) {
          $geometryFailure = "DOM-Geometrie meldet Überlauf (horizontal=$($geometryAudit.Geometry.pageOverflowX), vertikal=$($geometryAudit.Geometry.pageOverflowY), Elemente außerhalb=$(@($geometryAudit.Geometry.outsideElements).Count))."
        }
        if ($geometryFailure) {
          $result = [pscustomobject]@{ Browser=$candidate.Name; File=$document.HtmlFile.Name; PageNumber=$pageNumber; PageCount=$document.PageCount; ExitCode=$null; TimedOut=$false; ErrorMessage=$geometryFailure; Screenshot=$null; ScreenshotOk=$false; Pdf=$null; PdfOk=$false; Geometry=$geometryAudit.Geometry }
        } else {
          $result = Invoke-BrowserScreenshot -BrowserInfo $candidate -SourceHtmlFile $document.HtmlFile -CaptureHtmlFile $captureFile -OutputBaseName $document.HtmlFile.BaseName -PageNumber $pageNumber -PageCount $document.PageCount -TargetDir $layoutDir -BrowserTempRoot $browserTempRoot -RunId $runId -Width $Width -Height $Height -TimeoutSeconds $TimeoutSeconds -Pdf:$Pdf
          $result | Add-Member -NotePropertyName Geometry -NotePropertyValue $geometryAudit.Geometry
        }
      } finally {
        if (Test-Path -LiteralPath $capturePath -PathType Leaf) {
          Remove-Item -LiteralPath $capturePath -Force -ErrorAction SilentlyContinue
        }
      }

      $snapshotError = Get-HtmlSnapshotError -HtmlFile $document.HtmlFile -ExpectedSha256 $document.HtmlSha256
      if ($snapshotError) {
        foreach ($runOutput in @($result.Screenshot, $result.Pdf)) {
          if ($runOutput -and (Test-Path -LiteralPath $runOutput -PathType Leaf)) {
            Remove-Item -LiteralPath $runOutput -Force -ErrorAction SilentlyContinue
          }
        }
        $candidateOk = $false
        $browserErrors.Add("$($candidate.Name): $snapshotError") | Out-Null
        break
      }

      if ($result.ScreenshotOk) {
        Add-Ok "$($result.Browser): frischen A4-Screenshot erzeugt für $($result.File), Seite $pageNumber von $($document.PageCount)"
        $pageBody = $document.PageMatches[$pageIndex].Groups["body"].Value
        $hasDocumentFooter = $pageBody -match '(?is)<footer\b[^>]*class\s*=\s*["''][^"'']*\bpage-footer\b'
        $bottomReserveMm = if ($hasDocumentFooter) { 17.0 } else { 3.0 }
        $density = if ($DichtepruefungDeaktivieren) {
          [pscustomobject]@{ available = $false; bottomWhitespacePx = $null; bottomWhitespaceMm = $null; pageNumber = $pageNumber; pageCount = $document.PageCount; scanBottomReserveMm = $bottomReserveMm; warning = $null }
        } else {
          Get-LayoutDensity -Path $result.Screenshot -DocumentName $result.File -ExpectedHeight $Height -PageNumber $pageNumber -PageCount $document.PageCount -BottomReserveMm $bottomReserveMm
        }
        if (-not $DichtepruefungDeaktivieren -and -not $density.available) {
          $candidateOk = $false
          $browserErrors.Add("$($result.Browser): Erforderliche Layoutdichteprüfung fehlgeschlagen für $($result.File), Seite ${pageNumber}: $($density.warning)") | Out-Null
        }
        if ($density.warning) {
          Add-Warn "$($result.File): $($density.warning)"
        } elseif ($density.available) {
          Add-Ok "$($result.File), Seite ${pageNumber}: $($density.bottomWhitespaceMm) mm freie Fläche innerhalb der unteren Inhaltsgrenze."
        }
        $screenshotInfo = Get-Item -LiteralPath $result.Screenshot
        $candidateResults += [ordered]@{
          htmlFile = $document.HtmlFile.Name
          htmlSha256 = $document.HtmlSha256
          pageNumber = $pageNumber
          pageCount = $document.PageCount
          hasDocumentFooter = $hasDocumentFooter
          screenshot = $result.Screenshot
          screenshotSha256 = (Get-FileHash -LiteralPath $result.Screenshot -Algorithm SHA256).Hash
          screenshotBytes = $screenshotInfo.Length
          bottomWhitespacePx = $density.bottomWhitespacePx
          bottomWhitespaceMm = $density.bottomWhitespaceMm
          scanBottomReserveMm = $density.scanBottomReserveMm
          densityWarning = $density.warning
          domGeometry = [ordered]@{
            pageOverflowX = $result.Geometry.pageOverflowX
            pageOverflowY = $result.Geometry.pageOverflowY
            outsideElements = @($result.Geometry.outsideElements)
            pageClientWidth = $result.Geometry.pageClientWidth
            pageClientHeight = $result.Geometry.pageClientHeight
            pageScrollWidth = $result.Geometry.pageScrollWidth
            pageScrollHeight = $result.Geometry.pageScrollHeight
          }
        }
      } else {
        $candidateOk = $false
        $browserErrors.Add("$($result.Browser): Screenshot-Prüfung fehlgeschlagen für $($result.File), Seite ${pageNumber}: $($result.ErrorMessage)") | Out-Null
      }

      if ($Pdf -and -not $result.PdfOk) {
        $candidateOk = $false
        if ($result.ScreenshotOk) {
          $browserErrors.Add("$($result.Browser): PDF-Prüfung fehlgeschlagen für $($result.File), Seite ${pageNumber}: $($result.ErrorMessage)") | Out-Null
        }
      } elseif ($Pdf -and $result.PdfOk) {
        Add-Ok "$($result.Browser): frische Seiten-PDF erzeugt für $($result.File), Seite $pageNumber"
      }
    }
    if ($printPreflight.succeeded -and $candidateOk) {
      $candidateDocumentPreflights += [ordered]@{
        htmlFile = $document.HtmlFile.Name
        htmlSha256 = $document.HtmlSha256
        expectedPageCount = $printPreflight.expectedPageCount
        actualPageCount = $printPreflight.actualPageCount
        pdfBytes = $printPreflight.pdfBytes
        mediaBox = $printPreflight.mediaBox
        a4 = $printPreflight.a4
        status = 'bestanden'
        cssDiagnostics = @($document.PrintCssDiagnostics)
      }
    }
    if (-not $candidateOk) { break }
  }

  if ($candidateOk) {
    foreach ($document in $documents) {
      $snapshotError = Get-HtmlSnapshotError -HtmlFile $document.HtmlFile -ExpectedSha256 $document.HtmlSha256
      if ($snapshotError) {
        $candidateOk = $false
        $browserErrors.Add("$($candidate.Name): $snapshotError") | Out-Null
        break
      }
    }
  }
  if ($candidateOk) {
    Write-LayoutReport -Path $BerichtPath -BrowserInfo $candidate -Results $candidateResults -DocumentPreflights $candidateDocumentPreflights -ExpectedWidth $Width -ExpectedHeight $Height
    if ((Test-Path -LiteralPath $browserTempRoot -PathType Container) -and @(Get-ChildItem -LiteralPath $browserTempRoot -Force).Count -eq 0) {
      Remove-Item -LiteralPath $browserTempRoot -Force -ErrorAction SilentlyContinue
    }
    Add-Ok "Layoutcheck erfolgreich mit Browser: $($candidate.Name)"
    Add-Ok "Layoutcheck-Bericht geschrieben: $BerichtPath"
    exit 0
  }
  foreach ($document in $documents) {
    $candidateOutputs = @(Get-ChildItem -LiteralPath $layoutDir -File | Where-Object {
      ($_.Name -like "$($document.SafeBase)--seite-*-von-*--$($candidate.Name).png") -or
      ($_.Name -like "$($document.SafeBase)--seite-*-von-*--$($candidate.Name).pdf")
    })
    foreach ($candidateOutput in $candidateOutputs) {
      Remove-Item -LiteralPath $candidateOutput.FullName -Force -ErrorAction SilentlyContinue
    }
  }
  $remainingCandidateOutputs = @(Get-ChildItem -LiteralPath $layoutDir -File | Where-Object {
    $outputName = $_.Name
    @($documents | Where-Object {
      $outputName -like "$($_.SafeBase)--seite-*-von-*--$($candidate.Name).png" -or
      $outputName -like "$($_.SafeBase)--seite-*-von-*--$($candidate.Name).pdf"
    }).Count -gt 0
  })
  if ($remainingCandidateOutputs.Count -gt 0) {
    Add-Fail "Fehlgeschlagene Browserausgaben konnten nicht vollständig entfernt werden: $($remainingCandidateOutputs.Name -join ', ')"
    exit 1
  }
  Add-Warn "Browser $($candidate.Name) hat nicht alle erwarteten Ausgaben gültig erzeugt."
}

foreach ($message in $browserErrors) {
  Add-Fail $message
}
if ((Test-Path -LiteralPath $browserTempRoot -PathType Container) -and @(Get-ChildItem -LiteralPath $browserTempRoot -Force).Count -eq 0) {
  Remove-Item -LiteralPath $browserTempRoot -Force -ErrorAction SilentlyContinue
}
Add-Fail "Layoutcheck fehlgeschlagen: Kein Browser hat alle erwarteten Ausgabedateien frisch und gültig erzeugt."
exit 1
