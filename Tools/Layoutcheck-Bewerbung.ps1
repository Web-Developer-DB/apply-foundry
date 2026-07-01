[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Ordner,

  [ValidateSet("auto", "chrome", "edge", "firefox")]
  [string]$Browser = "auto",

  [switch]$NurVorbereiten,

  [switch]$Pdf,

  [int]$Width = 794,

  [int]$Height = 1123,

  [string]$OutputRoot
)

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
  param([string]$RequestedBrowser)

  $candidates = New-Object System.Collections.Generic.List[object]

  $known = @(
    @{ Name = "chrome"; Type = "chromium"; Paths = @("C:\Program Files\Google\Chrome\Application\chrome.exe", "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"); Commands = @("chrome", "chrome.exe") },
    @{ Name = "edge"; Type = "chromium"; Paths = @("C:\Program Files\Microsoft\Edge\Application\msedge.exe", "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"); Commands = @("msedge", "msedge.exe") },
    @{ Name = "firefox"; Type = "firefox"; Paths = @("C:\Program Files\Mozilla Firefox\firefox.exe", "C:\Program Files (x86)\Mozilla Firefox\firefox.exe"); Commands = @("firefox", "firefox.exe") }
  )

  foreach ($entry in $known) {
    if (($RequestedBrowser -ne "auto") -and ($entry.Name -ne $RequestedBrowser)) {
      continue
    }

    foreach ($path in $entry.Paths) {
      if (Test-Path -LiteralPath $path) {
        $candidates.Add([pscustomobject]@{ Name = $entry.Name; Type = $entry.Type; Path = $path }) | Out-Null
        break
      }
    }

    if (($candidates | Where-Object { $_.Name -eq $entry.Name }).Count -gt 0) {
      continue
    }

    foreach ($command in $entry.Commands) {
      $cmd = Get-Command $command -ErrorAction SilentlyContinue
      if ($cmd) {
        $candidates.Add([pscustomobject]@{ Name = $entry.Name; Type = $entry.Type; Path = $cmd.Source }) | Out-Null
        break
      }
    }
  }

  return $candidates
}

function Invoke-BrowserScreenshot {
  param(
    [pscustomobject]$BrowserInfo,
    [System.IO.FileInfo]$HtmlFile,
    [string]$TargetDir,
    [int]$Width,
    [int]$Height,
    [switch]$Pdf
  )

  $safeBase = Convert-ToSafeFilePart -Value $HtmlFile.BaseName
  $pngPath = Join-Path -Path $TargetDir -ChildPath "$safeBase--$($BrowserInfo.Name).png"
  $pdfPath = Join-Path -Path $TargetDir -ChildPath "$safeBase--$($BrowserInfo.Name).pdf"
  $profilePath = Join-Path -Path $TargetDir -ChildPath "Profile-$($BrowserInfo.Name)"
  New-Item -Path $profilePath -ItemType Directory -Force | Out-Null

  $uri = [System.Uri]::new($HtmlFile.FullName).AbsoluteUri

  if ($BrowserInfo.Type -eq "chromium") {
    $arguments = @(
      "--headless=new",
      "--disable-gpu",
      "--no-first-run",
      "--disable-background-networking",
      "--user-data-dir=$profilePath",
      "--window-size=$Width,$Height",
      "--screenshot=$pngPath"
    )

    if ($Pdf) {
      $arguments += "--print-to-pdf=$pdfPath"
      $arguments += "--print-to-pdf-no-header"
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

    if ($Pdf) {
      Add-Warn "Firefox-PDF-Export wird nicht automatisch erzeugt; Screenshot wird geprüft."
    }
  }

  $argumentLine = ($arguments | ForEach-Object { ConvertTo-QuotedArgument -Value $_ }) -join " "
  $process = Start-Process -FilePath $BrowserInfo.Path -ArgumentList $argumentLine -WindowStyle Hidden -Wait -PassThru

  $result = [pscustomobject]@{
    Browser = $BrowserInfo.Name
    File = $HtmlFile.Name
    ExitCode = $process.ExitCode
    Screenshot = $pngPath
    ScreenshotOk = $false
    Pdf = $pdfPath
    PdfOk = $false
  }

  if (Test-Path -LiteralPath $pngPath) {
    $pngInfo = Get-Item -LiteralPath $pngPath
    if ($pngInfo.Length -gt 5000) {
      $result.ScreenshotOk = $true
    }
  }

  if ($Pdf -and ($BrowserInfo.Type -eq "chromium") -and (Test-Path -LiteralPath $pdfPath)) {
    $pdfInfo = Get-Item -LiteralPath $pdfPath
    if ($pdfInfo.Length -gt 5000) {
      $result.PdfOk = $true
    }
  }

  return $result
}

if (-not (Test-Path -LiteralPath $Ordner)) {
  Add-Fail "Ordner existiert nicht: $Ordner"
  exit 1
}

$resolvedFolder = (Resolve-Path -LiteralPath $Ordner).Path
$folderInfo = Get-Item -LiteralPath $resolvedFolder
if (-not $folderInfo.PSIsContainer) {
  Add-Fail "Pfad ist kein Ordner: $resolvedFolder"
  exit 1
}

$htmlFiles = Get-ChildItem -LiteralPath $resolvedFolder -File -Filter "*.html" | Where-Object {
  $_.Name -match '^(Lebenslauf|Anschreiben) - .+\.html$'
}

if ($htmlFiles.Count -eq 0) {
  Add-Fail "Keine finalen HTML-Dateien nach Schema `Lebenslauf - NAME.html` oder `Anschreiben - NAME.html` gefunden."
  exit 1
}

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

if ($layoutDir -notmatch '[\\/]+_Arbeitsdateien([\\/]|$)') {
  Add-Fail "Layoutcheck-Ausgabe liegt nicht unter `_Arbeitsdateien`: $layoutDir"
  exit 1
}

if ($NurVorbereiten) {
  Add-Ok "Vorbereitung erfolgreich. Es wurde kein Browser gestartet."
  exit 0
}

New-Item -Path $layoutDir -ItemType Directory -Force | Out-Null

$browserCandidates = Get-BrowserCandidates -RequestedBrowser $Browser
if ($browserCandidates.Count -eq 0) {
  Add-Fail "Kein passender Browser gefunden. Erlaubt: chrome, edge, firefox."
  exit 1
}

Add-Info "Browser-Kandidaten: $($browserCandidates.Name -join ', ')"

$browserErrors = New-Object System.Collections.Generic.List[string]

foreach ($candidate in $browserCandidates) {
  Add-Info "Teste Browser: $($candidate.Name) ($($candidate.Path))"
  $allScreenshotsOk = $true
  $allPdfsOk = $true

  foreach ($html in $htmlFiles) {
    $result = Invoke-BrowserScreenshot -BrowserInfo $candidate -HtmlFile $html -TargetDir $layoutDir -Width $Width -Height $Height -Pdf:$Pdf

    if ($result.ScreenshotOk) {
      Add-Ok "$($result.Browser): Screenshot erzeugt für $($result.File)"
    } else {
      $allScreenshotsOk = $false
      $browserErrors.Add("$($result.Browser): Screenshot fehlt oder ist zu klein für $($result.File). ExitCode: $($result.ExitCode). Ziel: $($result.Screenshot)") | Out-Null
    }

    if ($Pdf) {
      if ($candidate.Type -eq "chromium") {
        if ($result.PdfOk) {
          Add-Ok "$($result.Browser): PDF erzeugt für $($result.File)"
        } else {
          $allPdfsOk = $false
          $browserErrors.Add("$($result.Browser): PDF fehlt oder ist zu klein für $($result.File). ExitCode: $($result.ExitCode). Ziel: $($result.Pdf)") | Out-Null
        }
      } else {
        $allPdfsOk = $false
        $browserErrors.Add("$($result.Browser): PDF-Export ist für diesen Browser nicht unterstützt. Ziel: $($result.Pdf)") | Out-Null
      }
    }
  }

  if ($allScreenshotsOk -and ((-not $Pdf) -or $allPdfsOk)) {
    Add-Ok "Layoutcheck erfolgreich mit Browser: $($candidate.Name)"
    exit 0
  }

  Add-Warn "Browser $($candidate.Name) hat nicht alle erwarteten Ausgaben erzeugt. Nächster Kandidat wird versucht."
}

foreach ($message in $browserErrors) {
  Add-Fail $message
}

Add-Fail "Layoutcheck fehlgeschlagen: Kein Browser hat alle erwarteten Ausgabedateien erzeugt."
exit 1
