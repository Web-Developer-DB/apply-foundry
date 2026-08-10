#requires -Version 7.6
#requires -PSEdition Core

[CmdletBinding()]
param(
  [ValidateSet('auto', 'chrome', 'edge', 'chromium', 'firefox')]
  [string]$Browser = 'auto',

  [string]$BrowserExecutablePath,

  [switch]$AlsJson,

  [switch]$BrowserErforderlich
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$platformModule = Join-Path -Path $PSScriptRoot -ChildPath 'Common'
$platformModule = Join-Path -Path $platformModule -ChildPath 'Platform.psm1'
Import-Module -Name $platformModule -Force

$checks = [System.Collections.Generic.List[object]]::new()
$exitCode = 0

function Add-DiagnosticCheck {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][ValidateSet('ok', 'warning', 'error')][string]$Status,
    [Parameter(Mandatory)][bool]$Required,
    [Parameter(Mandatory)][string]$Detail,
    [ValidateSet(0, 1, 2)][int]$FailureExitCode = 1
  )

  $script:checks.Add([pscustomobject][ordered]@{
    name = $Name
    status = $Status
    required = $Required
    detail = $Detail
  })
  if ($Status -eq 'error' -and $Required) {
    $script:exitCode = [math]::Max($script:exitCode, $FailureExitCode)
  }
}

function Test-TemporaryWriteAccess {
  $temporaryDirectory = [System.IO.Path]::GetTempPath()
  if (-not (Test-Path -LiteralPath $temporaryDirectory -PathType Container)) {
    throw "Temporärverzeichnis existiert nicht: $temporaryDirectory"
  }
  $probePath = Join-Path -Path $temporaryDirectory -ChildPath ('.bewerbungs-agent-probe-' + [guid]::NewGuid().ToString('N'))
  $stream = $null
  try {
    $stream = [System.IO.File]::Open($probePath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    $stream.WriteByte(42)
    $stream.Flush($true)
  } finally {
    if ($null -ne $stream) { $stream.Dispose() }
    if (Test-Path -LiteralPath $probePath) {
      Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
    }
  }
  if (Test-Path -LiteralPath $probePath) {
    throw "Temporäre Prüfdatei konnte nicht rückstandsfrei entfernt werden: $probePath"
  }
  return $temporaryDirectory
}

function Test-RequiredFont {
  param([Parameter(Mandatory)][object]$Platform)

  if ($Platform.IsWindows) {
    if ([string]::IsNullOrWhiteSpace($env:WINDIR)) {
      return [pscustomobject]@{ Available = $false; Font = 'Arial'; Detail = 'WINDIR ist nicht verfügbar.' }
    }
    $fontsDirectory = Join-Path -Path $env:WINDIR -ChildPath 'Fonts'
    $arial = Join-Path -Path $fontsDirectory -ChildPath 'arial.ttf'
    $available = Test-Path -LiteralPath $arial -PathType Leaf
    return [pscustomobject]@{
      Available = $available
      Font = 'Arial'
      Detail = if ($available) { "Arial gefunden: $arial" } else { "Arial fehlt im Windows-Schriftordner: $arial" }
    }
  }

  $knownLiberationPaths = @(
    '/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf',
    '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf'
  )
  foreach ($fontPath in $knownLiberationPaths) {
    if (Test-Path -LiteralPath $fontPath -PathType Leaf) {
      return [pscustomobject]@{ Available = $true; Font = 'Liberation Sans'; Detail = "Liberation Sans gefunden: $fontPath" }
    }
  }

  $fontConfig = Get-Command -Name 'fc-match' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($fontConfig -and $fontConfig.Source) {
    $fontProbe = Invoke-NativeProcess -FilePath $fontConfig.Source -ArgumentList @('--format=%{family}', 'Liberation Sans') -TimeoutSeconds 10 -MaxStdoutChars 4096 -MaxStderrChars 4096
    $available = -not $fontProbe.TimedOut -and $fontProbe.ExitCode -eq 0 -and $fontProbe.StandardOutput -match '(?i)(^|,)Liberation Sans($|,)'
    return [pscustomobject]@{
      Available = $available
      Font = 'Liberation Sans'
      Detail = if ($available) { 'Liberation Sans wurde über fontconfig gefunden.' } else { 'fontconfig meldet keine installierte Liberation Sans.' }
    }
  }
  return [pscustomobject]@{ Available = $false; Font = 'Liberation Sans'; Detail = 'Weder Liberation Sans noch fontconfig wurden gefunden.' }
}

$platform = Get-PlatformInfo
$powerShellOk = $PSVersionTable.PSEdition -eq 'Core' -and $PSVersionTable.PSVersion -ge [version]'7.6'
Add-DiagnosticCheck -Name 'powershell' -Status $(if ($powerShellOk) { 'ok' } else { 'error' }) -Required $true `
  -Detail "PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition)); erforderlich: Core 7.6 oder neuer." -FailureExitCode 2

$platformDetail = if ($platform.IsLinux) {
  "$($platform.OSDescription); Distribution $($platform.DistributionId) $($platform.DistributionVersion); Architektur $($platform.Architecture)."
} else {
  "$($platform.OSDescription); Architektur $($platform.Architecture)."
}
Add-DiagnosticCheck -Name 'plattform' -Status $(if ($platform.Supported) { 'ok' } else { 'error' }) -Required $true `
  -Detail $platformDetail -FailureExitCode 2

try {
  $temporaryDirectory = Test-TemporaryWriteAccess
  Add-DiagnosticCheck -Name 'temp_schreibzugriff' -Status 'ok' -Required $true -Detail "Temporärer Schreib-/Löschtest bestanden: $temporaryDirectory"
} catch {
  Add-DiagnosticCheck -Name 'temp_schreibzugriff' -Status 'error' -Required $true -Detail $_.Exception.Message
}

$bashRequired = [bool]$platform.IsLinux
try {
  $bashCommand = Get-Command -Name 'bash' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $bashCommand -or [string]::IsNullOrWhiteSpace($bashCommand.Source)) {
    throw 'Bash wurde nicht gefunden.'
  }
  $bashProbe = Invoke-NativeProcess -FilePath $bashCommand.Source -ArgumentList @('--version') -TimeoutSeconds 10 -MaxStdoutChars 4096 -MaxStderrChars 4096
  if ($bashProbe.TimedOut -or $bashProbe.ExitCode -ne 0) {
    throw "Bash-Versionsprüfung schlug fehl (Exitcode $($bashProbe.ExitCode), Timeout=$($bashProbe.TimedOut))."
  }
  $bashVersion = ($bashProbe.StandardOutput -split '[\r\n]+' | Select-Object -First 1).Trim()
  Add-DiagnosticCheck -Name 'bash' -Status 'ok' -Required $bashRequired -Detail "$bashVersion ($($bashCommand.Source))"
} catch {
  Add-DiagnosticCheck -Name 'bash' -Status $(if ($bashRequired) { 'error' } else { 'warning' }) -Required $bashRequired -Detail $_.Exception.Message
}

try {
  $font = Test-RequiredFont -Platform $platform
  Add-DiagnosticCheck -Name 'schriftart' -Status $(if ($font.Available) { 'ok' } else { 'error' }) -Required $true -Detail $font.Detail
} catch {
  Add-DiagnosticCheck -Name 'schriftart' -Status 'error' -Required $true -Detail $_.Exception.Message
}

$browserInfo = $null
$browserSelectionIsRequired = [bool]($BrowserErforderlich -or $Browser -ne 'auto' -or -not [string]::IsNullOrWhiteSpace($BrowserExecutablePath))
try {
  $allowFirefox = $Browser -eq 'firefox'
  $browserCandidates = @(Get-BrowserCandidates -RequestedBrowser $Browser -ExecutablePath $BrowserExecutablePath -AllowFirefox:$allowFirefox)
  if ($browserCandidates.Count -eq 0) {
    throw "Kein passender Browser gefunden (Auswahl: $Browser)."
  }
  $browserInfo = $browserCandidates[0]
  Add-DiagnosticCheck -Name 'browser' -Status 'ok' -Required $browserSelectionIsRequired `
    -Detail "$($browserInfo.Name) $($browserInfo.Version) [$($browserInfo.Engine)] ($($browserInfo.Path))"
} catch {
  Add-DiagnosticCheck -Name 'browser' -Status $(if ($browserSelectionIsRequired) { 'error' } else { 'warning' }) `
    -Required $browserSelectionIsRequired -Detail $_.Exception.Message
}

$runtimeFingerprint = Get-RuntimeFingerprint -BrowserInfo $browserInfo
$status = if ($exitCode -eq 2) {
  'nicht_unterstuetzt'
} elseif ($exitCode -eq 1) {
  'nicht_bereit'
} elseif (@($checks | Where-Object { $_.status -eq 'warning' }).Count -gt 0) {
  'bereit_mit_warnungen'
} else {
  'bereit'
}

$report = [pscustomobject][ordered]@{
  schemaVersion = 1
  checkedAtUtc = [datetime]::UtcNow.ToString('o')
  status = $status
  exitCode = $exitCode
  checks = $checks.ToArray()
  runtimeFingerprint = $runtimeFingerprint
}

if ($AlsJson) {
  $report | ConvertTo-Json -Depth 8
} else {
  foreach ($check in $checks) {
    $prefix = switch ($check.status) {
      'ok' { '[OK]' }
      'warning' { '[WARNUNG]' }
      default { '[FEHLER]' }
    }
    Write-Host "$prefix $($check.name): $($check.detail)"
  }
  Write-Host "Diagnosestatus: $status (Exitcode $exitCode)"
}

exit $exitCode
