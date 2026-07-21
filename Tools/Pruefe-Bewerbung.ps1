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

function Test-PublicationManifest {
  param([string]$Root, [string]$ManifestPath)

  if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    Add-ErrorMessage "Strukturierte Veröffentlichung enthält kein Manifest.json."
    return
  }
  try {
    $errorCountBeforeManifest = $errors.Count
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $records = @($manifest.files)
    if ($records.Count -eq 0) {
      Add-ErrorMessage "Manifest.json enthält keine Dateinachweise."
      return
    }
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $manifestFull = (Resolve-Path -LiteralPath $ManifestPath).Path
    $actualFiles = @(Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object { $_.FullName -ne $manifestFull })
    if ($records.Count -ne $actualFiles.Count) {
      Add-ErrorMessage "Manifest-Dateizahl stimmt nicht mit der Veröffentlichung überein ($($records.Count) statt $($actualFiles.Count))."
    }
    $manifestPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($record in $records) {
      $relativePath = [string]$record.path
      if ([string]::IsNullOrWhiteSpace($relativePath) -or [System.IO.Path]::IsPathRooted($relativePath) -or $relativePath -match '(^|[\\/])\.\.([\\/]|$)') {
        Add-ErrorMessage "Manifest enthält einen ungültigen relativen Pfad: $relativePath"
        continue
      }
      $normalizedRelative = ($relativePath -replace '\\', '/').TrimStart('/')
      if (-not $manifestPaths.Add($normalizedRelative)) {
        Add-ErrorMessage "Manifest enthält einen doppelten Dateipfad: $relativePath"
        continue
      }
      $filePath = [System.IO.Path]::GetFullPath((Join-Path -Path $Root -ChildPath ($normalizedRelative -replace '/', [System.IO.Path]::DirectorySeparatorChar)))
      if (-not $filePath.StartsWith($rootFull + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        Add-ErrorMessage "Manifestpfad liegt außerhalb des Veröffentlichungsordners: $relativePath"
        continue
      }
      if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
        Add-ErrorMessage "Manifest-Datei fehlt: $relativePath"
        continue
      }
      $fileInfo = Get-Item -LiteralPath $filePath
      if ($null -ne $record.PSObject.Properties["bytes"] -and [long]$record.bytes -ne $fileInfo.Length) {
        Add-ErrorMessage "Manifest-Dateigröße stimmt nicht: $relativePath"
      }
      $actualHash = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash
      if ($actualHash -ne [string]$record.sha256) {
        Add-ErrorMessage "Manifest-Hash stimmt nicht: $relativePath"
      }
    }
    foreach ($actualFile in $actualFiles) {
      $actualRelative = [System.IO.Path]::GetRelativePath($Root, $actualFile.FullName).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
      if (-not $manifestPaths.Contains($actualRelative)) {
        Add-ErrorMessage "Veröffentlichte Datei fehlt im Manifest: $actualRelative"
      }
    }
    if ($errors.Count -eq $errorCountBeforeManifest) {
      Add-OkMessage "Manifest der strukturierten Veröffentlichung wurde vollständig geprüft."
    }
  } catch {
    Add-ErrorMessage "Manifest.json konnte nicht geprüft werden: $($_.Exception.Message)"
  }
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

$internalFolder = Join-Path -Path $resolvedFolder -ChildPath "Intern"
$shippingFolder = Join-Path -Path $resolvedFolder -ChildPath "Versand"
$isStructuredPublication = (Test-Path -LiteralPath $internalFolder -PathType Container) -and (Test-Path -LiteralPath $shippingFolder -PathType Container)
$documentFolder = if ($isStructuredPublication) { $internalFolder } else { $resolvedFolder }
$emailFolder = if ($isStructuredPublication) { $shippingFolder } else { $resolvedFolder }

$fixedRequired = @(
  "Stellenbeschreibung.md",
  "Analyse.md",
  "Qualitaetscheck.md",
  "Druck-Hinweis.md"
)

foreach ($fileName in $fixedRequired) {
  $path = Join-Path -Path $documentFolder -ChildPath $fileName
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

$documentFiles = @(Get-ChildItem -LiteralPath $documentFolder -File)
$emailAreaFiles = if ($isStructuredPublication) { @(Get-ChildItem -LiteralPath $emailFolder -File) } else { @() }
$allFiles = @($documentFiles + $emailAreaFiles)
$htmlFiles = @($documentFiles | Where-Object { $_.Extension -ieq ".html" })
$markdownFiles = @($allFiles | Where-Object { $_.Extension -ieq ".md" })

$draftFiles = @($allFiles | Where-Object { $_.Name -match 'ENTWURF|DOKUMENT NOCH NICHT FINAL' })
foreach ($draft in $draftFiles) {
  Add-ErrorMessage "Entwurfsdatei im finalen Ordner gefunden: $($draft.Name)"
}

$personPattern = '[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z0-9][A-Za-z0-9.-]*'
$cvFiles = @($htmlFiles | Where-Object { $_.Name -match "^Lebenslauf - $personPattern\.html$" })
$letterFiles = @($htmlFiles | Where-Object { $_.Name -match "^Anschreiben - $personPattern\.html$" })
$emailFiles = @(Get-ChildItem -LiteralPath $emailFolder -File -Filter "Email-Nachricht--*.md" | Where-Object { $_.Name -match '^Email-Nachricht--[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*\.md$' })

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

if ($isStructuredPublication) {
  $shippingPdfs = @(Get-ChildItem -LiteralPath $shippingFolder -File -Filter "*.pdf")
  $expectedShippingPdfs = @($shippingPdfs | Where-Object { $_.Name -match '^(Lebenslauf|Anschreiben) - .+\.pdf$' })
  if ($shippingPdfs.Count -ne 2 -or $expectedShippingPdfs.Count -ne 2) {
    Add-ErrorMessage "Versandordner muss genau Lebenslauf- und Anschreiben-PDF enthalten; gefunden: $($shippingPdfs.Name -join ', ')"
  } else {
    Add-OkMessage "Versandordner enthält genau die beiden vorgesehenen PDF-Anlagen."
  }
  $unexpectedShipping = @(Get-ChildItem -LiteralPath $shippingFolder -File | Where-Object {
    $_.Extension -notin @(".pdf", ".md") -or ($_.Extension -eq ".md" -and $_.Name -notmatch '^Email-Nachricht--')
  })
  if ($unexpectedShipping.Count -gt 0) {
    Add-ErrorMessage "Versandordner enthält interne oder unerwartete Dateien: $($unexpectedShipping.Name -join ', ')"
  }
  $internalPdfs = @(Get-ChildItem -LiteralPath $internalFolder -File -Filter "*.pdf")
  if ($internalPdfs.Count -gt 0) {
    Add-ErrorMessage "Interner Ordner enthält Versand-PDFs und erzeugt unnötige Dubletten: $($internalPdfs.Name -join ', ')"
  }
  Test-PublicationManifest -Root $resolvedFolder -ManifestPath (Join-Path $resolvedFolder "Manifest.json")
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
