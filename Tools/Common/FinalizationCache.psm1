#requires -Version 7.6
#requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'AtomicFile.psm1') -Force

$script:CacheSchemaVersion = 1
$script:StageOrder = @('dialog', 'stammdaten', 'statisch', 'inhalt', 'layout', 'pdf', 'ats')

function Get-CacheRelativePath {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Root)
  $full = [IO.Path]::GetFullPath($Path)
  $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
  if (-not $full.StartsWith($rootFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    return '<extern>/' + [IO.Path]::GetFileName($full)
  }
  return $full.Substring($rootFull.Length).TrimStart([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) -replace '\\', '/'
}

function Get-CacheFileRecord {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Root)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  $item = Get-Item -LiteralPath $Path -Force
  return [ordered]@{
    path = Get-CacheRelativePath -Path $item.FullName -Root $Root
    bytes = [int64]$item.Length
    sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
  }
}

function Get-CacheValueSha256 {
  param([Parameter(Mandatory)][object]$Value)
  $json = $Value | ConvertTo-Json -Depth 24 -Compress
  $bytes = [Text.Encoding]::UTF8.GetBytes($json)
  return ([BitConverter]::ToString([Security.Cryptography.SHA256]::HashData($bytes)) -replace '-', '')
}

function Get-FinalizationStageFingerprint {
  param(
    [Parameter(Mandatory)][ValidateSet('dialog', 'stammdaten', 'statisch', 'inhalt', 'layout', 'pdf', 'ats')][string]$Stage,
    [Parameter(Mandatory)][string]$Root,
    [string[]]$ImplementationFiles = @(),
    [string[]]$InputFiles = @(),
    [hashtable]$Parameters = @{},
    [object]$Runtime = $null,
    [string[]]$DependencyKeys = @()
  )
  $implementation = @($ImplementationFiles | Sort-Object -Unique | ForEach-Object { Get-CacheFileRecord -Path $_ -Root $Root } | Where-Object { $null -ne $_ })
  $inputs = @($InputFiles | Sort-Object -Unique | ForEach-Object { Get-CacheFileRecord -Path $_ -Root $Root } | Where-Object { $null -ne $_ })
  $normalizedParameters = [ordered]@{}
  foreach ($key in @($Parameters.Keys | Sort-Object)) { $normalizedParameters[$key] = [string]$Parameters[$key] }
  $fingerprint = [ordered]@{
    contractVersion = 1
    stage = $Stage
    implementation = $implementation
    inputs = $inputs
    parameters = $normalizedParameters
    runtime = $Runtime
    dependencies = @($DependencyKeys)
  }
  return [ordered]@{ fingerprint = $fingerprint; cacheKey = Get-CacheValueSha256 -Value $fingerprint }
}

function Read-FinalizationCheckState {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  try {
    $state = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$state.schemaVersion -ne $script:CacheSchemaVersion -or [string]$state.kind -ne 'finalisierungs_pruefstand' -or $null -eq $state.stages) { return $null }
    return $state
  } catch { return $null }
}

function Get-FinalizationCacheDecision {
  param(
    [object]$State,
    [Parameter(Mandatory)][string]$Stage,
    [Parameter(Mandatory)][object]$Fingerprint,
    [Parameter(Mandatory)][string]$Root,
    [switch]$Force
  )
  if ($Force) { return [ordered]@{ reusable = $false; reason = 'forced'; entry = $null } }
  if ($null -eq $State) { return [ordered]@{ reusable = $false; reason = 'missing'; entry = $null } }
  $entry = @($State.stages | Where-Object { [string]$_.id -eq $Stage } | Select-Object -First 1)
  if ($entry.Count -eq 0) { return [ordered]@{ reusable = $false; reason = 'missing'; entry = $null } }
  $entry = $entry[0]
  if ([string]$entry.status -ne 'passed') { return [ordered]@{ reusable = $false; reason = 'input_changed'; entry = $entry } }
  if ([string]$entry.cacheKey -ne [string]$Fingerprint.cacheKey) {
    $old = $entry.fingerprint
    $new = $Fingerprint.fingerprint
    $serialize = { param($value) $value | ConvertTo-Json -Depth 24 -Compress }
    $reason = if ((& $serialize $old.implementation) -cne (& $serialize $new.implementation)) { 'implementation_changed' }
      elseif ((& $serialize $old.runtime) -cne (& $serialize $new.runtime)) { 'runtime_changed' }
      elseif ((& $serialize $old.dependencies) -cne (& $serialize $new.dependencies)) { 'dependency_changed' }
      else { 'input_changed' }
    return [ordered]@{ reusable = $false; reason = $reason; entry = $entry }
  }
  foreach ($output in @($entry.outputs)) {
    $relative = [string]$output.path
    if ([string]::IsNullOrWhiteSpace($relative) -or $relative.StartsWith('<extern>/')) { return [ordered]@{ reusable = $false; reason = 'output_missing'; entry = $entry } }
    $path = Join-Path $Root ($relative -replace '/', [IO.Path]::DirectorySeparatorChar)
    $actual = Get-CacheFileRecord -Path $path -Root $Root
    if ($null -eq $actual) { return [ordered]@{ reusable = $false; reason = 'output_missing'; entry = $entry } }
    if ([string]$actual.sha256 -ne [string]$output.sha256 -or [int64]$actual.bytes -ne [int64]$output.bytes) { return [ordered]@{ reusable = $false; reason = 'output_changed'; entry = $entry } }
  }
  return [ordered]@{ reusable = $true; reason = 'hit'; entry = $entry }
}

function Save-FinalizationStageResult {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$Stage,
    [Parameter(Mandatory)][object]$Fingerprint,
    [string[]]$OutputFiles = @(),
    [Parameter(Mandatory)][int]$DurationMs,
    [ValidateSet('passed', 'failed')][string]$Status = 'passed'
  )
  $stageIndex = [array]::IndexOf($script:StageOrder, $Stage)
  Invoke-AtomicFileUpdate -Path $Path -Depth 20 -Update {
    param($CurrentJson)
    $current = if ([string]::IsNullOrWhiteSpace($CurrentJson)) { $null } else { $CurrentJson | ConvertFrom-Json }
    $kept = @()
    if ($null -ne $current -and [int]$current.schemaVersion -eq $script:CacheSchemaVersion -and $null -ne $current.stages) {
      $kept = @($current.stages | Where-Object {
        $index = [array]::IndexOf($script:StageOrder, [string]$_.id)
        $index -ge 0 -and $index -lt $stageIndex
      })
    }
    $entry = [ordered]@{
      id = $Stage
      status = $Status
      cacheKey = [string]$Fingerprint.cacheKey
      fingerprint = $Fingerprint.fingerprint
      outputs = @($OutputFiles | Sort-Object -Unique | ForEach-Object { Get-CacheFileRecord -Path $_ -Root $Root } | Where-Object { $null -ne $_ })
      durationMs = $DurationMs
      completedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    return [ordered]@{ schemaVersion = $script:CacheSchemaVersion; kind = 'finalisierungs_pruefstand'; stages = @($kept + $entry) }
  }
}

function Get-FinalizationStageOrder { return @($script:StageOrder) }

Export-ModuleMember -Function @(
  'Get-CacheFileRecord', 'Get-FinalizationStageFingerprint', 'Read-FinalizationCheckState',
  'Get-FinalizationCacheDecision', 'Save-FinalizationStageResult', 'Get-FinalizationStageOrder'
)
