[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Ordner,

  [string]$StammdatenPath = (Join-Path -Path $PSScriptRoot -ChildPath "..\Private\Daten\01_PERSOENLICHE_DATEN.md"),

  [Parameter(Mandatory = $true)]
  [string]$AuftragPath,

  [ValidateRange(40, 100)]
  [int]$MinTextabdeckungProzent = 70,

  [string]$BerichtPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$oks = New-Object System.Collections.Generic.List[string]
$latin1 = [System.Text.Encoding]::GetEncoding(28591)

function Add-ErrorMessage { param([string]$Message) $errors.Add($Message) | Out-Null; Write-Host "[FEHLER] $Message" -ForegroundColor Red }
function Add-WarningMessage { param([string]$Message) $warnings.Add($Message) | Out-Null; Write-Host "[WARNUNG] $Message" -ForegroundColor Yellow }
function Add-OkMessage { param([string]$Message) $oks.Add($Message) | Out-Null; Write-Host "[OK] $Message" -ForegroundColor Green }

function Get-JsonProperty {
  param([object]$Object, [string]$Name)
  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

function Get-MarkdownFields {
  param([string]$Path)
  $result = [ordered]@{}
  foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
    if ($line -match '^\s*-\s*(?<key>[^:]+):\s*(?<value>.*)$' -and -not $result.Contains($Matches.key.Trim())) {
      $result[$Matches.key.Trim()] = $Matches.value.Trim()
    }
  }
  return $result
}

function Convert-HtmlToText {
  param([string]$Html)
  $text = [regex]::Replace($Html, '(?is)<head\b[^>]*>.*?</head>', ' ')
  $text = [regex]::Replace($text, '(?is)<script\b[^>]*>.*?</script>', ' ')
  $text = [regex]::Replace($text, '(?is)<style\b[^>]*>.*?</style>', ' ')
  $text = [regex]::Replace($text, '(?is)<[^>]+>', ' ')
  return [System.Net.WebUtility]::HtmlDecode($text)
}

function Normalize-Text {
  param([AllowEmptyString()][string]$Text)
  if ($null -eq $Text) { return "" }
  $normalized = $Text.Replace([char]0x2013, '-').Replace([char]0x2014, '-').Replace([char]0x00A0, ' ')
  $normalized = [regex]::Replace($normalized, '\s+', ' ')
  return $normalized.Trim().ToLowerInvariant()
}

function Get-ComparableLength {
  param([string]$Text)
  return ([regex]::Replace((Normalize-Text -Text $Text), '[^\p{L}\p{N}]', '')).Length
}

function Convert-HexToUnicode {
  param([string]$Hex)
  if ([string]::IsNullOrWhiteSpace($Hex) -or ($Hex.Length % 2 -ne 0)) { return "" }
  $bytes = New-Object byte[] ($Hex.Length / 2)
  for ($index = 0; $index -lt $bytes.Length; $index++) {
    $bytes[$index] = [Convert]::ToByte($Hex.Substring($index * 2, 2), 16)
  }
  if ($bytes.Length -eq 1) { return [char]$bytes[0] }
  return [System.Text.Encoding]::BigEndianUnicode.GetString($bytes)
}

function Get-PdfObjects {
  param([string]$Path)
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $text = $latin1.GetString($bytes)
  $objects = @{}
  foreach ($match in [regex]::Matches($text, '(?s)(?<number>\d+)\s+\d+\s+obj(?<body>.*?)endobj')) {
    $number = [int]$match.Groups["number"].Value
    $objects[$number] = $match.Groups["body"].Value
  }
  return [pscustomobject]@{ Bytes = $bytes; Text = $text; Objects = $objects }
}

function Get-DecodedPdfStream {
  param([string]$ObjectBody)
  $streamMatch = [regex]::Match($ObjectBody, '(?s)stream\r?\n(?<data>.*?)\r?\nendstream')
  if (-not $streamMatch.Success) { return "" }
  $rawBytes = $latin1.GetBytes($streamMatch.Groups["data"].Value)
  if ($ObjectBody -notmatch '/FlateDecode') {
    return $latin1.GetString($rawBytes)
  }
  try {
    $input = [System.IO.MemoryStream]::new($rawBytes)
    $zlib = [System.IO.Compression.ZLibStream]::new($input, [System.IO.Compression.CompressionMode]::Decompress)
    $output = [System.IO.MemoryStream]::new()
    $zlib.CopyTo($output)
    $zlib.Dispose()
    $input.Dispose()
    $decoded = $latin1.GetString($output.ToArray())
    $output.Dispose()
    return $decoded
  } catch {
    throw "Komprimierter PDF-Textstrom konnte nicht gelesen werden: $($_.Exception.Message)"
  }
}

function Get-CMap {
  param([string]$CMapText)
  $map = @{}
  foreach ($match in [regex]::Matches($CMapText, '(?im)^\s*<(?<source>[0-9A-Fa-f]+)>\s*<(?<target>[0-9A-Fa-f]+)>\s*$')) {
    $map[$match.Groups["source"].Value.ToUpperInvariant()] = Convert-HexToUnicode -Hex $match.Groups["target"].Value
  }
  foreach ($match in [regex]::Matches($CMapText, '(?im)^\s*<(?<start>[0-9A-Fa-f]+)>\s*<(?<end>[0-9A-Fa-f]+)>\s*<(?<target>[0-9A-Fa-f]+)>\s*$')) {
    $start = [Convert]::ToInt32($match.Groups["start"].Value, 16)
    $end = [Convert]::ToInt32($match.Groups["end"].Value, 16)
    $target = [Convert]::ToInt32($match.Groups["target"].Value, 16)
    $sourceWidth = $match.Groups["start"].Value.Length
    $targetWidth = $match.Groups["target"].Value.Length
    for ($code = $start; $code -le $end; $code++) {
      $sourceHex = $code.ToString("X$sourceWidth")
      $targetHex = ($target + ($code - $start)).ToString("X$targetWidth")
      $map[$sourceHex] = Convert-HexToUnicode -Hex $targetHex
    }
  }
  foreach ($match in [regex]::Matches($CMapText, '(?ims)<(?<start>[0-9A-Fa-f]+)>\s*<(?<end>[0-9A-Fa-f]+)>\s*\[(?<targets>.*?)\]')) {
    $start = [Convert]::ToInt32($match.Groups["start"].Value, 16)
    $sourceWidth = $match.Groups["start"].Value.Length
    $targets = @([regex]::Matches($match.Groups["targets"].Value, '<(?<value>[0-9A-Fa-f]+)>'))
    for ($index = 0; $index -lt $targets.Count; $index++) {
      $map[($start + $index).ToString("X$sourceWidth")] = Convert-HexToUnicode -Hex $targets[$index].Groups["value"].Value
    }
  }
  return $map
}

function Convert-PdfHexText {
  param([string]$Hex, [hashtable]$Map)
  if ([string]::IsNullOrWhiteSpace($Hex)) { return "" }
  $builder = [System.Text.StringBuilder]::new()
  $codeWidth = 4
  if ($Hex.Length % $codeWidth -ne 0) { $codeWidth = 2 }
  for ($index = 0; $index + $codeWidth -le $Hex.Length; $index += $codeWidth) {
    $code = $Hex.Substring($index, $codeWidth).ToUpperInvariant()
    if ($Map.ContainsKey($code)) {
      $null = $builder.Append([string]$Map[$code])
    } else {
      $fallback = Convert-HexToUnicode -Hex $code
      $null = $builder.Append($fallback)
    }
  }
  return $builder.ToString()
}

function Convert-PdfLiteralText {
  param([string]$Literal)
  $text = $Literal -replace '\\\(', '(' -replace '\\\)', ')' -replace '\\\\', '\'
  $text = $text -replace '\\n', "`n" -replace '\\r', "`r" -replace '\\t', "`t"
  return $text
}

function Get-ExtractedPdfText {
  param([string]$Path)

  $pdf = Get-PdfObjects -Path $Path
  if ($pdf.Objects.Count -eq 0) { throw "PDF enthält keine lesbaren Objekte." }

  $fontMapsByObject = @{}
  foreach ($fontObjectNumber in @($pdf.Objects.Keys | Sort-Object { [int]$_ })) {
    $fontBody = [string]$pdf.Objects[$fontObjectNumber]
    $toUnicode = [regex]::Match($fontBody, '/ToUnicode\s+(?<object>\d+)\s+0\s+R')
    if ($toUnicode.Success) {
      $cmapObjectNumber = [int]$toUnicode.Groups["object"].Value
      if ($pdf.Objects.Contains($cmapObjectNumber)) {
        $fontMapsByObject[[int]$fontObjectNumber] = Get-CMap -CMapText (Get-DecodedPdfStream -ObjectBody ([string]$pdf.Objects[$cmapObjectNumber]))
      }
    }
  }
  if ($fontMapsByObject.Count -eq 0) { throw "PDF enthält keine auswertbare ToUnicode-Zuordnung." }

  $pageObjects = @()
  foreach ($objectNumber in @($pdf.Objects.Keys | Sort-Object { [int]$_ })) {
    $body = [string]$pdf.Objects[$objectNumber]
    if ($body -match '/Type\s*/Page(?!s)') {
      $pageObjects += [pscustomobject]@{ Number = [int]$objectNumber; Body = $body }
    }
  }
  if ($pageObjects.Count -eq 0) { throw "PDF enthält keine auswertbaren Seitenobjekte." }

  $documentBuilder = [System.Text.StringBuilder]::new()
  foreach ($page in $pageObjects) {
    $resourceFonts = @{}
    $fontDictionary = [regex]::Match($page.Body, '(?s)/Font\s*<<(?<fonts>.*?)>>')
    if ($fontDictionary.Success) {
      foreach ($fontRef in [regex]::Matches($fontDictionary.Groups["fonts"].Value, '/(?<name>[A-Za-z0-9]+)\s+(?<object>\d+)\s+0\s+R')) {
        $resourceFonts[$fontRef.Groups["name"].Value] = [int]$fontRef.Groups["object"].Value
      }
    }

    $contentObjects = @()
    $contentsArray = [regex]::Match($page.Body, '(?s)/Contents\s*\[(?<items>.*?)\]')
    if ($contentsArray.Success) {
      $contentObjects = @([regex]::Matches($contentsArray.Groups["items"].Value, '(?<object>\d+)\s+0\s+R') | ForEach-Object { [int]$_.Groups["object"].Value })
    } else {
      $singleContent = [regex]::Match($page.Body, '/Contents\s+(?<object>\d+)\s+0\s+R')
      if ($singleContent.Success) { $contentObjects = @([int]$singleContent.Groups["object"].Value) }
    }

    foreach ($contentObject in $contentObjects) {
      if (-not $pdf.Objects.Contains($contentObject)) { continue }
      $content = Get-DecodedPdfStream -ObjectBody ([string]$pdf.Objects[$contentObject])
      $currentMap = @{}
      foreach ($token in [regex]::Matches($content, '(?s)(?<bt>\bBT\b)|(?<et>\bET\b)|/(?<font>[A-Za-z0-9]+)\s+[-+0-9.]+\s+Tf|<(?<hex>[0-9A-Fa-f]+)>\s*Tj|\((?<literal>(?:\\.|[^\\)])*)\)\s*Tj|\[(?<array>.*?)\]\s*TJ')) {
        if ($token.Groups["font"].Success) {
          $fontName = $token.Groups["font"].Value
          if ($resourceFonts.ContainsKey($fontName) -and $fontMapsByObject.ContainsKey([int]$resourceFonts[$fontName])) {
            $currentMap = $fontMapsByObject[[int]$resourceFonts[$fontName]]
          }
        } elseif ($token.Groups["hex"].Success) {
          $null = $documentBuilder.Append((Convert-PdfHexText -Hex $token.Groups["hex"].Value -Map $currentMap))
        } elseif ($token.Groups["literal"].Success) {
          $null = $documentBuilder.Append((Convert-PdfLiteralText -Literal $token.Groups["literal"].Value))
        } elseif ($token.Groups["array"].Success) {
          foreach ($part in [regex]::Matches($token.Groups["array"].Value, '<(?<hex>[0-9A-Fa-f]+)>|\((?<literal>(?:\\.|[^\\)])*)\)')) {
            if ($part.Groups["hex"].Success) {
              $null = $documentBuilder.Append((Convert-PdfHexText -Hex $part.Groups["hex"].Value -Map $currentMap))
            } else {
              $null = $documentBuilder.Append((Convert-PdfLiteralText -Literal $part.Groups["literal"].Value))
            }
          }
        } elseif ($token.Groups["et"].Success) {
          $null = $documentBuilder.AppendLine()
        }
      }
    }
    $null = $documentBuilder.AppendLine()
  }
  return $documentBuilder.ToString()
}

foreach ($path in @($Ordner, $StammdatenPath, $AuftragPath)) {
  if (-not (Test-Path -LiteralPath $path)) {
    Write-Host "[FEHLER] Erforderlicher Pfad fehlt: $path" -ForegroundColor Red
    exit 1
  }
}

$resolvedFolder = (Resolve-Path -LiteralPath $Ordner).Path
$internalFolder = Join-Path $resolvedFolder "Intern"
$shippingFolder = Join-Path $resolvedFolder "Versand"
$structured = (Test-Path -LiteralPath $internalFolder -PathType Container) -and (Test-Path -LiteralPath $shippingFolder -PathType Container)
$htmlFolder = if ($structured) { $internalFolder } else { $resolvedFolder }
$pdfFolder = if ($structured) { $shippingFolder } else { $resolvedFolder }
$auftrag = Get-Content -LiteralPath $AuftragPath -Raw -Encoding UTF8 | ConvertFrom-Json
$auftragSchemaValue = Get-JsonProperty -Object $auftrag -Name "schemaVersion"
if ($auftragSchemaValue -isnot [int] -and $auftragSchemaValue -isnot [long]) {
  Write-Host "[FEHLER] Bewerbungsauftrag enthält keine ganzzahlige schemaVersion." -ForegroundColor Red
  exit 1
}
$auftragSchema = [int]$auftragSchemaValue
$documentScope = Get-JsonProperty -Object $auftrag -Name "dokumentumfang"
$expectedCv = $true
$expectedLetter = $true
$cvKind = if ([string](Get-JsonProperty -Object $auftrag -Name "dokumentmodus") -eq "anschreiben_mit_universalem_lebenslauf") { "universal_unveraendert" } else { "individuell" }
if ($auftragSchema -lt 1 -or $auftragSchema -gt 4) {
  Write-Host "[FEHLER] Bewerbungsauftrag verwendet keine unterstützte schemaVersion 1 bis 4." -ForegroundColor Red
  exit 1
}
if ($auftragSchema -eq 4) {
  if ($null -eq $documentScope) {
    Write-Host "[FEHLER] Bewerbungsauftrag mit schemaVersion 4 enthält keinen dokumentumfang." -ForegroundColor Red
    exit 1
  }
  $cvKind = [string](Get-JsonProperty -Object $documentScope -Name "lebenslauf")
  $letterValue = Get-JsonProperty -Object $documentScope -Name "anschreiben"
  $emailValue = Get-JsonProperty -Object $documentScope -Name "emailNachricht"
  if ($cvKind -notin @("individuell", "universal_unveraendert", "nicht_enthalten") -or
      $letterValue -isnot [bool] -or $emailValue -isnot [bool]) {
    Write-Host "[FEHLER] dokumentumfang enthält ungültige oder nicht typisierte Werte." -ForegroundColor Red
    exit 1
  }
  $expectedCv = $cvKind -ne "nicht_enthalten"
  $expectedLetter = [bool]$letterValue
  if (-not ($expectedCv -or $expectedLetter -or [bool]$emailValue)) {
    Write-Host "[FEHLER] dokumentumfang wählt kein Dokument aus." -ForegroundColor Red
    exit 1
  }
}
$expectedHtmlCount = [int]$expectedCv + [int]$expectedLetter
$htmlFiles = @(Get-ChildItem -LiteralPath $htmlFolder -File -Filter "*.html" | Where-Object { $_.Name -match '^(Lebenslauf|Anschreiben) - ' } | Sort-Object Name)
$pdfFiles = @(Get-ChildItem -LiteralPath $pdfFolder -File -Filter "*.pdf" | Where-Object { $_.Name -match '^(Lebenslauf|Anschreiben) - ' } | Sort-Object Name)
if ($expectedHtmlCount -eq 0) {
  Write-Host "[FEHLER] ATS-Prüfung ist für einen Dokumentumfang ohne HTML/PDF nicht erforderlich und darf dafür nicht aufgerufen werden." -ForegroundColor Red
  exit 1
}
if ($htmlFiles.Count -ne $expectedHtmlCount -or $pdfFiles.Count -ne $expectedHtmlCount -or
    @($htmlFiles | Where-Object { $_.Name -like 'Lebenslauf -*' }).Count -ne [int]$expectedCv -or
    @($htmlFiles | Where-Object { $_.Name -like 'Anschreiben -*' }).Count -ne [int]$expectedLetter) {
  Write-Host "[FEHLER] ATS-Prüfung erwartet genau die $expectedHtmlCount laut Dokumentumfang ausgewählten HTML- und PDF-Dateien." -ForegroundColor Red
  exit 1
}

$fields = Get-MarkdownFields -Path $StammdatenPath
$fullName = [string]$fields["Vollständiger Name"]
$role = [string](Get-JsonProperty -Object $auftrag -Name "rolle")
$company = [string](Get-JsonProperty -Object $auftrag -Name "firma")
$results = @()

Write-Host "Pruefe ATS-Textschicht: $resolvedFolder"
foreach ($html in $htmlFiles) {
  $pdfName = [System.IO.Path]::ChangeExtension($html.Name, ".pdf")
  $pdf = @($pdfFiles | Where-Object { $_.Name -eq $pdfName })
  if ($pdf.Count -ne 1) {
    Add-ErrorMessage "Passende PDF fehlt für $($html.Name)."
    continue
  }
  try {
    $sourceText = Convert-HtmlToText -Html (Get-Content -LiteralPath $html.FullName -Raw -Encoding UTF8)
    $pdfText = Get-ExtractedPdfText -Path $pdf[0].FullName
    $sourceLength = Get-ComparableLength -Text $sourceText
    $pdfLength = Get-ComparableLength -Text $pdfText
    $coverage = if ($sourceLength -gt 0) { [math]::Round(([math]::Min($sourceLength, $pdfLength) / $sourceLength) * 100.0, 1) } else { 0.0 }
    $requiredValues = New-Object System.Collections.Generic.List[string]
    $requiredValues.Add($fullName) | Out-Null
    if ($html.Name -notlike "Lebenslauf -*" -or $cvKind -ne "universal_unveraendert") {
      $requiredValues.Add($role) | Out-Null
    }
    if ($html.Name -like "Anschreiben -*") { $requiredValues.Add($company) | Out-Null }
    if ($html.Name -like "Lebenslauf -*") {
      foreach ($period in [regex]::Matches($sourceText, '(?i)\b(?:0[1-9]|1[0-2])/\d{4}\s*[-–—]\s*(?:(?:0[1-9]|1[0-2])/\d{4}|fortlaufend)\b') | ForEach-Object { $_.Value } | Sort-Object -Unique) {
        $requiredValues.Add($period) | Out-Null
      }
    }
    $missing = @($requiredValues | Where-Object { -not (Normalize-Text -Text $pdfText).Contains((Normalize-Text -Text $_)) })
    if ($coverage -lt $MinTextabdeckungProzent) {
      Add-ErrorMessage "$($pdf[0].Name): Textabdeckung ist zu gering ($coverage % statt mindestens $MinTextabdeckungProzent %)."
    }
    if ($missing.Count -gt 0) {
      Add-ErrorMessage "$($pdf[0].Name): Pflichttext fehlt in der PDF-Textschicht: $($missing -join ', ')"
    }
    $normalizedPdf = Normalize-Text -Text $pdfText
    $nameIndex = $normalizedPdf.IndexOf((Normalize-Text -Text $fullName), [System.StringComparison]::Ordinal)
    $roleIndex = $normalizedPdf.IndexOf((Normalize-Text -Text $role), [System.StringComparison]::Ordinal)
    $roleRequiredInDocument = -not ($html.Name -like "Lebenslauf -*" -and $cvKind -eq "universal_unveraendert")
    $readingOrderPlausible = if ($roleRequiredInDocument) {
      ($nameIndex -ge 0) -and ($roleIndex -ge $nameIndex) -and ($roleIndex -lt [math]::Max(80, [int]($normalizedPdf.Length * 0.3)))
    } else {
      ($nameIndex -ge 0) -and ($nameIndex -lt [math]::Max(80, [int]($normalizedPdf.Length * 0.3)))
    }
    if (-not $readingOrderPlausible) {
      $readingOrderLabel = if ($roleRequiredInDocument) { "Name und Zielrolle liegen" } else { "Der Name liegt" }
      Add-WarningMessage "$($pdf[0].Name): $readingOrderLabel in der extrahierten Lesereihenfolge nicht früh genug."
    }
    if ($coverage -ge $MinTextabdeckungProzent -and $missing.Count -eq 0) {
      Add-OkMessage "$($pdf[0].Name): Unicode-Textschicht extrahierbar, Pflichttexte vorhanden, Abdeckung $coverage %."
    }
    $results += [ordered]@{
      htmlFile = $html.Name
      htmlSha256 = (Get-FileHash -LiteralPath $html.FullName -Algorithm SHA256).Hash
      pdfFile = $pdf[0].Name
      pdfSha256 = (Get-FileHash -LiteralPath $pdf[0].FullName -Algorithm SHA256).Hash
      sourceComparableCharacters = $sourceLength
      extractedComparableCharacters = $pdfLength
      textCoveragePercent = $coverage
      missingRequiredText = $missing
      readingOrderPlausible = $readingOrderPlausible
      extractionEngine = "interner_tounicode_parser"
    }
  } catch {
    Add-ErrorMessage "$($pdf[0].Name): ATS-Textprüfung fehlgeschlagen: $($_.Exception.Message) | $($_.ScriptStackTrace)"
  }
}

if (-not [string]::IsNullOrWhiteSpace($BerichtPath)) {
  $fullReportPath = [System.IO.Path]::GetFullPath($BerichtPath)
  $reportParent = Split-Path -Path $fullReportPath -Parent
  if (-not (Test-Path -LiteralPath $reportParent -PathType Container)) { New-Item -Path $reportParent -ItemType Directory -Force | Out-Null }
  $report = [ordered]@{
    schemaVersion = 1
    checkedAtUtc = [datetime]::UtcNow.ToString("o")
    folder = $resolvedFolder
    status = if ($errors.Count -gt 0) { "fehler" } elseif ($warnings.Count -gt 0) { "warnung" } else { "ok" }
    errors = @($errors)
    warnings = @($warnings)
    oks = @($oks)
    results = $results
  }
  Set-Content -LiteralPath $fullReportPath -Encoding UTF8 -Value ($report | ConvertTo-Json -Depth 8)
}

Write-Host ""
Write-Host "Zusammenfassung:"
Write-Host "OK: $($oks.Count)"
Write-Host "Warnungen: $($warnings.Count)"
Write-Host "Fehler: $($errors.Count)"
if ($errors.Count -gt 0) { Write-Host "ERGEBNIS: FEHLER" -ForegroundColor Red; exit 1 }
Write-Host "ERGEBNIS: OK" -ForegroundColor Green
exit 0
