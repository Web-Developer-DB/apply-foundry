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
$script:TransactionMutex = $null

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

function Write-BytesWithFlush {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][byte[]]$Bytes)

  $stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
  try {
    $stream.Write($Bytes, 0, $Bytes.Length)
    $stream.Flush($true)
  } finally {
    $stream.Dispose()
  }
}

function Move-TemporaryFileAtomically {
  param([Parameter(Mandatory)][string]$TemporaryPath, [Parameter(Mandatory)][string]$TargetPath)

  if (-not (Test-Path -LiteralPath $TemporaryPath -PathType Leaf)) { throw "Temporäre Transaktionsdatei fehlt: $TemporaryPath" }
  [System.IO.File]::Move($TemporaryPath, $TargetPath, $true)
}

function Write-AtomicBytes {
  param([Parameter(Mandatory)][string]$TargetPath, [Parameter(Mandatory)][byte[]]$Bytes, [Parameter(Mandatory)][string]$TempDirectory)

  $tempPath = Join-Path -Path $TempDirectory -ChildPath ('.write-' + [guid]::NewGuid().ToString('N') + '.tmp')
  Write-BytesWithFlush -Path $tempPath -Bytes $Bytes
  Move-TemporaryFileAtomically -TemporaryPath $tempPath -TargetPath $TargetPath
  if ((Get-Sha256ForBytes -Bytes ([System.IO.File]::ReadAllBytes($TargetPath))) -ine (Get-Sha256ForBytes -Bytes $Bytes)) {
    throw "Hashprüfung nach atomarem Schreiben fehlgeschlagen: $TargetPath"
  }
}

function Enter-DialogTransactionLock {
  $lockMaterial = "$($script:ResolvedOrderPath)|$($script:DataRoot)"
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($lockMaterial)
  $hash = Get-Sha256ForBytes -Bytes $bytes
  $script:TransactionMutex = [System.Threading.Mutex]::new($false, "BewerbungsAgent.Dialog.$hash")
  try {
    if (-not $script:TransactionMutex.WaitOne([timespan]::FromSeconds(30))) { throw 'Zeitlimit beim Warten auf die exklusive Dialog-Transaktionssperre.' }
  } catch {
    $script:TransactionMutex.Dispose()
    $script:TransactionMutex = $null
    throw
  }
}

function Exit-DialogTransactionLock {
  if ($null -eq $script:TransactionMutex) { return }
  try { $script:TransactionMutex.ReleaseMutex() } catch { }
  $script:TransactionMutex.Dispose()
  $script:TransactionMutex = $null
}

function Recover-PendingDialogTransactions {
  param([Parameter(Mandatory)][string]$ProfilePath, [Parameter(Mandatory)][string]$OrderPath)

  $pending = @(Get-ChildItem -LiteralPath $script:OrderWorkRoot -Directory -Force -Filter '.dialogtransaktion-*')
  foreach ($directory in $pending) {
    $journalPath = Join-Path -Path $directory.FullName -ChildPath 'journal.json'
    if (-not (Test-Path -LiteralPath $journalPath -PathType Leaf)) {
      Remove-Item -LiteralPath $directory.FullName -Recurse -Force
      Write-Host "[WARNUNG] Unvollständige Dialogtransaktion ohne Commit-Journal wurde entfernt." -ForegroundColor Yellow
      continue
    }
    try { $journal = (Get-Content -LiteralPath $journalPath -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { throw "Dialogtransaktionsjournal ist ungültig: $journalPath" }
    if ([int]$journal.schemaVersion -ne 1 -or [string]$journal.profileFileName -cne (Split-Path -Path $ProfilePath -Leaf) -or [string]$journal.orderFileName -cne (Split-Path -Path $OrderPath -Leaf)) {
      throw "Dialogtransaktionsjournal passt nicht zum angeforderten Profil- und Auftragsziel: $journalPath"
    }
    $profileBackup = Join-Path -Path $directory.FullName -ChildPath 'profile.before.bin'
    $orderBackup = Join-Path -Path $directory.FullName -ChildPath 'order.before.bin'
    if (-not (Test-Path -LiteralPath $profileBackup -PathType Leaf) -or -not (Test-Path -LiteralPath $orderBackup -PathType Leaf)) { throw "Dialogtransaktion enthält keine vollständigen Sicherungen: $($directory.FullName)" }
    $profileBefore = [System.IO.File]::ReadAllBytes($profileBackup)
    $orderBefore = [System.IO.File]::ReadAllBytes($orderBackup)
    if ((Get-Sha256ForBytes -Bytes $profileBefore) -ine [string]$journal.profileBeforeSha256 -or (Get-Sha256ForBytes -Bytes $orderBefore) -ine [string]$journal.orderBeforeSha256) { throw "Dialogtransaktion besitzt beschädigte Sicherungshashes: $($directory.FullName)" }
    $profileCurrent = Get-Sha256ForBytes -Bytes ([System.IO.File]::ReadAllBytes($ProfilePath))
    $orderCurrent = Get-Sha256ForBytes -Bytes ([System.IO.File]::ReadAllBytes($OrderPath))
    if ($profileCurrent -notin @([string]$journal.profileBeforeSha256, [string]$journal.profileAfterSha256) -or $orderCurrent -notin @([string]$journal.orderBeforeSha256, [string]$journal.orderAfterSha256)) {
      throw "Dialogtransaktion kann nach einer externen Änderung nicht sicher wiederhergestellt werden: $($directory.FullName)"
    }
    Write-AtomicBytes -TargetPath $ProfilePath -Bytes $profileBefore -TempDirectory $directory.FullName
    Write-AtomicBytes -TargetPath $OrderPath -Bytes $orderBefore -TempDirectory $directory.FullName
    Remove-Item -LiteralPath $directory.FullName -Recurse -Force
    Write-Host "[WARNUNG] Unterbrochene Dialogtransaktion wurde sicher auf den vorherigen konsistenten Stand zurückgesetzt." -ForegroundColor Yellow
  }
}

function Invoke-AtomicProfileOrderTransaction {
  param(
    [Parameter(Mandatory)][object]$Order,
    [Parameter(Mandatory)][string]$OrderPath,
    [Parameter(Mandatory)][bool]$OrderWithBom,
    [Parameter(Mandatory)][byte[]]$OriginalOrderBytes,
    [Parameter(Mandatory)][string]$ProfilePath,
    [Parameter(Mandatory)][byte[]]$OriginalProfileBytes,
    [Parameter(Mandatory)][byte[]]$NewProfileBytes
  )

  $OrderPath = Resolve-SafePath -Candidate $OrderPath -Root $script:ApplicationsRoot -MustExist -ForWrite -PathType Leaf
  $ProfilePath = Resolve-SafePath -Candidate $ProfilePath -Root $script:DataRoot -MustExist -ForWrite -PathType Leaf
  if (-not (Test-SamePath -Left $OrderPath -Right $script:ResolvedOrderPath)) {
    throw 'Schreibziel stimmt nicht mit dem validierten Bewerbungsauftrag überein.'
  }
  $json = ($Order | ConvertTo-Json -Depth 32) + [Environment]::NewLine
  $newOrderBytes = ConvertTo-Utf8Bytes -Text $json -WithBom $OrderWithBom
  if ((Get-Sha256ForBytes -Bytes ([System.IO.File]::ReadAllBytes($ProfilePath))) -ine (Get-Sha256ForBytes -Bytes $OriginalProfileBytes) -or
      (Get-Sha256ForBytes -Bytes ([System.IO.File]::ReadAllBytes($OrderPath))) -ine (Get-Sha256ForBytes -Bytes $OriginalOrderBytes)) {
    throw 'Profil oder Bewerbungsauftrag wurde während der vorbereiteten Transaktion verändert.'
  }
  $transactionDirectory = Join-Path -Path $script:OrderWorkRoot -ChildPath ('.dialogtransaktion-' + [guid]::NewGuid().ToString('N'))
  New-Item -Path $transactionDirectory -ItemType Directory -ErrorAction Stop | Out-Null
  $transactionDirectory = Resolve-SafePath -Candidate $transactionDirectory -Root $script:OrderWorkRoot -MustExist -ForWrite -PathType Container
  $profileBeforePath = Join-Path -Path $transactionDirectory -ChildPath 'profile.before.bin'
  $orderBeforePath = Join-Path -Path $transactionDirectory -ChildPath 'order.before.bin'
  $profileNewPath = Join-Path -Path $transactionDirectory -ChildPath 'profile.after.tmp'
  $orderNewPath = Join-Path -Path $transactionDirectory -ChildPath 'order.after.tmp'
  $orderValidationPath = Join-Path -Path $script:OrderWorkRoot -ChildPath ('.dialogauftrag-' + [guid]::NewGuid().ToString('N') + '.tmp')
  $journalPath = Join-Path -Path $transactionDirectory -ChildPath 'journal.json'
  $completed = $false
  try {
    Write-BytesWithFlush -Path $profileBeforePath -Bytes $OriginalProfileBytes
    Write-BytesWithFlush -Path $orderBeforePath -Bytes $OriginalOrderBytes
    Write-BytesWithFlush -Path $profileNewPath -Bytes $NewProfileBytes
    Write-BytesWithFlush -Path $orderValidationPath -Bytes $newOrderBytes
    Invoke-DialogValidator -Path $orderValidationPath
    Remove-Item -LiteralPath $orderValidationPath -Force
    Write-BytesWithFlush -Path $orderNewPath -Bytes $newOrderBytes
    $journal = [ordered]@{
      schemaVersion = 1
      profileFileName = Split-Path -Path $ProfilePath -Leaf
      orderFileName = Split-Path -Path $OrderPath -Leaf
      profileBeforeSha256 = Get-Sha256ForBytes -Bytes $OriginalProfileBytes
      profileAfterSha256 = Get-Sha256ForBytes -Bytes $NewProfileBytes
      orderBeforeSha256 = Get-Sha256ForBytes -Bytes $OriginalOrderBytes
      orderAfterSha256 = Get-Sha256ForBytes -Bytes $newOrderBytes
      createdAtUtc = [datetime]::UtcNow.ToString('o')
    }
    Write-BytesWithFlush -Path $journalPath -Bytes (ConvertTo-Utf8Bytes -Text (($journal | ConvertTo-Json -Depth 6) + [Environment]::NewLine) -WithBom $false)
    Move-TemporaryFileAtomically -TemporaryPath $profileNewPath -TargetPath $ProfilePath
    Move-TemporaryFileAtomically -TemporaryPath $orderNewPath -TargetPath $OrderPath
    if ((Get-Sha256ForBytes -Bytes ([System.IO.File]::ReadAllBytes($ProfilePath))) -ine $journal.profileAfterSha256 -or
        (Get-Sha256ForBytes -Bytes ([System.IO.File]::ReadAllBytes($OrderPath))) -ine $journal.orderAfterSha256) {
      throw 'Hashprüfung nach Dialogtransaktion fehlgeschlagen.'
    }
    $completed = $true
  } catch {
    $transactionError = $_
    try { Recover-PendingDialogTransactions -ProfilePath $ProfilePath -OrderPath $OrderPath } catch { throw "Dialogtransaktion fehlgeschlagen und die Wiederherstellung ist blockiert: $($_.Exception.Message)" }
    throw $transactionError
  } finally {
    if (Test-Path -LiteralPath $orderValidationPath -PathType Leaf) {
      Remove-Item -LiteralPath $orderValidationPath -Force -ErrorAction SilentlyContinue
    }
    if ($completed -and (Test-Path -LiteralPath $transactionDirectory -PathType Container)) {
      Remove-Item -LiteralPath $transactionDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

function Write-ValidatedOrder {
  param(
    [Parameter(Mandatory)][object]$Order,
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][bool]$WithBom,
    [Parameter(Mandatory)][byte[]]$OriginalBytes,
    [string]$ProfilePathToRollback,
    [byte[]]$OriginalProfileBytes
  )

  if (-not [string]::IsNullOrWhiteSpace($ProfilePathToRollback) -or $null -ne $OriginalProfileBytes) {
    throw 'Mehrdatei-Änderungen müssen über Invoke-AtomicProfileOrderTransaction erfolgen.'
  }
  $Path = Resolve-SafePath -Candidate $Path -Root $script:ApplicationsRoot -MustExist -ForWrite -PathType Leaf
  if (-not (Test-SamePath -Left $Path -Right $script:ResolvedOrderPath)) { throw 'Schreibziel stimmt nicht mit dem validierten Bewerbungsauftrag überein.' }
  if ((Get-Sha256ForBytes -Bytes ([System.IO.File]::ReadAllBytes($Path))) -ine (Get-Sha256ForBytes -Bytes $OriginalBytes)) { throw 'Bewerbungsauftrag wurde zwischen Prüfung und atomarem Schreiben verändert.' }
  $newBytes = ConvertTo-Utf8Bytes -Text (($Order | ConvertTo-Json -Depth 32) + [Environment]::NewLine) -WithBom $WithBom
  $temporaryPath = Join-Path -Path $script:OrderWorkRoot -ChildPath ('.dialogauftrag-' + [guid]::NewGuid().ToString('N') + '.tmp')
  try {
    Write-BytesWithFlush -Path $temporaryPath -Bytes $newBytes
    Invoke-DialogValidator -Path $temporaryPath
    Move-TemporaryFileAtomically -TemporaryPath $temporaryPath -TargetPath $Path
    if ((Get-Sha256ForBytes -Bytes ([System.IO.File]::ReadAllBytes($Path))) -ine (Get-Sha256ForBytes -Bytes $newBytes)) { throw 'Hashprüfung nach atomarem Auftragsschreiben fehlgeschlagen.' }
  } finally {
    if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue }
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
  Enter-DialogTransactionLock
  Recover-PendingDialogTransactions -ProfilePath $requestedProfileFull -OrderPath $resolvedOrderPath
} catch {
  Stop-WithValidationError -Message "Exklusive Dialogtransaktion konnte nicht sicher vorbereitet werden: $($_.Exception.Message)"
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
    Exit-DialogTransactionLock
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
  Invoke-AtomicProfileOrderTransaction -Order $auftrag -OrderPath $resolvedOrderPath -OrderWithBom $orderState.HasBom -OriginalOrderBytes $orderState.Bytes -ProfilePath $requestedProfileFull -OriginalProfileBytes $profileState.Bytes -NewProfileBytes $newProfileBytes
  $profileWasWritten = -not $profileResult.AlreadyPresent
} catch {
  Stop-WithValidationError -Message "Dauerhafte Profilübernahme wurde abgebrochen: $($_.Exception.Message)"
}

if ($profileResult.AlreadyPresent) {
  Write-Host "[OK] Exakte Formulierung war bereits vorhanden; Zustimmung und Hashnachweis wurden im Bewerbungsauftrag protokolliert: $AngabeId" -ForegroundColor Green
} else {
  Write-Host "[OK] Bestätigte Dialogangabe wurde im Abschnitt '$normalizedSection' dauerhaft übernommen und im Bewerbungsauftrag protokolliert: $AngabeId" -ForegroundColor Green
}
Exit-DialogTransactionLock
exit 0
