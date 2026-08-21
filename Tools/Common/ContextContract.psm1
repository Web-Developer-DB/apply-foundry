#requires -Version 7.6
#requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ContextManifestSchemaVersion = 1
$script:ContextLoadingMode = 'vollkontext'

function Get-ContextLoadingMode { return $script:ContextLoadingMode }

function Merge-ContextRanges {
  param([Parameter(Mandatory)][array]$Ranges, [int]$Padding = 2)
  $expanded = @($Ranges | ForEach-Object {
    $from = [int]$_.zeileVon
    $to = [int]$_.zeileBis
    if ($from -lt 1 -or $to -lt $from) { return }
    [pscustomobject]@{ zeileVon = [math]::Max(1, $from - $Padding); zeileBis = $to + $Padding }
  } | Sort-Object zeileVon, zeileBis)
  $merged = [System.Collections.Generic.List[object]]::new()
  foreach ($range in $expanded) {
    if ($merged.Count -eq 0 -or $range.zeileVon -gt ($merged[$merged.Count - 1].zeileBis + 1)) {
      $merged.Add([ordered]@{ zeileVon = $range.zeileVon; zeileBis = $range.zeileBis }) | Out-Null
    } else {
      $merged[$merged.Count - 1].zeileBis = [math]::Max([int]$merged[$merged.Count - 1].zeileBis, [int]$range.zeileBis)
    }
  }
  return @($merged.ToArray())
}

function Test-ContextManifest {
  param([Parameter(Mandatory)][object]$Manifest)
  if ([int]$Manifest.schemaVersion -ne $script:ContextManifestSchemaVersion -or [string]$Manifest.kind -ne 'kontextmanifest') { return $false }
  if ([string]$Manifest.mode -notin @('vollkontext', 'evidenzbasiert')) { return $false }
  if ($null -eq $Manifest.sources -or $null -eq $Manifest.documentContexts) { return $false }
  return $true
}

Export-ModuleMember -Function @('Get-ContextLoadingMode', 'Merge-ContextRanges', 'Test-ContextManifest')
