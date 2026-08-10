#requires -Version 7.6
#requires -PSEdition Core

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$AuftragPath,

  [Parameter(Mandatory = $true)]
  [string]$AngabeId,

  [Parameter(Mandatory = $true)]
  [ValidateSet('nur_auftrag', 'dauerhaft')]
  [string]$Speicherentscheidung,

  [string]$ProfilPath,

  [string]$Abschnitt,

  [string]$Formulierung,

  [string]$ErwarteterDateiHash,

  [switch]$ZustimmungBestaetigt
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath 'Common/Platform.psm1') -Force

$script:ApplicationsRoot = $null
$script:OrderWorkRoot = $null
$script:DataRoot = $null
$script:ResolvedOrderPath = $null

function Stop-WithValidationError {
  param([string]$Message)
  Write-Host "[FEHLER] $Message" -ForegroundColor Red
  exit 1
}

function Stop-WithUnsafePathError {
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

function Set-JsonProperty {
  param([object]$Object, [string]$Name, [AllowNull()][object]$Value)
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
  } else {
    $property.Value = $Value
  }
}

function Test-HasJsonProperty {
  param([object]$Object, [string]$Name)
  return ($null -ne $Object) -and ($null -ne $Object.PSObject.Properties[$Name])
}

function Remove-JsonProperty {
  param([object]$Object, [string]$Name)
  if (Test-HasJsonProperty -Object $Object -Name $Name) {
    $Object.PSObject.Properties.Remove($Name)
  }
}

function Get-ExpectedProfileFileForTargetType {
  param([string]$TargetType)

  switch ($TargetType) {
    'persoenliche_daten' { return 'Private/Daten/01_PERSOENLICHE_DATEN.md' }
    'bewerberprofil' { return 'Private/Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md' }
    default { return $null }
  }
}

function Complete-StorageDecisionState {
  param(
    [object]$Dialog,
    [string]$FactId
  )

  $facts = @((Get-JsonProperty -Object $Dialog -Name 'angaben'))
  $questions = @((Get-JsonProperty -Object $Dialog -Name 'rueckfragen'))
  $linkedOpenQuestions = 0

  foreach ($question in $questions) {
    if ([string](Get-JsonProperty -Object $question -Name 'art') -cne 'speicherentscheidung' -or
        [string](Get-JsonProperty -Object $question -Name 'status') -cne 'offen') {
      continue
    }

    $linkedIds = @((Get-JsonProperty -Object $question -Name 'angabeIds'))
    if ($FactId -cnotin $linkedIds) {
      continue
    }
    $linkedOpenQuestions++

    $allLinkedDecisionsResolved = $true
    foreach ($linkedId in $linkedIds) {
      $linkedFacts = @($facts | Where-Object { [string](Get-JsonProperty -Object $_ -Name 'id') -ceq [string]$linkedId })
      if ($linkedFacts.Count -ne 1 -or
          [string](Get-JsonProperty -Object $linkedFacts[0] -Name 'speicherentscheidung') -ceq 'ausstehend') {
        $allLinkedDecisionsResolved = $false
        break
      }
    }

    if ($allLinkedDecisionsResolved) {
      Set-JsonProperty -Object $question -Name 'status' -Value 'beantwortet'
      Set-JsonProperty -Object $question -Name 'antwortZusammenfassung' -Value 'Speicherentscheidung abgeschlossen'
      Set-JsonProperty -Object $question -Name 'blockiertDokumenterstellung' -Value $false
      Set-JsonProperty -Object $question -Name 'widerspruch' -Value $false
      Set-JsonProperty -Object $question -Name 'widerspruchGeklaert' -Value $true
    }
  }

  if ($linkedOpenQuestions -ne 1) {
    throw "Dialogangabe '$FactId' muss mit genau einer offenen Speicherfrage verknüpft sein; gefunden: $linkedOpenQuestions."
  }

  $hasPendingDecision = @($facts | Where-Object {
      [string](Get-JsonProperty -Object $_ -Name 'speicherentscheidung') -ceq 'ausstehend'
    }).Count -gt 0
  $hasBlockingQuestion = @($questions | Where-Object {
      [string](Get-JsonProperty -Object $_ -Name 'status') -ceq 'offen' -and
      (Get-JsonProperty -Object $_ -Name 'blockiertDokumenterstellung') -eq $true
    }).Count -gt 0
  $hasUnresolvedContradiction = @($questions | Where-Object {
      [string](Get-JsonProperty -Object $_ -Name 'status') -cne 'entfallen' -and
      (([string](Get-JsonProperty -Object $_ -Name 'art') -ceq 'widerspruch') -or
        (Get-JsonProperty -Object $_ -Name 'widerspruch') -eq $true) -and
      (Get-JsonProperty -Object $_ -Name 'widerspruchGeklaert') -ne $true
    }).Count -gt 0
  if (-not $hasUnresolvedContradiction) {
    $hasUnresolvedContradiction = @($facts | Where-Object {
        (((Get-JsonProperty -Object $_ -Name 'widerspruch') -eq $true) -or
          [string](Get-JsonProperty -Object $_ -Name 'wahrheitsstatus') -ceq 'widerspruechlich') -and
        (Get-JsonProperty -Object $_ -Name 'widerspruchGeklaert') -ne $true
      }).Count -gt 0
  }

  $nextStatus = if ($hasPendingDecision) {
    'speicherentscheidung_offen'
  } elseif ($hasBlockingQuestion -or $hasUnresolvedContradiction) {
    'rueckfragen_offen'
  } else {
    'bereit_zur_dokumenterstellung'
  }
  Set-JsonProperty -Object $Dialog -Name 'status' -Value $nextStatus
}

function Read-Utf8FileState {
  param([string]$Path)

  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
  $offset = if ($hasBom) { 3 } else { 0 }
  $encoding = [System.Text.UTF8Encoding]::new($false, $true)
  try {
    $text = $encoding.GetString($bytes, $offset, $bytes.Length - $offset)
  } catch {
    throw "Datei ist kein gültiges UTF-8: $Path"
  }
  return [pscustomobject]@{
    Bytes = $bytes
    HasBom = $hasBom
    Text = $text
  }
}

function ConvertTo-Utf8Bytes {
  param([string]$Text, [bool]$WithBom)

  $body = [System.Text.UTF8Encoding]::new($false).GetBytes($Text)
  if (-not $WithBom) { return $body }
  $result = New-Object byte[] ($body.Length + 3)
  $result[0] = 0xEF
  $result[1] = 0xBB
  $result[2] = 0xBF
  [System.Buffer]::BlockCopy($body, 0, $result, 3, $body.Length)
  return $result
}

function Get-Sha256ForBytes {
  param([byte[]]$Bytes)

  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([System.BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '')
  } finally {
    $sha.Dispose()
  }
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

function Get-NormalizedSectionName {
  param([string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
  $singleLine = $Value.Trim()
  if ($singleLine -match "[`r`n`0]") { return '' }
  return ([regex]::Replace($singleLine, '^#{1,6}\s+', '')).Trim()
}

function Get-UpdatedProfileText {
  param(
    [string]$Text,
    [string]$SectionName,
    [string]$ExactFormulation
  )

  $newline = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
  $hadTrailingNewline = $Text.EndsWith("`n", [System.StringComparison]::Ordinal)
  [array]$rawLines = [regex]::Split($Text, '\r\n|\n')
  $lines = New-Object System.Collections.Generic.List[string]
  foreach ($line in $rawLines) { $lines.Add([string]$line) }
  if ($hadTrailingNewline -and $lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') {
    $lines.RemoveAt($lines.Count - 1)
  }

  $sectionMatches = New-Object System.Collections.Generic.List[object]
  for ($index = 0; $index -lt $lines.Count; $index++) {
    $match = [regex]::Match($lines[$index], '^(?<marks>#{1,6})\s+(?<title>.*?)\s*$')
    if ($match.Success -and $match.Groups['title'].Value -ceq $SectionName) {
      $sectionMatches.Add([pscustomobject]@{
        Index = $index
        Level = $match.Groups['marks'].Value.Length
      }) | Out-Null
    }
  }
  if ($sectionMatches.Count -eq 0) {
    throw "Zielabschnitt wurde nicht exakt gefunden: $SectionName"
  }
  if ($sectionMatches.Count -gt 1) {
    throw "Zielabschnitt ist nicht eindeutig: $SectionName"
  }

  $sectionIndex = [int]$sectionMatches[0].Index
  $sectionLevel = [int]$sectionMatches[0].Level
  $insertAt = $lines.Count
  for ($index = $sectionIndex + 1; $index -lt $lines.Count; $index++) {
    $match = [regex]::Match($lines[$index], '^(?<marks>#{1,6})\s+')
    if ($match.Success -and $match.Groups['marks'].Value.Length -le $sectionLevel) {
      $insertAt = $index
      break
    }
  }

  for ($index = $sectionIndex + 1; $index -lt $insertAt; $index++) {
    if ($lines[$index] -ceq $ExactFormulation) {
      return [pscustomobject]@{
        Text = $Text
        AlreadyPresent = $true
      }
    }
  }

  $updatedLines = New-Object System.Collections.Generic.List[string]
  for ($index = 0; $index -lt $insertAt; $index++) {
    $updatedLines.Add($lines[$index])
  }
  if ($updatedLines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($updatedLines[$updatedLines.Count - 1])) {
    $updatedLines.Add('')
  }
  $updatedLines.Add($ExactFormulation)
  if ($insertAt -lt $lines.Count -and -not [string]::IsNullOrWhiteSpace($lines[$insertAt])) {
    $updatedLines.Add('')
  }
  for ($index = $insertAt; $index -lt $lines.Count; $index++) {
    $updatedLines.Add($lines[$index])
  }

  $updatedText = [string]::Join($newline, $updatedLines)
  if ($hadTrailingNewline) { $updatedText += $newline }
  return [pscustomobject]@{
    Text = $updatedText
    AlreadyPresent = $false
  }
}

function Invoke-DialogValidator {
  param([string]$Path)

  $validator = Join-Path -Path $PSScriptRoot -ChildPath 'Pruefe-Dialogstatus.ps1'
  if (-not (Test-Path -LiteralPath $validator -PathType Leaf)) {
    throw "Dialogstatus-Prüfer fehlt: $validator"
  }
  $powerShellExe = (Get-Process -Id $PID).Path
  $result = Invoke-NativeProcess `
    -FilePath $powerShellExe `
    -ArgumentList @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $validator, '-AuftragPath', $Path) `
    -TimeoutSeconds 120 `
    -MaxStdoutChars 262144 `
    -MaxStderrChars 262144
  $output = @($result.StandardOutput, $result.StandardError) -join "`n"
  if ($result.TimedOut) {
    throw 'Dialogstatus-Prüfung überschritt das Zeitlimit und wurde vollständig beendet.'
  }
  if ($result.StdoutTruncated -or $result.StderrTruncated) {
    throw 'Dialogstatus-Prüfung erzeugte mehr Ausgabe als sicher verarbeitet werden kann.'
  }
  if ($result.ExitCode -ne 0) {
    throw "Bewerbungsauftrag verletzt den Dialogvertrag: $($output.Trim())"
  }
}

function Write-ValidatedOrder {
  param(
    [object]$Order,
    [string]$Path,
    [bool]$WithBom,
    [byte[]]$OriginalBytes,
    [string]$ProfilePathToRollback,
    [byte[]]$OriginalProfileBytes
  )

  $Path = Resolve-SafePath -Candidate $Path -Root $script:ApplicationsRoot -MustExist -ForWrite -PathType Leaf
  if (-not (Test-SamePath -Left $Path -Right $script:ResolvedOrderPath)) {
    throw 'Schreibziel stimmt nicht mit dem validierten Bewerbungsauftrag überein.'
  }
  $json = ($Order | ConvertTo-Json -Depth 32) + [Environment]::NewLine
  $newBytes = ConvertTo-Utf8Bytes -Text $json -WithBom $WithBom
  $parent = Split-Path -Path $Path -Parent
  $temporaryPath = Resolve-SafePath -Candidate (Join-Path -Path $parent -ChildPath ('.dialogauftrag-' + [guid]::NewGuid().ToString('N') + '.tmp')) -Root $script:OrderWorkRoot -ForWrite -PathType Leaf
  if ((Test-SamePath -Left $temporaryPath -Right $Path) -or
      (-not [string]::IsNullOrWhiteSpace($ProfilePathToRollback) -and (Test-SamePath -Left $temporaryPath -Right $ProfilePathToRollback))) {
    throw 'Temporäres Schreibziel darf keine Eingabedatei aliasieren.'
  }
  try {
    [System.IO.File]::WriteAllBytes($temporaryPath, $newBytes)
    Invoke-DialogValidator -Path $temporaryPath
    try {
      $Path = Resolve-SafePath -Candidate $Path -Root $script:ApplicationsRoot -MustExist -ForWrite -PathType Leaf
      [System.IO.File]::WriteAllBytes($Path, $newBytes)
    } catch {
      if (-not [string]::IsNullOrWhiteSpace($ProfilePathToRollback) -and $null -ne $OriginalProfileBytes) {
        $ProfilePathToRollback = Resolve-SafePath -Candidate $ProfilePathToRollback -Root $script:DataRoot -MustExist -ForWrite -PathType Leaf
        [System.IO.File]::WriteAllBytes($ProfilePathToRollback, $OriginalProfileBytes)
      }
      if ($null -ne $OriginalBytes) {
        $Path = Resolve-SafePath -Candidate $Path -Root $script:ApplicationsRoot -MustExist -ForWrite -PathType Leaf
        [System.IO.File]::WriteAllBytes($Path, $OriginalBytes)
      }
      throw
    }
  } finally {
    if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
      try {
        $temporaryPath = Resolve-SafePath -Candidate $temporaryPath -Root $script:OrderWorkRoot -MustExist -ForWrite -PathType Leaf
        [System.IO.File]::Delete($temporaryPath)
      } catch {
        Write-Host "[WARNUNG] Temporäre Dialogdatei konnte nicht sicher entfernt werden: $($_.Exception.Message)" -ForegroundColor Yellow
      }
    }
  }
}

$projectRoot = Get-ProjectRootFromOrderPath -Path $AuftragPath
if ([string]::IsNullOrWhiteSpace([string]$projectRoot)) {
  Stop-WithUnsafePathError -Message 'AuftragPath muss unter <Projektwurzel>/Private/Bewerbungen/ liegen.'
}
try {
  $privateRoot = Resolve-SafePath -Candidate (Join-Path -Path $projectRoot -ChildPath 'Private') -Root (Join-Path -Path $projectRoot -ChildPath 'Private') -AllowRoot -MustExist -PathType Container
  $script:ApplicationsRoot = Resolve-SafePath -Candidate (Join-Path -Path $privateRoot -ChildPath 'Bewerbungen') -Root $privateRoot -MustExist -PathType Container
  $script:DataRoot = Resolve-SafePath -Candidate (Join-Path -Path $privateRoot -ChildPath 'Daten') -Root $privateRoot -PathType Container
  $resolvedOrderPath = Resolve-SafePath -Candidate $AuftragPath -Root $script:ApplicationsRoot -MustExist -ForWrite -PathType Leaf
  $script:ResolvedOrderPath = $resolvedOrderPath
  $script:OrderWorkRoot = Resolve-SafePath -Candidate (Split-Path -Path $resolvedOrderPath -Parent) -Root $script:ApplicationsRoot -MustExist -PathType Container
  $workCollection = Split-Path -Path $script:OrderWorkRoot -Parent
  if (-not (Test-PathNameEquals -Left (Split-Path -Path $workCollection -Leaf) -Right '_Arbeitsdateien')) {
    throw 'Bewerbungsauftrag muss direkt in einem Arbeitsordner unter _Arbeitsdateien liegen.'
  }
} catch {
  Stop-WithUnsafePathError -Message "Unsicherer Bewerbungsauftragspfad: $($_.Exception.Message)"
}

try {
  Invoke-DialogValidator -Path $resolvedOrderPath
} catch {
  Stop-WithValidationError -Message $_.Exception.Message
}

try {
  $orderState = Read-Utf8FileState -Path $resolvedOrderPath
  $auftrag = $orderState.Text | ConvertFrom-Json
} catch {
  Stop-WithValidationError -Message "Bewerbungsauftrag konnte nicht gelesen werden: $($_.Exception.Message)"
}

$schemaVersion = 0
if (-not [int]::TryParse([string](Get-JsonProperty -Object $auftrag -Name 'schemaVersion'), [ref]$schemaVersion) -or $schemaVersion -notin @(4, 5)) {
  Stop-WithValidationError -Message 'Dialogangaben können nur in einem Bewerbungsauftrag mit Schema 4 oder 5 übernommen werden.'
}

if ($AngabeId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$') {
  Stop-WithValidationError -Message 'AngabeId besitzt kein gültiges technisches Format.'
}
$dialog = Get-JsonProperty -Object $auftrag -Name 'dialog'
$facts = @((Get-JsonProperty -Object $dialog -Name 'angaben'))
$matches = @($facts | Where-Object { [string](Get-JsonProperty -Object $_ -Name 'id') -ceq $AngabeId })
if ($matches.Count -eq 0) {
  Stop-WithValidationError -Message "Dialogangabe wurde im Bewerbungsauftrag nicht gefunden: $AngabeId"
}
if ($matches.Count -gt 1) {
  Stop-WithValidationError -Message "Dialogangabe ist im Bewerbungsauftrag nicht eindeutig: $AngabeId"
}
$fact = $matches[0]
$existingDecision = [string](Get-JsonProperty -Object $fact -Name 'speicherentscheidung')
$profileUpdate = Get-JsonProperty -Object $fact -Name 'profilaktualisierung'
$dialogStatus = [string](Get-JsonProperty -Object $dialog -Name 'status')

if ($Speicherentscheidung -eq 'nur_auftrag') {
  if ($ZustimmungBestaetigt -or
      -not [string]::IsNullOrWhiteSpace($ProfilPath) -or
      -not [string]::IsNullOrWhiteSpace($Abschnitt) -or
      -not [string]::IsNullOrWhiteSpace($Formulierung) -or
      -not [string]::IsNullOrWhiteSpace($ErwarteterDateiHash)) {
    Stop-WithValidationError -Message 'nur_auftrag darf keine Zustimmung und keine Profildatei-, Abschnitts-, Formulierungs- oder Hashparameter erhalten.'
  }
  if ($existingDecision -eq 'dauerhaft') {
    Stop-WithValidationError -Message 'Eine bereits dauerhaft verarbeitete Dialogangabe kann nicht mit diesem Werkzeug auf nur_auftrag zurückgestuft werden.'
  }
  if ($existingDecision -eq 'nur_auftrag' -and [string](Get-JsonProperty -Object $profileUpdate -Name 'status') -eq 'nicht_geaendert') {
    Write-Host "[OK] Dialogangabe ist bereits ausschließlich für diesen Auftrag markiert: $AngabeId" -ForegroundColor Green
    exit 0
  }
  if ($existingDecision -cne 'ausstehend' -or [string](Get-JsonProperty -Object $profileUpdate -Name 'status') -cne 'ausstehend') {
    Stop-WithValidationError -Message 'Eine neue auftragsbezogene Speicherentscheidung erfordert den Zustand ausstehend/ausstehend.'
  }
  if ($dialogStatus -cne 'speicherentscheidung_offen') {
    Stop-WithValidationError -Message 'Eine neue Speicherentscheidung ist nur mit dialog.status speicherentscheidung_offen zulässig.'
  }

  Set-JsonProperty -Object $fact -Name 'speicherentscheidung' -Value 'nur_auftrag'
  if ($null -eq $profileUpdate) {
    $profileUpdate = [pscustomobject][ordered]@{}
    Set-JsonProperty -Object $fact -Name 'profilaktualisierung' -Value $profileUpdate
  }
  Set-JsonProperty -Object $profileUpdate -Name 'status' -Value 'nicht_geaendert'
  foreach ($field in @('datei', 'abschnitt', 'vorgeschlageneFormulierung', 'fachlicherZieltyp', 'bestaetigteFormulierung', 'zugestimmtAtUtc', 'vorherSha256', 'nachherSha256', 'aktualisiertAtUtc')) {
    Remove-JsonProperty -Object $profileUpdate -Name $field
  }
  try {
    Complete-StorageDecisionState -Dialog $dialog -FactId $AngabeId
  } catch {
    Stop-WithValidationError -Message "Speicherfrage konnte nicht konsistent abgeschlossen werden: $($_.Exception.Message)"
  }
  Set-JsonProperty -Object $dialog -Name 'updatedAtUtc' -Value ([datetime]::UtcNow.ToString('o'))

  try {
    Write-ValidatedOrder -Order $auftrag -Path $resolvedOrderPath -WithBom $orderState.HasBom -OriginalBytes $orderState.Bytes -ProfilePathToRollback '' -OriginalProfileBytes $null
  } catch {
    Stop-WithValidationError -Message "Bewerbungsauftrag konnte nicht sicher aktualisiert werden: $($_.Exception.Message)"
  }
  Write-Host "[OK] Dialogangabe wird nur für diesen Bewerbungsauftrag verwendet; keine Profildatei wurde gelesen oder verändert: $AngabeId" -ForegroundColor Green
  exit 0
}

$factContradiction = Get-JsonProperty -Object $fact -Name 'widerspruch'
$factContradictionResolved = Get-JsonProperty -Object $fact -Name 'widerspruchGeklaert'
$truthStatus = [string](Get-JsonProperty -Object $fact -Name 'wahrheitsstatus')
if ($truthStatus -cne 'bestaetigt') {
  Stop-WithValidationError -Message 'Dauerhafte Profilübernahme ist nur für eine Angabe mit wahrheitsstatus bestaetigt zulässig.'
}
if ((($factContradiction -eq $true) -or $truthStatus -eq 'widerspruechlich') -and
    $factContradictionResolved -ne $true) {
  Stop-WithValidationError -Message 'Eine ungeklärte Widerspruchsangabe darf nicht dauerhaft in das Profil übernommen werden.'
}

if (-not $ZustimmungBestaetigt) {
  Stop-WithValidationError -Message 'Dauerhafte Profilübernahme erfordert -ZustimmungBestaetigt.'
}
foreach ($parameter in @(
  [pscustomobject]@{ Name = 'ProfilPath'; Value = $ProfilPath },
  [pscustomobject]@{ Name = 'Abschnitt'; Value = $Abschnitt },
  [pscustomobject]@{ Name = 'Formulierung'; Value = $Formulierung },
  [pscustomobject]@{ Name = 'ErwarteterDateiHash'; Value = $ErwarteterDateiHash }
)) {
  if ([string]::IsNullOrWhiteSpace([string]$parameter.Value)) {
    Stop-WithValidationError -Message "Dauerhafte Profilübernahme erfordert -$($parameter.Name)."
  }
}
if ($ErwarteterDateiHash -notmatch '^[A-Fa-f0-9]{64}$') {
  Stop-WithValidationError -Message 'ErwarteterDateiHash muss ein SHA-256-Wert mit 64 Hexadezimalzeichen sein.'
}

$isIdempotentRetry = $existingDecision -ceq 'dauerhaft'
if (-not $isIdempotentRetry) {
  if ($existingDecision -cne 'ausstehend' -or [string](Get-JsonProperty -Object $profileUpdate -Name 'status') -cne 'ausstehend') {
    Stop-WithValidationError -Message 'Eine neue dauerhafte Profilübernahme erfordert den Zustand ausstehend/ausstehend.'
  }
  if ($dialogStatus -cne 'speicherentscheidung_offen') {
    Stop-WithValidationError -Message 'Eine neue dauerhafte Profilübernahme ist nur mit dialog.status speicherentscheidung_offen zulässig.'
  }
}

$normalizedSection = Get-NormalizedSectionName -Value $Abschnitt
if ([string]::IsNullOrWhiteSpace($normalizedSection)) {
  Stop-WithValidationError -Message 'Abschnitt muss eine einzelne, nichtleere Markdown-Überschrift bezeichnen.'
}
$normalizedFormulation = $Formulierung.Trim()
if ([string]::IsNullOrWhiteSpace($normalizedFormulation) -or $normalizedFormulation -match "[`r`n`0]") {
  Stop-WithValidationError -Message 'Formulierung muss eine einzelne, nichtleere Zeile sein.'
}

$allowedProfiles = [ordered]@{
  'Private/Daten/01_PERSOENLICHE_DATEN.md' = [System.IO.Path]::GetFullPath((Join-Path -Path $projectRoot -ChildPath 'Private/Daten/01_PERSOENLICHE_DATEN.md'))
  'Private/Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md' = [System.IO.Path]::GetFullPath((Join-Path -Path $projectRoot -ChildPath 'Private/Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md'))
}
$requestedProfileFull = if ([System.IO.Path]::IsPathRooted($ProfilPath)) {
  [System.IO.Path]::GetFullPath($ProfilPath)
} else {
  [System.IO.Path]::GetFullPath((Join-Path -Path $projectRoot -ChildPath $ProfilPath))
}
$comparison = Get-PathComparison
$profileRelativePath = $null
foreach ($entry in $allowedProfiles.GetEnumerator()) {
  if ([string]::Equals($requestedProfileFull, $entry.Value, $comparison)) {
    $profileRelativePath = [string]$entry.Key
    $requestedProfileFull = [string]$entry.Value
    break
  }
}
if ($null -eq $profileRelativePath) {
  Stop-WithValidationError -Message 'ProfilPath muss exakt auf Private/Daten/01_PERSOENLICHE_DATEN.md oder Private/Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md zeigen.'
}
try {
  $requestedProfileFull = Resolve-SafePath -Candidate $requestedProfileFull -Root $script:DataRoot -MustExist -ForWrite -PathType Leaf
  if (Test-SamePath -Left $requestedProfileFull -Right $resolvedOrderPath) {
    throw 'Profildatei darf den Bewerbungsauftrag nicht aliasieren.'
  }
} catch {
  Stop-WithUnsafePathError -Message "Unsicherer Profilpfad: $($_.Exception.Message)"
}

$storedPath = ([string](Get-JsonProperty -Object $profileUpdate -Name 'datei')).Replace('\', '/')
$storedSection = [string](Get-JsonProperty -Object $profileUpdate -Name 'abschnitt')
$storedTargetType = [string](Get-JsonProperty -Object $profileUpdate -Name 'fachlicherZieltyp')
$expectedProfileForTarget = Get-ExpectedProfileFileForTargetType -TargetType $storedTargetType
if ($null -eq $expectedProfileForTarget -or $storedPath -cne $expectedProfileForTarget) {
  Stop-WithValidationError -Message 'Der gespeicherte fachliche Zieltyp ist nicht eindeutig an die zulässige Profildatei gebunden.'
}
if ($profileRelativePath -cne $storedPath) {
  Stop-WithValidationError -Message "ProfilPath weicht vom vor der Zustimmung gespeicherten Profilziel ab: $storedPath"
}
if ($normalizedSection -cne $storedSection) {
  Stop-WithValidationError -Message "Abschnitt weicht vom vor der Zustimmung gespeicherten Zielabschnitt ab: $storedSection"
}

if (-not $isIdempotentRetry) {
  $storedProposedFormulation = [string](Get-JsonProperty -Object $profileUpdate -Name 'vorgeschlageneFormulierung')
  $storedBeforeHash = [string](Get-JsonProperty -Object $profileUpdate -Name 'vorherSha256')
  if ($normalizedFormulation -cne $storedProposedFormulation) {
    Stop-WithValidationError -Message 'Formulierung weicht von der vor der Zustimmung offengelegten Formulierung ab.'
  }
  if ($ErwarteterDateiHash -ine $storedBeforeHash) {
    Stop-WithValidationError -Message 'ErwarteterDateiHash weicht vom vor der Zustimmung gespeicherten Profilhash ab.'
  }
}
try {
  $profileState = Read-Utf8FileState -Path $requestedProfileFull
  $actualBeforeHash = Get-Sha256ForBytes -Bytes $profileState.Bytes
} catch {
  Stop-WithValidationError -Message "Profildatei konnte nicht sicher gelesen werden: $($_.Exception.Message)"
}
if ($actualBeforeHash -ine $ErwarteterDateiHash) {
  Stop-WithValidationError -Message "Profildatei wurde seit der Bestätigung verändert; erwartet $ErwarteterDateiHash, gefunden $actualBeforeHash."
}

if ($isIdempotentRetry) {
  $storedStatus = [string](Get-JsonProperty -Object $profileUpdate -Name 'status')
  $storedFormulation = [string](Get-JsonProperty -Object $profileUpdate -Name 'bestaetigteFormulierung')
  $storedAfterHash = [string](Get-JsonProperty -Object $profileUpdate -Name 'nachherSha256')
  if ($storedStatus -in @('aktualisiert', 'bereits_vorhanden') -and
      $storedPath -ceq $profileRelativePath -and
      $storedSection -ceq $normalizedSection -and
      $storedFormulation -ceq $normalizedFormulation -and
      $storedAfterHash -ieq $actualBeforeHash) {
    Write-Host "[OK] Dialogangabe wurde bereits dauerhaft und hashgleich verarbeitet: $AngabeId" -ForegroundColor Green
    exit 0
  }
  Stop-WithValidationError -Message 'Dialogangabe ist bereits dauerhaft mit einem anderen oder nicht mehr hashgleichen Profilnachweis verarbeitet.'
}

try {
  $profileResult = Get-UpdatedProfileText -Text $profileState.Text -SectionName $normalizedSection -ExactFormulation $normalizedFormulation
} catch {
  Stop-WithValidationError -Message "Profildatei konnte nicht sicher vorbereitet werden: $($_.Exception.Message)"
}

$newProfileBytes = if ($profileResult.AlreadyPresent) {
  $profileState.Bytes
} else {
  ConvertTo-Utf8Bytes -Text $profileResult.Text -WithBom $profileState.HasBom
}
$actualAfterHash = Get-Sha256ForBytes -Bytes $newProfileBytes
$profileStatus = if ($profileResult.AlreadyPresent) { 'bereits_vorhanden' } else { 'aktualisiert' }
$nowUtc = [datetime]::UtcNow.ToString('o')

Set-JsonProperty -Object $fact -Name 'speicherentscheidung' -Value 'dauerhaft'
if ($null -eq $profileUpdate) {
  $profileUpdate = [pscustomobject][ordered]@{}
  Set-JsonProperty -Object $fact -Name 'profilaktualisierung' -Value $profileUpdate
}
Set-JsonProperty -Object $profileUpdate -Name 'status' -Value $profileStatus
Set-JsonProperty -Object $profileUpdate -Name 'datei' -Value $profileRelativePath
Set-JsonProperty -Object $profileUpdate -Name 'abschnitt' -Value $normalizedSection
Set-JsonProperty -Object $profileUpdate -Name 'vorgeschlageneFormulierung' -Value $normalizedFormulation
Set-JsonProperty -Object $profileUpdate -Name 'fachlicherZieltyp' -Value $storedTargetType
Set-JsonProperty -Object $profileUpdate -Name 'bestaetigteFormulierung' -Value $normalizedFormulation
Set-JsonProperty -Object $profileUpdate -Name 'zugestimmtAtUtc' -Value $nowUtc
Set-JsonProperty -Object $profileUpdate -Name 'vorherSha256' -Value $actualBeforeHash
Set-JsonProperty -Object $profileUpdate -Name 'nachherSha256' -Value $actualAfterHash
Set-JsonProperty -Object $profileUpdate -Name 'aktualisiertAtUtc' -Value $nowUtc
try {
  Complete-StorageDecisionState -Dialog $dialog -FactId $AngabeId
} catch {
  Stop-WithValidationError -Message "Speicherfrage konnte nicht konsistent abgeschlossen werden: $($_.Exception.Message)"
}
Set-JsonProperty -Object $dialog -Name 'updatedAtUtc' -Value $nowUtc

$profileWasWritten = $false
try {
  $currentHashBeforeCommit = (Get-FileHash -LiteralPath $requestedProfileFull -Algorithm SHA256).Hash
  if ($currentHashBeforeCommit -ine $actualBeforeHash) {
    throw "Profildatei wurde zwischen Prüfung und Schreiben verändert: $currentHashBeforeCommit statt $actualBeforeHash"
  }
  if (-not $profileResult.AlreadyPresent) {
    $requestedProfileFull = Resolve-SafePath -Candidate $requestedProfileFull -Root $script:DataRoot -MustExist -ForWrite -PathType Leaf
    [System.IO.File]::WriteAllBytes($requestedProfileFull, $newProfileBytes)
    $profileWasWritten = $true
    $writtenHash = (Get-FileHash -LiteralPath $requestedProfileFull -Algorithm SHA256).Hash
    if ($writtenHash -ine $actualAfterHash) {
      throw "Hashprüfung nach Profiländerung fehlgeschlagen: $writtenHash statt $actualAfterHash"
    }
  }
  Write-ValidatedOrder -Order $auftrag -Path $resolvedOrderPath -WithBom $orderState.HasBom -OriginalBytes $orderState.Bytes -ProfilePathToRollback $(if ($profileWasWritten) { $requestedProfileFull } else { '' }) -OriginalProfileBytes $(if ($profileWasWritten) { $profileState.Bytes } else { $null })
} catch {
  if ($profileWasWritten) {
    try {
      $requestedProfileFull = Resolve-SafePath -Candidate $requestedProfileFull -Root $script:DataRoot -MustExist -ForWrite -PathType Leaf
      [System.IO.File]::WriteAllBytes($requestedProfileFull, $profileState.Bytes)
    } catch {
      Write-Host "[FEHLER] Zusätzlich konnte die ursprüngliche Profildatei nicht automatisch wiederhergestellt werden: $($_.Exception.Message)" -ForegroundColor Red
    }
  }
  Stop-WithValidationError -Message "Dauerhafte Profilübernahme wurde abgebrochen: $($_.Exception.Message)"
}

if ($profileResult.AlreadyPresent) {
  Write-Host "[OK] Exakte Formulierung war bereits vorhanden; Zustimmung und Hashnachweis wurden im Bewerbungsauftrag protokolliert: $AngabeId" -ForegroundColor Green
} else {
  Write-Host "[OK] Bestätigte Dialogangabe wurde im Abschnitt '$normalizedSection' dauerhaft übernommen und im Bewerbungsauftrag protokolliert: $AngabeId" -ForegroundColor Green
}
exit 0
