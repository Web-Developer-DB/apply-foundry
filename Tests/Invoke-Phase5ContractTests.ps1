#requires -PSEdition Core

[CmdletBinding()]
param(
  [string]$RepoRoot = (Split-Path -Path $PSScriptRoot -Parent)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$passed = 0
$failed = 0
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('bewerbungs-agent-phase5-' + [guid]::NewGuid().ToString('N'))
$powerShellExe = (Get-Process -Id $PID).Path
$toolsRoot = Join-Path $RepoRoot 'Tools'

Import-Module (Join-Path $toolsRoot 'Common/MatrixContract.psm1') -Force
Import-Module (Join-Path $toolsRoot 'Common/EvidenceIndexContract.psm1') -Force

function Assert-Phase5 {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

function Invoke-Phase5Test {
  param([string]$Name, [scriptblock]$Body)
  try {
    & $Body
    $script:passed++
    Write-Host "[OK] $Name" -ForegroundColor Green
  } catch {
    $script:failed++
    Write-Host "[FEHLER] ${Name}: $($_.Exception.Message)" -ForegroundColor Red
  }
}

function New-Phase5Fixture {
  param([Parameter(Mandatory)][string]$Name, [switch]$Incomplete)
  $privateRoot = Join-Path $testRoot $Name 'Private'
  $work = Join-Path $privateRoot 'Bewerbungen/Migration-Firma/_Arbeitsdateien/2026-08-19--Migration-Rolle'
  $candidate = Join-Path $work 'Kandidat'
  $dataRoot = Join-Path $privateRoot 'Daten'
  New-Item -Path $candidate -ItemType Directory -Force | Out-Null
  New-Item -Path $dataRoot -ItemType Directory -Force | Out-Null
  $profilePath = Join-Path $dataRoot '02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md'
  Set-Content -LiteralPath $profilePath -Encoding UTF8 -Value "# Profil`n`nWeiterbildung: Migrationstest"
  $jobPath = Join-Path $candidate 'Stellenbeschreibung.md'
  Set-Content -LiteralPath $jobPath -Encoding UTF8 -Value "## Ihr Profil`n- Migrationstest"
  $auftrag = [ordered]@{
    schemaVersion = 5
    dokumentumfang = [ordered]@{ lebenslauf = 'nicht_enthalten'; anschreiben = $false; emailNachricht = $true }
  }
  $auftragPath = Join-Path $work 'Bewerbungsauftrag.json'
  Set-Content -LiteralPath $auftragPath -Encoding UTF8 -Value ($auftrag | ConvertTo-Json -Depth 10)
  $matrixPath = Join-Path $work 'Anforderungsmatrix.json'
  if ($Incomplete) {
    $matrix = [ordered]@{ schemaVersion = 1; requirements = @([ordered]@{ id = 'muss-1'; anforderung = 'Migrationstest'; typ = 'muss'; status = 'unklar'; belegart = ''; beleg = ''; behandlung = 'klären' }) }
  } else {
    $matrix = [ordered]@{
      schemaVersion = 4
      requirements = @([ordered]@{ id = 'muss-1'; anforderung = 'Migrationstest'; typ = 'muss'; kategorie = 'fachlich'; gewichtung = 'hoch'; status = 'erfuellt'; belegart = 'WEITERBILDUNG'; beleg = 'Migrationstest'; stellenFundstellen = @('stelle-1'); belegRefIds = @('profil-1'); behandlung = 'E-Mail' })
      recruiterStrategie = [ordered]@{ kernbotschaft = 'Belegter Migrationstest mit klarer Struktur'; profilSubstanz = 'ausreichend'; profilSubstanzBegruendung = 'Testbeleg'; prioritaetsAnforderungen = @('muss-1'); profilHighlights = @(); transferbruecken = @(); auslassungen = @() }
      stellenanzeigeAbdeckung = [ordered]@{ sourceSha256 = (Get-FileHash -LiteralPath $jobPath -Algorithm SHA256).Hash; fundstellen = @([ordered]@{ id = 'stelle-1'; zeileVon = 2; zeileBis = 2; text = '- Migrationstest'; klassifikation = 'anforderung'; anforderungIds = @('muss-1') }) }
    }
  }
  Set-Content -LiteralPath $matrixPath -Encoding UTF8 -Value ($matrix | ConvertTo-Json -Depth 20)
  $evidencePath = Join-Path $work 'Evidenzindex.json'
  if (-not $Incomplete) {
    $evidence = [ordered]@{ schemaVersion = 1; profilSha256 = (Get-FileHash -LiteralPath $profilePath -Algorithm SHA256).Hash; belege = @([ordered]@{ id = 'profil-1'; quelle = 'profil'; zeileVon = 3; zeileBis = 3; text = 'Weiterbildung: Migrationstest'; belegart = 'WEITERBILDUNG' }) }
    Set-Content -LiteralPath $evidencePath -Encoding UTF8 -Value ($evidence | ConvertTo-Json -Depth 12)
  }
  return [pscustomobject]@{ Work = $work; Matrix = $matrixPath; Evidence = $evidencePath }
}

function Invoke-Migration {
  param([Parameter(Mandatory)][string]$Work, [switch]$Apply)
  $args = @('-Arbeitsordner', $Work, '-AlsJson')
  if ($Apply) { $args += '-Anwenden' }
  $output = & $powerShellExe -NoProfile -File (Join-Path $toolsRoot 'Migriere-Bewerbungsnachweise.ps1') @args 2>&1
  return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = @($output) }
}

try {
  Invoke-Phase5Test -Name 'Matrix- und Evidenzverträge versionieren aktuelle und Legacy-Strukturen' -Body {
    $matrixDraft = New-MatrixDraft -IncludeLetter:$true
    Assert-Phase5 ((Get-MatrixSchemaVersion -Matrix $matrixDraft) -eq 5) 'MatrixContract erzeugt keinen Schema-5-Entwurf.'
    foreach ($version in @(1, 2, 3, 4, 5)) {
      $legacy = $matrixDraft | ConvertTo-Json -Depth 20 | ConvertFrom-Json
      $legacy.schemaVersion = $version
      Assert-Phase5 ((Get-MatrixSchemaVersion -Matrix $legacy) -eq $version) "MatrixContract liest Schema $version nicht."
    }
    $invalid = $matrixDraft | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $invalid.schemaVersion = $true
    $thrown = $false
    try { $null = Get-MatrixSchemaVersion -Matrix $invalid } catch { $thrown = $true }
    Assert-Phase5 $thrown 'MatrixContract akzeptiert eine boolesche schemaVersion.'
    $missing = [pscustomobject]@{ requirements = @() }
    $thrown = $false
    try { $null = Get-MatrixSchemaVersion -Matrix $missing } catch { $thrown = $true }
    Assert-Phase5 $thrown 'MatrixContract akzeptiert eine fehlende schemaVersion.'
    $future = [pscustomobject]@{ schemaVersion = 6 }
    $thrown = $false
    try { $null = Get-MatrixSchemaVersion -Matrix $future } catch { $thrown = $true }
    Assert-Phase5 $thrown 'MatrixContract akzeptiert ein zukünftiges Schema.'
    $evidence = New-EvidenceIndexDraft -ProfilSha256 ('A' * 64)
    Assert-Phase5 ((Get-EvidenceIndexSchemaVersion -Index $evidence) -eq 1) 'EvidenceIndexContract erzeugt keinen Schema-1-Entwurf.'
    Assert-Phase5 ((Test-EvidenceSha256 -Value ('A' * 64)) -and -not (Test-EvidenceSha256 -Value 'gebrochen')) 'EvidenceIndexContract validiert SHA-256-Grundstruktur nicht.'
    Assert-Phase5 ((Get-EvidenceIndexSchemaVersion -Index $null -AllowMissing) -eq 0) 'EvidenceIndexContract behandelt einen fehlenden Index nicht als Migrationsversion 0.'
    $brokenEvidence = [pscustomobject]@{ schemaVersion = $true }
    Assert-Phase5 (-not (Test-EvidenceIndexSchemaVersion -Index $brokenEvidence -Expected 1)) 'EvidenceIndexContract akzeptiert eine boolesche schemaVersion.'
    $futureEvidence = [pscustomobject]@{ schemaVersion = 2 }
    Assert-Phase5 (-not (Test-EvidenceIndexSchemaVersion -Index $futureEvidence -Expected 1)) 'EvidenceIndexContract akzeptiert ein zukünftiges Schema.'
    Assert-Phase5 (@(Get-MatrixMigrationSteps).Count -eq 4 -and @((Get-EvidenceIndexMigrationSteps)).Count -eq 1) 'Migrationsschritte sind unvollständig.'
  }

  Invoke-Phase5Test -Name 'Migrationspreview bleibt read-only und vollständige Übernahme ist idempotent' -Body {
    $fixture = New-Phase5Fixture -Name 'complete'
    $matrixBefore = (Get-FileHash -LiteralPath $fixture.Matrix -Algorithm SHA256).Hash
    $preview = Invoke-Migration -Work $fixture.Work
    Assert-Phase5 ($preview.ExitCode -eq 0) "Migrationspreview schlug fehl: $($preview.Output -join ' | ')"
    Assert-Phase5 ((Get-FileHash -LiteralPath $fixture.Matrix -Algorithm SHA256).Hash -eq $matrixBefore) 'Preview veränderte die Originalmatrix.'
    $apply = Invoke-Migration -Work $fixture.Work -Apply
    Assert-Phase5 ($apply.ExitCode -eq 0) "Migration schlug fehl: $($apply.Output -join ' | ')"
    $migrated = Get-Content -LiteralPath $fixture.Matrix -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Phase5 ($migrated.schemaVersion -eq 5 -and $migrated.anschreibenStrategie.status -eq 'nicht_erforderlich') 'Migration erzeugte keine vollständige Matrix-5-Struktur.'
    $afterMatrix = (Get-FileHash -LiteralPath $fixture.Matrix -Algorithm SHA256).Hash
    $afterEvidence = (Get-FileHash -LiteralPath $fixture.Evidence -Algorithm SHA256).Hash
    $repeat = Invoke-Migration -Work $fixture.Work -Apply
    Assert-Phase5 ($repeat.ExitCode -eq 0) "Idempotente Migration schlug fehl: $($repeat.Output -join ' | ')"
    Assert-Phase5 ((Get-FileHash -LiteralPath $fixture.Matrix -Algorithm SHA256).Hash -eq $afterMatrix -and (Get-FileHash -LiteralPath $fixture.Evidence -Algorithm SHA256).Hash -eq $afterEvidence) 'Idempotente Migration änderte aktuelle Dateien erneut.'
  }

  Invoke-Phase5Test -Name 'Unvollständige Migration erzeugt private Entwürfe und lässt Originale unverändert' -Body {
    $fixture = New-Phase5Fixture -Name 'incomplete' -Incomplete
    $before = (Get-FileHash -LiteralPath $fixture.Matrix -Algorithm SHA256).Hash
    $result = Invoke-Migration -Work $fixture.Work -Apply
    Assert-Phase5 ($result.ExitCode -eq 1) "Unvollständige Migration wurde nicht abgelehnt: $($result.Output -join ' | ')"
    Assert-Phase5 ((Get-FileHash -LiteralPath $fixture.Matrix -Algorithm SHA256).Hash -eq $before) 'Unvollständige Migration veränderte die Originalmatrix.'
    Assert-Phase5 (Test-Path -LiteralPath (Join-Path $fixture.Work 'Anforderungsmatrix--MIGRATION-ENTWURF.json') -PathType Leaf) 'Matrix-Migrationsentwurf fehlt.'
    Assert-Phase5 (Test-Path -LiteralPath (Join-Path $fixture.Work 'Evidenzindex--MIGRATION-ENTWURF.json') -PathType Leaf) 'Evidenzindex-Migrationsentwurf fehlt.'
  }

  Invoke-Phase5Test -Name 'Console-App-Roadmap ist eindeutig nicht operativ' -Body {
    $roadmap = Get-Content -LiteralPath (Join-Path $RepoRoot 'Console App.md') -Raw -Encoding UTF8
    Assert-Phase5 ($roadmap -match '(?i)Roadmap' -and $roadmap -match '(?i)nicht implementiert' -and $roadmap -match 'AGENTS\.md' -and $roadmap -match 'Tools/bewerbung\.ps1') 'Console App.md ist nicht eindeutig als Roadmap gekennzeichnet.'
  }
} finally {
  if (Test-Path -LiteralPath $testRoot -PathType Container) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}

Write-Host "Phase-5-Vertragstests: $passed bestanden, $failed fehlgeschlagen."
if ($failed -gt 0) { exit 1 }
exit 0
