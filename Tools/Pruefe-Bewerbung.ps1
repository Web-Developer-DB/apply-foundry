[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Ordner,

  [switch]$WarnungenAlsFehler
)

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

function Get-MainPageCount {
  param([string]$Text)
  $matches = [regex]::Matches($Text, '<main\b[^>]*class=["''][^"'']*\bpage\b[^"'']*["'']', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  return $matches.Count
}

function Test-HasA4PageRule {
  param([string]$Text)

  $pageBlocks = [regex]::Matches($Text, '(?s)\.page\s*\{(?<body>.*?)\}', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  foreach ($block in $pageBlocks) {
    $body = $block.Groups["body"].Value
    if ((Test-Pattern -Text $body -Pattern 'width\s*:\s*210mm') -and (Test-Pattern -Text $body -Pattern 'height\s*:\s*297mm')) {
      return $true
    }
  }

  return $false
}

function Get-TextBeforePrintMedia {
  param([string]$Text)
  $parts = [regex]::Split($Text, '@media\s+print', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  return $parts[0]
}

function Test-OverflowHiddenOnlyOnPage {
  param(
    [string]$Text,
    [string]$FileName
  )

  $ok = $true
  $ruleMatches = [regex]::Matches($Text, '(?s)(?<selector>[^{}]+)\{(?<body>[^{}]*overflow\s*:\s*hidden[^{}]*)\}', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

  foreach ($rule in $ruleMatches) {
    $selector = $rule.Groups["selector"].Value.Trim()
    if ($selector -notmatch '(^|,|\s)\.page(\b|[.#:\s,])') {
      Add-ErrorMessage "${FileName}: `overflow: hidden` ist nicht nur auf `.page` gesetzt (Selektor: $selector)."
      $ok = $false
    }
  }

  return $ok
}

function Test-HtmlFile {
  param([System.IO.FileInfo]$File)

  $text = Read-FileText -Path $File.FullName
  $name = $File.Name

  if (-not (Test-Pattern -Text $text -Pattern '<!doctype html>')) {
    Add-ErrorMessage "${name}: HTML-Datei beginnt nicht mit einem Doctype."
  }

  if (-not (Test-Pattern -Text $text -Pattern '<style\b')) {
    Add-ErrorMessage "${name}: eingebettetes CSS im `<style>`-Block fehlt."
  }

  if (-not (Test-Pattern -Text $text -Pattern '@page\s*\{[^}]*size\s*:\s*A4')) {
    Add-ErrorMessage "${name}: `@page { size: A4; ... }` fehlt."
  }

  if (-not (Test-Pattern -Text $text -Pattern '@page\s*\{[^}]*margin\s*:\s*0')) {
    Add-ErrorMessage "${name}: `@page` setzt nicht `margin: 0`."
  }

  $screenCssText = Get-TextBeforePrintMedia -Text $text
  if (-not (Test-HasA4PageRule -Text $screenCssText)) {
    Add-ErrorMessage "${name}: `.page` enthält vor `@media print` keine feste A4-Geometrie mit `width: 210mm` und `height: 297mm`."
  }

  $pageCount = Get-MainPageCount -Text $text
  if ($pageCount -eq 0) {
    Add-ErrorMessage "${name}: kein `<main class=`"page`">` gefunden."
  } elseif ($pageCount -eq 1) {
    Add-OkMessage "${name}: ein expliziter A4-Seitencontainer gefunden."
  } else {
    Add-OkMessage "${name}: $pageCount explizite A4-Seitencontainer gefunden."
  }

  Test-OverflowHiddenOnlyOnPage -Text $text -FileName $name | Out-Null

  $externalPatterns = @(
    '<script\b',
    '@import\s+url',
    'fonts\.googleapis',
    'fonts\.gstatic',
    'cdnjs',
    'unpkg',
    'jsdelivr',
    '\bsrc\s*=\s*["'']https?://'
  )

  foreach ($pattern in $externalPatterns) {
    if (Test-Pattern -Text $text -Pattern $pattern) {
      Add-ErrorMessage "${name}: mögliche externe Abhängigkeit gefunden (`$pattern`)."
    }
  }
}

if (-not (Test-Path -LiteralPath $Ordner)) {
  Write-Host "[FEHLER] Ordner existiert nicht: $Ordner" -ForegroundColor Red
  exit 1
}

$resolvedFolder = (Resolve-Path -LiteralPath $Ordner).Path
$folderInfo = Get-Item -LiteralPath $resolvedFolder

if (-not $folderInfo.PSIsContainer) {
  Write-Host "[FEHLER] Pfad ist kein Ordner: $resolvedFolder" -ForegroundColor Red
  exit 1
}

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
  if (Test-Path -LiteralPath $path) {
    Add-OkMessage "Pflichtdatei vorhanden: $fileName"
  } else {
    Add-ErrorMessage "Pflichtdatei fehlt: $fileName"
  }
}

$allFiles = Get-ChildItem -LiteralPath $resolvedFolder -File
$htmlFiles = $allFiles | Where-Object { $_.Extension -ieq ".html" }
$markdownFiles = $allFiles | Where-Object { $_.Extension -ieq ".md" }

$draftFiles = $allFiles | Where-Object { $_.Name -match 'ENTWURF|DOKUMENT NOCH NICHT FINAL' }
foreach ($draft in $draftFiles) {
  Add-ErrorMessage "Entwurfsdatei im finalen Ordner gefunden: $($draft.Name)"
}

$cvFiles = $htmlFiles | Where-Object { $_.Name -match '^Lebenslauf - .+\.html$' }
$letterFiles = $htmlFiles | Where-Object { $_.Name -match '^Anschreiben - .+\.html$' }
$emailFiles = $markdownFiles | Where-Object { $_.Name -match '^Email-Nachricht--.+\.md$' }

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
  if ($cvNamePart -eq $letterNamePart) {
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
  'TODO',
  'DOKUMENT NOCH NICHT FINAL'
)

$scanFiles = $allFiles | Where-Object { ($_.Extension -in @(".html", ".md")) -and ($_.Name -ne "Stellenbeschreibung.md") }
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
  $nonEmptyLines = ($emailText -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
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
