#requires -Version 7.6
#requires -PSEdition Core

[CmdletBinding()]
param(
  [string]$Datum = (Get-Date -Format 'yyyy-MM-dd'),

  [string]$StammdatenPath = (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'Private', 'Daten', '01_PERSOENLICHE_DATEN.md'),

  [string]$ProfilPath = (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'Private', 'Daten', '02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md'),

  [string]$BewerbungenRoot = (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'Private', 'Bewerbungen'),

  [switch]$Fortsetzen
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath 'Common/Platform.psm1') -Force

function Stop-UniversalSetup {
  param([string]$Message, [int]$Code = 2)
  Write-Host "[FEHLER] $Message" -ForegroundColor Red
  exit $Code
}

function Get-MarkdownField {
  param([string]$Path, [string]$Name)
  foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
    if ($line -match '^\s*-\s*(?<key>[^:]+):\s*(?<value>.*)$' -and $Matches.key.Trim() -eq $Name) {
      return $Matches.value.Trim()
    }
  }
  return ''
}

$parsedDate = [datetime]::MinValue
if (-not [datetime]::TryParseExact($Datum, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsedDate)) {
  Stop-UniversalSetup 'Datum muss ein echtes Kalenderdatum im Format YYYY-MM-DD sein.'
}
foreach ($sourcePath in @($StammdatenPath, $ProfilPath)) {
  if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    Stop-UniversalSetup "Erforderliche private Quelldatei fehlt: $sourcePath" 1
  }
}

$applicationsRoot = [System.IO.Path]::GetFullPath($BewerbungenRoot)
$privateRoot = Split-Path -Path $applicationsRoot -Parent
if ((Split-Path -Path $applicationsRoot -Leaf) -cne 'Bewerbungen' -or (Split-Path -Path $privateRoot -Leaf) -cne 'Private') {
  Stop-UniversalSetup "BewerbungenRoot muss auf einen Private/Bewerbungen-Ordner zeigen: $applicationsRoot"
}
New-Item -Path $applicationsRoot -ItemType Directory -Force | Out-Null
$applicationsRoot = Resolve-SafePath -Candidate $applicationsRoot -Root $applicationsRoot -AllowRoot -MustExist -ForWrite -PathType Container
$stammdaten = Resolve-SafePath -Candidate $StammdatenPath -Root $privateRoot -MustExist -PathType Leaf
$profil = Resolve-SafePath -Candidate $ProfilPath -Root $privateRoot -MustExist -PathType Leaf
$fileNamePerson = Get-MarkdownField -Path $stammdaten -Name 'Dateiname-Name'
if ([string]::IsNullOrWhiteSpace($fileNamePerson) -or $fileNamePerson -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z0-9][A-Za-z0-9.-]*$') {
  Stop-UniversalSetup 'Dateiname-Name fehlt oder ist für den Lebenslauf-Dateinamen ungültig.'
}

$namespace = Resolve-SafePath -Candidate (Join-Path $applicationsRoot '_Universal-Lebenslauf') -Root $applicationsRoot -ForWrite -PathType Container
$workCollection = Resolve-SafePath -Candidate (Join-Path $namespace '_Arbeitsdateien') -Root $applicationsRoot -ForWrite -PathType Container
$jobName = "$Datum--Softwareentwicklung"
$work = Resolve-SafePath -Candidate (Join-Path $workCollection $jobName) -Root $applicationsRoot -ForWrite -PathType Container
$candidate = Resolve-SafePath -Candidate (Join-Path $work 'Kandidat') -Root $applicationsRoot -ForWrite -PathType Container
$orderPath = Resolve-SafePath -Candidate (Join-Path $work 'Universalauftrag.json') -Root $applicationsRoot -ForWrite -PathType Leaf

if (Test-Path -LiteralPath $work) {
  if (-not $Fortsetzen) {
    Stop-UniversalSetup "Universal-Arbeitsordner existiert bereits. Für exakt diesen Stand --fortsetzen verwenden: $work"
  }
  if (-not (Test-Path -LiteralPath $orderPath -PathType Leaf) -or -not (Test-Path -LiteralPath $candidate -PathType Container)) {
    Stop-UniversalSetup 'Vorhandener Universal-Arbeitsordner ist unvollständig und wird nicht überschrieben.'
  }
  Write-Host "[OK] Bestehender Universal-Lebenslauf-Arbeitsstand wird fortgesetzt: $work" -ForegroundColor Green
  exit 0
}

New-Item -Path $candidate -ItemType Directory -Force | Out-Null
$work = Resolve-SafePath -Candidate $work -Root $applicationsRoot -MustExist -ForWrite -PathType Container
$candidate = Resolve-SafePath -Candidate $candidate -Root $applicationsRoot -MustExist -ForWrite -PathType Container

$workRelative = "_Universal-Lebenslauf/_Arbeitsdateien/$jobName"
$order = [ordered]@{
  schemaVersion = 5
  auftragsart = 'universal_lebenslauf'
  fachrichtung = 'softwareentwicklung'
  zielrollen = @('Frontend-Entwickler', 'Backend-Entwickler', 'Fullstack-Entwickler')
  datum = $Datum
  bewerberDateiname = $fileNamePerson
  pfadModus = 'relativ_zu_bewerbungen_root'
  zielOrdner = '_Universal-Lebenslauf/Aktiv'
  arbeitsOrdner = $workRelative
  kandidatOrdner = "$workRelative/Kandidat"
  dokumentmodus = 'individuelle_auswahl'
  dokumentumfang = [ordered]@{
    kennung = 'universal_lebenslauf'
    bestaetigt = $true
    lebenslauf = 'individuell'
    anschreiben = $false
    emailNachricht = $false
  }
  seitenstrategie = [ordered]@{
    typ = 'zwei_seiten_semantisch'
    abschnitteAtomar = $true
    seite1 = @('kurzprofil', 'technologien', 'projekte')
    seite2 = @('berufserfahrung', 'weiterbildung', 'ausbildung', 'schulbildung')
  }
  sourceInputs = [ordered]@{
    stammdaten = [ordered]@{ name = [IO.Path]::GetFileName($stammdaten); sha256 = (Get-FileHash -LiteralPath $stammdaten -Algorithm SHA256).Hash }
    profil = [ordered]@{ name = [IO.Path]::GetFileName($profil); sha256 = (Get-FileHash -LiteralPath $profil -Algorithm SHA256).Hash }
  }
  status = 'dokumenterstellung'
  createdAtUtc = [datetime]::UtcNow.ToString('o')
}
Set-Content -LiteralPath $orderPath -Encoding UTF8 -Value ($order | ConvertTo-Json -Depth 8)

$positioning = @"
# Positionierungsgrundlage für den universellen Lebenslauf

Dieser Auftrag bezieht sich auf keine konkrete Stellenanzeige und keinen Arbeitgeber. Der Lebenslauf soll ausschließlich für offene Stellen in der Softwareentwicklung als Frontend-, Backend- oder Fullstack-Entwickler einsetzbar sein.

## Verbindliche Abgrenzung

- Schwerpunkt: Softwareentwicklung
- Kein Schwerpunkt: IT-Administration
- Persönliche und fachliche Tatsachen ausschließlich aus den gebundenen privaten Stammdaten und dem Bewerberprofil
- Status: [ergänzen und fachlich abschließen]
"@
$analysis = @"
# Analyse

## Recruiter-Strategie

[ergänzen: Belegstrategie, Priorisierung und Begründung der semantischen Seitenverteilung]

## Seitenplan

- Seite 1: Kurzprofil, Technologien und sämtliche relevanten Entwicklungsprojekte
- Seite 2: vollständige Berufserfahrung sowie vollständige Weiterbildung, Ausbildung und Schulbildung
"@
$quality = @"
# Qualitätscheck

- Wahrheits- und Profilabgleich: [ergänzen]
- Softwareentwicklung klar vor IT-Administration positioniert: [ergänzen]
- Alle fachlichen Abschnitte vollständig auf genau einer Seite: [ergänzen]
- Recruiter-freundliche Seitenverteilung persönlich geprüft: [ergänzen]
"@
$printNote = @"
# Druck-Hinweis

Der Lebenslauf wird aus der eigenständigen HTML-Datei im verbindlichen Chromium-A4-Export bei 100 Prozent Skalierung erzeugt. Browser-Kopf- und Fußzeilen bleiben deaktiviert. Beide expliziten A4-Seiten müssen vor der Aktivierung anhand ihrer aktuellen PNG-Dateien persönlich geprüft werden.
"@
Set-Content -LiteralPath (Join-Path $candidate 'Stellenbeschreibung.md') -Encoding UTF8 -Value $positioning
Set-Content -LiteralPath (Join-Path $candidate 'Analyse.md') -Encoding UTF8 -Value $analysis
Set-Content -LiteralPath (Join-Path $candidate 'Qualitaetscheck.md') -Encoding UTF8 -Value $quality
Set-Content -LiteralPath (Join-Path $candidate 'Druck-Hinweis.md') -Encoding UTF8 -Value $printNote

Write-Host "[OK] Universal-Lebenslauf-Arbeitsordner angelegt: $work" -ForegroundColor Green
Write-Host "Kandidat: $candidate"
Write-Host "Erwartete HTML-Datei: $(Join-Path $candidate "Lebenslauf - $fileNamePerson.html")"
Write-Host 'Der finale Ordner unter _Universal-Lebenslauf/Aktiv wird erst nach technischer und persönlicher Freigabe angelegt.'
