[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Arbeitsordner,

  [ValidateSet("auto", "chrome", "edge")]
  [string]$Browser = "auto",

  [string]$StammdatenPath = (Join-Path -Path $PSScriptRoot -ChildPath "..\Private\Daten\01_PERSOENLICHE_DATEN.md"),

  [string]$ProfilPath = (Join-Path -Path $PSScriptRoot -ChildPath "..\Private\Daten\02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md"),

  [switch]$Veroeffentlichen,

  [switch]$VisuellGeprueft,

  [string]$VisuelleFreigabeNotiz,

  [switch]$Ersetzen,

  [ValidateRange(1, 600)]
  [int]$TimeoutSeconds = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

trap {
  Write-Host "[FEHLER] Unerwarteter Finalisierungsfehler: $($_.Exception.Message)" -ForegroundColor Red
  if (-not [string]::IsNullOrWhiteSpace($_.InvocationInfo.PositionMessage)) {
    Write-Host $_.InvocationInfo.PositionMessage
  }
  if (-not [string]::IsNullOrWhiteSpace($_.ScriptStackTrace)) {
    Write-Host $_.ScriptStackTrace
  }
  exit 1
}

function Stop-Finalization {
  param([string]$Message)
  Write-Host "[FEHLER] $Message" -ForegroundColor Red
  exit 1
}

function Add-Info {
  param([string]$Message)
  Write-Host "[INFO] $Message"
}

function Add-Ok {
  param([string]$Message)
  Write-Host "[OK] $Message" -ForegroundColor Green
}

$script:PathComparison = if ($env:OS -eq "Windows_NT") { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
$script:PathComparer = if ($env:OS -eq "Windows_NT") { [System.StringComparer]::OrdinalIgnoreCase } else { [System.StringComparer]::Ordinal }

function Test-PathEqual {
  param([string]$Left, [string]$Right)
  if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) { return $false }
  return [string]::Equals([System.IO.Path]::GetFullPath($Left), [System.IO.Path]::GetFullPath($Right), $script:PathComparison)
}

function Test-IsSafeChildPath {
  param([string]$Candidate, [string]$Root)
  $candidateFull = [System.IO.Path]::GetFullPath($Candidate).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  return $candidateFull.StartsWith($rootFull + [System.IO.Path]::DirectorySeparatorChar, $script:PathComparison)
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

function Test-DocumentScopeMatches {
  param([object]$Actual, [object]$Expected)
  if ($null -eq $Actual -or $null -eq $Expected) { return $false }
  return (
    [string](Get-JsonProperty -Object $Actual -Name "lebenslauf") -eq [string]$Expected.lebenslauf -and
    (Get-JsonProperty -Object $Actual -Name "anschreiben") -is [bool] -and
    (Get-JsonProperty -Object $Actual -Name "emailNachricht") -is [bool] -and
    [bool](Get-JsonProperty -Object $Actual -Name "anschreiben") -eq [bool]$Expected.anschreiben -and
    [bool](Get-JsonProperty -Object $Actual -Name "emailNachricht") -eq [bool]$Expected.emailNachricht
  )
}

function Get-DocumentScope {
  param([object]$Auftrag)

  $scope = [ordered]@{
    lebenslauf = "individuell"
    anschreiben = $true
    emailNachricht = $true
  }
  $schemaValue = Get-JsonProperty -Object $Auftrag -Name "schemaVersion"
  if ($schemaValue -isnot [int] -and $schemaValue -isnot [long]) {
    throw "Bewerbungsauftrag enthält keine ganzzahlige schemaVersion."
  }
  $schema = [int]$schemaValue
  $configured = Get-JsonProperty -Object $Auftrag -Name "dokumentumfang"
  if ($schema -eq 4) {
    if ($null -eq $configured) { throw "Bewerbungsauftrag mit schemaVersion 4 enthält keinen dokumentumfang." }
    $cvKind = [string](Get-JsonProperty -Object $configured -Name "lebenslauf")
    $letterValue = Get-JsonProperty -Object $configured -Name "anschreiben"
    $emailValue = Get-JsonProperty -Object $configured -Name "emailNachricht"
    if ($cvKind -notin @("individuell", "universal_unveraendert", "nicht_enthalten") -or
        $letterValue -isnot [bool] -or $emailValue -isnot [bool]) {
      throw "Bewerbungsauftrag enthält einen ungültigen oder nicht typisierten dokumentumfang."
    }
    if ($cvKind -eq "nicht_enthalten" -and -not [bool]$letterValue -and -not [bool]$emailValue) {
      throw "Bewerbungsauftrag wählt kein Dokument aus."
    }
    $scope.lebenslauf = $cvKind
    $scope.anschreiben = [bool]$letterValue
    $scope.emailNachricht = [bool]$emailValue
  } elseif ($schema -lt 1 -or $schema -gt 4) {
    throw "Bewerbungsauftrag verwendet keine unterstützte schemaVersion 1 bis 4."
  } elseif ([string](Get-JsonProperty -Object $Auftrag -Name "dokumentmodus") -eq "anschreiben_mit_universalem_lebenslauf") {
    $scope.lebenslauf = "universal_unveraendert"
  }
  return $scope
}

function Write-NotRequiredReport {
  param([string]$Path, [string]$Kind)
  $parent = Split-Path -Path $Path -Parent
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -Path $parent -ItemType Directory -Force | Out-Null
  }
  $report = [ordered]@{
    schemaVersion = 1
    checkedAtUtc = [datetime]::UtcNow.ToString("o")
    status = "nicht_erforderlich"
    kind = $Kind
    reason = "Der gewählte Dokumentumfang enthält kein HTML-/PDF-Dokument."
    results = @()
  }
  Set-Content -LiteralPath $Path -Encoding UTF8 -Value ($report | ConvertTo-Json -Depth 5)
}

function Invoke-ChildTool {
  param([string]$ScriptPath, [string[]]$Arguments, [switch]$ThrowOnFailure)

  if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
    if ($ThrowOnFailure) { throw "Werkzeug fehlt: $ScriptPath" }
    Stop-Finalization -Message "Werkzeug fehlt: $ScriptPath"
  }
  $powerShellExe = (Get-Process -Id $PID).Path
  $output = & $powerShellExe -NoProfile -File $ScriptPath @Arguments 2>&1
  foreach ($line in @($output)) { Write-Host $line }
  if ($LASTEXITCODE -ne 0) {
    if ($ThrowOnFailure) { throw "Werkzeuglauf fehlgeschlagen: $([System.IO.Path]::GetFileName($ScriptPath))" }
    Stop-Finalization -Message "Werkzeuglauf fehlgeschlagen: $([System.IO.Path]::GetFileName($ScriptPath))"
  }
}

function Update-TokenReportNonBlocking {
  param(
    [string]$ScriptPath,
    [string]$WorkFolder,
    [string]$ReportPath
  )

  $reference = [ordered]@{
    path = $ReportPath
    availability = "unavailable"
    purpose = "Diagnose- und Kostenartefakt; kein Qualitätsnachweis"
    blocksFinalization = $false
    includedInManifest = $false
  }
  if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
    Write-Host "[WARNUNG] Tokenbericht-Werkzeug fehlt; die Finalisierung wird dadurch nicht blockiert: $ScriptPath" -ForegroundColor Yellow
    return $reference
  }

  try {
    $powerShellExe = (Get-Process -Id $PID).Path
    $output = & $powerShellExe -NoProfile -File $ScriptPath -Arbeitsordner $WorkFolder -Messbereich "technische_vorbereitung" 2>&1
    foreach ($line in @($output)) { Write-Host $line }
    if ($LASTEXITCODE -ne 0) {
      Write-Host "[WARNUNG] Tokenbericht konnte nicht aktualisiert werden; die Finalisierung wird fortgesetzt." -ForegroundColor Yellow
      return $reference
    }
    if (Test-Path -LiteralPath $ReportPath -PathType Leaf) {
      $tokenReport = Get-Content -LiteralPath $ReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
      $reference.availability = [string](Get-JsonProperty -Object $tokenReport -Name "availability")
    }
  } catch {
    Write-Host "[WARNUNG] Tokenbericht konnte nicht gelesen werden; die Finalisierung wird fortgesetzt: $($_.Exception.Message)" -ForegroundColor Yellow
  }
  return $reference
}

function Update-TechnicalSection {
  param(
    [string]$QualityPath,
    [ValidateSet("vorbereitet", "bestaetigt")]
    [string]$State,
    [string]$LayoutReportPath,
    [string]$PdfReportPath,
    [string]$AtsReportPath,
    [array]$LayoutWarnings,
    [string]$VisualApprovalNote,
    [int]$HtmlDocumentCount
  )

  $reviewLine = if ($State -eq "bestaetigt" -and $HtmlDocumentCount -gt 0) {
    $noteSuffix = if ([string]::IsNullOrWhiteSpace($VisualApprovalNote)) { "" } else { " Freigabenotiz: $VisualApprovalNote" }
    "- Visuelle Prüfung: bestätigt; jede gerenderte A4-Seite wurde auf Überlappungen, abgeschnittene Inhalte und problematische Leerflächen geprüft.$noteSuffix"
  } elseif ($State -eq "bestaetigt") {
    "- Persönliche Textprüfung: bestätigt; die ausgewählte E-Mail-Nachricht wurde vollständig inhaltlich geprüft."
  } elseif ($HtmlDocumentCount -gt 0) {
    "- Visuelle Prüfung: noch nicht bestätigt; die Veröffentlichung bleibt bis zur Sichtprüfung gesperrt."
  } else {
    "- Persönliche Textprüfung: noch nicht bestätigt; die Veröffentlichung bleibt bis zur Prüfung der ausgewählten E-Mail-Nachricht gesperrt."
  }
  $warningLine = if (@($LayoutWarnings).Count -gt 0) {
    "- Automatische Layoutwarnungen: " + (@($LayoutWarnings) -join " | ")
  } else {
    "- Automatische Layoutwarnungen: keine."
  }
  $documentChecks = if ($HtmlDocumentCount -gt 0) {
    @"
- Chrome-/Edge-Layoutcheck: für jede explizite A4-Seite der ausgewählten HTML-Dokumente wurde ein frischer Screenshot mit HTML-Hashnachweis erzeugt.
- PDF-Export: $HtmlDocumentCount ausgewählte(s) HTML-Dokument(e) wurden frisch als PDF erzeugt und auf Dateistruktur, Seitenzahl und DIN-A4-MediaBox geprüft.
- ATS-Prüfung: Unicode-Textschicht, Pflichttexte, Textabdeckung und grundlegende Lesereihenfolge wurden für die erzeugten PDFs geprüft.
"@
  } else {
    "- Layoutcheck, PDF-Export und PDF-ATS-Prüfung: laut Dokumentumfang nicht erforderlich; die persönliche Prüfung betrifft die ausgewählten Textdateien."
  }
  $section = @"
## Technischer Prüfbericht (automatisch)

- Stammdatenprüfung, statischer Strukturcheck und fachlicher Inhaltsabgleich: erfolgreich.
$documentChecks
$warningLine
$reviewLine
- Maschinenlesbare Nachweise: Layoutcheck-, PDF-Export- und ATS-Prüfbericht im zugehörigen privaten Arbeitsordner.
"@

  $text = Get-Content -LiteralPath $QualityPath -Raw -Encoding UTF8
  $pattern = '(?ms)^## Technischer Prüfbericht \(automatisch\)\s*.*?(?=^## |\z)'
  if ([regex]::IsMatch($text, $pattern)) {
    $updated = [regex]::Replace($text, $pattern, $section.TrimEnd() + "`r`n`r`n")
  } else {
    $updated = $text.TrimEnd() + "`r`n`r`n" + $section.TrimEnd() + "`r`n"
  }
  Set-Content -LiteralPath $QualityPath -Encoding UTF8 -Value $updated
}

function Get-ArtifactRecord {
  param([System.IO.FileInfo]$File)
  return [ordered]@{
    name = $File.Name
    path = $File.FullName
    bytes = $File.Length
    sha256 = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash
  }
}

function Get-ReportArtifacts {
  param([string]$CandidateFolder, [string]$LayoutFolder)
  $html = @(Get-ChildItem -LiteralPath $CandidateFolder -File -Filter "*.html" | Sort-Object Name | ForEach-Object { Get-ArtifactRecord -File $_ })
  $pdf = @(Get-ChildItem -LiteralPath $CandidateFolder -File -Filter "*.pdf" | Sort-Object Name | ForEach-Object { Get-ArtifactRecord -File $_ })
  $screenshots = @(Get-ChildItem -LiteralPath $LayoutFolder -File -Filter "*.png" | Sort-Object Name | ForEach-Object { Get-ArtifactRecord -File $_ })
  $candidate = @(Get-ChildItem -LiteralPath $CandidateFolder -File | Sort-Object Name | ForEach-Object { Get-ArtifactRecord -File $_ })
  return [ordered]@{ html = $html; pdf = $pdf; screenshots = $screenshots; candidate = $candidate }
}

function Get-ExpectedScreenshotCount {
  param([string]$CandidateFolder)
  $count = 0
  foreach ($html in Get-ChildItem -LiteralPath $CandidateFolder -File -Filter "*.html") {
    $text = Get-Content -LiteralPath $html.FullName -Raw -Encoding UTF8
    $count += [regex]::Matches($text, '(?is)<main\b[^>]*class\s*=\s*["''][^"'']*\bpage\b[^"'']*["'']').Count
  }
  return $count
}

function Get-LayoutWarnings {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
  $layout = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
  return @($layout.results | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.densityWarning) } | ForEach-Object {
    "$($_.htmlFile), Seite $($_.pageNumber) von $($_.pageCount): $($_.densityWarning)"
  })
}

function New-PublicationManifest {
  param([string]$Root, [object]$Auftrag, [object]$SourceInputs)
  $records = @()
  foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object { $_.Name -ne "Manifest.json" } | Sort-Object FullName) {
    $relative = [System.IO.Path]::GetRelativePath($Root, $file.FullName).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
    $records += [ordered]@{
      path = $relative
      bytes = $file.Length
      sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
  }
  $manifest = [ordered]@{
    schemaVersion = 1
    createdAtUtc = [datetime]::UtcNow.ToString("o")
    firma = [string](Get-JsonProperty -Object $Auftrag -Name "firma")
    rolle = [string](Get-JsonProperty -Object $Auftrag -Name "rolle")
    dokumentumfang = Get-DocumentScope -Auftrag $Auftrag
    struktur = [ordered]@{
      versand = "nur laut Dokumentumfang ausgewählte PDF-Anlagen und E-Mail-Nachricht"
      intern = "HTML-Quellen, Analyse und Prüfdokumente"
    }
    sourceInputs = [ordered]@{}
    files = $records
  }
  if ($null -ne $SourceInputs) {
    foreach ($sourceProperty in $SourceInputs.PSObject.Properties) {
      $sourceRecord = $sourceProperty.Value
      $manifest.sourceInputs[$sourceProperty.Name] = [ordered]@{
        name = [System.IO.Path]::GetFileName([string](Get-JsonProperty -Object $sourceRecord -Name "path"))
        sha256 = [string](Get-JsonProperty -Object $sourceRecord -Name "sha256")
      }
    }
  }
  $manifestPath = Join-Path -Path $Root -ChildPath "Manifest.json"
  Set-Content -LiteralPath $manifestPath -Encoding UTF8 -Value ($manifest | ConvertTo-Json -Depth 8)
  return $manifestPath
}

function Test-ArtifactSetUnchanged {
  param([array]$Records)
  foreach ($record in $Records) {
    $path = [string](Get-JsonProperty -Object $record -Name "path")
    $expectedHash = [string](Get-JsonProperty -Object $record -Name "sha256")
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
      Stop-Finalization -Message "Prüfartefakt fehlt seit der Vorbereitung: $path"
    }
    $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($actualHash -ne $expectedHash) {
      Stop-Finalization -Message "Prüfartefakt wurde nach der Vorbereitung verändert; erneute Vorbereitung erforderlich: $path"
    }
  }
}

function Test-ArtifactSetExact {
  param([array]$Records, [string]$Folder, [string]$Filter = "*")
  Test-ArtifactSetUnchanged -Records $Records
  $recordPaths = @($Records | ForEach-Object { [System.IO.Path]::GetFullPath([string](Get-JsonProperty -Object $_ -Name "path")) })
  $currentPaths = @(Get-ChildItem -LiteralPath $Folder -File -Filter $Filter | ForEach-Object { [System.IO.Path]::GetFullPath($_.FullName) })
  if ($recordPaths.Count -ne $currentPaths.Count) {
    Stop-Finalization -Message "Artefaktmenge wurde nach der Vorbereitung verändert: $Folder ($($recordPaths.Count) erwartet, $($currentPaths.Count) gefunden)."
  }
  $recordPathSet = New-Object 'System.Collections.Generic.HashSet[string]' ($script:PathComparer)
  foreach ($recordPath in $recordPaths) {
    if (-not $recordPathSet.Add($recordPath)) {
      Stop-Finalization -Message "Finalisierungsbericht enthält einen doppelten Artefaktpfad: $recordPath"
    }
  }
  foreach ($currentPath in $currentPaths) {
    if (-not $recordPathSet.Contains($currentPath)) {
      Stop-Finalization -Message "Neues oder nicht geprüftes Artefakt seit der Vorbereitung gefunden: $currentPath"
    }
  }
}

function Test-IntegerValue {
  param([object]$Value, [int]$Minimum = [int]::MinValue)
  return (($Value -is [int] -or $Value -is [long]) -and [long]$Value -ge $Minimum)
}

function Get-SingleArtifactRecord {
  param([array]$Records, [string]$Name, [string]$Context)
  $matches = @($Records | Where-Object { [string](Get-JsonProperty -Object $_ -Name "name") -ceq $Name })
  if ($matches.Count -ne 1) {
    Stop-Finalization -Message "$Context verweist nicht eindeutig auf das vorbereitete Artefakt: $Name"
  }
  return $matches[0]
}

function Test-PngStructure {
  param([string]$Path)
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $signature = [byte[]](137, 80, 78, 71, 13, 10, 26, 10)
  if ($bytes.Length -lt 24) {
    Stop-Finalization -Message "Layoutnachweis ist keine vollständige PNG-Datei: $Path"
  }
  for ($index = 0; $index -lt $signature.Length; $index++) {
    if ($bytes[$index] -ne $signature[$index]) {
      Stop-Finalization -Message "Layoutnachweis besitzt keine gültige PNG-Signatur: $Path"
    }
  }
  if ([System.Text.Encoding]::ASCII.GetString($bytes, 12, 4) -cne "IHDR") {
    Stop-Finalization -Message "Layoutnachweis enthält keinen PNG-IHDR-Block: $Path"
  }
  [uint32]$width = ([uint32]$bytes[16] -shl 24) -bor ([uint32]$bytes[17] -shl 16) -bor ([uint32]$bytes[18] -shl 8) -bor [uint32]$bytes[19]
  [uint32]$height = ([uint32]$bytes[20] -shl 24) -bor ([uint32]$bytes[21] -shl 16) -bor ([uint32]$bytes[22] -shl 8) -bor [uint32]$bytes[23]
  if ($width -lt 1 -or $height -lt 1) {
    Stop-Finalization -Message "Layoutnachweis enthält ungültige PNG-Abmessungen: $Path"
  }
}

function Test-TechnicalReportContracts {
  param(
    [string]$LayoutReportPath,
    [string]$PdfReportPath,
    [string]$AtsReportPath,
    [int]$ExpectedHtmlCount,
    [array]$HtmlRecords,
    [array]$PdfRecords,
    [array]$ScreenshotRecords,
    [string]$CandidateFolder
  )

  try {
    $layout = Get-Content -LiteralPath $LayoutReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $pdf = Get-Content -LiteralPath $PdfReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $ats = Get-Content -LiteralPath $AtsReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
  } catch {
    Stop-Finalization -Message "Technischer Prüfbericht ist kein gültiges JSON: $($_.Exception.Message)"
  }

  if ($ExpectedHtmlCount -eq 0) {
    $notRequiredReports = @(
      [pscustomobject]@{ Name = "Layoutbericht"; Value = $layout; Kind = "layoutcheck" },
      [pscustomobject]@{ Name = "PDF-Bericht"; Value = $pdf; Kind = "pdf_export" },
      [pscustomobject]@{ Name = "ATS-Bericht"; Value = $ats; Kind = "ats_pdf" }
    )
    foreach ($entry in $notRequiredReports) {
      $schema = Get-JsonProperty -Object $entry.Value -Name "schemaVersion"
      if (-not (Test-IntegerValue -Value $schema -Minimum 1) -or [int]$schema -ne 1 -or
          [string](Get-JsonProperty -Object $entry.Value -Name "status") -cne "nicht_erforderlich" -or
          [string](Get-JsonProperty -Object $entry.Value -Name "kind") -cne $entry.Kind -or
          @(Get-JsonProperty -Object $entry.Value -Name "results").Count -ne 0) {
        Stop-Finalization -Message "$($entry.Name) bildet den nicht erforderlichen HTML-/PDF-Schritt nicht korrekt ab."
      }
    }
    return
  }

  $layoutSchema = Get-JsonProperty -Object $layout -Name "schemaVersion"
  $layoutScreenshotCount = Get-JsonProperty -Object $layout -Name "expectedScreenshots"
  $layoutResults = @((Get-JsonProperty -Object $layout -Name "results"))
  if (-not (Test-IntegerValue -Value $layoutSchema -Minimum 1) -or [int]$layoutSchema -ne 2 -or
      -not (Test-IntegerValue -Value $layoutScreenshotCount -Minimum 1) -or [int]$layoutScreenshotCount -ne $ScreenshotRecords.Count -or
      $layoutResults.Count -ne $ScreenshotRecords.Count -or
      [string]::IsNullOrWhiteSpace([string](Get-JsonProperty -Object $layout -Name "browser")) -or
      -not (Test-PathEqual -Left ([string](Get-JsonProperty -Object $layout -Name "sourceFolder")) -Right $CandidateFolder)) {
    Stop-Finalization -Message "Layoutbericht ist unvollständig oder gehört nicht zum vorbereiteten Kandidatenbestand."
  }
  $layoutHtmlNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
  $layoutScreenshotPaths = New-Object 'System.Collections.Generic.HashSet[string]' ($script:PathComparer)
  foreach ($result in $layoutResults) {
    $htmlName = [string](Get-JsonProperty -Object $result -Name "htmlFile")
    $htmlRecord = Get-SingleArtifactRecord -Records $HtmlRecords -Name $htmlName -Context "Layoutbericht"
    $screenshotPath = [System.IO.Path]::GetFullPath([string](Get-JsonProperty -Object $result -Name "screenshot"))
    $screenshotMatches = @($ScreenshotRecords | Where-Object {
      Test-PathEqual -Left ([string](Get-JsonProperty -Object $_ -Name "path")) -Right $screenshotPath
    })
    if ($screenshotMatches.Count -ne 1 -or -not $layoutScreenshotPaths.Add($screenshotPath) -or
        [string](Get-JsonProperty -Object $result -Name "htmlSha256") -ine [string](Get-JsonProperty -Object $htmlRecord -Name "sha256") -or
        [string](Get-JsonProperty -Object $result -Name "screenshotSha256") -ine [string](Get-JsonProperty -Object $screenshotMatches[0] -Name "sha256") -or
        -not (Test-IntegerValue -Value (Get-JsonProperty -Object $result -Name "screenshotBytes") -Minimum 1) -or
        [long](Get-JsonProperty -Object $result -Name "screenshotBytes") -ne [long](Get-JsonProperty -Object $screenshotMatches[0] -Name "bytes") -or
        -not (Test-IntegerValue -Value (Get-JsonProperty -Object $result -Name "pageNumber") -Minimum 1) -or
        -not (Test-IntegerValue -Value (Get-JsonProperty -Object $result -Name "pageCount") -Minimum 1) -or
        [int](Get-JsonProperty -Object $result -Name "pageNumber") -gt [int](Get-JsonProperty -Object $result -Name "pageCount")) {
      Stop-Finalization -Message "Layoutbericht enthält einen ungültigen oder nicht hashgebundenen Seitennachweis."
    }
    $null = $layoutHtmlNames.Add($htmlName)
    Test-PngStructure -Path $screenshotPath
  }
  if ($layoutHtmlNames.Count -ne $HtmlRecords.Count) {
    Stop-Finalization -Message "Layoutbericht deckt nicht jedes ausgewählte HTML-Dokument ab."
  }

  $pdfSchema = Get-JsonProperty -Object $pdf -Name "schemaVersion"
  $pdfResults = @((Get-JsonProperty -Object $pdf -Name "results"))
  if (-not (Test-IntegerValue -Value $pdfSchema -Minimum 1) -or [int]$pdfSchema -ne 1 -or
      $pdfResults.Count -ne $ExpectedHtmlCount -or
      [string]::IsNullOrWhiteSpace([string](Get-JsonProperty -Object $pdf -Name "browser")) -or
      -not (Test-PathEqual -Left ([string](Get-JsonProperty -Object $pdf -Name "sourceFolder")) -Right $CandidateFolder)) {
    Stop-Finalization -Message "PDF-Export-Bericht ist unvollständig oder gehört nicht zum vorbereiteten Kandidatenbestand."
  }
  foreach ($htmlRecord in $HtmlRecords) {
    $htmlName = [string](Get-JsonProperty -Object $htmlRecord -Name "name")
    $resultMatches = @($pdfResults | Where-Object { [string](Get-JsonProperty -Object $_ -Name "htmlFile") -ceq $htmlName })
    if ($resultMatches.Count -ne 1) {
      Stop-Finalization -Message "PDF-Export-Bericht enthält keinen eindeutigen Nachweis für: $htmlName"
    }
    $result = $resultMatches[0]
    $pdfName = [System.IO.Path]::ChangeExtension($htmlName, ".pdf")
    $pdfRecord = Get-SingleArtifactRecord -Records $PdfRecords -Name $pdfName -Context "PDF-Export-Bericht"
    if ([string](Get-JsonProperty -Object $result -Name "htmlSha256") -ine [string](Get-JsonProperty -Object $htmlRecord -Name "sha256") -or
        [string](Get-JsonProperty -Object $result -Name "pdfFile") -cne $pdfName -or
        -not (Test-PathEqual -Left ([string](Get-JsonProperty -Object $result -Name "pdfPath")) -Right ([string](Get-JsonProperty -Object $pdfRecord -Name "path"))) -or
        [string](Get-JsonProperty -Object $result -Name "pdfSha256") -ine [string](Get-JsonProperty -Object $pdfRecord -Name "sha256") -or
        -not (Test-IntegerValue -Value (Get-JsonProperty -Object $result -Name "pdfBytes") -Minimum 1) -or
        [long](Get-JsonProperty -Object $result -Name "pdfBytes") -ne [long](Get-JsonProperty -Object $pdfRecord -Name "bytes") -or
        -not (Test-IntegerValue -Value (Get-JsonProperty -Object $result -Name "pages") -Minimum 1) -or
        [string]::IsNullOrWhiteSpace([string](Get-JsonProperty -Object $result -Name "mediaBox"))) {
      Stop-Finalization -Message "PDF-Export-Bericht ist nicht vollständig an HTML und PDF gebunden: $pdfName"
    }
  }

  $atsSchema = Get-JsonProperty -Object $ats -Name "schemaVersion"
  $atsResults = @((Get-JsonProperty -Object $ats -Name "results"))
  if (-not (Test-IntegerValue -Value $atsSchema -Minimum 1) -or [int]$atsSchema -ne 1 -or
      [string](Get-JsonProperty -Object $ats -Name "status") -notin @("ok", "warnung") -or
      @(Get-JsonProperty -Object $ats -Name "errors").Count -ne 0 -or
      $atsResults.Count -ne $ExpectedHtmlCount -or
      -not (Test-PathEqual -Left ([string](Get-JsonProperty -Object $ats -Name "folder")) -Right $CandidateFolder)) {
    Stop-Finalization -Message "ATS-Prüfbericht ist unvollständig, fehlerhaft oder gehört nicht zum vorbereiteten Kandidatenbestand."
  }
  foreach ($htmlRecord in $HtmlRecords) {
    $htmlName = [string](Get-JsonProperty -Object $htmlRecord -Name "name")
    $resultMatches = @($atsResults | Where-Object { [string](Get-JsonProperty -Object $_ -Name "htmlFile") -ceq $htmlName })
    if ($resultMatches.Count -ne 1) {
      Stop-Finalization -Message "ATS-Prüfbericht enthält keinen eindeutigen Nachweis für: $htmlName"
    }
    $result = $resultMatches[0]
    $pdfName = [System.IO.Path]::ChangeExtension($htmlName, ".pdf")
    $pdfRecord = Get-SingleArtifactRecord -Records $PdfRecords -Name $pdfName -Context "ATS-Prüfbericht"
    $coverage = Get-JsonProperty -Object $result -Name "textCoveragePercent"
    if ([string](Get-JsonProperty -Object $result -Name "htmlSha256") -ine [string](Get-JsonProperty -Object $htmlRecord -Name "sha256") -or
        [string](Get-JsonProperty -Object $result -Name "pdfFile") -cne $pdfName -or
        [string](Get-JsonProperty -Object $result -Name "pdfSha256") -ine [string](Get-JsonProperty -Object $pdfRecord -Name "sha256") -or
        @(Get-JsonProperty -Object $result -Name "missingRequiredText").Count -ne 0 -or
        ($coverage -isnot [int] -and $coverage -isnot [long] -and $coverage -isnot [double] -and $coverage -isnot [decimal]) -or
        [double]$coverage -lt 70 -or
        -not (Test-IntegerValue -Value (Get-JsonProperty -Object $result -Name "extractedComparableCharacters") -Minimum 1) -or
        [string](Get-JsonProperty -Object $result -Name "extractionEngine") -cne "interner_tounicode_parser") {
      Stop-Finalization -Message "ATS-Prüfbericht ist nicht vollständig an HTML und PDF gebunden: $pdfName"
    }
  }
}

if (-not (Test-Path -LiteralPath $Arbeitsordner -PathType Container)) {
  Stop-Finalization -Message "Arbeitsordner fehlt oder ist kein Verzeichnis: $Arbeitsordner"
}

$resolvedWork = (Resolve-Path -LiteralPath $Arbeitsordner).Path
if (($resolvedWork -notmatch '[\\/]Private[\\/]Bewerbungen[\\/]+') -or ($resolvedWork -notmatch '[\\/]_Arbeitsdateien[\\/]')) {
  Stop-Finalization -Message "Arbeitsordner muss unter Private/Bewerbungen/.../_Arbeitsdateien liegen: $resolvedWork"
}

$auftragPath = Join-Path -Path $resolvedWork -ChildPath "Bewerbungsauftrag.json"
$matrixPath = Join-Path -Path $resolvedWork -ChildPath "Anforderungsmatrix.json"
$candidateDir = Join-Path -Path $resolvedWork -ChildPath "Kandidat"
$layoutDir = Join-Path -Path $resolvedWork -ChildPath "Layoutcheck"
$pdfWorkDir = Join-Path -Path $resolvedWork -ChildPath "PDF-Export"
$layoutReportPath = Join-Path -Path $layoutDir -ChildPath "Layoutcheck-Bericht.json"
$pdfReportPath = Join-Path -Path $pdfWorkDir -ChildPath "PDF-Export-Bericht.json"
$atsReportPath = Join-Path -Path $resolvedWork -ChildPath "ATS-Pruefbericht.json"
$finalReportPath = Join-Path -Path $resolvedWork -ChildPath "Finalisierungsbericht.json"
$tokenReportPath = Join-Path -Path $resolvedWork -ChildPath "Tokenverbrauch.json"

foreach ($requiredPath in @($auftragPath, $matrixPath, $candidateDir, $StammdatenPath, $ProfilPath)) {
  if (-not (Test-Path -LiteralPath $requiredPath)) {
    Stop-Finalization -Message "Erforderlicher Pfad fehlt: $requiredPath"
  }
}

$auftrag = Get-Content -LiteralPath $auftragPath -Raw -Encoding UTF8 | ConvertFrom-Json
$documentScope = Get-DocumentScope -Auftrag $auftrag
$expectedCv = [string]$documentScope.lebenslauf -ne "nicht_enthalten"
$expectedLetter = [bool]$documentScope.anschreiben
$expectedEmail = [bool]$documentScope.emailNachricht
$expectedHtmlCount = [int]$expectedCv + [int]$expectedLetter
$targetDir = [System.IO.Path]::GetFullPath([string](Get-JsonProperty -Object $auftrag -Name "zielOrdner"))
$manifestCandidate = [System.IO.Path]::GetFullPath([string](Get-JsonProperty -Object $auftrag -Name "kandidatOrdner"))
$companyDir = Split-Path -Path (Split-Path -Path $resolvedWork -Parent) -Parent
$expectedTarget = [System.IO.Path]::GetFullPath((Join-Path -Path $companyDir -ChildPath (Split-Path -Path $resolvedWork -Leaf)))
if (-not (Test-PathEqual -Left $manifestCandidate -Right $candidateDir)) {
  Stop-Finalization -Message "Kandidatenordner stimmt nicht mit dem Bewerbungsauftrag überein."
}
if (-not (Test-PathEqual -Left $targetDir -Right $expectedTarget) -or -not (Test-IsSafeChildPath -Candidate $targetDir -Root $companyDir)) {
  Stop-Finalization -Message "Zielordner stimmt nicht mit der sicheren Projektstruktur überein."
}

$stammdatenTool = Join-Path -Path $PSScriptRoot -ChildPath "Pruefe-Stammdaten.ps1"
$staticTool = Join-Path -Path $PSScriptRoot -ChildPath "Pruefe-Bewerbung.ps1"
$contentTool = Join-Path -Path $PSScriptRoot -ChildPath "Pruefe-Bewerbungsinhalt.ps1"
$layoutTool = Join-Path -Path $PSScriptRoot -ChildPath "Layoutcheck-Bewerbung.ps1"
$exportTool = Join-Path -Path $PSScriptRoot -ChildPath "Exportiere-PDF.ps1"
$atsTool = Join-Path -Path $PSScriptRoot -ChildPath "Pruefe-ATS.ps1"
$tokenReportTool = Join-Path -Path $PSScriptRoot -ChildPath "Aktualisiere-Tokenbericht.ps1"
$dialogTool = Join-Path -Path $PSScriptRoot -ChildPath "Pruefe-Dialogstatus.ps1"
$stammdatenReportPath = Join-Path -Path $resolvedWork -ChildPath "Stammdaten-Pruefbericht.json"
$contentReportPath = Join-Path -Path $resolvedWork -ChildPath "Inhalts-Pruefbericht.json"

if (-not $Veroeffentlichen) {
  Add-Info "Finalisierung wird vorbereitet: $resolvedWork"
  Invoke-ChildTool -ScriptPath $dialogTool -Arguments @("-AuftragPath", $auftragPath, "-StammdatenPath", $StammdatenPath, "-ProfilPath", $ProfilPath, "-FuerDokumenterstellung")
  Invoke-ChildTool -ScriptPath $stammdatenTool -Arguments @("-StammdatenPath", $StammdatenPath, "-BewerbungsauftragPath", $auftragPath, "-UngeklaerteLogistikAlsFehler", "-BerichtPath", $stammdatenReportPath)
  Invoke-ChildTool -ScriptPath $staticTool -Arguments @("-Ordner", $candidateDir, "-AuftragPath", $auftragPath)
  Invoke-ChildTool -ScriptPath $contentTool -Arguments @("-Ordner", $candidateDir, "-StammdatenPath", $StammdatenPath, "-ProfilPath", $ProfilPath, "-AuftragPath", $auftragPath, "-AnforderungsmatrixPath", $matrixPath, "-BerichtPath", $contentReportPath)
  if ($expectedHtmlCount -gt 0) {
    Invoke-ChildTool -ScriptPath $layoutTool -Arguments @("-Ordner", $candidateDir, "-Browser", $Browser, "-TimeoutSeconds", "$TimeoutSeconds", "-OutputRoot", $layoutDir, "-BerichtPath", $layoutReportPath)
    Invoke-ChildTool -ScriptPath $exportTool -Arguments @("-Ordner", $candidateDir, "-AuftragPath", $auftragPath, "-Browser", $Browser, "-TimeoutSeconds", "$TimeoutSeconds", "-OutputRoot", $pdfWorkDir, "-BerichtPath", $pdfReportPath)
    Invoke-ChildTool -ScriptPath $atsTool -Arguments @("-Ordner", $candidateDir, "-StammdatenPath", $StammdatenPath, "-AuftragPath", $auftragPath, "-BerichtPath", $atsReportPath)
  } else {
    Write-NotRequiredReport -Path $layoutReportPath -Kind "layoutcheck"
    Write-NotRequiredReport -Path $pdfReportPath -Kind "pdf_export"
    Write-NotRequiredReport -Path $atsReportPath -Kind "ats_pdf"
  }

  $qualityPath = Join-Path -Path $candidateDir -ChildPath "Qualitaetscheck.md"
  if (-not (Test-Path -LiteralPath $qualityPath -PathType Leaf)) {
    Stop-Finalization -Message "Qualitaetscheck.md fehlt im Kandidatenordner."
  }
  $layoutWarnings = @(Get-LayoutWarnings -Path $layoutReportPath)
  Update-TechnicalSection -QualityPath $qualityPath -State "vorbereitet" -LayoutReportPath $layoutReportPath -PdfReportPath $pdfReportPath -AtsReportPath $atsReportPath -LayoutWarnings $layoutWarnings -VisualApprovalNote "" -HtmlDocumentCount $expectedHtmlCount
  Invoke-ChildTool -ScriptPath $staticTool -Arguments @("-Ordner", $candidateDir, "-AuftragPath", $auftragPath)
  Invoke-ChildTool -ScriptPath $contentTool -Arguments @("-Ordner", $candidateDir, "-StammdatenPath", $StammdatenPath, "-ProfilPath", $ProfilPath, "-AuftragPath", $auftragPath, "-AnforderungsmatrixPath", $matrixPath, "-BerichtPath", $contentReportPath)

  $artifacts = Get-ReportArtifacts -CandidateFolder $candidateDir -LayoutFolder $layoutDir
  $expectedScreenshots = Get-ExpectedScreenshotCount -CandidateFolder $candidateDir
  if ($artifacts.html.Count -ne $expectedHtmlCount -or $artifacts.pdf.Count -ne $expectedHtmlCount -or $artifacts.screenshots.Count -ne $expectedScreenshots) {
    Stop-Finalization -Message "Vorbereitung erzeugte nicht die laut Dokumentumfang erwarteten $expectedHtmlCount HTML-/PDF-Dateien und einen Screenshot pro A4-Seite (Screenshots erwartet: $expectedScreenshots, erzeugt: $($artifacts.screenshots.Count))."
  }
  $tokenUsageReference = Update-TokenReportNonBlocking -ScriptPath $tokenReportTool -WorkFolder $resolvedWork -ReportPath $tokenReportPath
  $report = [ordered]@{
    schemaVersion = 4
    status = "bereit_zur_sichtpruefung"
    preparedAtUtc = [datetime]::UtcNow.ToString("o")
    workFolder = $resolvedWork
    candidateFolder = $candidateDir
    targetFolder = $targetDir
    layoutReport = $layoutReportPath
    layoutReportArtifact = Get-ArtifactRecord -File (Get-Item -LiteralPath $layoutReportPath)
    pdfReport = $pdfReportPath
    pdfReportArtifact = Get-ArtifactRecord -File (Get-Item -LiteralPath $pdfReportPath)
    atsReport = $atsReportPath
    atsReportArtifact = Get-ArtifactRecord -File (Get-Item -LiteralPath $atsReportPath)
    expectedScreenshots = $expectedScreenshots
    documentScope = $documentScope
    personalReview = if ($expectedScreenshots -gt 0) { "png_sichtpruefung" } else { "textpruefung" }
    layoutWarnings = $layoutWarnings
    tokenUsageReport = $tokenUsageReference
    sourceInputs = [ordered]@{
      stammdaten = Get-ArtifactRecord -File (Get-Item -LiteralPath $StammdatenPath)
      profil = Get-ArtifactRecord -File (Get-Item -LiteralPath $ProfilPath)
      bewerbungsauftrag = Get-ArtifactRecord -File (Get-Item -LiteralPath $auftragPath)
      anforderungsmatrix = Get-ArtifactRecord -File (Get-Item -LiteralPath $matrixPath)
    }
    artifacts = $artifacts
  }
  Set-Content -LiteralPath $finalReportPath -Encoding UTF8 -Value ($report | ConvertTo-Json -Depth 10)
  Add-Ok "Technische Vorbereitung erfolgreich."
  Write-Host ""
  if ($expectedScreenshots -gt 0) {
    Write-Host "Öffne jetzt die Screenshots unter: $layoutDir"
  } else {
    Write-Host "Der Umfang enthält kein HTML-Dokument. Prüfe die ausgewählten Textdateien im Kandidatenordner persönlich: $candidateDir"
  }
  if ($layoutWarnings.Count -gt 0) {
    Write-Host "Layoutwarnungen müssen visuell bewertet und bei der Veröffentlichung mit -VisuelleFreigabeNotiz begründet werden."
  }
  Write-Host "Nach bestätigter Sichtprüfung veröffentlichen mit:"
  $noteExample = if ($layoutWarnings.Count -gt 0) { ' -VisuelleFreigabeNotiz "Warnungen je Seite geprüft; kein Beschnitt und keine Überlappung."' } else { "" }
  Write-Host ".\Tools\Finalisiere-Bewerbung.ps1 -Arbeitsordner `"$resolvedWork`" -Veroeffentlichen -VisuellGeprueft$noteExample"
  exit 0
}

if (-not $VisuellGeprueft) {
  Stop-Finalization -Message "Veröffentlichung erfordert den Schalter -VisuellGeprueft nach tatsächlicher Sichtprüfung."
}
if (-not (Test-Path -LiteralPath $finalReportPath -PathType Leaf)) {
  Stop-Finalization -Message "Finalisierungsbericht fehlt. Zuerst Vorbereitung ohne -Veroeffentlichen ausführen."
}
$preparedReportJson = Get-Content -LiteralPath $finalReportPath -Raw -Encoding UTF8
$report = $preparedReportJson | ConvertFrom-Json
$reportSchemaValue = Get-JsonProperty -Object $report -Name "schemaVersion"
if (($reportSchemaValue -isnot [int] -and $reportSchemaValue -isnot [long]) -or [int]$reportSchemaValue -ne 4) {
  Stop-Finalization -Message "Finalisierungsbericht verwendet kein unterstütztes Schema 4. Erneute Vorbereitung erforderlich."
}
$reportSchema = [int]$reportSchemaValue
foreach ($requiredReportProperty in @("status", "workFolder", "candidateFolder", "targetFolder", "documentScope", "personalReview", "expectedScreenshots", "layoutWarnings", "layoutReport", "layoutReportArtifact", "pdfReport", "pdfReportArtifact", "atsReport", "atsReportArtifact", "sourceInputs", "artifacts")) {
  if (-not (Test-JsonPropertyExists -Object $report -Name $requiredReportProperty)) {
    Stop-Finalization -Message "Finalisierungsbericht ist unvollständig; Pflichtfeld fehlt: $requiredReportProperty. Erneute Vorbereitung erforderlich."
  }
}
if ([string](Get-JsonProperty -Object $report -Name "status") -ne "bereit_zur_sichtpruefung") {
  Stop-Finalization -Message "Finalisierungsbericht befindet sich nicht im veröffentlichbaren Zustand."
}
if (-not (Test-PathEqual -Left ([string](Get-JsonProperty -Object $report -Name "workFolder")) -Right $resolvedWork) -or
    -not (Test-PathEqual -Left ([string](Get-JsonProperty -Object $report -Name "candidateFolder")) -Right $candidateDir) -or
    -not (Test-PathEqual -Left ([string](Get-JsonProperty -Object $report -Name "targetFolder")) -Right $targetDir)) {
  Stop-Finalization -Message "Finalisierungsbericht gehört nicht zum aktuellen Arbeits- oder Zielordner."
}
$reportDocumentScope = Get-JsonProperty -Object $report -Name "documentScope"
if (-not (Test-DocumentScopeMatches -Actual $reportDocumentScope -Expected $documentScope)) {
  Stop-Finalization -Message "Dokumentumfang im Finalisierungsbericht stimmt nicht mit dem aktuellen Bewerbungsauftrag überein. Erneute Vorbereitung erforderlich."
}
$expectedReviewKind = if ($expectedHtmlCount -gt 0) { "png_sichtpruefung" } else { "textpruefung" }
if ([string](Get-JsonProperty -Object $report -Name "personalReview") -ne $expectedReviewKind) {
  Stop-Finalization -Message "Persönliche Prüfart im Finalisierungsbericht stimmt nicht mit dem Dokumentumfang überein. Erneute Vorbereitung erforderlich."
}
$reportedScreenshotCount = Get-JsonProperty -Object $report -Name "expectedScreenshots"
if (($reportedScreenshotCount -isnot [int] -and $reportedScreenshotCount -isnot [long]) -or [int]$reportedScreenshotCount -lt 0) {
  Stop-Finalization -Message "Finalisierungsbericht enthält keine gültige erwartete Screenshotanzahl. Erneute Vorbereitung erforderlich."
}
$currentExpectedScreenshots = Get-ExpectedScreenshotCount -CandidateFolder $candidateDir
if ([int]$reportedScreenshotCount -ne $currentExpectedScreenshots) {
  Stop-Finalization -Message "Screenshot-Sollzahl stimmt nicht mehr mit den vorbereiteten HTML-Seiten überein. Erneute Vorbereitung erforderlich."
}
$rawLayoutWarnings = $report.PSObject.Properties["layoutWarnings"].Value
if ($null -eq $rawLayoutWarnings -or $rawLayoutWarnings -isnot [System.Array]) {
  Stop-Finalization -Message "Finalisierungsbericht enthält keine gültige Liste der Layoutwarnungen. Erneute Vorbereitung erforderlich."
}
[array]$reportLayoutWarnings = @($rawLayoutWarnings)
$expectedTechnicalReports = [ordered]@{
  layoutReport = $layoutReportPath
  pdfReport = $pdfReportPath
  atsReport = $atsReportPath
}
foreach ($technicalReportName in $expectedTechnicalReports.Keys) {
  $reportedPath = [string](Get-JsonProperty -Object $report -Name $technicalReportName)
  $artifactPropertyName = $technicalReportName + "Artifact"
  $reportArtifact = Get-JsonProperty -Object $report -Name $artifactPropertyName
  $artifactPath = [string](Get-JsonProperty -Object $reportArtifact -Name "path")
  if (-not (Test-PathEqual -Left $reportedPath -Right $expectedTechnicalReports[$technicalReportName]) -or
      -not (Test-PathEqual -Left $artifactPath -Right $expectedTechnicalReports[$technicalReportName])) {
    Stop-Finalization -Message "Technischer Berichtspfad stimmt nicht mit dem vorbereiteten Arbeitsordner überein: $technicalReportName"
  }
  Test-ArtifactSetUnchanged -Records @($reportArtifact)
}
$currentLayoutWarnings = @(Get-LayoutWarnings -Path $layoutReportPath)
if ([string]::Join([char]0x1F, [string[]]$reportLayoutWarnings) -cne [string]::Join([char]0x1F, [string[]]$currentLayoutWarnings)) {
  Stop-Finalization -Message "Layoutwarnungen stimmen nicht mehr mit dem vorbereiteten Layoutbericht überein. Erneute Vorbereitung erforderlich."
}
if ($reportLayoutWarnings.Count -gt 0 -and [string]::IsNullOrWhiteSpace($VisuelleFreigabeNotiz)) {
  Stop-Finalization -Message "Automatische Layoutwarnungen liegen vor. Die Sichtprüfung muss mit -VisuelleFreigabeNotiz nachvollziehbar begründet werden."
}
$normalizedVisualNote = if ([string]::IsNullOrWhiteSpace($VisuelleFreigabeNotiz)) {
  ""
} else {
  ([regex]::Replace($VisuelleFreigabeNotiz.Trim(), '\s+', ' '))
}

$artifactGroups = Get-JsonProperty -Object $report -Name "artifacts"
foreach ($requiredArtifactGroup in @("candidate", "html", "pdf", "screenshots")) {
  if (-not (Test-JsonPropertyExists -Object $artifactGroups -Name $requiredArtifactGroup)) {
    Stop-Finalization -Message "Finalisierungsbericht ist unvollständig; Artefaktgruppe fehlt: $requiredArtifactGroup. Erneute Vorbereitung erforderlich."
  }
}
$candidateArtifactRecords = @((Get-JsonProperty -Object $artifactGroups -Name "candidate"))
$htmlArtifactRecords = @((Get-JsonProperty -Object $artifactGroups -Name "html"))
$pdfArtifactRecords = @((Get-JsonProperty -Object $artifactGroups -Name "pdf"))
$screenshotRecords = @((Get-JsonProperty -Object $artifactGroups -Name "screenshots"))
if ($candidateArtifactRecords.Count -eq 0) {
  Stop-Finalization -Message "Finalisierungsbericht enthält keine Kandidatenartefakte. Erneute Vorbereitung erforderlich."
}
if ($htmlArtifactRecords.Count -ne $expectedHtmlCount -or $pdfArtifactRecords.Count -ne $expectedHtmlCount) {
  Stop-Finalization -Message "HTML-/PDF-Nachweise im Finalisierungsbericht stimmen nicht mit dem Dokumentumfang überein. Erneute Vorbereitung erforderlich."
}
if ($screenshotRecords.Count -ne $currentExpectedScreenshots) {
  Stop-Finalization -Message "Screenshot-Nachweise im Finalisierungsbericht stimmen nicht mit der erwarteten Seitenzahl überein. Erneute Vorbereitung erforderlich."
}
Test-ArtifactSetExact -Records $candidateArtifactRecords -Folder $candidateDir
Test-ArtifactSetExact -Records $htmlArtifactRecords -Folder $candidateDir -Filter "*.html"
Test-ArtifactSetExact -Records $pdfArtifactRecords -Folder $candidateDir -Filter "*.pdf"
Test-ArtifactSetExact -Records $screenshotRecords -Folder $layoutDir -Filter "*.png"
Test-TechnicalReportContracts `
  -LayoutReportPath $layoutReportPath `
  -PdfReportPath $pdfReportPath `
  -AtsReportPath $atsReportPath `
  -ExpectedHtmlCount $expectedHtmlCount `
  -HtmlRecords $htmlArtifactRecords `
  -PdfRecords $pdfArtifactRecords `
  -ScreenshotRecords $screenshotRecords `
  -CandidateFolder $candidateDir
$sourceInputs = Get-JsonProperty -Object $report -Name "sourceInputs"
$expectedSourcePaths = [ordered]@{
  stammdaten = [System.IO.Path]::GetFullPath($StammdatenPath)
  profil = [System.IO.Path]::GetFullPath($ProfilPath)
  bewerbungsauftrag = [System.IO.Path]::GetFullPath($auftragPath)
  anforderungsmatrix = [System.IO.Path]::GetFullPath($matrixPath)
}
$sourceProperties = @($sourceInputs.PSObject.Properties)
$actualSourceNames = @($sourceProperties.Name | Sort-Object)
if ($sourceProperties.Count -ne $expectedSourcePaths.Count -or
    @(Compare-Object -ReferenceObject @($expectedSourcePaths.Keys | Sort-Object) -DifferenceObject $actualSourceNames).Count -gt 0) {
  Stop-Finalization -Message "Finalisierungsbericht muss genau die vier vorbereiteten Quellnachweise enthalten. Erneute Vorbereitung erforderlich."
}
foreach ($sourceName in $expectedSourcePaths.Keys) {
  $sourceRecord = $sourceInputs.PSObject.Properties[$sourceName].Value
  $preparedSourcePath = [System.IO.Path]::GetFullPath([string](Get-JsonProperty -Object $sourceRecord -Name "path"))
  if (-not (Test-PathEqual -Left $preparedSourcePath -Right $expectedSourcePaths[$sourceName])) {
    Stop-Finalization -Message "Beim Veröffentlichungslauf wurde eine andere Quelldatei übergeben: $sourceName"
  }
  Test-ArtifactSetUnchanged -Records @($sourceRecord)
}

Invoke-ChildTool -ScriptPath $dialogTool -Arguments @("-AuftragPath", $auftragPath, "-StammdatenPath", $StammdatenPath, "-ProfilPath", $ProfilPath, "-FuerDokumenterstellung")
Invoke-ChildTool -ScriptPath $stammdatenTool -Arguments @("-StammdatenPath", $StammdatenPath, "-BewerbungsauftragPath", $auftragPath, "-UngeklaerteLogistikAlsFehler", "-BerichtPath", $stammdatenReportPath)

$qualityPath = Join-Path -Path $candidateDir -ChildPath "Qualitaetscheck.md"
if (-not (Test-Path -LiteralPath $qualityPath -PathType Leaf)) {
  Stop-Finalization -Message "Qualitaetscheck.md fehlt im Kandidatenordner oder ist keine reguläre Datei."
}

$candidateFiles = @(Get-ChildItem -LiteralPath $candidateDir -File)
$fixedCandidateNames = @("Stellenbeschreibung.md", "Analyse.md", "Qualitaetscheck.md", "Druck-Hinweis.md", "Offene_Fragen.md")
$personNamePattern = '[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z0-9][A-Za-z0-9.-]*'
$unexpected = @($candidateFiles | Where-Object {
  $name = $_.Name
  $isFixed = $name -in $fixedCandidateNames
  $isCv = $expectedCv -and $name -match "^Lebenslauf - $personNamePattern\.(?:html|pdf)$"
  $isLetter = $expectedLetter -and $name -match "^Anschreiben - $personNamePattern\.(?:html|pdf)$"
  $isEmail = $expectedEmail -and $name -match '^Email-Nachricht--[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*\.md$'
  -not ($isFixed -or $isCv -or $isLetter -or $isEmail) -or $name -match 'ENTWURF|TODO'
})
if ($unexpected.Count -gt 0) {
  Stop-Finalization -Message "Kandidatenordner enthält nicht veröffentlichbare Dateien: $($unexpected.Name -join ', ')"
}

$stageDir = Join-Path -Path $companyDir -ChildPath (".publish-" + [guid]::NewGuid().ToString("N"))
$backupDir = Join-Path -Path $companyDir -ChildPath (".backup-" + [guid]::NewGuid().ToString("N"))
$reportTempPath = Join-Path -Path $resolvedWork -ChildPath (".Finalisierungsbericht.publish-" + [guid]::NewGuid().ToString("N") + ".json")
$reportBackupPath = Join-Path -Path $resolvedWork -ChildPath (".Finalisierungsbericht.backup-" + [guid]::NewGuid().ToString("N") + ".json")
if (-not (Test-IsSafeChildPath -Candidate $stageDir -Root $companyDir) -or
    -not (Test-IsSafeChildPath -Candidate $backupDir -Root $companyDir) -or
    -not (Test-IsSafeChildPath -Candidate $reportTempPath -Root $resolvedWork) -or
    -not (Test-IsSafeChildPath -Candidate $reportBackupPath -Root $resolvedWork)) {
  Stop-Finalization -Message "Interne Veröffentlichungsordner liegen außerhalb des Firmenordners."
}

$targetBackedUp = $false
$targetWasEmpty = $false
$targetInstalled = $false
$qualityOriginalBytes = [System.IO.File]::ReadAllBytes($qualityPath)
$qualityMayHaveChanged = $false
try {
  $qualityMayHaveChanged = $true
  Update-TechnicalSection -QualityPath $qualityPath -State "bestaetigt" -LayoutReportPath $layoutReportPath -PdfReportPath $pdfReportPath -AtsReportPath $atsReportPath -LayoutWarnings $reportLayoutWarnings -VisualApprovalNote $normalizedVisualNote -HtmlDocumentCount $expectedHtmlCount
  Invoke-ChildTool -ScriptPath $staticTool -Arguments @("-Ordner", $candidateDir, "-AuftragPath", $auftragPath) -ThrowOnFailure
  Invoke-ChildTool -ScriptPath $contentTool -Arguments @("-Ordner", $candidateDir, "-StammdatenPath", $StammdatenPath, "-ProfilPath", $ProfilPath, "-AuftragPath", $auftragPath, "-AnforderungsmatrixPath", $matrixPath, "-BerichtPath", $contentReportPath) -ThrowOnFailure
  if ($reportSchema -ge 2 -and $expectedHtmlCount -gt 0) {
    Invoke-ChildTool -ScriptPath $atsTool -Arguments @("-Ordner", $candidateDir, "-StammdatenPath", $StammdatenPath, "-AuftragPath", $auftragPath) -ThrowOnFailure
  }

  $approvedArtifacts = Get-ReportArtifacts -CandidateFolder $candidateDir -LayoutFolder $layoutDir
  if ($approvedArtifacts.html.Count -ne $expectedHtmlCount -or
      $approvedArtifacts.pdf.Count -ne $expectedHtmlCount -or
      $approvedArtifacts.screenshots.Count -ne $currentExpectedScreenshots -or
      $approvedArtifacts.candidate.Count -ne $candidateArtifactRecords.Count) {
    throw "Artefaktmenge änderte sich während der Veröffentlichungsprüfung."
  }
  $report.artifacts = $approvedArtifacts
  $candidateFiles = @(Get-ChildItem -LiteralPath $candidateDir -File)

  New-Item -Path $stageDir -ItemType Directory | Out-Null
  $stageShippingDir = Join-Path -Path $stageDir -ChildPath "Versand"
  $stageInternalDir = Join-Path -Path $stageDir -ChildPath "Intern"
  New-Item -Path $stageShippingDir -ItemType Directory | Out-Null
  New-Item -Path $stageInternalDir -ItemType Directory | Out-Null
  foreach ($file in $candidateFiles) {
    $destinationFolder = if ($file.Extension -ieq ".pdf" -or $file.Name -match '^Email-Nachricht--.+\.md$') {
      $stageShippingDir
    } else {
      $stageInternalDir
    }
    Copy-Item -LiteralPath $file.FullName -Destination (Join-Path -Path $destinationFolder -ChildPath $file.Name)
  }
  $manifestPath = New-PublicationManifest -Root $stageDir -Auftrag $auftrag -SourceInputs $sourceInputs
  Invoke-ChildTool -ScriptPath $staticTool -Arguments @("-Ordner", $stageDir, "-AuftragPath", $auftragPath) -ThrowOnFailure
  Invoke-ChildTool -ScriptPath $contentTool -Arguments @("-Ordner", $stageDir, "-StammdatenPath", $StammdatenPath, "-ProfilPath", $ProfilPath, "-AuftragPath", $auftragPath, "-AnforderungsmatrixPath", $matrixPath) -ThrowOnFailure
  if ($reportSchema -ge 2 -and $expectedHtmlCount -gt 0) {
    Invoke-ChildTool -ScriptPath $atsTool -Arguments @("-Ordner", $stageDir, "-StammdatenPath", $StammdatenPath, "-AuftragPath", $auftragPath) -ThrowOnFailure
  }

  $report.status = "veroeffentlicht"
  $report | Add-Member -NotePropertyName publishedAtUtc -NotePropertyValue ([datetime]::UtcNow.ToString("o")) -Force
  $report | Add-Member -NotePropertyName publishedFolder -NotePropertyValue $targetDir -Force
  $publishedManifestPath = Join-Path -Path $targetDir -ChildPath "Manifest.json"
  $report | Add-Member -NotePropertyName publishedManifest -NotePropertyValue ([ordered]@{
    path = $publishedManifestPath
    sha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
  }) -Force
  $report | Add-Member -NotePropertyName visualApprovalNote -NotePropertyValue $normalizedVisualNote -Force
  Set-Content -LiteralPath $reportTempPath -Encoding UTF8 -Value ($report | ConvertTo-Json -Depth 10)
  $preparedPublishedReport = Get-Content -LiteralPath $reportTempPath -Raw -Encoding UTF8 | ConvertFrom-Json
  if ([string](Get-JsonProperty -Object $preparedPublishedReport -Name "status") -ne "veroeffentlicht") {
    throw "Temporärer Veröffentlichungsbericht konnte nicht validiert werden."
  }

  if (Test-Path -LiteralPath $targetDir) {
    if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) {
      throw "Zielpfad ist kein Ordner: $targetDir"
    }
    $targetEntries = @(Get-ChildItem -LiteralPath $targetDir -Force)
    if ($targetEntries.Count -gt 0 -and -not $Ersetzen) {
      throw "Finaler Zielordner ist nicht leer. Verwende -Ersetzen nur für eine bewusst neu geprüfte Veröffentlichung."
    }
    if ($targetEntries.Count -gt 0) {
      Move-Item -LiteralPath $targetDir -Destination $backupDir
      $targetBackedUp = $true
    } else {
      $targetWasEmpty = $true
      Remove-Item -LiteralPath $targetDir -Force
    }
  }

  Move-Item -LiteralPath $stageDir -Destination $targetDir
  $targetInstalled = $true
  [System.IO.File]::Replace($reportTempPath, $finalReportPath, $reportBackupPath, $true)
} catch {
  $publishError = $_.Exception.Message
  $rollbackErrors = New-Object System.Collections.Generic.List[string]
  $reportBackupRestored = $false
  if ($qualityMayHaveChanged) {
    try { [System.IO.File]::WriteAllBytes($qualityPath, $qualityOriginalBytes) } catch { $rollbackErrors.Add("Qualitaetscheck.md: $($_.Exception.Message)") | Out-Null }
  }
  if (Test-Path -LiteralPath $stageDir -PathType Container) {
    try { Remove-Item -LiteralPath $stageDir -Recurse -Force } catch { $rollbackErrors.Add("Staging-Ordner: $($_.Exception.Message)") | Out-Null }
  }
  if ($targetInstalled -and (Test-Path -LiteralPath $targetDir -PathType Container)) {
    try { Remove-Item -LiteralPath $targetDir -Recurse -Force } catch { $rollbackErrors.Add("neuer Zielordner: $($_.Exception.Message)") | Out-Null }
  }
  if ($targetBackedUp -and (Test-Path -LiteralPath $backupDir -PathType Container)) {
    try { Move-Item -LiteralPath $backupDir -Destination $targetDir } catch { $rollbackErrors.Add("alter Zielordner: $($_.Exception.Message)") | Out-Null }
  } elseif ($targetWasEmpty -and -not (Test-Path -LiteralPath $targetDir)) {
    try { New-Item -Path $targetDir -ItemType Directory -Force | Out-Null } catch { $rollbackErrors.Add("leerer Zielordner: $($_.Exception.Message)") | Out-Null }
  }
  if (Test-Path -LiteralPath $reportBackupPath -PathType Leaf) {
    try {
      Copy-Item -LiteralPath $reportBackupPath -Destination $finalReportPath -Force
      $reportBackupRestored = $true
    } catch {
      $rollbackErrors.Add("Finalisierungsbericht: $($_.Exception.Message)") | Out-Null
    }
  } elseif (-not (Test-Path -LiteralPath $finalReportPath -PathType Leaf)) {
    try { Set-Content -LiteralPath $finalReportPath -Encoding UTF8 -Value $preparedReportJson } catch { $rollbackErrors.Add("Finalisierungsbericht: $($_.Exception.Message)") | Out-Null }
  }
  if (Test-Path -LiteralPath $reportTempPath -PathType Leaf) {
    try { Remove-Item -LiteralPath $reportTempPath -Force } catch { $rollbackErrors.Add("temporärer Bericht: $($_.Exception.Message)") | Out-Null }
  }
  if ($reportBackupRestored -and (Test-Path -LiteralPath $reportBackupPath -PathType Leaf)) {
    try { Remove-Item -LiteralPath $reportBackupPath -Force } catch { $rollbackErrors.Add("wiederhergestellte Berichtssicherung: $($_.Exception.Message)") | Out-Null }
  } elseif (Test-Path -LiteralPath $reportBackupPath -PathType Leaf) {
    $rollbackErrors.Add("Berichtssicherung zur manuellen Wiederherstellung erhalten: $reportBackupPath") | Out-Null
  }
  $rollbackSuffix = if ($rollbackErrors.Count -gt 0) { " Rollback unvollständig: $($rollbackErrors -join ' | ')" } else { " Bisheriger Ziel- und Berichtsstand wurden wiederhergestellt." }
  Stop-Finalization -Message "Atomare Veröffentlichung fehlgeschlagen: $publishError.$rollbackSuffix"
}

foreach ($obsoleteBackup in @($backupDir, $reportBackupPath)) {
  if (Test-Path -LiteralPath $obsoleteBackup) {
    try {
      Remove-Item -LiteralPath $obsoleteBackup -Recurse -Force
    } catch {
      Write-Host "[WARNUNG] Veröffentlichung war erfolgreich, aber eine Sicherung konnte nicht entfernt werden: $obsoleteBackup ($($_.Exception.Message))" -ForegroundColor Yellow
    }
  }
}
Add-Ok "Bewerbung vollständig und atomar veröffentlicht: $targetDir"
Write-Host "Versandfertige Dateien: $(Join-Path -Path $targetDir -ChildPath 'Versand')"
exit 0
