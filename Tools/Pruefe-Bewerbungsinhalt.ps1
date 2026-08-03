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
  if ($null -eq $Object) { return $null }
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
  param(
    [string]$Path,
    [array]$Periods,
    [array]$RequiredPeriods,
    [array]$CompactSchoolPeriods,
    [object]$FitAssessment,
    [string]$SchoolMode,
    [string]$ProfileLinksMode,
    [string]$DocumentMode
  )
  if ([string]::IsNullOrWhiteSpace($Path)) { return }
  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $parent = Split-Path -Path $fullPath -Parent
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -Path $parent -ItemType Directory -Force | Out-Null
  }
  $report = [ordered]@{
    schemaVersion = 3
    checkedAtUtc = [datetime]::UtcNow.ToString("o")
    applicationFolder = [System.IO.Path]::GetFullPath($Ordner)
    status = if ($errors.Count -gt 0) { "fehler" } elseif ($warnings.Count -gt 0) { "warnung" } else { "ok" }
    errors = @($errors)
    warnings = @($warnings)
    oks = @($oks)
    checkedFormalPeriods = $Periods
    requiredFormalPeriods = $RequiredPeriods
    compactedSchoolPeriods = $CompactSchoolPeriods
    schoolMode = $SchoolMode
    profileLinksMode = $ProfileLinksMode
    documentMode = $DocumentMode
    fitAssessment = $FitAssessment
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
$internalFolder = Join-Path -Path $resolvedFolder -ChildPath "Intern"
$shippingFolder = Join-Path -Path $resolvedFolder -ChildPath "Versand"
$isStructuredPublication = (Test-Path -LiteralPath $internalFolder -PathType Container) -and (Test-Path -LiteralPath $shippingFolder -PathType Container)
$documentFolder = if ($isStructuredPublication) { $internalFolder } else { $resolvedFolder }
$emailFolder = if ($isStructuredPublication) { $shippingFolder } else { $resolvedFolder }
$cvFiles = @(Get-ChildItem -LiteralPath $documentFolder -File -Filter "Lebenslauf - *.html")
$letterFiles = @(Get-ChildItem -LiteralPath $documentFolder -File -Filter "Anschreiben - *.html")
$emailFiles = @(Get-ChildItem -LiteralPath $emailFolder -File -Filter "Email-Nachricht--*.md")
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
$auftragSchema = [int](Get-JsonProperty -Object $auftrag -Name "schemaVersion")
$applicationLogistics = Get-JsonProperty -Object $auftrag -Name "bewerbungslogistik"
$displayOptions = Get-JsonProperty -Object $auftrag -Name "darstellungsoptionen"
$schoolMode = [string](Get-JsonProperty -Object $displayOptions -Name "schulbildungsmodus")
$profileLinksMode = [string](Get-JsonProperty -Object $displayOptions -Name "profillinksModus")
$profileLinksSelection = @((Get-JsonProperty -Object $displayOptions -Name "profillinksAuswahl"))
$applicationDecision = [string](Get-JsonProperty -Object $auftrag -Name "bewerbungsentscheidung")
$documentMode = [string](Get-JsonProperty -Object $auftrag -Name "dokumentmodus")
$universalCv = Get-JsonProperty -Object $auftrag -Name "universalLebenslauf"

if ($auftragSchema -lt 3 -and [string]::IsNullOrWhiteSpace($documentMode)) {
  $documentMode = "vollbewerbung"
}

if ($auftragSchema -ge 2) {
  if ($applicationDecision -notin @("bewerben", "nicht_bewerben")) {
    Add-ErrorMessage "Bewerbungsauftrag enthält keine endgültige Bewerbungsentscheidung. Erlaubt: bewerben oder nicht_bewerben."
  } elseif ($applicationDecision -eq "nicht_bewerben") {
    Add-ErrorMessage "Bewerbungsauftrag ist auf nicht_bewerben gesetzt und darf nicht finalisiert werden."
  } else {
    Add-OkMessage "Bewerbungsentscheidung ist ausdrücklich auf bewerben gesetzt."
  }
  if ($schoolMode -notin @("vollstaendig", "recruiter_kompakt")) {
    Add-ErrorMessage "Schulbildungsmodus ist nicht endgültig festgelegt. Erlaubt: vollstaendig oder recruiter_kompakt."
  }
  if ($profileLinksMode -notin @("alle", "rollenrelevant", "keine")) {
    Add-ErrorMessage "Profillinks-Modus ist nicht endgültig festgelegt. Erlaubt: alle, rollenrelevant oder keine."
  }
} else {
  if ([string]::IsNullOrWhiteSpace($schoolMode)) { $schoolMode = "vollstaendig" }
  if ([string]::IsNullOrWhiteSpace($profileLinksMode)) { $profileLinksMode = "legacy_ungeprueft" }
}

if ($auftragSchema -ge 3) {
  if ($documentMode -notin @("vollbewerbung", "anschreiben_mit_universalem_lebenslauf")) {
    Add-ErrorMessage "Dokumentmodus ist ungültig. Erlaubt: vollbewerbung oder anschreiben_mit_universalem_lebenslauf."
  } else {
    Add-OkMessage "Dokumentmodus ist eindeutig festgelegt: $documentMode."
  }
}

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

if ($documentMode -eq "anschreiben_mit_universalem_lebenslauf") {
  $expectedUniversalHash = [string](Get-JsonProperty -Object $universalCv -Name "sourceHtmlSha256BeiAnlage")
  $expectedUniversalName = [string](Get-JsonProperty -Object $universalCv -Name "kandidatDatei")
  if ([string]::IsNullOrWhiteSpace($expectedUniversalHash) -or [string]::IsNullOrWhiteSpace($expectedUniversalName)) {
    Add-ErrorMessage "Der Anschreiben-Modus enthält keinen vollständigen Hashnachweis für den universellen Lebenslauf."
  } elseif ($cvFiles[0].Name -ne $expectedUniversalName) {
    Add-ErrorMessage "Der Kandidaten-Lebenslauf stimmt nicht mit dem im Auftrag eingefrorenen Universaldateinamen überein."
  } else {
    $actualUniversalHash = (Get-FileHash -LiteralPath $cvFiles[0].FullName -Algorithm SHA256).Hash
    if ($actualUniversalHash -eq $expectedUniversalHash) {
      Add-OkMessage "Universeller Lebenslauf wurde unverändert aus dem eingefrorenen Snapshot übernommen."
    } else {
      Add-ErrorMessage "Universeller Lebenslauf wurde für die konkrete Stelle verändert; Anschreiben-Modus verletzt."
    }
  }
}

if (Test-ContainsText -Haystack $letterText -Needle $firma) {
  Add-OkMessage "Anschreiben enthält die Firma aus dem Bewerbungsauftrag."
} else {
  Add-ErrorMessage "Anschreiben enthält die Firma aus dem Bewerbungsauftrag nicht."
}
$roleDocuments = @(
  [pscustomobject]@{ Name = "Anschreiben"; Text = $letterText },
  [pscustomobject]@{ Name = "E-Mail-Betreff"; Text = ($emailText -split "`r?`n", 2)[0] }
)
if ($documentMode -eq "vollbewerbung") {
  $roleDocuments = @([pscustomobject]@{ Name = "Lebenslauf"; Text = $cvText }) + $roleDocuments
} else {
  Add-OkMessage "Zielrollenprüfung im universellen Lebenslauf ist im Anschreiben-Modus bewusst ausgenommen."
}
foreach ($document in $roleDocuments) {
  if (Test-ContainsText -Haystack $document.Text -Needle $rolle) {
    Add-OkMessage "$($document.Name) enthält die Zielrolle."
  } else {
    Add-WarningMessage "$($document.Name) enthält die Zielrolle nicht in der im Auftrag gespeicherten Form."
  }
}

$periodMatches = [regex]::Matches($profileText, '(?im)\b(?:0[1-9]|1[0-2])/\d{4}\s*[-–—]\s*(?:(?:0[1-9]|1[0-2])/\d{4}|fortlaufend)\b')
$periods = @($periodMatches | ForEach-Object { Normalize-Text -Text $_.Value } | Sort-Object -Unique)
$schoolSectionMatch = [regex]::Match($profileText, '(?ims)^##\s+Schulbildung\s*$\s*(?<body>.*?)(?=^##\s+|\z)')
$schoolPeriods = if ($schoolSectionMatch.Success) {
  @([regex]::Matches($schoolSectionMatch.Groups["body"].Value, '(?im)\b(?:0[1-9]|1[0-2])/\d{4}\s*[-–—]\s*(?:(?:0[1-9]|1[0-2])/\d{4}|fortlaufend)\b') | ForEach-Object { Normalize-Text -Text $_.Value } | Sort-Object -Unique)
} else {
  @()
}
$requiredPeriods = if ($schoolMode -eq "recruiter_kompakt") {
  @($periods | Where-Object { $_ -notin $schoolPeriods })
} else {
  @($periods)
}
$compactedSchoolPeriods = if ($schoolMode -eq "recruiter_kompakt") { @($schoolPeriods) } else { @() }
$normalizedCv = Normalize-Text -Text $cvText
foreach ($period in $requiredPeriods) {
  if ($normalizedCv.Contains($period)) {
    Add-OkMessage "Formaler Zeitraum im Lebenslauf gefunden: $period"
  } else {
    Add-ErrorMessage "Formaler Zeitraum aus dem Profil fehlt im Lebenslauf: $period"
  }
}
if ($schoolMode -eq "recruiter_kompakt") {
  if ($cvText -match '(?i)Schulbildung|Schule|Hochschulzugangsberechtigung') {
    Add-OkMessage "Recruiter-kompakter Schulbildungsmodus ist gewählt und eine zusammengefasste Schulbildungsangabe bleibt sichtbar."
  } else {
    Add-ErrorMessage "Recruiter-kompakter Schulbildungsmodus erfordert weiterhin eine sichtbare zusammengefasste Schulbildungsangabe."
  }
}

$requirements = @((Get-JsonProperty -Object $matrix -Name "requirements"))
$matrixSchema = [int](Get-JsonProperty -Object $matrix -Name "schemaVersion")
$weightPoints = @{ kritisch = 4.0; hoch = 3.0; mittel = 2.0; niedrig = 1.0 }
$statusFactors = @{ erfuellt = 1.0; teilweise = 0.5; nicht_belegt = 0.0; unklar = 0.0 }
$fitMaximum = 0.0
$fitAchieved = 0.0
$criticalGaps = New-Object System.Collections.Generic.List[string]
$weightedRequirements = @()
if ($requirements.Count -eq 0 -or $null -eq $requirements[0]) {
  Add-ErrorMessage "Anforderungsmatrix enthält keine Anforderungen."
} else {
  $allowedStatuses = @("erfuellt", "teilweise", "nicht_belegt", "unklar", "nicht_relevant")
  $allowedCategories = @("fachlich", "erfahrung", "formal", "arbeitsweise", "logistik")
  foreach ($requirement in $requirements) {
    $description = [string](Get-JsonProperty -Object $requirement -Name "anforderung")
    $kind = [string](Get-JsonProperty -Object $requirement -Name "typ")
    $status = [string](Get-JsonProperty -Object $requirement -Name "status")
    $handling = [string](Get-JsonProperty -Object $requirement -Name "behandlung")
    $weight = [string](Get-JsonProperty -Object $requirement -Name "gewichtung")
    $category = [string](Get-JsonProperty -Object $requirement -Name "kategorie")
    $evidenceType = [string](Get-JsonProperty -Object $requirement -Name "belegart")
    $evidence = [string](Get-JsonProperty -Object $requirement -Name "beleg")
    if ([string]::IsNullOrWhiteSpace($description) -or [string]::IsNullOrWhiteSpace($kind)) {
      Add-ErrorMessage "Anforderungsmatrix enthält einen Eintrag ohne Anforderung oder Typ."
      continue
    }
    if ($kind -notin @("muss", "kann")) {
      Add-ErrorMessage "Anforderung '$description' enthält einen ungültigen Typ: $kind"
    }
    if ($status -notin $allowedStatuses) {
      Add-ErrorMessage "Ungültiger Matrixstatus bei '$description': $status"
      continue
    }
    if ([string]::IsNullOrWhiteSpace($weight)) {
      $weight = if ($kind -eq "muss") { "hoch" } else { "niedrig" }
      if ($matrixSchema -ge 2) {
        Add-ErrorMessage "Anforderung '$description' enthält keine Gewichtung."
      }
    } elseif (-not $weightPoints.ContainsKey($weight)) {
      Add-ErrorMessage "Anforderung '$description' enthält eine ungültige Gewichtung: $weight"
      continue
    }
    if ($matrixSchema -ge 2 -and [string]::IsNullOrWhiteSpace($category)) {
      Add-ErrorMessage "Anforderung '$description' enthält keine Kategorie."
    } elseif ($matrixSchema -ge 2 -and $category -notin $allowedCategories) {
      Add-ErrorMessage "Anforderung '$description' enthält eine ungültige Kategorie: $category"
    }
    if ($matrixSchema -ge 2 -and $status -in @("erfuellt", "teilweise") -and
        ([string]::IsNullOrWhiteSpace($evidenceType) -or [string]::IsNullOrWhiteSpace($evidence))) {
      Add-ErrorMessage "Belegte oder teilweise belegte Anforderung benötigt Belegart und konkreten Beleg: $description"
    }
    if (($status -ne "erfuellt") -and [string]::IsNullOrWhiteSpace($handling)) {
      Add-ErrorMessage "Nicht vollständig erfüllte Anforderung hat keine dokumentierte Behandlung: $description"
    }
    if (($kind -eq "muss") -and ($status -in @("teilweise", "nicht_belegt", "unklar"))) {
      Add-WarningMessage "Muss-Anforderung ist nicht vollständig belegt: $description ($status)"
    } else {
      Add-OkMessage "Anforderung ist klassifiziert: $description ($status)"
    }

    if ($status -ne "nicht_relevant" -and $weightPoints.ContainsKey($weight)) {
      $points = [double]$weightPoints[$weight]
      $factor = if ($statusFactors.ContainsKey($status)) { [double]$statusFactors[$status] } else { 0.0 }
      $fitMaximum += $points
      $fitAchieved += ($points * $factor)
      if ($weight -eq "kritisch" -and $status -ne "erfuellt") {
        $criticalGaps.Add($description) | Out-Null
      }
      $weightedRequirements += [ordered]@{
        id = [string](Get-JsonProperty -Object $requirement -Name "id")
        anforderung = $description
        typ = $kind
        kategorie = $category
        gewichtung = $weight
        status = $status
        beitrag = [math]::Round(($points * $factor), 2)
        maximum = $points
      }
    }
  }
}

$fitPercent = if ($fitMaximum -gt 0) { [math]::Round(($fitAchieved / $fitMaximum) * 100.0, 1) } else { 0.0 }
$fitClassification = if ($criticalGaps.Count -eq 0 -and $fitPercent -ge 80) {
  "stark"
} elseif ($criticalGaps.Count -le 1 -and $fitPercent -ge 55) {
  "vertretbar_mit_risiken"
} else {
  "stretch"
}
$fitAssessment = [ordered]@{
  scorePercent = $fitPercent
  classification = $fitClassification
  achievedPoints = [math]::Round($fitAchieved, 2)
  maximumPoints = [math]::Round($fitMaximum, 2)
  criticalGaps = @($criticalGaps)
  requirements = $weightedRequirements
}
if ($fitClassification -eq "stretch") {
  Add-WarningMessage "Gewichtete Eignungsbewertung: Stretch-Bewerbung ($fitPercent %, kritische Lücken: $($criticalGaps.Count))."
} else {
  Add-OkMessage "Gewichtete Eignungsbewertung: $fitClassification ($fitPercent %)."
}

$fitScorePattern = '(?im)(?:Eignung|Passung|gewichtete\s+(?:Eignungsbewertung|Anforderungsmatrix))[^\r\n]{0,100}?(?<score>\d+(?:[\.,]\d+)?)\s*(?:%|Prozent)|(?<scoreBefore>\d+(?:[\.,]\d+)?)\s*(?:%|Prozent)[^\r\n]{0,70}?(?:Eignung|Passung)'
foreach ($scoreDocumentName in @("Analyse.md", "Qualitaetscheck.md")) {
  $scoreDocumentPath = Join-Path -Path $documentFolder -ChildPath $scoreDocumentName
  if (-not (Test-Path -LiteralPath $scoreDocumentPath -PathType Leaf)) { continue }
  $scoreDocumentText = Get-Content -LiteralPath $scoreDocumentPath -Raw -Encoding UTF8
  foreach ($scoreMatch in [regex]::Matches($scoreDocumentText, $fitScorePattern)) {
    $scoreText = if ($scoreMatch.Groups["score"].Success) { $scoreMatch.Groups["score"].Value } else { $scoreMatch.Groups["scoreBefore"].Value }
    $documentScore = 0.0
    if ([double]::TryParse($scoreText.Replace(',', '.'), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$documentScore)) {
      if ([math]::Abs($documentScore - $fitPercent) -gt 0.11) {
        Add-ErrorMessage "$scoreDocumentName nennt eine Eignungskennzahl von $scoreText Prozent, berechnet wurden $fitPercent Prozent."
      } else {
        Add-OkMessage "$scoreDocumentName verwendet die berechnete Eignungskennzahl von $fitPercent Prozent."
      }
    }
  }
}

function Get-EffectiveLogisticsValue {
  param([string]$ApplicationProperty, [string]$MasterField)
  $applicationValue = [string](Get-JsonProperty -Object $applicationLogistics -Name $ApplicationProperty)
  if (-not [string]::IsNullOrWhiteSpace($applicationValue) -and $applicationValue -notmatch '^(?i:nicht festgelegt|offen|noch offen|unbekannt)$') {
    return $applicationValue
  }
  if ($fields.Contains($MasterField)) {
    return [string]$fields[$MasterField]
  }
  return ""
}

$availability = Get-EffectiveLogisticsValue -ApplicationProperty "verfuegbarkeit" -MasterField "Verfügbarkeit"
if (-not [string]::IsNullOrWhiteSpace($availability)) {
  if ((Test-ContainsText -Haystack $cvText -Needle $availability) -or (Test-ContainsText -Haystack $letterText -Needle $availability)) {
    Add-OkMessage "Verfügbarkeit ist konsistent sichtbar."
  } else {
    Add-WarningMessage "Verfügbarkeit aus den Stammdaten ist weder im Lebenslauf noch im Anschreiben sichtbar."
  }
}

$employmentType = Get-EffectiveLogisticsValue -ApplicationProperty "stellenart" -MasterField "Gewünschte Stellenart"
if (-not [string]::IsNullOrWhiteSpace($employmentType)) {
  if ($employmentType -notmatch '(?i)^\s*(\[|nicht festgelegt|offen|unbekannt)') {
    if ((Test-ContainsText -Haystack $cvText -Needle $employmentType) -or (Test-ContainsText -Haystack $letterText -Needle $employmentType)) {
      Add-OkMessage "Gewünschte Stellenart ist in den Unterlagen berücksichtigt."
    } else {
      Add-WarningMessage "Gewünschte Stellenart ist nicht in Lebenslauf oder Anschreiben erkennbar."
    }
  }
}

$profileFieldNames = @("GitHub", "Portfolio", "LinkedIn", "Xing")
$availableProfileLinks = [ordered]@{}
foreach ($profileFieldName in $profileFieldNames) {
  if ($fields.Contains($profileFieldName)) {
    $profileValue = [string]$fields[$profileFieldName]
    if (-not [string]::IsNullOrWhiteSpace($profileValue) -and $profileValue -notmatch '^(?i:nicht angegeben|nicht festgelegt|offen|unbekannt)$') {
      $availableProfileLinks[$profileFieldName] = $profileValue
    }
  }
}
if ($auftragSchema -ge 2 -and $profileLinksMode -in @("alle", "rollenrelevant", "keine")) {
  $selectedNames = @($profileLinksSelection | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  if ($profileLinksMode -eq "alle") {
    $selectedNames = @($availableProfileLinks.Keys)
  } elseif ($profileLinksMode -eq "keine" -and $selectedNames.Count -gt 0) {
    Add-ErrorMessage "Profillinks-Modus 'keine' darf keine profillinksAuswahl enthalten."
  }
  foreach ($selectedName in $selectedNames) {
    if (-not $availableProfileLinks.Contains($selectedName)) {
      Add-ErrorMessage "Ausgewählter Profillink ist in den Stammdaten nicht gepflegt: $selectedName"
      continue
    }
    if (-not (Test-ContainsText -Haystack $cvText -Needle ([string]$availableProfileLinks[$selectedName]))) {
      Add-ErrorMessage "Ausgewählter Profillink fehlt im Lebenslauf: $selectedName"
    }
  }
  foreach ($profileName in $availableProfileLinks.Keys) {
    $linkIsVisible = Test-ContainsText -Haystack $cvText -Needle ([string]$availableProfileLinks[$profileName])
    if ($linkIsVisible -and $profileName -notin $selectedNames) {
      Add-ErrorMessage "Nicht ausgewählter Profillink ist im Lebenslauf sichtbar: $profileName"
    }
  }
  Add-OkMessage "Rollenabhängige Profillink-Regel wurde geprüft: $profileLinksMode."
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

Write-JsonReport -Path $BerichtPath -Periods $periods -RequiredPeriods $requiredPeriods -CompactSchoolPeriods $compactedSchoolPeriods -FitAssessment $fitAssessment -SchoolMode $schoolMode -ProfileLinksMode $profileLinksMode -DocumentMode $documentMode

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
