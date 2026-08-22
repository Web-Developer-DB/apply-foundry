#requires -Version 7.6
#requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'JsonContract.psm1') -Force

function Get-ContractDocumentScope {
  param([Parameter(Mandatory)][object]$Auftrag)
  $schema = Get-ContractJsonProperty $Auftrag 'schemaVersion'
  if ($schema -isnot [int] -and $schema -isnot [long]) { throw 'Bewerbungsauftrag enthält keine ganzzahlige schemaVersion.' }
  $scope = [ordered]@{ lebenslauf = 'individuell'; anschreiben = $true; emailNachricht = $true }
  $configured = Get-ContractJsonProperty $Auftrag 'dokumentumfang'
  if ([int]$schema -ge 4 -and $null -ne $configured) {
    $cv = [string](Get-ContractJsonProperty $configured 'lebenslauf')
    $letter = Get-ContractJsonProperty $configured 'anschreiben'
    $email = Get-ContractJsonProperty $configured 'emailNachricht'
    if ($cv -notin @('individuell','universal_unveraendert','nicht_enthalten') -or $letter -isnot [bool] -or $email -isnot [bool]) {
      throw 'Bewerbungsauftrag enthält einen ungültigen oder nicht typisierten dokumentumfang.'
    }
    if ($cv -eq 'nicht_enthalten' -and -not [bool]$letter -and -not [bool]$email) { throw 'Bewerbungsauftrag wählt kein Dokument aus.' }
    $scope.lebenslauf = $cv; $scope.anschreiben = [bool]$letter; $scope.emailNachricht = [bool]$email
  } elseif ([int]$schema -lt 1 -or [int]$schema -gt 5) {
    throw "Bewerbungsauftrag verwendet keine unterstützte schemaVersion 1 bis 5."
  } elseif ([string](Get-ContractJsonProperty $Auftrag 'dokumentmodus') -eq 'anschreiben_mit_universalem_lebenslauf') {
    $scope.lebenslauf = 'universal_unveraendert'
  }
  return $scope
}

function Test-ContractDocumentScope {
  param([object]$Actual, [Parameter(Mandatory)][object]$Expected)
  if ($null -eq $Actual) { return $false }
  return ([string](Get-ContractJsonProperty $Actual 'lebenslauf') -ceq [string]$Expected.lebenslauf -and
    (Get-ContractJsonProperty $Actual 'anschreiben') -is [bool] -and
    (Get-ContractJsonProperty $Actual 'emailNachricht') -is [bool] -and
    [bool](Get-ContractJsonProperty $Actual 'anschreiben') -eq [bool]$Expected.anschreiben -and
    [bool](Get-ContractJsonProperty $Actual 'emailNachricht') -eq [bool]$Expected.emailNachricht)
}

Export-ModuleMember -Function @('Get-ContractDocumentScope','Test-ContractDocumentScope')
