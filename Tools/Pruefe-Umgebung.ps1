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
  $probePath = Join-Path -Path $temporaryDirectory -ChildPath ('.apply-foundry-probe-' + [guid]::NewGuid().ToString('N'))
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
      return [pscustomobject]@{ Available = $false; Font = 'Arial'; Path = $null; Version = $null; Detail = 'WINDIR ist nicht verfügbar.' }
    }
    $fontsDirectory = Join-Path -Path $env:WINDIR -ChildPath 'Fonts'
    $arial = Join-Path -Path $fontsDirectory -ChildPath 'arial.ttf'
    $available = Test-Path -LiteralPath $arial -PathType Leaf
    return [pscustomobject]@{
      Available = $available
      Font = 'Arial'
      Path = $arial
      Version = $null
      Detail = if ($available) { "Arial gefunden: $arial" } else { "Arial fehlt im Windows-Schriftordner: $arial" }
    }
  }

  $knownLiberationPaths = @(
    '/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf',
    '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf'
  )
  foreach ($fontPath in $knownLiberationPaths) {
    if (Test-Path -LiteralPath $fontPath -PathType Leaf) {
      return [pscustomobject]@{ Available = $true; Font = 'Liberation Sans'; Path = $fontPath; Version = $null; Detail = "Liberation Sans gefunden: $fontPath" }
    }
  }

  $fontConfig = Get-Command -Name 'fc-match' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($fontConfig -and $fontConfig.Source) {
    $fontProbe = Invoke-NativeProcess -FilePath $fontConfig.Source -ArgumentList @('--format=%{family}', 'Liberation Sans') -TimeoutSeconds 10 -MaxStdoutChars 4096 -MaxStderrChars 4096
    $available = -not $fontProbe.TimedOut -and $fontProbe.ExitCode -eq 0 -and $fontProbe.StandardOutput -match '(?i)(^|,)Liberation Sans($|,)'
    $fontPathProbe = Invoke-NativeProcess -FilePath $fontConfig.Source -ArgumentList @('--format=%{file}', 'Liberation Sans') -TimeoutSeconds 10 -MaxStdoutChars 4096 -MaxStderrChars 4096
    $fontPath = ($fontPathProbe.StandardOutput -split '[\r\n]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
    if (-not $available) { $fontPath = $null }
    return [pscustomobject]@{
      Available = $available
      Font = 'Liberation Sans'
      Path = $fontPath
      Version = $null
      Detail = if ($available) { 'Liberation Sans wurde über fontconfig gefunden.' } else { 'fontconfig meldet keine installierte Liberation Sans.' }
    }
  }
  return [pscustomobject]@{ Available = $false; Font = 'Liberation Sans'; Path = $null; Version = $null; Detail = 'Weder Liberation Sans noch fontconfig wurden gefunden.' }
}

function Get-ExecutableDetails {
  param(
    [Parameter(Mandatory)][string[]]$Names,
    [string]$VersionArgument = '--version'
  )

  $command = $null
  foreach ($name in $Names) {
    $command = Get-Command -Name $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { break }
  }
  if ($null -eq $command -or [string]::IsNullOrWhiteSpace($command.Source)) {
    return [pscustomobject]@{ Available = $false; Version = $null; Path = $null; Detail = "Nicht gefunden: $($Names -join ', ')" }
  }
  $probe = Invoke-NativeProcess -FilePath $command.Source -ArgumentList @($VersionArgument) -TimeoutSeconds 8 -MaxStdoutChars 4096 -MaxStderrChars 4096
  $text = (($probe.StandardOutput + $probe.StandardError) -replace '[\r\n]+', ' ').Trim()
  $match = [regex]::Match($text, '(?<!\d)(?:v)?(?<version>\d+(?:\.\d+){1,3})(?!\d)')
  $available = -not $probe.TimedOut -and $probe.ExitCode -eq 0 -and $match.Success
  return [pscustomobject]@{
    Available = $available
    Version = if ($match.Success) { $match.Groups['version'].Value } else { $null }
    Path = (Resolve-Path -LiteralPath $command.Source).Path
    Detail = if ($available) { "$text ($($command.Source))" } else { "Versionsprüfung fehlgeschlagen: $($command.Source)" }
  }
}

$platform = Get-PlatformInfo
$powerShellOk = $PSVersionTable.PSEdition -eq 'Core' -and $PSVersionTable.PSVersion -ge [version]'7.6'
$powerShellDetail = if ($platform.IsLinux) {
  "PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition)) ist als Legacy-Fallback verfügbar. Der produktive Linux-Kern ist System-Python 3.9+; prüfen Sie ihn mit python3 Tools/setup-linux.py --runtime --dry-run --format json."
} else {
  "PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition)); erforderlich: Core 7.6 oder neuer. Bei fehlender Runtime: Tools/setup-windows.ps1 -Runtime -DryRun -Format json."
}
Add-DiagnosticCheck -Name 'powershell' -Status $(if ($powerShellOk) { 'ok' } else { 'error' }) -Required $true `
  -Detail $powerShellDetail -FailureExitCode 2

$platformDetail = if ($platform.IsLinux) {
  "$($platform.OSDescription); Distribution $($platform.DistributionId) $($platform.DistributionVersion); Architektur $($platform.Architecture)."
} else {
  "$($platform.OSDescription); Architektur $($platform.Architecture)."
}
Add-DiagnosticCheck -Name 'plattform' -Status $(if ($platform.Supported) { 'ok' } else { 'error' }) -Required $true `
  -Detail "$platformDetail Paketmanager: $($platform.PackageManager). Unterstützt werden Windows x64 sowie Linux x64 mit APT, DNF/YUM, Pacman oder Zypper." -FailureExitCode 2

if ($platform.IsLinux) {
  Add-DiagnosticCheck -Name 'paketmanager' -Status $(if ($platform.PackageManager) { 'ok' } else { 'error' }) -Required $true `
    -Detail $(if ($platform.PackageManager) { "Erkannt: $($platform.PackageManager)." } else { 'Kein unterstützter Paketmanager erkannt; python3 Tools/setup-linux.py gibt nur eine manuelle Anleitung aus.' }) -FailureExitCode 2
}

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
  $font = [pscustomobject]@{ Available = $false; Font = if ($platform.IsWindows) { 'Arial' } else { 'Liberation Sans' }; Path = $null; Version = $null; Detail = $_.Exception.Message }
  Add-DiagnosticCheck -Name 'schriftart' -Status 'error' -Required $true -Detail $_.Exception.Message
}

$shellCheck = Get-ExecutableDetails -Names @('shellcheck', 'shellcheck.exe')
Add-DiagnosticCheck -Name 'shellcheck' -Status $(if ($shellCheck.Available) { 'ok' } else { 'warning' }) -Required $false `
  -Detail $(if ($shellCheck.Available) { $shellCheck.Detail } else { if ($platform.IsLinux) { 'ShellCheck fehlt; für die vollständige Bash-/CI-Prüfung python3 Tools/setup-linux.py --shellcheck --dry-run verwenden.' } else { 'ShellCheck fehlt; für die vollständige Bash-/CI-Prüfung Tools/setup-windows.ps1 -ShellCheck verwenden.' } })

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

$powerShellPath = $null
$powerShellCommand = Get-Command -Name 'pwsh' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($powerShellCommand -and $powerShellCommand.Source) {
  $powerShellPath = (Resolve-Path -LiteralPath $powerShellCommand.Source).Path
} else {
  $powerShellCandidate = Join-Path -Path $PSHOME -ChildPath $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
  if (Test-Path -LiteralPath $powerShellCandidate -PathType Leaf) { $powerShellPath = $powerShellCandidate }
}

$setupBase = if ($platform.IsWindows) { 'Tools/setup-windows.ps1' } else { 'python3 Tools/setup-linux.py' }
$runtimeSetupOption = if ($platform.IsWindows) { '-Runtime' } else { '--runtime' }
$browserSetupOption = if ($platform.IsWindows) { '-Browser chromium' } else { '--browser chromium' }
$fontSetupOption = if ($platform.IsWindows) { '-Fonts' } else { '--fonts' }
$shellCheckSetupOption = if ($platform.IsWindows) { '-ShellCheck' } else { '--shellcheck' }
$runtimeSolution = if ($platform.IsWindows) {
  'Microsoft.PowerShell über winget'
} else {
  'Bereits installierter PowerShell-Legacy-Fallback; kein Linux-Installationsziel'
}
$browserSolution = if ($platform.IsWindows) { 'Chromium-fähiger Browser über winget (Chrome)' } else { 'Chromium aus der Distribution' }
$fontSolution = if ($platform.IsWindows) { 'Arial als geprüfte Windows-Systemvoraussetzung; nicht automatisch ersetzen' } else { 'Liberation Sans aus der Distribution' }
$shellCheckSolution = if ($platform.IsWindows) { 'ShellCheck über winget' } else { 'ShellCheck aus der Distribution' }
$setupSuffix = if ($platform.IsWindows) { ' -DryRun -Format json' } else { ' --dry-run --format json' }
$dependencyDetails = @(
  [pscustomobject][ordered]@{
    name = 'powershell'; status = if ($powerShellOk) { 'present' } else { 'missing' }; version = $PSVersionTable.PSVersion.ToString(); path = $powerShellPath
    package = if ($platform.IsWindows) { 'Microsoft.PowerShell' } else { $null }; source = $runtimeSolution; solution = $runtimeSolution; installable = [bool]$platform.IsWindows
    setupCommand = if ($platform.IsWindows) { "$setupBase $runtimeSetupOption$setupSuffix" } else { $null }; permission = if ($platform.IsWindows) { 'winget-Berechtigung, ggf. Administrator' } else { 'Keine Installation: Linux verwendet Python als produktiven Kern.' }
  },
  [pscustomobject][ordered]@{
    name = 'chromium'; status = if ($null -ne $browserInfo -and $browserInfo.Engine -eq 'chromium') { 'present' } else { 'missing' }; version = if ($null -ne $browserInfo -and $browserInfo.Engine -eq 'chromium') { $browserInfo.Version } else { $null }; path = if ($null -ne $browserInfo -and $browserInfo.Engine -eq 'chromium') { $browserInfo.Path } else { $null }
    package = if ($platform.IsWindows) { 'Google.Chrome' } else { 'chromium' }; source = $browserSolution; solution = $browserSolution; installable = [bool]($platform.Supported -and -not ($platform.IsLinux -and $platform.DistributionId -eq 'ubuntu' -and (Get-Command apt-cache -ErrorAction SilentlyContinue) -and ((apt-cache show chromium chromium-browser 2>$null) -match '(?i)snap')))
    setupCommand = "$setupBase $browserSetupOption$setupSuffix"; permission = if ($platform.IsWindows) { 'winget-Berechtigung, ggf. Administrator' } else { 'Root/sudo für Distributionspaket' }
  },
  [pscustomobject][ordered]@{
    name = 'fonts'; status = if ($font.Available) { 'present' } else { 'missing' }; version = $font.Version; path = $font.Path
    package = if ($platform.IsWindows) { $null } else { 'fonts-liberation2 beziehungsweise distributionsspezifisches Liberation-Paket' }; source = $fontSolution; solution = $fontSolution; installable = [bool]($platform.IsLinux -and $platform.Supported)
    setupCommand = "$setupBase $fontSetupOption$setupSuffix"; permission = if ($platform.IsWindows) { 'Keine Installation; Windows-Systemvoraussetzung' } else { 'Root/sudo für Distributionspaket' }
  },
  [pscustomobject][ordered]@{
    name = 'shellcheck'; status = if ($shellCheck.Available) { 'present' } else { 'missing' }; version = $shellCheck.Version; path = $shellCheck.Path
    package = if ($platform.IsWindows) { 'koalaman.shellcheck' } else { 'shellcheck' }; source = $shellCheckSolution; solution = $shellCheckSolution; installable = [bool]$platform.Supported
    setupCommand = "$setupBase $shellCheckSetupOption$setupSuffix"; permission = if ($platform.IsWindows) { 'winget-Berechtigung, ggf. Administrator' } else { 'Root/sudo für Distributionspaket' }
  }
)

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
  schemaVersion = 3
  checkedAtUtc = [datetime]::UtcNow.ToString('o')
  status = $status
  exitCode = $exitCode
  checks = $checks.ToArray()
  platform = [pscustomobject][ordered]@{
    name = $platform.Name
    distributionId = $platform.DistributionId
    distributionVersion = $platform.DistributionVersion
    architecture = $platform.Architecture
    packageManager = $platform.PackageManager
  }
  coreRuntime = [pscustomobject][ordered]@{
    platform = if ($platform.IsWindows) { 'windows' } elseif ($platform.IsLinux) { 'linux' } else { [string]$platform.Name }
    name = 'powershell'
    language = 'powershell'
    status = if ($powerShellOk) { 'present' } else { 'missing' }
    version = $PSVersionTable.PSVersion.ToString()
    minimumVersion = '7.6'
    path = $powerShellPath
    source = $runtimeSolution
    installable = [bool]$platform.Supported
    setupCommand = if ($platform.IsWindows) { "$setupBase $runtimeSetupOption$setupSuffix" } else { 'python3 Tools/setup-linux.py --runtime --dry-run --format json' }
    permission = if ($platform.IsWindows) { 'winget-Berechtigung, ggf. Administrator' } else { 'Legacy-Fallback; Linux verwendet primär System-Python 3.9+' }
  }
  setup = [pscustomobject][ordered]@{
    linux = if ($platform.IsLinux) { 'python3 Tools/setup-linux.py --all --dry-run --format json' } else { $null }
    windows = if ($platform.IsWindows) { 'Tools/setup-windows.ps1 -All -DryRun -Format json' } else { $null }
  }
  dependencies = $dependencyDetails
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
