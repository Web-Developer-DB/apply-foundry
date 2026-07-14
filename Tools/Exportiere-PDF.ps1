[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Ordner,

  [ValidateSet("auto", "chrome", "edge")]
  [string]$Browser = "auto",

  [switch]$MitLayoutcheck,

  [switch]$NichtUeberschreiben,

  [ValidateRange(100, 100000000)]
  [int]$MinPdfBytes = 5000,

  [ValidateRange(1, 600)]
  [int]$TimeoutSeconds = 60
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

function ConvertTo-QuotedArgument {
  param([string]$Value)
  if ($Value -match '[\s"]') {
    return '"' + ($Value -replace '"', '\"') + '"'
  }
  return $Value
}

function Convert-ToSafeFilePart {
  param([string]$Value)
  $safe = $Value -replace '[\\/:*?"<>|]+', '-'
  $safe = $safe -replace '\s+', '-'
  return $safe.Trim('-')
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

  $localChrome = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA "Google\Chrome\Application\chrome.exe" } else { $null }
  $localEdge = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA "Microsoft\Edge\Application\msedge.exe" } else { $null }
  $known = @(
    @{ Name = "chrome"; Paths = @("C:\Program Files\Google\Chrome\Application\chrome.exe", "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe", $localChrome); Commands = @("chrome", "chrome.exe") },
    @{ Name = "edge"; Paths = @("C:\Program Files\Microsoft\Edge\Application\msedge.exe", "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe", $localEdge); Commands = @("msedge", "msedge.exe") }
  )

  $candidates = @()
  foreach ($entry in $known) {
    if (($RequestedBrowser -ne "auto") -and ($entry.Name -ne $RequestedBrowser)) {
      continue
    }

    foreach ($path in @($entry.Paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
      if (Test-Path -LiteralPath $path -PathType Leaf) {
        $candidates += [pscustomobject]@{ Name = $entry.Name; Path = $path }
        break
      }
    }

    if (@($candidates | Where-Object { $_.Name -eq $entry.Name }).Count -gt 0) {
      continue
    }

    foreach ($command in $entry.Commands) {
      $cmd = Get-Command $command -ErrorAction SilentlyContinue
      if ($cmd -and $cmd.Source) {
        $candidates += [pscustomobject]@{ Name = $entry.Name; Path = $cmd.Source }
        break
      }
    }
  }

  return $candidates
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
    [string]$ProfileDir,
    [int]$MinPdfBytes,
    [int]$TimeoutSeconds
  )

  try {
    if (Test-Path -LiteralPath $TemporaryPdfPath) {
      Remove-Item -LiteralPath $TemporaryPdfPath -Force
    }
    New-Item -Path $ProfileDir -ItemType Directory -Force | Out-Null

    $uri = [System.Uri]::new($HtmlFile.FullName).AbsoluteUri
    $arguments = @(
      "--headless=new",
      "--disable-gpu",
      "--no-first-run",
      "--disable-background-networking",
      "--disable-extensions",
      "--user-data-dir=$ProfileDir",
      "--print-to-pdf=$TemporaryPdfPath",
      "--print-to-pdf-no-header",
      "--no-pdf-header-footer",
      $uri
    )

    $argumentLine = ($arguments | ForEach-Object { ConvertTo-QuotedArgument -Value $_ }) -join " "
    $runStartedUtc = [datetime]::UtcNow
    $process = Start-Process -FilePath $BrowserInfo.Path -ArgumentList $argumentLine -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
      Stop-BrowserProcessTree -Process $process
      return "Browser $($BrowserInfo.Name) überschritt das Zeitlimit von $TimeoutSeconds Sekunden für $($HtmlFile.Name)."
    }
    if ($process.ExitCode -ne 0) {
      return "Browser $($BrowserInfo.Name) beendete mit Exitcode $($process.ExitCode) für $($HtmlFile.Name)."
    }

    $expectedPageCount = Get-HtmlPageCount -Path $HtmlFile.FullName
    if ($expectedPageCount -eq 0) {
      return "HTML enthält keine expliziten A4-Seitencontainer: $($HtmlFile.Name)"
    }
    return Test-PdfFile -Path $TemporaryPdfPath -MinBytes $MinPdfBytes -ExpectedPageCount $expectedPageCount -RunStartedUtc $runStartedUtc
  } catch {
    return $_.Exception.Message
  } finally {
    if (Test-Path -LiteralPath $ProfileDir -PathType Container) {
      Remove-Item -LiteralPath $ProfileDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

function Publish-PdfSet {
  param(
    [object[]]$PdfSet,
    [string]$RunDirectory
  )

  $backups = New-Object System.Collections.Generic.List[object]
  $published = New-Object System.Collections.Generic.List[string]
  try {
    foreach ($item in $PdfSet) {
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

    foreach ($backup in $backups) {
      Remove-Item -LiteralPath $backup.BackupPath -Force -ErrorAction SilentlyContinue
    }
  } catch {
    foreach ($path in $published) {
      Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
    foreach ($backup in $backups) {
      if (Test-Path -LiteralPath $backup.BackupPath -PathType Leaf) {
        Move-Item -LiteralPath $backup.BackupPath -Destination $backup.FinalPath -Force -ErrorAction SilentlyContinue
      }
    }
    throw
  }
}

if (-not (Test-Path -LiteralPath $Ordner -PathType Container)) {
  Add-Fail "Ordner existiert nicht oder ist kein Verzeichnis: $Ordner"
  exit 1
}

$resolvedFolder = (Resolve-Path -LiteralPath $Ordner).Path
$checkerPath = Join-Path -Path $PSScriptRoot -ChildPath "Pruefe-Bewerbung.ps1"
$layoutcheckPath = Join-Path -Path $PSScriptRoot -ChildPath "Layoutcheck-Bewerbung.ps1"

if (-not (Test-Path -LiteralPath $checkerPath -PathType Leaf)) {
  Add-Fail "Statischer Prüfer nicht gefunden: $checkerPath"
  exit 1
}

Invoke-ToolScript -ScriptPath $checkerPath -Arguments @("-Ordner", $resolvedFolder)

if ($MitLayoutcheck) {
  if (-not (Test-Path -LiteralPath $layoutcheckPath -PathType Leaf)) {
    Add-Fail "Layoutcheck-Tool nicht gefunden: $layoutcheckPath"
    exit 1
  }
  Invoke-ToolScript -ScriptPath $layoutcheckPath -Arguments @("-Ordner", $resolvedFolder, "-Browser", $Browser, "-TimeoutSeconds", "$TimeoutSeconds")
}

$htmlFiles = @(Get-ChildItem -LiteralPath $resolvedFolder -File -Filter "*.html" | Where-Object {
  $_.Name -match '^(Lebenslauf|Anschreiben) - .+\.html$'
} | Sort-Object Name)

if ($htmlFiles.Count -ne 2) {
  Add-Fail "Genau zwei finale HTML-Dateien werden erwartet; gefunden: $($htmlFiles.Count)."
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

$finalPdfPaths = @($htmlFiles | ForEach-Object { [System.IO.Path]::ChangeExtension($_.FullName, ".pdf") })
foreach ($finalPdfPath in $finalPdfPaths) {
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

Add-Info "Finaler Bewerbungsordner: $resolvedFolder"
Add-Info "PDF-Export-Arbeitsordner: $workDir"
Add-Info "HTML-Dateien: $($htmlFiles.Name -join ', ')"

$browserCandidates = @(Get-BrowserCandidates -RequestedBrowser $Browser)
if ($browserCandidates.Count -eq 0) {
  Add-Fail "Kein Chromium-Browser gefunden. Unterstützt werden Chrome oder Edge."
  exit 1
}

Add-Info "Browser-Kandidaten: $($browserCandidates.Name -join ', ')"
$browserErrors = New-Object System.Collections.Generic.List[string]

foreach ($candidate in $browserCandidates) {
  # Kurze interne Namen vermeiden Chromes Windows-Pfadgrenze bei tiefen
  # Bewerbungsordnern. Der Lauf bleibt durch die GUID trotzdem eindeutig.
  $runId = [guid]::NewGuid().ToString("N").Substring(0, 8)
  $runDir = Join-Path -Path $workDir -ChildPath "R-$runId"
  New-Item -Path $runDir -ItemType Directory -Force | Out-Null
  Add-Info "Teste PDF-Export mit Browser: $($candidate.Name) ($($candidate.Path))"

  $pdfSet = @()
  $candidateOk = $true
  foreach ($html in $htmlFiles) {
    $safeBase = Convert-ToSafeFilePart -Value $html.BaseName
    $temporaryPdfPath = Join-Path -Path $runDir -ChildPath "$safeBase.pdf"
    $finalPdfPath = [System.IO.Path]::ChangeExtension($html.FullName, ".pdf")
    $profileDir = Join-Path -Path $runDir -ChildPath ("P-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
    $errorMessage = Export-HtmlToPdf -BrowserInfo $candidate -HtmlFile $html -TemporaryPdfPath $temporaryPdfPath -ProfileDir $profileDir -MinPdfBytes $MinPdfBytes -TimeoutSeconds $TimeoutSeconds

    if ($errorMessage) {
      $candidateOk = $false
      $browserErrors.Add("$($candidate.Name): $errorMessage") | Out-Null
      break
    }

    $pdfSet += [pscustomobject]@{
      HtmlFile = $html
      TemporaryPath = $temporaryPdfPath
      FinalPath = $finalPdfPath
    }
    $pdfInfo = Get-Item -LiteralPath $temporaryPdfPath
    Add-Ok "$($candidate.Name): temporäre PDF validiert: $($html.Name) ($($pdfInfo.Length) Bytes, $(Get-PdfPageCount -Path $temporaryPdfPath) Seite(n))"
  }

  if ($candidateOk -and ($pdfSet.Count -eq $htmlFiles.Count)) {
    try {
      Publish-PdfSet -PdfSet $pdfSet -RunDirectory $runDir
      Add-Ok "PDF-Export vollständig und atomar veröffentlicht mit Browser: $($candidate.Name)"
      Write-Host ""
      Write-Host "Erzeugte PDFs:"
      foreach ($item in $pdfSet) {
        $pdfInfo = Get-Item -LiteralPath $item.FinalPath
        $mediaBoxSummary = Format-PdfMediaBoxSummary -Path $item.FinalPath
        Write-Host "- $($item.FinalPath) ($($pdfInfo.Length) Bytes, $(Get-PdfPageCount -Path $item.FinalPath) Seite(n), $mediaBoxSummary)"
      }
      Remove-Item -LiteralPath $runDir -Recurse -Force -ErrorAction SilentlyContinue
      Write-Host ""
      Write-Host "ERGEBNIS: OK" -ForegroundColor Green
      exit 0
    } catch {
      $browserErrors.Add("$($candidate.Name): Veröffentlichung der validierten PDFs fehlgeschlagen: $($_.Exception.Message)") | Out-Null
      $candidateOk = $false
    }
  }

  Remove-Item -LiteralPath $runDir -Recurse -Force -ErrorAction SilentlyContinue
  Add-Warn "Browser $($candidate.Name) konnte kein vollständig validiertes PDF-Set erzeugen. Nächster Kandidat wird versucht."
}

foreach ($message in $browserErrors) {
  Add-Fail $message
}
Add-Fail "PDF-Export fehlgeschlagen: Kein Browser hat beide PDFs frisch, seitenrichtig und vollständig erzeugt."
exit 1
