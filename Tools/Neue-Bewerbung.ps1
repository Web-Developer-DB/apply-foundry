[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Firma,

  [string]$Rolle = "Bewerbung",

  [string]$Datum = (Get-Date -Format "yyyy-MM-dd"),

  [string]$StellenbeschreibungPath,

  [string]$StammdatenPath = (Join-Path -Path $PSScriptRoot -ChildPath "..\Private\Daten\01_PERSOENLICHE_DATEN.md"),

  [string]$BewerbungenRoot = (Join-Path -Path $PSScriptRoot -ChildPath "..\Private\Bewerbungen"),

  [switch]$Fortsetzen,

  [switch]$StammdatenpruefungUeberspringen
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Convert-ToSlug {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Value
  )

  $slug = $Value.Trim()
  $replacements = @(
    @{ From = "ä"; To = "ae" }
    @{ From = "ö"; To = "oe" }
    @{ From = "ü"; To = "ue" }
    @{ From = "Ä"; To = "Ae" }
    @{ From = "Ö"; To = "Oe" }
    @{ From = "Ü"; To = "Ue" }
    @{ From = "ß"; To = "ss" }
    @{ From = "&"; To = "und" }
  )

  foreach ($replacement in $replacements) {
    $slug = $slug.Replace($replacement.From, $replacement.To)
  }

  $slug = $slug -replace "[^A-Za-z0-9]+", "-"
  $slug = $slug.Trim("-")

  if ([string]::IsNullOrWhiteSpace($slug)) {
    return "Unbekannt"
  }

  return $slug
}

function Stop-WithValidationError {
  param([string]$Message)
  Write-Host "[FEHLER] $Message" -ForegroundColor Red
  exit 2
}

function Test-IsSafeChildPath {
  param(
    [string]$Candidate,
    [string]$Root
  )

  $candidateFull = [System.IO.Path]::GetFullPath($Candidate).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  return $candidateFull.StartsWith($rootFull + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-MarkdownField {
  param([string]$Path, [string]$Name)

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return ""
  }
  foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
    if ($line -match '^\s*-\s*(?<key>[^:]+):\s*(?<value>.*)$' -and $Matches.key.Trim() -eq $Name) {
      return $Matches.value.Trim()
    }
  }
  return ""
}

function Invoke-RequiredTool {
  param([string]$ScriptPath, [string[]]$Arguments)

  $powerShellExe = (Get-Process -Id $PID).Path
  & $powerShellExe -NoProfile -File $ScriptPath @Arguments
  if ($LASTEXITCODE -ne 0) {
    Stop-WithValidationError -Message "Vorprüfung fehlgeschlagen: $ScriptPath"
  }
}

$Firma = $Firma.Trim()
$Rolle = $Rolle.Trim()
if ([string]::IsNullOrWhiteSpace($Firma)) {
  Stop-WithValidationError -Message "Der Parameter -Firma darf nicht leer sein."
}
if ([string]::IsNullOrWhiteSpace($Rolle)) {
  Stop-WithValidationError -Message "Der Parameter -Rolle darf nicht leer sein."
}
if (($Firma.Length -gt 120) -or ($Rolle.Length -gt 120)) {
  Stop-WithValidationError -Message "Firma und Rolle dürfen jeweils höchstens 120 Zeichen lang sein."
}
if (($Firma -match '[\x00-\x1F\x7F]') -or ($Rolle -match '[\x00-\x1F\x7F]')) {
  Stop-WithValidationError -Message "Firma und Rolle dürfen keine Steuerzeichen oder Zeilenumbrüche enthalten."
}

$parsedDate = [datetime]::MinValue
$dateIsValid = [datetime]::TryParseExact(
  $Datum,
  "yyyy-MM-dd",
  [System.Globalization.CultureInfo]::InvariantCulture,
  [System.Globalization.DateTimeStyles]::None,
  [ref]$parsedDate
)
if (-not $dateIsValid) {
  Stop-WithValidationError -Message "Der Parameter -Datum muss ein echtes Kalenderdatum im Format YYYY-MM-DD sein."
}

if ($StellenbeschreibungPath) {
  if (-not (Test-Path -LiteralPath $StellenbeschreibungPath -PathType Leaf)) {
    Stop-WithValidationError -Message "StellenbeschreibungPath muss auf eine vorhandene Datei zeigen: $StellenbeschreibungPath"
  }
  $StellenbeschreibungPath = (Resolve-Path -LiteralPath $StellenbeschreibungPath).Path
}

if (-not $StammdatenpruefungUeberspringen) {
  $stammdatenChecker = Join-Path -Path $PSScriptRoot -ChildPath "Pruefe-Stammdaten.ps1"
  if (-not (Test-Path -LiteralPath $stammdatenChecker -PathType Leaf)) {
    Stop-WithValidationError -Message "Stammdatenprüfer fehlt: $stammdatenChecker"
  }
  Invoke-RequiredTool -ScriptPath $stammdatenChecker -Arguments @("-StammdatenPath", $StammdatenPath)
}

$bewerbungenRootFull = [System.IO.Path]::GetFullPath($BewerbungenRoot)
if ((Test-Path -LiteralPath $bewerbungenRootFull) -and -not (Test-Path -LiteralPath $bewerbungenRootFull -PathType Container)) {
  Stop-WithValidationError -Message "BewerbungenRoot existiert, ist aber kein Ordner: $bewerbungenRootFull"
}

$firmaSlug = Convert-ToSlug -Value $Firma
$rolleSlug = Convert-ToSlug -Value $Rolle
$firmaHtml = [System.Net.WebUtility]::HtmlEncode($Firma)
$rolleHtml = [System.Net.WebUtility]::HtmlEncode($Rolle)

$firmaDir = Join-Path -Path $bewerbungenRootFull -ChildPath $firmaSlug
$zielDir = Join-Path -Path $firmaDir -ChildPath "$Datum--$rolleSlug"
$arbeitsDir = Join-Path -Path (Join-Path -Path $firmaDir -ChildPath "_Arbeitsdateien") -ChildPath "$Datum--$rolleSlug"
$kandidatDir = Join-Path -Path $arbeitsDir -ChildPath "Kandidat"

if (-not (Test-IsSafeChildPath -Candidate $zielDir -Root $bewerbungenRootFull) -or -not (Test-IsSafeChildPath -Candidate $arbeitsDir -Root $bewerbungenRootFull) -or -not (Test-IsSafeChildPath -Candidate $kandidatDir -Root $arbeitsDir)) {
  Stop-WithValidationError -Message "Berechneter Zielpfad liegt außerhalb von BewerbungenRoot."
}

foreach ($path in @($zielDir, $arbeitsDir)) {
  if ((Test-Path -LiteralPath $path) -and -not (Test-Path -LiteralPath $path -PathType Container)) {
    Stop-WithValidationError -Message "Bewerbungspfad existiert, ist aber kein Ordner: $path"
  }
}

$zielExisted = Test-Path -LiteralPath $zielDir -PathType Container
$arbeitsExisted = Test-Path -LiteralPath $arbeitsDir -PathType Container
if (($zielExisted -or $arbeitsExisted) -and -not $Fortsetzen) {
  Stop-WithValidationError -Message "Die Bewerbung existiert bereits. Verwende -Fortsetzen nur für exakt dieselbe Bewerbung oder wähle Datum/Rolle eindeutig."
}

if ($Fortsetzen -and ($zielExisted -xor $arbeitsExisted)) {
  Stop-WithValidationError -Message "Die vorhandene Bewerbung ist unvollständig: Ziel- und Arbeitsordner müssen beide existieren. Fortsetzen wurde verweigert."
}

if ($Fortsetzen -and $arbeitsExisted) {
  $existingNotes = Join-Path -Path $arbeitsDir -ChildPath "Arbeitsnotizen.md"
  if (-not (Test-Path -LiteralPath $existingNotes -PathType Leaf)) {
    Stop-WithValidationError -Message "Der vorhandene Arbeitsordner enthält keine prüfbaren Arbeitsnotizen. Fortsetzen wurde verweigert."
  }

  $noteLines = @(Get-Content -LiteralPath $existingNotes -Encoding UTF8)
  if (($noteLines -notcontains "- Firma: $Firma") -or ($noteLines -notcontains "- Zielrolle: $Rolle")) {
    Stop-WithValidationError -Message "Der vorhandene Arbeitsordner gehört zu einer anderen Firma oder Rolle. Fortsetzen wurde verweigert."
  }
}

$zielCreated = -not $zielExisted
$arbeitsCreated = -not $arbeitsExisted
$kandidatCreated = -not (Test-Path -LiteralPath $kandidatDir -PathType Container)

try {
  if ($zielCreated) {
    New-Item -Path $zielDir -ItemType Directory | Out-Null
  }
  if ($arbeitsCreated) {
    New-Item -Path $arbeitsDir -ItemType Directory | Out-Null
  }
  if ($kandidatCreated) {
    New-Item -Path $kandidatDir -ItemType Directory | Out-Null
  }

$stellenbeschreibungKandidatFile = Join-Path -Path $kandidatDir -ChildPath "Stellenbeschreibung.md"
$stellenbeschreibungEntwurfFile = Join-Path -Path $arbeitsDir -ChildPath "Stellenbeschreibung--ENTWURF.md"
$analyseEntwurfFile = Join-Path -Path $arbeitsDir -ChildPath "Analyse--ENTWURF.md"
$lebenslaufEntwurfFile = Join-Path -Path $arbeitsDir -ChildPath "Lebenslauf--$firmaSlug--ENTWURF.html"
$anschreibenEntwurfFile = Join-Path -Path $arbeitsDir -ChildPath "Anschreiben--$firmaSlug--ENTWURF.html"
$arbeitsnotizenFile = Join-Path -Path $arbeitsDir -ChildPath "Arbeitsnotizen.md"
$emailEntwurfFile = Join-Path -Path $arbeitsDir -ChildPath "Email-Nachricht--$firmaSlug--ENTWURF.md"
$qualitaetscheckEntwurfFile = Join-Path -Path $arbeitsDir -ChildPath "Qualitaetscheck--ENTWURF.md"
$offeneFragenEntwurfFile = Join-Path -Path $arbeitsDir -ChildPath "Offene_Fragen--ENTWURF.md"
$anforderungsmatrixEntwurfFile = Join-Path -Path $arbeitsDir -ChildPath "Anforderungsmatrix--ENTWURF.json"
$auftragFile = Join-Path -Path $arbeitsDir -ChildPath "Bewerbungsauftrag.json"
$druckHinweisFile = Join-Path -Path $kandidatDir -ChildPath "Druck-Hinweis.md"

if ((Test-Path -LiteralPath $stellenbeschreibungKandidatFile) -and -not (Test-Path -LiteralPath $stellenbeschreibungKandidatFile -PathType Leaf)) {
  throw "Stellenbeschreibung.md existiert, ist aber keine reguläre Datei."
}

if ($StellenbeschreibungPath) {
  if (Test-Path -LiteralPath $stellenbeschreibungKandidatFile -PathType Leaf) {
    $sourceHash = (Get-FileHash -LiteralPath $StellenbeschreibungPath -Algorithm SHA256).Hash
    $targetHash = (Get-FileHash -LiteralPath $stellenbeschreibungKandidatFile -Algorithm SHA256).Hash
    if ($sourceHash -ne $targetHash) {
      throw "Eine andere Stellenbeschreibung liegt bereits im Kandidatenordner. Überschreiben wurde verweigert."
    }
  } else {
    Copy-Item -LiteralPath $StellenbeschreibungPath -Destination $stellenbeschreibungKandidatFile
  }
} elseif (-not (Test-Path -LiteralPath $stellenbeschreibungKandidatFile) -and -not (Test-Path -LiteralPath $stellenbeschreibungEntwurfFile)) {
  Set-Content -LiteralPath $stellenbeschreibungEntwurfFile -Encoding UTF8 -Value @"
# Stellenbeschreibung

[Stellenbeschreibung hier einfügen]
"@
}

if (-not (Test-Path -LiteralPath $auftragFile -PathType Leaf)) {
  $applicantFileName = Get-MarkdownField -Path $StammdatenPath -Name "Dateiname-Name"
  $auftrag = [ordered]@{
    schemaVersion = 1
    firma = $Firma
    firmaSlug = $firmaSlug
    rolle = $Rolle
    rolleSlug = $rolleSlug
    datum = $Datum
    bewerberDateiname = $applicantFileName
    zielOrdner = $zielDir
    arbeitsOrdner = $arbeitsDir
    kandidatOrdner = $kandidatDir
    seitenstrategie = "noch_festzulegen"
    createdAtUtc = [datetime]::UtcNow.ToString("o")
  }
  Set-Content -LiteralPath $auftragFile -Encoding UTF8 -Value ($auftrag | ConvertTo-Json -Depth 5)
}

if (-not (Test-Path -LiteralPath $anforderungsmatrixEntwurfFile)) {
  Set-Content -LiteralPath $anforderungsmatrixEntwurfFile -Encoding UTF8 -Value @"
{
  "schemaVersion": 1,
  "requirements": [
    {
      "id": "muss-1",
      "anforderung": "durch den Agenten aus der Stellenbeschreibung zu extrahieren",
      "typ": "muss",
      "status": "unklar",
      "belegart": "",
      "beleg": "",
      "behandlung": "vor Erstellung der Kandidatendateien klären"
    }
  ]
}
"@
}

if (-not (Test-Path -LiteralPath $analyseEntwurfFile)) {
  Set-Content -LiteralPath $analyseEntwurfFile -Encoding UTF8 -Value @"
# Analyse

- Firma: $Firma
- Zielrolle: $Rolle
- Datum: $Datum
- Profilstrategie: [nach Analyse ergänzen]
- Wichtigste Anforderungen: [ergänzen]
- Passende Bewerberargumente: [ergänzen]
- Bewusst weggelassene Inhalte: [ergänzen]
"@
}

if (-not (Test-Path -LiteralPath $lebenslaufEntwurfFile)) {
  Set-Content -LiteralPath $lebenslaufEntwurfFile -Encoding UTF8 -Value @"
<!doctype html>
<html lang="de">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Lebenslauf - Bewerber - $firmaHtml</title>
  <style>
    @page { size: A4; margin: 0; }
    * { box-sizing: border-box; }
    html, body { margin: 0; padding: 0; font-family: Arial, Helvetica, sans-serif; color: #101828; line-height: 1.4; }
    .page { width: 210mm; min-height: 297mm; margin: 0 auto; padding: 16mm; background: #fff; }
    .warning { padding: 8mm; border: 2px solid #b42318; color: #7a271a; background: #fff4ed; font-weight: 700; }
    @media print { html, body { width: 210mm; min-height: 297mm; margin: 0; padding: 0; background: #fff; } .page { width: 210mm; min-height: 297mm; margin: 0; box-shadow: none; } }
  </style>
</head>
<body>
  <main class="page">
    <h1>Lebenslauf - Arbeitsentwurf</h1>
    <p class="warning">DOKUMENT NOCH NICHT FINAL - durch den Agenten vollständig ersetzen.</p>
    <p>Firma: $firmaHtml</p>
    <p>Zielrolle: $rolleHtml</p>
    <p>Nutze die Regeln aus <code>Prompts/00_AGENTEN_START_HIER.md</code> und die neutrale Vorlage <code>Vorlagen/Designreferenz-Lebenslauf.html</code>.</p>
  </main>
</body>
</html>
"@
}

if (-not (Test-Path -LiteralPath $anschreibenEntwurfFile)) {
  Set-Content -LiteralPath $anschreibenEntwurfFile -Encoding UTF8 -Value @"
<!doctype html>
<html lang="de">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Anschreiben - Bewerber - $firmaHtml</title>
  <style>
    @page { size: A4; margin: 0; }
    * { box-sizing: border-box; }
    html, body { margin: 0; padding: 0; font-family: Arial, Helvetica, sans-serif; color: #101828; line-height: 1.4; }
    .page { width: 210mm; min-height: 297mm; margin: 0 auto; padding: 18mm; background: #fff; }
    .warning { padding: 8mm; border: 2px solid #b42318; color: #7a271a; background: #fff4ed; font-weight: 700; }
    @media print { html, body { width: 210mm; min-height: 297mm; margin: 0; padding: 0; background: #fff; } .page { width: 210mm; min-height: 297mm; margin: 0; box-shadow: none; } }
  </style>
</head>
<body>
  <main class="page">
    <h1>Anschreiben - Arbeitsentwurf</h1>
    <p class="warning">DOKUMENT NOCH NICHT FINAL - durch den Agenten vollständig ersetzen.</p>
    <p>Firma: $firmaHtml</p>
    <p>Zielrolle: $rolleHtml</p>
    <p>Nutze die Regeln aus <code>Prompts/00_AGENTEN_START_HIER.md</code> und die neutrale Vorlage <code>Vorlagen/Designreferenz-Anschreiben.html</code>.</p>
  </main>
</body>
</html>
"@
}

if (-not (Test-Path -LiteralPath $arbeitsnotizenFile)) {
  Set-Content -LiteralPath $arbeitsnotizenFile -Encoding UTF8 -Value @"
# Arbeitsnotizen

- Firma: $Firma
- Zielrolle: $Rolle
- Finaler Bewerbungsordner: $zielDir
- Entwurfs-/Arbeitsdateien: $arbeitsDir
- Kandidatendateien vor Freigabe: $kandidatDir

Dieser Ordner ist nur für temporäre Entwürfe und Arbeitsnotizen gedacht.
Versandfertig benannte Kandidatendateien gehören zunächst in den Kandidatenordner.
Der finale Bewerbungsordner bleibt bis zur erfolgreichen atomaren Veröffentlichung leer.
"@
}

if (-not (Test-Path -LiteralPath $emailEntwurfFile)) {
  Set-Content -LiteralPath $emailEntwurfFile -Encoding UTF8 -Value @"
Betreff: Bewerbung als $Rolle - [Name aus Private/Daten/01_PERSOENLICHE_DATEN.md]

Sehr geehrte Damen und Herren,

anbei sende ich Ihnen meine Bewerbungsunterlagen für die Position als $Rolle.

Über eine Rückmeldung freue ich mich.

Mit freundlichen Grüßen
[Name aus Private/Daten/01_PERSOENLICHE_DATEN.md]
"@
}

if (-not (Test-Path -LiteralPath $qualitaetscheckEntwurfFile)) {
  Set-Content -LiteralPath $qualitaetscheckEntwurfFile -Encoding UTF8 -Value @"
# Qualitätscheck

- [ ] Stellenbeschreibung analysiert
- [ ] Lebenslauf auf Zielrolle zugeschnitten
- [ ] Anschreiben individuell formuliert
- [ ] E-Mail-Nachricht erstellt
- [ ] Keine erfundenen Kenntnisse
- [ ] Keine sichtbaren Platzhalter in finalen Dokumenten
- [ ] Fehlende Daten in Offene_Fragen.md dokumentiert
- [ ] HTML/CSS druckfreundlich geprüft
"@
}

if (-not (Test-Path -LiteralPath $offeneFragenEntwurfFile)) {
  Set-Content -LiteralPath $offeneFragenEntwurfFile -Encoding UTF8 -Value @"
# Offene Fragen

- [ ] Fehlen Ansprechpartner oder Adresse?
- [ ] Sind genaue Zeiträume relevant?
- [ ] Gibt es einen gewünschten Eintrittstermin?
"@
}

if (-not (Test-Path -LiteralPath $druckHinweisFile)) {
  Set-Content -LiteralPath $druckHinweisFile -Encoding UTF8 -Value @"
# Druck-Hinweis

Wenn in Firefox Dateiname, URL, Datum oder Seitenzahl im Ausdruck erscheinen, kommt das aus dem Firefox-Druckdialog und nicht aus der HTML-Datei.

Vor dem finalen PDF-Export oder Druck:

1. HTML-Datei in Firefox öffnen.
2. `Strg + P` drücken.
3. `Weitere Einstellungen` öffnen.
4. `Kopf- und Fußzeilen drucken` deaktivieren.
5. Skalierung auf `100%` stellen.
6. Ränder auf `Keine` stellen.

Ziel: Die sichtbare A4-Seite im Browser soll ohne Firefox-Dateipfad, URL, Datum oder Seitenzahlen als PDF/Druck ausgegeben werden.
"@
}

Write-Output "Bewerbungsordner: $zielDir"
Write-Output "Arbeitsdateien: $arbeitsDir"
Write-Output "Kandidatendateien: $kandidatDir"
} catch {
  if ($kandidatCreated -and -not $arbeitsCreated -and (Test-Path -LiteralPath $kandidatDir -PathType Container) -and (Test-IsSafeChildPath -Candidate $kandidatDir -Root $arbeitsDir)) {
    Remove-Item -LiteralPath $kandidatDir -Recurse -Force -ErrorAction SilentlyContinue
  }
  if ($arbeitsCreated -and (Test-Path -LiteralPath $arbeitsDir -PathType Container) -and (Test-IsSafeChildPath -Candidate $arbeitsDir -Root $bewerbungenRootFull)) {
    Remove-Item -LiteralPath $arbeitsDir -Recurse -Force -ErrorAction SilentlyContinue
  }
  if ($zielCreated -and (Test-Path -LiteralPath $zielDir -PathType Container) -and (Test-IsSafeChildPath -Candidate $zielDir -Root $bewerbungenRootFull)) {
    Remove-Item -LiteralPath $zielDir -Recurse -Force -ErrorAction SilentlyContinue
  }
  Write-Host "[FEHLER] Bewerbungsstruktur konnte nicht vollständig erstellt werden: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}
