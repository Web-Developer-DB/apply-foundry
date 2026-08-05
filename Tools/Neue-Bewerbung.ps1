[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Firma,

  [string]$Rolle = "Bewerbung",

  [ValidateSet("vollbewerbung", "anschreiben_mit_universalem_lebenslauf", "individuelle_auswahl")]
  [string]$Dokumentmodus,

  [ValidateSet("A", "B", "C", "D", "E")]
  [string]$UmfangAuswahl,

  [ValidateSet("lebenslauf", "anschreiben", "email_nachricht")]
  [string[]]$Dokumente = @(),

  [ValidateSet("auswahl", "direkter_auftrag", "fortgesetzter_auftrag")]
  [string]$UmfangQuelle = "auswahl",

  [switch]$EmailAlleinBestaetigt,

  [string]$UniversalLebenslaufPath,

  [string]$Datum = (Get-Date -Format "yyyy-MM-dd"),

  [string]$StellenbeschreibungPath,

  [string]$StammdatenPath = (Join-Path -Path $PSScriptRoot -ChildPath "..\Private\Daten\01_PERSOENLICHE_DATEN.md"),

  [string]$ProfilPath = (Join-Path -Path $PSScriptRoot -ChildPath "..\Private\Daten\02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md"),

  [string]$BewerbungenRoot = (Join-Path -Path $PSScriptRoot -ChildPath "..\Private\Bewerbungen"),

  [switch]$Fortsetzen,

  [switch]$StammdatenpruefungUeberspringen
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$script:PathComparison = if ([System.IO.Path]::DirectorySeparatorChar -eq '\') { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }

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

function Get-JsonProperty {
  param([object]$Object, [string]$Name)
  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

function Test-IsSafeChildPath {
  param(
    [string]$Candidate,
    [string]$Root
  )

  $candidateFull = [System.IO.Path]::GetFullPath($Candidate).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  return $candidateFull.StartsWith($rootFull + [System.IO.Path]::DirectorySeparatorChar, $script:PathComparison)
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

$modeWasProvided = $PSBoundParameters.ContainsKey("Dokumentmodus")
$selectionWasProvided = $PSBoundParameters.ContainsKey("UmfangAuswahl")
if (-not $modeWasProvided -and -not $selectionWasProvided) {
  Stop-WithValidationError -Message "Der gewünschte Bewerbungsumfang muss vor der Ordneranlage ausdrücklich mit -UmfangAuswahl A-E oder -Dokumentmodus festgelegt werden."
}

$includeCv = $false
$includeLetter = $false
$includeEmail = $false
$cvKind = "nicht_enthalten"
$normalizedDocuments = @($Dokumente | Sort-Object -Unique)

if ($selectionWasProvided) {
  switch ($UmfangAuswahl) {
    "A" {
      $resolvedMode = "vollbewerbung"
      $includeCv = $true
      $includeLetter = $true
      $includeEmail = $true
      $cvKind = "individuell"
    }
    "B" {
      $resolvedMode = "anschreiben_mit_universalem_lebenslauf"
      $includeCv = $true
      $includeLetter = $true
      $includeEmail = $true
      $cvKind = "universal_unveraendert"
    }
    "C" {
      $resolvedMode = "individuelle_auswahl"
      $includeCv = $true
      $cvKind = "individuell"
    }
    "D" {
      $resolvedMode = "individuelle_auswahl"
      $includeLetter = $true
    }
    "E" {
      if ($normalizedDocuments.Count -eq 0) {
        Stop-WithValidationError -Message "Umfang E erfordert mit -Dokumente mindestens lebenslauf, anschreiben oder email_nachricht."
      }
      $resolvedMode = "individuelle_auswahl"
      $includeCv = $normalizedDocuments -contains "lebenslauf"
      $includeLetter = $normalizedDocuments -contains "anschreiben"
      $includeEmail = $normalizedDocuments -contains "email_nachricht"
      if ($includeCv) {
        $cvKind = if ([string]::IsNullOrWhiteSpace($UniversalLebenslaufPath)) { "individuell" } else { "universal_unveraendert" }
      }
    }
  }
  if ($UmfangAuswahl -ne "E" -and $normalizedDocuments.Count -gt 0) {
    Stop-WithValidationError -Message "-Dokumente ist nur für Umfang E zulässig."
  }
  if ($modeWasProvided -and $Dokumentmodus -ne $resolvedMode) {
    Stop-WithValidationError -Message "Dokumentmodus und UmfangAuswahl widersprechen sich."
  }
  $Dokumentmodus = $resolvedMode
} else {
  switch ($Dokumentmodus) {
    "vollbewerbung" {
      $UmfangAuswahl = "A"
      $includeCv = $true
      $includeLetter = $true
      $includeEmail = $true
      $cvKind = "individuell"
    }
    "anschreiben_mit_universalem_lebenslauf" {
      $UmfangAuswahl = "B"
      $includeCv = $true
      $includeLetter = $true
      $includeEmail = $true
      $cvKind = "universal_unveraendert"
    }
    "individuelle_auswahl" {
      $UmfangAuswahl = "E"
      if ($normalizedDocuments.Count -eq 0) {
        Stop-WithValidationError -Message "Der Dokumentmodus individuelle_auswahl erfordert -Dokumente."
      }
      $includeCv = $normalizedDocuments -contains "lebenslauf"
      $includeLetter = $normalizedDocuments -contains "anschreiben"
      $includeEmail = $normalizedDocuments -contains "email_nachricht"
      if ($includeCv) {
        $cvKind = if ([string]::IsNullOrWhiteSpace($UniversalLebenslaufPath)) { "individuell" } else { "universal_unveraendert" }
      }
    }
  }
}

if (-not ($includeCv -or $includeLetter -or $includeEmail)) {
  Stop-WithValidationError -Message "Der Dokumentumfang muss mindestens ein Dokument enthalten."
}
if ($includeEmail -and -not $includeCv -and -not $includeLetter -and -not $EmailAlleinBestaetigt) {
  Stop-WithValidationError -Message "Ein reiner E-Mail-Auftrag ohne Anlagen erfordert nach ausdrücklicher Nutzerbestätigung -EmailAlleinBestaetigt."
}
$scopeCode = switch ($UmfangAuswahl) {
  "A" { "komplette_bewerbung" }
  "B" { "anschreiben_mit_universalem_lebenslauf" }
  "C" { "individueller_lebenslauf" }
  "D" { "nur_anschreiben" }
  default { "eigene_zusammenstellung" }
}
$scopeSummary = "Lebenslauf=$cvKind; Anschreiben=$($includeLetter.ToString().ToLowerInvariant()); E-Mail=$($includeEmail.ToString().ToLowerInvariant())"

foreach ($sourcePath in @($StammdatenPath, $ProfilPath)) {
  if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    Stop-WithValidationError -Message "Stammdaten- und Profilpfad müssen vor der Anlage auf vorhandene Dateien zeigen: $sourcePath"
  }
}
$StammdatenPath = (Resolve-Path -LiteralPath $StammdatenPath).Path
$ProfilPath = (Resolve-Path -LiteralPath $ProfilPath).Path
$stammdatenSourceHash = (Get-FileHash -LiteralPath $StammdatenPath -Algorithm SHA256).Hash
$profilSourceHash = (Get-FileHash -LiteralPath $ProfilPath -Algorithm SHA256).Hash
if ($stammdatenSourceHash -notmatch '^[A-Fa-f0-9]{64}$' -or $profilSourceHash -notmatch '^[A-Fa-f0-9]{64}$') {
  Stop-WithValidationError -Message "Stammdaten und Profil konnten nicht mit gültigem SHA-256 gebunden werden."
}

$applicantFileName = Get-MarkdownField -Path $StammdatenPath -Name "Dateiname-Name"
$universalSourceResolved = ""
$universalSourceHash = ""
if ($cvKind -eq "universal_unveraendert") {
  if ([string]::IsNullOrWhiteSpace($UniversalLebenslaufPath)) {
    Stop-WithValidationError -Message "Ein unveränderter universeller Lebenslauf erfordert -UniversalLebenslaufPath."
  }
  if (-not (Test-Path -LiteralPath $UniversalLebenslaufPath -PathType Leaf)) {
    Stop-WithValidationError -Message "UniversalLebenslaufPath muss auf eine vorhandene HTML-Datei zeigen: $UniversalLebenslaufPath"
  }
  $universalSourceResolved = (Resolve-Path -LiteralPath $UniversalLebenslaufPath).Path
  if ([System.IO.Path]::GetExtension($universalSourceResolved) -ne ".html") {
    Stop-WithValidationError -Message "Der universelle Lebenslauf muss als HTML-Quelle vorliegen."
  }
  if ([string]::IsNullOrWhiteSpace($applicantFileName)) {
    Stop-WithValidationError -Message "Dateiname-Name fehlt in den Stammdaten; universeller Lebenslauf kann nicht sicher zugeordnet werden."
  }
  if ([System.IO.Path]::GetFileNameWithoutExtension($universalSourceResolved) -ne "Lebenslauf - $applicantFileName") {
    Stop-WithValidationError -Message "Der universelle Lebenslauf muss exakt 'Lebenslauf - $applicantFileName.html' heißen."
  }
  $universalSourceText = Get-Content -LiteralPath $universalSourceResolved -Raw -Encoding UTF8
  if ($universalSourceText -match '(?i)\[ergänzen\]|\{\{[^}]+\}\}|TODO|DOKUMENT NOCH NICHT FINAL') {
    Stop-WithValidationError -Message "Der universelle Lebenslauf enthält sichtbare Platzhalter oder Entwurfsmarker."
  }
  $universalSourceHash = (Get-FileHash -LiteralPath $universalSourceResolved -Algorithm SHA256).Hash
} elseif (-not [string]::IsNullOrWhiteSpace($UniversalLebenslaufPath)) {
  Stop-WithValidationError -Message "-UniversalLebenslaufPath ist nur zulässig, wenn der gewählte Umfang einen universellen Lebenslauf enthält."
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
  $documentModeNotes = @($noteLines | Where-Object { $_ -like "- Dokumentmodus:*" })
  if ($documentModeNotes.Count -gt 0 -and $noteLines -notcontains "- Dokumentmodus: $Dokumentmodus") {
    Stop-WithValidationError -Message "Der vorhandene Arbeitsordner verwendet einen anderen Dokumentmodus. Fortsetzen wurde verweigert."
  }
  if (@($noteLines | Where-Object { $_ -like "- Dokumentumfang:*" }).Count -gt 0 -and $noteLines -notcontains "- Dokumentumfang: $scopeSummary") {
    Stop-WithValidationError -Message "Der vorhandene Arbeitsordner verwendet einen anderen Dokumentumfang. Fortsetzen wurde verweigert."
  }
  $existingAuftragPath = Join-Path -Path $arbeitsDir -ChildPath "Bewerbungsauftrag.json"
  if (-not (Test-Path -LiteralPath $existingAuftragPath -PathType Leaf)) {
    Stop-WithValidationError -Message "Der vorhandene Arbeitsordner enthält keinen prüfbaren Bewerbungsauftrag. Fortsetzen wurde verweigert."
  }
  $existingAuftrag = Get-Content -LiteralPath $existingAuftragPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $existingSchemaValue = Get-JsonProperty -Object $existingAuftrag -Name "schemaVersion"
  if (($existingSchemaValue -isnot [int] -and $existingSchemaValue -isnot [long]) -or
      [long]$existingSchemaValue -lt 1 -or [long]$existingSchemaValue -gt 4) {
    Stop-WithValidationError -Message "Bewerbungsauftrag enthält keine unterstützte schemaVersion 1 bis 4."
  }
  $existingSchema = [int]$existingSchemaValue
  if ($existingSchema -eq 4) {
    $existingScope = Get-JsonProperty -Object $existingAuftrag -Name "dokumentumfang"
    $existingLetter = Get-JsonProperty -Object $existingScope -Name "anschreiben"
    $existingEmail = Get-JsonProperty -Object $existingScope -Name "emailNachricht"
    $existingEmailOnlyApproval = Get-JsonProperty -Object $existingScope -Name "emailAlleinBestaetigt"
    if ($null -eq $existingScope -or
        [string](Get-JsonProperty -Object $existingScope -Name "auswahl") -cne $UmfangAuswahl -or
        [string](Get-JsonProperty -Object $existingScope -Name "kennung") -cne $scopeCode -or
        [string](Get-JsonProperty -Object $existingScope -Name "lebenslauf") -cne $cvKind -or
        $existingLetter -isnot [bool] -or [bool]$existingLetter -ne $includeLetter -or
        $existingEmail -isnot [bool] -or [bool]$existingEmail -ne $includeEmail -or
        $existingEmailOnlyApproval -isnot [bool] -or [bool]$existingEmailOnlyApproval -ne [bool]$EmailAlleinBestaetigt -or
        [string](Get-JsonProperty -Object $existingAuftrag -Name "dokumentmodus") -cne $Dokumentmodus) {
      Stop-WithValidationError -Message "Bewerbungsauftrag und gewünschter Dokumentumfang stimmen beim Fortsetzen nicht exakt überein."
    }
  } else {
    $legacyMode = [string](Get-JsonProperty -Object $existingAuftrag -Name "dokumentmodus")
    if ($legacyMode -eq "anschreiben_mit_universalem_lebenslauf") {
      $legacySelection = "B"
    } elseif ([string]::IsNullOrWhiteSpace($legacyMode) -or $legacyMode -eq "vollbewerbung") {
      $legacySelection = "A"
      $legacyMode = "vollbewerbung"
    } else {
      Stop-WithValidationError -Message "Legacy-Bewerbungsauftrag enthält keinen eindeutig fortsetzbaren Dokumentumfang. Zuerst auf Schema 4 migrieren."
    }
    if ($UmfangAuswahl -cne $legacySelection -or $Dokumentmodus -cne $legacyMode) {
      Stop-WithValidationError -Message "Legacy-Bewerbungsauftrag repräsentiert einen anderen Dokumentumfang. Fortsetzen wurde verweigert."
    }
  }
  if ($cvKind -eq "universal_unveraendert") {
    $existingUniversal = Get-JsonProperty -Object $existingAuftrag -Name "universalLebenslauf"
    $existingUniversalPath = [string](Get-JsonProperty -Object $existingUniversal -Name "sourceHtmlPath")
    $expectedUniversalCandidateName = "Lebenslauf - $applicantFileName.html"
    $sameUniversalPath = -not [string]::IsNullOrWhiteSpace($existingUniversalPath) -and
      [string]::Equals(
        [System.IO.Path]::GetFullPath($existingUniversalPath),
        [System.IO.Path]::GetFullPath($universalSourceResolved),
          $script:PathComparison
      )
    if (-not $sameUniversalPath -or
        [string](Get-JsonProperty -Object $existingUniversal -Name "sourceHtmlSha256BeiAnlage") -ine $universalSourceHash -or
        [string](Get-JsonProperty -Object $existingUniversal -Name "kandidatDatei") -cne $expectedUniversalCandidateName -or
        [string](Get-JsonProperty -Object $existingAuftrag -Name "bewerberDateiname") -cne $applicantFileName) {
      Stop-WithValidationError -Message "Beim Fortsetzen wurde eine andere Universal-Lebenslauf-Quelle übergeben."
    }
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
$universalCandidateFile = if ([string]::IsNullOrWhiteSpace($applicantFileName)) { "" } else { Join-Path -Path $kandidatDir -ChildPath "Lebenslauf - $applicantFileName.html" }

foreach ($expectedFilePath in @(
  $stellenbeschreibungKandidatFile,
  $stellenbeschreibungEntwurfFile,
  $analyseEntwurfFile,
  $lebenslaufEntwurfFile,
  $anschreibenEntwurfFile,
  $arbeitsnotizenFile,
  $emailEntwurfFile,
  $qualitaetscheckEntwurfFile,
  $offeneFragenEntwurfFile,
  $anforderungsmatrixEntwurfFile,
  $auftragFile,
  $druckHinweisFile,
  $universalCandidateFile
)) {
  if (-not [string]::IsNullOrWhiteSpace($expectedFilePath) -and
      (Test-Path -LiteralPath $expectedFilePath) -and
      -not (Test-Path -LiteralPath $expectedFilePath -PathType Leaf)) {
    throw "Erwarteter Dateipfad existiert, ist aber keine reguläre Datei: $expectedFilePath"
  }
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

if ($cvKind -eq "universal_unveraendert") {
  if (Test-Path -LiteralPath $universalCandidateFile -PathType Leaf) {
    $candidateUniversalHash = (Get-FileHash -LiteralPath $universalCandidateFile -Algorithm SHA256).Hash
    if ($candidateUniversalHash -ne $universalSourceHash) {
      throw "Der Lebenslauf im Kandidatenordner weicht von der freigegebenen Universalquelle ab. Überschreiben wurde verweigert."
    }
  } elseif (Test-Path -LiteralPath $universalCandidateFile) {
    throw "Der erwartete universelle Lebenslauf im Kandidatenordner ist keine reguläre Datei."
  } else {
    Copy-Item -LiteralPath $universalSourceResolved -Destination $universalCandidateFile
  }
}

if (-not (Test-Path -LiteralPath $auftragFile -PathType Leaf)) {
  $bewerbungslogistik = [ordered]@{
    verfuegbarkeit = Get-MarkdownField -Path $StammdatenPath -Name "Verfügbarkeit"
    fruehesterEintrittstermin = Get-MarkdownField -Path $StammdatenPath -Name "Frühester Eintrittstermin"
    stellenart = Get-MarkdownField -Path $StammdatenPath -Name "Gewünschte Stellenart"
    stundenumfang = Get-MarkdownField -Path $StammdatenPath -Name "Gewünschter Stundenumfang"
    arbeitsmodell = Get-MarkdownField -Path $StammdatenPath -Name "Gewünschtes Arbeitsmodell"
    region = Get-MarkdownField -Path $StammdatenPath -Name "Gewünschte Region"
    maximalePendeldistanz = Get-MarkdownField -Path $StammdatenPath -Name "Maximale Pendeldistanz"
    reisebereitschaft = Get-MarkdownField -Path $StammdatenPath -Name "Reisebereitschaft"
    schichtOderWochenendbereitschaft = Get-MarkdownField -Path $StammdatenPath -Name "Schicht- oder Wochenendbereitschaft"
    befristung = Get-MarkdownField -Path $StammdatenPath -Name "Befristung"
    umzugsbereitschaft = Get-MarkdownField -Path $StammdatenPath -Name "Umzugsbereitschaft"
    wunschgehaltVerwenden = Get-MarkdownField -Path $StammdatenPath -Name "Wunschgehalt verwenden"
    wunschgehaltManuell = Get-MarkdownField -Path $StammdatenPath -Name "Wunschgehalt manuell"
    gehaltsmodell = Get-MarkdownField -Path $StammdatenPath -Name "Gehaltsmodell"
    gehaltsregion = Get-MarkdownField -Path $StammdatenPath -Name "Gehaltsregion"
    gehaltslogik = Get-MarkdownField -Path $StammdatenPath -Name "Gehaltslogik"
  }
  $sourceEvidence = [ordered]@{
    stammdatenSha256BeiAnlage = $stammdatenSourceHash
    profilSha256BeiAnlage = $profilSourceHash
  }
  $auftrag = [ordered]@{
    schemaVersion = 4
    firma = $Firma
    firmaSlug = $firmaSlug
    rolle = $Rolle
    rolleSlug = $rolleSlug
    datum = $Datum
    bewerberDateiname = $applicantFileName
    zielOrdner = $zielDir
    arbeitsOrdner = $arbeitsDir
    kandidatOrdner = $kandidatDir
    dokumentmodus = $Dokumentmodus
    dokumentumfang = [ordered]@{
      auswahl = $UmfangAuswahl
      kennung = $scopeCode
      lebenslauf = $cvKind
      anschreiben = $includeLetter
      emailNachricht = $includeEmail
      quelle = $UmfangQuelle
      bestaetigt = $true
      emailAlleinBestaetigt = [bool]$EmailAlleinBestaetigt
      bestaetigtAtUtc = [datetime]::UtcNow.ToString("o")
    }
    universalLebenslauf = if ($cvKind -eq "universal_unveraendert") {
      [ordered]@{
        sourceHtmlPath = $universalSourceResolved
        sourceHtmlSha256BeiAnlage = $universalSourceHash
        kandidatDatei = "Lebenslauf - $applicantFileName.html"
      }
    } else {
      $null
    }
    seitenstrategie = if ($includeCv) { "noch_festzulegen" } else { "nicht_erforderlich" }
    bewerbungslogistik = $bewerbungslogistik
    bewerbungsentscheidung = "noch_festzulegen"
    darstellungsoptionen = [ordered]@{
      schulbildungsmodus = if ($includeCv) { "noch_festzulegen" } else { "nicht_erforderlich" }
      profillinksModus = if ($includeCv) { "noch_festzulegen" } else { "nicht_erforderlich" }
      profillinksAuswahl = @()
    }
    dialog = [ordered]@{
      schemaVersion = 1
      status = "profilabgleich_ausstehend"
      rueckfragen = @()
      angaben = @()
      updatedAtUtc = [datetime]::UtcNow.ToString("o")
    }
    quellnachweise = $sourceEvidence
    createdAtUtc = [datetime]::UtcNow.ToString("o")
  }
  Set-Content -LiteralPath $auftragFile -Encoding UTF8 -Value ($auftrag | ConvertTo-Json -Depth 8)
}

if (-not (Test-Path -LiteralPath $anforderungsmatrixEntwurfFile)) {
  Set-Content -LiteralPath $anforderungsmatrixEntwurfFile -Encoding UTF8 -Value @"
{
  "schemaVersion": 2,
  "requirements": [
    {
      "id": "muss-1",
      "anforderung": "durch den Agenten aus der Stellenbeschreibung zu extrahieren",
      "typ": "muss",
      "kategorie": "fachlich",
      "gewichtung": "hoch",
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

if ($includeCv -and $cvKind -eq "individuell" -and -not (Test-Path -LiteralPath $lebenslaufEntwurfFile)) {
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

if ($includeLetter -and -not (Test-Path -LiteralPath $anschreibenEntwurfFile)) {
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
- Dokumentmodus: $Dokumentmodus
- Dokumentumfang: $scopeSummary
- Finaler Bewerbungsordner: $zielDir
- Entwurfs-/Arbeitsdateien: $arbeitsDir
- Kandidatendateien vor Freigabe: $kandidatDir

Dieser Ordner ist nur für temporäre Entwürfe und Arbeitsnotizen gedacht.
Versandfertig benannte Kandidatendateien gehören zunächst in den Kandidatenordner.
Der finale Bewerbungsordner bleibt bis zur erfolgreichen atomaren Veröffentlichung leer.
"@
}

if ($includeEmail -and -not (Test-Path -LiteralPath $emailEntwurfFile)) {
  $emailLead = if ($includeCv -and $includeLetter) {
    "anbei sende ich Ihnen meine Bewerbungsunterlagen für die Position als $Rolle bei $Firma."
  } elseif ($includeCv) {
    "anbei sende ich Ihnen meinen Lebenslauf für die Position als $Rolle bei $Firma."
  } elseif ($includeLetter) {
    "anbei sende ich Ihnen mein Anschreiben für die Position als $Rolle bei $Firma."
  } else {
    "hiermit bewerbe ich mich für die Position als $Rolle bei $Firma."
  }
  Set-Content -LiteralPath $emailEntwurfFile -Encoding UTF8 -Value @"
Betreff: Bewerbung als $Rolle - [Name aus Private/Daten/01_PERSOENLICHE_DATEN.md]

Sehr geehrte Damen und Herren,

$emailLead

Über eine Rückmeldung freue ich mich.

Mit freundlichen Grüßen
[Name aus Private/Daten/01_PERSOENLICHE_DATEN.md]
"@
}

if (-not (Test-Path -LiteralPath $qualitaetscheckEntwurfFile)) {
  $documentChecklistLines = @()
  if ($includeCv) { $documentChecklistLines += "- [ ] Lebenslauf gemäß gewählter Strategie geprüft" }
  if ($includeLetter) { $documentChecklistLines += "- [ ] Anschreiben individuell formuliert" }
  if ($includeEmail) { $documentChecklistLines += "- [ ] E-Mail-Nachricht erstellt" }
  Set-Content -LiteralPath $qualitaetscheckEntwurfFile -Encoding UTF8 -Value @"
# Qualitätscheck

- [ ] Stellenbeschreibung analysiert
$($documentChecklistLines -join "`r`n")
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
Write-Output "Dokumentmodus: $Dokumentmodus"
Write-Output "Dokumentumfang: $scopeSummary"
if ($cvKind -eq "universal_unveraendert") {
  Write-Output "Universeller Lebenslauf unverändert übernommen: $universalCandidateFile"
}
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
