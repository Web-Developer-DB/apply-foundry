[CmdletBinding()]
param(
  [switch]$MitBrowser
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$toolsRoot = Join-Path -Path $repoRoot -ChildPath "Tools"
$powerShellExe = (Get-Process -Id $PID).Path
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("bewerbungs-agent-tests-" + [guid]::NewGuid().ToString("N"))
$passed = New-Object System.Collections.Generic.List[string]
$failed = New-Object System.Collections.Generic.List[string]

function Invoke-ChildScript {
  param(
    [string]$ScriptPath,
    [string[]]$Arguments
  )

  if ((Split-Path -Path $ScriptPath -Leaf) -eq "Neue-Bewerbung.ps1" -and ($Arguments -notcontains "-StammdatenpruefungUeberspringen")) {
    $Arguments = @($Arguments + "-StammdatenpruefungUeberspringen")
  }
  $output = & $powerShellExe -NoProfile -File $ScriptPath @Arguments 2>&1
  return [pscustomobject]@{
    ExitCode = $LASTEXITCODE
    Output = @($output)
  }
}

function Assert-True {
  param(
    [bool]$Condition,
    [string]$Message
  )

  if (-not $Condition) {
    throw $Message
  }
}

function Invoke-Test {
  param(
    [string]$Name,
    [scriptblock]$Body
  )

  try {
    & $Body
    $passed.Add($Name) | Out-Null
    Write-Host "[OK] $Name" -ForegroundColor Green
  } catch {
    $failed.Add("${Name}: $($_.Exception.Message)") | Out-Null
    Write-Host "[FEHLER] ${Name}: $($_.Exception.Message)" -ForegroundColor Red
  }
}

function New-ValidApplicationFixture {
  param(
    [string]$Root,
    [string]$Company = "Audit-Firma",
    [string]$Role = "2026-07-14--Audit-Rolle"
  )

  $folder = Join-Path -Path $Root -ChildPath "Private/Bewerbungen/$Company/$Role"
  New-Item -Path $folder -ItemType Directory -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $folder "Stellenbeschreibung.md") -Encoding UTF8 -Value "Fiktive Teststelle"
  Set-Content -LiteralPath (Join-Path $folder "Analyse.md") -Encoding UTF8 -Value "Fiktive Analyse"
  Set-Content -LiteralPath (Join-Path $folder "Qualitaetscheck.md") -Encoding UTF8 -Value "Fiktiver Qualitätscheck"
  Set-Content -LiteralPath (Join-Path $folder "Druck-Hinweis.md") -Encoding UTF8 -Value "Fiktiver Druckhinweis"
  Set-Content -LiteralPath (Join-Path $folder "Email-Nachricht--Audit-Firma.md") -Encoding UTF8 -Value @"
Betreff: Bewerbung als Audit-Rolle - Test Person

Sehr geehrte Damen und Herren,

anbei sende ich Ihnen meine Bewerbungsunterlagen.

Mit freundlichen Grüßen
Test Person
"@

  $html = @"
<!doctype html>
<html lang="de">
<head>
  <meta charset="utf-8">
  <style>
    @page { size: A4; margin: 0; }
    * { box-sizing: border-box; }
    html, body { margin: 0; padding: 0; }
    .page { width: 210mm; height: 297mm; margin: 0; overflow: hidden; background: #fff; }
  </style>
</head>
<body><main class="page"><h1>Fiktiver Testinhalt</h1></main></body>
</html>
"@
  Set-Content -LiteralPath (Join-Path $folder "Lebenslauf - TEST.PERSON.html") -Encoding UTF8 -Value $html
  Set-Content -LiteralPath (Join-Path $folder "Anschreiben - TEST.PERSON.html") -Encoding UTF8 -Value $html
  return $folder
}

function New-ValidPrivateDataFixture {
  param([string]$Root)

  $dataDir = Join-Path -Path $Root -ChildPath "Private/Daten"
  New-Item -Path $dataDir -ItemType Directory -Force | Out-Null
  $personal = Join-Path -Path $dataDir -ChildPath "01_PERSOENLICHE_DATEN.md"
  $profile = Join-Path -Path $dataDir -ChildPath "02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md"
  Set-Content -LiteralPath $personal -Encoding UTF8 -Value @"
# Persönliche Daten
- Vollständiger Name: Test Person
- Vorname: Test
- Nachname: Person
- Dateiname-Name: TEST.PERSON
- Adresse: Teststraße 1, 12345 Teststadt
- Telefon: +49 151 00000000
- E-Mail: test.person@example.com
- Verfügbarkeit: nach Vereinbarung
- Frühester Eintrittstermin: nach Vereinbarung
- Gewünschte Stellenart: Vollzeit
- Gewünschter Stundenumfang: 40 Std./Woche
- Gewünschtes Arbeitsmodell: hybrid
- Gewünschte Region: Deutschland
- Maximale Pendeldistanz: 60 Minuten
- Reisebereitschaft: gelegentlich
- Schicht- oder Wochenendbereitschaft: nein
- Befristung: unbefristet bevorzugt
- Umzugsbereitschaft: nein
- Wunschgehalt verwenden: nein
- Wunschgehalt manuell: nicht angegeben
- Gehaltsmodell: Jahresbrutto
- Gehaltsregion: Deutschland
- Gehaltslogik: manuelle Angabe bevorzugen
"@
  Set-Content -LiteralPath $profile -Encoding UTF8 -Value @"
# Bewerberprofil

## Berufserfahrung

### Testrolle
Test Arbeitgeber, 01/2020 - 12/2020

## Weiterbildung

### Testweiterbildung
Test Institut, 02/2021 - 03/2022
"@
  return [pscustomobject]@{ Personal = $personal; Profile = $profile }
}

function New-ValidContentFixture {
  param([string]$Root, [switch]$MissingSecondPeriod)

  $folder = New-ValidApplicationFixture -Root $Root
  $data = New-ValidPrivateDataFixture -Root $Root
  $periodText = if ($MissingSecondPeriod) { "01/2020 - 12/2020" } else { "01/2020 - 12/2020 02/2021 - 03/2022" }
  foreach ($htmlPath in @(
    (Join-Path $folder "Lebenslauf - TEST.PERSON.html"),
    (Join-Path $folder "Anschreiben - TEST.PERSON.html")
  )) {
    $text = Get-Content -LiteralPath $htmlPath -Raw -Encoding UTF8
    $replacement = if ($htmlPath -like "*Lebenslauf*") {
      "<h1>Test Person</h1><p>Audit-Rolle Vollzeit nach Vereinbarung $periodText</p>"
    } else {
      "<h1>Test Person</h1><p>Audit Firma Audit-Rolle Vollzeit nach Vereinbarung</p>"
    }
    $text = $text.Replace('<h1>Fiktiver Testinhalt</h1>', $replacement)
    Set-Content -LiteralPath $htmlPath -Value $text -Encoding UTF8
  }
  $emailPath = Join-Path $folder "Email-Nachricht--Audit-Firma.md"
  $email = (Get-Content -LiteralPath $emailPath -Raw -Encoding UTF8).Replace("Test Person", "Test Person")
  Set-Content -LiteralPath $emailPath -Value $email -Encoding UTF8

  $work = Join-Path -Path $Root -ChildPath "Private/Bewerbungen/Audit-Firma/_Arbeitsdateien/2026-07-14--Audit-Rolle"
  New-Item -Path $work -ItemType Directory -Force | Out-Null
  $auftragPath = Join-Path $work "Bewerbungsauftrag.json"
  $matrixPath = Join-Path $work "Anforderungsmatrix.json"
  $target = Join-Path -Path $Root -ChildPath "Private/Bewerbungen/Audit-Firma/2026-07-14--Audit-Rolle"
  $auftrag = [ordered]@{
    schemaVersion = 1
    firma = "Audit Firma"
    firmaSlug = "Audit-Firma"
    rolle = "Audit-Rolle"
    rolleSlug = "Audit-Rolle"
    datum = "2026-07-14"
    bewerberDateiname = "TEST.PERSON"
    zielOrdner = $target
    arbeitsOrdner = $work
    kandidatOrdner = $folder
    seitenstrategie = "eine_seite"
  }
  Set-Content -LiteralPath $auftragPath -Encoding UTF8 -Value ($auftrag | ConvertTo-Json -Depth 5)
  $matrix = [ordered]@{
    schemaVersion = 1
    requirements = @(
      [ordered]@{
        id = "muss-1"
        anforderung = "Audit-Rolle"
        typ = "muss"
        status = "erfuellt"
        belegart = "WEITERBILDUNG"
        beleg = "Testweiterbildung"
        behandlung = "Lebenslauf und Anschreiben"
      }
    )
  }
  Set-Content -LiteralPath $matrixPath -Encoding UTF8 -Value ($matrix | ConvertTo-Json -Depth 6)
  return [pscustomobject]@{
    Folder = $folder
    Work = $work
    Personal = $data.Personal
    Profile = $data.Profile
    Auftrag = $auftragPath
    Matrix = $matrixPath
  }
}

function Convert-ToSchema2Fixture {
  param(
    [object]$Fixture,
    [ValidateSet("vollstaendig", "recruiter_kompakt")]
    [string]$SchoolMode = "vollstaendig",
    [ValidateSet("alle", "rollenrelevant", "keine")]
    [string]$ProfileLinksMode = "keine",
    [string[]]$ProfileLinksSelection = @(),
    [ValidateSet("bewerben", "nicht_bewerben")]
    [string]$Decision = "bewerben"
  )

  $auftrag = Get-Content -LiteralPath $Fixture.Auftrag -Raw -Encoding UTF8 | ConvertFrom-Json
  $auftrag.schemaVersion = 2
  $auftrag | Add-Member -NotePropertyName bewerbungslogistik -NotePropertyValue ([ordered]@{
    verfuegbarkeit = "nach Vereinbarung"
    fruehesterEintrittstermin = "nach Vereinbarung"
    stellenart = "Vollzeit"
    stundenumfang = "40 Std./Woche"
    arbeitsmodell = "hybrid"
    region = "Deutschland"
    maximalePendeldistanz = "60 Minuten"
    reisebereitschaft = "gelegentlich"
    schichtOderWochenendbereitschaft = "nein"
    befristung = "unbefristet bevorzugt"
    umzugsbereitschaft = "nein"
    wunschgehaltVerwenden = "nein"
    wunschgehaltManuell = "nicht angegeben"
    gehaltsmodell = "Jahresbrutto"
    gehaltsregion = "Deutschland"
    gehaltslogik = "manuelle Angabe bevorzugen"
  }) -Force
  $auftrag | Add-Member -NotePropertyName bewerbungsentscheidung -NotePropertyValue $Decision -Force
  $auftrag | Add-Member -NotePropertyName darstellungsoptionen -NotePropertyValue ([ordered]@{
    schulbildungsmodus = $SchoolMode
    profillinksModus = $ProfileLinksMode
    profillinksAuswahl = @($ProfileLinksSelection)
  }) -Force
  Set-Content -LiteralPath $Fixture.Auftrag -Encoding UTF8 -Value ($auftrag | ConvertTo-Json -Depth 8)

  $matrix = Get-Content -LiteralPath $Fixture.Matrix -Raw -Encoding UTF8 | ConvertFrom-Json
  $matrix.schemaVersion = 2
  foreach ($requirement in $matrix.requirements) {
    $requirement | Add-Member -NotePropertyName kategorie -NotePropertyValue "fachlich" -Force
    $requirement | Add-Member -NotePropertyName gewichtung -NotePropertyValue "hoch" -Force
  }
  Set-Content -LiteralPath $Fixture.Matrix -Encoding UTF8 -Value ($matrix | ConvertTo-Json -Depth 8)
  return $Fixture
}

function New-StagedFinalizationFixture {
  param([string]$Root)

  $fixture = New-ValidContentFixture -Root $Root
  $candidate = Join-Path -Path $fixture.Work -ChildPath "Kandidat"
  New-Item -Path $candidate -ItemType Directory -Force | Out-Null
  foreach ($file in Get-ChildItem -LiteralPath $fixture.Folder -File) {
    Move-Item -LiteralPath $file.FullName -Destination (Join-Path $candidate $file.Name)
  }
  Set-Content -LiteralPath (Join-Path $candidate "Anschreiben - TEST.PERSON.pdf") -Encoding ASCII -Value "%PDF-1.4 test-letter"
  Set-Content -LiteralPath (Join-Path $candidate "Lebenslauf - TEST.PERSON.pdf") -Encoding ASCII -Value "%PDF-1.4 test-cv"
  $layoutDir = Join-Path -Path $fixture.Work -ChildPath "Layoutcheck"
  New-Item -Path $layoutDir -ItemType Directory -Force | Out-Null
  [System.IO.File]::WriteAllBytes((Join-Path $layoutDir "Anschreiben---TEST.PERSON--chrome.png"), [byte[]](1..32))
  [System.IO.File]::WriteAllBytes((Join-Path $layoutDir "Lebenslauf---TEST.PERSON--chrome.png"), [byte[]](33..64))

  $auftrag = Get-Content -LiteralPath $fixture.Auftrag -Raw -Encoding UTF8 | ConvertFrom-Json
  $auftrag.kandidatOrdner = $candidate
  Set-Content -LiteralPath $fixture.Auftrag -Encoding UTF8 -Value ($auftrag | ConvertTo-Json -Depth 6)

  $record = {
    param([System.IO.FileInfo]$File)
    return [ordered]@{
      name = $File.Name
      path = $File.FullName
      bytes = $File.Length
      sha256 = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash
    }
  }
  $report = [ordered]@{
    schemaVersion = 1
    status = "bereit_zur_sichtpruefung"
    preparedAtUtc = [datetime]::UtcNow.ToString("o")
    workFolder = $fixture.Work
    candidateFolder = $candidate
    targetFolder = $fixture.Folder
    layoutReport = (Join-Path $layoutDir "Layoutcheck-Bericht.json")
    pdfReport = (Join-Path $fixture.Work "PDF-Export/PDF-Export-Bericht.json")
    layoutWarnings = @()
    sourceInputs = [ordered]@{
      stammdaten = & $record (Get-Item -LiteralPath $fixture.Personal)
      profil = & $record (Get-Item -LiteralPath $fixture.Profile)
      bewerbungsauftrag = & $record (Get-Item -LiteralPath $fixture.Auftrag)
      anforderungsmatrix = & $record (Get-Item -LiteralPath $fixture.Matrix)
    }
    artifacts = [ordered]@{
      html = @(Get-ChildItem -LiteralPath $candidate -File -Filter "*.html" | Sort-Object Name | ForEach-Object { & $record $_ })
      pdf = @(Get-ChildItem -LiteralPath $candidate -File -Filter "*.pdf" | Sort-Object Name | ForEach-Object { & $record $_ })
      screenshots = @(Get-ChildItem -LiteralPath $layoutDir -File -Filter "*.png" | Sort-Object Name | ForEach-Object { & $record $_ })
      candidate = @(Get-ChildItem -LiteralPath $candidate -File | Sort-Object Name | ForEach-Object { & $record $_ })
    }
  }
  $finalReport = Join-Path $fixture.Work "Finalisierungsbericht.json"
  Set-Content -LiteralPath $finalReport -Encoding UTF8 -Value ($report | ConvertTo-Json -Depth 10)

  $fixture | Add-Member -NotePropertyName Candidate -NotePropertyValue $candidate
  $fixture | Add-Member -NotePropertyName FinalReport -NotePropertyValue $finalReport
  return $fixture
}

function Test-PngSignature {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return $false
  }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -lt 8) {
    return $false
  }
  $signature = @(137, 80, 78, 71, 13, 10, 26, 10)
  for ($index = 0; $index -lt $signature.Count; $index++) {
    if ($bytes[$index] -ne $signature[$index]) {
      return $false
    }
  }
  return $true
}

New-Item -Path $testRoot -ItemType Directory | Out-Null
try {
  Invoke-Test -Name "PowerShell-Dateien sind syntaktisch gültig" -Body {
    foreach ($file in Get-ChildItem -LiteralPath $toolsRoot -Filter "*.ps1" -File) {
      $tokens = $null
      $parseErrors = $null
      [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
      Assert-True -Condition ($parseErrors.Count -eq 0) -Message "$($file.Name) enthält Parserfehler."
    }
  }

  Invoke-Test -Name "Gültige Bewerbung besteht den statischen Prüfer" -Body {
    $folder = New-ValidApplicationFixture -Root (Join-Path $testRoot "valid")
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Pruefe-Bewerbung.ps1") -Arguments @("-Ordner", $folder)
    Assert-True -Condition ($result.ExitCode -eq 0) -Message "Gültige Fixture wurde abgelehnt: $($result.Output -join ' | ')"
  }

  Invoke-Test -Name "Stammdatenprüfer lehnt Platzhalter in Pflichtfeldern ab" -Body {
    $data = New-ValidPrivateDataFixture -Root (Join-Path $testRoot "invalid-personal-data")
    $text = Get-Content -LiteralPath $data.Personal -Raw -Encoding UTF8
    $text = $text.Replace("- Adresse: Teststraße 1, 12345 Teststadt", "- Adresse: [Adresse ergänzen]")
    Set-Content -LiteralPath $data.Personal -Value $text -Encoding UTF8
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Pruefe-Stammdaten.ps1") -Arguments @("-StammdatenPath", $data.Personal)
    Assert-True -Condition ($result.ExitCode -ne 0) -Message "Platzhalter im Pflichtfeld wurde akzeptiert."
  }

  Invoke-Test -Name "Stammdatenprüfer sperrt ungeklärte Kernlogistik im strikten Modus" -Body {
    $data = New-ValidPrivateDataFixture -Root (Join-Path $testRoot "unclear-logistics")
    $text = Get-Content -LiteralPath $data.Personal -Raw -Encoding UTF8
    $text = $text.Replace("- Gewünschte Stellenart: Vollzeit", "- Gewünschte Stellenart: [Vollzeit / Teilzeit]")
    Set-Content -LiteralPath $data.Personal -Value $text -Encoding UTF8
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Pruefe-Stammdaten.ps1") -Arguments @("-StammdatenPath", $data.Personal, "-UngeklaerteLogistikAlsFehler")
    Assert-True -Condition ($result.ExitCode -ne 0) -Message "Ungeklärte zentrale Bewerbungslogistik wurde im strikten Modus akzeptiert."
  }

  Invoke-Test -Name "Ordnerhelfer legt Schema-3-Auftrag mit Dokumentmodus und Logistik-Snapshot an" -Body {
    $root = Join-Path $testRoot "schema3-order"
    $data = New-ValidPrivateDataFixture -Root $root
    $applicationsRoot = Join-Path $root "Private/Bewerbungen"
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Neue-Bewerbung.ps1") -Arguments @(
      "-Firma", "Audit Firma",
      "-Rolle", "Audit Rolle",
      "-Datum", "2026-07-14",
      "-StammdatenPath", $data.Personal,
      "-ProfilPath", $data.Profile,
      "-BewerbungenRoot", $applicationsRoot
    )
    Assert-True -Condition ($result.ExitCode -eq 0) -Message "Ordnerhelfer schlug fehl: $($result.Output -join ' | ')"
    $auftragPath = Join-Path $applicationsRoot "Audit-Firma/_Arbeitsdateien/2026-07-14--Audit-Rolle/Bewerbungsauftrag.json"
    $auftrag = Get-Content -LiteralPath $auftragPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True -Condition ($auftrag.schemaVersion -eq 3) -Message "Bewerbungsauftrag verwendet nicht Schema 3."
    Assert-True -Condition ($auftrag.dokumentmodus -eq "vollbewerbung") -Message "Standard-Dokumentmodus ist nicht vollbewerbung."
    Assert-True -Condition ($auftrag.bewerbungslogistik.stellenart -eq "Vollzeit" -and $auftrag.bewerbungslogistik.arbeitsmodell -eq "hybrid") -Message "Logistik-Snapshot ist unvollständig."
    Assert-True -Condition ($auftrag.bewerbungsentscheidung -eq "noch_festzulegen") -Message "Initiale Bewerbungsentscheidung ist nicht offen markiert."
    Assert-True -Condition ($auftrag.quellnachweise.stammdatenSha256BeiAnlage -eq (Get-FileHash -LiteralPath $data.Personal -Algorithm SHA256).Hash) -Message "Stammdaten-Quellhash fehlt oder stimmt nicht."
  }

  Invoke-Test -Name "Ordnerhelfer übernimmt universellen Lebenslauf unverändert und erzeugt keinen CV-Entwurf" -Body {
    $root = Join-Path $testRoot "universal-order"
    $data = New-ValidPrivateDataFixture -Root $root
    $universalDir = Join-Path $root "Private/LebenslaufUniversal/Aktiv"
    New-Item -Path $universalDir -ItemType Directory -Force | Out-Null
    $universalPath = Join-Path $universalDir "Lebenslauf - TEST.PERSON.html"
    $universalHtml = @"
<!doctype html><html lang="de"><head><style>@page { size: A4; margin: 0; } .page { width: 210mm; height: 297mm; overflow: hidden; }</style></head><body><main class="page"><h1>Test Person</h1><p>Universeller Lebenslauf 01/2020 - 12/2020 02/2021 - 03/2022</p></main></body></html>
"@
    Set-Content -LiteralPath $universalPath -Encoding UTF8 -Value $universalHtml
    $applicationsRoot = Join-Path $root "Private/Bewerbungen"
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Neue-Bewerbung.ps1") -Arguments @(
      "-Firma", "Universal Firma", "-Rolle", "Universal Rolle", "-Datum", "2026-07-14",
      "-Dokumentmodus", "anschreiben_mit_universalem_lebenslauf", "-UniversalLebenslaufPath", $universalPath,
      "-StammdatenPath", $data.Personal, "-ProfilPath", $data.Profile, "-BewerbungenRoot", $applicationsRoot
    )
    Assert-True -Condition ($result.ExitCode -eq 0) -Message "Anschreiben-Modus schlug fehl: $($result.Output -join ' | ')"
    $work = Join-Path $applicationsRoot "Universal-Firma/_Arbeitsdateien/2026-07-14--Universal-Rolle"
    $candidatePath = Join-Path $work "Kandidat/Lebenslauf - TEST.PERSON.html"
    $auftrag = Get-Content -LiteralPath (Join-Path $work "Bewerbungsauftrag.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True -Condition ($auftrag.dokumentmodus -eq "anschreiben_mit_universalem_lebenslauf") -Message "Anschreiben-Modus fehlt im Auftrag."
    Assert-True -Condition ((Get-FileHash $candidatePath -Algorithm SHA256).Hash -eq (Get-FileHash $universalPath -Algorithm SHA256).Hash) -Message "Universalquelle wurde beim Übernehmen verändert."
    Assert-True -Condition (-not (Test-Path (Join-Path $work "Lebenslauf--Universal-Firma--ENTWURF.html"))) -Message "Im Anschreiben-Modus wurde fälschlich ein Lebenslaufentwurf erzeugt."
  }

  Invoke-Test -Name "Bewerbungsspezifische Logistik überschreibt ungeklärte globale Kernwerte" -Body {
    $fixture = Convert-ToSchema2Fixture -Fixture (New-ValidContentFixture -Root (Join-Path $testRoot "application-logistics"))
    $text = Get-Content -LiteralPath $fixture.Personal -Raw -Encoding UTF8
    $text = $text.Replace("- Gewünschte Stellenart: Vollzeit", "- Gewünschte Stellenart: [Vollzeit / Teilzeit]")
    $text = $text.Replace("- Gewünschtes Arbeitsmodell: hybrid", "- Gewünschtes Arbeitsmodell: [vor Ort / hybrid / remote]")
    $text = $text.Replace("- Wunschgehalt verwenden: nein", "- Wunschgehalt verwenden: [ja / nein]")
    $text = $text.Replace("- Gehaltslogik: manuelle Angabe bevorzugen", "- Gehaltslogik: [noch festlegen]")
    Set-Content -LiteralPath $fixture.Personal -Encoding UTF8 -Value $text
    $reportPath = Join-Path $fixture.Work "Stammdaten-Schema2.json"
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Pruefe-Stammdaten.ps1") -Arguments @("-StammdatenPath", $fixture.Personal, "-BewerbungsauftragPath", $fixture.Auftrag, "-UngeklaerteLogistikAlsFehler", "-BerichtPath", $reportPath)
    Assert-True -Condition ($result.ExitCode -eq 0) -Message "Bewerbungsspezifische Logistik wurde nicht priorisiert: $($result.Output -join ' | ')"
    $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True -Condition ($report.logisticsSource -eq "bewerbungsauftrag_mit_stammdaten_fallback") -Message "Logistikquelle wurde im Bericht nicht ausgewiesen."
  }

  Invoke-Test -Name "Inhaltsprüfer akzeptiert vollständigen Anforderungs- und Zeitraumabgleich" -Body {
    $fixture = New-ValidContentFixture -Root (Join-Path $testRoot "valid-content")
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Pruefe-Bewerbungsinhalt.ps1") -Arguments @("-Ordner", $fixture.Folder, "-StammdatenPath", $fixture.Personal, "-ProfilPath", $fixture.Profile, "-AuftragPath", $fixture.Auftrag, "-AnforderungsmatrixPath", $fixture.Matrix)
    Assert-True -Condition ($result.ExitCode -eq 0) -Message "Vollständiger Inhaltsabgleich wurde abgelehnt: $($result.Output -join ' | ')"
  }

  Invoke-Test -Name "Schema-2-Inhaltsprüfung bewertet Gewichtung und rollenbezogene Links" -Body {
    $fixture = New-ValidContentFixture -Root (Join-Path $testRoot "schema2-weighted-links")
    Add-Content -LiteralPath $fixture.Personal -Encoding UTF8 -Value "`n- GitHub: https://github.com/test-person`n- Portfolio: https://portfolio.example/test-person"
    $fixture = Convert-ToSchema2Fixture -Fixture $fixture -ProfileLinksMode "rollenrelevant" -ProfileLinksSelection @("GitHub")
    $cvPath = Join-Path $fixture.Folder "Lebenslauf - TEST.PERSON.html"
    $cv = (Get-Content -LiteralPath $cvPath -Raw -Encoding UTF8).Replace("</main>", "<p>https://github.com/test-person</p></main>")
    Set-Content -LiteralPath $cvPath -Encoding UTF8 -Value $cv
    $reportPath = Join-Path $fixture.Work "Inhalt-Schema2.json"
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Pruefe-Bewerbungsinhalt.ps1") -Arguments @("-Ordner", $fixture.Folder, "-StammdatenPath", $fixture.Personal, "-ProfilPath", $fixture.Profile, "-AuftragPath", $fixture.Auftrag, "-AnforderungsmatrixPath", $fixture.Matrix, "-BerichtPath", $reportPath)
    Assert-True -Condition ($result.ExitCode -eq 0) -Message "Schema-2-Inhaltsprüfung wurde abgelehnt: $($result.Output -join ' | ')"
    $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True -Condition ($report.fitAssessment.classification -eq "stark" -and $report.fitAssessment.scorePercent -eq 100) -Message "Gewichtete Eignungsbewertung ist unerwartet."
    Assert-True -Condition ($report.profileLinksMode -eq "rollenrelevant") -Message "Profillink-Modus fehlt im Bericht."
  }

  Invoke-Test -Name "Anschreiben-Modus verlangt Zielrolle nicht im unveränderten Universal-Lebenslauf" -Body {
    $fixture = Convert-ToSchema2Fixture -Fixture (New-ValidContentFixture -Root (Join-Path $testRoot "universal-content"))
    $cvPath = Join-Path $fixture.Folder "Lebenslauf - TEST.PERSON.html"
    $cv = (Get-Content -LiteralPath $cvPath -Raw -Encoding UTF8).Replace("Audit-Rolle", "Universeller Lebenslauf")
    Set-Content -LiteralPath $cvPath -Encoding UTF8 -Value $cv
    $auftrag = Get-Content -LiteralPath $fixture.Auftrag -Raw -Encoding UTF8 | ConvertFrom-Json
    $auftrag.schemaVersion = 3
    $auftrag | Add-Member -NotePropertyName dokumentmodus -NotePropertyValue "anschreiben_mit_universalem_lebenslauf" -Force
    $auftrag | Add-Member -NotePropertyName universalLebenslauf -NotePropertyValue ([ordered]@{
      sourceHtmlPath = $cvPath
      sourceHtmlSha256BeiAnlage = (Get-FileHash -LiteralPath $cvPath -Algorithm SHA256).Hash
      kandidatDatei = "Lebenslauf - TEST.PERSON.html"
    }) -Force
    Set-Content -LiteralPath $fixture.Auftrag -Encoding UTF8 -Value ($auftrag | ConvertTo-Json -Depth 8)
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Pruefe-Bewerbungsinhalt.ps1") -Arguments @("-Ordner", $fixture.Folder, "-StammdatenPath", $fixture.Personal, "-ProfilPath", $fixture.Profile, "-AuftragPath", $fixture.Auftrag, "-AnforderungsmatrixPath", $fixture.Matrix)
    Assert-True -Condition ($result.ExitCode -eq 0) -Message "Unveränderter Universal-Lebenslauf wurde abgelehnt: $($result.Output -join ' | ')"

    Add-Content -LiteralPath $cvPath -Encoding UTF8 -Value "<!-- stellenbezogen verändert -->"
    $tamperResult = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Pruefe-Bewerbungsinhalt.ps1") -Arguments @("-Ordner", $fixture.Folder, "-StammdatenPath", $fixture.Personal, "-ProfilPath", $fixture.Profile, "-AuftragPath", $fixture.Auftrag, "-AnforderungsmatrixPath", $fixture.Matrix)
    Assert-True -Condition ($tamperResult.ExitCode -ne 0) -Message "Veränderter Universal-Lebenslauf wurde im Anschreiben-Modus akzeptiert."
  }

  Invoke-Test -Name "Inhaltsprüfer lehnt abweichende manuelle Eignungskennzahl ab" -Body {
    $fixture = Convert-ToSchema2Fixture -Fixture (New-ValidContentFixture -Root (Join-Path $testRoot "fit-score-drift"))
    Set-Content -LiteralPath (Join-Path $fixture.Folder "Analyse.md") -Encoding UTF8 -Value "Eignung: 61 Prozent gewichtete Passung."
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Pruefe-Bewerbungsinhalt.ps1") -Arguments @("-Ordner", $fixture.Folder, "-StammdatenPath", $fixture.Personal, "-ProfilPath", $fixture.Profile, "-AuftragPath", $fixture.Auftrag, "-AnforderungsmatrixPath", $fixture.Matrix)
    Assert-True -Condition ($result.ExitCode -ne 0) -Message "Abweichende manuelle Eignungskennzahl wurde akzeptiert."
  }

  Invoke-Test -Name "Nicht ausgewählter Profillink wird im Lebenslauf abgelehnt" -Body {
    $fixture = New-ValidContentFixture -Root (Join-Path $testRoot "schema2-link-rejected")
    Add-Content -LiteralPath $fixture.Personal -Encoding UTF8 -Value "`n- GitHub: https://github.com/test-person`n- Portfolio: https://portfolio.example/test-person"
    $fixture = Convert-ToSchema2Fixture -Fixture $fixture -ProfileLinksMode "rollenrelevant" -ProfileLinksSelection @("GitHub")
    $cvPath = Join-Path $fixture.Folder "Lebenslauf - TEST.PERSON.html"
    $cv = (Get-Content -LiteralPath $cvPath -Raw -Encoding UTF8).Replace("</main>", "<p>https://github.com/test-person https://portfolio.example/test-person</p></main>")
    Set-Content -LiteralPath $cvPath -Encoding UTF8 -Value $cv
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Pruefe-Bewerbungsinhalt.ps1") -Arguments @("-Ordner", $fixture.Folder, "-StammdatenPath", $fixture.Personal, "-ProfilPath", $fixture.Profile, "-AuftragPath", $fixture.Auftrag, "-AnforderungsmatrixPath", $fixture.Matrix)
    Assert-True -Condition ($result.ExitCode -ne 0) -Message "Nicht ausgewählter Portfolio-Link wurde akzeptiert."
  }

  Invoke-Test -Name "Recruiter-kompakte Schulbildung erlaubt Abschluss ohne Schulzeiträume" -Body {
    $fixture = New-ValidContentFixture -Root (Join-Path $testRoot "compact-school")
    Add-Content -LiteralPath $fixture.Profile -Encoding UTF8 -Value "`n## Schulbildung`n`nFachhochschulreife, Testschule, 08/2000 - 06/2003"
    $fixture = Convert-ToSchema2Fixture -Fixture $fixture -SchoolMode "recruiter_kompakt"
    $cvPath = Join-Path $fixture.Folder "Lebenslauf - TEST.PERSON.html"
    $cv = (Get-Content -LiteralPath $cvPath -Raw -Encoding UTF8).Replace("</main>", "<p>Schulbildung: Fachhochschulreife</p></main>")
    Set-Content -LiteralPath $cvPath -Encoding UTF8 -Value $cv
    $reportPath = Join-Path $fixture.Work "Inhalt-Kompakte-Schule.json"
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Pruefe-Bewerbungsinhalt.ps1") -Arguments @("-Ordner", $fixture.Folder, "-StammdatenPath", $fixture.Personal, "-ProfilPath", $fixture.Profile, "-AuftragPath", $fixture.Auftrag, "-AnforderungsmatrixPath", $fixture.Matrix, "-BerichtPath", $reportPath)
    Assert-True -Condition ($result.ExitCode -eq 0) -Message "Kompakte Schulbildungsangabe wurde abgelehnt: $($result.Output -join ' | ')"
    $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True -Condition (@($report.compactedSchoolPeriods).Count -eq 1) -Message "Verdichteter Schulzeitraum wurde nicht im Bericht ausgewiesen."
  }

  Invoke-Test -Name "Inhaltsprüfer erkennt fehlenden formalen Zeitraum" -Body {
    $fixture = New-ValidContentFixture -Root (Join-Path $testRoot "missing-period") -MissingSecondPeriod
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Pruefe-Bewerbungsinhalt.ps1") -Arguments @("-Ordner", $fixture.Folder, "-StammdatenPath", $fixture.Personal, "-ProfilPath", $fixture.Profile, "-AuftragPath", $fixture.Auftrag, "-AnforderungsmatrixPath", $fixture.Matrix)
    Assert-True -Condition ($result.ExitCode -ne 0) -Message "Fehlender formaler Zeitraum wurde nicht erkannt."
  }

  Invoke-Test -Name "Inhaltsprüfer verlangt Behandlung für nicht erfüllte Muss-Anforderung" -Body {
    $fixture = New-ValidContentFixture -Root (Join-Path $testRoot "missing-requirement-treatment")
    $matrix = Get-Content -LiteralPath $fixture.Matrix -Raw -Encoding UTF8 | ConvertFrom-Json
    $matrix.requirements[0].status = "nicht_belegt"
    $matrix.requirements[0].behandlung = ""
    Set-Content -LiteralPath $fixture.Matrix -Encoding UTF8 -Value ($matrix | ConvertTo-Json -Depth 6)
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Pruefe-Bewerbungsinhalt.ps1") -Arguments @("-Ordner", $fixture.Folder, "-StammdatenPath", $fixture.Personal, "-ProfilPath", $fixture.Profile, "-AuftragPath", $fixture.Auftrag, "-AnforderungsmatrixPath", $fixture.Matrix)
    Assert-True -Condition ($result.ExitCode -ne 0) -Message "Nicht belegte Muss-Anforderung ohne Behandlung wurde akzeptiert."
  }

  Invoke-Test -Name "Schema-2-Matrix verlangt Kategorie und Gewichtung" -Body {
    $fixture = Convert-ToSchema2Fixture -Fixture (New-ValidContentFixture -Root (Join-Path $testRoot "missing-weight"))
    $matrix = Get-Content -LiteralPath $fixture.Matrix -Raw -Encoding UTF8 | ConvertFrom-Json
    $matrix.requirements[0].PSObject.Properties.Remove("gewichtung")
    $matrix.requirements[0].PSObject.Properties.Remove("kategorie")
    Set-Content -LiteralPath $fixture.Matrix -Encoding UTF8 -Value ($matrix | ConvertTo-Json -Depth 8)
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Pruefe-Bewerbungsinhalt.ps1") -Arguments @("-Ordner", $fixture.Folder, "-StammdatenPath", $fixture.Personal, "-ProfilPath", $fixture.Profile, "-AuftragPath", $fixture.Auftrag, "-AnforderungsmatrixPath", $fixture.Matrix)
    Assert-True -Condition ($result.ExitCode -ne 0) -Message "Schema-2-Matrix ohne Kategorie und Gewichtung wurde akzeptiert."
  }

  Invoke-Test -Name "Inhaltsprüfer verlangt eine endgültige Seitenstrategie" -Body {
    $fixture = New-ValidContentFixture -Root (Join-Path $testRoot "missing-page-strategy")
    $auftrag = Get-Content -LiteralPath $fixture.Auftrag -Raw -Encoding UTF8 | ConvertFrom-Json
    $auftrag.seitenstrategie = "noch_festzulegen"
    Set-Content -LiteralPath $fixture.Auftrag -Encoding UTF8 -Value ($auftrag | ConvertTo-Json -Depth 6)
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Pruefe-Bewerbungsinhalt.ps1") -Arguments @("-Ordner", $fixture.Folder, "-StammdatenPath", $fixture.Personal, "-ProfilPath", $fixture.Profile, "-AuftragPath", $fixture.Auftrag, "-AnforderungsmatrixPath", $fixture.Matrix)
    Assert-True -Condition ($result.ExitCode -ne 0) -Message "Nicht festgelegte Seitenstrategie wurde akzeptiert."
  }

  Invoke-Test -Name "Finalisierung verlangt eine ausdrückliche Sichtprüfung" -Body {
    $fixture = New-StagedFinalizationFixture -Root (Join-Path $testRoot "finalize-needs-visual")
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Finalisiere-Bewerbung.ps1") -Arguments @("-Arbeitsordner", $fixture.Work, "-StammdatenPath", $fixture.Personal, "-ProfilPath", $fixture.Profile, "-Veroeffentlichen")
    Assert-True -Condition ($result.ExitCode -ne 0) -Message "Finalisierung wurde ohne bestätigte Sichtprüfung erlaubt."
    Assert-True -Condition (@(Get-ChildItem -LiteralPath $fixture.Folder -Force).Count -eq 0) -Message "Finaler Ordner wurde trotz fehlender Sichtprüfung verändert."
  }

  Invoke-Test -Name "Finalisierung verwirft Hashnachweis nach HTML-Änderung" -Body {
    $fixture = New-StagedFinalizationFixture -Root (Join-Path $testRoot "finalize-stale-html")
    $cvPath = Join-Path $fixture.Candidate "Lebenslauf - TEST.PERSON.html"
    Add-Content -LiteralPath $cvPath -Encoding UTF8 -Value "<!-- nach Prüfung geändert -->"
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Finalisiere-Bewerbung.ps1") -Arguments @("-Arbeitsordner", $fixture.Work, "-StammdatenPath", $fixture.Personal, "-ProfilPath", $fixture.Profile, "-Veroeffentlichen", "-VisuellGeprueft")
    Assert-True -Condition ($result.ExitCode -ne 0) -Message "Veralteter Layoutnachweis wurde nach HTML-Änderung akzeptiert."
    Assert-True -Condition (@(Get-ChildItem -LiteralPath $fixture.Folder -Force).Count -eq 0) -Message "Finaler Ordner wurde trotz veraltetem Hashnachweis verändert."
  }

  Invoke-Test -Name "Finalisierung schützt auch Markdown-Kandidaten und Quelldateien per Hash" -Body {
    $fixture = New-StagedFinalizationFixture -Root (Join-Path $testRoot "finalize-stale-candidate")
    Add-Content -LiteralPath (Join-Path $fixture.Candidate "Analyse.md") -Encoding UTF8 -Value "nach Vorbereitung geändert"
    $candidateResult = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Finalisiere-Bewerbung.ps1") -Arguments @("-Arbeitsordner", $fixture.Work, "-StammdatenPath", $fixture.Personal, "-ProfilPath", $fixture.Profile, "-Veroeffentlichen", "-VisuellGeprueft")
    Assert-True -Condition ($candidateResult.ExitCode -ne 0) -Message "Veränderte Markdown-Kandidatendatei wurde akzeptiert."
    Assert-True -Condition (@(Get-ChildItem -LiteralPath $fixture.Folder -Force).Count -eq 0) -Message "Zielordner wurde trotz geändertem Kandidatenartefakt befüllt."

    $sourceFixture = New-StagedFinalizationFixture -Root (Join-Path $testRoot "finalize-stale-source")
    Add-Content -LiteralPath $sourceFixture.Profile -Encoding UTF8 -Value "nach Vorbereitung geändert"
    $sourceResult = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Finalisiere-Bewerbung.ps1") -Arguments @("-Arbeitsordner", $sourceFixture.Work, "-StammdatenPath", $sourceFixture.Personal, "-ProfilPath", $sourceFixture.Profile, "-Veroeffentlichen", "-VisuellGeprueft")
    Assert-True -Condition ($sourceResult.ExitCode -ne 0) -Message "Veränderte Profildatei wurde akzeptiert."
    Assert-True -Condition (@(Get-ChildItem -LiteralPath $sourceFixture.Folder -Force).Count -eq 0) -Message "Zielordner wurde trotz geändertem Quellnachweis befüllt."

    $newFileFixture = New-StagedFinalizationFixture -Root (Join-Path $testRoot "finalize-added-candidate")
    Set-Content -LiteralPath (Join-Path $newFileFixture.Candidate "Notizen.md") -Encoding UTF8 -Value "nach Vorbereitung hinzugefügt"
    $newFileResult = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Finalisiere-Bewerbung.ps1") -Arguments @("-Arbeitsordner", $newFileFixture.Work, "-StammdatenPath", $newFileFixture.Personal, "-ProfilPath", $newFileFixture.Profile, "-Veroeffentlichen", "-VisuellGeprueft")
    Assert-True -Condition ($newFileResult.ExitCode -ne 0) -Message "Neu hinzugefügte ungeprüfte Kandidatendatei wurde akzeptiert."
    Assert-True -Condition (@(Get-ChildItem -LiteralPath $newFileFixture.Folder -Force).Count -eq 0) -Message "Zielordner wurde trotz neuer ungeprüfter Datei befüllt."
  }

  Invoke-Test -Name "Layoutwarnung verlangt eine nachvollziehbare Freigabenotiz" -Body {
    $fixture = New-StagedFinalizationFixture -Root (Join-Path $testRoot "finalize-warning-note")
    $report = Get-Content -LiteralPath $fixture.FinalReport -Raw -Encoding UTF8 | ConvertFrom-Json
    $report.layoutWarnings = @("Lebenslauf, Seite 1: ungewöhnlich viel freie Fläche")
    Set-Content -LiteralPath $fixture.FinalReport -Encoding UTF8 -Value ($report | ConvertTo-Json -Depth 10)
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Finalisiere-Bewerbung.ps1") -Arguments @("-Arbeitsordner", $fixture.Work, "-StammdatenPath", $fixture.Personal, "-ProfilPath", $fixture.Profile, "-Veroeffentlichen", "-VisuellGeprueft")
    Assert-True -Condition ($result.ExitCode -ne 0) -Message "Layoutwarnung wurde ohne Freigabenotiz akzeptiert."
    Assert-True -Condition (@(Get-ChildItem -LiteralPath $fixture.Folder -Force).Count -eq 0) -Message "Zielordner wurde trotz unbegründeter Layoutwarnung befüllt."
  }

  Invoke-Test -Name "Finalisierung veröffentlicht validiertes Set atomar" -Body {
    $fixture = New-StagedFinalizationFixture -Root (Join-Path $testRoot "finalize-valid")
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Finalisiere-Bewerbung.ps1") -Arguments @("-Arbeitsordner", $fixture.Work, "-StammdatenPath", $fixture.Personal, "-ProfilPath", $fixture.Profile, "-Veroeffentlichen", "-VisuellGeprueft")
    Assert-True -Condition ($result.ExitCode -eq 0) -Message "Gültige atomare Veröffentlichung schlug fehl: $($result.Output -join ' | ')"
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $fixture.Folder "Versand/Lebenslauf - TEST.PERSON.pdf") -PathType Leaf) -Message "Veröffentlichter Lebenslauf fehlt im Versandordner."
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $fixture.Folder "Versand/Anschreiben - TEST.PERSON.pdf") -PathType Leaf) -Message "Veröffentlichtes Anschreiben fehlt im Versandordner."
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $fixture.Folder "Intern/Lebenslauf - TEST.PERSON.html") -PathType Leaf) -Message "Interne HTML-Quelle fehlt."
    Assert-True -Condition (@(Get-ChildItem -LiteralPath (Join-Path $fixture.Folder "Intern") -Filter "*.pdf" -File).Count -eq 0) -Message "Interner Ordner enthält PDF-Dubletten."
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $fixture.Folder "Manifest.json") -PathType Leaf) -Message "Veröffentlichungsmanifest fehlt."
    $staticResult = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Pruefe-Bewerbung.ps1") -Arguments @("-Ordner", $fixture.Folder)
    Assert-True -Condition ($staticResult.ExitCode -eq 0) -Message "Strukturierte Veröffentlichung wurde nachträglich abgelehnt: $($staticResult.Output -join ' | ')"
    $report = Get-Content -LiteralPath $fixture.FinalReport -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True -Condition ($report.status -eq "veroeffentlicht") -Message "Finalisierungsbericht wurde nicht auf veröffentlicht gesetzt."
    Add-Content -LiteralPath (Join-Path $fixture.Folder "Versand/Email-Nachricht--Audit-Firma.md") -Encoding UTF8 -Value "Manipulation nach Veröffentlichung"
    $tamperResult = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Pruefe-Bewerbung.ps1") -Arguments @("-Ordner", $fixture.Folder)
    Assert-True -Condition ($tamperResult.ExitCode -ne 0) -Message "Manifest erkannte eine nachträglich veränderte Versanddatei nicht."
  }

  Invoke-Test -Name "Initiativbewerbung gilt als konkreter E-Mail-Betreff" -Body {
    $folder = New-ValidApplicationFixture -Root (Join-Path $testRoot "initiative-subject")
    $path = Join-Path $folder "Email-Nachricht--Audit-Firma.md"
    $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $text = $text.Replace("Betreff: Bewerbung als Audit-Rolle", "Betreff: Initiativbewerbung IT")
    Set-Content -LiteralPath $path -Value $text -Encoding UTF8
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Pruefe-Bewerbung.ps1") -Arguments @("-Ordner", $folder)
    Assert-True -Condition ($result.ExitCode -eq 0) -Message "Korrekte Initiativbewerbung wurde abgelehnt: $($result.Output -join ' | ')"
  }

  Invoke-Test -Name "Mehrfach defekte Bewerbung wird abgelehnt" -Body {
    $folder = New-ValidApplicationFixture -Root (Join-Path $testRoot "invalid")
    Remove-Item -LiteralPath (Join-Path $folder "Analyse.md") -Force
    New-Item -Path (Join-Path $folder "Analyse.md") -ItemType Directory | Out-Null
    Set-Content -LiteralPath (Join-Path $folder "Qualitaetscheck.md") -Value "" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $folder "Email-Nachricht--Audit-Firma.md") -Value "Anbei die Bewerbung." -Encoding UTF8
    $badHtml = @"
Text vor dem Doctype
<!doctype html><html lang="de"><head><style>
@page { size: A4; margin: 0; }
.page { width: 210mm; min-height: 297mm; }
.page .secret { overflow: hidden; }
</style></head><body>
<main class="page"><div class="secret">Seite 1</div></main>
<main class="page">Seite 2</main>
</body></html>
"@
    Set-Content -LiteralPath (Join-Path $folder "Lebenslauf - TEST.PERSON.html") -Value $badHtml -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $folder "Anschreiben - TEST.PERSON.html") -Value $badHtml -Encoding UTF8
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Pruefe-Bewerbung.ps1") -Arguments @("-Ordner", $folder)
    Assert-True -Condition ($result.ExitCode -ne 0) -Message "Defekte Fixture wurde fälschlich akzeptiert."
  }

  Invoke-Test -Name "Automatisch ladende externe Ressourcen werden abgelehnt" -Body {
    $folder = New-ValidApplicationFixture -Root (Join-Path $testRoot "external")
    $path = Join-Path $folder "Anschreiben - TEST.PERSON.html"
    $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $text = $text.Replace('<meta charset="utf-8">', '<meta charset="utf-8"><link rel="stylesheet" href="https://example.invalid/external.css">')
    Set-Content -LiteralPath $path -Value $text -Encoding UTF8
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Pruefe-Bewerbung.ps1") -Arguments @("-Ordner", $folder)
    Assert-True -Condition ($result.ExitCode -ne 0) -Message "Externe Ressource wurde fälschlich akzeptiert."
  }

  Invoke-Test -Name "Relative lokale Ressourcen werden ebenfalls abgelehnt" -Body {
    $folder = New-ValidApplicationFixture -Root (Join-Path $testRoot "relative-resource")
    $path = Join-Path $folder "Anschreiben - TEST.PERSON.html"
    $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $text = $text.Replace('<h1>Fiktiver Testinhalt</h1>', '<h1>Fiktiver Testinhalt</h1><img src="lokales-foto.png" alt="Test">')
    Set-Content -LiteralPath $path -Value $text -Encoding UTF8
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Pruefe-Bewerbung.ps1") -Arguments @("-Ordner", $folder)
    Assert-True -Condition ($result.ExitCode -ne 0) -Message "Relative automatisch geladene Ressource wurde fälschlich akzeptiert."
  }

  Invoke-Test -Name "Unmögliches Kalenderdatum wird vor jeder Ausgabe abgelehnt" -Body {
    $root = Join-Path $testRoot "invalid-date-root"
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Neue-Bewerbung.ps1") -Arguments @("-Firma", "Audit Firma", "-Rolle", "Audit Rolle", "-Datum", "2026-99-99", "-BewerbungenRoot", $root)
    Assert-True -Condition ($result.ExitCode -eq 2) -Message "Ungültiges Datum lieferte Exitcode $($result.ExitCode)."
    Assert-True -Condition (-not (Test-Path -LiteralPath $root)) -Message "Trotz ungültigem Datum wurde ein Ausgabeordner erstellt."
  }

  Invoke-Test -Name "Verzeichnis als Stellenbeschreibung wird ohne Teilstruktur abgelehnt" -Body {
    $source = Join-Path $testRoot "source-directory"
    New-Item -Path $source -ItemType Directory | Out-Null
    $root = Join-Path $testRoot "directory-source-root"
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Neue-Bewerbung.ps1") -Arguments @("-Firma", "Audit Firma", "-Rolle", "Audit Rolle", "-Datum", "2026-07-14", "-StellenbeschreibungPath", $source, "-BewerbungenRoot", $root)
    Assert-True -Condition ($result.ExitCode -eq 2) -Message "Verzeichnisquelle lieferte Exitcode $($result.ExitCode)."
    Assert-True -Condition (-not (Test-Path -LiteralPath $root)) -Message "Trotz ungültiger Quelle wurde ein Ausgabeordner erstellt."
  }

  Invoke-Test -Name "Datei als BewerbungenRoot wird als Fehler gemeldet" -Body {
    $rootFile = Join-Path $testRoot "root-is-file"
    Set-Content -LiteralPath $rootFile -Value "keine Verzeichnisstruktur" -Encoding UTF8
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Neue-Bewerbung.ps1") -Arguments @("-Firma", "Audit Firma", "-Rolle", "Audit Rolle", "-Datum", "2026-07-14", "-BewerbungenRoot", $rootFile)
    Assert-True -Condition ($result.ExitCode -eq 2) -Message "Datei als Root lieferte Exitcode $($result.ExitCode)."
    Assert-True -Condition (-not ($result.Output -match '^Bewerbungsordner:')) -Message "Fehlerhafter Lauf meldete einen Bewerbungsordner als Erfolg."
  }

  Invoke-Test -Name "Slug-Kollision überschreibt keine vorhandene Bewerbung" -Body {
    $root = Join-Path $testRoot "collision-root"
    $sourceOne = Join-Path $testRoot "job-one.md"
    $sourceTwo = Join-Path $testRoot "job-two.md"
    Set-Content -LiteralPath $sourceOne -Value "JOB-ONE" -Encoding UTF8
    Set-Content -LiteralPath $sourceTwo -Value "JOB-TWO" -Encoding UTF8
    $first = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Neue-Bewerbung.ps1") -Arguments @("-Firma", "A+B", "-Rolle", "Audit", "-Datum", "2026-07-14", "-StellenbeschreibungPath", $sourceOne, "-BewerbungenRoot", $root)
    $second = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Neue-Bewerbung.ps1") -Arguments @("-Firma", "A B", "-Rolle", "Audit", "-Datum", "2026-07-14", "-StellenbeschreibungPath", $sourceTwo, "-BewerbungenRoot", $root)
    Assert-True -Condition ($first.ExitCode -eq 0) -Message "Erster Lauf schlug fehl."
    Assert-True -Condition ($second.ExitCode -eq 2) -Message "Kollisionslauf wurde nicht mit Exitcode 2 abgelehnt."
    $finalJob = Join-Path $root "A-B/_Arbeitsdateien/2026-07-14--Audit/Kandidat/Stellenbeschreibung.md"
    Assert-True -Condition ((Get-Content -LiteralPath $finalJob -Raw -Encoding UTF8).Trim() -eq "JOB-ONE") -Message "Vorhandene Stellenbeschreibung wurde verändert."
    Assert-True -Condition (@(Get-ChildItem -LiteralPath (Join-Path $root "A-B/2026-07-14--Audit") -Force).Count -eq 0) -Message "Finaler Ordner wurde vor der Freigabe befüllt."
  }

  Invoke-Test -Name "Exakt dieselbe Bewerbung kann explizit fortgesetzt werden" -Body {
    $root = Join-Path $testRoot "resume-root"
    $source = Join-Path $testRoot "resume-job.md"
    Set-Content -LiteralPath $source -Value "GLEICHE-STELLE" -Encoding UTF8
    $arguments = @("-Firma", "Audit Firma", "-Rolle", "Audit Rolle", "-Datum", "2026-07-14", "-StellenbeschreibungPath", $source, "-BewerbungenRoot", $root)
    $first = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Neue-Bewerbung.ps1") -Arguments $arguments
    $second = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Neue-Bewerbung.ps1") -Arguments @($arguments + "-Fortsetzen")
    Assert-True -Condition (($first.ExitCode -eq 0) -and ($second.ExitCode -eq 0)) -Message "Sicheres Fortsetzen schlug fehl."
  }

  Invoke-Test -Name "Unvollständige Bewerbung kann nicht blind fortgesetzt werden" -Body {
    $root = Join-Path $testRoot "incomplete-resume-root"
    New-Item -Path (Join-Path $root "Audit-Firma/2026-07-14--Audit-Rolle") -ItemType Directory -Force | Out-Null
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Neue-Bewerbung.ps1") -Arguments @("-Firma", "Audit Firma", "-Rolle", "Audit Rolle", "-Datum", "2026-07-14", "-BewerbungenRoot", $root, "-Fortsetzen")
    Assert-True -Condition ($result.ExitCode -eq 2) -Message "Unvollständige Bewerbung wurde mit Exitcode $($result.ExitCode) fortgesetzt."
  }

  Invoke-Test -Name "Verzeichnis kann Stellenbeschreibung beim Fortsetzen nicht ersetzen" -Body {
    $root = Join-Path $testRoot "job-directory-resume-root"
    $source = Join-Path $testRoot "job-directory-resume.md"
    Set-Content -LiteralPath $source -Value "FIKTIVE STELLE" -Encoding UTF8
    $arguments = @("-Firma", "Audit Firma", "-Rolle", "Audit Rolle", "-Datum", "2026-07-14", "-BewerbungenRoot", $root)
    $first = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Neue-Bewerbung.ps1") -Arguments $arguments
    Assert-True -Condition ($first.ExitCode -eq 0) -Message "Vorbereitung der Fixture schlug fehl."
    $jobPath = Join-Path $root "Audit-Firma/_Arbeitsdateien/2026-07-14--Audit-Rolle/Kandidat/Stellenbeschreibung.md"
    New-Item -Path $jobPath -ItemType Directory | Out-Null
    $second = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Neue-Bewerbung.ps1") -Arguments @($arguments + @("-StellenbeschreibungPath", $source, "-Fortsetzen"))
    Assert-True -Condition ($second.ExitCode -ne 0) -Message "Stellenbeschreibungs-Verzeichnis wurde beim Fortsetzen akzeptiert."
    Assert-True -Condition (@(Get-ChildItem -LiteralPath $jobPath -Force).Count -eq 0) -Message "Quelldatei wurde in das Stellenbeschreibungs-Verzeichnis kopiert."
  }

  $gitBash = Join-Path $env:USERPROFILE "scoop/apps/git/current/bin/bash.exe"
  if (Test-Path -LiteralPath $gitBash -PathType Leaf) {
    Invoke-Test -Name "Bash-Regressionssuite besteht" -Body {
      & $gitBash (Join-Path $PSScriptRoot "Bash/test-neue-bewerbung.sh")
      Assert-True -Condition ($LASTEXITCODE -eq 0) -Message "Bash-Regressionssuite lieferte Exitcode $LASTEXITCODE."
    }
  } else {
    Write-Host "[INFO] Git Bash nicht gefunden; Bash-Lauf wird in CI ausgeführt."
  }

  if ($MitBrowser) {
    $chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"
    if (-not (Test-Path -LiteralPath $chrome -PathType Leaf)) {
      Write-Host "[INFO] Chrome nicht gefunden; Browser-Regressionsfälle übersprungen."
    } else {
      Invoke-Test -Name "Layoutcheck akzeptiert keine unveränderten Pseudo-PNGs" -Body {
        $folder = New-ValidApplicationFixture -Root (Join-Path $testRoot "layout-browser")
        $companyDir = Split-Path -Path $folder -Parent
        $roleDir = Split-Path -Path $folder -Leaf
        $layoutDir = Join-Path $companyDir "_Arbeitsdateien/$roleDir/Layoutcheck"
        New-Item -Path $layoutDir -ItemType Directory -Force | Out-Null
        $fake = New-Object byte[] 6001
        for ($index = 0; $index -lt $fake.Length; $index++) {
          $fake[$index] = 65
        }
        $fakePaths = @(
          (Join-Path $layoutDir "Anschreiben---TEST.PERSON--seite-1-von-1--chrome.png"),
          (Join-Path $layoutDir "Lebenslauf---TEST.PERSON--seite-1-von-1--chrome.png")
        )
        foreach ($path in $fakePaths) {
          [System.IO.File]::WriteAllBytes($path, $fake)
          (Get-Item -LiteralPath $path).IsReadOnly = $true
        }
        $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Layoutcheck-Bewerbung.ps1") -Arguments @("-Ordner", $folder, "-Browser", "chrome", "-TimeoutSeconds", "60")
        Assert-True -Condition ($result.ExitCode -eq 0) -Message "Layoutcheck konnte die Pseudo-PNGs nicht durch frische Screenshots ersetzen: $($result.Output -join ' | ')"
        foreach ($path in $fakePaths) {
          Assert-True -Condition (Test-PngSignature -Path $path) -Message "Layoutcheck akzeptierte eine unveränderte Pseudo-PNG-Datei."
        }
        $layoutReport = Join-Path $layoutDir "Layoutcheck-Bericht.json"
        Assert-True -Condition (Test-Path -LiteralPath $layoutReport -PathType Leaf) -Message "Layoutcheck schrieb keinen JSON-Bericht."
        $layoutData = Get-Content -LiteralPath $layoutReport -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-True -Condition (@($layoutData.results).Count -eq 2) -Message "Layoutbericht enthält nicht genau zwei Dokumentnachweise."
        Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($layoutData.results[0].htmlSha256)) -Message "Layoutbericht enthält keinen HTML-Hash."
        Assert-True -Condition ($layoutData.captureMode -eq "eine_png_pro_a4_seite") -Message "Layoutbericht weist den Seitencapture-Modus nicht aus."
      }

      Invoke-Test -Name "Layoutcheck erfasst jede explizite A4-Seite einzeln" -Body {
        $folder = New-ValidApplicationFixture -Root (Join-Path $testRoot "layout-multipage")
        $cvPath = Join-Path $folder "Lebenslauf - TEST.PERSON.html"
        $cv = Get-Content -LiteralPath $cvPath -Raw -Encoding UTF8
        $twoPages = @"
<body>
  <main class="page"><h1>Lebenslauf Seite 1</h1><footer class="page-footer">Seite 1 von 2</footer></main>
  <main class="page"><h2>Lebenslauf Seite 2</h2><footer class="page-footer">Seite 2 von 2</footer></main>
</body>
"@
        $cv = [regex]::Replace($cv, '(?is)<body>.*?</body>', $twoPages)
        Set-Content -LiteralPath $cvPath -Encoding UTF8 -Value $cv
        $companyDir = Split-Path -Path $folder -Parent
        $roleDir = Split-Path -Path $folder -Leaf
        $layoutDir = Join-Path $companyDir "_Arbeitsdateien/$roleDir/Layoutcheck"
        $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Layoutcheck-Bewerbung.ps1") -Arguments @("-Ordner", $folder, "-Browser", "chrome", "-TimeoutSeconds", "60")
        Assert-True -Condition ($result.ExitCode -eq 0) -Message "Mehrseiten-Layoutcheck schlug fehl: $($result.Output -join ' | ')"
        $pngs = @(Get-ChildItem -LiteralPath $layoutDir -Filter "*.png" -File)
        Assert-True -Condition ($pngs.Count -eq 3) -Message "Erwartet wurden drei Seitenscreenshots, erzeugt wurden $($pngs.Count)."
        Assert-True -Condition (Test-Path -LiteralPath (Join-Path $layoutDir "Lebenslauf---TEST.PERSON--seite-2-von-2--chrome.png") -PathType Leaf) -Message "Screenshot der zweiten Lebenslaufseite fehlt."
        $layoutData = Get-Content -LiteralPath (Join-Path $layoutDir "Layoutcheck-Bericht.json") -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-True -Condition (@($layoutData.results).Count -eq 3 -and $layoutData.expectedScreenshots -eq 3) -Message "Layoutbericht bildet nicht alle A4-Seiten ab."
      }

      Invoke-Test -Name "Finalisierungs-Vorbereitung erzeugt gebundene Browser- und PDF-Nachweise" -Body {
        $fixture = New-StagedFinalizationFixture -Root (Join-Path $testRoot "finalize-browser")
        Remove-Item -LiteralPath $fixture.FinalReport -Force
        $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Finalisiere-Bewerbung.ps1") -Arguments @("-Arbeitsordner", $fixture.Work, "-StammdatenPath", $fixture.Personal, "-ProfilPath", $fixture.Profile, "-Browser", "chrome", "-TimeoutSeconds", "60")
        Assert-True -Condition ($result.ExitCode -eq 0) -Message "Browsergestützte Finalisierungsvorbereitung schlug fehl: $($result.Output -join ' | ')"
        $report = Get-Content -LiteralPath $fixture.FinalReport -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-True -Condition ($report.status -eq "bereit_zur_sichtpruefung") -Message "Finalisierungsbericht hat nicht den erwarteten Vorbereitungsstatus."
        Assert-True -Condition (@($report.artifacts.html).Count -eq 2) -Message "Finalisierungsbericht enthält nicht genau zwei HTML-Nachweise."
        Assert-True -Condition (@($report.artifacts.pdf).Count -eq 2) -Message "Finalisierungsbericht enthält nicht genau zwei PDF-Nachweise."
        Assert-True -Condition (@($report.artifacts.screenshots).Count -eq 2) -Message "Finalisierungsbericht enthält nicht genau zwei Screenshot-Nachweise."
        Assert-True -Condition (Test-Path -LiteralPath $report.atsReport -PathType Leaf) -Message "Finalisierung schrieb keinen ATS-Prüfbericht."
        $ats = Get-Content -LiteralPath $report.atsReport -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-True -Condition ($ats.status -eq "ok" -and @($ats.results).Count -eq 2) -Message "ATS-Prüfung bestätigte nicht beide PDFs."
        Assert-True -Condition (@(Get-ChildItem -LiteralPath $fixture.Folder -Force).Count -eq 0) -Message "Vorbereitung hat den finalen Zielordner befüllt."
        $publish = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Finalisiere-Bewerbung.ps1") -Arguments @(
          "-Arbeitsordner", $fixture.Work,
          "-StammdatenPath", $fixture.Personal,
          "-ProfilPath", $fixture.Profile,
          "-Veroeffentlichen",
          "-VisuellGeprueft",
          "-VisuelleFreigabeNotiz", "Alle erzeugten Testseiten geprüft; keine Überlappung oder abgeschnittener Inhalt."
        )
        Assert-True -Condition ($publish.ExitCode -eq 0) -Message "Veröffentlichung nach realer Browservorbereitung schlug fehl: $($publish.Output -join ' | ')"
        Assert-True -Condition (Test-Path -LiteralPath (Join-Path $fixture.Folder "Versand/Lebenslauf - TEST.PERSON.pdf") -PathType Leaf) -Message "Realer Versand-Lebenslauf fehlt."
        Assert-True -Condition (Test-Path -LiteralPath (Join-Path $fixture.Folder "Manifest.json") -PathType Leaf) -Message "Manifest der realen Veröffentlichung fehlt."
        $publishedStatic = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Pruefe-Bewerbung.ps1") -Arguments @("-Ordner", $fixture.Folder)
        Assert-True -Condition ($publishedStatic.ExitCode -eq 0) -Message "Reale strukturierte Veröffentlichung wurde abgelehnt: $($publishedStatic.Output -join ' | ')"
      }

      Invoke-Test -Name "PDF-Export lehnt zusätzliche Druckseiten ab" -Body {
        $folder = New-ValidApplicationFixture -Root (Join-Path $testRoot "overflow-pdf")
        foreach ($html in Get-ChildItem -LiteralPath $folder -Filter "*.html" -File) {
          $text = Get-Content -LiteralPath $html.FullName -Raw -Encoding UTF8
          $text = $text.Replace('</body>', '<section style="width:210mm;height:297mm;background:#fff">Absichtlich zusätzliche Druckseite</section></body>')
          Set-Content -LiteralPath $html.FullName -Value $text -Encoding UTF8
        }
        $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Exportiere-PDF.ps1") -Arguments @("-Ordner", $folder, "-Browser", "chrome", "-TimeoutSeconds", "60")
        Assert-True -Condition ($result.ExitCode -ne 0) -Message "PDF mit zusätzlichen Druckseiten wurde fälschlich akzeptiert."
        Assert-True -Condition (($result.Output -join "`n") -match "PDF-Seitenzahl stimmt nicht mit dem HTML überein") -Message "Export scheiterte nicht aus dem erwarteten Seitenzahl-Grund: $($result.Output -join ' | ')"
        Assert-True -Condition (@(Get-ChildItem -LiteralPath $folder -Filter "*.pdf" -File).Count -eq 0) -Message "Fehlgeschlagener Export hinterließ finale PDFs."
      }

      Invoke-Test -Name "Erfolgreicher PDF-Export ersetzt alte Dateien nach Validierung" -Body {
        $folder = New-ValidApplicationFixture -Root (Join-Path $testRoot "valid-pdf")
        $first = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Exportiere-PDF.ps1") -Arguments @("-Ordner", $folder, "-Browser", "chrome", "-TimeoutSeconds", "60")
        Assert-True -Condition ($first.ExitCode -eq 0) -Message "Erster gültiger PDF-Export schlug fehl: $($first.Output -join ' | ')"
        $pdfs = @(Get-ChildItem -LiteralPath $folder -Filter "*.pdf" -File)
        Assert-True -Condition ($pdfs.Count -eq 2) -Message "Es wurden nicht genau zwei PDFs erzeugt."
        $pdfReport = Join-Path (Split-Path -Path $folder -Parent) "_Arbeitsdateien/$(Split-Path -Path $folder -Leaf)/PDF-Export/PDF-Export-Bericht.json"
        Assert-True -Condition (Test-Path -LiteralPath $pdfReport -PathType Leaf) -Message "PDF-Export schrieb keinen JSON-Bericht."
        $hashes = @{}
        foreach ($pdf in $pdfs) {
          $hashes[$pdf.FullName] = (Get-FileHash -LiteralPath $pdf.FullName -Algorithm SHA256).Hash
          $pdf.IsReadOnly = $true
        }
        foreach ($html in Get-ChildItem -LiteralPath $folder -Filter "*.html" -File) {
          $text = Get-Content -LiteralPath $html.FullName -Raw -Encoding UTF8
          $text = $text.Replace("Fiktiver Testinhalt", "Geänderter sichtbarer Testinhalt")
          Set-Content -LiteralPath $html.FullName -Value $text -Encoding UTF8
        }
        $second = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Exportiere-PDF.ps1") -Arguments @("-Ordner", $folder, "-Browser", "chrome", "-TimeoutSeconds", "60")
        Assert-True -Condition ($second.ExitCode -eq 0) -Message "Zweiter gültiger PDF-Export schlug fehl: $($second.Output -join ' | ')"
        foreach ($pdf in Get-ChildItem -LiteralPath $folder -Filter "*.pdf" -File) {
          Assert-True -Condition ($hashes[$pdf.FullName] -ne (Get-FileHash -LiteralPath $pdf.FullName -Algorithm SHA256).Hash) -Message "Alter PDF-Inhalt wurde trotz Erfolg unverändert weiterverwendet."
        }
      }

      Invoke-Test -Name "PDF-Zielverzeichnis wird nicht als Datei behandelt" -Body {
        $folder = New-ValidApplicationFixture -Root (Join-Path $testRoot "pdf-target-directory")
        $invalidTarget = Join-Path $folder "Anschreiben - TEST.PERSON.pdf"
        New-Item -Path $invalidTarget -ItemType Directory | Out-Null
        $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Exportiere-PDF.ps1") -Arguments @("-Ordner", $folder, "-Browser", "chrome", "-TimeoutSeconds", "60")
        Assert-True -Condition ($result.ExitCode -ne 0) -Message "PDF-Zielverzeichnis wurde als gültige Datei behandelt."
        Assert-True -Condition (($result.Output -join "`n") -match "keine reguläre Datei") -Message "Unerwarteter Fehlergrund für PDF-Zielverzeichnis: $($result.Output -join ' | ')"
      }
    }
  }
} finally {
  if (Test-Path -LiteralPath $testRoot -PathType Container) {
    Get-ChildItem -LiteralPath $testRoot -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { $_.IsReadOnly = $false }
    $fullTestRoot = [System.IO.Path]::GetFullPath($testRoot)
    $fullTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($fullTestRoot.StartsWith($fullTempRoot, [System.StringComparison]::OrdinalIgnoreCase) -and ((Split-Path -Leaf $fullTestRoot) -like "bewerbungs-agent-tests-*")) {
      Remove-Item -LiteralPath $fullTestRoot -Recurse -Force
    }
  }
}

Write-Host ""
Write-Host "Testergebnis: $($passed.Count) bestanden, $($failed.Count) fehlgeschlagen."
foreach ($failure in $failed) {
  Write-Host "- $failure" -ForegroundColor Red
}

if ($failed.Count -gt 0) {
  exit 1
}
exit 0
