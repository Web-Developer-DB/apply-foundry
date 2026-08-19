#requires -Version 7.6
#requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-AtomicMutexName {
  param([Parameter(Mandatory)][string]$Path)
  $full = [IO.Path]::GetFullPath($Path)
  $bytes = [Text.Encoding]::UTF8.GetBytes($full.ToLowerInvariant())
  $hash = [Security.Cryptography.SHA256]::HashData($bytes)
  return 'bewerbungs-agent-atomic-' + ([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
}

function Invoke-WithAtomicFileLock {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][scriptblock]$ScriptBlock,
    [ValidateRange(1, 300)][int]$TimeoutSeconds = 30
  )

  $mutex = [Threading.Mutex]::new($false, (Get-AtomicMutexName -Path $Path))
  $held = $false
  try {
    $held = $mutex.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))
    if (-not $held) { throw "Dateisperre konnte nicht innerhalb von $TimeoutSeconds Sekunden erworben werden: $Path" }
    return & $ScriptBlock
  } finally {
    if ($held) { try { $mutex.ReleaseMutex() | Out-Null } catch {} }
    $mutex.Dispose()
  }
}

function Write-AtomicText {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
    [ValidateRange(1, 30)][int]$RetryCount = 8
  )

  $full = [IO.Path]::GetFullPath($Path)
  $parent = Split-Path -Path $full -Parent
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -LiteralPath $parent -ItemType Directory -Force | Out-Null
  }
  $temporary = Join-Path $parent ('.atomic-' + [guid]::NewGuid().ToString('N') + '.tmp')
  $encoding = [Text.UTF8Encoding]::new($false)
  try {
    [IO.File]::WriteAllText($temporary, $Content, $encoding)
    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
      try {
        [IO.File]::Move($temporary, $full, $true)
        return
      } catch {
        if ($attempt -eq $RetryCount) { throw }
        Start-Sleep -Milliseconds ([math]::Min(1000, 40 * $attempt))
      }
    }
  } finally {
    if (Test-Path -LiteralPath $temporary -PathType Leaf) {
      Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
  }
}

function Write-AtomicJson {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][object]$Value,
    [int]$Depth = 12
  )
  $json = $Value | ConvertTo-Json -Depth $Depth
  Invoke-WithAtomicFileLock -Path $Path -ScriptBlock { Write-AtomicText -Path $Path -Content $json }
}

function Invoke-AtomicFileUpdate {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][scriptblock]$Update,
    [int]$Depth = 12
  )
  Invoke-WithAtomicFileLock -Path $Path -ScriptBlock {
    $current = if (Test-Path -LiteralPath $Path -PathType Leaf) { [IO.File]::ReadAllText([IO.Path]::GetFullPath($Path), [Text.UTF8Encoding]::new($false)) } else { $null }
    $next = & $Update $current
    if ($next -is [string]) { Write-AtomicText -Path $Path -Content $next }
    else { Write-AtomicText -Path $Path -Content ($next | ConvertTo-Json -Depth $Depth) }
  }
}

Export-ModuleMember -Function @(
  'Invoke-WithAtomicFileLock',
  'Write-AtomicText',
  'Write-AtomicJson',
  'Invoke-AtomicFileUpdate'
)
