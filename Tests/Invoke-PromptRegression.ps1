#requires -Version 7.6
#requires -PSEdition Core

[CmdletBinding()]
param(
  [ValidateSet('pr', 'vollstaendig')]
  [string]$Matrix = 'pr',
  [string]$BerichtPath,
  [string]$AgentId,
  [string]$TestNamePattern
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$toolsRoot = Join-Path $repoRoot 'Tools'
$modelPath = Join-Path $PSScriptRoot 'PromptRegression/models.json'
$scenarioPath = Join-Path $PSScriptRoot 'PromptRegression/scenarios.json'
$startedAtUtc = [DateTime]::UtcNow
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('bewerbungs-agent-prompt-' + [guid]::NewGuid().ToString('N'))
$results = New-Object System.Collections.Generic.List[object]
$failures = New-Object System.Collections.Generic.List[string]

Import-Module (Join-Path $toolsRoot 'Common/Platform.psm1') -Force

function Get-JsonFile {
  param([Parameter(Mandatory)][string]$Path)
  return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-CommandVersion {
  param([Parameter(Mandatory)][string]$Command)
  $probe = Invoke-NativeProcess -FilePath $Command -ArgumentList @('--version') -TimeoutSeconds 15 -MaxStdoutChars 4096 -MaxStderrChars 4096
  if ($probe.TimedOut -or $probe.ExitCode -ne 0) { throw "CLI '$Command' meldet keine gültige Version: $($probe.StandardError)" }
  return (($probe.StandardOutput + "`n" + $probe.StandardError).Trim())
}

function New-IsolatedEnvironment {
  param(
    [Parameter(Mandatory)][string]$CredentialVariable,
    [Parameter(Mandatory)][string]$HomePath
  )

  $environment = @{}
  foreach ($entry in [Environment]::GetEnvironmentVariables().GetEnumerator()) { $environment[[string]$entry.Key] = $null }
  foreach ($safeName in @('PATH', 'SystemRoot', 'WINDIR', 'ComSpec', 'PATHEXT', 'TEMP', 'TMP', 'PSModulePath', 'LANG', 'LC_ALL', 'CI')) {
    $safeValue = [Environment]::GetEnvironmentVariable($safeName)
    if (-not [string]::IsNullOrWhiteSpace($safeValue)) { $environment[$safeName] = $safeValue }
  }
  $credential = [Environment]::GetEnvironmentVariable($CredentialVariable)
  if ([string]::IsNullOrWhiteSpace($credential)) { throw "Credential fehlt: $CredentialVariable" }
  $environment[$CredentialVariable] = $credential
  $environment['HOME'] = $HomePath
  $environment['USERPROFILE'] = $HomePath
  $environment['XDG_CONFIG_HOME'] = Join-Path $HomePath '.config'
  $environment['XDG_DATA_HOME'] = Join-Path $HomePath '.local/share'
  $environment['CODEX_HOME'] = Join-Path $HomePath '.codex'
  $environment['OPENCODE_CONFIG_DIR'] = Join-Path $HomePath '.config/opencode'
  New-Item -Path $environment['XDG_CONFIG_HOME'], $environment['XDG_DATA_HOME'], $environment['CODEX_HOME'], $environment['OPENCODE_CONFIG_DIR'] -ItemType Directory -Force | Out-Null
  return $environment
}

function Copy-PublicRepository {
  param([Parameter(Mandatory)][string]$Destination)

  New-Item -Path $Destination -ItemType Directory -Force | Out-Null
  $excludedRoots = @('.git', 'Private', '.agents', '.codex')
  foreach ($item in Get-ChildItem -LiteralPath $repoRoot -Force -Recurse) {
    $relative = $item.FullName.Substring($repoRoot.Length).TrimStart('\', '/')
    if ([string]::IsNullOrWhiteSpace($relative)) { continue }
    $segments = $relative -split '[\\/]'
    if ($segments | Where-Object { $_ -in $excludedRoots }) { continue }
    if ($item.Name -eq 'test-fast.json') { continue }
    $target = Join-Path $Destination $relative
    if ($item.PSIsContainer) { New-Item -Path $target -ItemType Directory -Force | Out-Null }
    elseif ($item.LinkType -eq $null) {
      New-Item -Path (Split-Path -Path $target -Parent) -ItemType Directory -Force | Out-Null
      Copy-Item -LiteralPath $item.FullName -Destination $target -Force
    }
  }
  & git -C $Destination init --quiet | Out-Null
  return $Destination
}

function Initialize-SyntheticFixture {
  param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$FixtureId)
  $data = Join-Path $Root 'Private/Daten'
  $work = Join-Path $Root 'Private/Bewerbungen/Synthetische-Firma/_Arbeitsdateien/2026-08-19--Synthetische-Rolle'
  $candidate = Join-Path $Root 'Private/Bewerbungen/Synthetische-Firma/2026-08-19--Synthetische-Rolle'
  $job = Join-Path $work 'Stellenbeschreibung.md'
  New-Item -Path $data, $work, $candidate -ItemType Directory -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $data '01_PERSOENLICHE_DATEN.md') -Encoding UTF8 -Value @"
# Persönliche Daten
- Vollständiger Name: Synthetische Person
- Vorname: Synthetische
- Nachname: Person
- Dateiname-Name: SYNTHETISCHE.PERSON
- Adresse: Testweg 1, 12345 Beispielstadt
- Telefon: +49 000 000000
- E-Mail: synthetische.person@example.invalid
- Verfügbarkeit: nach Vereinbarung
- Frühester Eintrittstermin: nach Vereinbarung
- Gewünschte Stellenart: Vollzeit
- Gewünschtes Arbeitsmodell: hybrid
- Gewünschte Region: Deutschland
- Wunschgehalt verwenden: nein
- Wunschgehalt manuell: nicht angegeben
- Gehaltsmodell: Jahresbrutto
"@
  Set-Content -LiteralPath (Join-Path $data '02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md') -Encoding UTF8 -Value @"
# Bewerberprofil
## Synthetische Belege
- Beruflich belegte Dokumentation und strukturierte Kommunikation
- Weiterbildung mit nachvollziehbarer Praxis
- Eigene Projektpraxis und ehrliche Transfergrundlage
"@
  Set-Content -LiteralPath $job -Encoding UTF8 -Value @"
# Synthetische Stelle: $FixtureId
- Fiktive Anforderungen, Dokumentation und verlässliche Zusammenarbeit
- Konkrete Aufgaben mit nachvollziehbarem eigenem Beitrag
"@
  $auftragObject = [ordered]@{
    schemaVersion = 5
    firma = 'Synthetische Firma'
    firmaSlug = 'Synthetische-Firma'
    rolle = 'Synthetische Rolle'
    rolleSlug = 'Synthetische-Rolle'
    datum = '2026-08-19'
    dokumentmodus = 'individuelle_auswahl'
    dokumentumfang = [ordered]@{ lebenslauf = 'individuell'; anschreiben = $true; emailNachricht = $true }
    bewerbungsentscheidung = 'bewerben'
    zielOrdner = $candidate
    arbeitsOrdner = $work
    kandidatOrdner = $candidate
    seitenstrategie = 'eine_seite'
  }
  $auftragPath = Join-Path $work 'Bewerbungsauftrag.json'
  Set-Content -LiteralPath $auftragPath -Encoding UTF8 -Value ($auftragObject | ConvertTo-Json -Depth 8)
  $matrixObject = [ordered]@{
    schemaVersion = 5
    requirements = @([ordered]@{ id = 'muss-1'; anforderung = 'Dokumentation'; typ = 'muss'; status = 'erfuellt'; belegart = 'ÜBERTRAGBAR'; beleg = 'Synthetische Projekterfahrung'; behandlung = 'Lebenslauf, Anschreiben und Transferbrücke'; kategorie = 'fachlich'; gewichtung = 'hoch'; stellenFundstellen = @('stelle-profil'); belegRefIds = @('profil-projekt') })
    stellenanzeigeAbdeckung = [ordered]@{ sourceSha256 = (Get-FileHash -LiteralPath $job -Algorithm SHA256).Hash; fundstellen = @([ordered]@{ id = 'stelle-profil'; zeileVon = 2; zeileBis = 2; text = '- Fiktive Anforderungen, Dokumentation und verlässliche Zusammenarbeit'; klassifikation = 'anforderung'; anforderungIds = @('muss-1') }) }
    recruiterStrategie = [ordered]@{ kernbotschaft = 'Belegte und ehrliche Transferstrategie'; profilSubstanz = 'ausreichend'; profilSubstanzBegruendung = 'Synthetische Belege sind vorhanden.'; prioritaetsAnforderungen = @('muss-1'); profilHighlights = @([ordered]@{ id = 'highlight-projekt'; anforderungIds = @('muss-1'); belegart = 'PROJEKTPRAXIS'; relevanz = 'hoch'; zielDokument = 'lebenslauf'; platzierung = 'seite_1'; sichtbareAnker = @('Synthetische Person') }); transferbruecken = @(); auslassungen = @([ordered]@{ thema = 'Verfügbarkeit'; begruendung = 'Logistikangabe'; anforderungId = ''; belegRefIds = @('dialog-verfuegbarkeit') }) }
    externeQuellen = @()
    anschreibenStrategie = [ordered]@{ status = 'ausstehend'; argumente = @(); abweichungBegruendung = '' }
  }
  Set-Content -LiteralPath (Join-Path $work 'Anforderungsmatrix.json') -Encoding UTF8 -Value ($matrixObject | ConvertTo-Json -Depth 12)
  $evidenceObject = [ordered]@{
    schemaVersion = 1
    profilSha256 = (Get-FileHash -LiteralPath (Join-Path $data '02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md') -Algorithm SHA256).Hash
    auftragSha256 = (Get-FileHash -LiteralPath $auftragPath -Algorithm SHA256).Hash
    belege = @([ordered]@{ id = 'profil-projekt'; quelle = 'profil'; zeileVon = 3; zeileBis = 3; text = 'Eigene Projektpraxis und ehrliche Transfergrundlage'; belegart = 'PROJEKTPRAXIS' }, [ordered]@{ id = 'dialog-verfuegbarkeit'; quelle = 'auftrag_angabe'; angabeId = 'dialog-verfuegbarkeit'; text = 'Verfügbar ab nach Vereinbarung'; belegart = 'ÜBERTRAGBAR' })
  }
  Set-Content -LiteralPath (Join-Path $work 'Evidenzindex.json') -Encoding UTF8 -Value ($evidenceObject | ConvertTo-Json -Depth 8)
}

function Get-InvocationArguments {
  param([Parameter(Mandatory)][object]$Model, [Parameter(Mandatory)][string]$Prompt)
  $arguments = @([string[]]$Model.arguments)
  if ($Model.agent -eq 'gemini') {
    $promptIndex = [Array]::IndexOf($arguments, '--prompt')
    if ($promptIndex -ge 0 -and $promptIndex + 1 -lt $arguments.Count -and [string]::IsNullOrEmpty($arguments[$promptIndex + 1])) {
      $arguments[$promptIndex + 1] = $Prompt
      return $arguments
    }
  }
  return @($arguments + $Prompt)
}

function Test-ScenarioOutput {
  param([Parameter(Mandatory)][object]$Scenario, [Parameter(Mandatory)][string]$Output)
  foreach ($pattern in @($Scenario.requiredPatterns)) {
    if ($Output -notmatch [regex]::Escape([string]$pattern)) { return "Pflichtsignal fehlt: $pattern" }
  }
  foreach ($pattern in @($Scenario.forbiddenPatterns)) {
    if ($Output -match [regex]::Escape([string]$pattern)) { return "Verbotenes Signal gefunden: $pattern" }
  }
  return $null
}

function Test-AllowedMutation {
  param([Parameter(Mandatory)][string[]]$Changes, [Parameter(Mandatory)][string[]]$AllowedPatterns)
  foreach ($change in $Changes) {
    $relative = ([string]$change -replace '^[ MADRCU?!]{1,3}\s+', '').Trim().Replace('\', '/')
    if ([string]::IsNullOrWhiteSpace($relative)) { continue }
    $allowed = $false
    foreach ($pattern in $AllowedPatterns) {
      $regex = '^' + [regex]::Escape([string]$pattern).Replace('\*\*', '.*').Replace('\*', '[^/]*') + '$'
      if ($relative -match $regex) { $allowed = $true; break }
    }
    if (-not $allowed) { return "Nicht erlaubte Dateimutation: $relative" }
  }
  return $null
}

function Test-ScenarioArtifacts {
  param([Parameter(Mandatory)][object]$Scenario, [Parameter(Mandatory)][string]$ScenarioRoot)
  if ([string]$Scenario.id -notlike 'rollenstrategie-*') { return $null }
  $expected = @(
    'Private/Bewerbungen/Synthetische-Firma/_Arbeitsdateien/2026-08-19--Synthetische-Rolle/Bewerbungsauftrag.json',
    'Private/Bewerbungen/Synthetische-Firma/_Arbeitsdateien/2026-08-19--Synthetische-Rolle/Anforderungsmatrix.json',
    'Private/Bewerbungen/Synthetische-Firma/_Arbeitsdateien/2026-08-19--Synthetische-Rolle/Evidenzindex.json'
  )
  foreach ($relative in $expected) {
    if (-not (Test-Path -LiteralPath (Join-Path $ScenarioRoot $relative) -PathType Leaf)) { return "Erwartetes Fixture-Artefakt fehlt: $relative" }
  }
  return $null
}

try {
  $modelCatalog = Get-JsonFile -Path $modelPath
  $scenarioCatalog = Get-JsonFile -Path $scenarioPath
  $models = @($modelCatalog.models | Where-Object { $_.tier -eq 'pr' -or $Matrix -eq 'vollstaendig' })
  if (-not [string]::IsNullOrWhiteSpace($AgentId)) { $models = @($models | Where-Object { $_.id -eq $AgentId }) }
  if ($models.Count -eq 0) { throw 'Keine Prompt-Regression ist für die gewählte Matrix konfiguriert.' }
  $scenarios = @($scenarioCatalog.scenarios | Where-Object { $_.tier -eq 'pr' -or $Matrix -eq 'vollstaendig' })
  if (-not [string]::IsNullOrWhiteSpace($TestNamePattern)) { $scenarios = @($scenarios | Where-Object { [string]$_.id -match $TestNamePattern }) }
  if ($scenarios.Count -eq 0) { throw "Kein Prompt-Szenario entspricht dem Muster: $TestNamePattern" }

  foreach ($model in $models) {
    $commandInfo = Get-Command -Name ([string]$model.command) -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $commandInfo) { throw "Agenten-CLI fehlt: $($model.command)" }
    $versionText = Get-CommandVersion -Command $commandInfo.Source
    if ($versionText -notmatch [regex]::Escape([string]$model.cliVersion)) { throw "CLI-Version für $($model.id) weicht ab. Erwartet $($model.cliVersion), erhalten: $versionText" }

    foreach ($scenario in $scenarios) {
      $scenarioRoot = Join-Path $tempRoot ("$($model.id)-$($scenario.id)")
      Copy-PublicRepository -Destination $scenarioRoot | Out-Null
      if ($null -ne $scenario.fixture -and -not [string]::IsNullOrWhiteSpace([string]$scenario.fixture)) { Initialize-SyntheticFixture -Root $scenarioRoot -FixtureId ([string]$scenario.fixture) }
      Add-Content -LiteralPath (Join-Path $scenarioRoot '.git/info/exclude') -Encoding UTF8 -Value "`n.agent-home/"
      $sentinel = Join-Path $scenarioRoot 'PRIVATE_SENTINEL.txt'
      Set-Content -LiteralPath $sentinel -Encoding UTF8 -Value 'PRIVATE_SENTINEL'
      & git -C $scenarioRoot add -A -- .
      $agentHome = Join-Path $scenarioRoot '.agent-home'
      $environment = New-IsolatedEnvironment -CredentialVariable ([string]$model.credentialVariable) -HomePath $agentHome
      $prompt = [string]$scenario.prompt
      $arguments = Get-InvocationArguments -Model $model -Prompt $prompt
      $process = $null
      $combinedOutput = ''
      $attempt = 0
      do {
        $attempt++
        $process = Invoke-NativeProcess -FilePath $commandInfo.Source -ArgumentList $arguments -WorkingDirectory $scenarioRoot -Environment $environment -TimeoutSeconds ([int]$modelCatalog.defaultTimeoutSeconds) -MaxStdoutChars 262144 -MaxStderrChars 16384
        $combinedOutput = [string]$process.StandardOutput + "`n" + [string]$process.StandardError
        $transient = $combinedOutput -match '(?i)(rate.?limit|quota|temporar|timeout|transport|connection reset|503|429)'
        if ($process.TimedOut -or -not $transient -or $attempt -ge 3) { break }
        Start-Sleep -Seconds ([int](2 * $attempt))
      } while ($true)
      $error = $null
      if ($process.TimedOut) { $error = 'Timeout' }
      elseif ($process.ExitCode -ne 0) { $error = "Exitcode $($process.ExitCode)" }
      else { $error = Test-ScenarioOutput -Scenario $scenario -Output $combinedOutput }
      if ($null -eq $error) { $error = Test-ScenarioArtifacts -Scenario $scenario -ScenarioRoot $scenarioRoot }
      $changes = @((git -C $scenarioRoot status --short 2>$null))
      if ($null -eq $error -and @($scenario.allowedFileChanges).Count -eq 0 -and $changes.Count -gt 0) { $error = 'Szenario sollte keine Dateimutationen erzeugen.' }
      if ($null -eq $error -and @($scenario.allowedFileChanges).Count -gt 0) { $error = Test-AllowedMutation -Changes $changes -AllowedPatterns @($scenario.allowedFileChanges) }
      $actualModel = $null
      $modelMatch = [regex]::Match($combinedOutput, '"model"\s*:\s*"([^"]+)"')
      if ($modelMatch.Success) { $actualModel = $modelMatch.Groups[1].Value; if ($actualModel -ne [string]$model.model) { $error = "Unerwartete Modellweiterleitung: $actualModel statt $($model.model)" } }
      $errorClass = if ($null -eq $error) { $null } elseif ($error -match '(?i)timeout') { 'infrastructure_timeout' } elseif ($error -match '(?i)credential|secret|PRIVATE|Private') { 'security_or_configuration' } elseif ($error -match '(?i)mutation|Modellweiterleitung') { 'contract_violation' } elseif ($error -match '(?i)exitcode') { 'agent_runtime' } else { 'scenario_assertion' }
      $status = if ($null -eq $error) { 'bestanden' } else { 'fehlgeschlagen' }
      $result = [ordered]@{
        modelId = [string]$model.id
        agent = [string]$model.agent
        provider = [string]$model.provider
        credentialVariable = [string]$model.credentialVariable
        model = [string]$model.model
        requestedModel = [string]$model.model
        actualModel = $actualModel
        cliPackage = [string]$model.cliPackage
        cliVersion = [string]$model.cliVersion
        tokenAvailability = 'not_provided'
        tokenValues = $null
        scenario = [string]$scenario.id
        status = $status
        errorClass = $errorClass
        error = $error
        exitCode = $process.ExitCode
        timedOut = [bool]$process.TimedOut
        durationMs = $process.DurationMs
        attempts = $attempt
        filesChanged = $changes
      }
      $results.Add($result) | Out-Null
      if ($null -ne $error) { $failures.Add("$($model.id)/$($scenario.id): $error") | Out-Null }
    }
  }
} catch {
  $failures.Add($_.Exception.Message) | Out-Null
} finally {
  if (Test-Path -LiteralPath $tempRoot -PathType Container) {
    Get-ChildItem -LiteralPath $tempRoot -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { $_.IsReadOnly = $false }
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}

$report = [ordered]@{
  schemaVersion = 1
  suite = "prompt-$Matrix"
  matrix = $Matrix
  testNamePattern = $TestNamePattern
  startedAtUtc = $startedAtUtc.ToString('o')
  endedAtUtc = [DateTime]::UtcNow.ToString('o')
  durationMs = [int](([DateTime]::UtcNow - $startedAtUtc).TotalMilliseconds)
  runtime = [ordered]@{ os = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription; architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString(); powershell = $PSVersionTable.PSVersion.ToString() }
  status = if ($failures.Count -eq 0) { 'bestanden' } else { 'fehlgeschlagen' }
  results = @($results.ToArray())
  failures = @($failures.ToArray())
}
if (-not [string]::IsNullOrWhiteSpace($BerichtPath)) {
  $reportFullPath = if ([System.IO.Path]::IsPathRooted($BerichtPath)) { [System.IO.Path]::GetFullPath($BerichtPath) } else { [System.IO.Path]::GetFullPath((Join-Path $repoRoot $BerichtPath)) }
  New-Item -Path (Split-Path -Path $reportFullPath -Parent) -ItemType Directory -Force | Out-Null
  Set-Content -LiteralPath $reportFullPath -Encoding UTF8 -Value ($report | ConvertTo-Json -Depth 8)
  Write-Host "Prompt-Regressionsbericht: $reportFullPath"
}
Write-Host "Prompt-Regressionssuite ($Matrix): $($results.Count) bestanden/ausgeführt, $($failures.Count) fehlgeschlagen."
if ($failures.Count -gt 0) { $failures | ForEach-Object { Write-Host "- $_" -ForegroundColor Red }; exit 1 }
exit 0
