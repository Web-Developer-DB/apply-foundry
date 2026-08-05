[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$AuftragPath,

  [string]$StammdatenPath,

  [string]$ProfilPath,

  [switch]$FuerDokumenterstellung
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$errors = New-Object System.Collections.Generic.List[string]

function Add-ValidationError {
  param([string]$Message)
  $errors.Add($Message) | Out-Null
  Write-Host "[FEHLER] $Message" -ForegroundColor Red
}

function Get-JsonProperty {
  param([object]$Object, [string]$Name)
  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

function Test-HasJsonProperty {
  param([object]$Object, [string]$Name)
  return ($null -ne $Object) -and ($null -ne $Object.PSObject.Properties[$Name])
}

function Test-IsBoolean {
  param([object]$Value)
  return $Value -is [bool]
}

function Test-IsPositiveInteger {
  param([object]$Value)
  if ($null -eq $Value -or $Value -is [bool]) { return $false }
  $typeCode = [System.Type]::GetTypeCode($Value.GetType())
  if ($typeCode -notin @(
      [System.TypeCode]::Byte,
      [System.TypeCode]::SByte,
      [System.TypeCode]::Int16,
      [System.TypeCode]::UInt16,
      [System.TypeCode]::Int32,
      [System.TypeCode]::UInt32,
      [System.TypeCode]::Int64,
      [System.TypeCode]::UInt64
    )) {
    return $false
  }
  try {
    return ([uint64]$Value) -ge 1
  } catch {
    return $false
  }
}

function Test-IsZeroOrOneInteger {
  param([object]$Value)
  if ($null -eq $Value -or $Value -is [bool]) { return $false }
  $typeCode = [System.Type]::GetTypeCode($Value.GetType())
  if ($typeCode -notin @(
      [System.TypeCode]::Byte,
      [System.TypeCode]::SByte,
      [System.TypeCode]::Int16,
      [System.TypeCode]::UInt16,
      [System.TypeCode]::Int32,
      [System.TypeCode]::UInt32,
      [System.TypeCode]::Int64,
      [System.TypeCode]::UInt64
    )) {
    return $false
  }
  try {
    $number = [int64]$Value
    return $number -ge 0 -and $number -le 1
  } catch {
    return $false
  }
}

function Test-IsIsoTimestamp {
  param([object]$Value)
  if ($Value -is [datetime] -or $Value -is [datetimeoffset]) { return $true }
  if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value)) { return $false }
  $parsed = [datetimeoffset]::MinValue
  return [datetimeoffset]::TryParse(
    $Value,
    [System.Globalization.CultureInfo]::InvariantCulture,
    [System.Globalization.DateTimeStyles]::RoundtripKind,
    [ref]$parsed
  )
}

function Test-IsSha256 {
  param([object]$Value)
  return ($Value -is [string]) -and ($Value -match '^[A-Fa-f0-9]{64}$')
}

function Test-IsTechnicalId {
  param([object]$Value)
  return ($Value -is [string]) -and ($Value -match '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')
}

function Get-PathComparison {
  if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
    return [System.StringComparison]::OrdinalIgnoreCase
  }
  return [System.StringComparison]::Ordinal
}

function Test-PathNameEquals {
  param([string]$Left, [string]$Right)
  return [string]::Equals($Left, $Right, (Get-PathComparison))
}

function Get-ProjectRootFromOrderPath {
  param([string]$Path)

  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $directory = [System.IO.DirectoryInfo]::new((Split-Path -Path $fullPath -Parent))
  while ($null -ne $directory) {
    if ((Test-PathNameEquals -Left $directory.Name -Right 'Bewerbungen') -and
        $null -ne $directory.Parent -and
        (Test-PathNameEquals -Left $directory.Parent.Name -Right 'Private') -and
        $null -ne $directory.Parent.Parent) {
      return $directory.Parent.Parent.FullName
    }
    $directory = $directory.Parent
  }
  return $null
}

function Get-NormalizedPropertyName {
  param([string]$Name)
  return ([regex]::Replace($Name.ToLowerInvariant(), '[^a-z0-9äöüß]', ''))
}

function Find-ForbiddenRawChatFields {
  param(
    [object]$Value,
    [string]$Path = '$'
  )

  if ($null -eq $Value -or $Value -is [string] -or $Value.GetType().IsValueType) {
    return
  }

  if ($Value -is [System.Collections.IDictionary]) {
    foreach ($key in $Value.Keys) {
      $name = [string]$key
      Test-ForbiddenRawChatField -Name $name -Path "$Path.$name"
      Find-ForbiddenRawChatFields -Value $Value[$key] -Path "$Path.$name"
    }
    return
  }

  if ($Value -is [System.Collections.IEnumerable]) {
    $index = 0
    foreach ($item in $Value) {
      Find-ForbiddenRawChatFields -Value $item -Path "$Path[$index]"
      $index++
    }
    return
  }

  foreach ($property in $Value.PSObject.Properties) {
    Test-ForbiddenRawChatField -Name $property.Name -Path "$Path.$($property.Name)"
    Find-ForbiddenRawChatFields -Value $property.Value -Path "$Path.$($property.Name)"
  }
}

function Test-ForbiddenRawChatField {
  param([string]$Name, [string]$Path)
  $normalized = Get-NormalizedPropertyName -Name $Name
  $forbidden = @(
    'rawchat', 'rohchat', 'chatverlauf', 'dialogverlauf', 'conversation',
    'messages', 'prompt', 'systemprompt', 'vollstaendigerprompt',
    'rawmessage', 'rohnachricht', 'usermessage', 'assistantmessage',
    'transcript', 'transkript', 'rawanswer', 'rohantwort'
  )
  if ($normalized -in $forbidden) {
    Add-ValidationError "Verbotenes Rohchatfeld im Bewerbungsauftrag: $Path"
  }
}

function Get-ProfileUpdateStatus {
  param([object]$Record)
  return [string](Get-JsonProperty -Object $Record -Name 'status')
}

function Get-ExpectedProfileFileForTargetType {
  param([string]$TargetType)

  switch ($TargetType) {
    'persoenliche_daten' { return 'Private/Daten/01_PERSOENLICHE_DATEN.md' }
    'bewerberprofil' { return 'Private/Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md' }
    default { return $null }
  }
}

function Test-IsSingleLineText {
  param([object]$Value)
  return ($Value -is [string]) -and
    -not [string]::IsNullOrWhiteSpace($Value) -and
    $Value -notmatch "[`r`n`0]"
}

if (-not (Test-Path -LiteralPath $AuftragPath -PathType Leaf)) {
  Write-Host "[FEHLER] Bewerbungsauftrag fehlt oder ist keine Datei: $AuftragPath" -ForegroundColor Red
  exit 1
}
$resolvedOrderPath = (Resolve-Path -LiteralPath $AuftragPath).Path

try {
  $auftrag = Get-Content -LiteralPath $resolvedOrderPath -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
  Write-Host "[FEHLER] Bewerbungsauftrag ist kein gültiges JSON: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}

$schemaRaw = Get-JsonProperty -Object $auftrag -Name 'schemaVersion'
$schemaVersion = 0
if (-not [int]::TryParse([string]$schemaRaw, [ref]$schemaVersion) -or $schemaVersion -lt 1) {
  Add-ValidationError 'Bewerbungsauftrag enthält keine gültige positive schemaVersion.'
} elseif ($schemaVersion -le 3) {
  Write-Host "[OK] Legacy-Bewerbungsauftrag mit Schema $schemaVersion akzeptiert; ein Dialogstatus ist für diesen Altauftrag nicht verpflichtend." -ForegroundColor Green
  exit 0
} elseif ($schemaVersion -ne 4) {
  Add-ValidationError "Nicht unterstützte Bewerbungsauftrag-Schemaversion: $schemaVersion"
}

Find-ForbiddenRawChatFields -Value $auftrag

$scope = Get-JsonProperty -Object $auftrag -Name 'dokumentumfang'
if ($null -eq $scope) {
  Add-ValidationError 'Schema 4 erfordert dokumentumfang.'
} else {
  $selection = [string](Get-JsonProperty -Object $scope -Name 'auswahl')
  $scopeCode = [string](Get-JsonProperty -Object $scope -Name 'kennung')
  $cvMode = [string](Get-JsonProperty -Object $scope -Name 'lebenslauf')
  $source = [string](Get-JsonProperty -Object $scope -Name 'quelle')
  if ($selection -notin @('A', 'B', 'C', 'D', 'E')) {
    Add-ValidationError 'dokumentumfang.auswahl muss A, B, C, D oder E sein.'
  }
  if ($cvMode -notin @('individuell', 'universal_unveraendert', 'nicht_enthalten')) {
    Add-ValidationError 'dokumentumfang.lebenslauf muss individuell, universal_unveraendert oder nicht_enthalten sein.'
  }
  if ($source -notin @('auswahl', 'direkter_auftrag', 'fortgesetzter_auftrag')) {
    Add-ValidationError 'dokumentumfang.quelle muss auswahl, direkter_auftrag oder fortgesetzter_auftrag sein.'
  }

  $letterSelected = Get-JsonProperty -Object $scope -Name 'anschreiben'
  $emailSelected = Get-JsonProperty -Object $scope -Name 'emailNachricht'
  $scopeConfirmed = Get-JsonProperty -Object $scope -Name 'bestaetigt'
  $emailOnlyConfirmed = Get-JsonProperty -Object $scope -Name 'emailAlleinBestaetigt'
  if (-not (Test-IsBoolean -Value $letterSelected)) {
    Add-ValidationError 'dokumentumfang.anschreiben muss ein JSON-Boolean sein.'
  }
  if (-not (Test-IsBoolean -Value $emailSelected)) {
    Add-ValidationError 'dokumentumfang.emailNachricht muss ein JSON-Boolean sein.'
  }
  if (-not (Test-IsBoolean -Value $scopeConfirmed) -or $scopeConfirmed -ne $true) {
    Add-ValidationError 'dokumentumfang.bestaetigt muss als JSON-Boolean true gesetzt sein.'
  }
  if (-not (Test-IsBoolean -Value $emailOnlyConfirmed)) {
    Add-ValidationError 'dokumentumfang.emailAlleinBestaetigt muss ein JSON-Boolean sein.'
  }
  if (($cvMode -eq 'nicht_enthalten') -and ($letterSelected -eq $false) -and ($emailSelected -eq $false)) {
    Add-ValidationError 'dokumentumfang darf nicht alle Dokumente ausschließen.'
  }
  if (($cvMode -eq 'nicht_enthalten') -and ($letterSelected -eq $false) -and ($emailSelected -eq $true) -and ($emailOnlyConfirmed -ne $true)) {
    Add-ValidationError 'Ein reiner E-Mail-Umfang ist nur mit dokumentumfang.emailAlleinBestaetigt = true zulässig.'
  }

  if (-not (Test-HasJsonProperty -Object $scope -Name 'bestaetigtAtUtc') -or
      -not (Test-IsIsoTimestamp -Value (Get-JsonProperty -Object $scope -Name 'bestaetigtAtUtc'))) {
    Add-ValidationError 'dokumentumfang.bestaetigtAtUtc muss ein gültiger ISO-8601-Zeitstempel sein.'
  }

  $fixedScopes = [ordered]@{
    A = [pscustomobject]@{ Kennung = 'komplette_bewerbung'; Lebenslauf = 'individuell'; Anschreiben = $true; Email = $true }
    B = [pscustomobject]@{ Kennung = 'anschreiben_mit_universalem_lebenslauf'; Lebenslauf = 'universal_unveraendert'; Anschreiben = $true; Email = $true }
    C = [pscustomobject]@{ Kennung = 'individueller_lebenslauf'; Lebenslauf = 'individuell'; Anschreiben = $false; Email = $false }
    D = [pscustomobject]@{ Kennung = 'nur_anschreiben'; Lebenslauf = 'nicht_enthalten'; Anschreiben = $true; Email = $false }
  }
  if ($selection -in @('A', 'B', 'C', 'D')) {
    $expected = $fixedScopes[$selection]
    if ($scopeCode -cne $expected.Kennung -or
        $cvMode -cne $expected.Lebenslauf -or
        $letterSelected -ne $expected.Anschreiben -or
        $emailSelected -ne $expected.Email) {
      Add-ValidationError "dokumentumfang entspricht nicht der verbindlichen Abbildung für Auswahl $selection."
    }
  } elseif ($selection -eq 'E' -and $scopeCode -cne 'eigene_zusammenstellung') {
    Add-ValidationError 'dokumentumfang.kennung muss für Auswahl E eigene_zusammenstellung sein.'
  }

  if ($selection -in @('A', 'B', 'C', 'D', 'E')) {
    $expectedDocumentMode = switch ($selection) {
      'A' { 'vollbewerbung' }
      'B' { 'anschreiben_mit_universalem_lebenslauf' }
      default { 'individuelle_auswahl' }
    }
    $documentMode = [string](Get-JsonProperty -Object $auftrag -Name 'dokumentmodus')
    if ($documentMode -cne $expectedDocumentMode) {
      Add-ValidationError "dokumentmodus muss für Auswahl $selection '$expectedDocumentMode' sein."
    }
  }
}

$dialog = Get-JsonProperty -Object $auftrag -Name 'dialog'
$questions = @()
$facts = @()
$dialogStatus = ''
if ($null -eq $dialog) {
  Add-ValidationError 'Schema 4 erfordert dialog.'
} else {
  $dialogSchemaVersion = Get-JsonProperty -Object $dialog -Name 'schemaVersion'
  if (-not (Test-IsPositiveInteger -Value $dialogSchemaVersion) -or [uint64]$dialogSchemaVersion -ne 1) {
    Add-ValidationError 'dialog.schemaVersion muss als Ganzzahl 1 gesetzt sein.'
  }
  $dialogStatus = [string](Get-JsonProperty -Object $dialog -Name 'status')
  $allowedDialogStatuses = @(
    'profilabgleich_ausstehend',
    'rueckfragen_offen',
    'speicherentscheidung_offen',
    'bereit_zur_dokumenterstellung',
    'dokumenterstellung',
    'abgeschlossen'
  )
  if ($dialogStatus -notin $allowedDialogStatuses) {
    Add-ValidationError "dialog.status ist ungültig: '$dialogStatus'."
  }
  if (-not (Test-HasJsonProperty -Object $dialog -Name 'rueckfragen')) {
    Add-ValidationError 'dialog.rueckfragen fehlt.'
  } else {
    $questions = @((Get-JsonProperty -Object $dialog -Name 'rueckfragen'))
  }
  if (-not (Test-HasJsonProperty -Object $dialog -Name 'angaben')) {
    Add-ValidationError 'dialog.angaben fehlt.'
  } else {
    $facts = @((Get-JsonProperty -Object $dialog -Name 'angaben'))
  }
  if (-not (Test-HasJsonProperty -Object $dialog -Name 'updatedAtUtc') -or
      -not (Test-IsIsoTimestamp -Value (Get-JsonProperty -Object $dialog -Name 'updatedAtUtc'))) {
    Add-ValidationError 'dialog.updatedAtUtc muss ein gültiger ISO-8601-Zeitstempel sein.'
  }
}

$allIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
$questionIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
$factIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
$roundCounts = @{}
$blockingOpenQuestions = New-Object System.Collections.Generic.List[string]
$unresolvedContradictions = New-Object System.Collections.Generic.List[string]
$pendingDecisions = New-Object System.Collections.Generic.List[string]
$projectRootForProfiles = $null
$currentProfileHashes = @{}
$verifyCurrentProfileHashes = $FuerDokumenterstellung -or
  -not [string]::IsNullOrWhiteSpace($StammdatenPath) -or
  -not [string]::IsNullOrWhiteSpace($ProfilPath)

foreach ($question in $questions) {
  if ($null -eq $question) {
    Add-ValidationError 'dialog.rueckfragen enthält einen leeren Eintrag.'
    continue
  }
  $id = [string](Get-JsonProperty -Object $question -Name 'id')
  if (-not (Test-IsTechnicalId -Value $id)) {
    Add-ValidationError "Rückfrage besitzt keine gültige technische ID: '$id'"
  } elseif (-not $allIds.Add($id)) {
    Add-ValidationError "Dialog-ID ist nicht eindeutig: $id"
  } else {
    $questionIds.Add($id) | Out-Null
  }

  foreach ($requiredField in @(
      'runde',
      'art',
      'frage',
      'status',
      'antwortZusammenfassung',
      'angabeIds',
      'blockiertDokumenterstellung',
      'widerspruch',
      'widerspruchGeklaert'
    )) {
    if (-not (Test-HasJsonProperty -Object $question -Name $requiredField)) {
      Add-ValidationError "Rückfrage '$id' benötigt das Pflichtfeld $requiredField."
    }
  }

  $round = Get-JsonProperty -Object $question -Name 'runde'
  if (-not (Test-IsPositiveInteger -Value $round)) {
    Add-ValidationError "Rückfrage '$id' benötigt runde als positive Ganzzahl."
  } else {
    $roundKey = [string]([uint64]$round)
    if (-not $roundCounts.ContainsKey($roundKey)) { $roundCounts[$roundKey] = 0 }
    $roundCounts[$roundKey]++
  }

  if ((Test-HasJsonProperty -Object $question -Name 'wiederholungen') -and
      -not (Test-IsZeroOrOneInteger -Value (Get-JsonProperty -Object $question -Name 'wiederholungen'))) {
    Add-ValidationError "Rückfrage '$id': wiederholungen muss als Ganzzahl 0 oder 1 gesetzt sein."
  }

  $questionType = [string](Get-JsonProperty -Object $question -Name 'art')
  if ($questionType -notin @('informationsluecke', 'praezisierung', 'speicherentscheidung', 'widerspruch', 'email_only_gate')) {
    Add-ValidationError "Rückfrage '$id' hat eine ungültige art: $questionType"
  }

  $status = [string](Get-JsonProperty -Object $question -Name 'status')
  if ($status -notin @('offen', 'beantwortet', 'entfallen')) {
    Add-ValidationError "Rückfrage '$id' hat einen ungültigen Status: $status"
  }
  $questionText = [string](Get-JsonProperty -Object $question -Name 'frage')
  if ([string]::IsNullOrWhiteSpace($questionText)) {
    Add-ValidationError "Rückfrage '$id' enthält keinen knappen Fragetext."
  }

  $answerSummary = [string](Get-JsonProperty -Object $question -Name 'antwortZusammenfassung')
  [array]$linkedFactIds = @()
  if (Test-HasJsonProperty -Object $question -Name 'angabeIds') {
    $linkedFactIds = @((Get-JsonProperty -Object $question -Name 'angabeIds'))
    foreach ($linkedId in $linkedFactIds) {
      if (-not (Test-IsTechnicalId -Value $linkedId)) {
        Add-ValidationError "Rückfrage '$id' enthält eine ungültige angabeIds-Referenz: '$linkedId'"
      }
    }
  }
  if ($status -eq 'offen' -and -not [string]::IsNullOrWhiteSpace($answerSummary)) {
    Add-ValidationError "Offene Rückfrage '$id' darf noch keine antwortZusammenfassung enthalten."
  }
  if ($status -eq 'beantwortet' -and [string]::IsNullOrWhiteSpace($answerSummary)) {
    Add-ValidationError "Beantwortete Rückfrage '$id' benötigt eine knappe antwortZusammenfassung."
  }

  $blocksCreation = Get-JsonProperty -Object $question -Name 'blockiertDokumenterstellung'
  if (Test-HasJsonProperty -Object $question -Name 'blockiertDokumenterstellung') {
    if (-not (Test-IsBoolean -Value $blocksCreation)) {
      Add-ValidationError "Rückfrage '$id': blockiertDokumenterstellung muss ein JSON-Boolean sein."
    } elseif ($status -eq 'offen' -and $blocksCreation) {
      $blockingOpenQuestions.Add($id) | Out-Null
    } elseif ($status -in @('beantwortet', 'entfallen') -and $blocksCreation) {
      Add-ValidationError "Rückfrage '$id' darf mit Status $status die Dokumenterstellung nicht mehr blockieren."
    }
  }

  if ($questionType -eq 'speicherentscheidung' -and $status -eq 'offen' -and $blocksCreation -ne $true) {
    Add-ValidationError "Offene Speicherfrage '$id' muss die Dokumenterstellung blockieren."
  }

  $contradiction = Get-JsonProperty -Object $question -Name 'widerspruch'
  $contradictionResolved = Get-JsonProperty -Object $question -Name 'widerspruchGeklaert'
  if ((Test-HasJsonProperty -Object $question -Name 'widerspruch') -and -not (Test-IsBoolean -Value $contradiction)) {
    Add-ValidationError "Rückfrage '$id': widerspruch muss ein JSON-Boolean sein."
  }
  if ((Test-HasJsonProperty -Object $question -Name 'widerspruchGeklaert') -and -not (Test-IsBoolean -Value $contradictionResolved)) {
    Add-ValidationError "Rückfrage '$id': widerspruchGeklaert muss ein JSON-Boolean sein."
  }
  $isContradiction = ($questionType -eq 'widerspruch') -or ($contradiction -eq $true)
  if ($isContradiction -and $contradictionResolved -ne $true -and $status -ne 'entfallen') {
    $unresolvedContradictions.Add($id) | Out-Null
  }
  if ($isContradiction -and $status -in @('beantwortet', 'entfallen') -and $contradictionResolved -ne $true) {
    Add-ValidationError "Rückfrage '$id' darf als $status keinen ungeklärten Widerspruch behalten."
  }
}

foreach ($roundKey in $roundCounts.Keys) {
  if ($roundCounts[$roundKey] -gt 3) {
    Add-ValidationError "Dialogrunde $roundKey enthält $($roundCounts[$roundKey]) Rückfragen; erlaubt sind höchstens 3."
  }
}

foreach ($fact in $facts) {
  if ($null -eq $fact) {
    Add-ValidationError 'dialog.angaben enthält einen leeren Eintrag.'
    continue
  }
  $id = [string](Get-JsonProperty -Object $fact -Name 'id')
  if (-not (Test-IsTechnicalId -Value $id)) {
    Add-ValidationError "Dialogangabe besitzt keine gültige technische ID: '$id'"
  } elseif (-not $allIds.Add($id)) {
    Add-ValidationError "Dialog-ID ist nicht eindeutig: $id"
  } else {
    $factIds.Add($id) | Out-Null
  }

  foreach ($requiredTextField in @('thema', 'normalisierteAngabe', 'kenntnisniveau')) {
    if ([string]::IsNullOrWhiteSpace([string](Get-JsonProperty -Object $fact -Name $requiredTextField))) {
      Add-ValidationError "Dialogangabe '$id' benötigt einen nichtleeren Wert in $requiredTextField."
    }
  }
  $requirementStatus = [string](Get-JsonProperty -Object $fact -Name 'anforderungsstatus')
  if ($requirementStatus -notin @(
      'eindeutig_belegt',
      'teilweise_belegt',
      'indirekt_oder_uebertragbar_belegt',
      'nicht_belegt',
      'widerspruechlich',
      'moeglicherweise_vorhanden_aber_nicht_dokumentiert',
      'nicht_relevant'
    )) {
    Add-ValidationError "Dialogangabe '$id' hat einen ungültigen anforderungsstatus: $requirementStatus"
  }
  $experienceType = [string](Get-JsonProperty -Object $fact -Name 'erfahrungsart')
  if ($experienceType -notmatch '^[a-z0-9][a-z0-9._-]{0,79}$') {
    Add-ValidationError "Dialogangabe '$id' benötigt erfahrungsart als nichtleeren technischen Wert."
  }
  $truthStatus = [string](Get-JsonProperty -Object $fact -Name 'wahrheitsstatus')
  if ($truthStatus -notin @('bestaetigt', 'unklar', 'widerspruechlich', 'verworfen')) {
    Add-ValidationError "Dialogangabe '$id' hat einen ungültigen wahrheitsstatus: $truthStatus"
  }

  $decision = [string](Get-JsonProperty -Object $fact -Name 'speicherentscheidung')
  if ($decision -notin @('ausstehend', 'nur_auftrag', 'dauerhaft')) {
    Add-ValidationError "Dialogangabe '$id' hat eine ungültige speicherentscheidung: $decision"
  }

  $profileUpdate = Get-JsonProperty -Object $fact -Name 'profilaktualisierung'
  if ($null -eq $profileUpdate) {
    Add-ValidationError "Dialogangabe '$id' enthält keine profilaktualisierung."
    continue
  }
  $profileStatus = Get-ProfileUpdateStatus -Record $profileUpdate
  if ($profileStatus -notin @('nicht_geaendert', 'ausstehend', 'aktualisiert', 'bereits_vorhanden')) {
    Add-ValidationError "Dialogangabe '$id' hat einen ungültigen profilaktualisierung.status: $profileStatus"
  }

  if ($decision -eq 'ausstehend') {
    $pendingDecisions.Add($id) | Out-Null
    if ($truthStatus -cne 'bestaetigt') {
      Add-ValidationError "Dialogangabe '$id' darf erst nach bestätigter Wahrheitsebene eine Speicherentscheidung öffnen."
    }
    $pendingContradiction = Get-JsonProperty -Object $fact -Name 'widerspruch'
    $pendingContradictionResolved = Get-JsonProperty -Object $fact -Name 'widerspruchGeklaert'
    if ((($pendingContradiction -eq $true) -or $requirementStatus -ceq 'widerspruechlich') -and
        $pendingContradictionResolved -ne $true) {
      Add-ValidationError "Dialogangabe '$id' darf vor der Widerspruchsklärung keine Speicherentscheidung öffnen."
    }
    if ($profileStatus -ne 'ausstehend') {
      Add-ValidationError "Dialogangabe '$id' mit ausstehender Speicherentscheidung benötigt profilaktualisierung.status ausstehend."
    }
    $profileFile = ([string](Get-JsonProperty -Object $profileUpdate -Name 'datei')).Replace('\', '/')
    $targetType = [string](Get-JsonProperty -Object $profileUpdate -Name 'fachlicherZieltyp')
    $expectedProfileFile = Get-ExpectedProfileFileForTargetType -TargetType $targetType
    if ($null -eq $expectedProfileFile) {
      Add-ValidationError "Dialogangabe '$id' benötigt profilaktualisierung.fachlicherZieltyp mit persoenliche_daten oder bewerberprofil."
    } elseif ($profileFile -cne $expectedProfileFile) {
      Add-ValidationError "Dialogangabe '$id': Profilziel $profileFile passt nicht zum fachlichen Zieltyp $targetType."
    }
    foreach ($field in @('abschnitt', 'vorgeschlageneFormulierung')) {
      if (-not (Test-IsSingleLineText -Value (Get-JsonProperty -Object $profileUpdate -Name $field))) {
        Add-ValidationError "Dialogangabe '$id' benötigt profilaktualisierung.$field als nichtleeren einzeiligen Wert."
      }
    }
    if (-not (Test-IsSha256 -Value (Get-JsonProperty -Object $profileUpdate -Name 'vorherSha256'))) {
      Add-ValidationError "Dialogangabe '$id' benötigt einen gültigen profilaktualisierung.vorherSha256."
    }
    foreach ($field in @('bestaetigteFormulierung', 'zugestimmtAtUtc', 'nachherSha256', 'aktualisiertAtUtc')) {
      if (-not [string]::IsNullOrWhiteSpace([string](Get-JsonProperty -Object $profileUpdate -Name $field))) {
        Add-ValidationError "Dialogangabe '$id' mit ausstehender Speicherentscheidung darf kein abgeschlossenes Profilfeld befüllen: $field"
      }
    }
  } elseif ($decision -eq 'nur_auftrag') {
    if ($profileStatus -ne 'nicht_geaendert') {
      Add-ValidationError "Dialogangabe '$id' mit nur_auftrag muss profilaktualisierung.status nicht_geaendert verwenden."
    }
    foreach ($field in @('datei', 'abschnitt', 'vorgeschlageneFormulierung', 'fachlicherZieltyp', 'bestaetigteFormulierung', 'zugestimmtAtUtc', 'vorherSha256', 'nachherSha256', 'aktualisiertAtUtc')) {
      if (-not [string]::IsNullOrWhiteSpace([string](Get-JsonProperty -Object $profileUpdate -Name $field))) {
        Add-ValidationError "Dialogangabe '$id' mit nur_auftrag darf kein dauerhaftes Profilfeld befüllen: $field"
      }
    }
  } elseif ($decision -eq 'dauerhaft') {
    if ($truthStatus -cne 'bestaetigt') {
      Add-ValidationError "Dialogangabe '$id' darf nur mit wahrheitsstatus bestaetigt dauerhaft gespeichert werden."
    }
    if ($profileStatus -notin @('aktualisiert', 'bereits_vorhanden')) {
      Add-ValidationError "Dialogangabe '$id' mit dauerhaft benötigt profilaktualisierung.status aktualisiert oder bereits_vorhanden."
    }
    $profileFile = ([string](Get-JsonProperty -Object $profileUpdate -Name 'datei')).Replace('\', '/')
    $targetType = [string](Get-JsonProperty -Object $profileUpdate -Name 'fachlicherZieltyp')
    $expectedProfileFile = Get-ExpectedProfileFileForTargetType -TargetType $targetType
    if ($null -eq $expectedProfileFile) {
      Add-ValidationError "Dialogangabe '$id' benötigt profilaktualisierung.fachlicherZieltyp mit persoenliche_daten oder bewerberprofil."
    } elseif ($profileFile -cne $expectedProfileFile) {
      Add-ValidationError "Dialogangabe '$id': Profilziel $profileFile passt nicht zum fachlichen Zieltyp $targetType."
    }
    foreach ($field in @('abschnitt', 'vorgeschlageneFormulierung', 'bestaetigteFormulierung')) {
      if (-not (Test-IsSingleLineText -Value (Get-JsonProperty -Object $profileUpdate -Name $field))) {
        Add-ValidationError "Dialogangabe '$id' benötigt profilaktualisierung.$field als nichtleeren einzeiligen Wert."
      }
    }
    $proposedFormulation = [string](Get-JsonProperty -Object $profileUpdate -Name 'vorgeschlageneFormulierung')
    $confirmedFormulation = [string](Get-JsonProperty -Object $profileUpdate -Name 'bestaetigteFormulierung')
    if ($proposedFormulation -cne $confirmedFormulation) {
      Add-ValidationError "Dialogangabe '$id': bestätigte Formulierung weicht von der zuvor vorgeschlagenen Formulierung ab."
    }
    foreach ($field in @('zugestimmtAtUtc', 'aktualisiertAtUtc')) {
      if (-not (Test-IsIsoTimestamp -Value (Get-JsonProperty -Object $profileUpdate -Name $field))) {
        Add-ValidationError "Dialogangabe '$id' benötigt einen gültigen ISO-8601-Zeitstempel in profilaktualisierung.$field."
      }
    }
    $beforeHash = Get-JsonProperty -Object $profileUpdate -Name 'vorherSha256'
    $afterHash = Get-JsonProperty -Object $profileUpdate -Name 'nachherSha256'
    if (-not (Test-IsSha256 -Value $beforeHash)) {
      Add-ValidationError "Dialogangabe '$id' benötigt einen gültigen profilaktualisierung.vorherSha256."
    }
    if (-not (Test-IsSha256 -Value $afterHash)) {
      Add-ValidationError "Dialogangabe '$id' benötigt einen gültigen profilaktualisierung.nachherSha256."
    }
    if ($profileStatus -eq 'bereits_vorhanden' -and
        (Test-IsSha256 -Value $beforeHash) -and
        (Test-IsSha256 -Value $afterHash) -and
        $beforeHash -ine $afterHash) {
      Add-ValidationError "Dialogangabe '$id' mit bereits_vorhanden muss identische Vorher-/Nachherhashes besitzen."
    }
    if ($profileStatus -eq 'aktualisiert' -and
        (Test-IsSha256 -Value $beforeHash) -and
        (Test-IsSha256 -Value $afterHash) -and
        $beforeHash -ieq $afterHash) {
      Add-ValidationError "Dialogangabe '$id' mit aktualisiert muss unterschiedliche Vorher-/Nachherhashes besitzen."
    }

    if ($verifyCurrentProfileHashes -and $profileFile -in @(
        'Private/Daten/01_PERSOENLICHE_DATEN.md',
        'Private/Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md'
      )) {
      if ($null -eq $projectRootForProfiles) {
        $projectRootForProfiles = Get-ProjectRootFromOrderPath -Path $resolvedOrderPath
      }
      if ([string]::IsNullOrWhiteSpace([string]$projectRootForProfiles)) {
        Add-ValidationError "Dialogangabe '$id': Die Projektwurzel kann nur aus einem Auftrag unter Private/Bewerbungen sicher abgeleitet werden."
      } else {
        $canonicalProfilePath = [System.IO.Path]::GetFullPath((Join-Path -Path $projectRootForProfiles -ChildPath $profileFile))
        $configuredProfilePath = if ($profileFile -ceq 'Private/Daten/01_PERSOENLICHE_DATEN.md') {
          $StammdatenPath
        } else {
          $ProfilPath
        }
        $actualProfilePath = if ([string]::IsNullOrWhiteSpace($configuredProfilePath)) {
          $canonicalProfilePath
        } elseif ([System.IO.Path]::IsPathRooted($configuredProfilePath)) {
          [System.IO.Path]::GetFullPath($configuredProfilePath)
        } else {
          [System.IO.Path]::GetFullPath((Join-Path -Path $projectRootForProfiles -ChildPath $configuredProfilePath))
        }

        if (-not (Test-PathNameEquals -Left $actualProfilePath -Right $canonicalProfilePath)) {
          Add-ValidationError "Dialogangabe '$id': Der übergebene Profilpfad stimmt nicht mit $profileFile überein."
        } elseif (-not (Test-Path -LiteralPath $actualProfilePath -PathType Leaf)) {
          Add-ValidationError "Dialogangabe '$id': Nachgewiesene Profildatei fehlt: $profileFile"
        } else {
          $profileItem = Get-Item -LiteralPath $actualProfilePath
          if (($profileItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            Add-ValidationError "Dialogangabe '$id': Reparse-Points sind als nachgewiesene Profildatei nicht zulässig."
          } else {
            if (-not $currentProfileHashes.ContainsKey($canonicalProfilePath)) {
              try {
                $currentProfileHashes[$canonicalProfilePath] = (Get-FileHash -LiteralPath $actualProfilePath -Algorithm SHA256).Hash
              } catch {
                Add-ValidationError "Dialogangabe '$id': Aktueller Profilhash konnte nicht gelesen werden: $($_.Exception.Message)"
              }
            }
            if ($currentProfileHashes.ContainsKey($canonicalProfilePath) -and
                (Test-IsSha256 -Value $afterHash) -and
                $currentProfileHashes[$canonicalProfilePath] -ine $afterHash) {
              Add-ValidationError "Dialogangabe '$id': Aktueller Profilhash stimmt nicht mit profilaktualisierung.nachherSha256 überein."
            }
          }
        }
      }
    }
  }

  $factContradiction = Get-JsonProperty -Object $fact -Name 'widerspruch'
  $factContradictionResolved = Get-JsonProperty -Object $fact -Name 'widerspruchGeklaert'
  if ((Test-HasJsonProperty -Object $fact -Name 'widerspruch') -and -not (Test-IsBoolean -Value $factContradiction)) {
    Add-ValidationError "Dialogangabe '$id': widerspruch muss ein JSON-Boolean sein."
  }
  if ((Test-HasJsonProperty -Object $fact -Name 'widerspruchGeklaert') -and -not (Test-IsBoolean -Value $factContradictionResolved)) {
    Add-ValidationError "Dialogangabe '$id': widerspruchGeklaert muss ein JSON-Boolean sein."
  }
  if ((($factContradiction -eq $true) -or $truthStatus -eq 'widerspruechlich') -and
      ($factContradictionResolved -ne $true)) {
    $unresolvedContradictions.Add($id) | Out-Null
  }
}

foreach ($question in $questions) {
  if ($null -eq $question -or -not (Test-HasJsonProperty -Object $question -Name 'angabeIds')) { continue }
  $questionId = [string](Get-JsonProperty -Object $question -Name 'id')
  foreach ($linkedId in @((Get-JsonProperty -Object $question -Name 'angabeIds'))) {
    if ((Test-IsTechnicalId -Value $linkedId) -and -not $factIds.Contains([string]$linkedId)) {
      Add-ValidationError "Rückfrage '$questionId' verweist auf eine nicht vorhandene Dialogangabe: $linkedId"
    }
  }
}

$pendingQuestionCounts = @{}
foreach ($question in $questions) {
  if ($null -eq $question -or
      [string](Get-JsonProperty -Object $question -Name 'art') -cne 'speicherentscheidung' -or
      [string](Get-JsonProperty -Object $question -Name 'status') -cne 'offen') {
    continue
  }
  foreach ($linkedId in @((Get-JsonProperty -Object $question -Name 'angabeIds'))) {
    if (Test-IsTechnicalId -Value $linkedId) {
      $key = [string]$linkedId
      if (-not $pendingQuestionCounts.ContainsKey($key)) { $pendingQuestionCounts[$key] = 0 }
      $pendingQuestionCounts[$key]++
    }
  }
}
foreach ($pendingId in $pendingDecisions) {
  $linkedQuestionCount = if ($pendingQuestionCounts.ContainsKey($pendingId)) { [int]$pendingQuestionCounts[$pendingId] } else { 0 }
  if ($linkedQuestionCount -ne 1) {
    Add-ValidationError "Ausstehende Speicherentscheidung '$pendingId' benötigt genau eine offene verknüpfte Speicherfrage; gefunden: $linkedQuestionCount."
  }
}

if ($pendingDecisions.Count -gt 0 -and $dialogStatus -cne 'speicherentscheidung_offen') {
  Add-ValidationError "Ausstehende Speicherentscheidungen erfordern dialog.status speicherentscheidung_offen."
} elseif ($pendingDecisions.Count -eq 0 -and $dialogStatus -ceq 'speicherentscheidung_offen') {
  Add-ValidationError "dialog.status speicherentscheidung_offen erfordert mindestens eine ausstehende Speicherentscheidung."
}

if ($pendingDecisions.Count -eq 0 -and
    ($blockingOpenQuestions.Count -gt 0 -or $unresolvedContradictions.Count -gt 0) -and
    $dialogStatus -cne 'rueckfragen_offen') {
  Add-ValidationError 'Blockierende offene Rückfragen oder Widersprüche erfordern dialog.status rueckfragen_offen.'
}

if ($dialogStatus -in @('bereit_zur_dokumenterstellung', 'dokumenterstellung', 'abgeschlossen')) {
  if ($blockingOpenQuestions.Count -gt 0) {
    Add-ValidationError "dialog.status $dialogStatus ist mit blockierenden offenen Rückfragen nicht konsistent."
  }
  if ($unresolvedContradictions.Count -gt 0) {
    Add-ValidationError "dialog.status $dialogStatus ist mit ungeklärten Widersprüchen nicht konsistent."
  }
  if ($pendingDecisions.Count -gt 0) {
    Add-ValidationError "dialog.status $dialogStatus ist mit ausstehenden Speicherentscheidungen nicht konsistent."
  }
}

if ($FuerDokumenterstellung) {
  if ($dialogStatus -notin @('bereit_zur_dokumenterstellung', 'dokumenterstellung', 'abgeschlossen')) {
    Add-ValidationError "Dokumenterstellung ist mit dialog.status '$dialogStatus' nicht zulässig."
  }
  foreach ($id in $blockingOpenQuestions) {
    Add-ValidationError "Dokumenterstellung ist durch die offene Rückfrage '$id' blockiert."
  }
  foreach ($id in $unresolvedContradictions | Sort-Object -Unique) {
    Add-ValidationError "Dokumenterstellung ist durch den ungeklärten Widerspruch '$id' blockiert."
  }
  foreach ($id in $pendingDecisions) {
    Add-ValidationError "Dokumenterstellung ist durch die ausstehende Speicherentscheidung '$id' blockiert."
  }
}

Write-Host ''
Write-Host 'Zusammenfassung:'
Write-Host "Fehler: $($errors.Count)"
if ($errors.Count -gt 0) {
  Write-Host 'ERGEBNIS: FEHLER' -ForegroundColor Red
  exit 1
}

Write-Host '[OK] Dialogstatus und Dokumentumfang sind konsistent.' -ForegroundColor Green
exit 0
