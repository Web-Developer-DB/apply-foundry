[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Ordner,

  [ValidateSet("auto", "chrome", "edge", "firefox")]
  [string]$Browser = "auto",

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

function Stop-BrowserProcessTree {
  param([System.Diagnostics.Process]$Process)

  try {
    if (($env:OS -eq "Windows_NT") -and -not $Process.HasExited) {
      $taskKill = Get-Command "taskkill.exe" -ErrorAction SilentlyContinue
      if ($taskKill) {
        & $taskKill.Source /PID $Process.Id /T /F 2>$null | Out-Null
      }
    }
    if (-not $Process.HasExited) {
      Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
    }
    $null = $Process.WaitForExit(5000)
  } catch {
    Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
  }
}

function Convert-ToSafeFilePart {
  param([string]$Value)
  $safe = $Value -replace '[\\/:*?"<>|]+', '-'
  $safe = $safe -replace '\s+', '-'
  return $safe.Trim('-')
}

function ConvertTo-QuotedArgument {
  param([string]$Value)
  if ($Value -match '[\s"]') {
    return '"' + ($Value -replace '"', '\"') + '"'
  }
  return $Value
}

function Get-BrowserCandidates {
  param(
    [string]$RequestedBrowser,
    [switch]$AllowFirefoxFallback
  )

  $localChrome = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA "Google\Chrome\Application\chrome.exe" } else { $null }
  $localEdge = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA "Microsoft\Edge\Application\msedge.exe" } else { $null }
  $localFirefox = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA "Mozilla Firefox\firefox.exe" } else { $null }

  $known = @(
    @{ Name = "chrome"; Type = "chromium"; Paths = @("C:\Program Files\Google\Chrome\Application\chrome.exe", "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe", $localChrome); Commands = @("chrome", "chrome.exe") },
    @{ Name = "edge"; Type = "chromium"; Paths = @("C:\Program Files\Microsoft\Edge\Application\msedge.exe", "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe", $localEdge); Commands = @("msedge", "msedge.exe") },
    @{ Name = "firefox"; Type = "firefox"; Paths = @("C:\Program Files\Mozilla Firefox\firefox.exe", "C:\Program Files (x86)\Mozilla Firefox\firefox.exe", $localFirefox); Commands = @("firefox", "firefox.exe") }
  )

  $found = @()
  foreach ($entry in $known) {
    if (($RequestedBrowser -ne "auto") -and ($entry.Name -ne $RequestedBrowser)) {
      continue
    }

    foreach ($path in @($entry.Paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
      if (Test-Path -LiteralPath $path -PathType Leaf) {
        $found += [pscustomobject]@{ Name = $entry.Name; Type = $entry.Type; Path = $path }
        break
      }
    }

    if (@($found | Where-Object { $_.Name -eq $entry.Name }).Count -gt 0) {
      continue
    }

    foreach ($command in $entry.Commands) {
      $cmd = Get-Command $command -ErrorAction SilentlyContinue
      if ($cmd -and $cmd.Source) {
        $found += [pscustomobject]@{ Name = $entry.Name; Type = $entry.Type; Path = $cmd.Source }
        break
      }
    }
  }

  if ($RequestedBrowser -ne "auto") {
    return $found
  }

  $chromium = @($found | Where-Object { $_.Type -eq "chromium" })
  $firefox = @($found | Where-Object { $_.Type -eq "firefox" })
  if ($chromium.Count -gt 0) {
    if ($AllowFirefoxFallback) {
      return @($chromium + $firefox)
    }
    return $chromium
  }

  return $firefox
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

function Get-LayoutDensity {
  param(
    [string]$Path,
    [string]$DocumentName,
    [int]$ExpectedHeight
  )

  $result = [ordered]@{
    available = $false
    bottomWhitespacePx = $null
    bottomWhitespaceMm = $null
    warning = $null
  }
  try {
    Add-Type -AssemblyName System.Drawing.Common -ErrorAction SilentlyContinue
    $bitmap = [System.Drawing.Bitmap]::new([string]$Path)
    try {
      $lastInkRow = -1
      $left = [math]::Max(8, [int]($bitmap.Width * 0.03))
      $right = [math]::Min($bitmap.Width - 9, [int]($bitmap.Width * 0.97))
      for ($y = $bitmap.Height - 1; $y -ge 0; $y--) {
        $inkSamples = 0
        for ($x = $left; $x -le $right; $x += 2) {
          $pixel = $bitmap.GetPixel($x, $y)
          if (($pixel.R -lt 242) -or ($pixel.G -lt 242) -or ($pixel.B -lt 242)) {
            $inkSamples++
            if ($inkSamples -ge 2) {
              $lastInkRow = $y
              break
            }
          }
        }
        if ($lastInkRow -ge 0) { break }
      }

      if ($lastInkRow -ge 0) {
        $whitespacePx = ($bitmap.Height - 1) - $lastInkRow
        $whitespaceMm = [math]::Round(($whitespacePx * 297.0) / $ExpectedHeight, 1)
        $result.available = $true
        $result.bottomWhitespacePx = $whitespacePx
        $result.bottomWhitespaceMm = $whitespaceMm
        $isCv = $DocumentName -like "Lebenslauf -*"
        $maxWhitespaceMm = if ($isCv) { 45.0 } else { 70.0 }
        if ($whitespaceMm -gt $maxWhitespaceMm) {
          $result.warning = "Ungewöhnlich große freie Fläche am Seitenende: $whitespaceMm mm."
        } elseif ($whitespaceMm -lt 6.0) {
          $result.warning = "Inhalt liegt mit nur $whitespaceMm mm Abstand sehr nah am unteren Seitenrand."
        }
      }
    } finally {
      $bitmap.Dispose()
    }
  } catch {
    $result.warning = "Layoutdichte konnte nicht automatisch ausgewertet werden: $($_.Exception.Message)"
  }
  return [pscustomobject]$result
}

function Write-LayoutReport {
  param(
    [string]$Path,
    [string]$BrowserName,
    [array]$Results,
    [int]$ExpectedWidth,
    [int]$ExpectedHeight
  )

  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $parent = Split-Path -Path $fullPath -Parent
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -Path $parent -ItemType Directory -Force | Out-Null
  }
  $report = [ordered]@{
    schemaVersion = 1
    checkedAtUtc = [datetime]::UtcNow.ToString("o")
    browser = $BrowserName
    sourceFolder = $resolvedFolder
    width = $ExpectedWidth
    height = $ExpectedHeight
    results = $Results
  }
  Set-Content -LiteralPath $fullPath -Encoding UTF8 -Value ($report | ConvertTo-Json -Depth 8)
}

function Invoke-BrowserScreenshot {
  param(
    [pscustomobject]$BrowserInfo,
    [System.IO.FileInfo]$HtmlFile,
    [string]$TargetDir,
    [string]$RunId,
    [int]$Width,
    [int]$Height,
    [int]$TimeoutSeconds,
    [switch]$Pdf
  )

  $safeBase = Convert-ToSafeFilePart -Value $HtmlFile.BaseName
  $pngPath = Join-Path -Path $TargetDir -ChildPath "$safeBase--$($BrowserInfo.Name).png"
  $pdfPath = Join-Path -Path $TargetDir -ChildPath "$safeBase--$($BrowserInfo.Name).pdf"
  # Chrome verwendet für das Profildatenverzeichnis teilweise noch APIs mit
  # enger Windows-Pfadgrenze. Der interne Name bleibt deshalb bewusst kurz.
  $profilePath = Join-Path -Path $TargetDir -ChildPath ("P-" + $RunId.Substring(0, 8))

  $result = [pscustomobject]@{
    Browser = $BrowserInfo.Name
    File = $HtmlFile.Name
    ExitCode = $null
    TimedOut = $false
    ErrorMessage = $null
    Screenshot = $pngPath
    ScreenshotOk = $false
    Pdf = $pdfPath
    PdfOk = $false
  }

  try {
    foreach ($oldOutput in @($pngPath, $pdfPath)) {
      if (Test-Path -LiteralPath $oldOutput) {
        Remove-Item -LiteralPath $oldOutput -Force
      }
      if (Test-Path -LiteralPath $oldOutput) {
        throw "Alte Ausgabedatei konnte nicht entfernt werden: $oldOutput"
      }
    }

    New-Item -Path $profilePath -ItemType Directory -Force | Out-Null
    $uri = [System.Uri]::new($HtmlFile.FullName).AbsoluteUri

    if ($BrowserInfo.Type -eq "chromium") {
      $arguments = @(
        "--headless=new",
        "--disable-gpu",
        "--no-first-run",
        "--disable-background-networking",
        "--disable-extensions",
        "--user-data-dir=$profilePath",
        "--window-size=$Width,$Height",
        "--screenshot=$pngPath"
      )

      if ($Pdf) {
        $arguments += "--print-to-pdf=$pdfPath"
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
        $pngPath,
        $uri
      )
    }

    $argumentLine = ($arguments | ForEach-Object { ConvertTo-QuotedArgument -Value $_ }) -join " "
    $runStartedUtc = [datetime]::UtcNow
    $process = Start-Process -FilePath $BrowserInfo.Path -ArgumentList $argumentLine -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
      $result.TimedOut = $true
      Stop-BrowserProcessTree -Process $process
      $result.ErrorMessage = "Browserlauf hat das Zeitlimit von $TimeoutSeconds Sekunden überschritten."
      return $result
    }

    $result.ExitCode = $process.ExitCode
    if ($process.ExitCode -ne 0) {
      $result.ErrorMessage = "Browser beendete den Lauf mit Exitcode $($process.ExitCode)."
      return $result
    }

    $pngError = Test-PngFile -Path $pngPath -ExpectedWidth $Width -ExpectedHeight $Height -RunStartedUtc $runStartedUtc
    if ($pngError) {
      $result.ErrorMessage = $pngError
      return $result
    }
    $result.ScreenshotOk = $true

    if ($Pdf) {
      if ($BrowserInfo.Type -ne "chromium") {
        $result.ErrorMessage = "PDF-Export ist für Browser $($BrowserInfo.Name) nicht unterstützt."
        return $result
      }
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
    if (Test-Path -LiteralPath $profilePath -PathType Container) {
      Remove-Item -LiteralPath $profilePath -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  return $result
}

if (-not (Test-Path -LiteralPath $Ordner -PathType Container)) {
  Add-Fail "Ordner existiert nicht oder ist kein Verzeichnis: $Ordner"
  exit 1
}

$resolvedFolder = (Resolve-Path -LiteralPath $Ordner).Path
$cvFiles = @(Get-ChildItem -LiteralPath $resolvedFolder -File -Filter "Lebenslauf - *.html")
$letterFiles = @(Get-ChildItem -LiteralPath $resolvedFolder -File -Filter "Anschreiben - *.html")
if (($cvFiles.Count -ne 1) -or ($letterFiles.Count -ne 1)) {
  Add-Fail "Für den Layoutcheck werden genau ein Lebenslauf und ein Anschreiben erwartet; gefunden: $($cvFiles.Count) Lebenslauf, $($letterFiles.Count) Anschreiben."
  exit 1
}
$htmlFiles = @($letterFiles + $cvFiles | Sort-Object Name)

if ($OutputRoot) {
  $layoutDir = [System.IO.Path]::GetFullPath($OutputRoot)
} else {
  $roleDir = Split-Path -Path $resolvedFolder -Leaf
  $companyDir = Split-Path -Path $resolvedFolder -Parent
  $companyName = Split-Path -Path $companyDir -Leaf
  if ($companyName -eq "_Arbeitsdateien") {
    Add-Fail "Der angegebene Ordner scheint bereits ein Arbeitsordner zu sein. Bitte den finalen Bewerbungsordner angeben."
    exit 1
  }
  $layoutDir = Join-Path -Path $companyDir -ChildPath "_Arbeitsdateien"
  $layoutDir = Join-Path -Path $layoutDir -ChildPath $roleDir
  $layoutDir = Join-Path -Path $layoutDir -ChildPath "Layoutcheck"
}

Add-Info "Finaler Bewerbungsordner: $resolvedFolder"
Add-Info "Layoutcheck-Ausgabe: $layoutDir"
Add-Info "HTML-Dateien: $($htmlFiles.Name -join ', ')"

if (($layoutDir -notmatch '[\\/]Private[\\/]Bewerbungen[\\/]+') -or ($layoutDir -notmatch '[\\/]_Arbeitsdateien(?:[\\/]|$)')) {
  Add-Fail "Layoutcheck-Ausgabe muss unter `Private/Bewerbungen/.../_Arbeitsdateien` liegen: $layoutDir"
  exit 1
}

New-Item -Path $layoutDir -ItemType Directory -Force | Out-Null
if ([string]::IsNullOrWhiteSpace($BerichtPath)) {
  $BerichtPath = Join-Path -Path $layoutDir -ChildPath "Layoutcheck-Bericht.json"
}
if ($NurVorbereiten) {
  Add-Ok "Vorbereitung erfolgreich. Es wurde kein Browser gestartet."
  exit 0
}

$browserCandidates = @(Get-BrowserCandidates -RequestedBrowser $Browser -AllowFirefoxFallback:$ErlaubeFirefoxFallback)
if ($browserCandidates.Count -eq 0) {
  Add-Fail "Kein passender Browser gefunden. Erlaubt: Chrome, Edge oder Firefox."
  exit 1
}

Add-Info "Browser-Kandidaten: $($browserCandidates.Name -join ', ')"
$browserErrors = New-Object System.Collections.Generic.List[string]
$runId = [guid]::NewGuid().ToString("N")

foreach ($candidate in $browserCandidates) {
  Add-Info "Teste Browser: $($candidate.Name) ($($candidate.Path))"
  $candidateOk = $true
  $candidateResults = @()
  foreach ($html in $htmlFiles) {
    $runId = [guid]::NewGuid().ToString("N")
    $result = Invoke-BrowserScreenshot -BrowserInfo $candidate -HtmlFile $html -TargetDir $layoutDir -RunId $runId -Width $Width -Height $Height -TimeoutSeconds $TimeoutSeconds -Pdf:$Pdf
    if ($result.ScreenshotOk) {
      Add-Ok "$($result.Browser): frischen, gültigen Screenshot erzeugt für $($result.File)"
      $density = if ($DichtepruefungDeaktivieren) {
        [pscustomobject]@{ available = $false; bottomWhitespacePx = $null; bottomWhitespaceMm = $null; warning = $null }
      } else {
        Get-LayoutDensity -Path $result.Screenshot -DocumentName $result.File -ExpectedHeight $Height
      }
      if ($density.warning) {
        Add-Warn "$($result.File): $($density.warning)"
      } elseif ($density.available) {
        Add-Ok "$($result.File): Seitenende mit $($density.bottomWhitespaceMm) mm freier Fläche plausibel."
      }
      $screenshotInfo = Get-Item -LiteralPath $result.Screenshot
      $candidateResults += [ordered]@{
        htmlFile = $html.Name
        htmlSha256 = (Get-FileHash -LiteralPath $html.FullName -Algorithm SHA256).Hash
        screenshot = $result.Screenshot
        screenshotSha256 = (Get-FileHash -LiteralPath $result.Screenshot -Algorithm SHA256).Hash
        screenshotBytes = $screenshotInfo.Length
        bottomWhitespacePx = $density.bottomWhitespacePx
        bottomWhitespaceMm = $density.bottomWhitespaceMm
        densityWarning = $density.warning
      }
    } else {
      $candidateOk = $false
      $browserErrors.Add("$($result.Browser): Screenshot-Prüfung fehlgeschlagen für $($result.File): $($result.ErrorMessage)") | Out-Null
    }

    if ($Pdf -and -not $result.PdfOk) {
      $candidateOk = $false
      if ($result.ScreenshotOk) {
        $browserErrors.Add("$($result.Browser): PDF-Prüfung fehlgeschlagen für $($result.File): $($result.ErrorMessage)") | Out-Null
      }
    } elseif ($Pdf -and $result.PdfOk) {
      Add-Ok "$($result.Browser): frische PDF erzeugt für $($result.File)"
    }
  }

  if ($candidateOk) {
    Write-LayoutReport -Path $BerichtPath -BrowserName $candidate.Name -Results $candidateResults -ExpectedWidth $Width -ExpectedHeight $Height
    Add-Ok "Layoutcheck erfolgreich mit Browser: $($candidate.Name)"
    Add-Ok "Layoutcheck-Bericht geschrieben: $BerichtPath"
    exit 0
  }
  Add-Warn "Browser $($candidate.Name) hat nicht alle erwarteten Ausgaben gültig erzeugt."
}

foreach ($message in $browserErrors) {
  Add-Fail $message
}
Add-Fail "Layoutcheck fehlgeschlagen: Kein Browser hat alle erwarteten Ausgabedateien frisch und gültig erzeugt."
exit 1
