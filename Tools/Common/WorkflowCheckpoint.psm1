#requires -Version 7.6
#requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Nicht mit -Force laden: Aufrufer importieren Platform.psm1 bereits für ihre
# Sicherheitsfunktionen. Ein erzwungenes Neuladen würde deren privaten
# Funktionskontext während eines laufenden Werkzeugs entfernen.
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath 'Platform.psm1') -ErrorAction Stop
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath 'AtomicFile.psm1') -ErrorAction Stop

$script:CheckpointFileName = 'Workflow-Checkpoint.json'
$script:CheckpointSchemaVersion = 1
$script:CheckpointHistoryLimit = 24
$script:CheckpointSteps = @(
  'auftrag_angelegt',
  'profilabgleich_abgeschlossen',
  'analyse_abgeschlossen',
  'dokumente_abgeschlossen',
  'fachpruefung_abgeschlossen',
  'technische_vorbereitung_abgeschlossen',
  'sichtpruefung_bestaetigt',
  'veroeffentlicht'
)

function Get-CheckpointProperty {
  param([object]$Object, [string]$Name)

  if ($null -eq $Object) { return $null }
  if ($Object -is [System.Collections.IDictionary]) {
    if ($Object.Contains($Name)) { return $Object[$Name] }
    return $null
  }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

function Get-WorkflowCheckpointStepNames {
  return @($script:CheckpointSteps)
}

function Test-WorkflowCheckpointStep {
  param([string]$Step)

  return -not [string]::IsNullOrWhiteSpace($Step) -and $script:CheckpointSteps -contains $Step
}

function ConvertTo-CheckpointRelativePath {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Root
  )

  $relative = [System.IO.Path]::GetRelativePath($Root, $Path)
  if ([string]::IsNullOrWhiteSpace($relative) -or $relative -eq '.') {
    throw "Checkpoint-Artefakt darf nicht auf seinen Root zeigen: $Path"
  }
  if ([System.IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)') {
    throw "Checkpoint-Artefakt liegt nicht sicher im Arbeitsordner: $Path"
  }
  return ($relative -replace '\\', '/')
}

function Resolve-WorkflowCheckpointWorkFolder {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Arbeitsordner)

  $full = [System.IO.Path]::GetFullPath($Arbeitsordner).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
  )
  $workParent = [System.IO.Path]::GetDirectoryName($full)
  $companyFolder = if ([string]::IsNullOrWhiteSpace($workParent)) { $null } else { [System.IO.Path]::GetDirectoryName($workParent) }
  $applicationsRoot = if ([string]::IsNullOrWhiteSpace($companyFolder)) { $null } else { [System.IO.Path]::GetDirectoryName($companyFolder) }
  $comparison = Get-PathStringComparison

  if (
    [string]::IsNullOrWhiteSpace($applicationsRoot) -or
    [string]::IsNullOrWhiteSpace([System.IO.Path]::GetFileName($companyFolder)) -or
    -not [string]::Equals([System.IO.Path]::GetFileName($workParent), '_Arbeitsdateien', $comparison)
  ) {
    throw "Arbeitsordner besitzt nicht die erwartete <BewerbungenRoot>/<Firma>/_Arbeitsdateien/<Auftrag>-Struktur: $full"
  }

  $safeApplicationsRoot = Resolve-SafePath -Candidate $applicationsRoot -Root $applicationsRoot -AllowRoot -MustExist -ForWrite -PathType Container
  $safeWorkFolder = Resolve-SafePath -Candidate $full -Root $safeApplicationsRoot -MustExist -ForWrite -PathType Container
  return [pscustomobject][ordered]@{
    WorkFolder = $safeWorkFolder
    ApplicationsRoot = $safeApplicationsRoot
    WorkFolderRelative = (ConvertTo-CheckpointRelativePath -Path $safeWorkFolder -Root $safeApplicationsRoot)
    CheckpointPath = (Join-Path -Path $safeWorkFolder -ChildPath $script:CheckpointFileName)
  }
}

function Get-WorkflowCheckpointArtifacts {
  param([Parameter(Mandatory)][psobject]$Context)

  $records = [System.Collections.Generic.List[object]]::new()
  $comparison = Get-PathStringComparison
  foreach ($item in @(Get-ChildItem -LiteralPath $Context.WorkFolder -File -Force -Recurse | Sort-Object FullName)) {
    if ([string]::Equals($item.FullName, $Context.CheckpointPath, $comparison)) { continue }
    $safePath = Resolve-SafePath -Candidate $item.FullName -Root $Context.WorkFolder -MustExist -ForWrite -PathType Leaf
    $records.Add([ordered]@{
      path = ConvertTo-CheckpointRelativePath -Path $safePath -Root $Context.WorkFolder
      bytes = [long]$item.Length
      sha256 = (Get-FileHash -LiteralPath $safePath -Algorithm SHA256).Hash.ToUpperInvariant()
    }) | Out-Null
  }
  return @($records)
}

function Get-WorkflowCheckpointArtifactSetSha256 {
  param([Parameter(Mandatory)][object[]]$Artifacts)

  $canonical = @($Artifacts | Sort-Object { [string](Get-CheckpointProperty -Object $_ -Name 'path') }) | ConvertTo-Json -Compress -Depth 4
  $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($canonical)
  return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes))
}

function Get-WorkflowCheckpointOrderSummary {
  param([Parameter(Mandatory)][string]$OrderPath)

  try {
    $order = Get-Content -LiteralPath $OrderPath -Raw -Encoding UTF8 | ConvertFrom-Json
  } catch {
    throw "Bewerbungsauftrag.json ist für den Workflow-Checkpoint nicht lesbar: $($_.Exception.Message)"
  }

  $scope = Get-CheckpointProperty -Object $order -Name 'dokumentumfang'
  $dialog = Get-CheckpointProperty -Object $order -Name 'dialog'
  $blockingQuestions = 0
  foreach ($question in @((Get-CheckpointProperty -Object $dialog -Name 'rueckfragen'))) {
    if (
      $null -ne $question -and
      [string](Get-CheckpointProperty -Object $question -Name 'status') -eq 'offen' -and
      [bool](Get-CheckpointProperty -Object $question -Name 'blockiertDokumenterstellung')
    ) {
      $blockingQuestions++
    }
  }
  $pendingStorageDecisions = 0
  foreach ($fact in @((Get-CheckpointProperty -Object $dialog -Name 'angaben'))) {
    if ($null -ne $fact -and [string](Get-CheckpointProperty -Object $fact -Name 'speicherentscheidung') -eq 'ausstehend') {
      $pendingStorageDecisions++
    }
  }

  return [ordered]@{
    orderSchemaVersion = Get-CheckpointProperty -Object $order -Name 'schemaVersion'
    firmaSlug = [string](Get-CheckpointProperty -Object $order -Name 'firmaSlug')
    rolleSlug = [string](Get-CheckpointProperty -Object $order -Name 'rolleSlug')
    datum = [string](Get-CheckpointProperty -Object $order -Name 'datum')
    documentScope = [ordered]@{
      auswahl = [string](Get-CheckpointProperty -Object $scope -Name 'auswahl')
      lebenslauf = [string](Get-CheckpointProperty -Object $scope -Name 'lebenslauf')
      anschreiben = [bool](Get-CheckpointProperty -Object $scope -Name 'anschreiben')
      emailNachricht = [bool](Get-CheckpointProperty -Object $scope -Name 'emailNachricht')
    }
    dialog = [ordered]@{
      status = [string](Get-CheckpointProperty -Object $dialog -Name 'status')
      blockierendeRueckfragen = $blockingQuestions
      ausstehendeSpeicherentscheidungen = $pendingStorageDecisions
    }
  }
}

function Get-WorkflowCheckpointHistory {
  param([Parameter(Mandatory)][psobject]$Context)

  if (-not (Test-Path -LiteralPath $Context.CheckpointPath -PathType Leaf)) { return @() }
  try {
    $safePath = Resolve-SafePath -Candidate $Context.CheckpointPath -Root $Context.WorkFolder -MustExist -ForWrite -PathType Leaf
    $existing = Get-Content -LiteralPath $safePath -Raw -Encoding UTF8 | ConvertFrom-Json
  } catch {
    return @()
  }
  $schema = Get-CheckpointProperty -Object $existing -Name 'schemaVersion'
  if (($schema -isnot [int] -and $schema -isnot [long]) -or [int]$schema -ne $script:CheckpointSchemaVersion) { return @() }
  if ([string](Get-CheckpointProperty -Object $existing -Name 'workFolder') -cne $Context.WorkFolderRelative) { return @() }

  $history = [System.Collections.Generic.List[object]]::new()
  foreach ($entry in @((Get-CheckpointProperty -Object $existing -Name 'history'))) {
    $sequence = Get-CheckpointProperty -Object $entry -Name 'sequence'
    $step = [string](Get-CheckpointProperty -Object $entry -Name 'step')
    $updatedAtUtc = [string](Get-CheckpointProperty -Object $entry -Name 'updatedAtUtc')
    $artifactSetSha256 = [string](Get-CheckpointProperty -Object $entry -Name 'artifactSetSha256')
    $timestamp = [datetime]::MinValue
    if (
      ($sequence -is [int] -or $sequence -is [long]) -and [int]$sequence -gt 0 -and
      (Test-WorkflowCheckpointStep -Step $step) -and
      [datetime]::TryParse($updatedAtUtc, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$timestamp) -and
      $artifactSetSha256 -match '^[A-Fa-f0-9]{64}$'
    ) {
      $history.Add([ordered]@{
        sequence = [int]$sequence
        step = $step
        updatedAtUtc = $timestamp.ToUniversalTime().ToString('o')
        artifactSetSha256 = $artifactSetSha256.ToUpperInvariant()
      }) | Out-Null
    }
  }
  return @($history | Sort-Object sequence | Select-Object -Last $script:CheckpointHistoryLimit)
}

function Test-WorkflowCheckpointArtifactSet {
  param(
    [Parameter(Mandatory)][object[]]$Expected,
    [Parameter(Mandatory)][object[]]$Actual
  )

  if ($Expected.Count -ne $Actual.Count) { return $false }
  $comparer = if ($IsWindows) { [System.StringComparer]::OrdinalIgnoreCase } else { [System.StringComparer]::Ordinal }
  $actualByPath = [System.Collections.Generic.Dictionary[string, object]]::new($comparer)
  foreach ($record in $Actual) {
    $path = [string](Get-CheckpointProperty -Object $record -Name 'path')
    if (-not $actualByPath.TryAdd($path, $record)) { return $false }
  }
  foreach ($record in $Expected) {
    $path = [string](Get-CheckpointProperty -Object $record -Name 'path')
    $sha256 = [string](Get-CheckpointProperty -Object $record -Name 'sha256')
    $bytes = Get-CheckpointProperty -Object $record -Name 'bytes'
    if ([string]::IsNullOrWhiteSpace($path) -or $path -match '(^|/)\.\.(/|$)' -or $sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or ($bytes -isnot [int] -and $bytes -isnot [long])) {
      return $false
    }
    $current = $null
    if (-not $actualByPath.TryGetValue($path, [ref]$current)) { return $false }
    if ([long](Get-CheckpointProperty -Object $current -Name 'bytes') -ne [long]$bytes) { return $false }
    if ([string](Get-CheckpointProperty -Object $current -Name 'sha256') -cne $sha256.ToUpperInvariant()) { return $false }
  }
  return $true
}

function Get-WorkflowCheckpointStatus {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Arbeitsordner)

  $context = Resolve-WorkflowCheckpointWorkFolder -Arbeitsordner $Arbeitsordner
  if (-not (Test-Path -LiteralPath $context.CheckpointPath -PathType Leaf)) {
    return [pscustomobject][ordered]@{
      available = $false
      valid = $false
      reason = 'fehlend'
      updatedAtUtc = $null
      lastCompletedStep = $null
      artifactCount = 0
      historyCount = 0
    }
  }

  try {
    $safePath = Resolve-SafePath -Candidate $context.CheckpointPath -Root $context.WorkFolder -MustExist -ForWrite -PathType Leaf
    $checkpoint = Get-Content -LiteralPath $safePath -Raw -Encoding UTF8 | ConvertFrom-Json
  } catch {
    return [pscustomobject][ordered]@{ available = $true; valid = $false; reason = 'nicht_lesbar'; updatedAtUtc = $null; lastCompletedStep = $null; artifactCount = 0; historyCount = 0 }
  }
  $schema = Get-CheckpointProperty -Object $checkpoint -Name 'schemaVersion'
  if (($schema -isnot [int] -and $schema -isnot [long]) -or [int]$schema -ne $script:CheckpointSchemaVersion) {
    return [pscustomobject][ordered]@{ available = $true; valid = $false; reason = 'schema_ungueltig'; updatedAtUtc = $null; lastCompletedStep = $null; artifactCount = 0; historyCount = 0 }
  }
  if ([string](Get-CheckpointProperty -Object $checkpoint -Name 'kind') -cne 'workflow_checkpoint' -or [string](Get-CheckpointProperty -Object $checkpoint -Name 'workFolder') -cne $context.WorkFolderRelative) {
    return [pscustomobject][ordered]@{ available = $true; valid = $false; reason = 'arbeitsordner_abweichend'; updatedAtUtc = $null; lastCompletedStep = $null; artifactCount = 0; historyCount = 0 }
  }
  $step = [string](Get-CheckpointProperty -Object $checkpoint -Name 'lastCompletedStep')
  $updatedAtUtc = [string](Get-CheckpointProperty -Object $checkpoint -Name 'updatedAtUtc')
  $updatedAt = [datetime]::MinValue
  if (-not (Test-WorkflowCheckpointStep -Step $step) -or -not [datetime]::TryParse($updatedAtUtc, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$updatedAt)) {
    return [pscustomobject][ordered]@{ available = $true; valid = $false; reason = 'kopf_ungueltig'; updatedAtUtc = $null; lastCompletedStep = $null; artifactCount = 0; historyCount = 0 }
  }
  try {
    $expectedArtifacts = @((Get-CheckpointProperty -Object $checkpoint -Name 'artifacts'))
    $actualArtifacts = @(Get-WorkflowCheckpointArtifacts -Context $context)
    $expectedSetHash = [string](Get-CheckpointProperty -Object $checkpoint -Name 'artifactSetSha256')
    if ($expectedSetHash -notmatch '^[A-Fa-f0-9]{64}$' -or -not (Test-WorkflowCheckpointArtifactSet -Expected $expectedArtifacts -Actual $actualArtifacts) -or (Get-WorkflowCheckpointArtifactSetSha256 -Artifacts $actualArtifacts) -cne $expectedSetHash.ToUpperInvariant()) {
      return [pscustomobject][ordered]@{ available = $true; valid = $false; reason = 'artefakte_veraltet'; updatedAtUtc = $updatedAt.ToUniversalTime().ToString('o'); lastCompletedStep = $step; artifactCount = $expectedArtifacts.Count; historyCount = @((Get-CheckpointProperty -Object $checkpoint -Name 'history')).Count }
    }
  } catch {
    return [pscustomobject][ordered]@{ available = $true; valid = $false; reason = 'artefakte_ungueltig'; updatedAtUtc = $updatedAt.ToUniversalTime().ToString('o'); lastCompletedStep = $step; artifactCount = 0; historyCount = 0 }
  }
  return [pscustomobject][ordered]@{
    available = $true
    valid = $true
    reason = $null
    updatedAtUtc = $updatedAt.ToUniversalTime().ToString('o')
    lastCompletedStep = $step
    artifactCount = $expectedArtifacts.Count
    historyCount = @((Get-CheckpointProperty -Object $checkpoint -Name 'history')).Count
  }
}

function Write-WorkflowCheckpointCore {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Arbeitsordner,
    [Parameter(Mandatory)][string]$Schritt
  )

  if (-not (Test-WorkflowCheckpointStep -Step $Schritt)) {
    throw "Unzulässiger Workflow-Schritt: $Schritt"
  }
  $context = Resolve-WorkflowCheckpointWorkFolder -Arbeitsordner $Arbeitsordner
  $orderPath = Resolve-SafePath -Candidate (Join-Path -Path $context.WorkFolder -ChildPath 'Bewerbungsauftrag.json') -Root $context.WorkFolder -MustExist -ForWrite -PathType Leaf
  $orderSummary = Get-WorkflowCheckpointOrderSummary -OrderPath $orderPath
  $artifacts = @(Get-WorkflowCheckpointArtifacts -Context $context)
  $artifactSetSha256 = Get-WorkflowCheckpointArtifactSetSha256 -Artifacts $artifacts
  $history = [System.Collections.Generic.List[object]]::new()
  foreach ($entry in @(Get-WorkflowCheckpointHistory -Context $context)) { $history.Add($entry) | Out-Null }
  $nextSequence = if ($history.Count -eq 0) { 1 } else { ([int]$history[$history.Count - 1].sequence + 1) }
  $updatedAtUtc = [datetime]::UtcNow.ToString('o')
  $history.Add([ordered]@{
    sequence = $nextSequence
    step = $Schritt
    updatedAtUtc = $updatedAtUtc
    artifactSetSha256 = $artifactSetSha256
  }) | Out-Null
  if ($history.Count -gt $script:CheckpointHistoryLimit) {
    $history = [System.Collections.Generic.List[object]]::new(@($history | Select-Object -Last $script:CheckpointHistoryLimit))
  }

  $checkpoint = [ordered]@{
    schemaVersion = $script:CheckpointSchemaVersion
    kind = 'workflow_checkpoint'
    updatedAtUtc = $updatedAtUtc
    workFolder = $context.WorkFolderRelative
    lastCompletedStep = $Schritt
    order = $orderSummary
    artifacts = $artifacts
    artifactSetSha256 = $artifactSetSha256
    history = @($history)
    dataPolicy = [ordered]@{
      copiesSourceContents = $false
      containsRawChat = $false
      sourceOfTruth = 'referenzierte_arbeitsartefakte'
    }
  }

  $safeTarget = Resolve-SafePath -Candidate $context.CheckpointPath -Root $context.WorkFolder -ForWrite -PathType Leaf
  Write-AtomicJson -Path $safeTarget -Value $checkpoint -Depth 12
  return [pscustomobject][ordered]@{
    path = $safeTarget
    workFolder = $context.WorkFolderRelative
    step = $Schritt
    artifactCount = $artifacts.Count
    artifactSetSha256 = $artifactSetSha256
    updatedAtUtc = $updatedAtUtc
  }
}

function Write-WorkflowCheckpoint {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Arbeitsordner,
    [Parameter(Mandatory)][string]$Schritt
  )
  $context = Resolve-WorkflowCheckpointWorkFolder -Arbeitsordner $Arbeitsordner
  return Invoke-WithAtomicFileLock -Path $context.CheckpointPath -ScriptBlock {
    Write-WorkflowCheckpointCore -Arbeitsordner $Arbeitsordner -Schritt $Schritt
  }
}

Export-ModuleMember -Function @(
  'Get-WorkflowCheckpointStepNames',
  'Resolve-WorkflowCheckpointWorkFolder',
  'Get-WorkflowCheckpointStatus',
  'Write-WorkflowCheckpoint'
)
