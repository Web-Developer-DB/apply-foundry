#requires -Version 7.6
#requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Platform.psm1") -ErrorAction Stop

$script:PassfotoFileName = "Passfoto.png"
$script:PassfotoStartMarker = "<!-- passfoto:start -->"
$script:PassfotoEndMarker = "<!-- passfoto:end -->"

function Get-PngUInt32BigEndian {
  param(
    [Parameter(Mandatory)][byte[]]$Bytes,
    [Parameter(Mandatory)][int]$Offset
  )

  return [uint32]((([uint32]$Bytes[$Offset]) -shl 24) -bor
    (([uint32]$Bytes[$Offset + 1]) -shl 16) -bor
    (([uint32]$Bytes[$Offset + 2]) -shl 8) -bor
    ([uint32]$Bytes[$Offset + 3]))
}

function Test-PassfotoPngBytes {
  param([Parameter(Mandatory)][byte[]]$Bytes)

  $signature = [byte[]](137, 80, 78, 71, 13, 10, 26, 10)
  if ($Bytes.Length -lt 33) {
    return [pscustomobject][ordered]@{ Valid = $false; Error = "PNG-Datei ist zu kurz."; Width = 0; Height = 0 }
  }
  for ($index = 0; $index -lt $signature.Length; $index++) {
    if ($Bytes[$index] -ne $signature[$index]) {
      return [pscustomobject][ordered]@{ Valid = $false; Error = "PNG-Signatur fehlt oder ist beschädigt."; Width = 0; Height = 0 }
    }
  }

  $ihdrLength = Get-PngUInt32BigEndian -Bytes $Bytes -Offset 8
  $ihdrName = [System.Text.Encoding]::ASCII.GetString($Bytes, 12, 4)
  if ($ihdrLength -ne 13 -or $ihdrName -cne "IHDR") {
    return [pscustomobject][ordered]@{ Valid = $false; Error = "PNG enthält keinen gültigen IHDR-Header."; Width = 0; Height = 0 }
  }

  $width = Get-PngUInt32BigEndian -Bytes $Bytes -Offset 16
  $height = Get-PngUInt32BigEndian -Bytes $Bytes -Offset 20
  if ($width -eq 0 -or $height -eq 0) {
    return [pscustomobject][ordered]@{ Valid = $false; Error = "PNG enthält keine gültigen Bildmaße."; Width = 0; Height = 0 }
  }

  return [pscustomobject][ordered]@{
    Valid = $true
    Error = $null
    Width = [long]$width
    Height = [long]$height
  }
}

function Get-PassfotoSourceState {
  param([Parameter(Mandatory)][string]$DataRoot)

  $safeDataRoot = Resolve-SafePath -Candidate $DataRoot -Root $DataRoot -AllowRoot -MustExist -PathType Container
  $candidate = Join-Path -Path $safeDataRoot -ChildPath $script:PassfotoFileName
  if (-not (Test-Path -LiteralPath $candidate)) {
    $caseVariants = @(Get-ChildItem -LiteralPath $safeDataRoot -Force -File | Where-Object {
      $_.Name -ieq $script:PassfotoFileName -and $_.Name -cne $script:PassfotoFileName
    })
    if ($caseVariants.Count -gt 0) {
      throw "Das optionale Bewerbungsfoto muss exakt '$script:PassfotoFileName' heißen; gefunden: $($caseVariants.Name -join ', ')."
    }
    return [pscustomobject][ordered]@{
      Exists = $false
      Path = [System.IO.Path]::GetFullPath($candidate)
      Name = $script:PassfotoFileName
      ByteCount = 0
      Sha256 = $null
      Width = 0
      Height = 0
    }
  }

  $safePath = Resolve-SafePath -Candidate $candidate -Root $safeDataRoot -MustExist -PathType Leaf
  $item = Get-Item -LiteralPath $safePath -Force
  if ($item.Name -cne $script:PassfotoFileName) {
    throw "Das optionale Bewerbungsfoto muss exakt '$script:PassfotoFileName' heißen; gefunden: $($item.Name)."
  }
  $bytes = [System.IO.File]::ReadAllBytes($safePath)
  $validation = Test-PassfotoPngBytes -Bytes $bytes
  if (-not $validation.Valid) {
    throw "$script:PassfotoFileName ist keine gültige PNG-Datei: $($validation.Error)"
  }

  return [pscustomobject][ordered]@{
    Exists = $true
    Path = $safePath
    Name = $script:PassfotoFileName
    ByteCount = [long]$bytes.Length
    Sha256 = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes))
    Width = [long]$validation.Width
    Height = [long]$validation.Height
  }
}

function Get-HtmlAttributeValue {
  param(
    [Parameter(Mandatory)][string]$Tag,
    [Parameter(Mandatory)][string]$Name
  )

  $pattern = '(?is)\b' + [regex]::Escape($Name) + '\s*=\s*(?:"(?<double>[^"]*)"|''(?<single>[^'']*)'')'
  $match = [regex]::Match($Tag, $pattern)
  if (-not $match.Success) { return $null }
  if ($match.Groups['double'].Success) { return $match.Groups['double'].Value }
  return $match.Groups['single'].Value
}

function Get-BewerbungsfotoTags {
  param([AllowEmptyString()][string]$Html)

  $result = [System.Collections.Generic.List[object]]::new()
  foreach ($match in [regex]::Matches($Html, '(?is)<img\b[^>]*>')) {
    $tag = $match.Value
    $classValue = [string](Get-HtmlAttributeValue -Tag $tag -Name 'class')
    if ($classValue -notmatch '(?:^|\s)bewerbungsfoto(?:\s|$)') { continue }
    $result.Add([pscustomobject][ordered]@{
      Tag = $tag
      Src = [string](Get-HtmlAttributeValue -Tag $tag -Name 'src')
      Alt = [string](Get-HtmlAttributeValue -Tag $tag -Name 'alt')
    }) | Out-Null
  }
  return @($result)
}

function Test-PassfotoEmbedding {
  param(
    [AllowEmptyString()][string]$Html,
    [Parameter(Mandatory)][object]$SourceState
  )

  $tags = @(Get-BewerbungsfotoTags -Html $Html)
  $result = [ordered]@{
    Valid = $false
    Error = $null
    SourceExists = [bool]$SourceState.Exists
    EmbeddedCount = $tags.Count
    SourceSha256 = if ($SourceState.Exists) { [string]$SourceState.Sha256 } else { $null }
    EmbeddedSha256 = $null
  }

  if (-not $SourceState.Exists) {
    if ($tags.Count -ne 0) {
      $result.Error = "Der Lebenslauf enthält ein Bewerbungsfoto, obwohl Private/Daten/Passfoto.png nicht existiert."
      return [pscustomobject]$result
    }
    $result.Valid = $true
    return [pscustomobject]$result
  }

  if ($tags.Count -ne 1) {
    $result.Error = "Bei vorhandenem Private/Daten/Passfoto.png muss der individuelle Lebenslauf genau ein img.bewerbungsfoto enthalten; gefunden: $($tags.Count)."
    return [pscustomobject]$result
  }
  if ([string]::IsNullOrWhiteSpace($tags[0].Src) -or $tags[0].Src -cnotmatch '^data:image/png;base64,(?<payload>[A-Za-z0-9+/=\s]+)$') {
    $result.Error = "Das Bewerbungsfoto muss als eingebettete data:image/png;base64-Ressource vorliegen."
    return [pscustomobject]$result
  }

  try {
    $embeddedBytes = [Convert]::FromBase64String($Matches.payload)
  } catch {
    $result.Error = "Die Base64-Daten des eingebetteten Bewerbungsfotos sind ungültig."
    return [pscustomobject]$result
  }
  $embeddedValidation = Test-PassfotoPngBytes -Bytes $embeddedBytes
  if (-not $embeddedValidation.Valid) {
    $result.Error = "Das eingebettete Bewerbungsfoto ist keine gültige PNG-Datei: $($embeddedValidation.Error)"
    return [pscustomobject]$result
  }

  $embeddedHash = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($embeddedBytes))
  $result.EmbeddedSha256 = $embeddedHash
  if ($embeddedHash -cne [string]$SourceState.Sha256 -or $embeddedBytes.Length -ne [long]$SourceState.ByteCount) {
    $result.Error = "Das eingebettete Bewerbungsfoto stimmt nicht bytegleich mit Private/Daten/Passfoto.png überein."
    return [pscustomobject]$result
  }

  $result.Valid = $true
  return [pscustomobject]$result
}

function Update-PassfotoHtml {
  param(
    [Parameter(Mandatory)][AllowEmptyString()][string]$Html,
    [Parameter(Mandatory)][object]$SourceState
  )

  $pattern = [regex]::new(
    '(?s)(?<start>' + [regex]::Escape($script:PassfotoStartMarker) + ')(?<content>.*?)(?<end>' + [regex]::Escape($script:PassfotoEndMarker) + ')'
  )
  $matches = @($pattern.Matches($Html))
  if ($matches.Count -gt 1) {
    throw "Der Lebenslauf enthält mehr als einen markierten Passfoto-Block."
  }
  if ($matches.Count -eq 0) {
    $current = Test-PassfotoEmbedding -Html $Html -SourceState $SourceState
    if ($current.Valid) { return $Html }
    throw "Der markierte Block '$script:PassfotoStartMarker ... $script:PassfotoEndMarker' fehlt: $($current.Error)"
  }

  $newline = if ($Html.Contains("`r`n")) { "`r`n" } else { "`n" }
  $replacementContent = $newline
  if ($SourceState.Exists) {
    $photoBytes = [System.IO.File]::ReadAllBytes([string]$SourceState.Path)
    $dataUri = "data:image/png;base64,$([Convert]::ToBase64String($photoBytes))"
    $replacementContent = $newline +
      '  <figure class="bewerbungsfoto-rahmen" aria-hidden="true">' + $newline +
      '    <img class="bewerbungsfoto" src="' + $dataUri + '" alt="">' + $newline +
      '  </figure>' + $newline
  }

  $updated = $pattern.Replace($Html, {
    param($match)
    return $match.Groups['start'].Value + $replacementContent + $match.Groups['end'].Value
  }, 1)
  $validation = Test-PassfotoEmbedding -Html $updated -SourceState $SourceState
  if (-not $validation.Valid) {
    throw "Passfoto-Block konnte nicht gültig aktualisiert werden: $($validation.Error)"
  }
  return $updated
}

function Get-PassfotoMarkerContract {
  return [pscustomobject][ordered]@{
    Start = $script:PassfotoStartMarker
    End = $script:PassfotoEndMarker
  }
}

Export-ModuleMember -Function @(
  'Get-PassfotoMarkerContract',
  'Get-PassfotoSourceState',
  'Test-PassfotoEmbedding',
  'Test-PassfotoPngBytes',
  'Update-PassfotoHtml'
)
