#requires -Version 7.6
#requires -PSEdition Core

[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Repository,
  [Parameter(Mandatory)][string]$OutputPath,
  [string]$Token,
  [string]$Workflow = 'browser-smoke.yml'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$headers = @{ 'Accept' = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }
if (-not [string]::IsNullOrWhiteSpace($Token)) { $headers.Authorization = "Bearer $Token" }
$base = "https://api.github.com/repos/$Repository/actions"
$runsResponse = Invoke-RestMethod -Uri "$base/workflows/$Workflow/runs?status=completed&per_page=20" -Headers $headers -Method Get
$runs = New-Object System.Collections.Generic.List[object]
foreach ($run in @($runsResponse.workflow_runs | Sort-Object run_number -Descending)) {
  $jobsResponse = Invoke-RestMethod -Uri "$base/runs/$($run.id)/jobs?per_page=100" -Headers $headers -Method Get
  $job = @($jobsResponse.jobs | Where-Object { $_.name -eq 'Ubuntu browser smoke (staged)' } | Select-Object -First 1)
  if ($null -eq $job) { continue }
  $success = [string]$job.conclusion -eq 'success'
  $runs.Add([ordered]@{
    runId = [string]$run.id
    attempt = [int]$run.run_attempt
    runNumber = [int]$run.run_number
    commitSha = [string]$run.head_sha
    url = [string]$run.html_url
    startedAtUtc = [string]$run.run_started_at
    runner = 'ubuntu-24.04'
    powershellVersion = 'not_read_from_api'
    browserVersion = 'not_read_from_api'
    result = if ($success) { 'success' } else { 'failure' }
    criteria = [ordered]@{ screenshot = $false; a4 = $false; pageCount = $false; atsTextLayer = $false; hashBinding = $false; timeoutCleanup = $false; noResidualProcesses = $false }
  }) | Out-Null
  if ($runs.Count -ge 3) { break }
}
$draft = [ordered]@{
  schemaVersion = 1
  status = 'entwurf'
  requiredConsecutiveRuns = 3
  promotion = [ordered]@{ ubuntuPullRequest = $false; requiredRulesetCheck = $false; promotionPullRequest = $null }
  source = [ordered]@{ repository = $Repository; workflow = $Workflow; generatedAtUtc = [DateTime]::UtcNow.ToString('o'); readOnly = $true }
  runs = @($runs.ToArray())
}
$fullOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
New-Item -Path (Split-Path -Path $fullOutputPath -Parent) -ItemType Directory -Force | Out-Null
Set-Content -LiteralPath $fullOutputPath -Encoding UTF8 -Value ($draft | ConvertTo-Json -Depth 10)
Write-Output "Browser-Stabilitätsentwurf geschrieben: $fullOutputPath"
