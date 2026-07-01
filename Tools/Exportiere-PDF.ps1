[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Ordner,

  [ValidateSet("auto", "chrome", "edge")]
  [string]$Browser = "auto",

  [switch]$MitLayoutcheck,

  [switch]$NichtUeberschreiben,

  [int]$MinPdfBytes = 5000
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

function Quote-Argument {
  param([string]$Value)
  if ($Value -match '[\s"]') {
    return '"' + ($Value -replace '"', '\"') + '"'
  }
  return $Value
}

function Get-PowerShellExecutable {
  $currentProcess = Get-Process -Id $PID
  if ($currentProcess.Path -and (Test-Path -LiteralPath $currentProcess.Path)) {
    return $currentProcess.Path
  }

  $pwsh = Get-Command "pwsh" -ErrorAction SilentlyContinue
  if ($pwsh) {
    return $pwsh.Source
  }

  $powershell = Get-Command "powershell" -ErrorAction SilentlyContinue
  if ($powershell) {
    return $powershell.Source
  }

  throw "Keine PowerShell-Executable gefunden."
}

function Invoke-ToolScript {
  param(
    [string]$ScriptPath,
    [string[]]$Arguments
  )

  $powerShellExe = Get-PowerShellExecutable
  Add-Info "Starte Tool: $ScriptPath"
  & $powerShellExe -NoProfile -File $ScriptPath @Arguments
  $exitCode = $LASTEXITCODE

  if ($exitCode -ne 0) {
    Add-Fail "Tool fehlgeschlagen: $ScriptPath (Exitcode $exitCode)"
    exit $exitCode
  }
}

function Get-BrowserCandidates {
  param([string]$RequestedBrowser)

  $candidates = New-Object System.Collections.Generic.List[object]
  $known = @(
    @{ Name = "chrome"; Paths = @("C:\Program Files\Google\Chrome\Application\chrome.exe", "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"); Commands = @("chrome", "chrome.exe") },
    @{ Name = "edge"; Paths = @("C:\Program Files\Microsoft\Edge\Application\msedge.exe", "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"); Commands = @("msedge", "msedge.exe") }
  )

  foreach ($entry in $known) {
    if (($RequestedBrowser -ne "auto") -and ($entry.Name -ne $RequestedBrowser)) {
      continue
    }

    foreach ($path in $entry.Paths) {
      if (Test-Path -LiteralPath $path) {
        $candidates.Add([pscustomobject]@{ Name = $entry.Name; Path = $path }) | Out-Null
        break
      }
    }

    if (($candidates | Where-Object { $_.Name -eq $entry.Name }).Count -gt 0) {
      continue
    }

    foreach ($command in $entry.Commands) {
      $cmd = Get-Command $command -ErrorAction SilentlyContinue
      if ($cmd) {
        $candidates.Add([pscustomobject]@{ Name = $entry.Name; Path = $cmd.Source }) | Out-Null
        break
      }
    }
  }

  return $candidates
}

function Test-PdfFile {
  param(
    [string]$Path,
    [int]$MinBytes
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    return "PDF wurde nicht erzeugt: $Path"
  }

  $info = Get-Item -LiteralPath $Path
  if ($info.Length -lt $MinBytes) {
    return "PDF ist zu klein ($($info.Length) Bytes): $Path"
  }

  $stream = [System.IO.File]::OpenRead($Path)
  try {
    $buffer = New-Object byte[] 5
    $read = $stream.Read($buffer, 0, 5)
    $header = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $read)
    if ($header -ne "%PDF-") {
      return "PDF-Datei hat keinen PDF-Header: $Path"
    }
  } finally {
    $stream.Dispose()
  }

  return $null
}

function Export-HtmlToPdf {
  param(
    [pscustomobject]$BrowserInfo,
    [System.IO.FileInfo]$HtmlFile,
    [string]$PdfPath,
    [string]$ProfileDir,
    [int]$MinPdfBytes
  )

  New-Item -Path $ProfileDir -ItemType Directory -Force | Out-Null

  $uri = [System.Uri]::new($HtmlFile.FullName).AbsoluteUri
  $arguments = @(
    "--headless=new",
    "--disable-gpu",
    "--no-first-run",
    "--disable-background-networking",
    "--disable-extensions",
    "--user-data-dir=$ProfileDir",
    "--print-to-pdf=$PdfPath",
    "--print-to-pdf-no-header",
    "--no-pdf-header-footer",
    $uri
  )

  $argumentLine = ($arguments | ForEach-Object { Quote-Argument -Value $_ }) -join " "
  $process = Start-Process -FilePath $BrowserInfo.Path -ArgumentList $argumentLine -WindowStyle Hidden -Wait -PassThru

  $pdfError = Test-PdfFile -Path $PdfPath -MinBytes $MinPdfBytes
  if ($process.ExitCode -ne 0) {
    return "Browser $($BrowserInfo.Name) beendete mit Exitcode $($process.ExitCode) für $($HtmlFile.Name)."
  }

  if ($pdfError) {
    return $pdfError
  }

  return $null
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

$checkerPath = Join-Path -Path $PSScriptRoot -ChildPath "Pruefe-Bewerbung.ps1"
$layoutcheckPath = Join-Path -Path $PSScriptRoot -ChildPath "Layoutcheck-Bewerbung.ps1"

if (-not (Test-Path -LiteralPath $checkerPath)) {
  Add-Fail "Statischer Prüfer nicht gefunden: $checkerPath"
  exit 1
}

Invoke-ToolScript -ScriptPath $checkerPath -Arguments @("-Ordner", $resolvedFolder)

if ($MitLayoutcheck) {
  if (-not (Test-Path -LiteralPath $layoutcheckPath)) {
    Add-Fail "Layoutcheck-Tool nicht gefunden: $layoutcheckPath"
    exit 1
  }

  Invoke-ToolScript -ScriptPath $layoutcheckPath -Arguments @("-Ordner", $resolvedFolder, "-Browser", $Browser)
}

$htmlFiles = Get-ChildItem -LiteralPath $resolvedFolder -File -Filter "*.html" | Where-Object {
  $_.Name -match '^(Lebenslauf|Anschreiben) - .+\.html$'
} | Sort-Object Name

if ($htmlFiles.Count -eq 0) {
  Add-Fail "Keine finalen HTML-Dateien gefunden."
  exit 1
}

$roleDir = Split-Path -Path $resolvedFolder -Leaf
$companyDir = Split-Path -Path $resolvedFolder -Parent
$companyName = Split-Path -Path $companyDir -Leaf
if ($companyName -eq "_Arbeitsdateien") {
  Add-Fail "Der angegebene Ordner scheint ein Arbeitsordner zu sein. Bitte finalen Bewerbungsordner angeben."
  exit 1
}

$workDir = Join-Path -Path $companyDir -ChildPath "_Arbeitsdateien"
$workDir = Join-Path -Path $workDir -ChildPath $roleDir
$workDir = Join-Path -Path $workDir -ChildPath "PDF-Export"
New-Item -Path $workDir -ItemType Directory -Force | Out-Null

Add-Info "Finaler Bewerbungsordner: $resolvedFolder"
Add-Info "PDF-Export-Arbeitsordner: $workDir"
Add-Info "HTML-Dateien: $($htmlFiles.Name -join ', ')"

$browserCandidates = Get-BrowserCandidates -RequestedBrowser $Browser
if ($browserCandidates.Count -eq 0) {
  Add-Fail "Kein Chromium-Browser gefunden. Unterstützt werden Chrome oder Edge."
  exit 1
}

Add-Info "Browser-Kandidaten: $($browserCandidates.Name -join ', ')"

$browserErrors = New-Object System.Collections.Generic.List[string]

foreach ($candidate in $browserCandidates) {
  Add-Info "Teste PDF-Export mit Browser: $($candidate.Name) ($($candidate.Path))"
  $exportedPdfs = New-Object System.Collections.Generic.List[string]
  $candidateOk = $true

  foreach ($html in $htmlFiles) {
    $pdfPath = [System.IO.Path]::ChangeExtension($html.FullName, ".pdf")

    if ($NichtUeberschreiben -and (Test-Path -LiteralPath $pdfPath)) {
      Add-Fail "PDF existiert bereits und `-NichtUeberschreiben` ist gesetzt: $pdfPath"
      exit 1
    }

    $profileDir = Join-Path -Path $workDir -ChildPath "Profile-$($candidate.Name)"
    $errorMessage = Export-HtmlToPdf -BrowserInfo $candidate -HtmlFile $html -PdfPath $pdfPath -ProfileDir $profileDir -MinPdfBytes $MinPdfBytes

    if ($errorMessage) {
      $candidateOk = $false
      $browserErrors.Add("$($candidate.Name): $errorMessage") | Out-Null
      break
    }

    $exportedPdfs.Add($pdfPath) | Out-Null
    $pdfInfo = Get-Item -LiteralPath $pdfPath
    Add-Ok "$($candidate.Name): PDF erzeugt: $([System.IO.Path]::GetFileName($pdfPath)) ($($pdfInfo.Length) Bytes)"
  }

  if ($candidateOk) {
    Add-Ok "PDF-Export erfolgreich mit Browser: $($candidate.Name)"
    Write-Host ""
    Write-Host "Erzeugte PDFs:"
    foreach ($pdf in $exportedPdfs) {
      Write-Host "- $pdf"
    }
    Write-Host ""
    Write-Host "ERGEBNIS: OK" -ForegroundColor Green
    exit 0
  }

  Add-Warn "Browser $($candidate.Name) konnte nicht alle PDFs erzeugen. Nächster Kandidat wird versucht."
}

foreach ($message in $browserErrors) {
  Add-Fail $message
}

Add-Fail "PDF-Export fehlgeschlagen: Kein Browser hat alle erwarteten PDFs erzeugt."
exit 1
