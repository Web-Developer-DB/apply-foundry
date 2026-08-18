#requires -Version 7.6
#requires -PSEdition Core

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Ordner,

  [string]$AuftragPath,

  [switch]$WarnungenAlsFehler
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/Platform.psm1") -Force

$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$oks = New-Object System.Collections.Generic.List[string]
$script:PathComparison = if ($env:OS -eq "Windows_NT") { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
$script:PathComparer = if ($env:OS -eq "Windows_NT") { [System.StringComparer]::OrdinalIgnoreCase } else { [System.StringComparer]::Ordinal }

function Get-ApplicationsRootFromPath {
  param([string]$Path, [switch]$Container)

  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $directory = if ($Container) {
    [System.IO.DirectoryInfo]::new($fullPath)
  } else {
    [System.IO.DirectoryInfo]::new((Split-Path -Path $fullPath -Parent))
  }
  while ($null -ne $directory) {
    if ([string]::Equals($directory.Name, 'Bewerbungen', $script:PathComparison) -and
        $null -ne $directory.Parent -and
        [string]::Equals($directory.Parent.Name, 'Private', $script:PathComparison)) {
      return $directory.FullName
    }
    $directory = $directory.Parent
  }
  return $null
}

function ConvertTo-SafeFileList {
  param([object[]]$Files, [string]$Root, [string]$Context)

  $safeFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
  foreach ($file in @($Files)) {
    try {
      $safePath = Resolve-SafePath -Candidate $file.FullName -Root $Root -MustExist -PathType Leaf
      $safeFiles.Add((Get-Item -LiteralPath $safePath -Force))
    } catch {
      Write-Host "[FEHLER] $Context enthält einen unsicheren Dateipfad: $($file.FullName): $($_.Exception.Message)" -ForegroundColor Red
      exit 2
    }
  }
  return $safeFiles.ToArray()
}

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

function Test-PathEqual {
  param([string]$Left, [string]$Right)
  if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) { return $false }
  return [string]::Equals([System.IO.Path]::GetFullPath($Left), [System.IO.Path]::GetFullPath($Right), $script:PathComparison)
}

function Convert-ToSlug {
  param([string]$Value)
  $slug = $Value.Trim()
  foreach ($replacement in @(
    @{ From = "ä"; To = "ae" }, @{ From = "ö"; To = "oe" }, @{ From = "ü"; To = "ue" },
    @{ From = "Ä"; To = "Ae" }, @{ From = "Ö"; To = "Oe" }, @{ From = "Ü"; To = "Ue" },
    @{ From = "ß"; To = "ss" }, @{ From = "&"; To = "und" }
  )) {
    $slug = $slug.Replace($replacement.From, $replacement.To)
  }
  $slug = ($slug -replace '[^A-Za-z0-9]+', '-').Trim('-')
  return $slug
}

function Get-JsonProperty {
  param([object]$Object, [string]$Name)
  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

function Test-JsonPropertyExists {
  param([object]$Object, [string]$Name)
  return ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name])
}

function ConvertTo-DocumentScope {
  param(
    [object]$Configured,
    [string]$Context
  )

  if ($null -eq $Configured) {
    throw "$Context enthält keinen Dokumentumfang."
  }
  $cvKind = [string](Get-JsonProperty -Object $Configured -Name "lebenslauf")
  $letterValue = Get-JsonProperty -Object $Configured -Name "anschreiben"
  $emailValue = Get-JsonProperty -Object $Configured -Name "emailNachricht"
  if ($cvKind -notin @("individuell", "universal_unveraendert", "nicht_enthalten")) {
    throw "$Context enthält einen ungültigen Lebenslaufumfang: $cvKind"
  }
  if ($letterValue -isnot [bool] -or $emailValue -isnot [bool]) {
    throw "$Context muss anschreiben und emailNachricht als boolesche Werte führen."
  }
  if ($cvKind -eq "nicht_enthalten" -and -not [bool]$letterValue -and -not [bool]$emailValue) {
    throw "$Context wählt kein Dokument aus."
  }
  return [ordered]@{
    Lebenslauf = $cvKind -ne "nicht_enthalten"
    LebenslaufArt = $cvKind
    Anschreiben = [bool]$letterValue
    EmailNachricht = [bool]$emailValue
  }
}

function Get-DocumentScope {
  param([string]$Path)

  $scope = [ordered]@{
    Lebenslauf = $true
    LebenslaufArt = "individuell"
    Anschreiben = $true
    EmailNachricht = $true
  }
  if ([string]::IsNullOrWhiteSpace($Path)) { return $scope }
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Bewerbungsauftrag fehlt oder ist keine Datei: $Path"
  }
  $auftrag = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
  $schemaValue = Get-JsonProperty -Object $auftrag -Name "schemaVersion"
  if ($schemaValue -isnot [int] -and $schemaValue -isnot [long]) {
    throw "Bewerbungsauftrag enthält keine ganzzahlige schemaVersion."
  }
  $schema = [int]$schemaValue
  $configured = Get-JsonProperty -Object $auftrag -Name "dokumentumfang"
  if ($schema -ge 4 -and $schema -le 5) {
    if ($null -eq $configured) {
      throw "Bewerbungsauftrag mit schemaVersion $schema enthält keinen dokumentumfang."
    }
    return ConvertTo-DocumentScope -Configured $configured -Context "Bewerbungsauftrag"
  } elseif ($schema -lt 1 -or $schema -gt 5) {
    throw "Bewerbungsauftrag verwendet keine unterstützte schemaVersion 1 bis 5."
  } elseif ([string](Get-JsonProperty -Object $auftrag -Name "dokumentmodus") -eq "anschreiben_mit_universalem_lebenslauf") {
    $scope.LebenslaufArt = "universal_unveraendert"
  }
  return $scope
}

function Get-ManifestDocumentScope {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Strukturierte Veröffentlichung enthält kein Manifest.json."
  }
  $manifest = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
  $manifestSchema = Get-JsonProperty -Object $manifest -Name "schemaVersion"
  if (($manifestSchema -isnot [int] -and $manifestSchema -isnot [long]) -or [int]$manifestSchema -ne 1) {
    throw "Manifest.json verwendet keine unterstützte schemaVersion 1."
  }
  $configured = Get-JsonProperty -Object $manifest -Name "dokumentumfang"
  if ($null -eq $configured) {
    Add-WarningMessage "Legacy-Manifest ohne dokumentumfang erkannt; Vollumfang wird angenommen."
    return Get-DocumentScope -Path ""
  }
  return ConvertTo-DocumentScope -Configured $configured -Context "Manifest.json"
}

function Test-DocumentScopeEqual {
  param([object]$Left, [object]$Right)
  return (
    [bool]$Left.Lebenslauf -eq [bool]$Right.Lebenslauf -and
    [string]$Left.LebenslaufArt -eq [string]$Right.LebenslaufArt -and
    [bool]$Left.Anschreiben -eq [bool]$Right.Anschreiben -and
    [bool]$Left.EmailNachricht -eq [bool]$Right.EmailNachricht
  )
}

function Test-ExpectedFileSet {
  param(
    [array]$Files,
    [bool]$Expected,
    [string]$Label,
    [string]$Schema
  )

  if ($Expected -and $Files.Count -eq 1) {
    Add-OkMessage "$Label-Datei gefunden: $($Files[0].Name)"
  } elseif ($Expected -and $Files.Count -eq 0) {
    Add-ErrorMessage "Ausgewählte $Label-Datei fehlt nach Schema `$Schema`."
  } elseif ($Expected) {
    Add-ErrorMessage "Mehrere $Label-Dateien gefunden: $($Files.Name -join ', ')"
  } elseif ($Files.Count -gt 0) {
    Add-ErrorMessage "Nicht ausgewählte $Label-Datei ist vorhanden: $($Files.Name -join ', ')"
  } else {
    Add-OkMessage "$Label ist laut Dokumentumfang nicht ausgewählt."
  }
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

function Test-SemanticMultipageCvContract {
  param(
    [object[]]$PageMatches,
    [string]$FileName
  )

  $seenSections = @{}
  for ($index = 0; $index -lt $PageMatches.Count; $index++) {
    $pageNumber = $index + 1
    $body = $PageMatches[$index].Groups['body'].Value
    if ($body -notmatch '(?is)<header\b[^>]*\bdata-cv-page-header(?:\s*=|\s|>)') {
      Add-ErrorMessage "${FileName}: Seite $pageNumber besitzt keinen semantisch markierten Seitenkopf (`data-cv-page-header`)."
    }
    $sectionTags = @([regex]::Matches($body, '(?is)<section\b[^>]*>'))
    $sectionMatches = @([regex]::Matches($body, '(?is)<section\b[^>]*\bdata-cv-section\s*=\s*["''](?<id>[a-z0-9]+(?:-[a-z0-9]+)*)["''][^>]*>'))
    if ($sectionTags.Count -eq 0 -or $sectionMatches.Count -ne $sectionTags.Count) {
      Add-ErrorMessage "${FileName}: Auf Seite $pageNumber muss jeder fachliche `<section>`-Block eine stabile `data-cv-section`-Kennung tragen."
    }
    foreach ($match in $sectionMatches) {
      $id = $match.Groups['id'].Value
      if ($seenSections.ContainsKey($id)) {
        Add-ErrorMessage "${FileName}: Abschnitt '$id' ist auf Seite $($seenSections[$id]) und Seite $pageNumber vorhanden; fachliche Abschnitte dürfen nicht über Seiten geteilt werden."
      } else {
        $seenSections[$id] = $pageNumber
      }
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
        Test-SemanticMultipageCvContract -PageMatches $pageMatches -FileName $name
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
    $manifestSchema = Get-JsonProperty -Object $manifest -Name "schemaVersion"
    if (($manifestSchema -isnot [int] -and $manifestSchema -isnot [long]) -or [int]$manifestSchema -ne 1) {
      Add-ErrorMessage "Manifest.json verwendet keine unterstützte schemaVersion 1."
    }

    $sourceInputs = Get-JsonProperty -Object $manifest -Name "sourceInputs"
    $requiredSourceNames = @("stammdaten", "profil", "bewerbungsauftrag", "anforderungsmatrix")
    $allowedSourceNames = @($requiredSourceNames + "passfoto")
    if ($null -eq $sourceInputs) {
      Add-ErrorMessage "Manifest.json enthält keine Quellnachweise."
    } else {
      $sourceProperties = @($sourceInputs.PSObject.Properties)
      $actualSourceNames = @($sourceProperties.Name | Sort-Object)
      $missingRequiredSources = @($requiredSourceNames | Where-Object { $actualSourceNames -notcontains $_ })
      $unexpectedSources = @($actualSourceNames | Where-Object { $allowedSourceNames -notcontains $_ })
      if ($missingRequiredSources.Count -gt 0 -or $unexpectedSources.Count -gt 0 -or $sourceProperties.Count -notin @(4, 5)) {
        Add-ErrorMessage "Manifest.json muss die vier Pflichtquellen und darf zusätzlich ausschließlich den optionalen Quellnachweis passfoto enthalten."
      }
      foreach ($sourceProperty in $sourceProperties) {
        $sourceName = [string](Get-JsonProperty -Object $sourceProperty.Value -Name "name")
        $sourceHash = [string](Get-JsonProperty -Object $sourceProperty.Value -Name "sha256")
        if ([string]::IsNullOrWhiteSpace($sourceName) -or $sourceName -match '[\\/]') {
          Add-ErrorMessage "Manifest-Quellnachweis enthält keinen gültigen Dateinamen: $($sourceProperty.Name)"
        }
        if ($sourceHash -notmatch '^[A-Fa-f0-9]{64}$') {
          Add-ErrorMessage "Manifest-Quellnachweis enthält keinen gültigen SHA-256-Wert: $($sourceProperty.Name)"
        }
        if ($sourceProperty.Name -ceq 'passfoto' -and $sourceName -cne 'Passfoto.png') {
          Add-ErrorMessage "Der optionale Manifest-Quellnachweis passfoto muss exakt auf Passfoto.png verweisen."
        }
      }
    }

    if (-not (Test-JsonPropertyExists -Object $manifest -Name "files")) {
      Add-ErrorMessage "Manifest.json enthält keine Dateinachweise."
      return
    }
    $records = @((Get-JsonProperty -Object $manifest -Name "files"))
    if ($records.Count -eq 0) {
      Add-ErrorMessage "Manifest.json enthält keine Dateinachweise."
      return
    }
    $rootFull = (Resolve-SafePath -Candidate $Root -Root $script:ApplicationsRoot -MustExist -PathType Container).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $manifestFull = Resolve-SafePath -Candidate $ManifestPath -Root $rootFull -MustExist -PathType Leaf
    $actualFiles = @(ConvertTo-SafeFileList -Files @(Get-ChildItem -LiteralPath $Root -Recurse -File) -Root $rootFull -Context 'Veröffentlichung' | Where-Object { -not (Test-PathEqual -Left $_.FullName -Right $manifestFull) })
    if ($records.Count -ne $actualFiles.Count) {
      Add-ErrorMessage "Manifest-Dateizahl stimmt nicht mit der Veröffentlichung überein ($($records.Count) statt $($actualFiles.Count))."
    }
    $manifestPaths = New-Object 'System.Collections.Generic.HashSet[string]' ($script:PathComparer)
    foreach ($record in $records) {
      $relativePath = [string]$record.path
      $bytesValue = Get-JsonProperty -Object $record -Name "bytes"
      $expectedHash = [string](Get-JsonProperty -Object $record -Name "sha256")
      if ([string]::IsNullOrWhiteSpace($relativePath) -or [System.IO.Path]::IsPathRooted($relativePath) -or $relativePath -match '(^|[\\/])\.\.([\\/]|$)') {
        Add-ErrorMessage "Manifest enthält einen ungültigen relativen Pfad: $relativePath"
        continue
      }
      if (($bytesValue -isnot [int] -and $bytesValue -isnot [long]) -or [long]$bytesValue -lt 0) {
        Add-ErrorMessage "Manifest enthält keine gültige Bytezahl: $relativePath"
      }
      if ($expectedHash -notmatch '^[A-Fa-f0-9]{64}$') {
        Add-ErrorMessage "Manifest enthält keinen gültigen SHA-256-Wert: $relativePath"
      }
      $normalizedRelative = ($relativePath -replace '\\', '/').TrimStart('/')
      if (-not $manifestPaths.Add($normalizedRelative)) {
        Add-ErrorMessage "Manifest enthält einen doppelten Dateipfad: $relativePath"
        continue
      }
      try {
        $filePath = Resolve-SafePath -Candidate (Join-Path -Path $Root -ChildPath ($normalizedRelative -replace '/', [System.IO.Path]::DirectorySeparatorChar)) -Root $rootFull -MustExist -PathType Leaf
      } catch {
        Add-ErrorMessage "Manifest-Datei fehlt oder verlässt den Veröffentlichungsordner: $relativePath"
        continue
      }
      $fileInfo = Get-Item -LiteralPath $filePath
      if (($bytesValue -is [int] -or $bytesValue -is [long]) -and [long]$bytesValue -ne $fileInfo.Length) {
        Add-ErrorMessage "Manifest-Dateigröße stimmt nicht: $relativePath"
      }
      $actualHash = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash
      if ($actualHash -ne $expectedHash) {
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

$script:ApplicationsRoot = Get-ApplicationsRootFromPath -Path $Ordner -Container
if ([string]::IsNullOrWhiteSpace($script:ApplicationsRoot)) {
  Write-Host "[FEHLER] Ordner muss unter <Projektwurzel>/Private/Bewerbungen liegen: $Ordner" -ForegroundColor Red
  exit 2
}
try {
  $script:ApplicationsRoot = Resolve-SafePath -Candidate $script:ApplicationsRoot -Root $script:ApplicationsRoot -AllowRoot -MustExist -PathType Container
  $resolvedFolder = Resolve-SafePath -Candidate $Ordner -Root $script:ApplicationsRoot -MustExist -PathType Container
} catch {
  Write-Host "[FEHLER] Unsicherer Bewerbungsordner: $($_.Exception.Message)" -ForegroundColor Red
  exit 2
}
Write-Host "Pruefe Bewerbung: $resolvedFolder"

try {
  $internalFolder = Resolve-SafePath -Candidate (Join-Path -Path $resolvedFolder -ChildPath "Intern") -Root $resolvedFolder -PathType Container
  $shippingFolder = Resolve-SafePath -Candidate (Join-Path -Path $resolvedFolder -ChildPath "Versand") -Root $resolvedFolder -PathType Container
  $manifestPath = Resolve-SafePath -Candidate (Join-Path -Path $resolvedFolder -ChildPath "Manifest.json") -Root $resolvedFolder -PathType Leaf
} catch {
  Write-Host "[FEHLER] Unsicherer Intern-, Versand- oder Manifestpfad: $($_.Exception.Message)" -ForegroundColor Red
  exit 2
}
$isStructuredPublication = (Test-Path -LiteralPath $internalFolder -PathType Container) -and (Test-Path -LiteralPath $shippingFolder -PathType Container)
$manifestDocumentScope = $null
if ($isStructuredPublication -and (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
  try {
    $manifestDocumentScope = Get-ManifestDocumentScope -Path $manifestPath
  } catch {
    Add-ErrorMessage $_.Exception.Message
  }
}

try {
  if (-not [string]::IsNullOrWhiteSpace($AuftragPath)) {
    $AuftragPath = Resolve-SafePath -Candidate $AuftragPath -Root $script:ApplicationsRoot -MustExist -PathType Leaf
    $documentScope = Get-DocumentScope -Path $AuftragPath
    if ($null -ne $manifestDocumentScope -and -not (Test-DocumentScopeEqual -Left $documentScope -Right $manifestDocumentScope)) {
      Add-ErrorMessage "Dokumentumfang im Manifest stimmt nicht mit dem Bewerbungsauftrag überein."
    }
  } elseif ($null -ne $manifestDocumentScope) {
    $documentScope = $manifestDocumentScope
  } else {
    $documentScope = Get-DocumentScope -Path ""
  }
} catch {
  Add-ErrorMessage $_.Exception.Message
  $documentScope = Get-DocumentScope -Path ""
}

$applicationCompany = ""
$applicationRole = ""
$applicationCompanySlug = ""
try {
  $metadataSource = if (-not [string]::IsNullOrWhiteSpace($AuftragPath) -and (Test-Path -LiteralPath $AuftragPath -PathType Leaf)) {
    Get-Content -LiteralPath $AuftragPath -Raw -Encoding UTF8 | ConvertFrom-Json
  } elseif ($isStructuredPublication -and (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
  } else {
    $null
  }
  if ($null -ne $metadataSource) {
    $applicationCompany = [string](Get-JsonProperty -Object $metadataSource -Name "firma")
    $applicationRole = [string](Get-JsonProperty -Object $metadataSource -Name "rolle")
    $applicationCompanySlug = [string](Get-JsonProperty -Object $metadataSource -Name "firmaSlug")
    if ([string]::IsNullOrWhiteSpace($applicationCompanySlug) -and -not [string]::IsNullOrWhiteSpace($applicationCompany)) {
      $applicationCompanySlug = Convert-ToSlug -Value $applicationCompany
    }
  }
} catch {
  Add-ErrorMessage "Bewerbungsmetadaten konnten nicht gelesen werden: $($_.Exception.Message)"
}

if ($resolvedFolder -notmatch '[\\/]+Private[\\/]+Bewerbungen[\\/]+' ) {
  Add-WarningMessage "Der Ordner liegt nicht unter `Private/Bewerbungen/`. Bitte prüfen, ob dies beabsichtigt ist."
}

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
  try {
    $path = Resolve-SafePath -Candidate $path -Root $documentFolder -MustExist -PathType Leaf
  } catch {
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

$documentFiles = @(ConvertTo-SafeFileList -Files @(Get-ChildItem -LiteralPath $documentFolder -File) -Root $documentFolder -Context 'Dokumentenordner')
$emailAreaFiles = if ($isStructuredPublication) { @(ConvertTo-SafeFileList -Files @(Get-ChildItem -LiteralPath $emailFolder -File) -Root $emailFolder -Context 'Versandordner') } else { @() }
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
$emailFiles = @(ConvertTo-SafeFileList -Files @(Get-ChildItem -LiteralPath $emailFolder -File -Filter "Email-Nachricht--*.md") -Root $emailFolder -Context 'E-Mail-Ordner' | Where-Object { $_.Name -match '^Email-Nachricht--[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*\.md$' })

$allowedInternalMarkdown = @($fixedRequired + "Offene_Fragen.md")
$unexpectedMarkdown = @($markdownFiles | Where-Object {
  $isExpectedInternal = $_.Name -in $allowedInternalMarkdown
  $isExpectedEmail = [bool]$documentScope.EmailNachricht -and
    (Test-PathEqual -Left $_.DirectoryName -Right $emailFolder) -and
    $_.Name -match '^Email-Nachricht--[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*\.md$'
  -not ($isExpectedInternal -or $isExpectedEmail)
})
foreach ($markdown in $unexpectedMarkdown) {
  Add-ErrorMessage "Unerwartete Markdown-Datei im Kandidaten- oder Veröffentlichungsumfang: $($markdown.Name)"
}

$unexpectedHtml = @($htmlFiles | Where-Object { ($_ -notin $cvFiles) -and ($_ -notin $letterFiles) })
foreach ($html in $unexpectedHtml) {
  Add-ErrorMessage "Unerwartete oder falsch benannte HTML-Datei im finalen Ordner: $($html.Name)"
}

Test-ExpectedFileSet -Files $cvFiles -Expected ([bool]$documentScope.Lebenslauf) -Label "Lebenslauf" -Schema "Lebenslauf - NACHNAME.VORNAME.html"
Test-ExpectedFileSet -Files $letterFiles -Expected ([bool]$documentScope.Anschreiben) -Label "Anschreiben" -Schema "Anschreiben - NACHNAME.VORNAME.html"

if (($cvFiles.Count -eq 1) -and ($letterFiles.Count -eq 1)) {
  $cvNamePart = $cvFiles[0].BaseName -replace '^Lebenslauf - ', ''
  $letterNamePart = $letterFiles[0].BaseName -replace '^Anschreiben - ', ''
  if ($cvNamePart -ceq $letterNamePart) {
    Add-OkMessage "Lebenslauf und Anschreiben verwenden denselben Bewerbernamen: $cvNamePart"
  } else {
    Add-ErrorMessage "Lebenslauf und Anschreiben verwenden unterschiedliche Bewerbernamen: `$cvNamePart` vs. `$letterNamePart`."
  }
}

Test-ExpectedFileSet -Files $emailFiles -Expected ([bool]$documentScope.EmailNachricht) -Label "E-Mail-Nachricht" -Schema "Email-Nachricht--FIRMA.md"
if ([bool]$documentScope.EmailNachricht -and $emailFiles.Count -eq 1 -and -not [string]::IsNullOrWhiteSpace($applicationCompanySlug)) {
  $expectedEmailName = "Email-Nachricht--$applicationCompanySlug.md"
  if ($emailFiles[0].Name -cne $expectedEmailName) {
    Add-ErrorMessage "E-Mail-Dateiname stimmt nicht mit dem Firmen-Slug aus Auftrag oder Manifest überein: erwartet $expectedEmailName."
  } else {
    Add-OkMessage "E-Mail-Dateiname stimmt mit dem Firmen-Slug überein."
  }
}

$expectedPdfNames = @()
if ([bool]$documentScope.Lebenslauf -and $cvFiles.Count -eq 1) {
  $expectedPdfNames += [System.IO.Path]::ChangeExtension($cvFiles[0].Name, ".pdf")
}
if ([bool]$documentScope.Anschreiben -and $letterFiles.Count -eq 1) {
  $expectedPdfNames += [System.IO.Path]::ChangeExtension($letterFiles[0].Name, ".pdf")
}
$expectedPdfNameSet = New-Object 'System.Collections.Generic.HashSet[string]' ($script:PathComparer)
foreach ($expectedPdfName in $expectedPdfNames) {
  $null = $expectedPdfNameSet.Add($expectedPdfName)
}

if ($isStructuredPublication) {
  $shippingPdfs = @($emailAreaFiles | Where-Object { $_.Extension -ieq ".pdf" })
  $shippingPdfNamesExact = $shippingPdfs.Count -eq $expectedPdfNames.Count -and
    @($shippingPdfs | Where-Object { -not $expectedPdfNameSet.Contains($_.Name) }).Count -eq 0
  if (-not $shippingPdfNamesExact) {
    Add-ErrorMessage "Versandordner enthält nicht genau die laut Dokumentumfang erwarteten PDF-Dateien; gefunden: $($shippingPdfs.Name -join ', ')"
  } else {
    Add-OkMessage "Versandordner enthält genau die zu den ausgewählten HTML-Dateien gehörenden PDF-Anlagen."
  }
  $unexpectedShipping = @($emailAreaFiles | Where-Object {
    $_.Extension -notin @(".pdf", ".md") -or ($_.Extension -eq ".md" -and $_.Name -notmatch '^Email-Nachricht--')
  })
  if ($unexpectedShipping.Count -gt 0) {
    Add-ErrorMessage "Versandordner enthält interne oder unerwartete Dateien: $($unexpectedShipping.Name -join ', ')"
  }
  $misplacedPdfs = @(ConvertTo-SafeFileList -Files @(Get-ChildItem -LiteralPath $resolvedFolder -Recurse -File) -Root $resolvedFolder -Context 'Veröffentlichung' | Where-Object {
    $_.Extension -ieq ".pdf" -and -not (Test-PathEqual -Left $_.DirectoryName -Right $shippingFolder)
  })
  if ($misplacedPdfs.Count -gt 0) {
    Add-ErrorMessage "PDF-Dateien liegen außerhalb des Versandordners: $($misplacedPdfs.FullName -join ', ')"
  }
  Test-PublicationManifest -Root $resolvedFolder -ManifestPath $manifestPath
} else {
  $candidatePdfs = @(ConvertTo-SafeFileList -Files @(Get-ChildItem -LiteralPath $resolvedFolder -Recurse -File) -Root $resolvedFolder -Context 'Kandidatenordner' | Where-Object { $_.Extension -ieq ".pdf" })
  $unexpectedCandidatePdfs = @($candidatePdfs | Where-Object {
    -not (Test-PathEqual -Left $_.DirectoryName -Right $resolvedFolder) -or
    -not $expectedPdfNameSet.Contains($_.Name)
  })
  if ($unexpectedCandidatePdfs.Count -gt 0) {
    Add-ErrorMessage "Kandidatenordner enthält zusätzliche, veraltete oder nicht ausgewählte PDF-Dateien: $($unexpectedCandidatePdfs.FullName -join ', ')"
  } elseif ($candidatePdfs.Count -gt 0) {
    Add-OkMessage "Vorhandene Kandidaten-PDFs sind exakt an die ausgewählten HTML-Dateinamen gebunden."
  }
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
  if (-not [string]::IsNullOrWhiteSpace($applicationRole) -and -not (Test-Pattern -Text $firstLine -Pattern ([regex]::Escape($applicationRole)))) {
    Add-ErrorMessage "$($emailFiles[0].Name): Der Betreff enthält die Zielrolle aus Auftrag oder Manifest nicht."
  }
  if (-not [string]::IsNullOrWhiteSpace($applicationCompany) -and -not (Test-Pattern -Text $emailText -Pattern ([regex]::Escape($applicationCompany)))) {
    Add-ErrorMessage "$($emailFiles[0].Name): Die E-Mail enthält die Firma aus Auftrag oder Manifest nicht."
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
