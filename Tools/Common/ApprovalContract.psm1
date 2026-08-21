#requires -Version 7.6
#requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'JsonContract.psm1') -Force

function Resolve-ContractArtifactPath {
  param([Parameter(Mandatory)][string]$Candidate, [Parameter(Mandatory)][string]$Root)
  $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
  $candidateFull = [IO.Path]::GetFullPath($Candidate)
  $comparison = if ([OperatingSystem]::IsWindows()) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
  $prefix = $rootFull + [IO.Path]::DirectorySeparatorChar
  if (-not $candidateFull.StartsWith($prefix, $comparison)) { throw 'Pfad liegt außerhalb des Arbeitsordners.' }
  $current = $rootFull
  $relativeCandidate = [IO.Path]::GetRelativePath($rootFull, $candidateFull)
  $segments = @($relativeCandidate -split '[\\/]+')
  for ($index = 0; $index -lt $segments.Count; $index++) {
    $segment = $segments[$index]
    if ([string]::IsNullOrWhiteSpace($segment) -or $segment -eq '.') { continue }
    $current = Join-Path $current $segment
    $isLeaf = $index -eq ($segments.Count - 1)
    if ($isLeaf) {
      if (-not (Test-Path -LiteralPath $current -PathType Leaf)) { throw 'Freigabe-Artefakt fehlt.' }
    } elseif (-not (Test-Path -LiteralPath $current -PathType Container)) {
      throw 'Freigabe-Artefakt fehlt.'
    }
    $item = Get-Item -LiteralPath $current -Force
    if (([int]$item.Attributes -band [int][IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Freigabe-Artefakt liegt unter einem symbolischen Link.' }
  }
  return $candidateFull
}

function New-ContractApprovalId {
  return ('FR-' + [guid]::NewGuid().ToString('N').Substring(0, 12).ToUpperInvariant())
}

function Get-ContractArtifactSetHash {
  param([Parameter(Mandatory)][object[]]$Records, [string]$Root = '')
  $canonical = @($Records | ForEach-Object {
    $recordPath = [string](Get-ContractJsonProperty $_ 'path')
    if (-not [string]::IsNullOrWhiteSpace($Root)) {
      $recordPath = if ([IO.Path]::IsPathRooted($recordPath)) { [IO.Path]::GetFullPath($recordPath) } else { [IO.Path]::GetFullPath((Join-Path $Root $recordPath)) }
    }
    [ordered]@{ path = $recordPath.Replace('\','/'); bytes = [long](Get-ContractJsonProperty $_ 'bytes'); sha256 = ([string](Get-ContractJsonProperty $_ 'sha256')).ToUpperInvariant() }
  } | Sort-Object path | ConvertTo-Json -Depth 5 -Compress)
  $bytes = [Text.Encoding]::UTF8.GetBytes($canonical)
  return ([BitConverter]::ToString([Security.Cryptography.SHA256]::HashData($bytes)) -replace '-', '').ToUpperInvariant()
}

function Get-ContractApprovalRecords {
  param([Parameter(Mandatory)][object]$Report)
  $records = [Collections.Generic.List[object]]::new()
  $artifacts = Get-ContractJsonProperty $Report 'artifacts'
  if ($null -ne $artifacts) {
    $properties = if ($artifacts -is [Collections.IDictionary]) {
      @($artifacts.GetEnumerator() | ForEach-Object { [pscustomobject]@{ Name = [string]$_.Key; Value = $_.Value } })
    } else { @($artifacts.PSObject.Properties) }
    foreach ($property in $properties) {
      foreach ($record in @($property.Value)) { if ($null -ne $record -and $record -isnot [ValueType]) { $records.Add($record) | Out-Null } }
    }
  }
  foreach ($name in @('layoutReportArtifact','pdfReportArtifact','atsReportArtifact')) {
    $record = Get-ContractJsonProperty $Report $name
    if ($null -ne $record) { $records.Add($record) | Out-Null }
  }
  foreach ($name in @('candidate','screenshots','reports','order')) {
    $value = Get-ContractJsonProperty $Report $name
    if ($null -ne $value -and $name -in @('candidate','screenshots','reports')) {
      foreach ($record in @($value)) { if ($null -ne $record) { $records.Add($record) | Out-Null } }
    } elseif ($null -ne $value -and $name -eq 'order') { $records.Add($value) | Out-Null }
  }
  $unique = @{}
  foreach ($record in $records) { $key = ([string](Get-ContractJsonProperty $record 'path')).ToLowerInvariant(); if (-not $unique.ContainsKey($key)) { $unique[$key] = $record } }
  return @($unique.Values | Sort-Object { [string](Get-ContractJsonProperty $_ 'path') })
}

function Test-ContractArtifactRecordsCurrent {
  param([Parameter(Mandatory)][object[]]$Records, [Parameter(Mandatory)][string]$Root)
  foreach ($record in $Records) {
    $relative = ([string](Get-ContractJsonProperty $record 'path')).Replace('\','/')
    if ([IO.Path]::IsPathRooted($relative)) { $relative = [IO.Path]::GetRelativePath($Root, $relative).Replace('\','/') }
    if ([string]::IsNullOrWhiteSpace($relative) -or $relative -match '(^|/)\.\.(?:/|$)') { throw "Ungültiger Freigabe-Artefaktpfad: $relative" }
    try { $path = Resolve-ContractArtifactPath -Candidate (Join-Path $Root $relative) -Root $Root } catch { throw "Freigabe-Artefakt ist unsicher oder fehlt: $relative" }
    $file = Get-Item -LiteralPath $path -Force
    if ($file.Length -ne [long](Get-ContractJsonProperty $record 'bytes') -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine [string](Get-ContractJsonProperty $record 'sha256')) { throw "Freigabe-Artefakt wurde verändert: $relative" }
  }
}

Export-ModuleMember -Function @('New-ContractApprovalId','Get-ContractArtifactSetHash','Get-ContractApprovalRecords','Test-ContractArtifactRecordsCurrent')
