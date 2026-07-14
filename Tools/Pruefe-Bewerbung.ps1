[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Ordner,

  [switch]$WarnungenAlsFehler
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$oks = New-Object System.Collections.Generic.List[string]

function Add-ErrorMessage {
  param([string]$Message)
  $errors.Add($Message) | Out-Null
  Write-Host "[FEHLER] $Message" -ForegroundColor Red
}

function Add-WarningMessage {
  param([string]$Message)
  $warnings.Add($Message) | Out-Null
  Write-Host "[WARNUNG] $Message" -ForegroundColor Yellow
}

function Add-OkMessage {
  param([string]$Message)
  $oks.Add($Message) | Out-Null
  Write-Host "[OK] $Message" -ForegroundColor Green
}

function Read-FileText {
  param([string]$Path)
  return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
}

function Test-Pattern {
  param(
    [string]$Text,
    [string]$Pattern
  )
  return [regex]::IsMatch($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

function Remove-CssComments {
  param([string]$Text)
  return [regex]::Replace($Text, '(?s)/\*.*?\*/', '')
}

function Get-CssRules {
  param([string]$Text)

  $cleanText = Remove-CssComments -Text $Text
  return [regex]::Matches(
    $cleanText,
    '(?s)(?<selector>[^{}]+)\{(?<body>[^{}]*)\}',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
  )
}

function Test-ExactCssProperty {
  param(
    [string]$Body,
    [string]$Property,
    [string]$ValuePattern
  )

  $propertyPattern = [regex]::Escape($Property)
  $pattern = "(?is)(?:^|;)\s*$propertyPattern\s*:\s*(?:$ValuePattern)(?:\s*!important)?\s*(?:;|$)"
  return [regex]::IsMatch($Body, $pattern)
}

function Test-IsOuterPageSelector {
  param([string]$Selector)

  $normalized = $Selector.Trim()
  return $normalized -match '^(?:main)?\.page(?:[.#][A-Za-z0-9_-]+|:{1,2}[A-Za-z0-9_-]+(?:\([^)]*\))?)*$'
}

function Get-TextBeforePrintMedia {
  param([string]$Text)
  $parts = [regex]::Split($Text, '@media\s+print', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  return $parts[0]
}

function Test-HasExactA4PageRule {
  param([string]$Text)

  foreach ($rule in (Get-CssRules -Text $Text)) {
    $body = $rule.Groups["body"].Value
    $hasGeometry = (Test-ExactCssProperty -Body $body -Property "width" -ValuePattern '210mm') -and
      (Test-ExactCssProperty -Body $body -Property "height" -ValuePattern '297mm')

    if (-not $hasGeometry) {
      continue
    }

    foreach ($selector in ($rule.Groups["selector"].Value -split ',')) {
      if (Test-IsOuterPageSelector -Selector $selector) {
        return $true
      }
    }
  }

  return $false
}

function Get-MainPageMatches {
  param([string]$Text)

  return [regex]::Matches(
    $Text,
    '(?is)<main\b(?=[^>]*\bclass\s*=\s*["''][^"'']*\bpage\b[^"'']*["''])[^>]*>(?<body>.*?)</main\s*>',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
  )
}

function Test-MultipageFooterContract {
  param(
    [object[]]$PageMatches,
    [string]$FileName
  )

  $expectedPages = $PageMatches.Count
  for ($index = 0; $index -lt $expectedPages; $index++) {
    $pageNumber = $index + 1
    $pageBody = $PageMatches[$index].Groups["body"].Value
    $footerPattern = '(?is)<footer\b[^>]*class\s*=\s*["''][^"'']*\bpage-footer\b[^"'']*["''][^>]*>.*?Seite\s+' + $pageNumber + '\s+von\s+' + $expectedPages + '.*?</footer\s*>'
    if (-not [regex]::IsMatch($pageBody, $footerPattern)) {
      Add-ErrorMessage "${FileName}: Seite $pageNumber enthält keinen festen Footer mit `Seite $pageNumber von $expectedPages`."
    }
  }
}

function Test-OverflowHiddenOnlyOnPage {
  param(
    [string]$Text,
    [string]$FileName
  )

  foreach ($rule in (Get-CssRules -Text $Text)) {
    $body = $rule.Groups["body"].Value
    if (-not (Test-ExactCssProperty -Body $body -Property "overflow" -ValuePattern 'hidden')) {
      continue
    }

    foreach ($selector in ($rule.Groups["selector"].Value -split ',')) {
      if (-not (Test-IsOuterPageSelector -Selector $selector)) {
        Add-ErrorMessage "${FileName}: `overflow: hidden` ist nicht direkt auf einem äußeren `.page`-Selektor gesetzt (Selektor: $($selector.Trim()))."
      }
    }
  }
}

function Test-NoExternalDependencies {
  param(
    [string]$Text,
    [string]$FileName
  )

  $patterns = @(
    @{ Pattern = '<script\b'; Description = 'Skript-Element' },
    @{ Pattern = '@import\b'; Description = 'CSS-Import' },
    @{ Pattern = '<base\b'; Description = 'Base-URL' },
    @{ Pattern = '(?is)<link\b[^>]*\bhref\s*='; Description = 'automatisch geladenes Link-Ziel' },
    @{ Pattern = '(?is)<(?:img|iframe|source|video|audio|embed|input)\b[^>]*\bsrc\s*=\s*(?!["'']?\s*data:)'; Description = 'automatisch geladene src-Ressource' },
    @{ Pattern = '(?is)<video\b[^>]*\bposter\s*=\s*(?!["'']?\s*data:)'; Description = 'automatisch geladenes Poster' },
    @{ Pattern = '(?is)<object\b[^>]*\bdata\s*=\s*(?!["'']?\s*data:)'; Description = 'automatisch geladenes Objekt' },
    @{ Pattern = '(?is)<(?:use|image)\b[^>]*\b(?:href|xlink:href)\s*=\s*(?!["'']?\s*(?:#|data:))'; Description = 'automatisch geladene SVG-Ressource' },
    @{ Pattern = '(?is)\bsrcset\s*='; Description = 'automatisch geladene srcset-Ressource' },
    @{ Pattern = '(?is)url\s*\(\s*(?!["'']?\s*data:)'; Description = 'automatisch geladene CSS-URL' },
    @{ Pattern = '(?is)<meta\b[^>]*http-equiv\s*=\s*["'']?refresh\b'; Description = 'automatische Weiterleitung' }
  )

  foreach ($entry in $patterns) {
    if ([regex]::IsMatch($Text, $entry.Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
      Add-ErrorMessage "${FileName}: $($entry.Description) ist nicht erlaubt."
    }
  }
}

function Test-HtmlFile {
  param([System.IO.FileInfo]$File)

  $text = Read-FileText -Path $File.FullName
  $name = $File.Name

  if ($text -notmatch '^(?:\uFEFF)?\s*<!doctype\s+html\s*>') {
    Add-ErrorMessage "${name}: Der HTML-Doctype fehlt am Dateianfang."
  }

  if (-not (Test-Pattern -Text $text -Pattern '<html\b[^>]*\blang\s*=\s*["'']de(?:-DE)?["'']')) {
    Add-ErrorMessage "${name}: `<html lang=`"de`">` fehlt."
  }

  if (-not (Test-Pattern -Text $text -Pattern '<style\b')) {
    Add-ErrorMessage "${name}: eingebettetes CSS im `<style>`-Block fehlt."
  }

  if (-not (Test-Pattern -Text $text -Pattern '@page\s*\{[^}]*\bsize\s*:\s*A4(?:\s+portrait)?')) {
    Add-ErrorMessage "${name}: `@page { size: A4; ... }` fehlt."
  }

  if (-not (Test-Pattern -Text $text -Pattern '@page\s*\{[^}]*\bmargin\s*:\s*0(?:\D|$)')) {
    Add-ErrorMessage "${name}: `@page` setzt nicht exakt `margin: 0`."
  }

  $screenCssText = Get-TextBeforePrintMedia -Text $text
  if (-not (Test-HasExactA4PageRule -Text $screenCssText)) {
    Add-ErrorMessage "${name}: `.page` enthält vor `@media print` keine feste A4-Geometrie mit exakt `width: 210mm` und `height: 297mm`."
  }

  $pageMatches = @(Get-MainPageMatches -Text $text)
  $pageCount = $pageMatches.Count
  if ($name -match '^Anschreiben - ') {
    if ($pageCount -ne 1) {
      Add-ErrorMessage "${name}: Ein Anschreiben muss genau einen expliziten A4-Seitencontainer enthalten; gefunden: $pageCount."
    } else {
      Add-OkMessage "${name}: genau ein expliziter A4-Seitencontainer gefunden."
    }
  } elseif ($name -match '^Lebenslauf - ') {
    if ($pageCount -notin @(1, 2)) {
      Add-ErrorMessage "${name}: Ein Lebenslauf muss einen oder zwei explizite A4-Seitencontainer enthalten; gefunden: $pageCount."
    } else {
      Add-OkMessage "${name}: $pageCount explizite A4-Seitencontainer gefunden."
      if ($pageCount -eq 2) {
        Test-MultipageFooterContract -PageMatches $pageMatches -FileName $name
      }
    }
  } elseif ($pageCount -eq 0) {
    Add-ErrorMessage "${name}: kein `<main class=`"page`">` gefunden."
  }

  Test-OverflowHiddenOnlyOnPage -Text $text -FileName $name
  Test-NoExternalDependencies -Text $text -FileName $name
}

if (-not (Test-Path -LiteralPath $Ordner -PathType Container)) {
  Write-Host "[FEHLER] Ordner existiert nicht oder ist kein Verzeichnis: $Ordner" -ForegroundColor Red
  exit 1
}

$resolvedFolder = (Resolve-Path -LiteralPath $Ordner).Path
Write-Host "Pruefe Bewerbung: $resolvedFolder"

if ($resolvedFolder -notmatch '[\\/]+Private[\\/]+Bewerbungen[\\/]+' ) {
  Add-WarningMessage "Der Ordner liegt nicht unter `Private/Bewerbungen/`. Bitte prüfen, ob dies beabsichtigt ist."
}

$fixedRequired = @(
  "Stellenbeschreibung.md",
  "Analyse.md",
  "Qualitaetscheck.md",
  "Druck-Hinweis.md"
)

foreach ($fileName in $fixedRequired) {
  $path = Join-Path -Path $resolvedFolder -ChildPath $fileName
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    Add-ErrorMessage "Pflichtdatei fehlt oder ist keine Datei: $fileName"
    continue
  }

  $info = Get-Item -LiteralPath $path
  if ($info.Length -eq 0) {
    Add-ErrorMessage "Pflichtdatei ist leer: $fileName"
  } else {
    Add-OkMessage "Pflichtdatei vorhanden und nicht leer: $fileName"
  }
}

$allFiles = @(Get-ChildItem -LiteralPath $resolvedFolder -File)
$htmlFiles = @($allFiles | Where-Object { $_.Extension -ieq ".html" })
$markdownFiles = @($allFiles | Where-Object { $_.Extension -ieq ".md" })

$draftFiles = @($allFiles | Where-Object { $_.Name -match 'ENTWURF|DOKUMENT NOCH NICHT FINAL' })
foreach ($draft in $draftFiles) {
  Add-ErrorMessage "Entwurfsdatei im finalen Ordner gefunden: $($draft.Name)"
}

$personPattern = '[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z0-9][A-Za-z0-9.-]*'
$cvFiles = @($htmlFiles | Where-Object { $_.Name -match "^Lebenslauf - $personPattern\.html$" })
$letterFiles = @($htmlFiles | Where-Object { $_.Name -match "^Anschreiben - $personPattern\.html$" })
$emailFiles = @($markdownFiles | Where-Object { $_.Name -match '^Email-Nachricht--[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*\.md$' })

$unexpectedHtml = @($htmlFiles | Where-Object { ($_ -notin $cvFiles) -and ($_ -notin $letterFiles) })
foreach ($html in $unexpectedHtml) {
  Add-ErrorMessage "Unerwartete oder falsch benannte HTML-Datei im finalen Ordner: $($html.Name)"
}

if ($cvFiles.Count -eq 1) {
  Add-OkMessage "Lebenslauf-Datei gefunden: $($cvFiles[0].Name)"
} elseif ($cvFiles.Count -eq 0) {
  Add-ErrorMessage "Keine finale Lebenslauf-HTML nach Schema `Lebenslauf - NACHNAME.VORNAME.html` gefunden."
} else {
  Add-ErrorMessage "Mehrere finale Lebenslauf-HTML-Dateien gefunden: $($cvFiles.Name -join ', ')"
}

if ($letterFiles.Count -eq 1) {
  Add-OkMessage "Anschreiben-Datei gefunden: $($letterFiles[0].Name)"
} elseif ($letterFiles.Count -eq 0) {
  Add-ErrorMessage "Keine finale Anschreiben-HTML nach Schema `Anschreiben - NACHNAME.VORNAME.html` gefunden."
} else {
  Add-ErrorMessage "Mehrere finale Anschreiben-HTML-Dateien gefunden: $($letterFiles.Name -join ', ')"
}

if (($cvFiles.Count -eq 1) -and ($letterFiles.Count -eq 1)) {
  $cvNamePart = $cvFiles[0].BaseName -replace '^Lebenslauf - ', ''
  $letterNamePart = $letterFiles[0].BaseName -replace '^Anschreiben - ', ''
  if ($cvNamePart -ceq $letterNamePart) {
    Add-OkMessage "Lebenslauf und Anschreiben verwenden denselben Bewerbernamen: $cvNamePart"
  } else {
    Add-ErrorMessage "Lebenslauf und Anschreiben verwenden unterschiedliche Bewerbernamen: `$cvNamePart` vs. `$letterNamePart`."
  }
}

if ($emailFiles.Count -eq 1) {
  Add-OkMessage "E-Mail-Nachricht gefunden: $($emailFiles[0].Name)"
} elseif ($emailFiles.Count -eq 0) {
  Add-ErrorMessage "Keine E-Mail-Nachricht nach Schema `Email-Nachricht--FIRMA.md` gefunden."
} else {
  Add-ErrorMessage "Mehrere E-Mail-Nachrichten gefunden: $($emailFiles.Name -join ', ')"
}

$markerPatterns = @(
  '\{\{',
  '\}\}',
  '\[[^\]\r\n]*(ergänzen|optional|Zeitraum|Name aus|Platzhalter|hier einfügen)[^\]\r\n]*\]',
  '\[(Name|Rolle|Firma|Vorname|Nachname|Adresse|Telefon|E-Mail|Email)\]',
  '\bTODO\b',
  'DOKUMENT NOCH NICHT FINAL'
)

$scanFiles = @($allFiles | Where-Object { ($_.Extension -in @(".html", ".md")) -and ($_.Name -ne "Stellenbeschreibung.md") })
foreach ($file in $scanFiles) {
  $text = Read-FileText -Path $file.FullName
  foreach ($pattern in $markerPatterns) {
    if (Test-Pattern -Text $text -Pattern $pattern) {
      Add-ErrorMessage "$($file.Name): sichtbarer Platzhalter oder Entwurfsmarker gefunden ($pattern)."
    }
  }
}

foreach ($html in $htmlFiles) {
  Test-HtmlFile -File $html
}

if ($emailFiles.Count -eq 1) {
  $emailText = Read-FileText -Path $emailFiles[0].FullName
  $firstLine = ($emailText -split "`r?`n", 2)[0].TrimStart([char]0xFEFF)
  if ($firstLine -notmatch '^Betreff:\s*\S') {
    Add-ErrorMessage "$($emailFiles[0].Name): Die erste Zeile muss mit `Betreff: ` beginnen und einen konkreten Betreff enthalten."
  } elseif ($firstLine -notmatch '(?i)Bewerbung') {
    Add-ErrorMessage "$($emailFiles[0].Name): Der Betreff muss einen Bewerbungsbegriff enthalten."
  } else {
    Add-OkMessage "E-Mail-Nachricht enthält eine konkrete Betreffzeile."
  }

  $nonEmptyLines = @($emailText -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
  if ($nonEmptyLines -le 10) {
    Add-OkMessage "E-Mail-Nachricht ist kompakt ($nonEmptyLines nicht-leere Zeilen)."
  } else {
    Add-WarningMessage "E-Mail-Nachricht ist ungewöhnlich lang ($nonEmptyLines nicht-leere Zeilen)."
  }
}

Write-Host ""
Write-Host "Zusammenfassung:"
Write-Host "OK: $($oks.Count)"
Write-Host "Warnungen: $($warnings.Count)"
Write-Host "Fehler: $($errors.Count)"

if ($errors.Count -gt 0) {
  Write-Host "ERGEBNIS: FEHLER" -ForegroundColor Red
  exit 1
}

if (($warnings.Count -gt 0) -and $WarnungenAlsFehler) {
  Write-Host "ERGEBNIS: WARNUNGEN ALS FEHLER" -ForegroundColor Red
  exit 1
}

Write-Host "ERGEBNIS: OK" -ForegroundColor Green
exit 0
