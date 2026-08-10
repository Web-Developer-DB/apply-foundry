#requires -Version 7.6
#requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:PathComparison = if ($IsWindows) {
  [System.StringComparison]::OrdinalIgnoreCase
} else {
  [System.StringComparison]::Ordinal
}

function Get-ObjectPropertyValue {
  param(
    [AllowNull()]
    [object]$Object,

    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  if ($null -eq $Object) {
    return $null
  }
  if ($Object -is [System.Collections.IDictionary]) {
    if ($Object.Contains($Name)) {
      return $Object[$Name]
    }
    return $null
  }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return $null
  }
  return $property.Value
}

function Get-CanonicalFileSystemPath {
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Path
  )

  if ([string]::IsNullOrWhiteSpace($Path) -or $Path -match '[\x00-\x1F\x7F]') {
    throw "Dateisystempfad darf weder leer sein noch Steuerzeichen enthalten."
  }
  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $pathRoot = [System.IO.Path]::GetPathRoot($fullPath)
  if ([string]::IsNullOrWhiteSpace($pathRoot)) {
    throw "Dateisystempfad besitzt keinen auflösbaren Root: $Path"
  }

  $currentPath = $pathRoot
  $relativePart = $fullPath.Substring($pathRoot.Length)
  $segments = @($relativePart.Split(
      [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar),
      [System.StringSplitOptions]::RemoveEmptyEntries
    ))

  for ($index = 0; $index -lt $segments.Count; $index++) {
    $nextPath = [System.IO.Path]::Combine($currentPath, $segments[$index])
    try {
      $item = Get-Item -LiteralPath $nextPath -Force -ErrorAction Stop
    } catch [System.Management.Automation.ItemNotFoundException] {
      for ($remaining = $index; $remaining -lt $segments.Count; $remaining++) {
        $currentPath = [System.IO.Path]::Combine($currentPath, $segments[$remaining])
      }
      break
    }

    $resolvedItem = $item
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
      $target = $item.ResolveLinkTarget($true)
      if ($null -eq $target) {
        throw "Verknüpfungsziel konnte nicht sicher aufgelöst werden: $nextPath"
      }
      $resolvedItem = $target
      $currentPath = $target.FullName
    } else {
      $currentPath = $item.FullName
    }
    if ($index -lt ($segments.Count - 1) -and
        ($resolvedItem.Attributes -band [System.IO.FileAttributes]::Directory) -eq 0) {
      throw "Ein bestehender Datei-Pfad maskiert einen benötigten Ordner: $nextPath"
    }
  }

  return [System.IO.Path]::GetFullPath($currentPath)
}

function Get-ComparableFileSystemPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $canonicalPath = Get-CanonicalFileSystemPath -Path $Path
  $pathRoot = [System.IO.Path]::GetPathRoot($canonicalPath)
  if ([string]::Equals($canonicalPath, $pathRoot, $script:PathComparison)) {
    return $canonicalPath
  }
  return $canonicalPath.TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
  )
}

function Assert-PortableRelativePath {
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RelativePath,

    [string]$FieldName = "Relativpfad"
  )

  if ($RelativePath -cne $RelativePath.Trim()) {
    throw "$FieldName darf keine führenden oder abschließenden Leerzeichen enthalten."
  }
  if ([System.IO.Path]::IsPathRooted($RelativePath) -or
      [System.IO.Path]::IsPathFullyQualified($RelativePath) -or
      $RelativePath -match '^[A-Za-z]:' -or
      $RelativePath.StartsWith('/') -or
      $RelativePath.StartsWith('\')) {
    throw "$FieldName muss relativ sein."
  }
  if ($RelativePath.Contains('\')) {
    throw "$FieldName muss ausschließlich '/' als Pfadtrenner verwenden."
  }
  if ($RelativePath -match '[\x00-\x1F\x7F]') {
    throw "$FieldName darf keine Steuerzeichen enthalten."
  }

  $segments = @($RelativePath.Split('/'))
  if ($segments.Count -eq 0) {
    throw "$FieldName darf nicht leer sein."
  }
  foreach ($segment in $segments) {
    if ([string]::IsNullOrWhiteSpace($segment) -or $segment -eq '.' -or $segment -eq '..') {
      throw "$FieldName enthält ein unzulässiges leeres, '.'- oder '..'-Segment."
    }
    if ($segment -match '[<>:"\\|?*]' -or $segment.EndsWith('.') -or $segment.EndsWith(' ')) {
      throw "$FieldName enthält ein nicht portables Pfadsegment: $segment"
    }
    $baseName = $segment.Split('.')[0]
    if ($baseName -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') {
      throw "$FieldName enthält einen unter Windows reservierten Namen: $segment"
    }
  }

  return $RelativePath
}

function Join-PortableRelativePath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Root,

    [Parameter(Mandatory = $true)]
    [string]$RelativePath
  )

  $validatedPath = Assert-PortableRelativePath -RelativePath $RelativePath
  $result = $Root
  foreach ($segment in $validatedPath.Split('/')) {
    $result = Join-Path -Path $result -ChildPath $segment
  }
  return [System.IO.Path]::GetFullPath($result)
}

function Test-BewerbungsPathWithinRoot {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$Root,

    [switch]$AllowRoot
  )

  try {
    $candidatePath = Get-ComparableFileSystemPath -Path $Path
    $rootPath = Get-ComparableFileSystemPath -Path $Root
    if ([string]::Equals($candidatePath, $rootPath, $script:PathComparison)) {
      return [bool]$AllowRoot
    }
    $rootPrefix = $rootPath + [System.IO.Path]::DirectorySeparatorChar
    return $candidatePath.StartsWith($rootPrefix, $script:PathComparison)
  } catch {
    return $false
  }
}

function Resolve-BewerbungsRelativePath {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Root,

    [Parameter(Mandatory = $true)]
    [string]$RelativePath
  )

  $canonicalRoot = Get-ComparableFileSystemPath -Path $Root
  if ((Test-Path -LiteralPath $canonicalRoot) -and
      -not (Test-Path -LiteralPath $canonicalRoot -PathType Container)) {
    throw "Pfad-Root existiert, ist aber kein Ordner: $canonicalRoot"
  }
  $candidatePath = Join-PortableRelativePath -Root $canonicalRoot -RelativePath $RelativePath
  $canonicalCandidate = Get-ComparableFileSystemPath -Path $candidatePath
  if (-not (Test-BewerbungsPathWithinRoot -Path $canonicalCandidate -Root $canonicalRoot)) {
    throw "Relativpfad verlässt seinen vorgesehenen Root: $RelativePath"
  }
  # Die kanonische Form dient ausschließlich der Containmentprüfung. Der
  # zurückgegebene Vertragspfad bleibt lexikalisch an den Schema-5-Relativpfad
  # gebunden, damit ein interner Link-Alias nicht als anderer Auftrag erscheint.
  return [System.IO.Path]::GetFullPath($candidatePath)
}

function ConvertTo-BewerbungsRelativePath {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$Root
  )

  $canonicalRoot = Get-ComparableFileSystemPath -Path $Root
  $canonicalPath = Get-ComparableFileSystemPath -Path $Path
  if (-not (Test-BewerbungsPathWithinRoot -Path $canonicalPath -Root $canonicalRoot)) {
    throw "Pfad liegt nicht innerhalb des vorgesehenen Roots: $Path"
  }
  $relativePath = [System.IO.Path]::GetRelativePath($canonicalRoot, $canonicalPath).Replace('\', '/')
  return Assert-PortableRelativePath -RelativePath $relativePath
}

function ConvertTo-BewerbungsSlug {
  [CmdletBinding()]
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
  $slug = ($slug -replace "[^A-Za-z0-9]+", "-").Trim('-')
  if ([string]::IsNullOrWhiteSpace($slug)) {
    $slug = "Unbekannt"
  }
  [void](Assert-PortableRelativePath -RelativePath $slug -FieldName "Slug")
  return $slug
}

function Assert-OrderDate {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Datum
  )

  $parsedDate = [datetime]::MinValue
  $dateIsValid = [datetime]::TryParseExact(
    $Datum,
    "yyyy-MM-dd",
    [System.Globalization.CultureInfo]::InvariantCulture,
    [System.Globalization.DateTimeStyles]::None,
    [ref]$parsedDate
  )
  if (-not $dateIsValid) {
    throw "Auftragsdatum muss ein echtes Kalenderdatum im Format YYYY-MM-DD sein."
  }
}

function New-BewerbungsauftragPathSet {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$BewerbungenRoot,

    [Parameter(Mandatory = $true)]
    [string]$FirmaSlug,

    [Parameter(Mandatory = $true)]
    [string]$RolleSlug,

    [Parameter(Mandatory = $true)]
    [string]$Datum
  )

  [void](Assert-PortableRelativePath -RelativePath $FirmaSlug -FieldName "firmaSlug")
  [void](Assert-PortableRelativePath -RelativePath $RolleSlug -FieldName "rolleSlug")
  if ($FirmaSlug.Contains('/') -or $RolleSlug.Contains('/')) {
    throw "Firma- und Rolle-Slug müssen jeweils aus genau einem Pfadsegment bestehen."
  }
  Assert-OrderDate -Datum $Datum

  $rootPath = Get-ComparableFileSystemPath -Path $BewerbungenRoot
  if ((Test-Path -LiteralPath $rootPath) -and
      -not (Test-Path -LiteralPath $rootPath -PathType Container)) {
    throw "BewerbungenRoot existiert, ist aber kein Ordner: $rootPath"
  }

  $jobSegment = "$Datum--$RolleSlug"
  $targetRelative = "$FirmaSlug/$jobSegment"
  $workRelative = "$FirmaSlug/_Arbeitsdateien/$jobSegment"
  $candidateRelative = "$workRelative/Kandidat"
  $targetPath = Resolve-BewerbungsRelativePath -Root $rootPath -RelativePath $targetRelative
  $workPath = Resolve-BewerbungsRelativePath -Root $rootPath -RelativePath $workRelative
  $candidatePath = Resolve-BewerbungsRelativePath -Root $rootPath -RelativePath $candidateRelative

  return [pscustomobject][ordered]@{
    SchemaVersion = 5
    PfadModus = "relativ_zu_bewerbungen_root"
    BewerbungenRoot = $rootPath
    ZielOrdner = $targetPath
    ArbeitsOrdner = $workPath
    KandidatOrdner = $candidatePath
    ZielOrdnerRelativ = $targetRelative
    ArbeitsOrdnerRelativ = $workRelative
    KandidatOrdnerRelativ = $candidateRelative
  }
}

function Get-BewerbungsauftragSchemaVersion {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [object]$Auftrag
  )

  $schemaValue = Get-ObjectPropertyValue -Object $Auftrag -Name "schemaVersion"
  $isInteger = $schemaValue -is [byte] -or
    $schemaValue -is [sbyte] -or
    $schemaValue -is [int16] -or
    $schemaValue -is [uint16] -or
    $schemaValue -is [int32] -or
    $schemaValue -is [uint32] -or
    $schemaValue -is [int64] -or
    $schemaValue -is [uint64]
  if (-not $isInteger) {
    throw "Bewerbungsauftrag enthält keine ganzzahlige schemaVersion."
  }
  $schemaVersion = [int64]$schemaValue
  if ($schemaVersion -lt 1 -or $schemaVersion -gt 5) {
    throw "Bewerbungsauftrag verwendet keine unterstützte schemaVersion 1 bis 5."
  }
  return [int]$schemaVersion
}

function Resolve-BewerbungsauftragPathSet {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [object]$Auftrag,

    [string]$BewerbungenRoot,

    [string]$Arbeitsordner
  )

  $schemaVersion = Get-BewerbungsauftragSchemaVersion -Auftrag $Auftrag
  if ($schemaVersion -le 4) {
    $targetValue = [string](Get-ObjectPropertyValue -Object $Auftrag -Name "zielOrdner")
    $workValue = [string](Get-ObjectPropertyValue -Object $Auftrag -Name "arbeitsOrdner")
    $candidateValue = [string](Get-ObjectPropertyValue -Object $Auftrag -Name "kandidatOrdner")
    if ([string]::IsNullOrWhiteSpace($targetValue) -or
        [string]::IsNullOrWhiteSpace($workValue) -or
        [string]::IsNullOrWhiteSpace($candidateValue)) {
      throw "Legacy-Bewerbungsauftrag enthält keine vollständigen Auftragspfade."
    }
    $targetPath = Get-ComparableFileSystemPath -Path $targetValue
    $workPath = Get-ComparableFileSystemPath -Path $workValue
    $candidatePath = Get-ComparableFileSystemPath -Path $candidateValue
    if (-not [string]::IsNullOrWhiteSpace($Arbeitsordner)) {
      $providedWorkPath = Get-ComparableFileSystemPath -Path $Arbeitsordner
      if (-not [string]::Equals($providedWorkPath, $workPath, $script:PathComparison)) {
        throw "Übergebener Arbeitsordner stimmt nicht mit dem Legacy-Auftrag überein."
      }
    }
    $rootPath = $null
    if (-not [string]::IsNullOrWhiteSpace($BewerbungenRoot)) {
      $rootPath = Get-ComparableFileSystemPath -Path $BewerbungenRoot
      foreach ($legacyPath in @($targetPath, $workPath, $candidatePath)) {
        if (-not (Test-BewerbungsPathWithinRoot -Path $legacyPath -Root $rootPath)) {
          throw "Legacy-Auftragspfad liegt außerhalb von BewerbungenRoot: $legacyPath"
        }
      }
    }
    return [pscustomobject][ordered]@{
      SchemaVersion = $schemaVersion
      PfadModus = "legacy_gespeichert"
      BewerbungenRoot = $rootPath
      ZielOrdner = $targetPath
      ArbeitsOrdner = $workPath
      KandidatOrdner = $candidatePath
      ZielOrdnerRelativ = $null
      ArbeitsOrdnerRelativ = $null
      KandidatOrdnerRelativ = $null
    }
  }

  $pathMode = [string](Get-ObjectPropertyValue -Object $Auftrag -Name "pfadModus")
  if ($pathMode -cne "relativ_zu_bewerbungen_root") {
    throw "Schema-5-Auftrag verwendet keinen unterstützten pfadModus."
  }

  $company = [string](Get-ObjectPropertyValue -Object $Auftrag -Name "firma")
  $role = [string](Get-ObjectPropertyValue -Object $Auftrag -Name "rolle")
  $companySlug = [string](Get-ObjectPropertyValue -Object $Auftrag -Name "firmaSlug")
  $roleSlug = [string](Get-ObjectPropertyValue -Object $Auftrag -Name "rolleSlug")
  $date = [string](Get-ObjectPropertyValue -Object $Auftrag -Name "datum")
  if ([string]::IsNullOrWhiteSpace($company) -or [string]::IsNullOrWhiteSpace($role)) {
    throw "Schema-5-Auftrag enthält keine vollständige Firma oder Rolle."
  }
  if ($companySlug -cne (ConvertTo-BewerbungsSlug -Value $company) -or
      $roleSlug -cne (ConvertTo-BewerbungsSlug -Value $role)) {
    throw "Schema-5-Auftrag enthält Slugs, die nicht zu Firma oder Rolle passen."
  }
  Assert-OrderDate -Datum $date

  $targetRelative = Assert-PortableRelativePath -RelativePath ([string](Get-ObjectPropertyValue -Object $Auftrag -Name "zielOrdner")) -FieldName "zielOrdner"
  $workRelative = Assert-PortableRelativePath -RelativePath ([string](Get-ObjectPropertyValue -Object $Auftrag -Name "arbeitsOrdner")) -FieldName "arbeitsOrdner"
  $candidateRelative = Assert-PortableRelativePath -RelativePath ([string](Get-ObjectPropertyValue -Object $Auftrag -Name "kandidatOrdner")) -FieldName "kandidatOrdner"
  $expectedJobSegment = "$date--$roleSlug"
  $expectedTargetRelative = "$companySlug/$expectedJobSegment"
  $expectedWorkRelative = "$companySlug/_Arbeitsdateien/$expectedJobSegment"
  $expectedCandidateRelative = "$expectedWorkRelative/Kandidat"
  if ($targetRelative -cne $expectedTargetRelative -or
      $workRelative -cne $expectedWorkRelative -or
      $candidateRelative -cne $expectedCandidateRelative) {
    throw "Schema-5-Auftragspfade stimmen nicht mit Firma, Rolle, Datum und Slugs überein."
  }

  $inferredRoot = $null
  $providedWorkPath = $null
  if (-not [string]::IsNullOrWhiteSpace($Arbeitsordner)) {
    $providedWorkLexical = [System.IO.Path]::GetFullPath($Arbeitsordner).TrimEnd(
      [System.IO.Path]::DirectorySeparatorChar,
      [System.IO.Path]::AltDirectorySeparatorChar
    )
    $jobDirectory = [System.IO.Path]::GetFileName($providedWorkLexical)
    $workFilesDirectory = [System.IO.Path]::GetDirectoryName($providedWorkLexical)
    $workFilesName = [System.IO.Path]::GetFileName($workFilesDirectory)
    $companyDirectory = [System.IO.Path]::GetDirectoryName($workFilesDirectory)
    $companyDirectoryName = [System.IO.Path]::GetFileName($companyDirectory)
    $inferredRootValue = [System.IO.Path]::GetDirectoryName($companyDirectory)
    if (-not [string]::Equals($jobDirectory, $expectedJobSegment, $script:PathComparison) -or
        -not [string]::Equals($workFilesName, "_Arbeitsdateien", $script:PathComparison) -or
        -not [string]::Equals($companyDirectoryName, $companySlug, $script:PathComparison) -or
        [string]::IsNullOrWhiteSpace($inferredRootValue)) {
      throw "Übergebener Arbeitsordner besitzt nicht die erwartete Schema-5-Struktur."
    }
    $inferredRoot = Get-ComparableFileSystemPath -Path $inferredRootValue
    $providedWorkPath = Get-ComparableFileSystemPath -Path $providedWorkLexical
  }

  $resolvedRoot = $null
  if (-not [string]::IsNullOrWhiteSpace($BewerbungenRoot)) {
    $resolvedRoot = Get-ComparableFileSystemPath -Path $BewerbungenRoot
  } elseif ($null -ne $inferredRoot) {
    $resolvedRoot = $inferredRoot
  } else {
    throw "Schema-5-Pfadauflösung erfordert BewerbungenRoot oder Arbeitsordner."
  }
  if ($null -ne $inferredRoot -and
      -not [string]::Equals($resolvedRoot, $inferredRoot, $script:PathComparison)) {
    throw "BewerbungenRoot und der aus Arbeitsordner abgeleitete Root stimmen nicht überein."
  }

  $pathSet = New-BewerbungsauftragPathSet `
    -BewerbungenRoot $resolvedRoot `
    -FirmaSlug $companySlug `
    -RolleSlug $roleSlug `
    -Datum $date
  if ($null -ne $providedWorkPath -and
      -not [string]::Equals($pathSet.ArbeitsOrdner, $providedWorkPath, $script:PathComparison)) {
    throw "Übergebener Arbeitsordner stimmt nicht mit den rekonstruierten Schema-5-Pfaden überein."
  }
  return $pathSet
}

Export-ModuleMember -Function @(
  "ConvertTo-BewerbungsRelativePath",
  "ConvertTo-BewerbungsSlug",
  "Get-BewerbungsauftragSchemaVersion",
  "New-BewerbungsauftragPathSet",
  "Resolve-BewerbungsauftragPathSet",
  "Resolve-BewerbungsRelativePath",
  "Test-BewerbungsPathWithinRoot"
)
