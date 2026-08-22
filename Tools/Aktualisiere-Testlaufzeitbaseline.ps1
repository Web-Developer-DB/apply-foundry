#requires -Version 7.6
#requires -PSEdition Core

[CmdletBinding()]
param(
  [Parameter(Mandatory)][string[]]$BerichtPath,
  [string]$BaselinePath = (Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..') -ChildPath 'Tests/Testlaufzeit-Baselines.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common/AtomicFile.psm1') -Force

$inputPaths = @($BerichtPath | ForEach-Object { $_ -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } })
if ($inputPaths.Count -ne 3) { throw 'Genau drei durch Komma getrennte Testberichtspfade sind erforderlich.' }
$reports = @($inputPaths | ForEach-Object {
  if (-not (Test-Path -LiteralPath $_ -PathType Leaf)) { throw "Testbericht fehlt: $_" }
  Get-Content -LiteralPath $_ -Raw -Encoding UTF8 | ConvertFrom-Json
})
foreach ($report in $reports) {
  if ([int]$report.schemaVersion -ne 1 -or [string]$report.status -ne 'bestanden' -or -not [string]::IsNullOrWhiteSpace([string]$report.testNamePattern) -or $null -eq $report.timing) {
    throw 'Nur erfolgreiche, ungefilterte Schema-1-Berichte mit Laufzeitdaten dürfen eine Baseline bilden.'
  }
}
$suite = [string]$reports[0].suite
$runtime = $reports[0].runtime
$runtimeKey = ([string]$runtime.os + '|' + [string]$runtime.architecture + '|' + [string]$runtime.powershell)
foreach ($report in $reports) {
  $key = ([string]$report.runtime.os + '|' + [string]$report.runtime.architecture + '|' + [string]$report.runtime.powershell)
  if ([string]$report.suite -ne $suite -or $key -ne $runtimeKey) { throw 'Die drei Berichte müssen dieselbe Suite und Laufzeitfamilie besitzen.' }
}
$median = {
  param([array]$Values)
  $sorted = @($Values | Sort-Object)
  return [int]$sorted[[math]::Floor(($sorted.Count - 1) / 2)]
}
$entry = [ordered]@{
  suite = $suite
  runtime = [ordered]@{ os = [string]$runtime.os; architecture = [string]$runtime.architecture; powershell = [string]$runtime.powershell }
  sampleCount = 3
  recordedAtUtc = [DateTime]::UtcNow.ToString('o')
  durationMsMedian = & $median @($reports | ForEach-Object { [int]$_.durationMs })
  testDurationMsMedian = & $median @($reports | ForEach-Object { [int]$_.timing.testDurationMs })
  p95TestDurationMsMedian = & $median @($reports | ForEach-Object { [int]$_.timing.p95TestDurationMs })
}
$current = if (Test-Path -LiteralPath $BaselinePath -PathType Leaf) { Get-Content -LiteralPath $BaselinePath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$entries = @()
if ($null -ne $current -and [int]$current.schemaVersion -eq 1 -and $null -ne $current.baselines) {
  $entries = @($current.baselines | Where-Object { -not ([string]$_.suite -eq $suite -and [string]$_.runtime.os -eq [string]$runtime.os -and [string]$_.runtime.architecture -eq [string]$runtime.architecture -and [string]$_.runtime.powershell -eq [string]$runtime.powershell) })
}
$result = [ordered]@{ schemaVersion = 1; kind = 'testlaufzeit_baselines'; warningThresholdPercent = 25; warningMinimumMs = 1000; baselines = @($entries + $entry) }
Write-AtomicJson -Path $BaselinePath -Value $result -Depth 12
Write-Host "Laufzeitbaseline aktualisiert: $BaselinePath"
