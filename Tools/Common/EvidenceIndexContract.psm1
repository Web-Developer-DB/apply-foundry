#requires -Version 7.6
#requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'JsonContract.psm1') -Force

$script:EvidenceIndexCurrentSchemaVersion = 1
$script:EvidenceIndexSupportedSchemaVersions = @(1)
$script:EvidenceTypes = @(
  'BERUFLICH BELEGT',
  'ÜBERTRAGBAR',
  'WEITERBILDUNG',
  'PROJEKTPRAXIS',
  'PRIVATE PRAXIS / HOME-LAB',
  'GRUNDLAGEN / VERSTÄNDNIS',
  'EINARBEITUNGSZIEL',
  'NICHT BEHAUPTEN'
)
$script:EvidenceSources = @('profil', 'auftrag_angabe')

function Get-EvidenceIndexSchemaVersion {
  param(
    [object]$Index,
    [switch]$AllowMissing
  )

  if ($null -eq $Index -and $AllowMissing) { return 0 }
  $raw = Get-ContractJsonProperty -Object $Index -Name 'schemaVersion'
  if ($null -eq $raw -and $AllowMissing) { return 0 }
  if ($raw -isnot [int] -and $raw -isnot [long]) {
    throw 'Evidenzindex enthält keine ganzzahlige schemaVersion.'
  }
  $schema = [int]$raw
  if ($schema -notin $script:EvidenceIndexSupportedSchemaVersions) {
    throw "Evidenzindex verwendet keine unterstützte schemaVersion 1: $schema"
  }
  return $schema
}

function Test-EvidenceIndexSchemaVersion {
  param([object]$Index, [int]$Expected)
  try {
    return (Get-EvidenceIndexSchemaVersion -Index $Index) -eq $Expected
  } catch {
    return $false
  }
}

function Test-EvidenceSha256 {
  param([AllowNull()][object]$Value)
  return ([string]$Value -match '^[A-Fa-f0-9]{64}$')
}

function New-EvidenceIndexDraft {
  param(
    [string]$ProfilSha256,
    [string]$AuftragSha256
  )

  $draft = [ordered]@{
    schemaVersion = $script:EvidenceIndexCurrentSchemaVersion
    profilSha256 = if ([string]::IsNullOrWhiteSpace($ProfilSha256)) { 'aus Profildatei übernehmen' } else { $ProfilSha256 }
    belege = @()
  }
  if (-not [string]::IsNullOrWhiteSpace($AuftragSha256)) {
    $draft['auftragSha256'] = $AuftragSha256
  }
  return $draft
}

function Get-EvidenceIndexMigrationSteps {
  return @([ordered]@{ id = 'evidenzindex/0-zu-1'; from = 0; to = 1 })
}

function Test-EvidenceRecordShape {
  param([Parameter(Mandatory)][object]$Record)
  $id = [string](Get-ContractJsonProperty -Object $Record -Name 'id')
  $source = [string](Get-ContractJsonProperty -Object $Record -Name 'quelle')
  $evidenceType = [string](Get-ContractJsonProperty -Object $Record -Name 'belegart')
  if ([string]::IsNullOrWhiteSpace($id)) { return $false }
  if ($source -notin $script:EvidenceSources) { return $false }
  return $evidenceType -in $script:EvidenceTypes
}

Export-ModuleMember -Function @(
  'Get-EvidenceIndexSchemaVersion',
  'Test-EvidenceIndexSchemaVersion',
  'Test-EvidenceSha256',
  'New-EvidenceIndexDraft',
  'Get-EvidenceIndexMigrationSteps',
  'Test-EvidenceRecordShape'
)
