[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Firma,

  [string]$Rolle = "Bewerbung",

  [string]$Datum = (Get-Date -Format "yyyy-MM-dd"),

  [string]$StellenbeschreibungPath,

  [string]$BewerbungenRoot = (Join-Path -Path $PSScriptRoot -ChildPath "..\Private\Bewerbungen")
)

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

$firmaSlug = Convert-ToSlug -Value $Firma
$rolleSlug = Convert-ToSlug -Value $Rolle
$firmaHtml = [System.Net.WebUtility]::HtmlEncode($Firma)
$rolleHtml = [System.Net.WebUtility]::HtmlEncode($Rolle)
$bewerbungenRootFull = [System.IO.Path]::GetFullPath($BewerbungenRoot)

if ($Datum -notmatch '^\d{4}-\d{2}-\d{2}$') {
  Write-Host "[FEHLER] Der Parameter -Datum muss im Format YYYY-MM-DD angegeben werden." -ForegroundColor Red
  exit 2
}

if ($StellenbeschreibungPath -and -not (Test-Path -LiteralPath $StellenbeschreibungPath)) {
  Write-Host "[FEHLER] StellenbeschreibungPath existiert nicht: $StellenbeschreibungPath" -ForegroundColor Red
  exit 2
}

$firmaDir = Join-Path -Path $bewerbungenRootFull -ChildPath $firmaSlug
$zielDir = Join-Path -Path $firmaDir -ChildPath "$Datum--$rolleSlug"
$arbeitsDir = Join-Path -Path (Join-Path -Path $firmaDir -ChildPath "_Arbeitsdateien") -ChildPath "$Datum--$rolleSlug"

New-Item -Path $zielDir -ItemType Directory -Force | Out-Null
New-Item -Path $arbeitsDir -ItemType Directory -Force | Out-Null

$stellenbeschreibungFinalFile = Join-Path -Path $zielDir -ChildPath "Stellenbeschreibung.md"
$stellenbeschreibungEntwurfFile = Join-Path -Path $arbeitsDir -ChildPath "Stellenbeschreibung--ENTWURF.md"
$analyseEntwurfFile = Join-Path -Path $arbeitsDir -ChildPath "Analyse--ENTWURF.md"
$lebenslaufEntwurfFile = Join-Path -Path $arbeitsDir -ChildPath "Lebenslauf--$firmaSlug--ENTWURF.html"
$anschreibenEntwurfFile = Join-Path -Path $arbeitsDir -ChildPath "Anschreiben--$firmaSlug--ENTWURF.html"
$arbeitsnotizenFile = Join-Path -Path $arbeitsDir -ChildPath "Arbeitsnotizen.md"
$emailEntwurfFile = Join-Path -Path $arbeitsDir -ChildPath "Email-Nachricht--$firmaSlug--ENTWURF.md"
$qualitaetscheckEntwurfFile = Join-Path -Path $arbeitsDir -ChildPath "Qualitaetscheck--ENTWURF.md"
$offeneFragenEntwurfFile = Join-Path -Path $arbeitsDir -ChildPath "Offene_Fragen--ENTWURF.md"
$druckHinweisFile = Join-Path -Path $zielDir -ChildPath "Druck-Hinweis.md"

if ($StellenbeschreibungPath) {
  Copy-Item -LiteralPath $StellenbeschreibungPath -Destination $stellenbeschreibungFinalFile -Force
} elseif (-not (Test-Path -LiteralPath $stellenbeschreibungEntwurfFile)) {
  Set-Content -LiteralPath $stellenbeschreibungEntwurfFile -Encoding UTF8 -Value @"
# Stellenbeschreibung

[Stellenbeschreibung hier einfügen]
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

Dieser Ordner ist nur für temporäre Entwürfe und Arbeitsnotizen gedacht.
Finale Dateien gehören erst nach vollständiger Agentenprüfung in den finalen Bewerbungsordner.
"@
}

if (-not (Test-Path -LiteralPath $emailEntwurfFile)) {
  Set-Content -LiteralPath $emailEntwurfFile -Encoding UTF8 -Value @"
# E-Mail-Nachricht

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
