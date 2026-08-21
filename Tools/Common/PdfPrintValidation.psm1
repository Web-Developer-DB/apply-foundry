#requires -Version 7.6
#requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Platform.psm1')

function Get-HtmlExplicitPageCount {
  param([Parameter(Mandatory)][string]$Path)

  $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
  return [regex]::Matches(
    $text,
    '<main\b(?=[^>]*\bclass\s*=\s*["''][^"'']*\bpage\b[^"'']*["''])[^>]*>',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
  ).Count
}

function Get-PdfMediaBoxes {
  param([Parameter(Mandatory)][string]$Path)

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
  param([Parameter(Mandatory)][string]$Path)

  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $text = [System.Text.Encoding]::ASCII.GetString($bytes)
  return [regex]::Matches($text, '/Type\s*/Page(?!s)').Count
}

function Format-PdfMediaBoxSummary {
  param([Parameter(Mandatory)][string]$Path)

  $boxes = @(Get-PdfMediaBoxes -Path $Path)
  if ($boxes.Count -eq 0) { return $null }
  return ('{0:N2} x {1:N2} pt' -f $boxes[0].Width, $boxes[0].Height)
}

function Test-PrintedPdf {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][int]$MinBytes,
    [Parameter(Mandatory)][int]$ExpectedPageCount,
    [Parameter(Mandatory)][datetime]$RunStartedUtc
  )

  $result = [ordered]@{
    valid = $false
    error = $null
    bytes = [int64]0
    expectedPageCount = $ExpectedPageCount
    actualPageCount = 0
    mediaBox = $null
    a4 = $false
  }
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    $result.error = "PDF wurde nicht erzeugt: $Path"
    return [pscustomobject]$result
  }
  $info = Get-Item -LiteralPath $Path
  $result.bytes = [int64]$info.Length
  if ($info.LastWriteTimeUtc -lt $RunStartedUtc.AddSeconds(-1)) {
    $result.error = "PDF ist älter als der aktuelle Browserlauf: $Path"
    return [pscustomobject]$result
  }
  if ($info.Length -lt $MinBytes) {
    $result.error = "PDF ist zu klein ($($info.Length) Bytes): $Path"
    return [pscustomobject]$result
  }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -lt 8 -or [System.Text.Encoding]::ASCII.GetString($bytes, 0, 5) -ne '%PDF-') {
    $result.error = "PDF-Datei hat keinen PDF-Header: $Path"
    return [pscustomobject]$result
  }
  $tailLength = [Math]::Min(4096, $bytes.Length)
  $tail = [System.Text.Encoding]::ASCII.GetString($bytes, $bytes.Length - $tailLength, $tailLength)
  if ($tail -notmatch '%%EOF\s*$') {
    $result.error = "PDF-Datei hat keinen gültigen EOF-Marker: $Path"
    return [pscustomobject]$result
  }
  $boxes = @(Get-PdfMediaBoxes -Path $Path)
  if ($boxes.Count -eq 0) {
    $result.error = "PDF enthält keine lesbare MediaBox: $Path"
    return [pscustomobject]$result
  }
  $result.mediaBox = Format-PdfMediaBoxSummary -Path $Path
  foreach ($box in $boxes) {
    if ($box.Width -lt 590 -or $box.Width -gt 600 -or $box.Height -lt 838 -or $box.Height -gt 846) {
      $result.error = ('PDF ist nicht DIN A4. MediaBox: {0:N2} x {1:N2} pt, erwartet ca. 595 x 842 pt: {2}' -f $box.Width, $box.Height, $Path)
      return [pscustomobject]$result
    }
  }
  $result.a4 = $true
  $result.actualPageCount = Get-PdfPageCount -Path $Path
  if ($result.actualPageCount -eq 0) {
    $result.error = "PDF-Seitenzahl konnte nicht zuverlässig gelesen werden: $Path"
    return [pscustomobject]$result
  }
  if ($result.actualPageCount -ne $ExpectedPageCount) {
    $result.error = "PDF-Seitenzahl stimmt nicht mit den expliziten HTML-A4-Seiten überein ($($result.actualPageCount) statt $ExpectedPageCount): $Path"
    return [pscustomobject]$result
  }
  $result.valid = $true
  return [pscustomobject]$result
}

function Remove-PrintValidationTemporaryDirectory {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Root)

  if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
  for ($attempt = 1; $attempt -le 5; $attempt++) {
    try {
      $safePath = Platform\Resolve-SafePath -Candidate $Path -Root $Root -MustExist -ForWrite -PathType Container
      Remove-Item -LiteralPath $safePath -Recurse -Force -ErrorAction Stop
    } catch {
      if ($attempt -lt 5) { Start-Sleep -Milliseconds 200 }
    }
    if (-not (Test-Path -LiteralPath $Path)) { return }
  }
}

function Invoke-HtmlPrintPreflight {
  param(
    [Parameter(Mandatory)][pscustomobject]$BrowserInfo,
    [Parameter(Mandatory)][System.IO.FileInfo]$HtmlFile,
    [Parameter(Mandatory)][string]$BrowserTempRoot,
    [ValidateRange(100, 100000000)][int]$MinPdfBytes = 5000,
    [ValidateRange(1, 600)][int]$TimeoutSeconds = 60,
    [string]$CopyValidatedPdfTo
  )

  $expectedPageCount = Get-HtmlExplicitPageCount -Path $HtmlFile.FullName
  $result = [ordered]@{
    succeeded = $false
    error = $null
    expectedPageCount = $expectedPageCount
    actualPageCount = 0
    pdfBytes = [int64]0
    mediaBox = $null
    a4 = $false
  }
  if ($expectedPageCount -eq 0) {
    $result.error = "HTML enthält keine expliziten A4-Seitencontainer: $($HtmlFile.Name)"
    return [pscustomobject]$result
  }
  $runRoot = Platform\Resolve-SafePath -Candidate (Join-Path -Path $BrowserTempRoot -ChildPath ('P-' + [guid]::NewGuid().ToString('N'))) -Root $BrowserTempRoot -ForWrite -PathType Container
  $profileDir = Join-Path -Path $runRoot -ChildPath 'profile'
  $browserPdfPath = Join-Path -Path $runRoot -ChildPath 'output.pdf'
  try {
    if (-not [string]::IsNullOrWhiteSpace($CopyValidatedPdfTo) -and (Test-Path -LiteralPath $CopyValidatedPdfTo -PathType Leaf)) {
      Remove-Item -LiteralPath $CopyValidatedPdfTo -Force
    }
    New-Item -Path $runRoot -ItemType Directory | Out-Null
    New-Item -Path $profileDir -ItemType Directory | Out-Null
    $arguments = @(
      '--headless=new', '--disable-gpu', '--disable-gpu-sandbox', '--no-sandbox', '--disable-dev-shm-usage',
      '--no-first-run', '--disable-background-networking', '--disable-extensions',
      "--user-data-dir=$profileDir", "--print-to-pdf=$browserPdfPath", '--print-to-pdf-no-header', '--no-pdf-header-footer',
      ([System.Uri]::new($HtmlFile.FullName).AbsoluteUri)
    )
    $runStartedUtc = [datetime]::UtcNow
    $process = Platform\Invoke-NativeProcess -FilePath $BrowserInfo.Path -ArgumentList $arguments -TimeoutSeconds $TimeoutSeconds -MaxStdoutChars 4096 -MaxStderrChars 8192
    if ($process.TimedOut) {
      $result.error = "Browser $($BrowserInfo.Name) überschritt das Zeitlimit von $TimeoutSeconds Sekunden für $($HtmlFile.Name)."
      return [pscustomobject]$result
    }
    if ($process.ExitCode -ne 0) {
      $stderr = $process.StandardError.Trim()
      $suffix = if ([string]::IsNullOrWhiteSpace($stderr)) { '' } else { " stderr: $stderr" }
      $result.error = "Browser $($BrowserInfo.Name) beendete mit Exitcode $($process.ExitCode) für $($HtmlFile.Name).$suffix"
      return [pscustomobject]$result
    }
    $validation = Test-PrintedPdf -Path $browserPdfPath -MinBytes $MinPdfBytes -ExpectedPageCount $expectedPageCount -RunStartedUtc $runStartedUtc
    $result.actualPageCount = $validation.actualPageCount
    $result.pdfBytes = $validation.bytes
    $result.mediaBox = $validation.mediaBox
    $result.a4 = $validation.a4
    if (-not $validation.valid) {
      $result.error = $validation.error
      return [pscustomobject]$result
    }
    if (-not [string]::IsNullOrWhiteSpace($CopyValidatedPdfTo)) {
      Copy-Item -LiteralPath $browserPdfPath -Destination $CopyValidatedPdfTo
      $copyValidation = Test-PrintedPdf -Path $CopyValidatedPdfTo -MinBytes $MinPdfBytes -ExpectedPageCount $expectedPageCount -RunStartedUtc $runStartedUtc
      if (-not $copyValidation.valid) {
        $result.error = $copyValidation.error
        return [pscustomobject]$result
      }
    }
    $result.succeeded = $true
    return [pscustomobject]$result
  } catch {
    $result.error = $_.Exception.Message
    return [pscustomobject]$result
  } finally {
    Remove-PrintValidationTemporaryDirectory -Path $runRoot -Root $BrowserTempRoot
  }
}

Export-ModuleMember -Function @(
  'Get-HtmlExplicitPageCount', 'Get-PdfMediaBoxes', 'Get-PdfPageCount', 'Format-PdfMediaBoxSummary',
  'Test-PrintedPdf', 'Invoke-HtmlPrintPreflight'
)
