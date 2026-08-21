#requires -Version 7.6
#requires -PSEdition Core

[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Arbeitsordner,
  [string]$ProfilPath = (Join-Path -Path (Join-Path -Path (Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..') -ChildPath 'Private') -ChildPath 'Daten') -ChildPath '02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md'),
  [string]$BerichtPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common/AtomicFile.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Common/MatrixContract.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Common/EvidenceIndexContract.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Common/ContextContract.psm1') -Force

function Get-Record {
  param([string]$Path, [string]$Root)
  $item = Get-Item -LiteralPath $Path -Force
  [ordered]@{ path = [IO.Path]::GetRelativePath($Root, $item.FullName) -replace '\\', '/'; bytes = [int64]$item.Length; sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash }
}
function Values { param($Value) return @($Value | Where-Object { $null -ne $_ }) }

$work = [IO.Path]::GetFullPath($Arbeitsordner)
if (-not (Test-Path -LiteralPath $work -PathType Container)) { throw "Arbeitsordner fehlt: $work" }
$matrixPath = Join-Path $work 'Anforderungsmatrix.json'
$indexPath = Join-Path $work 'Evidenzindex.json'
$orderPath = Join-Path $work 'Bewerbungsauftrag.json'
$jobPath = Join-Path $work 'Kandidat/Stellenbeschreibung.md'
foreach ($path in @($matrixPath, $indexPath, $orderPath, $jobPath, $ProfilPath)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Kontextquelle fehlt: $path" } }
$matrix = Get-Content -LiteralPath $matrixPath -Raw -Encoding UTF8 | ConvertFrom-Json
$index = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json
$order = Get-Content -LiteralPath $orderPath -Raw -Encoding UTF8 | ConvertFrom-Json
$matrixSchema = Get-MatrixSchemaVersion -Matrix $matrix
$indexSchema = Get-EvidenceIndexSchemaVersion -Index $index
$reasons = [System.Collections.Generic.List[string]]::new()
if ($matrixSchema -ne 5) { $reasons.Add('legacy_matrix') | Out-Null }
if ($indexSchema -ne 1) { $reasons.Add('unsupported_evidence_index') | Out-Null }
if ((Get-ContextLoadingMode) -ne 'evidenzbasiert') { $reasons.Add('rollout_deaktiviert') | Out-Null }

$requirements = Values $matrix.requirements
$highlights = Values $matrix.recruiterStrategie.profilHighlights
$letterArguments = Values $matrix.anschreibenStrategie.argumente
$omissions = Values $matrix.recruiterStrategie.auslassungen
$requirementIds = @($requirements | ForEach-Object { [string]$_.id } | Where-Object { $_ })
$evidenceIds = @($requirements.belegRefIds + $highlights.belegRefIds + $letterArguments.belegRefIds + $omissions.belegRefIds | ForEach-Object { [string]$_ } | Where-Object { $_ } | Sort-Object -Unique)
$jobIds = @($requirements.stellenFundstellen + $letterArguments.stellenFundstellen | ForEach-Object { [string]$_ } | Where-Object { $_ } | Sort-Object -Unique)
$sourceIds = @($letterArguments.externeQuellenIds | ForEach-Object { [string]$_ } | Where-Object { $_ } | Sort-Object -Unique)
$evidenceById = @{}; foreach ($item in (Values $index.belege)) { $evidenceById[[string]$item.id] = $item }
$anchorsById = @{}; foreach ($item in (Values $matrix.stellenanzeigeAbdeckung.fundstellen)) { $anchorsById[[string]$item.id] = $item }
foreach ($id in $evidenceIds) { if (-not $evidenceById.ContainsKey($id)) { $reasons.Add("unbekannte_evidenz:$id") | Out-Null } }
foreach ($id in $jobIds) { if (-not $anchorsById.ContainsKey($id)) { $reasons.Add("unbekannte_fundstelle:$id") | Out-Null } }
$profileRanges = Merge-ContextRanges -Ranges @(foreach ($id in $evidenceIds) { if ($evidenceById.ContainsKey($id) -and [string]$evidenceById[$id].quelle -eq 'profil') { $evidenceById[$id] } })
$jobRanges = Merge-ContextRanges -Ranges @(foreach ($id in $jobIds) { if ($anchorsById.ContainsKey($id)) { $anchorsById[$id] } })
$scope = $order.dokumentumfang
$contexts = [System.Collections.Generic.List[object]]::new()
foreach ($purpose in @('lebenslauf', 'anschreiben', 'email_nachricht', 'qualitaetspruefung')) {
  $selected = $purpose -eq 'qualitaetspruefung' -or (($purpose -eq 'lebenslauf') -and [string]$scope.lebenslauf -ne 'nicht_enthalten') -or (($purpose -eq 'anschreiben') -and [bool]$scope.anschreiben) -or (($purpose -eq 'email_nachricht') -and [bool]$scope.emailNachricht)
  if ($selected) { $contexts.Add([ordered]@{ zweck = $purpose; anforderungIds = $requirementIds; belegIds = $evidenceIds; stellenFundstellenIds = $jobIds; externeQuellenIds = $sourceIds; profilBereiche = $profileRanges; stellenBereiche = $jobRanges; dialogAngabeIds = @($evidenceIds | Where-Object { $evidenceById.ContainsKey($_) -and [string]$evidenceById[$_].quelle -eq 'auftrag_angabe' }) }) | Out-Null }
}
$manifest = [ordered]@{
  schemaVersion = 1; kind = 'kontextmanifest'; mode = Get-ContextLoadingMode; status = if ($reasons.Count -eq 0) { 'evidenzbasiert_bereit' } else { 'vollkontext_erforderlich' }
  generatedAtUtc = [DateTime]::UtcNow.ToString('o')
  sources = [ordered]@{ anforderungsmatrix = Get-Record $matrixPath $work; evidenzindex = Get-Record $indexPath $work; auftrag = Get-Record $orderPath $work; stellenbeschreibung = Get-Record $jobPath $work; profil = Get-Record $ProfilPath $work }
  documentContexts = @($contexts.ToArray()); exclusions = @($omissions | ForEach-Object { [ordered]@{ belegRefIds = @($_.belegRefIds); begruendung = [string]$_.begruendung } }); fallbackReasons = @($reasons.ToArray())
}
$target = if ([string]::IsNullOrWhiteSpace($BerichtPath)) { Join-Path $work 'Kontextmanifest.json' } else { $BerichtPath }
Write-AtomicJson -Path $target -Value $manifest -Depth 20
Write-Host "Kontextmanifest: $target ($($manifest.status))"
