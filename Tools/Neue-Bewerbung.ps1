#requires -Version 7.6
#requires -PSEdition Core

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Firma,

  [string]$Rolle = "Bewerbung",

  [ValidateSet("vollbewerbung", "anschreiben_mit_universalem_lebenslauf", "individuelle_auswahl")]
  [string]$Dokumentmodus,

  [ValidateSet("A", "B", "C", "D", "E")]
  [string]$UmfangAuswahl,

  [string[]]$Dokumente = @(),

  [ValidateSet("auswahl", "direkter_auftrag", "fortgesetzter_auftrag")]
  [string]$UmfangQuelle = "auswahl",

  [switch]$EmailAlleinBestaetigt,

  [string]$UniversalLebenslaufPath,

  [string]$Datum = (Get-Date -Format "yyyy-MM-dd"),

  [string]$StellenbeschreibungPath,

  [string]$StammdatenPath = (Join-Path -Path (Join-Path -Path (Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "..") -ChildPath "Private") -ChildPath "Daten") -ChildPath "01_PERSOENLICHE_DATEN.md"),

  [string]$ProfilPath = (Join-Path -Path (Join-Path -Path (Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "..") -ChildPath "Private") -ChildPath "Daten") -ChildPath "02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md"),

  [string]$BewerbungenRoot = (Join-Path -Path (Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "..") -ChildPath "Private") -ChildPath "Bewerbungen"),

  [switch]$Fortsetzen,

  [switch]$StammdatenpruefungUeberspringen
)

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/AtomicFile.psm1") -Force

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$script:PathComparison = if ([System.IO.Path]::DirectorySeparatorChar -eq '\') { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }

$orderPathsModule = Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "Common") -ChildPath "OrderPaths.psm1"
Import-Module -Name $orderPathsModule -Force -ErrorAction Stop
Import-Module -Name (Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "Common") -ChildPath "Platform.psm1") -Force -ErrorAction Stop
Import-Module -Name (Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "Common") -ChildPath "WorkflowCheckpoint.psm1") -Force -ErrorAction Stop

function Stop-WithValidationError {
  param([string]$Message)
  Write-Host "[FEHLER] $Message" -ForegroundColor Red
  exit 2
}

function Assert-NoPortableCaseCollision {
  param([string]$Parent, [string]$ExpectedName)

  if (-not (Test-Path -LiteralPath $Parent -PathType Container)) { return }
  $collisions = @(Get-ChildItem -LiteralPath $Parent -Force | Where-Object {
    [string]::Equals($_.Name, $ExpectedName, [System.StringComparison]::OrdinalIgnoreCase) -and $_.Name -cne $ExpectedName
  })
  if ($collisions.Count -gt 0) {
    Stop-WithValidationError -Message "Portabilitätskonflikt durch abweichende Groß-/Kleinschreibung: erwartet '$ExpectedName', gefunden '$($collisions[0].Name)'."
  }
}

function Get-JsonProperty {
  param([object]$Object, [string]$Name)
  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
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

function Test-ApprovedUniversalActiveSource {
  param([string]$HtmlPath, [string]$ActiveFolder)

  $manifestPath = Join-Path $ActiveFolder 'Manifest.json'
  if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return $false }
  try {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $records = @($manifest.files)
    if ([int]$manifest.schemaVersion -ne 1 -or [string]$manifest.auftragsart -cne 'universal_lebenslauf' -or
        $manifest.personalReview.confirmed -isnot [bool] -or -not [bool]$manifest.personalReview.confirmed -or $records.Count -ne 2) {
      return $false
    }
    $htmlRelative = [IO.Path]::GetRelativePath($ActiveFolder, $HtmlPath).Replace('\', '/')
    $pdfRelative = 'Versand/' + [IO.Path]::GetFileName([IO.Path]::ChangeExtension($HtmlPath, '.pdf'))
    $recordPaths = @($records | ForEach-Object { ([string]$_.path).Replace('\', '/') })
    if (@($recordPaths | Where-Object { $_ -ceq $htmlRelative }).Count -ne 1 -or
        @($recordPaths | Where-Object { $_ -ceq $pdfRelative }).Count -ne 1) { return $false }
    foreach ($record in $records) {
      $relative = [string]$record.path
      if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $relative -match '(^|/|\\)\.\.($|/|\\)') { return $false }
      $path = Resolve-SafePath -Candidate (Join-Path $ActiveFolder $relative) -Root $ActiveFolder -MustExist -PathType Leaf
      $file = Get-Item -LiteralPath $path
      if ($file.Length -ne [long]$record.bytes -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine [string]$record.sha256) { return $false }
    }
    $actualPaths = @(Get-ChildItem -LiteralPath $ActiveFolder -Recurse -File | Where-Object { $_.Name -cne 'Manifest.json' } | ForEach-Object { [IO.Path]::GetRelativePath($ActiveFolder, $_.FullName).Replace('\', '/') } | Sort-Object)
    return (($actualPaths -join "`n") -ceq (($recordPaths | Sort-Object) -join "`n"))
  } catch {
    return $false
  }
}

function Invoke-RequiredTool {
  param([string]$ScriptPath, [string[]]$Arguments)

  $powerShellExe = (Get-Process -Id $PID).Path
  $nativeArguments = @("-NoLogo", "-NoProfile", "-NonInteractive", "-File", $ScriptPath) + @($Arguments)
  $result = Invoke-NativeProcess -FilePath $powerShellExe -ArgumentList $nativeArguments -TimeoutSeconds 120 -MaxStdoutChars 262144 -MaxStderrChars 262144
  foreach ($line in @($result.StandardOutput -split '\r?\n' | Where-Object { $_.Length -gt 0 })) { Write-Host $line }
  foreach ($line in @($result.StandardError -split '\r?\n' | Where-Object { $_.Length -gt 0 })) { Write-Host $line }
  if ($result.TimedOut) {
    Stop-WithValidationError -Message "Vorprüfung überschritt das Zeitlimit und wurde vollständig beendet: $ScriptPath"
  }
  if ($result.StdoutTruncated -or $result.StderrTruncated) {
    Stop-WithValidationError -Message "Vorprüfung erzeugte zu viel Ausgabe und wurde sicher abgebrochen: $ScriptPath"
  }
  if ($result.ExitCode -ne 0) {
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
$documentValues = [System.Collections.Generic.List[string]]::new()
foreach ($documentArgument in @($Dokumente)) {
  foreach ($documentPart in @(([string]$documentArgument).Split(','))) {
    $normalizedDocument = $documentPart.Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($normalizedDocument) -or
        $normalizedDocument -notin @("lebenslauf", "anschreiben", "email_nachricht")) {
      Stop-WithValidationError -Message "-Dokumente erlaubt ausschließlich die kommaseparierten Werte lebenslauf, anschreiben und email_nachricht."
    }
    $documentValues.Add($normalizedDocument) | Out-Null
  }
}
$normalizedDocuments = @($documentValues | Sort-Object -Unique)

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

try {
  $bewerbungenRootLexical = [System.IO.Path]::GetFullPath($BewerbungenRoot)
  $privateRoot = Split-Path -Path $bewerbungenRootLexical -Parent
  if ([string]::IsNullOrWhiteSpace($privateRoot)) {
    throw "BewerbungenRoot besitzt keinen validierbaren Elternpfad."
  }
  if (Test-Path -LiteralPath $bewerbungenRootLexical) {
    if (-not (Test-Path -LiteralPath $bewerbungenRootLexical -PathType Container)) {
      throw "BewerbungenRoot existiert, ist aber kein Ordner: $bewerbungenRootLexical"
    }
    $segmentItem = Get-Item -LiteralPath $bewerbungenRootLexical -Force
    if (([int]$segmentItem.Attributes -band [int][System.IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "BewerbungenRoot darf kein symbolischer Link-Alias sein: $bewerbungenRootLexical"
    }
  }
} catch {
  Stop-WithValidationError -Message "Unsicherer BewerbungenRoot: $($_.Exception.Message)"
}

foreach ($sourcePath in @($StammdatenPath, $ProfilPath)) {
  if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    Stop-WithValidationError -Message "Stammdaten- und Profilpfad müssen vor der Anlage auf vorhandene Dateien zeigen: $sourcePath"
  }
}
try {
  $StammdatenPath = Get-CanonicalPath -Path $StammdatenPath
  $ProfilPath = Get-CanonicalPath -Path $ProfilPath
} catch {
  Stop-WithValidationError -Message "Stammdaten oder Profil konnten nicht sicher aufgelöst werden: $($_.Exception.Message)"
}
$stammdatenSourceHash = (Get-FileHash -LiteralPath $StammdatenPath -Algorithm SHA256).Hash
$profilSourceHash = (Get-FileHash -LiteralPath $ProfilPath -Algorithm SHA256).Hash
if ($stammdatenSourceHash -notmatch '^[A-Fa-f0-9]{64}$' -or $profilSourceHash -notmatch '^[A-Fa-f0-9]{64}$') {
  Stop-WithValidationError -Message "Stammdaten und Profil konnten nicht mit gültigem SHA-256 gebunden werden."
}

$applicantFileName = Get-MarkdownField -Path $StammdatenPath -Name "Dateiname-Name"
$projectRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath "..")).Path
$universalSourceResolved = ""
$universalSourceHash = ""
$universalSourceFileName = ""
$universalSourcePathMode = ""
$universalSourceRelativePath = ""
if ($cvKind -eq "universal_unveraendert") {
  if ([string]::IsNullOrWhiteSpace($UniversalLebenslaufPath)) {
    $preferredUniversalPath = Join-Path -Path $bewerbungenRootLexical -ChildPath "_Universal-Lebenslauf/Aktiv/Intern/Lebenslauf - $applicantFileName.html"
    $legacyUniversalPath = Join-Path -Path $projectRoot -ChildPath "Private/LebenslaufUniversal/Aktiv/Lebenslauf - $applicantFileName.html"
    if (Test-Path -LiteralPath $preferredUniversalPath -PathType Leaf) {
      $preferredActiveFolder = Split-Path -Path (Split-Path -Path $preferredUniversalPath -Parent) -Parent
      if (-not (Test-ApprovedUniversalActiveSource -HtmlPath $preferredUniversalPath -ActiveFolder $preferredActiveFolder)) {
        Stop-WithValidationError -Message 'Die lokale Universalquelle unter Private/Bewerbungen besitzt keinen gültigen persönlichen Freigabe- und Hashnachweis.'
      }
      $UniversalLebenslaufPath = $preferredUniversalPath
    } elseif (Test-Path -LiteralPath $legacyUniversalPath -PathType Leaf) {
      $UniversalLebenslaufPath = $legacyUniversalPath
      Write-Host "[WARNUNG] Legacy-Universalquelle wird weiterhin gelesen. Neue Freigaben gehören unter Private/Bewerbungen/_Universal-Lebenslauf/Aktiv." -ForegroundColor Yellow
    } else {
      Stop-WithValidationError -Message "Keine aktive Universalquelle gefunden. Zuerst 'bewerbung.ps1 universal-neu' und 'universal-finalisieren' ausführen oder -UniversalLebenslaufPath ausdrücklich angeben."
    }
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
  $universalSourceFileName = [System.IO.Path]::GetFileName($universalSourceResolved)
  if (Test-BewerbungsPathWithinRoot -Path $universalSourceResolved -Root $projectRoot) {
    $universalSourcePathMode = "relativ_zu_projekt_root"
    $universalSourceRelativePath = ConvertTo-BewerbungsRelativePath -Path $universalSourceResolved -Root $projectRoot
  } else {
    $universalSourcePathMode = "extern_nicht_gespeichert"
  }
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

$firmaSlug = ConvertTo-BewerbungsSlug -Value $Firma
$rolleSlug = ConvertTo-BewerbungsSlug -Value $Rolle
$firmaHtml = [System.Net.WebUtility]::HtmlEncode($Firma)
$rolleHtml = [System.Net.WebUtility]::HtmlEncode($Rolle)

try {
  $pathSet = New-BewerbungsauftragPathSet `
    -BewerbungenRoot $bewerbungenRootLexical `
    -FirmaSlug $firmaSlug `
    -RolleSlug $rolleSlug `
    -Datum $Datum
} catch {
  Stop-WithValidationError -Message $_.Exception.Message
}
$bewerbungenRootFull = $pathSet.BewerbungenRoot
$zielDir = $pathSet.ZielOrdner
$arbeitsDir = $pathSet.ArbeitsOrdner
$kandidatDir = $pathSet.KandidatOrdner
$zielDirRelativ = $pathSet.ZielOrdnerRelativ
$arbeitsDirRelativ = $pathSet.ArbeitsOrdnerRelativ
$kandidatDirRelativ = $pathSet.KandidatOrdnerRelativ
$firmaDir = Split-Path -Path $zielDir -Parent
$arbeitsParentDir = Split-Path -Path $arbeitsDir -Parent

Assert-NoPortableCaseCollision -Parent $bewerbungenRootFull -ExpectedName $firmaSlug
Assert-NoPortableCaseCollision -Parent $firmaDir -ExpectedName (Split-Path -Path $zielDir -Leaf)
Assert-NoPortableCaseCollision -Parent $firmaDir -ExpectedName "_Arbeitsdateien"
Assert-NoPortableCaseCollision -Parent $arbeitsParentDir -ExpectedName (Split-Path -Path $arbeitsDir -Leaf)

foreach ($path in @($zielDir, $arbeitsDir)) {
  if ((Test-Path -LiteralPath $path) -and -not (Test-Path -LiteralPath $path -PathType Container)) {
    Stop-WithValidationError -Message "Bewerbungspfad existiert, ist aber kein Ordner: $path"
  }
}
if (Test-Path -LiteralPath $bewerbungenRootFull -PathType Container) {
  try {
    $resolvedPrivateRoot = Split-Path -Path $bewerbungenRootFull -Parent
    $bewerbungenRootFull = Resolve-SafePath -Candidate $bewerbungenRootFull -Root $resolvedPrivateRoot -MustExist -ForWrite -PathType Container
    if (Test-Path -LiteralPath $zielDir -PathType Container) {
      $zielDir = Resolve-SafePath -Candidate $zielDir -Root $bewerbungenRootFull -MustExist -ForWrite -PathType Container
    }
    if (Test-Path -LiteralPath $arbeitsDir -PathType Container) {
      $arbeitsDir = Resolve-SafePath -Candidate $arbeitsDir -Root $bewerbungenRootFull -MustExist -ForWrite -PathType Container
    }
  } catch {
    Stop-WithValidationError -Message "Vorhandene Bewerbungspfade enthalten einen unsicheren Link-Alias: $($_.Exception.Message)"
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
  try {
    $existingNotes = Resolve-SafePath -Candidate $existingNotes -Root $arbeitsDir -MustExist -ForWrite -PathType Leaf
  } catch {
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
  try {
    $existingAuftragPath = Resolve-SafePath -Candidate $existingAuftragPath -Root $arbeitsDir -MustExist -ForWrite -PathType Leaf
  } catch {
    Stop-WithValidationError -Message "Der vorhandene Arbeitsordner enthält keinen prüfbaren Bewerbungsauftrag. Fortsetzen wurde verweigert."
  }
  $existingAuftrag = Get-Content -LiteralPath $existingAuftragPath -Raw -Encoding UTF8 | ConvertFrom-Json
  try {
    $existingSchema = Get-BewerbungsauftragSchemaVersion -Auftrag $existingAuftrag
    if ($existingSchema -eq 5) {
      [void](Resolve-BewerbungsauftragPathSet `
          -Auftrag $existingAuftrag `
          -BewerbungenRoot $bewerbungenRootFull `
          -Arbeitsordner $arbeitsDir)
    }
  } catch {
    Stop-WithValidationError -Message $_.Exception.Message
  }
  foreach ($identityField in @(
      [pscustomobject]@{ Name = "firma"; Expected = $Firma },
      [pscustomobject]@{ Name = "rolle"; Expected = $Rolle },
      [pscustomobject]@{ Name = "datum"; Expected = $Datum }
    )) {
    $storedIdentity = [string](Get-JsonProperty -Object $existingAuftrag -Name $identityField.Name)
    if (-not [string]::IsNullOrWhiteSpace($storedIdentity) -and $storedIdentity -cne [string]$identityField.Expected) {
      Stop-WithValidationError -Message "Bewerbungsauftrag und gewünschte $($identityField.Name) stimmen beim Fortsetzen nicht exakt überein."
    }
  }
  if ($existingSchema -ge 4) {
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
    $expectedUniversalCandidateName = "Lebenslauf - $applicantFileName.html"
    $existingUniversalHash = [string](Get-JsonProperty -Object $existingUniversal -Name "sourceHtmlSha256BeiAnlage")
    $existingUniversalCandidate = [string](Get-JsonProperty -Object $existingUniversal -Name "kandidatDatei")
    $universalBindingIsValid = $true
    if ($existingSchema -le 4) {
      $existingUniversalPath = [string](Get-JsonProperty -Object $existingUniversal -Name "sourceHtmlPath")
      $universalBindingIsValid = -not [string]::IsNullOrWhiteSpace($existingUniversalPath) -and
        [string]::Equals(
          [System.IO.Path]::GetFullPath($existingUniversalPath),
          [System.IO.Path]::GetFullPath($universalSourceResolved),
          $script:PathComparison
        )
    } else {
      $existingUniversalFileName = [string](Get-JsonProperty -Object $existingUniversal -Name "sourceHtmlDateiname")
      $existingUniversalPathMode = [string](Get-JsonProperty -Object $existingUniversal -Name "sourceHtmlPfadModus")
      $existingUniversalPath = [string](Get-JsonProperty -Object $existingUniversal -Name "sourceHtmlPath")
      $universalBindingIsValid = $existingUniversalFileName -ceq $universalSourceFileName
      if ($existingUniversalPathMode -ceq "relativ_zu_projekt_root") {
        if ($universalSourcePathMode -cne "relativ_zu_projekt_root" -or
            $existingUniversalPath -cne $universalSourceRelativePath) {
          $universalBindingIsValid = $false
        }
        try {
          $storedUniversalSource = Resolve-BewerbungsRelativePath -Root $projectRoot -RelativePath $existingUniversalPath
          if ([System.IO.Path]::GetFileName($storedUniversalSource) -cne $existingUniversalFileName -or
              ((Test-Path -LiteralPath $storedUniversalSource) -and
                -not (Test-Path -LiteralPath $storedUniversalSource -PathType Leaf))) {
            $universalBindingIsValid = $false
          }
        } catch {
          $universalBindingIsValid = $false
        }
      } elseif ($existingUniversalPathMode -ceq "extern_nicht_gespeichert") {
        if ($universalSourcePathMode -cne "extern_nicht_gespeichert" -or
            -not [string]::IsNullOrWhiteSpace($existingUniversalPath)) {
          $universalBindingIsValid = $false
        }
      } else {
        $universalBindingIsValid = $false
      }
    }
    if (-not $universalBindingIsValid -or
        $existingUniversalHash -ine $universalSourceHash -or
        $existingUniversalCandidate -cne $expectedUniversalCandidateName -or
        [string](Get-JsonProperty -Object $existingAuftrag -Name "bewerberDateiname") -cne $applicantFileName) {
      Stop-WithValidationError -Message "Beim Fortsetzen wurde eine andere Universal-Lebenslauf-Quelle übergeben."
    }
  }
}

$bewerbungenRootCreated = -not (Test-Path -LiteralPath $bewerbungenRootFull -PathType Container)
$firmaDirCreated = -not (Test-Path -LiteralPath $firmaDir -PathType Container)
$arbeitsParentCreated = -not (Test-Path -LiteralPath $arbeitsParentDir -PathType Container)
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

  $resolvedPrivateRoot = Split-Path -Path $bewerbungenRootFull -Parent
  $bewerbungenRootFull = Resolve-SafePath -Candidate $bewerbungenRootFull -Root $resolvedPrivateRoot -MustExist -ForWrite -PathType Container
  $zielDir = Resolve-SafePath -Candidate $zielDir -Root $bewerbungenRootFull -MustExist -ForWrite -PathType Container
  $arbeitsDir = Resolve-SafePath -Candidate $arbeitsDir -Root $bewerbungenRootFull -MustExist -ForWrite -PathType Container
  $kandidatDir = Resolve-SafePath -Candidate $kandidatDir -Root $arbeitsDir -MustExist -ForWrite -PathType Container

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
$evidenzindexEntwurfFile = Join-Path -Path $arbeitsDir -ChildPath "Evidenzindex--ENTWURF.json"
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
  if (-not [string]::IsNullOrWhiteSpace($expectedFilePath)) {
    $expectedRoot = if (Test-BewerbungsPathWithinRoot -Path $expectedFilePath -Root $kandidatDir) { $kandidatDir } else { $arbeitsDir }
    try {
      $null = Resolve-SafePath -Candidate $expectedFilePath -Root $expectedRoot -ForWrite -PathType Leaf
    } catch {
      throw "Erwarteter Dateipfad ist kein sicheres Schreibziel: $expectedFilePath ($($_.Exception.Message))"
    }
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
    $candidateUniversalHash = (Get-FileHash -LiteralPath $universalCandidateFile -Algorithm SHA256).Hash
    if ($candidateUniversalHash -ine $universalSourceHash) {
      throw "Der kopierte Universal-Lebenslauf stimmt nicht mit dem vorab gebundenen Quellhash überein."
    }
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
  $universalBinding = if ($cvKind -eq "universal_unveraendert") {
    $binding = [ordered]@{
      sourceHtmlPfadModus = $universalSourcePathMode
      sourceHtmlDateiname = $universalSourceFileName
      sourceHtmlSha256BeiAnlage = $universalSourceHash
      kandidatDatei = "Lebenslauf - $applicantFileName.html"
    }
    if ($universalSourcePathMode -eq "relativ_zu_projekt_root") {
      $binding["sourceHtmlPath"] = $universalSourceRelativePath
    }
    $binding
  } else {
    $null
  }
  $auftrag = [ordered]@{
    schemaVersion = 5
    pfadModus = "relativ_zu_bewerbungen_root"
    firma = $Firma
    firmaSlug = $firmaSlug
    rolle = $Rolle
    rolleSlug = $rolleSlug
    datum = $Datum
    bewerberDateiname = $applicantFileName
    zielOrdner = $zielDirRelativ
    arbeitsOrdner = $arbeitsDirRelativ
    kandidatOrdner = $kandidatDirRelativ
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
    universalLebenslauf = $universalBinding
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
  Write-AtomicJson -Path $auftragFile -Value $auftrag -Depth 8
}

if (-not (Test-Path -LiteralPath $anforderungsmatrixEntwurfFile)) {
Set-Content -LiteralPath $anforderungsmatrixEntwurfFile -Encoding UTF8 -Value @"
{
  "schemaVersion": 5,
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
      "stellenFundstellen": [],
      "belegRefIds": [],
      "behandlung": "vor Erstellung der Kandidatendateien klären"
    }
  ],
  "recruiterStrategie": {
    "kernbotschaft": "durch den Agenten aus Zielrolle, Stellenanforderungen und den stärksten belegten Profilargumenten abzuleiten",
    "profilSubstanz": "noch_zu_pruefen",
    "profilSubstanzBegruendung": "vor der Dokumenterstellung anhand der relevanten Profildaten zu prüfen",
    "prioritaetsAnforderungen": ["muss-1"],
    "profilHighlights": [],
    "transferbruecken": [],
    "auslassungen": []
  },
  "anschreibenStrategie": {
    "status": "$(if ($includeLetter) { 'ausstehend' } else { 'nicht_erforderlich' })",
    "argumente": [],
    "abweichungBegruendung": ""
  },
  "externeQuellen": [],
  "stellenanzeigeAbdeckung": {
    "sourceSha256": "aus Stellenbeschreibung.md übernehmen",
    "fundstellen": []
  }
}
"@
}

if (-not (Test-Path -LiteralPath $evidenzindexEntwurfFile)) {
  Set-Content -LiteralPath $evidenzindexEntwurfFile -Encoding UTF8 -Value @"
{
  "schemaVersion": 1,
  "profilSha256": "aus Private/Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md übernehmen",
  "belege": []
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
    html, body { margin: 0; padding: 0; font-family: Arial, "Liberation Sans", Helvetica, sans-serif; color: #101828; line-height: 1.4; }
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
    html, body { margin: 0; padding: 0; font-family: Arial, "Liberation Sans", Helvetica, sans-serif; color: #101828; line-height: 1.4; }
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
- Vor der Dokumenterstellung: Anforderungsmatrix.json und Evidenzindex.json aus den jeweiligen Entwürfen fachlich vervollständigen.

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

Der verbindliche PDF-Export erfolgt automatisiert mit Chrome oder Edge. Browser-Kopf- und Fußzeilen wie Dateiname, URL, Datum oder Seitenzahl dürfen dabei nicht erscheinen.

Vor dem finalen PDF-Export oder Druck:

1. `Tools/Finalisiere-Bewerbung.ps1` mit `-Browser auto` ausführen.
2. Jeden frisch erzeugten Seitenscreenshot tatsächlich prüfen.
3. Keine manuelle Browservorschau als bestandenen maschinellen Export ausgeben.

Ziel: Die sichtbare A4-Seite wird ohne Browser-Dateipfad, URL, Datum oder Browser-Seitenzahlen als PDF ausgegeben.
"@
}

$workflowCheckpoint = Write-WorkflowCheckpoint -Arbeitsordner $arbeitsDir -Schritt 'auftrag_angelegt'

Write-Output "Bewerbungsordner: $zielDir"
Write-Output "Arbeitsdateien: $arbeitsDir"
Write-Output "Kandidatendateien: $kandidatDir"
Write-Output "Dokumentmodus: $Dokumentmodus"
Write-Output "Dokumentumfang: $scopeSummary"
Write-Output "Workflow-Checkpoint: $($workflowCheckpoint.path)"
if ($cvKind -eq "universal_unveraendert") {
  Write-Output "Universeller Lebenslauf unverändert übernommen: $universalCandidateFile"
}
} catch {
  if ($kandidatCreated -and -not $arbeitsCreated -and (Test-Path -LiteralPath $kandidatDir -PathType Container) -and (Test-BewerbungsPathWithinRoot -Path $kandidatDir -Root $arbeitsDir)) {
    try {
      $safeCleanup = Resolve-SafePath -Candidate $kandidatDir -Root $arbeitsDir -MustExist -ForWrite -PathType Container
      Remove-Item -LiteralPath $safeCleanup -Recurse -Force -ErrorAction SilentlyContinue
    } catch {}
  }
  if ($arbeitsCreated -and (Test-Path -LiteralPath $arbeitsDir -PathType Container) -and (Test-BewerbungsPathWithinRoot -Path $arbeitsDir -Root $bewerbungenRootFull)) {
    try {
      $safeCleanup = Resolve-SafePath -Candidate $arbeitsDir -Root $bewerbungenRootFull -MustExist -ForWrite -PathType Container
      Remove-Item -LiteralPath $safeCleanup -Recurse -Force -ErrorAction SilentlyContinue
    } catch {}
  }
  if ($zielCreated -and (Test-Path -LiteralPath $zielDir -PathType Container) -and (Test-BewerbungsPathWithinRoot -Path $zielDir -Root $bewerbungenRootFull)) {
    try {
      $safeCleanup = Resolve-SafePath -Candidate $zielDir -Root $bewerbungenRootFull -MustExist -ForWrite -PathType Container
      Remove-Item -LiteralPath $safeCleanup -Recurse -Force -ErrorAction SilentlyContinue
    } catch {}
  }
  foreach ($emptyParent in @(
      [pscustomobject]@{ Path = $arbeitsParentDir; Created = $arbeitsParentCreated },
      [pscustomobject]@{ Path = $firmaDir; Created = $firmaDirCreated },
      [pscustomobject]@{ Path = $bewerbungenRootFull; Created = $bewerbungenRootCreated; IsRoot = $true }
    )) {
    if (-not $emptyParent.Created -or -not (Test-Path -LiteralPath $emptyParent.Path -PathType Container)) { continue }
    $allowRoot = $null -ne $emptyParent.PSObject.Properties['IsRoot'] -and [bool]$emptyParent.IsRoot
    $safeParent = if ($allowRoot) {
      [string]::Equals([System.IO.Path]::GetFullPath($emptyParent.Path), [System.IO.Path]::GetFullPath($bewerbungenRootFull), $script:PathComparison)
    } else {
      Test-BewerbungsPathWithinRoot -Path $emptyParent.Path -Root $bewerbungenRootFull
    }
    if ($safeParent -and @(Get-ChildItem -LiteralPath $emptyParent.Path -Force -ErrorAction SilentlyContinue).Count -eq 0) {
      try {
        $cleanupRoot = if ($allowRoot) { Split-Path -Path $bewerbungenRootFull -Parent } else { $bewerbungenRootFull }
        $safeEmptyParent = Resolve-SafePath -Candidate $emptyParent.Path -Root $cleanupRoot -MustExist -ForWrite -PathType Container
        Remove-Item -LiteralPath $safeEmptyParent -Force -ErrorAction SilentlyContinue
      } catch {}
    }
  }
  Write-Host "[FEHLER] Bewerbungsstruktur konnte nicht vollständig erstellt werden: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}
