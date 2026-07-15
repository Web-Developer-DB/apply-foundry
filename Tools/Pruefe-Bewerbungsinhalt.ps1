[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Ordner,

  [string]$StammdatenPath = (Join-Path -Path $PSScriptRoot -ChildPath "..\Private\Daten\01_PERSOENLICHE_DATEN.md"),

  [string]$ProfilPath = (Join-Path -Path $PSScriptRoot -ChildPath "..\Private\Daten\02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md"),

  [Parameter(Mandatory = $true)]
  [string]$AuftragPath,

  [Parameter(Mandatory = $true)]
  [string]$AnforderungsmatrixPath,

  [switch]$WarnungenAlsFehler,

  [string]$BerichtPath
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

function Get-MarkdownFields {
  param([string]$Path)
  $result = [ordered]@{}
  foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
    if ($line -match '^\s*-\s*(?<key>[^:]+):\s*(?<value>.*)$') {
      $key = $Matches.key.Trim()
      if (-not $result.Contains($key)) {
        $result[$key] = $Matches.value.Trim()
      }
    }
  }
  return $result
}

function Get-JsonProperty {
  param([object]$Object, [string]$Name)
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return $null
  }
  return $property.Value
}

function Convert-HtmlToText {
  param([string]$Html)
  $withoutStyle = [regex]::Replace($Html, '(?is)<style\b[^>]*>.*?</style>', ' ')
  $withoutTags = [regex]::Replace($withoutStyle, '(?is)<[^>]+>', ' ')
  return [System.Net.WebUtility]::HtmlDecode($withoutTags)
}

function Normalize-Text {
  param([AllowEmptyString()][string]$Text)
  if ($null -eq $Text) { return "" }
  $normalized = $Text.Replace([char]0x2013, '-').Replace([char]0x2014, '-').Replace([char]0x00A0, ' ')
  $normalized = [regex]::Replace($normalized, '\s+', ' ')
  return $normalized.Trim().ToLowerInvariant()
}

function Test-ContainsText {
  param([string]$Haystack, [AllowEmptyString()][string]$Needle)
  if ([string]::IsNullOrWhiteSpace($Needle)) { return $false }
  return (Normalize-Text -Text $Haystack).Contains((Normalize-Text -Text $Needle))
}

function Write-JsonReport {
  param([string]$Path, [array]$Periods)
  if ([string]::IsNullOrWhiteSpace($Path)) { return }
  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $parent = Split-Path -Path $fullPath -Parent
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -Path $parent -ItemType Directory -Force | Out-Null
  }
  $report = [ordered]@{
    schemaVersion = 1
    checkedAtUtc = [datetime]::UtcNow.ToString("o")
    applicationFolder = [System.IO.Path]::GetFullPath($Ordner)
    status = if ($errors.Count -gt 0) { "fehler" } elseif ($warnings.Count -gt 0) { "warnung" } else { "ok" }
    errors = @($errors)
    warnings = @($warnings)
    oks = @($oks)
    checkedFormalPeriods = $Periods
  }
  Set-Content -LiteralPath $fullPath -Encoding UTF8 -Value ($report | ConvertTo-Json -Depth 6)
}

foreach ($path in @($Ordner, $StammdatenPath, $ProfilPath, $AuftragPath, $AnforderungsmatrixPath)) {
  if (-not (Test-Path -LiteralPath $path)) {
    Write-Host "[FEHLER] Erforderlicher Pfad fehlt: $path" -ForegroundColor Red
    exit 1
  }
}
if (-not (Test-Path -LiteralPath $Ordner -PathType Container)) {
  Write-Host "[FEHLER] Bewerbungsordner ist kein Verzeichnis: $Ordner" -ForegroundColor Red
  exit 1
}

$resolvedFolder = (Resolve-Path -LiteralPath $Ordner).Path
$cvFiles = @(Get-ChildItem -LiteralPath $resolvedFolder -File -Filter "Lebenslauf - *.html")
$letterFiles = @(Get-ChildItem -LiteralPath $resolvedFolder -File -Filter "Anschreiben - *.html")
$emailFiles = @(Get-ChildItem -LiteralPath $resolvedFolder -File -Filter "Email-Nachricht--*.md")
if ($cvFiles.Count -ne 1 -or $letterFiles.Count -ne 1 -or $emailFiles.Count -ne 1) {
  Write-Host "[FEHLER] Inhaltsprüfung erwartet genau einen Lebenslauf, ein Anschreiben und eine E-Mail-Nachricht." -ForegroundColor Red
  exit 1
}

$cvHtml = Get-Content -LiteralPath $cvFiles[0].FullName -Raw -Encoding UTF8
$letterHtml = Get-Content -LiteralPath $letterFiles[0].FullName -Raw -Encoding UTF8
$emailText = Get-Content -LiteralPath $emailFiles[0].FullName -Raw -Encoding UTF8
$cvText = Convert-HtmlToText -Html $cvHtml
$letterText = Convert-HtmlToText -Html $letterHtml
$profileText = Get-Content -LiteralPath $ProfilPath -Raw -Encoding UTF8
$fields = Get-MarkdownFields -Path $StammdatenPath
$auftrag = Get-Content -LiteralPath $AuftragPath -Raw -Encoding UTF8 | ConvertFrom-Json
$matrix = Get-Content -LiteralPath $AnforderungsmatrixPath -Raw -Encoding UTF8 | ConvertFrom-Json

Write-Host "Pruefe Bewerbungsinhalt: $resolvedFolder"

$fullName = if ($fields.Contains("Vollständiger Name")) { [string]$fields["Vollständiger Name"] } else { "" }
$fileNamePerson = if ($fields.Contains("Dateiname-Name")) { [string]$fields["Dateiname-Name"] } else { "" }
$firma = [string](Get-JsonProperty -Object $auftrag -Name "firma")
$rolle = [string](Get-JsonProperty -Object $auftrag -Name "rolle")
$pageStrategy = [string](Get-JsonProperty -Object $auftrag -Name "seitenstrategie")

$cvPageCount = [regex]::Matches($cvHtml, '(?is)<main\b[^>]*class\s*=\s*["''][^"'']*\bpage\b[^"'']*["'']').Count
if ($pageStrategy -eq "eine_seite" -and $cvPageCount -eq 1) {
  Add-OkMessage "Seitenstrategie stimmt mit einem Lebenslauf-Seitencontainer überein."
} elseif ($pageStrategy -eq "zwei_seiten" -and $cvPageCount -eq 2) {
  Add-OkMessage "Seitenstrategie stimmt mit zwei Lebenslauf-Seitencontainern überein."
} elseif ($pageStrategy -notin @("eine_seite", "zwei_seiten")) {
  Add-ErrorMessage "Bewerbungsauftrag enthält keine final festgelegte Seitenstrategie. Erlaubt: eine_seite oder zwei_seiten."
} else {
  Add-ErrorMessage "Seitenstrategie im Bewerbungsauftrag stimmt nicht mit den Lebenslauf-Seitencontainern überein."
}

foreach ($document in @(
  [pscustomobject]@{ Name = "Lebenslauf"; Text = $cvText },
  [pscustomobject]@{ Name = "Anschreiben"; Text = $letterText },
  [pscustomobject]@{ Name = "E-Mail-Nachricht"; Text = $emailText }
)) {
  if (Test-ContainsText -Haystack $document.Text -Needle $fullName) {
    Add-OkMessage "$($document.Name) enthält den Bewerbernamen."
  } else {
    Add-ErrorMessage "$($document.Name) enthält den Bewerbernamen aus den Stammdaten nicht."
  }
}

if ($cvFiles[0].BaseName -ne "Lebenslauf - $fileNamePerson") {
  Add-ErrorMessage "Lebenslauf-Dateiname stimmt nicht mit Dateiname-Name aus den Stammdaten überein."
}
if ($letterFiles[0].BaseName -ne "Anschreiben - $fileNamePerson") {
  Add-ErrorMessage "Anschreiben-Dateiname stimmt nicht mit Dateiname-Name aus den Stammdaten überein."
}

if (Test-ContainsText -Haystack $letterText -Needle $firma) {
  Add-OkMessage "Anschreiben enthält die Firma aus dem Bewerbungsauftrag."
} else {
  Add-ErrorMessage "Anschreiben enthält die Firma aus dem Bewerbungsauftrag nicht."
}
foreach ($document in @(
  [pscustomobject]@{ Name = "Lebenslauf"; Text = $cvText },
  [pscustomobject]@{ Name = "Anschreiben"; Text = $letterText },
  [pscustomobject]@{ Name = "E-Mail-Betreff"; Text = ($emailText -split "`r?`n", 2)[0] }
)) {
  if (Test-ContainsText -Haystack $document.Text -Needle $rolle) {
    Add-OkMessage "$($document.Name) enthält die Zielrolle."
  } else {
    Add-WarningMessage "$($document.Name) enthält die Zielrolle nicht in der im Auftrag gespeicherten Form."
  }
}

$periodMatches = [regex]::Matches($profileText, '(?im)\b(?:0[1-9]|1[0-2])/\d{4}\s*[-–—]\s*(?:(?:0[1-9]|1[0-2])/\d{4}|fortlaufend)\b')
$periods = @($periodMatches | ForEach-Object { Normalize-Text -Text $_.Value } | Sort-Object -Unique)
$normalizedCv = Normalize-Text -Text $cvText
foreach ($period in $periods) {
  if ($normalizedCv.Contains($period)) {
    Add-OkMessage "Formaler Zeitraum im Lebenslauf gefunden: $period"
  } else {
    Add-ErrorMessage "Formaler Zeitraum aus dem Profil fehlt im Lebenslauf: $period"
  }
}

$requirements = @((Get-JsonProperty -Object $matrix -Name "requirements"))
if ($requirements.Count -eq 0 -or $null -eq $requirements[0]) {
  Add-ErrorMessage "Anforderungsmatrix enthält keine Anforderungen."
} else {
  $allowedStatuses = @("erfuellt", "teilweise", "nicht_belegt", "unklar", "nicht_relevant")
  foreach ($requirement in $requirements) {
    $description = [string](Get-JsonProperty -Object $requirement -Name "anforderung")
    $kind = [string](Get-JsonProperty -Object $requirement -Name "typ")
    $status = [string](Get-JsonProperty -Object $requirement -Name "status")
    $handling = [string](Get-JsonProperty -Object $requirement -Name "behandlung")
    if ([string]::IsNullOrWhiteSpace($description) -or [string]::IsNullOrWhiteSpace($kind)) {
      Add-ErrorMessage "Anforderungsmatrix enthält einen Eintrag ohne Anforderung oder Typ."
      continue
    }
    if ($status -notin $allowedStatuses) {
      Add-ErrorMessage "Ungültiger Matrixstatus bei '$description': $status"
      continue
    }
    if (($status -ne "erfuellt") -and [string]::IsNullOrWhiteSpace($handling)) {
      Add-ErrorMessage "Nicht vollständig erfüllte Anforderung hat keine dokumentierte Behandlung: $description"
    }
    if (($kind -eq "muss") -and ($status -in @("teilweise", "nicht_belegt", "unklar"))) {
      Add-WarningMessage "Muss-Anforderung ist nicht vollständig belegt: $description ($status)"
    } else {
      Add-OkMessage "Anforderung ist klassifiziert: $description ($status)"
    }
  }
}

if ($fields.Contains("Verfügbarkeit")) {
  $availability = [string]$fields["Verfügbarkeit"]
  if ((Test-ContainsText -Haystack $cvText -Needle $availability) -or (Test-ContainsText -Haystack $letterText -Needle $availability)) {
    Add-OkMessage "Verfügbarkeit ist konsistent sichtbar."
  } else {
    Add-WarningMessage "Verfügbarkeit aus den Stammdaten ist weder im Lebenslauf noch im Anschreiben sichtbar."
  }
}

if ($fields.Contains("Gewünschte Stellenart")) {
  $employmentType = [string]$fields["Gewünschte Stellenart"]
  if ($employmentType -notmatch '(?i)^\s*(\[|nicht festgelegt|offen|unbekannt)') {
    if ((Test-ContainsText -Haystack $cvText -Needle $employmentType) -or (Test-ContainsText -Haystack $letterText -Needle $employmentType)) {
      Add-OkMessage "Gewünschte Stellenart ist in den Unterlagen berücksichtigt."
    } else {
      Add-WarningMessage "Gewünschte Stellenart ist nicht in Lebenslauf oder Anschreiben erkennbar."
    }
  }
}

$defensivePatterns = @(
  '(?i)\bnicht belegt\b',
  '(?i)\bnoch keine (?:Berufs-?|Praxis-?)?erfahrung\b',
  '(?i)\bkeine Erfahrung\b',
  '(?i)ohne daraus .*Berufserfahrung abzuleiten',
  '(?i)ich erfülle .* nicht'
)
foreach ($pattern in $defensivePatterns) {
  if ($letterText -match $pattern) {
    Add-WarningMessage "Anschreiben enthält eine potenziell defensive Metaformulierung: $($Matches[0])"
  }
}

Write-JsonReport -Path $BerichtPath -Periods $periods

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
