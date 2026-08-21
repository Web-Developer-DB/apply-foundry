#requires -Version 7.6
#requires -PSEdition Core

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Arbeitsordner,

  [switch]$AlsJson,

  [switch]$Anwenden,

  [string]$BerichtPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Common/Platform.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Common/AtomicFile.psm1') -Force -Global
Import-Module (Join-Path $PSScriptRoot 'Common/JsonContract.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Common/DocumentScope.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Common/MatrixContract.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Common/EvidenceIndexContract.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Common/JsonContract.psm1') -Force -Global
Import-Module (Join-Path $PSScriptRoot 'Common/AtomicFile.psm1') -Force -Global

$script:ExitCode = 0
$script:ErrorClass = $null
$script:Errors = [System.Collections.Generic.List[string]]::new()
$script:Warnings = [System.Collections.Generic.List[string]]::new()
$script:Unresolved = [System.Collections.Generic.List[string]]::new()
$script:ChangedFiles = [System.Collections.Generic.List[string]]::new()

function Stop-Migration {
  param([Parameter(Mandatory)][string]$Message, [int]$Code = 2, [string]$ErrorClass = 'ungueltige_eingabe')
  $script:Errors.Add($Message) | Out-Null
  $script:ErrorClass = $ErrorClass
  $script:ExitCode = $Code
  throw $Message
}

function Add-Unresolved {
  param([Parameter(Mandatory)][string]$Field)
  if ($Field -notin $script:Unresolved) { $script:Unresolved.Add($Field) | Out-Null }
}

function Get-JsonHash {
  param([Parameter(Mandatory)][object]$Value, [int]$Depth = 30)
  $json = $Value | ConvertTo-Json -Depth $Depth
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
  return ([BitConverter]::ToString([Security.Cryptography.SHA256]::HashData($bytes)) -replace '-', '').ToUpperInvariant()
}

function Get-FileHashOrNull {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-Property {
  param([object]$Object, [string]$Name)
  if ($null -eq $Object) { return $null }
  if ($Object -is [Collections.IDictionary]) {
    if (-not $Object.Contains($Name)) { return $null }
    $value = $Object[$Name]
  } else {
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    $value = $property.Value
  }
  if ($value -is [array]) { return ,$value }
  return $value
}

function Set-Property {
  param([Parameter(Mandatory)][object]$Object, [Parameter(Mandatory)][string]$Name, [AllowNull()][object]$Value)
  if ($Object.PSObject.Properties[$Name]) {
    $Object.$Name = $Value
  } else {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
  }
}

function Test-PropertyPresent {
  param([object]$Object, [Parameter(Mandatory)][string]$Name)
  if ($null -eq $Object) { return $false }
  if ($Object -is [Collections.IDictionary]) { return $Object.Contains($Name) }
  return $null -ne $Object.PSObject.Properties[$Name]
}

function Get-Clone {
  param([Parameter(Mandatory)][object]$Value)
  return ($Value | ConvertTo-Json -Depth 40 | ConvertFrom-Json)
}

function Get-InferredPrivateRoot {
  param([Parameter(Mandatory)][string]$WorkFolder)
  $workFiles = Split-Path -Path $WorkFolder -Parent
  $company = Split-Path -Path $workFiles -Parent
  $applications = Split-Path -Path $company -Parent
  $private = Split-Path -Path $applications -Parent
  if ([string]::IsNullOrWhiteSpace($private)) { throw 'Privater Datenroot konnte aus dem Arbeitsordner nicht abgeleitet werden.' }
  return [System.IO.Path]::GetFullPath($private)
}

function Get-TextPath {
  param([Parameter(Mandatory)][string]$WorkFolder, [Parameter(Mandatory)][string]$RelativeName)
  $candidate = Join-Path $WorkFolder $RelativeName
  if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
  return $null
}

function New-RecruiterStrategyScaffold {
  return [pscustomobject][ordered]@{
    kernbotschaft = 'vor der Dokumenterstellung aus Zielrolle, Anforderungen und belegten Profilargumenten abzuleiten'
    profilSubstanz = 'noch_zu_pruefen'
    profilSubstanzBegruendung = 'fachlich zu ergänzen'
    prioritaetsAnforderungen = ([object[]]@())
    profilHighlights = ([object[]]@())
    transferbruecken = ([object[]]@())
    auslassungen = ([object[]]@())
  }
}

function New-LetterStrategyScaffold {
  param([bool]$Selected)
  return [pscustomobject][ordered]@{
    status = if ($Selected) { 'ausstehend' } else { 'nicht_erforderlich' }
    argumente = ([object[]]@())
    abweichungBegruendung = ''
  }
}

function Invoke-MatrixStep {
  param(
    [Parameter(Mandatory)][object]$Matrix,
    [Parameter(Mandatory)][int]$From,
    [Parameter(Mandatory)][int]$To,
    [AllowEmptyString()][string]$StellenbeschreibungPath,
    [Parameter(Mandatory)][bool]$LetterSelected
  )

  if ($From -eq 1 -and $To -eq 2) {
    foreach ($requirement in @((Get-Property $Matrix 'requirements'))) {
      if ([string]::IsNullOrWhiteSpace([string](Get-Property $requirement 'gewichtung'))) {
        $kind = [string](Get-Property $requirement 'typ')
        $fallbackWeight = 'niedrig'
        if ($kind -eq 'muss') { $fallbackWeight = 'hoch' }
        Set-Property $requirement 'gewichtung' $fallbackWeight
      }
      if ([string]::IsNullOrWhiteSpace([string](Get-Property $requirement 'kategorie'))) {
        Set-Property $requirement 'kategorie' 'noch_zu_pruefen'
        Add-Unresolved "requirements[$([string](Get-Property $requirement 'id'))].kategorie"
      }
    }
  } elseif ($From -eq 2 -and $To -eq 3) {
    if ($null -eq (Get-Property $Matrix 'recruiterStrategie')) {
      Set-Property $Matrix 'recruiterStrategie' (New-RecruiterStrategyScaffold)
      Add-Unresolved 'recruiterStrategie'
    }
  } elseif ($From -eq 3 -and $To -eq 4) {
    if ($null -eq (Get-Property $Matrix 'stellenanzeigeAbdeckung')) {
      $sourceHash = Get-FileHashOrNull -Path $StellenbeschreibungPath
      if ($null -eq $sourceHash) {
        Set-Property $Matrix 'stellenanzeigeAbdeckung' ([pscustomobject][ordered]@{ sourceSha256 = ''; fundstellen = ([object[]]@()) })
        Add-Unresolved 'stellenanzeigeAbdeckung.sourceSha256'
      } else {
        Set-Property $Matrix 'stellenanzeigeAbdeckung' ([pscustomobject][ordered]@{ sourceSha256 = $sourceHash; fundstellen = ([object[]]@()) })
      }
      Add-Unresolved 'stellenanzeigeAbdeckung.fundstellen'
    }
    foreach ($requirement in @((Get-Property $Matrix 'requirements'))) {
      if ($null -eq (Get-Property $requirement 'stellenFundstellen')) { Set-Property $requirement 'stellenFundstellen' ([object[]]@()) }
      if ($null -eq (Get-Property $requirement 'belegRefIds')) { Set-Property $requirement 'belegRefIds' ([object[]]@()) }
    }
  } elseif ($From -eq 4 -and $To -eq 5) {
    if ($null -eq (Get-Property $Matrix 'externeQuellen')) { Set-Property $Matrix 'externeQuellen' ([object[]]@()) }
    if ($null -eq (Get-Property $Matrix 'anschreibenStrategie')) {
      Set-Property $Matrix 'anschreibenStrategie' (New-LetterStrategyScaffold -Selected:$LetterSelected)
      if ($LetterSelected) { Add-Unresolved 'anschreibenStrategie.argumente' }
    }
    $strategy = Get-Property $Matrix 'recruiterStrategie'
    if ($null -eq $strategy) {
      Set-Property $Matrix 'recruiterStrategie' (New-RecruiterStrategyScaffold)
      Add-Unresolved 'recruiterStrategie'
    } elseif ($null -eq (Get-Property $strategy 'auslassungen')) {
      Set-Property $strategy 'auslassungen' ([object[]]@())
    }
  } else {
    Stop-Migration -Message "Nicht registrierter Matrix-Migrationsschritt $From->$To." -Code 2 -ErrorClass 'unbekanntes_schema'
  }
  Set-Property $Matrix 'schemaVersion' $To
}

function Invoke-EvidenceStep {
  param(
    [AllowNull()][object]$Index,
    [Parameter(Mandatory)][string]$ProfilPath,
    [Parameter(Mandatory)][string]$AuftragPath
  )
  if ($null -ne $Index) { return (Get-Clone -Value $Index) }
  $profileHash = Get-FileHashOrNull -Path $ProfilPath
  $orderHash = Get-FileHashOrNull -Path $AuftragPath
  if ($null -eq $profileHash) { Add-Unresolved 'Evidenzindex.profilSha256' }
  $draft = New-EvidenceIndexDraft -ProfilSha256 $profileHash -AuftragSha256 $orderHash
  Add-Unresolved 'Evidenzindex.belege'
  return $draft
}

function Test-MatrixTargetCompleteness {
  param([Parameter(Mandatory)][object]$Matrix, [Parameter(Mandatory)][bool]$LetterSelected)

  foreach ($property in @('requirements', 'recruiterStrategie', 'anschreibenStrategie', 'externeQuellen', 'stellenanzeigeAbdeckung')) {
    if (-not (Test-PropertyPresent -Object $Matrix -Name $property)) { Add-Unresolved "matrix.$property" }
  }
  $requirements = Get-Property $Matrix 'requirements'
  if (@($requirements).Count -eq 0) { Add-Unresolved 'matrix.requirements' }
  $requirementFields = @('id', 'anforderung', 'typ', 'kategorie', 'gewichtung', 'status', 'belegart', 'beleg', 'stellenFundstellen', 'belegRefIds', 'behandlung')
  $index = 0
  foreach ($requirement in @($requirements)) {
    foreach ($property in $requirementFields) {
      if (-not (Test-PropertyPresent -Object $requirement -Name $property)) { Add-Unresolved "requirements[$index].$property" }
    }
    foreach ($property in @('stellenFundstellen', 'belegRefIds')) {
      if ((Test-PropertyPresent -Object $requirement -Name $property) -and (Get-Property $requirement $property) -isnot [array]) { Add-Unresolved "requirements[$index].$property" }
    }
    $index++
  }
  $jobCoverage = Get-Property $Matrix 'stellenanzeigeAbdeckung'
  if ($null -ne $jobCoverage) {
    $sourceHash = [string](Get-Property $jobCoverage 'sourceSha256')
    if (-not (Test-EvidenceSha256 -Value $sourceHash)) { Add-Unresolved 'stellenanzeigeAbdeckung.sourceSha256' }
    if (-not (Test-PropertyPresent -Object $jobCoverage -Name 'fundstellen')) { Add-Unresolved 'stellenanzeigeAbdeckung.fundstellen' }
    elseif ((Get-Property $jobCoverage 'fundstellen') -isnot [array]) { Add-Unresolved 'stellenanzeigeAbdeckung.fundstellen' }
  }
  $recruiter = Get-Property $Matrix 'recruiterStrategie'
  foreach ($property in @('kernbotschaft', 'profilSubstanz', 'profilSubstanzBegruendung', 'prioritaetsAnforderungen', 'profilHighlights', 'transferbruecken', 'auslassungen')) {
    if ($null -ne $recruiter -and -not (Test-PropertyPresent -Object $recruiter -Name $property)) { Add-Unresolved "recruiterStrategie.$property" }
  }
  foreach ($property in @('prioritaetsAnforderungen', 'profilHighlights', 'transferbruecken', 'auslassungen')) {
    if ($null -ne $recruiter -and (Test-PropertyPresent -Object $recruiter -Name $property) -and (Get-Property $recruiter $property) -isnot [array]) { Add-Unresolved "recruiterStrategie.$property" }
  }
  $letter = Get-Property $Matrix 'anschreibenStrategie'
  foreach ($property in @('status', 'argumente', 'abweichungBegruendung')) {
    if ($null -ne $letter -and -not (Test-PropertyPresent -Object $letter -Name $property)) { Add-Unresolved "anschreibenStrategie.$property" }
  }
  if ($null -ne $letter -and $LetterSelected) {
    $arguments = Get-Property $letter 'argumente'
    if ((Test-PropertyPresent -Object $letter -Name 'argumente') -and $arguments -isnot [array]) { Add-Unresolved 'anschreibenStrategie.argumente' }
    if ([string](Get-Property $letter 'status') -ne 'final' -or @($arguments).Count -eq 0) { Add-Unresolved 'anschreibenStrategie.argumente' }
  }
  if ((Test-PropertyPresent -Object $Matrix -Name 'externeQuellen') -and (Get-Property $Matrix 'externeQuellen') -isnot [array]) { Add-Unresolved 'matrix.externeQuellen' }
}

function Test-EvidenceTargetCompleteness {
  param([Parameter(Mandatory)][object]$Index)

  $profileHash = [string](Get-Property $Index 'profilSha256')
  if (-not (Test-EvidenceSha256 -Value $profileHash)) { Add-Unresolved 'Evidenzindex.profilSha256' }
  $records = Get-Property $Index 'belege'
  if (-not (Test-PropertyPresent -Object $Index -Name 'belege') -or @($records).Count -eq 0) { Add-Unresolved 'Evidenzindex.belege' }
  if ((Test-PropertyPresent -Object $Index -Name 'belege') -and $records -isnot [array]) { Add-Unresolved 'Evidenzindex.belege' }
  $index = 0
  foreach ($record in @($records)) {
    if (-not (Test-EvidenceRecordShape -Record $record)) { Add-Unresolved "Evidenzindex.belege[$index]" }
    $index++
  }
}

function Test-DraftConflict {
  param([string]$Path, [object]$Value)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  $existing = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
  return (Get-JsonHash -Value $existing) -ne (Get-JsonHash -Value $Value)
}

function Write-MigrationReport {
  param([Parameter(Mandatory)][object]$Report, [string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return }
  Write-AtomicJson -Path $Path -Value $Report -Depth 20
}

function Invoke-ApplyMigration {
  param(
    [Parameter(Mandatory)][string]$LockPath,
    [Parameter(Mandatory)][string]$MatrixPath,
    [Parameter(Mandatory)][string]$EvidencePath,
    [Parameter(Mandatory)][string]$MatrixJson,
    [Parameter(Mandatory)][string]$EvidenceJson,
    [Parameter(Mandatory)][string]$MatrixSourceHash,
    [string]$EvidenceSourceHash
  )

  Invoke-WithAtomicFileLock -Path $LockPath -ScriptBlock {
    if ((Get-FileHashOrNull -Path $MatrixPath) -ne $MatrixSourceHash) {
      Stop-Migration -Message 'Anforderungsmatrix wurde während der Migration geändert; Hash-Recheck fehlgeschlagen.' -Code 1 -ErrorClass 'konkurrenz_aenderung'
    }
    if ($null -ne $EvidenceSourceHash -and (Get-FileHashOrNull -Path $EvidencePath) -ne $EvidenceSourceHash) {
      Stop-Migration -Message 'Evidenzindex wurde während der Migration geändert; Hash-Recheck fehlgeschlagen.' -Code 1 -ErrorClass 'konkurrenz_aenderung'
    }

    $backupRoot = Join-Path (Split-Path $MatrixPath -Parent) ('Migration-Sicherungen/' + [datetime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'))
    New-Item -Path $backupRoot -ItemType Directory -Force | Out-Null
    $matrixBackup = Join-Path $backupRoot 'Anforderungsmatrix.json'
    $evidenceBackup = Join-Path $backupRoot 'Evidenzindex.json'
    Copy-Item -LiteralPath $MatrixPath -Destination $matrixBackup -Force
    $evidenceExisted = Test-Path -LiteralPath $EvidencePath -PathType Leaf
    if ($evidenceExisted) { Copy-Item -LiteralPath $EvidencePath -Destination $evidenceBackup -Force }
    $matrixWritten = $false
    $evidenceWritten = $false
    try {
      Write-AtomicText -Path $MatrixPath -Content $MatrixJson
      $matrixWritten = $true
      Write-AtomicText -Path $EvidencePath -Content $EvidenceJson
      $evidenceWritten = $true
    } catch {
      if ($matrixWritten) { Write-AtomicText -Path $MatrixPath -Content ([IO.File]::ReadAllText($matrixBackup, [Text.UTF8Encoding]::new($false))) }
      if ($evidenceWritten) {
        if ($evidenceExisted) { Write-AtomicText -Path $EvidencePath -Content ([IO.File]::ReadAllText($evidenceBackup, [Text.UTF8Encoding]::new($false))) }
        elseif (Test-Path -LiteralPath $EvidencePath -PathType Leaf) { Remove-Item -LiteralPath $EvidencePath -Force }
      }
      throw
    }
  }
}

$resolvedWork = $null
$matrixPath = $null
$evidencePath = $null
$reportPath = $null
$report = $null
try {
  try {
    $resolvedWork = Resolve-SafePath -Candidate $Arbeitsordner -Root $Arbeitsordner -AllowRoot -MustExist -ForWrite -PathType Container
  } catch {
    Stop-Migration -Message $_.Exception.Message -Code 2 -ErrorClass 'unsicherer_pfad'
  }
  try {
    $matrixPath = Resolve-SafePath -Candidate (Join-Path $resolvedWork 'Anforderungsmatrix.json') -Root $resolvedWork -MustExist -ForWrite -PathType Leaf
    $evidenceCandidate = Join-Path $resolvedWork 'Evidenzindex.json'
    $evidencePath = Resolve-SafePath -Candidate $evidenceCandidate -Root $resolvedWork -ForWrite -PathType Leaf
  $auftragPath = Resolve-SafePath -Candidate (Join-Path $resolvedWork 'Bewerbungsauftrag.json') -Root $resolvedWork -MustExist -PathType Leaf
  } catch {
    Stop-Migration -Message 'Arbeitsordner enthält keinen sicheren Vertragsdateipfad.' -Code 2 -ErrorClass 'unsicherer_pfad'
  }
  $stellenPath = Get-TextPath -WorkFolder $resolvedWork -RelativeName 'Kandidat/Stellenbeschreibung.md'
  if ($null -eq $stellenPath) { $stellenPath = Get-TextPath -WorkFolder $resolvedWork -RelativeName 'Stellenbeschreibung.md' }
  $privateRoot = Get-InferredPrivateRoot -WorkFolder $resolvedWork
  $profilPath = Join-Path $privateRoot 'Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md'

  $auftrag = Get-Content -LiteralPath $auftragPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $scope = Get-ContractDocumentScope -Auftrag $auftrag
  $matrixSource = Get-Content -LiteralPath $matrixPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $matrixSourceHash = Get-FileHashOrNull -Path $matrixPath
  try {
    $matrixSchema = Get-MatrixSchemaVersion -Matrix $matrixSource
  } catch {
    Stop-Migration -Message $_.Exception.Message -Code 2 -ErrorClass 'unbekanntes_schema'
  }
  $evidenceExists = Test-Path -LiteralPath $evidencePath -PathType Leaf
  $evidenceSource = if ($evidenceExists) { Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
  $evidenceSourceHash = if ($evidenceExists) { Get-FileHashOrNull -Path $evidencePath } else { $null }
  if ($null -ne $evidenceSource) {
    try {
      [void](Get-EvidenceIndexSchemaVersion -Index $evidenceSource)
    } catch {
      Stop-Migration -Message $_.Exception.Message -Code 2 -ErrorClass 'unbekanntes_schema'
    }
  }

  $matrixTarget = Get-Clone -Value $matrixSource
  $current = $matrixSchema
  $steps = [System.Collections.Generic.List[object]]::new()
  while ($current -lt 5) {
    $next = $current + 1
    $stepId = "matrix/$current-zu-$next"
    Invoke-MatrixStep -Matrix $matrixTarget -From $current -To $next -StellenbeschreibungPath $stellenPath -LetterSelected ([bool]$scope.anschreiben)
    $steps.Add([ordered]@{ id = $stepId; from = $current; to = $next; status = 'ausgeführt' }) | Out-Null
    $current = $next
  }

  $evidenceTarget = Invoke-EvidenceStep -Index $evidenceSource -ProfilPath $profilPath -AuftragPath $auftragPath
  if ($null -eq $evidenceSource) {
    $steps.Add([ordered]@{ id = 'evidenzindex/0-zu-1'; from = 0; to = 1; status = 'ausgeführt' }) | Out-Null
  }
  $evidenceBelege = Get-Property $evidenceSource 'belege'
  if ($null -ne $evidenceSource -and @($evidenceBelege).Count -eq 0) {
    Add-Unresolved 'Evidenzindex.belege'
  }
  Test-MatrixTargetCompleteness -Matrix $matrixTarget -LetterSelected ([bool]$scope.anschreiben)
  Test-EvidenceTargetCompleteness -Index $evidenceTarget
  if ($matrixSchema -eq 5) {
    foreach ($requiredProperty in @('recruiterStrategie', 'anschreibenStrategie', 'externeQuellen', 'stellenanzeigeAbdeckung')) {
      if ($null -eq (Get-Property $matrixTarget $requiredProperty)) { Add-Unresolved "matrix.$requiredProperty" }
    }
    $letterStrategy = Get-Property $matrixTarget 'anschreibenStrategie'
    if ([bool]$scope.anschreiben -and $null -ne $letterStrategy -and [string](Get-Property $letterStrategy 'status') -ne 'final') {
      Add-Unresolved 'anschreibenStrategie.argumente'
    }
  }
  if ($null -eq $stellenPath -and $matrixSchema -lt 4) { Add-Unresolved 'Kandidat/Stellenbeschreibung.md' }

  $matrixJson = $matrixTarget | ConvertTo-Json -Depth 40
  $evidenceJson = $evidenceTarget | ConvertTo-Json -Depth 20
  $matrixTargetHash = Get-JsonHash -Value $matrixTarget
  $evidenceTargetHash = Get-JsonHash -Value $evidenceTarget
  $draftMatrixPath = Join-Path $resolvedWork 'Anforderungsmatrix--MIGRATION-ENTWURF.json'
  $draftEvidencePath = Join-Path $resolvedWork 'Evidenzindex--MIGRATION-ENTWURF.json'
  $migrationIncomplete = $script:Unresolved.Count -gt 0
  $reportStatus = if ($migrationIncomplete) { 'unvollstaendig' } elseif ($matrixSchema -eq 5 -and $evidenceExists) { 'aktuell' } else { 'bereit_zur_uebernahme' }
  $report = [ordered]@{
    schemaVersion = 1
    kind = 'matrix_evidenz_migration'
    status = $reportStatus
    preview = (-not $Anwenden)
    preparedAtUtc = [datetime]::UtcNow.ToString('o')
    workFolder = $resolvedWork
    matrix = [ordered]@{ sourceSchemaVersion = $matrixSchema; targetSchemaVersion = 5; sourceSha256 = $matrixSourceHash; targetSha256 = $matrixTargetHash; draftPath = if ($migrationIncomplete) { 'Anforderungsmatrix--MIGRATION-ENTWURF.json' } else { $null } }
    evidenzindex = [ordered]@{ sourceSchemaVersion = if ($null -eq $evidenceSource) { 0 } else { 1 }; targetSchemaVersion = 1; sourceSha256 = $evidenceSourceHash; targetSha256 = $evidenceTargetHash; draftPath = if ($migrationIncomplete) { 'Evidenzindex--MIGRATION-ENTWURF.json' } else { $null } }
    steps = @($steps)
    unresolvedFields = @($script:Unresolved)
    changedFiles = @()
    errors = @($script:Errors)
    warnings = @($script:Warnings)
    errorClass = $script:ErrorClass
  }

  if ($Anwenden) {
    if ($migrationIncomplete) {
      if (Test-DraftConflict -Path $draftMatrixPath -Value $matrixTarget) { Stop-Migration -Message 'Vorhandener Matrix-Migrationsentwurf würde überschrieben; bitte erst manuell prüfen.' -Code 2 -ErrorClass 'migration_entwurf_konflikt' }
      if (Test-DraftConflict -Path $draftEvidencePath -Value $evidenceTarget) { Stop-Migration -Message 'Vorhandener Evidenzindex-Migrationsentwurf würde überschrieben; bitte erst manuell prüfen.' -Code 2 -ErrorClass 'migration_entwurf_konflikt' }
      Write-AtomicJson -Path $draftMatrixPath -Value $matrixTarget -Depth 40
      Write-AtomicJson -Path $draftEvidencePath -Value $evidenceTarget -Depth 20
      $script:ChangedFiles.Add('Anforderungsmatrix--MIGRATION-ENTWURF.json') | Out-Null
      $script:ChangedFiles.Add('Evidenzindex--MIGRATION-ENTWURF.json') | Out-Null
      $report.status = 'entwurf_erzeugt'
      $report.preview = $false
    } elseif (-not $migrationIncomplete -and $matrixSchema -eq 5 -and $evidenceExists) {
      $report.status = 'aktuell'
      $report.preview = $false
    } else {
      Invoke-ApplyMigration -LockPath (Join-Path $resolvedWork 'Migration.lock') -MatrixPath $matrixPath -EvidencePath $evidencePath -MatrixJson $matrixJson -EvidenceJson $evidenceJson -MatrixSourceHash $matrixSourceHash -EvidenceSourceHash $evidenceSourceHash
      $script:ChangedFiles.Add('Anforderungsmatrix.json') | Out-Null
      $script:ChangedFiles.Add('Evidenzindex.json') | Out-Null
      $report.status = if ($matrixSchema -eq 5 -and $evidenceExists) { 'aktuell' } else { 'migriert' }
      $report.preview = $false
    }
  }
  $report.changedFiles = @($script:ChangedFiles)
  if ([string]::IsNullOrWhiteSpace($BerichtPath) -and $Anwenden) { $BerichtPath = Join-Path $resolvedWork 'Migrationsbericht.json' }
  if (-not [string]::IsNullOrWhiteSpace($BerichtPath)) {
    try {
      $reportPath = Resolve-SafePath -Candidate $BerichtPath -Root $resolvedWork -ForWrite
    } catch {
      Stop-Migration -Message $_.Exception.Message -Code 2 -ErrorClass 'unsicherer_pfad'
    }
    Write-MigrationReport -Report $report -Path $reportPath
  }
  if ($AlsJson) { $report | ConvertTo-Json -Depth 20 | Write-Output } else {
    Write-Host "[INFO] Migrationsstatus: $($report.status)"
    if (@($script:Unresolved).Count -gt 0) { Write-Host "[WARNUNG] Offene Ergänzungen: $(@($script:Unresolved) -join ', ')" -ForegroundColor Yellow }
    if (@($script:ChangedFiles).Count -gt 0) { Write-Host "[OK] Geänderte Dateien: $(@($script:ChangedFiles) -join ', ')" -ForegroundColor Green }
  }
  if ($report.status -in @('unvollstaendig', 'entwurf_erzeugt')) { exit 1 }
  exit 0
} catch {
  if ($script:ExitCode -eq 0) { $script:ExitCode = 1; $script:ErrorClass = if ($null -eq $script:ErrorClass) { 'laufzeitfehler' } else { $script:ErrorClass } }
  if ($script:Errors.Count -eq 0) { $script:Errors.Add($_.Exception.Message) | Out-Null }
  $failure = [ordered]@{
    schemaVersion = 1
    kind = 'matrix_evidenz_migration'
    status = 'fehlgeschlagen'
    preview = (-not $Anwenden)
    preparedAtUtc = [datetime]::UtcNow.ToString('o')
    workFolder = $resolvedWork
    errors = @($script:Errors)
    errorClass = $script:ErrorClass
    changedFiles = @($script:ChangedFiles)
  }
  if (-not [string]::IsNullOrWhiteSpace($BerichtPath) -and $null -ne $resolvedWork) {
    try {
      $failurePath = Resolve-SafePath -Candidate $BerichtPath -Root $resolvedWork -ForWrite
      Write-MigrationReport -Report $failure -Path $failurePath
    } catch {}
  }
  if ($AlsJson) { $failure | ConvertTo-Json -Depth 20 | Write-Output } else { Write-Host "[FEHLER] $($script:Errors -join '; ')" -ForegroundColor Red }
  exit $script:ExitCode
}
