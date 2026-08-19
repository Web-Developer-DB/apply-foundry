#requires -Version 7.6
#requires -PSEdition Core

[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Arbeitsordner,
  [Parameter(Mandatory)][string]$FreigabeId,
  [Parameter(Mandatory)][switch]$Bestaetigt,
  [string]$Notiz = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common/ApprovalContract.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Common/JsonContract.psm1') -Force -Global
Import-Module (Join-Path $PSScriptRoot 'Common/AtomicFile.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Common/WorkflowCheckpoint.psm1') -Force

function Stop-Approval { param([string]$Message, [int]$Code = 1); Write-Host "[FEHLER] $Message" -ForegroundColor Red; exit $Code }
try {
  $work = [IO.Path]::GetFullPath($Arbeitsordner)
  if (-not (Test-Path -LiteralPath $work -PathType Container)) { throw "Arbeitsordner fehlt: $work" }
  $reportPath = Join-Path $work 'Finalisierungsbericht.json'
  if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) { $reportPath = Join-Path $work 'Universal-Finalisierungsbericht.json' }
  if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) { throw 'Kein vorbereiteter Finalisierungsbericht gefunden.' }
  if (-not $Bestaetigt) { throw 'Die Freigabe-ID darf erst nach ausdrücklicher Chat-Bestätigung mit --bestaetigt gespeichert werden.' }
  if ($FreigabeId -notmatch '^FR-[A-Z0-9]{12}$') { throw 'Freigabe-ID besitzt nicht das erwartete Format FR-XXXXXXXXXXXX.' }
  $report = Read-ContractJson -Path $reportPath
  if ([string](Get-ContractJsonProperty $report 'status') -cne 'bereit_zur_sichtpruefung') { throw 'Der Finalisierungsbericht ist nicht zur Sichtprüfung freigegeben.' }
  $request = Get-ContractJsonProperty $report 'approvalRequest'
  if ($null -eq $request -or [string](Get-ContractJsonProperty $request 'approvalId') -cne $FreigabeId) { throw 'Freigabe-ID stimmt nicht mit der vorbereiteten Anforderung überein.' }
  $records = @(Get-ContractApprovalRecords -Report $report)
  Test-ContractArtifactRecordsCurrent -Records $records -Root $work
  $setHash = Get-ContractArtifactSetHash -Records $records -Root $work
  if ($setHash -cne [string](Get-ContractJsonProperty $request 'artifactSetSha256')) { throw 'Artefaktsatz hat sich seit der Vorbereitung verändert.' }
  $reportHash = (Get-FileHash -LiteralPath $reportPath -Algorithm SHA256).Hash
  $relativeRecords = @($records | ForEach-Object {
    $record = [ordered]@{}
    foreach ($property in @('path','name','bytes','sha256')) { $record[$property] = Get-ContractJsonProperty $_ $property }
    $recordPath = [string]$record.path
    $absoluteRecordPath = if ([IO.Path]::IsPathRooted($recordPath)) { [IO.Path]::GetFullPath($recordPath) } else { [IO.Path]::GetFullPath((Join-Path $work $recordPath)) }
    $record.path = [IO.Path]::GetRelativePath($work, $absoluteRecordPath).Replace('\','/')
    $record
  })
  $approvalPath = Join-Path $work 'Sichtfreigabe.json'
  $approval = [ordered]@{
    schemaVersion = 1; kind = 'sichtfreigabe'; approvalId = $FreigabeId
    confirmedAtUtc = [datetime]::UtcNow.ToString('o'); humanConfirmation = $true
    preparedReport = [ordered]@{ path = [IO.Path]::GetRelativePath($work, $reportPath).Replace('\','/'); sha256 = $reportHash }
    artifactSetSha256 = $setHash; artifacts = $relativeRecords
    reviewKind = [string](Get-ContractJsonProperty $report 'personalReview')
    note = ([regex]::Replace(([string]$Notiz).Trim(), '\s+', ' '))
  }
  Write-AtomicJson -Path $approvalPath -Value $approval -Depth 10
  try {
    Write-WorkflowCheckpoint -Arbeitsordner $work -Schritt 'sichtpruefung_bestaetigt' | Out-Null
  } catch {
    Write-Host "[WARNUNG] Workflow-Checkpoint konnte nach der Sichtfreigabe nicht aktualisiert werden: $($_.Exception.Message)" -ForegroundColor Yellow
  }
  Write-Host "[OK] Sichtfreigabe gespeichert: $approvalPath" -ForegroundColor Green
  Write-Host "Freigabe-ID: $FreigabeId"
} catch { Stop-Approval $_.Exception.Message }
