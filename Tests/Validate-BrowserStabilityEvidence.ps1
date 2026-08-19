#requires -Version 7.6
#requires -PSEdition Core

[CmdletBinding()]
param(
  [string]$Path = (Join-Path $PSScriptRoot 'Stabilitaetsnachweise/browser-smoke.json'),
  [switch]$RequireStable
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Stabilitätsnachweis fehlt: $Path" }
$evidence = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
if ($evidence.schemaVersion -ne 1) { throw 'Stabilitätsnachweis verwendet nicht schemaVersion 1.' }
if ($evidence.requiredConsecutiveRuns -ne 3) { throw 'Der Ubuntu-Nachweis muss drei aufeinanderfolgende Läufe verlangen.' }
$runs = @($evidence.runs)
$duplicateRuns = @($runs | Group-Object { "$(($_.runId).ToString())/$(($_.attempt).ToString())" } | Where-Object Count -gt 1)
if ($duplicateRuns.Count -gt 0) { throw 'Stabilitätsnachweis enthält doppelte Run-ID/Attempt-Einträge.' }
$validRuns = @($runs | Where-Object {
  $_.runId -and $_.attempt -and $_.runNumber -and $_.commitSha -and $_.url -and $_.startedAtUtc -and $_.runner -and
  $_.powershellVersion -and $_.browserVersion -and $_.result -eq 'success' -and
  $_.criteria.screenshot -and $_.criteria.a4 -and $_.criteria.pageCount -and
  $_.criteria.atsTextLayer -and $_.criteria.hashBinding -and $_.criteria.timeoutCleanup -and $_.criteria.noResidualProcesses
})
if ($RequireStable -and $validRuns.Count -lt 3) { throw "Ubuntu ist erst nach drei vollständigen grünen Läufen stabil (gefunden: $($validRuns.Count))." }
if ($RequireStable) {
  $runNumbers = @($validRuns | ForEach-Object { [int]$_.runNumber } | Sort-Object)
  if ((($runNumbers | Select-Object -Unique).Count -ne $runNumbers.Count) -or (($runNumbers[-1] - $runNumbers[0]) -ne ($runNumbers.Count - 1))) { throw 'Die grünen Ubuntu-Läufe sind nicht drei aufeinanderfolgende Workflow-Läufe.' }
}
if ($evidence.status -eq 'stabil' -and ($validRuns.Count -lt 3 -or -not $evidence.promotion.ubuntuPullRequest -or -not $evidence.promotion.requiredRulesetCheck)) {
  throw 'Stabilitätsnachweis behauptet stabil ohne drei Kriterienläufe und Promotion-Gate.'
}
Write-Output "Browser-Stabilitätsnachweis gültig: $($validRuns.Count) vollständige Läufe; Status $($evidence.status)."
