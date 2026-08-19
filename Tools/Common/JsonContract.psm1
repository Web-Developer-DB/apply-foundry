#requires -Version 7.6
#requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AtomicFile.psm1') -Force

function Get-ContractJsonProperty {
  param([object]$Object, [Parameter(Mandatory)][string]$Name)
  if ($null -eq $Object) { return $null }
  if ($Object -is [Collections.IDictionary]) {
    if ($Object.Contains($Name)) { return $Object[$Name] }
    return $null
  }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

function Test-ContractJsonProperty {
  param([object]$Object, [Parameter(Mandatory)][string]$Name)
  if ($null -eq $Object) { return $false }
  if ($Object -is [Collections.IDictionary]) { return $Object.Contains($Name) }
  return $null -ne $Object.PSObject.Properties[$Name]
}

function Read-ContractJson {
  param([Parameter(Mandatory)][string]$Path)
  return [IO.File]::ReadAllText([IO.Path]::GetFullPath($Path), [Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
}

function Write-ContractJson {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][object]$Value, [int]$Depth = 12)
  Write-AtomicJson -Path $Path -Value $Value -Depth $Depth
}

Export-ModuleMember -Function @(
  'Get-ContractJsonProperty',
  'Test-ContractJsonProperty',
  'Read-ContractJson',
  'Write-ContractJson'
)
