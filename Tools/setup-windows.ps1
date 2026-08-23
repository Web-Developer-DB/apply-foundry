[CmdletBinding()]
param(
  [switch]$Runtime,
  [ValidateSet('chromium')][string]$Browser,
  [switch]$Fonts,
  [switch]$ShellCheck,
  [switch]$All,
  [switch]$DryRun,
  [switch]$Yes,
  [ValidateSet('text','json')][string]$Format = 'text'
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { [Console]::Error.WriteLine('FEHLER: setup-windows.ps1 kann nur unter Windows ausgeführt werden.'); exit 2 }
if ($All) { $Runtime = $true; $Browser = 'chromium'; $Fonts = $true; $ShellCheck = $true }
if (-not ($Runtime -or $Browser -or $Fonts -or $ShellCheck)) { Get-Help $PSCommandPath -Detailed; exit 0 }

function Test-Command([string]$Name) { return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue) }
function Get-PowerShellExecutable {
  $candidates = @()
  $command = Get-Command 'pwsh.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($command -and $command.Source) { $candidates += $command.Source }
  if ($env:ProgramFiles) { $candidates += (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe') }
  if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA 'Microsoft\PowerShell\7\pwsh.exe') }
  foreach ($candidate in ($candidates | Select-Object -Unique)) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return (Resolve-Path -LiteralPath $candidate).Path }
  }
  return $null
}
function Get-PowerShellVersion {
  $path = Get-PowerShellExecutable
  if (-not $path) { return $null }
  $raw = (& $path -NoLogo -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()' 2>$null | Select-Object -First 1)
  $parsed = $null
  if ([version]::TryParse([string]$raw, [ref]$parsed)) { return $parsed }
  return $null
}
function Test-PowerShell {
  $v = Get-PowerShellVersion
  return $null -ne $v -and ($v.Major -gt 7 -or ($v.Major -eq 7 -and $v.Minor -ge 6))
}
function Get-ChromiumInfo {
  $paths = @()
  if ($env:ProgramFiles) {
    $paths += [pscustomobject]@{ Name = 'Google Chrome'; Path = (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe') }
    $paths += [pscustomobject]@{ Name = 'Microsoft Edge'; Path = (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe') }
  }
  if (${env:ProgramFiles(x86)}) {
    $paths += [pscustomobject]@{ Name = 'Google Chrome'; Path = (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe') }
    $paths += [pscustomobject]@{ Name = 'Microsoft Edge'; Path = (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe') }
  }
  if ($env:LOCALAPPDATA) {
    $paths += [pscustomobject]@{ Name = 'Google Chrome'; Path = (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe') }
    $paths += [pscustomobject]@{ Name = 'Microsoft Edge'; Path = (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\Application\msedge.exe') }
  }
  foreach ($candidate in $paths) {
    $path = $candidate.Path
    if (Test-Path -LiteralPath $path -PathType Leaf) {
      $resolved = (Resolve-Path -LiteralPath $path).Path
      $fileVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($resolved).FileVersion
      $number = [regex]::Match([string]$fileVersion, '(?<!\d)\d+(?:\.\d+){1,3}(?!\d)')
      if ($number.Success) { return [pscustomobject]@{ Name = $candidate.Name; Path = $resolved; Version = $number.Value } }
    }
  }
  return $null
}
function Test-Chromium { return $null -ne (Get-ChromiumInfo) }
function Test-Font { return Test-Path -LiteralPath (Join-Path $env:WINDIR 'Fonts\arial.ttf') -PathType Leaf }
function Get-ShellCheckInfo {
  $command = Get-Command 'shellcheck.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $command -or -not $command.Source) { return $null }
  $versionText = [string]((& $command.Source --version 2>$null) -join "`n")
  $number = [regex]::Match($versionText, '(?im)^version:\s*(\d+(?:\.\d+){1,2})\s*$')
  if (-not $number.Success) { return $null }
  return [pscustomobject]@{ Path = (Resolve-Path -LiteralPath $command.Source).Path; Version = $number.Groups[1].Value }
}
function Test-ShellCheck { return $null -ne (Get-ShellCheckInfo) }
function Test-WingetPackage([string]$Id) {
  & winget.exe show --id $Id --exact --accept-source-agreements *> $null
  return $LASTEXITCODE -eq 0
}
function Write-Plan {
  $powerShellPath = Get-PowerShellExecutable
  $powerShellVersion = Get-PowerShellVersion
  $chromiumInfo = Get-ChromiumInfo
  $shellCheckInfo = Get-ShellCheckInfo
  $wingetCommand = Get-Command 'winget.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  $wingetAvailable = $null -ne $wingetCommand -and -not [string]::IsNullOrWhiteSpace($wingetCommand.Source)
  $fontPath = Join-Path $env:WINDIR 'Fonts\arial.ttf'
  $runtimePresent = Test-PowerShell
  $browserPresent = $null -ne $chromiumInfo
  $fontPresent = Test-Font
  $shellCheckPresent = $null -ne $shellCheckInfo
  $coreRuntime = [ordered]@{
    selected = [bool]$Runtime; status = if ($runtimePresent) { 'present' } else { 'missing' }
    version = if ($powerShellVersion) { $powerShellVersion.ToString() } else { $null }; path = $powerShellPath
    packages = @('Microsoft.PowerShell'); source = 'winget'; permission = 'winget-Berechtigung, ggf. Administrator'
    installable = [bool]$wingetAvailable; blocked = [bool]($Runtime -and -not $runtimePresent -and -not $wingetAvailable)
    plannedAction = if (-not $Runtime -or $runtimePresent) { 'none' } elseif ($wingetAvailable) { 'install' } else { 'manual' }
    language = 'powershell'; minimumVersion = '7.6'; platform = 'windows'
    setupCommand = 'powershell -NoProfile -ExecutionPolicy Bypass -File Tools/setup-windows.ps1 -Runtime -DryRun -Format json'
  }
  $dependencies = [ordered]@{
    browser = [ordered]@{
      selected = [bool]($Browser -eq 'chromium'); status = if ($browserPresent) { 'present' } else { 'missing' }
      version = if ($chromiumInfo) { $chromiumInfo.Version } else { $null }; path = if ($chromiumInfo) { $chromiumInfo.Path } else { $null }
      packages = @('Google.Chrome'); source = 'winget'; permission = 'winget-Berechtigung, ggf. Administrator'
      installable = [bool]$wingetAvailable; blocked = [bool]($Browser -eq 'chromium' -and -not $browserPresent -and -not $wingetAvailable)
      plannedAction = if ($Browser -ne 'chromium' -or $browserPresent) { 'none' } elseif ($wingetAvailable) { 'install' } else { 'manual' }
      detectedAs = if ($chromiumInfo) { $chromiumInfo.Name } else { $null }
    }
    fonts = [ordered]@{
      selected = [bool]$Fonts; status = if ($fontPresent) { 'present' } else { 'missing' }; version = $null; path = $fontPath
      packages = @(); source = 'Windows-Systemvoraussetzung'; permission = 'manuell durch Windows bereitstellen'
      installable = $false; blocked = [bool]($Fonts -and -not $fontPresent)
      plannedAction = if (-not $Fonts -or $fontPresent) { 'none' } else { 'manual' }
    }
    shellcheck = [ordered]@{
      selected = [bool]$ShellCheck; status = if ($shellCheckPresent) { 'present' } else { 'missing' }
      version = if ($shellCheckInfo) { $shellCheckInfo.Version } else { $null }; path = if ($shellCheckInfo) { $shellCheckInfo.Path } else { $null }
      packages = @('koalaman.shellcheck'); source = 'winget'; permission = 'winget-Berechtigung, ggf. Administrator'
      installable = [bool]$wingetAvailable; blocked = [bool]($ShellCheck -and -not $shellCheckPresent -and -not $wingetAvailable)
      plannedAction = if (-not $ShellCheck -or $shellCheckPresent) { 'none' } elseif ($wingetAvailable) { 'install' } else { 'manual' }
    }
  }
  $plannedChanges = @()
  $manualActions = @()
  foreach ($entry in @(
    [pscustomobject]@{ Name = 'coreRuntime'; Value = $coreRuntime },
    [pscustomobject]@{ Name = 'browser'; Value = $dependencies.browser },
    [pscustomobject]@{ Name = 'fonts'; Value = $dependencies.fonts },
    [pscustomobject]@{ Name = 'shellcheck'; Value = $dependencies.shellcheck }
  )) {
    if ($entry.Value.plannedAction -eq 'install') {
      $plannedChanges += [pscustomobject][ordered]@{ component = $entry.Name; action = 'install'; packages = @($entry.Value.packages); source = $entry.Value.source; permission = $entry.Value.permission }
    } elseif ($entry.Value.plannedAction -eq 'manual') {
      $manualActions += [pscustomobject][ordered]@{
        component = $entry.Name
        reason = if ($entry.Name -eq 'fonts') { 'Arial ist eine geprüfte Windows-Systemvoraussetzung und wird nicht automatisch ersetzt.' } else { 'winget fehlt; Windows App Installer muss bereitgestellt werden.' }
        requirement = if ($entry.Name -eq 'fonts') { 'Eine unterstützte Windows-x64-Installation mit Arial unter %WINDIR%\Fonts\arial.ttf bereitstellen.' } else { 'Microsoft App Installer mit winget.exe bereitstellen und danach nur die deklarierten Paket-IDs installieren.' }
        verificationCommand = if ($entry.Name -eq 'fonts') { 'powershell -NoProfile -Command "Test-Path $env:WINDIR\Fonts\arial.ttf"' } else { 'powershell -NoProfile -ExecutionPolicy Bypass -File Tools/setup-windows.ps1 -All -DryRun -Format json' }
      }
    }
  }
  if (-not [Environment]::Is64BitOperatingSystem) {
    $manualActions += [pscustomobject][ordered]@{ component = 'platform'; reason = 'Unterstützt wird ausschließlich Windows x64.' }
  }
  $applyParts = @('powershell -NoProfile -ExecutionPolicy Bypass -File Tools/setup-windows.ps1')
  if ($Runtime) { $applyParts += '-Runtime' }
  if ($Browser -eq 'chromium') { $applyParts += '-Browser chromium' }
  if ($Fonts) { $applyParts += '-Fonts' }
  if ($ShellCheck) { $applyParts += '-ShellCheck' }
  $applyParts += @('-Yes', '-Format json')
  $status = if (-not [Environment]::Is64BitOperatingSystem) { 'unsupported' } elseif ($manualActions.Count -gt 0) { 'blocked' } elseif ($plannedChanges.Count -gt 0) { 'planned' } else { 'ready' }
  $report = [pscustomobject][ordered]@{
    schemaVersion = 2; kind = 'windows_setup_plan'; status = $status
    platform = [pscustomobject][ordered]@{ id = 'windows'; version = [Environment]::OSVersion.Version.ToString(); architecture = if ([Environment]::Is64BitOperatingSystem) { 'x86_64' } else { 'unsupported' } }
    packageManager = 'winget'; packageManagerPath = if ($wingetAvailable) { $wingetCommand.Source } else { $null }
    coreRuntime = $coreRuntime; dependencies = $dependencies; plannedChanges = @($plannedChanges); manualActions = @($manualActions)
    changesRequired = [bool]($plannedChanges.Count -gt 0); manualActionRequired = [bool]($manualActions.Count -gt 0)
    requiresPrivilege = [bool]($plannedChanges.Count -gt 0); applyCommand = ($applyParts -join ' '); dryRun = [bool]$DryRun
  }
  if ($Format -eq 'json') { $report | ConvertTo-Json -Depth 8 }
  else {
    Write-Output 'Geplante Windows-Projektabhängigkeiten:'
    Write-Output ("  coreRuntime: {0} | Paket={1} | Quelle={2} | Rechte={3} | Aktion={4}" -f $coreRuntime.status, ($coreRuntime.packages -join ', '), $coreRuntime.source, $coreRuntime.permission, $coreRuntime.plannedAction)
    foreach ($item in $dependencies.GetEnumerator()) { Write-Output ("  {0}: {1} | Paket={2} | Quelle={3} | Rechte={4} | Aktion={5}" -f $item.Key, $item.Value.status, ($item.Value.packages -join ', '), $item.Value.source, $item.Value.permission, $item.Value.plannedAction) }
    foreach ($manual in $manualActions) { Write-Warning ("{0}: {1}" -f $manual.component, $manual.reason) }
  }
}
if (-not [Environment]::Is64BitOperatingSystem) {
  Write-Plan
  if (-not $DryRun) { [Console]::Error.WriteLine('FEHLER: setup-windows.ps1 unterstützt ausschließlich Windows x64.') }
  exit 2
}
if (-not (Test-Command 'winget.exe')) {
  Write-Plan
  if (-not $DryRun) { [Console]::Error.WriteLine('FEHLER: winget wurde nicht gefunden; stellen Sie Microsoft App Installer bereit und prüfen Sie den ausgegebenen Plan erneut.'); exit 2 }
  exit 0
}
if ($DryRun) { Write-Plan; exit 0 }
$pending = @()
if ($Runtime -and -not (Test-PowerShell)) { $pending += 'Microsoft.PowerShell' }
if ($Browser -eq 'chromium' -and -not (Test-Chromium)) { $pending += 'Google.Chrome' }
if ($ShellCheck -and -not (Test-ShellCheck)) { $pending += 'koalaman.shellcheck' }
$fontMissing = $Fonts -and -not (Test-Font)
if ($fontMissing) { Write-Warning 'Arial fehlt; Windows-Systemschriftarten werden nicht per Bootstrap überschrieben. Bitte eine unterstützte Windows-Installation mit Arial bereitstellen.' }
if ($pending.Count -eq 0) { Write-Plan; if ($fontMissing) { exit 2 }; exit 0 }
if (-not $Yes) {
  Write-Plan
  if ([Environment]::UserInteractive) {
    $answer = Read-Host 'Diese Änderungen jetzt ausführen? [j/N]'
    if ($answer -notmatch '^(j|ja|y|yes)$') { Write-Output 'Setup wurde ohne Änderungen abgebrochen.'; exit 1 }
  } else { [Console]::Error.WriteLine('FEHLER: Keine interaktive Eingabe verfügbar. Nach Prüfung mit -Yes erneut starten.'); exit 2 }
}
foreach ($id in $pending) {
  if (-not (Test-WingetPackage $id)) {
    Write-Plan
    [Console]::Error.WriteLine("FEHLER: winget kennt das deklarierte Paket '$id' nicht. Bitte die Komponente manuell aus einer vertrauenswürdigen Quelle einrichten.")
    exit 2
  }
  & winget.exe install --id $id --exact --accept-source-agreements --accept-package-agreements
  if ($LASTEXITCODE -ne 0) { Write-Plan; [Console]::Error.WriteLine("FEHLER: winget konnte $id nicht installieren."); exit 1 }
}
Write-Plan
$validationErrors = @()
if ($Runtime -and -not (Test-PowerShell)) { $validationErrors += 'PowerShell 7.6 wurde nach der Installation nicht mit gültiger Version und ausführbarem Pfad gefunden.' }
if ($Browser -eq 'chromium' -and -not (Test-Chromium)) { $validationErrors += 'Nach der Installation wurde kein versionsgeprüfter Chromium-Browserpfad gefunden.' }
if ($ShellCheck -and -not (Test-ShellCheck)) { $validationErrors += 'ShellCheck wurde nach der Installation nicht mit gültiger Version und ausführbarem Pfad gefunden.' }
if ($Fonts -and -not (Test-Font)) { $validationErrors += 'Arial fehlt weiterhin als Windows-Systemvoraussetzung.' }
if ($validationErrors.Count -gt 0) {
  foreach ($validationError in $validationErrors) { [Console]::Error.WriteLine("FEHLER: $validationError") }
  exit 1
}
exit 0
