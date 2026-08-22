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
if ($env:OS -ne 'Windows_NT') { Write-Error 'setup-windows.ps1 kann nur unter Windows ausgeführt werden.'; exit 2 }
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
  $paths = @(
    (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
    (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe'),
    (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe')
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  foreach ($path in $paths) {
    if (Test-Path -LiteralPath $path -PathType Leaf) {
      $version = (& $path --version 2>$null | Select-Object -First 1)
      if ($version -match '(?i)(Chrome|Chromium|Edge)\s+[0-9]+') {
        $number = [regex]::Match([string]$version, '(?<!\d)\d+(?:\.\d+){1,3}(?!\d)')
        return [pscustomobject]@{ Path = $path; Version = if ($number.Success) { $number.Value } else { $null } }
      }
    }
  }
  return $null
}
function Test-Chromium { return $null -ne (Get-ChromiumInfo) }
function Test-Font { return Test-Path -LiteralPath (Join-Path $env:WINDIR 'Fonts\arial.ttf') -PathType Leaf }
function Get-ShellCheckInfo {
  $command = Get-Command 'shellcheck.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $command -or -not $command.Source) { return $null }
  $versionText = (& $command.Source --version 2>$null | Select-Object -First 1)
  $number = [regex]::Match([string]$versionText, '(?<!\d)\d+(?:\.\d+){1,3}(?!\d)')
  if (-not $number.Success) { return $null }
  return [pscustomobject]@{ Path = (Resolve-Path -LiteralPath $command.Source).Path; Version = $number.Value }
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
  $items = [ordered]@{
    powershell = [ordered]@{ status = if (Test-PowerShell) { 'present' } else { 'missing' }; version = if ($powerShellVersion) { $powerShellVersion.ToString() } else { $null }; path = $powerShellPath; wingetId = 'Microsoft.PowerShell'; source = 'winget'; permission = 'winget-Berechtigung, ggf. Administrator' }
    chromium = [ordered]@{ status = if ($chromiumInfo) { 'present' } else { 'missing' }; version = if ($chromiumInfo) { $chromiumInfo.Version } else { $null }; path = if ($chromiumInfo) { $chromiumInfo.Path } else { $null }; wingetId = 'Google.Chrome'; source = 'winget'; permission = 'winget-Berechtigung, ggf. Administrator' }
    fonts = [ordered]@{ status = if (Test-Font) { 'present' } else { 'missing' }; version = $null; path = Join-Path $env:WINDIR 'Fonts\arial.ttf'; wingetId = $null; source = 'Windows-Systemvoraussetzung'; permission = 'manuell durch Windows bereitstellen' }
    shellcheck = [ordered]@{ status = if ($shellCheckInfo) { 'present' } else { 'missing' }; version = if ($shellCheckInfo) { $shellCheckInfo.Version } else { $null }; path = if ($shellCheckInfo) { $shellCheckInfo.Path } else { $null }; wingetId = 'koalaman.shellcheck'; source = 'winget'; permission = 'winget-Berechtigung, ggf. Administrator' }
  }
  if ($Format -eq 'json') { [pscustomobject][ordered]@{ schemaVersion = 1; platform = 'windows-x64'; packageManager = 'winget'; dependencies = $items; dryRun = [bool]$DryRun } | ConvertTo-Json -Depth 6 }
  else {
    Write-Output 'Geplante Windows-Projektabhängigkeiten:'
    foreach ($item in $items.GetEnumerator()) { Write-Output ("  {0}: {1} | Paket={2} | Quelle={3} | Rechte={4}" -f $item.Key, $item.Value.status, $item.Value.wingetId, $item.Value.source, $item.Value.permission) }
  }
}
if (-not (Test-Command 'winget.exe')) {
  Write-Plan
  if (-not $DryRun) { Write-Error 'winget wurde nicht gefunden; installieren Sie den App Installer oder richten Sie die fehlenden Komponenten manuell ein.'; exit 2 }
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
  } else { Write-Error 'Keine interaktive Eingabe verfügbar. Nach Prüfung mit -Yes erneut starten.'; exit 2 }
}
foreach ($id in $pending) {
  if (-not (Test-WingetPackage $id)) {
    Write-Plan
    Write-Error "winget kennt das deklarierte Paket '$id' nicht. Bitte die Komponente manuell aus einer vertrauenswürdigen Quelle einrichten."
    exit 2
  }
  & winget.exe install --id $id --exact --accept-source-agreements --accept-package-agreements
  if ($LASTEXITCODE -ne 0) { Write-Plan; Write-Error "winget konnte $id nicht installieren."; exit 1 }
}
Write-Plan
