#requires -Version 7.6
#requires -PSEdition Core

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Arbeitsordner,

  [ValidateSet("auto", "chrome", "edge", "chromium")]
  [string]$Browser = "auto",

  [string]$BrowserExecutablePath,

  [string]$StammdatenPath = (Join-Path -Path $PSScriptRoot -ChildPath ".." -AdditionalChildPath "Private", "Daten", "01_PERSOENLICHE_DATEN.md"),

  [string]$ProfilPath = (Join-Path -Path $PSScriptRoot -ChildPath ".." -AdditionalChildPath "Private", "Daten", "02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md"),

  [switch]$Veroeffentlichen,

  [switch]$VisuellGeprueft,

  [string]$VisuelleFreigabeNotiz,

  [switch]$Ersetzen,

  [switch]$NeuPruefen,

  [ValidateRange(1, 600)]
  [int]$TimeoutSeconds = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/OrderPaths.psm1") -Force
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/Passfoto.psm1") -Force
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/Platform.psm1") -Force
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/PngTools.psm1") -Force
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/WorkflowCheckpoint.psm1") -Force
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/ApprovalContract.psm1") -Force
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/DocumentScope.psm1") -Force
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/JsonContract.psm1") -Force
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/AtomicFile.psm1") -Force
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/MatrixContract.psm1") -Force
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/EvidenceIndexContract.psm1") -Force
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/FinalizationCache.psm1") -Force
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/JsonContract.psm1") -Force -Global
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/AtomicFile.psm1") -Force -Global
$script:ChildToolTimeoutSeconds = [math]::Min(3600, [math]::Max(120, $TimeoutSeconds * 8))

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

function Update-WorkflowCheckpointNonBlocking {
  param(
    [Parameter(Mandatory)][string]$WorkFolder,
    [Parameter(Mandatory)][string]$Step
  )

  try {
    $checkpoint = Write-WorkflowCheckpoint -Arbeitsordner $WorkFolder -Schritt $Step
    Add-Info "Workflow-Checkpoint aktualisiert ($($checkpoint.step), $($checkpoint.artifactCount) Artefakte)."
  } catch {
    Write-Host "[WARNUNG] Workflow-Checkpoint konnte nicht aktualisiert werden; die fachlichen Originalartefakte bleiben maßgeblich: $($_.Exception.Message)" -ForegroundColor Yellow
  }
}

$script:PathComparison = if ($env:OS -eq "Windows_NT") { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
$script:PathComparer = if ($env:OS -eq "Windows_NT") { [System.StringComparer]::OrdinalIgnoreCase } else { [System.StringComparer]::Ordinal }

function Test-PathEqual {
  param([string]$Left, [string]$Right)
  if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) { return $false }
  return Test-SamePath -Left $Left -Right $Right
}

function Test-IsSafeChildPath {
  param([string]$Candidate, [string]$Root)
  return Test-PathWithinRoot -Candidate $Candidate -Root $Root
}

function Get-LexicalFullPath {
  param([Parameter(Mandatory)][string]$Path)

  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $pathRoot = [System.IO.Path]::GetPathRoot($fullPath)
  if ([string]::Equals($fullPath, $pathRoot, $script:PathComparison)) {
    return $fullPath
  }
  return $fullPath.TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
  )
}

function Test-LexicalPathEqual {
  param([string]$Left, [string]$Right)

  if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) { return $false }
  try {
    return [string]::Equals(
      (Get-LexicalFullPath -Path $Left),
      (Get-LexicalFullPath -Path $Right),
      $script:PathComparison
    )
  } catch {
    return $false
  }
}

function Resolve-WorkflowContractPath {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Candidate,
    [Parameter(Mandatory)][string]$Root,
    [switch]$AllowRoot,
    [switch]$MustExist,
    [switch]$ForWrite,
    [ValidateSet("Any", "Leaf", "Container")][string]$PathType = "Any"
  )

  $safePath = Resolve-SafePath `
    -Candidate $Candidate `
    -Root $Root `
    -AllowRoot:$AllowRoot `
    -MustExist:$MustExist `
    -ForWrite:$ForWrite `
    -PathType $PathType

  # Canonical containment alone would accept an internal link alias (for example
  # Ziel-A -> Ziel-B inside the same company root). Contract paths must retain
  # their relative lexical identity so that -Ersetzen can never target Ziel-B
  # through such an alias.
  $lexicalRoot = Get-LexicalFullPath -Path $Root
  $lexicalCandidate = Get-LexicalFullPath -Path $safePath
  $canonicalRoot = Get-LexicalFullPath -Path (Get-CanonicalPath -Path $lexicalRoot)
  $canonicalCandidate = Get-LexicalFullPath -Path (Get-CanonicalPath -Path $lexicalCandidate -AllowMissing)
  $lexicalRelative = [System.IO.Path]::GetRelativePath($lexicalRoot, $lexicalCandidate)
  $canonicalRelative = [System.IO.Path]::GetRelativePath($canonicalRoot, $canonicalCandidate)
  if (-not [string]::Equals($lexicalRelative, $canonicalRelative, $script:PathComparison)) {
    throw "Vertragspfad verwendet einen symbolischen Link oder eine Junction als internen Alias: $lexicalCandidate"
  }
  return $lexicalCandidate
}

function Get-SafeFileSet {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Folder,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$SecurityRoot,
    [string]$Filter = "*",
    [switch]$Recurse
  )

  $safeFolder = Resolve-WorkflowContractPath `
    -Candidate $Folder `
    -Root $SecurityRoot `
    -AllowRoot:$(Test-LexicalPathEqual -Left $Folder -Right $SecurityRoot) `
    -MustExist `
    -ForWrite `
    -PathType Container
  foreach ($item in Get-ChildItem -LiteralPath $safeFolder -File -Filter $Filter -Recurse:$Recurse) {
    $safeItemPath = Resolve-WorkflowContractPath `
      -Candidate $item.FullName `
      -Root $safeFolder `
      -MustExist `
      -ForWrite `
      -PathType Leaf
    # Repeat the outer-root check for each enumerated item. This also catches a
    # directory alias introduced after the folder preflight.
    $null = Resolve-WorkflowContractPath `
      -Candidate $safeItemPath `
      -Root $SecurityRoot `
      -MustExist `
      -ForWrite `
      -PathType Leaf
    Get-Item -LiteralPath $safeItemPath -Force
  }
}

function Get-JsonProperty {
  param([object]$Object, [string]$Name)
  if ($null -eq $Object) { return $null }
  if ($Object -is [System.Collections.IDictionary]) {
    if ($Object.Contains($Name)) { return $Object[$Name] }
    return $null
  }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

function Test-JsonPropertyExists {
  param([object]$Object, [string]$Name)
  if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($Name) }
  return ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name])
}

function Test-DocumentScopeMatches {
  param([object]$Actual, [object]$Expected)
  if ($null -eq $Actual -or $null -eq $Expected) { return $false }
  return Test-ContractDocumentScope -Actual $Actual -Expected $Expected
}

function Get-DocumentScope {
  param([object]$Auftrag)
  return Get-ContractDocumentScope -Auftrag $Auftrag
}

function Write-NotRequiredReport {
  param([string]$Path, [string]$Kind, [string]$WorkflowRoot)

  $Path = Resolve-WorkflowContractPath -Candidate $Path -Root $WorkflowRoot -ForWrite -PathType Leaf
  $parent = Split-Path -Path $Path -Parent
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -Path $parent -ItemType Directory -Force | Out-Null
  }
  $null = Resolve-WorkflowContractPath -Candidate $parent -Root $WorkflowRoot -MustExist -ForWrite -PathType Container
  $Path = Resolve-WorkflowContractPath -Candidate $Path -Root $WorkflowRoot -ForWrite -PathType Leaf
  $report = [ordered]@{
    schemaVersion = 1
    checkedAtUtc = [datetime]::UtcNow.ToString("o")
    runtime = Get-RuntimeFingerprint
    status = "nicht_erforderlich"
    kind = $Kind
    reason = "Der gewählte Dokumentumfang enthält kein HTML-/PDF-Dokument."
    results = @()
  }
  Write-AtomicJson -Path $Path -Value $report -Depth 5
}

function Invoke-ChildTool {
  param([string]$ScriptPath, [string[]]$Arguments, [switch]$ThrowOnFailure)

  if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
    if ($ThrowOnFailure) { throw "Werkzeug fehlt: $ScriptPath" }
    Stop-Finalization -Message "Werkzeug fehlt: $ScriptPath"
  }
  $powerShellExe = (Get-Process -Id $PID).Path
  $nativeArguments = @("-NoLogo", "-NoProfile", "-NonInteractive", "-File", $ScriptPath) + @($Arguments)
  $result = Invoke-NativeProcess `
    -FilePath $powerShellExe `
    -ArgumentList $nativeArguments `
    -TimeoutSeconds $script:ChildToolTimeoutSeconds `
    -MaxStdoutChars 1048576 `
    -MaxStderrChars 1048576
  foreach ($line in @($result.StandardOutput -split '\r?\n' | Where-Object { $_.Length -gt 0 })) { Write-Host $line }
  foreach ($line in @($result.StandardError -split '\r?\n' | Where-Object { $_.Length -gt 0 })) { Write-Host $line }
  $failure = if ($result.TimedOut) {
    "Werkzeuglauf überschritt das Zeitlimit und sein Prozessbaum wurde beendet: $([System.IO.Path]::GetFileName($ScriptPath))"
  } elseif ($result.StdoutTruncated -or $result.StderrTruncated) {
    "Werkzeuglauf erzeugte mehr Ausgabe als sicher verarbeitet werden kann: $([System.IO.Path]::GetFileName($ScriptPath))"
  } elseif ($result.ExitCode -ne 0) {
    "Werkzeuglauf fehlgeschlagen: $([System.IO.Path]::GetFileName($ScriptPath)) (Exitcode $($result.ExitCode))"
  } else {
    $null
  }
  if ($failure) {
    if ($ThrowOnFailure) { throw $failure }
    Stop-Finalization -Message $failure
  }
}

function Invoke-FinalizationStage {
  param(
    [Parameter(Mandatory)][ValidateSet('dialog', 'stammdaten', 'statisch', 'inhalt', 'layout', 'pdf', 'ats')][string]$Stage,
    [Parameter(Mandatory)][string[]]$InputFiles,
    [string[]]$OutputFiles = @(),
    [hashtable]$Parameters = @{},
    [object]$Runtime = $null,
    [Parameter(Mandatory)][scriptblock]$Action
  )
  # Each downstream cache key binds its concrete report and artifact inputs.  The
  # preceding stage must still pass in this invocation, but unrelated report-only
  # changes (for example the technical quality note) do not force a new browser run.
  $dependencyKeys = @()
  $fingerprint = Get-FinalizationStageFingerprint -Stage $Stage -Root $resolvedWork -ImplementationFiles $script:CacheImplementationFiles -InputFiles $InputFiles -Parameters $Parameters -Runtime $Runtime -DependencyKeys $dependencyKeys
  $decision = Get-FinalizationCacheDecision -State $script:CheckState -Stage $Stage -Fingerprint $fingerprint -Root $resolvedWork -Force:$NeuPruefen
  if ([bool]$decision.reusable) {
    $run = [ordered]@{ id = $Stage; status = 'reused'; cacheKey = $fingerprint.cacheKey; cacheReason = $decision.reason; durationMs = 0 }
    $script:StageRuns.Add($run) | Out-Null
    return $run
  }
  $started = [DateTime]::UtcNow
  try {
    & $Action
    $durationMs = [int](([DateTime]::UtcNow - $started).TotalMilliseconds)
    Save-FinalizationStageResult -Path $script:CheckStatePath -Root $resolvedWork -Stage $Stage -Fingerprint $fingerprint -OutputFiles $OutputFiles -DurationMs $durationMs
    $script:CheckState = Read-FinalizationCheckState -Path $script:CheckStatePath
    $run = [ordered]@{ id = $Stage; status = 'executed'; cacheKey = $fingerprint.cacheKey; cacheReason = $decision.reason; durationMs = $durationMs }
    $script:StageRuns.Add($run) | Out-Null
    return $run
  } catch {
    $durationMs = [int](([DateTime]::UtcNow - $started).TotalMilliseconds)
    Save-FinalizationStageResult -Path $script:CheckStatePath -Root $resolvedWork -Stage $Stage -Fingerprint $fingerprint -OutputFiles @() -DurationMs $durationMs -Status failed
    throw
  }
}

function Update-TokenReportNonBlocking {
  param(
    [string]$ScriptPath,
    [string]$WorkFolder,
    [string]$ReportPath,
    [string]$WorkflowRoot
  )

  $WorkFolder = Resolve-WorkflowContractPath -Candidate $WorkFolder -Root $WorkflowRoot -MustExist -ForWrite -PathType Container
  $ReportPath = Resolve-WorkflowContractPath -Candidate $ReportPath -Root $WorkflowRoot -ForWrite -PathType Leaf

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
    $result = Invoke-NativeProcess `
      -FilePath $powerShellExe `
      -ArgumentList @("-NoLogo", "-NoProfile", "-NonInteractive", "-File", $ScriptPath, "-Arbeitsordner", $WorkFolder, "-Messbereich", "technische_vorbereitung") `
      -TimeoutSeconds 120 `
      -MaxStdoutChars 262144 `
      -MaxStderrChars 262144
    foreach ($line in @($result.StandardOutput -split '\r?\n' | Where-Object { $_.Length -gt 0 })) { Write-Host $line }
    foreach ($line in @($result.StandardError -split '\r?\n' | Where-Object { $_.Length -gt 0 })) { Write-Host $line }
    if ($result.TimedOut -or $result.StdoutTruncated -or $result.StderrTruncated -or $result.ExitCode -ne 0) {
      Write-Host "[WARNUNG] Tokenbericht konnte nicht aktualisiert werden; die Finalisierung wird fortgesetzt." -ForegroundColor Yellow
      return $reference
    }
    if (Test-Path -LiteralPath $ReportPath -PathType Leaf) {
      $ReportPath = Resolve-WorkflowContractPath -Candidate $ReportPath -Root $WorkflowRoot -MustExist -ForWrite -PathType Leaf
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
    [string]$WorkflowRoot,
    [ValidateSet("vorbereitet", "bestaetigt")]
    [string]$State,
    [string]$LayoutReportPath,
    [string]$PdfReportPath,
    [string]$AtsReportPath,
    [array]$LayoutWarnings,
    [string]$VisualApprovalNote,
    [int]$HtmlDocumentCount
  )

  $QualityPath = Resolve-WorkflowContractPath -Candidate $QualityPath -Root $WorkflowRoot -MustExist -ForWrite -PathType Leaf

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
  $QualityPath = Resolve-WorkflowContractPath -Candidate $QualityPath -Root $WorkflowRoot -MustExist -ForWrite -PathType Leaf
  Write-AtomicText -Path $QualityPath -Content $updated
}

function Get-ArtifactRecord {
  param([System.IO.FileInfo]$File, [string]$Root)

  if (-not [string]::IsNullOrWhiteSpace($Root)) {
    $safePath = Resolve-WorkflowContractPath -Candidate $File.FullName -Root $Root -MustExist -ForWrite -PathType Leaf
    $File = Get-Item -LiteralPath $safePath -Force
  }
  return [ordered]@{
    name = $File.Name
    path = $File.FullName
    bytes = $File.Length
    sha256 = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash
  }
}

function Get-ReportArtifacts {
  param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$CandidateFolder,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$LayoutFolder,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$WorkflowRoot
  )
  $html = @(Get-SafeFileSet -Folder $CandidateFolder -SecurityRoot $WorkflowRoot -Filter "*.html" | Sort-Object Name | ForEach-Object { Get-ArtifactRecord -File $_ -Root $WorkflowRoot })
  $pdf = @(Get-SafeFileSet -Folder $CandidateFolder -SecurityRoot $WorkflowRoot -Filter "*.pdf" | Sort-Object Name | ForEach-Object { Get-ArtifactRecord -File $_ -Root $WorkflowRoot })
  $screenshots = @(Get-SafeFileSet -Folder $LayoutFolder -SecurityRoot $WorkflowRoot -Filter "*.png" | Sort-Object Name | ForEach-Object { Get-ArtifactRecord -File $_ -Root $WorkflowRoot })
  $candidate = @(Get-SafeFileSet -Folder $CandidateFolder -SecurityRoot $WorkflowRoot | Sort-Object Name | ForEach-Object { Get-ArtifactRecord -File $_ -Root $WorkflowRoot })
  return [ordered]@{ html = $html; pdf = $pdf; screenshots = $screenshots; candidate = $candidate }
}

function Get-ExpectedScreenshotCount {
  param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$CandidateFolder,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$WorkflowRoot
  )
  $count = 0
  foreach ($html in Get-SafeFileSet -Folder $CandidateFolder -SecurityRoot $WorkflowRoot -Filter "*.html") {
    $safeHtmlPath = Resolve-WorkflowContractPath -Candidate $html.FullName -Root $WorkflowRoot -MustExist -ForWrite -PathType Leaf
    $text = Get-Content -LiteralPath $safeHtmlPath -Raw -Encoding UTF8
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
  param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Root,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$SecurityRoot,
    [object]$Auftrag,
    [object]$SourceInputs
  )

  $Root = Resolve-WorkflowContractPath -Candidate $Root -Root $SecurityRoot -MustExist -ForWrite -PathType Container
  $records = @()
  foreach ($file in Get-SafeFileSet -Folder $Root -SecurityRoot $SecurityRoot -Recurse | Where-Object { $_.Name -ne "Manifest.json" } | Sort-Object FullName) {
    $safeFilePath = Resolve-WorkflowContractPath -Candidate $file.FullName -Root $SecurityRoot -MustExist -ForWrite -PathType Leaf
    $file = Get-Item -LiteralPath $safeFilePath -Force
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
  $manifestPath = Resolve-WorkflowContractPath -Candidate (Join-Path -Path $Root -ChildPath "Manifest.json") -Root $SecurityRoot -ForWrite -PathType Leaf
  Write-AtomicJson -Path $manifestPath -Value $manifest -Depth 8
  return $manifestPath
}

function Test-ArtifactSetUnchanged {
  param([array]$Records, [string]$Root)
  foreach ($record in $Records) {
    $path = [string](Get-JsonProperty -Object $record -Name "path")
    $expectedHash = [string](Get-JsonProperty -Object $record -Name "sha256")
    if (-not [string]::IsNullOrWhiteSpace($Root)) {
      try {
        $path = Resolve-WorkflowContractPath -Candidate $path -Root $Root -MustExist -ForWrite -PathType Leaf
      } catch {
        Stop-Finalization -Message "Prüfartefakt liegt nicht mehr als sichere reguläre Datei unter seinem Root vor: $path ($($_.Exception.Message))"
      }
    } elseif (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
      Stop-Finalization -Message "Prüfartefakt fehlt seit der Vorbereitung: $path"
    }
    $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($actualHash -ne $expectedHash) {
      Stop-Finalization -Message "Prüfartefakt wurde nach der Vorbereitung verändert; erneute Vorbereitung erforderlich: $path"
    }
  }
}

function Test-ArtifactSetExact {
  param(
    [array]$Records,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Folder,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$SecurityRoot,
    [string]$Filter = "*"
  )
  $Folder = Resolve-WorkflowContractPath -Candidate $Folder -Root $SecurityRoot -MustExist -ForWrite -PathType Container
  Test-ArtifactSetUnchanged -Records $Records -Root $Folder
  $recordPaths = @($Records | ForEach-Object {
    Resolve-WorkflowContractPath -Candidate ([string](Get-JsonProperty -Object $_ -Name "path")) -Root $Folder -MustExist -ForWrite -PathType Leaf
  })
  $currentPaths = @(Get-SafeFileSet -Folder $Folder -SecurityRoot $SecurityRoot -Filter $Filter | ForEach-Object { [System.IO.Path]::GetFullPath($_.FullName) })
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

function Test-NumberValue {
  param([object]$Value, [double]$Minimum = [double]::NegativeInfinity)

  if ($Value -isnot [byte] -and $Value -isnot [int16] -and $Value -isnot [int] -and
      $Value -isnot [long] -and $Value -isnot [single] -and $Value -isnot [double] -and
      $Value -isnot [decimal]) {
    return $false
  }
  $number = [double]$Value
  return (-not [double]::IsNaN($number) -and -not [double]::IsInfinity($number) -and $number -ge $Minimum)
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
  param([string]$Path, [int]$ExpectedWidth, [int]$ExpectedHeight)

  $png = Test-PngImage -LiteralPath $Path -ExpectedWidth $ExpectedWidth -ExpectedHeight $ExpectedHeight
  if (-not $png.valid) {
    Stop-Finalization -Message "Layoutnachweis ist kein vollständig auswertbares PNG: $Path ($($png.error))"
  }
}

function Assert-CurrentRuntimeFingerprint {
  param(
    [object]$Fingerprint,
    [string]$Context,
    [switch]$RequireBrowser
  )

  if ($null -eq $Fingerprint) {
    Stop-Finalization -Message "$Context enthält keinen Runtime-Fingerprint. Erneute Vorbereitung erforderlich."
  }
  $fingerprintSchema = Get-JsonProperty -Object $Fingerprint -Name "schemaVersion"
  if (($fingerprintSchema -isnot [int] -and $fingerprintSchema -isnot [long]) -or [int]$fingerprintSchema -ne 1) {
    Stop-Finalization -Message "$Context enthält keinen unterstützten Runtime-Fingerprint. Erneute Vorbereitung erforderlich."
  }
  $current = Get-RuntimeFingerprint
  foreach ($field in @("os", "architecture")) {
    $actual = [string](Get-JsonProperty -Object $Fingerprint -Name $field)
    $expected = [string](Get-JsonProperty -Object $current -Name $field)
    if ([string]::IsNullOrWhiteSpace($actual) -or $actual -cne $expected) {
      Stop-Finalization -Message "$Context wurde auf einer anderen Plattform oder Architektur erzeugt. Erneute Vorbereitung erforderlich."
    }
  }
  if ([string]$current.os -ceq "linux") {
    foreach ($field in @("distributionId", "distributionVersion", "wsl")) {
      if ([string](Get-JsonProperty -Object $Fingerprint -Name $field) -cne [string](Get-JsonProperty -Object $current -Name $field)) {
        Stop-Finalization -Message "$Context wurde in einer anderen Linux-Umgebung erzeugt. Erneute Vorbereitung erforderlich."
      }
    }
  }
  if ([string](Get-JsonProperty -Object $Fingerprint -Name "psEdition") -cne "Core" -or
      [string]::IsNullOrWhiteSpace([string](Get-JsonProperty -Object $Fingerprint -Name "powerShellVersion"))) {
    Stop-Finalization -Message "$Context enthält keinen gültigen PowerShell-Core-Fingerprint. Erneute Vorbereitung erforderlich."
  }
  if ($RequireBrowser) {
    $browserFingerprint = Get-JsonProperty -Object $Fingerprint -Name "browser"
    if ($null -eq $browserFingerprint -or
        [string]::IsNullOrWhiteSpace([string](Get-JsonProperty -Object $browserFingerprint -Name "name")) -or
        [string]::IsNullOrWhiteSpace([string](Get-JsonProperty -Object $browserFingerprint -Name "version")) -or
        [string]::IsNullOrWhiteSpace([string](Get-JsonProperty -Object $browserFingerprint -Name "executable"))) {
      Stop-Finalization -Message "$Context enthält keinen vollständigen Browser-Fingerprint. Erneute Vorbereitung erforderlich."
    }
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
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$CandidateFolder,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$LayoutFolder,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$WorkflowRoot
  )

  try {
    $LayoutReportPath = Resolve-WorkflowContractPath -Candidate $LayoutReportPath -Root $WorkflowRoot -MustExist -ForWrite -PathType Leaf
    $PdfReportPath = Resolve-WorkflowContractPath -Candidate $PdfReportPath -Root $WorkflowRoot -MustExist -ForWrite -PathType Leaf
    $AtsReportPath = Resolve-WorkflowContractPath -Candidate $AtsReportPath -Root $WorkflowRoot -MustExist -ForWrite -PathType Leaf
    $CandidateFolder = Resolve-WorkflowContractPath -Candidate $CandidateFolder -Root $WorkflowRoot -MustExist -ForWrite -PathType Container
    $LayoutFolder = Resolve-WorkflowContractPath -Candidate $LayoutFolder -Root $WorkflowRoot -MustExist -ForWrite -PathType Container
    $layout = Get-Content -LiteralPath $LayoutReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $pdf = Get-Content -LiteralPath $PdfReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $ats = Get-Content -LiteralPath $AtsReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
  } catch {
    Stop-Finalization -Message "Technischer Prüfbericht ist kein gültiges JSON: $($_.Exception.Message)"
  }

  Assert-CurrentRuntimeFingerprint -Fingerprint (Get-JsonProperty -Object $layout -Name "runtime") -Context "Layoutbericht" -RequireBrowser:($ExpectedHtmlCount -gt 0)
  Assert-CurrentRuntimeFingerprint -Fingerprint (Get-JsonProperty -Object $pdf -Name "runtime") -Context "PDF-Export-Bericht" -RequireBrowser:($ExpectedHtmlCount -gt 0)
  Assert-CurrentRuntimeFingerprint -Fingerprint (Get-JsonProperty -Object $ats -Name "runtime") -Context "ATS-Prüfbericht" -RequireBrowser:($ExpectedHtmlCount -gt 0)

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
  $layoutWidth = Get-JsonProperty -Object $layout -Name "pageWidth"
  $layoutHeight = Get-JsonProperty -Object $layout -Name "pageHeight"
  $layoutRatioValid = if ((Test-IntegerValue -Value $layoutWidth -Minimum 1) -and (Test-IntegerValue -Value $layoutHeight -Minimum 1)) {
    [math]::Abs(([double]$layoutWidth / [double]$layoutHeight) - (210.0 / 297.0)) -le 0.01
  } else {
    $false
  }
  $layoutResults = @((Get-JsonProperty -Object $layout -Name "results"))
  if (-not (Test-IntegerValue -Value $layoutSchema -Minimum 1) -or [int]$layoutSchema -ne 2 -or
      -not (Test-IntegerValue -Value $layoutScreenshotCount -Minimum 1) -or [int]$layoutScreenshotCount -ne $ScreenshotRecords.Count -or
      -not (Test-IntegerValue -Value $layoutWidth -Minimum 320) -or
      -not (Test-IntegerValue -Value $layoutHeight -Minimum 320) -or
      -not $layoutRatioValid -or
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
    try {
      $screenshotPath = Resolve-WorkflowContractPath `
        -Candidate ([string](Get-JsonProperty -Object $result -Name "screenshot")) `
        -Root $LayoutFolder `
        -MustExist `
        -ForWrite `
        -PathType Leaf
    } catch {
      Stop-Finalization -Message "Layoutbericht verweist auf keinen sicheren Screenshot unter dem Layoutordner: $($_.Exception.Message)"
    }
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
        [int](Get-JsonProperty -Object $result -Name "pageNumber") -gt [int](Get-JsonProperty -Object $result -Name "pageCount") -or
        -not (Test-IntegerValue -Value (Get-JsonProperty -Object $result -Name "bottomWhitespacePx") -Minimum 0) -or
        -not (Test-NumberValue -Value (Get-JsonProperty -Object $result -Name "bottomWhitespaceMm") -Minimum 0) -or
        -not (Test-NumberValue -Value (Get-JsonProperty -Object $result -Name "scanBottomReserveMm") -Minimum 0)) {
      Stop-Finalization -Message "Layoutbericht enthält einen ungültigen oder nicht hashgebundenen Seitennachweis."
    }
    $null = $layoutHtmlNames.Add($htmlName)
    Test-PngStructure -Path $screenshotPath -ExpectedWidth ([int]$layoutWidth) -ExpectedHeight ([int]$layoutHeight)
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
  if (-not (Test-IntegerValue -Value $atsSchema -Minimum 1) -or [int]$atsSchema -ne 2 -or
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
    $tokenCoverage = Get-JsonProperty -Object $result -Name "tokenCoveragePercent"
    $bigramCoverage = Get-JsonProperty -Object $result -Name "orderedBigramCoveragePercent"
    $trigramCoverage = Get-JsonProperty -Object $result -Name "orderedTrigramCoveragePercent"
    $tokenPassed = Get-JsonProperty -Object $result -Name "tokenComparisonPassed"
    if ([string](Get-JsonProperty -Object $result -Name "htmlSha256") -ine [string](Get-JsonProperty -Object $htmlRecord -Name "sha256") -or
        [string](Get-JsonProperty -Object $result -Name "pdfFile") -cne $pdfName -or
        [string](Get-JsonProperty -Object $result -Name "pdfSha256") -ine [string](Get-JsonProperty -Object $pdfRecord -Name "sha256") -or
        @(Get-JsonProperty -Object $result -Name "missingRequiredText").Count -ne 0 -or
        ($coverage -isnot [int] -and $coverage -isnot [long] -and $coverage -isnot [double] -and $coverage -isnot [decimal]) -or
        [double]$coverage -lt 70 -or
        ($tokenCoverage -isnot [double] -and $tokenCoverage -isnot [int] -and $tokenCoverage -isnot [long] -and $tokenCoverage -isnot [decimal]) -or
        ($bigramCoverage -isnot [double] -and $bigramCoverage -isnot [int] -and $bigramCoverage -isnot [long] -and $bigramCoverage -isnot [decimal]) -or
        ($trigramCoverage -isnot [double] -and $trigramCoverage -isnot [int] -and $trigramCoverage -isnot [long] -and $trigramCoverage -isnot [decimal]) -or
        $tokenPassed -isnot [bool] -or -not [bool]$tokenPassed -or
        -not (Test-IntegerValue -Value (Get-JsonProperty -Object $result -Name "extractedComparableCharacters") -Minimum 1) -or
        [string](Get-JsonProperty -Object $result -Name "extractionEngine") -cne "interner_tounicode_parser") {
      Stop-Finalization -Message "ATS-Prüfbericht ist nicht vollständig an HTML und PDF gebunden: $pdfName"
    }
  }
}

try {
  $workInputPath = Get-LexicalFullPath -Path $Arbeitsordner
  if (-not (Test-Path -LiteralPath $workInputPath -PathType Container)) {
    throw "Arbeitsordner fehlt oder ist kein Verzeichnis: $workInputPath"
  }
  $workFilesFolder = Split-Path -Path $workInputPath -Parent
  $companyFolder = Split-Path -Path $workFilesFolder -Parent
  $applicationsRootForWork = Split-Path -Path $companyFolder -Parent
  $privateRoot = Split-Path -Path $applicationsRootForWork -Parent
  if (-not [string]::Equals((Split-Path -Path $workFilesFolder -Leaf), "_Arbeitsdateien", $script:PathComparison) -or
      -not [string]::Equals((Split-Path -Path $applicationsRootForWork -Leaf), "Bewerbungen", $script:PathComparison) -or
      -not [string]::Equals((Split-Path -Path $privateRoot -Leaf), "Private", $script:PathComparison)) {
    throw "Arbeitsordner muss unter Private/Bewerbungen/<Firma>/_Arbeitsdateien liegen: $workInputPath"
  }
  $applicationsRootForWork = Resolve-WorkflowContractPath `
    -Candidate $applicationsRootForWork `
    -Root $applicationsRootForWork `
    -AllowRoot `
    -MustExist `
    -ForWrite `
    -PathType Container
  $companyDir = Resolve-WorkflowContractPath -Candidate $companyFolder -Root $applicationsRootForWork -MustExist -ForWrite -PathType Container
  $resolvedWork = Resolve-WorkflowContractPath -Candidate $workInputPath -Root $applicationsRootForWork -MustExist -ForWrite -PathType Container
} catch {
  Write-Host "[FEHLER] Unsicherer Arbeitsordner: $($_.Exception.Message)" -ForegroundColor Red
  exit 2
}

try {
  $auftragPath = Resolve-WorkflowContractPath -Candidate (Join-Path -Path $resolvedWork -ChildPath "Bewerbungsauftrag.json") -Root $applicationsRootForWork -MustExist -ForWrite -PathType Leaf
  $matrixPath = Resolve-WorkflowContractPath -Candidate (Join-Path -Path $resolvedWork -ChildPath "Anforderungsmatrix.json") -Root $applicationsRootForWork -MustExist -ForWrite -PathType Leaf
  $candidateDir = Resolve-WorkflowContractPath -Candidate (Join-Path -Path $resolvedWork -ChildPath "Kandidat") -Root $applicationsRootForWork -MustExist -ForWrite -PathType Container
  $layoutDir = Resolve-WorkflowContractPath -Candidate (Join-Path -Path $resolvedWork -ChildPath "Layoutcheck") -Root $applicationsRootForWork -ForWrite -PathType Container
  $pdfWorkDir = Resolve-WorkflowContractPath -Candidate (Join-Path -Path $resolvedWork -ChildPath "PDF-Export") -Root $applicationsRootForWork -ForWrite -PathType Container
  $layoutReportPath = Resolve-WorkflowContractPath -Candidate (Join-Path -Path $layoutDir -ChildPath "Layoutcheck-Bericht.json") -Root $applicationsRootForWork -ForWrite -PathType Leaf
  $pdfReportPath = Resolve-WorkflowContractPath -Candidate (Join-Path -Path $pdfWorkDir -ChildPath "PDF-Export-Bericht.json") -Root $applicationsRootForWork -ForWrite -PathType Leaf
  $atsReportPath = Resolve-WorkflowContractPath -Candidate (Join-Path -Path $resolvedWork -ChildPath "ATS-Pruefbericht.json") -Root $applicationsRootForWork -ForWrite -PathType Leaf
  $finalReportPath = Resolve-WorkflowContractPath -Candidate (Join-Path -Path $resolvedWork -ChildPath "Finalisierungsbericht.json") -Root $applicationsRootForWork -ForWrite -PathType Leaf
  $tokenReportPath = Resolve-WorkflowContractPath -Candidate (Join-Path -Path $resolvedWork -ChildPath "Tokenverbrauch.json") -Root $applicationsRootForWork -ForWrite -PathType Leaf
  $stammdatenReportPath = Resolve-WorkflowContractPath -Candidate (Join-Path -Path $resolvedWork -ChildPath "Stammdaten-Pruefbericht.json") -Root $applicationsRootForWork -ForWrite -PathType Leaf
  $contentReportPath = Resolve-WorkflowContractPath -Candidate (Join-Path -Path $resolvedWork -ChildPath "Inhalts-Pruefbericht.json") -Root $applicationsRootForWork -ForWrite -PathType Leaf
  $checkStatePath = Resolve-WorkflowContractPath -Candidate (Join-Path -Path $resolvedWork -ChildPath "Pruefstand.json") -Root $applicationsRootForWork -ForWrite -PathType Leaf
  $qualityPath = Resolve-WorkflowContractPath -Candidate (Join-Path -Path $candidateDir -ChildPath "Qualitaetscheck.md") -Root $applicationsRootForWork -MustExist -ForWrite -PathType Leaf
} catch {
  Write-Host "[FEHLER] Unsicherer Workflowpfad: $($_.Exception.Message)" -ForegroundColor Red
  exit 2
}

foreach ($requiredFile in @($auftragPath, $matrixPath, $StammdatenPath, $ProfilPath)) {
  if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
    Stop-Finalization -Message "Erforderliche reguläre Datei fehlt: $requiredFile"
  }
}
if (-not (Test-Path -LiteralPath $candidateDir -PathType Container)) {
  Stop-Finalization -Message "Erforderlicher Kandidatenordner fehlt: $candidateDir"
}

$auftrag = Get-Content -LiteralPath $auftragPath -Raw -Encoding UTF8 | ConvertFrom-Json
$documentScope = Get-DocumentScope -Auftrag $auftrag
$matrixForFinalization = Get-Content -LiteralPath $matrixPath -Raw -Encoding UTF8 | ConvertFrom-Json
$matrixContractInfoForFinalization = Get-MatrixContractInfo -Matrix $matrixForFinalization
$matrixSchemaForFinalization = [int]$matrixContractInfoForFinalization.schemaVersion
$evidenceIndexPath = Resolve-WorkflowContractPath -Candidate (Join-Path -Path $resolvedWork -ChildPath 'Evidenzindex.json') -Root $applicationsRootForWork -ForWrite -PathType Leaf
$expectedCv = [string]$documentScope.lebenslauf -ne "nicht_enthalten"
$expectedLetter = [bool]$documentScope.anschreiben
$expectedEmail = [bool]$documentScope.emailNachricht
$expectedHtmlCount = [int]$expectedCv + [int]$expectedLetter
$passfotoSource = $null
if ([string]$documentScope.lebenslauf -eq 'individuell') {
  try {
    $dataRoot = Resolve-SafePath -Candidate (Join-Path -Path $privateRoot -ChildPath 'Daten') -Root $privateRoot -MustExist -PathType Container
    $passfotoSource = Get-PassfotoSourceState -DataRoot $dataRoot
  } catch {
    Stop-Finalization -Message "Passfoto-Quelle ist ungültig oder unsicher: $($_.Exception.Message)"
  }
}
try {
  $orderPaths = Resolve-BewerbungsauftragPathSet -Auftrag $auftrag -Arbeitsordner $resolvedWork -BewerbungenRoot $applicationsRootForWork
} catch {
  Stop-Finalization -Message "Auftragspfade sind nicht sicher auflösbar: $($_.Exception.Message)"
}
$targetDir = [string]$orderPaths.ZielOrdner
$manifestCandidate = $orderPaths.KandidatOrdner
try {
  $expectedTarget = Resolve-WorkflowContractPath `
    -Candidate (Join-Path -Path $companyDir -ChildPath (Split-Path -Path $resolvedWork -Leaf)) `
    -Root $applicationsRootForWork `
    -ForWrite `
    -PathType Container
} catch {
  Stop-Finalization -Message "Finaler Zielordner ist nicht sicher beschreibbar: $($_.Exception.Message)"
}
if (-not (Test-LexicalPathEqual -Left $manifestCandidate -Right $candidateDir)) {
  Stop-Finalization -Message "Kandidatenordner stimmt nicht mit dem Bewerbungsauftrag überein."
}
if (-not (Test-LexicalPathEqual -Left $targetDir -Right $expectedTarget)) {
  Stop-Finalization -Message "Zielordner stimmt nicht mit der sicheren Projektstruktur überein."
}
$targetDir = $expectedTarget

$stammdatenTool = Join-Path -Path $PSScriptRoot -ChildPath "Pruefe-Stammdaten.ps1"
$staticTool = Join-Path -Path $PSScriptRoot -ChildPath "Pruefe-Bewerbung.ps1"
$contentTool = Join-Path -Path $PSScriptRoot -ChildPath "Pruefe-Bewerbungsinhalt.ps1"
$layoutTool = Join-Path -Path $PSScriptRoot -ChildPath "Layoutcheck-Bewerbung.ps1"
$exportTool = Join-Path -Path $PSScriptRoot -ChildPath "Exportiere-PDF.ps1"
$atsTool = Join-Path -Path $PSScriptRoot -ChildPath "Pruefe-ATS.ps1"
$tokenReportTool = Join-Path -Path $PSScriptRoot -ChildPath "Aktualisiere-Tokenbericht.ps1"
$dialogTool = Join-Path -Path $PSScriptRoot -ChildPath "Pruefe-Dialogstatus.ps1"
$script:CheckStatePath = $checkStatePath
$script:CheckState = Read-FinalizationCheckState -Path $checkStatePath
$script:StageRuns = [System.Collections.Generic.List[object]]::new()
$script:CacheImplementationFiles = @(
  $PSCommandPath,
  $dialogTool, $stammdatenTool, $staticTool, $contentTool, $layoutTool, $exportTool, $atsTool,
  (Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Common') -Filter '*.psm1' -File | Select-Object -ExpandProperty FullName)
)

if (-not $Veroeffentlichen) {
  Add-Info "Finalisierung wird vorbereitet: $resolvedWork"
  $baseRuntime = Get-RuntimeFingerprint
  Invoke-FinalizationStage -Stage dialog -InputFiles @($auftragPath, $StammdatenPath, $ProfilPath) -Parameters @{ fuerDokumenterstellung = 'true' } -Runtime $baseRuntime -Action {
    Invoke-ChildTool -ScriptPath $dialogTool -Arguments @("-AuftragPath", $auftragPath, "-StammdatenPath", $StammdatenPath, "-ProfilPath", $ProfilPath, "-FuerDokumenterstellung")
  } | Out-Null
  $stammdatenReportPath = Resolve-WorkflowContractPath -Candidate $stammdatenReportPath -Root $applicationsRootForWork -ForWrite -PathType Leaf
  Invoke-FinalizationStage -Stage stammdaten -InputFiles @($auftragPath, $StammdatenPath) -OutputFiles @($stammdatenReportPath) -Parameters @{ ungeklAerteLogistikAlsFehler = 'true' } -Runtime $baseRuntime -Action {
    Invoke-ChildTool -ScriptPath $stammdatenTool -Arguments @("-StammdatenPath", $StammdatenPath, "-BewerbungsauftragPath", $auftragPath, "-UngeklaerteLogistikAlsFehler", "-BerichtPath", $stammdatenReportPath)
  } | Out-Null
  Invoke-FinalizationStage -Stage statisch -InputFiles @($auftragPath, (Get-SafeFileSet -Folder $candidateDir -SecurityRoot $applicationsRootForWork | Select-Object -ExpandProperty FullName)) -Parameters @{} -Runtime $baseRuntime -Action {
    Invoke-ChildTool -ScriptPath $staticTool -Arguments @("-Ordner", $candidateDir, "-AuftragPath", $auftragPath)
  } | Out-Null
  $contentReportPath = Resolve-WorkflowContractPath -Candidate $contentReportPath -Root $applicationsRootForWork -ForWrite -PathType Leaf
  $contentInputs = @($auftragPath, $StammdatenPath, $ProfilPath, $matrixPath) + @(Get-SafeFileSet -Folder $candidateDir -SecurityRoot $applicationsRootForWork | Select-Object -ExpandProperty FullName)
  if (Test-Path -LiteralPath $evidenceIndexPath -PathType Leaf) { $contentInputs += $evidenceIndexPath }
  Invoke-FinalizationStage -Stage inhalt -InputFiles $contentInputs -OutputFiles @($contentReportPath) -Parameters @{} -Runtime $baseRuntime -Action {
    Invoke-ChildTool -ScriptPath $contentTool -Arguments @("-Ordner", $candidateDir, "-StammdatenPath", $StammdatenPath, "-ProfilPath", $ProfilPath, "-AuftragPath", $auftragPath, "-AnforderungsmatrixPath", $matrixPath, "-EvidenzindexPath", $evidenceIndexPath, "-BerichtPath", $contentReportPath)
  } | Out-Null
  if ($expectedHtmlCount -gt 0) {
    $browserPathArguments = if ([string]::IsNullOrWhiteSpace($BrowserExecutablePath)) { @() } else { @("-BrowserExecutablePath", $BrowserExecutablePath) }
    $layoutDir = Resolve-WorkflowContractPath -Candidate $layoutDir -Root $applicationsRootForWork -ForWrite -PathType Container
    $layoutReportPath = Resolve-WorkflowContractPath -Candidate $layoutReportPath -Root $applicationsRootForWork -ForWrite -PathType Leaf
    $browserInfo = Resolve-BrowserExecutable -RequestedBrowser $Browser -ExecutablePath $BrowserExecutablePath -RequireChromium
    $browserRuntime = Get-RuntimeFingerprint -BrowserInfo $browserInfo
    $htmlInputs = @(Get-SafeFileSet -Folder $candidateDir -SecurityRoot $applicationsRootForWork -Filter '*.html' | Select-Object -ExpandProperty FullName)
    Invoke-FinalizationStage -Stage layout -InputFiles $htmlInputs -OutputFiles @($layoutReportPath) -Parameters @{ browser = $browserInfo.Name; browserVersion = $browserInfo.Version; timeoutSeconds = "$TimeoutSeconds" } -Runtime $browserRuntime -Action {
      Invoke-ChildTool -ScriptPath $layoutTool -Arguments @(@("-Ordner", $candidateDir, "-Browser", $Browser, "-TimeoutSeconds", "$TimeoutSeconds", "-OutputRoot", $layoutDir, "-BerichtPath", $layoutReportPath) + $browserPathArguments)
    } | Out-Null
    $layoutOutputs = @(Get-SafeFileSet -Folder $layoutDir -SecurityRoot $applicationsRootForWork -Filter '*.png' | Select-Object -ExpandProperty FullName)
    if ($layoutOutputs.Count -gt 0) {
      # Persist the complete screenshot set after the layout report exists.
      $layoutEntry = @($script:CheckState.stages | Where-Object { [string]$_.id -eq 'layout' } | Select-Object -First 1)
      if ($layoutEntry.Count -eq 1 -and @($layoutEntry[0].outputs).Count -lt 2) {
        $fingerprint = Get-FinalizationStageFingerprint -Stage layout -Root $resolvedWork -ImplementationFiles $script:CacheImplementationFiles -InputFiles $htmlInputs -Parameters @{ browser = $browserInfo.Name; browserVersion = $browserInfo.Version; timeoutSeconds = "$TimeoutSeconds" } -Runtime $browserRuntime -DependencyKeys @()
        Save-FinalizationStageResult -Path $script:CheckStatePath -Root $resolvedWork -Stage layout -Fingerprint $fingerprint -OutputFiles @($layoutReportPath + $layoutOutputs) -DurationMs 0
        $script:CheckState = Read-FinalizationCheckState -Path $script:CheckStatePath
      }
    }
    $pdfWorkDir = Resolve-WorkflowContractPath -Candidate $pdfWorkDir -Root $applicationsRootForWork -ForWrite -PathType Container
    $pdfReportPath = Resolve-WorkflowContractPath -Candidate $pdfReportPath -Root $applicationsRootForWork -ForWrite -PathType Leaf
    Invoke-FinalizationStage -Stage pdf -InputFiles @($auftragPath + $htmlInputs + @($layoutReportPath) + $layoutOutputs) -OutputFiles @($pdfReportPath) -Parameters @{ browser = $browserInfo.Name; browserVersion = $browserInfo.Version; timeoutSeconds = "$TimeoutSeconds" } -Runtime $browserRuntime -Action {
      Invoke-ChildTool -ScriptPath $exportTool -Arguments @(@("-Ordner", $candidateDir, "-AuftragPath", $auftragPath, "-Browser", $Browser, "-TimeoutSeconds", "$TimeoutSeconds", "-OutputRoot", $pdfWorkDir, "-BerichtPath", $pdfReportPath) + $browserPathArguments)
    } | Out-Null
    $pdfOutputs = @(Get-SafeFileSet -Folder $candidateDir -SecurityRoot $applicationsRootForWork -Filter '*.pdf' | Select-Object -ExpandProperty FullName)
    $pdfEntry = @($script:CheckState.stages | Where-Object { [string]$_.id -eq 'pdf' } | Select-Object -First 1)
    if ($pdfEntry.Count -eq 1 -and @($pdfEntry[0].outputs).Count -lt 2) {
      $fingerprint = Get-FinalizationStageFingerprint -Stage pdf -Root $resolvedWork -ImplementationFiles $script:CacheImplementationFiles -InputFiles @($auftragPath + $htmlInputs + @($layoutReportPath) + $layoutOutputs) -Parameters @{ browser = $browserInfo.Name; browserVersion = $browserInfo.Version; timeoutSeconds = "$TimeoutSeconds" } -Runtime $browserRuntime -DependencyKeys @()
      Save-FinalizationStageResult -Path $script:CheckStatePath -Root $resolvedWork -Stage pdf -Fingerprint $fingerprint -OutputFiles @($pdfReportPath + $pdfOutputs) -DurationMs 0
      $script:CheckState = Read-FinalizationCheckState -Path $script:CheckStatePath
    }
    $atsReportPath = Resolve-WorkflowContractPath -Candidate $atsReportPath -Root $applicationsRootForWork -ForWrite -PathType Leaf
    $pdfReportPath = Resolve-WorkflowContractPath -Candidate $pdfReportPath -Root $applicationsRootForWork -MustExist -ForWrite -PathType Leaf
    Invoke-FinalizationStage -Stage ats -InputFiles @($auftragPath, $StammdatenPath, $pdfReportPath) + $pdfOutputs -OutputFiles @($atsReportPath) -Parameters @{} -Runtime $browserRuntime -Action {
      Invoke-ChildTool -ScriptPath $atsTool -Arguments @("-Ordner", $candidateDir, "-StammdatenPath", $StammdatenPath, "-AuftragPath", $auftragPath, "-BerichtPath", $atsReportPath, "-PdfExportBerichtPath", $pdfReportPath)
    } | Out-Null
  } else {
    Write-NotRequiredReport -Path $layoutReportPath -Kind "layoutcheck" -WorkflowRoot $applicationsRootForWork
    Write-NotRequiredReport -Path $pdfReportPath -Kind "pdf_export" -WorkflowRoot $applicationsRootForWork
    Write-NotRequiredReport -Path $atsReportPath -Kind "ats_pdf" -WorkflowRoot $applicationsRootForWork
  }

  $layoutReportPath = Resolve-WorkflowContractPath -Candidate $layoutReportPath -Root $applicationsRootForWork -MustExist -ForWrite -PathType Leaf
  $layoutWarnings = @(Get-LayoutWarnings -Path $layoutReportPath)
  Update-TechnicalSection -QualityPath $qualityPath -WorkflowRoot $applicationsRootForWork -State "vorbereitet" -LayoutReportPath $layoutReportPath -PdfReportPath $pdfReportPath -AtsReportPath $atsReportPath -LayoutWarnings $layoutWarnings -VisualApprovalNote "" -HtmlDocumentCount $expectedHtmlCount
  $artifacts = Get-ReportArtifacts -CandidateFolder $candidateDir -LayoutFolder $layoutDir -WorkflowRoot $applicationsRootForWork
  $expectedScreenshots = Get-ExpectedScreenshotCount -CandidateFolder $candidateDir -WorkflowRoot $applicationsRootForWork
  if ($artifacts.html.Count -ne $expectedHtmlCount -or $artifacts.pdf.Count -ne $expectedHtmlCount -or $artifacts.screenshots.Count -ne $expectedScreenshots) {
    Stop-Finalization -Message "Vorbereitung erzeugte nicht die laut Dokumentumfang erwarteten $expectedHtmlCount HTML-/PDF-Dateien und einen Screenshot pro A4-Seite (Screenshots erwartet: $expectedScreenshots, erzeugt: $($artifacts.screenshots.Count))."
  }
  Test-TechnicalReportContracts `
    -LayoutReportPath $layoutReportPath `
    -PdfReportPath $pdfReportPath `
    -AtsReportPath $atsReportPath `
    -ExpectedHtmlCount $expectedHtmlCount `
    -HtmlRecords $artifacts.html `
    -PdfRecords $artifacts.pdf `
    -ScreenshotRecords $artifacts.screenshots `
    -CandidateFolder $candidateDir `
    -LayoutFolder $layoutDir `
    -WorkflowRoot $applicationsRootForWork
  $tokenUsageReference = Update-TokenReportNonBlocking -ScriptPath $tokenReportTool -WorkFolder $resolvedWork -ReportPath $tokenReportPath -WorkflowRoot $applicationsRootForWork
  $layoutReportPath = Resolve-WorkflowContractPath -Candidate $layoutReportPath -Root $applicationsRootForWork -MustExist -ForWrite -PathType Leaf
  $layoutRuntime = (Get-Content -LiteralPath $layoutReportPath -Raw -Encoding UTF8 | ConvertFrom-Json).runtime
  $preparedSourceInputs = [ordered]@{
    stammdaten = Get-ArtifactRecord -File (Get-Item -LiteralPath $StammdatenPath)
    profil = Get-ArtifactRecord -File (Get-Item -LiteralPath $ProfilPath)
    bewerbungsauftrag = Get-ArtifactRecord -File (Get-Item -LiteralPath $auftragPath) -Root $applicationsRootForWork
    anforderungsmatrix = Get-ArtifactRecord -File (Get-Item -LiteralPath $matrixPath) -Root $applicationsRootForWork
  }
  if ($matrixContractInfoForFinalization.requiresAnschreibenStrategie) {
    if (-not (Test-Path -LiteralPath $evidenceIndexPath -PathType Leaf)) {
      Stop-Finalization -Message "Schema-5-Bewerbung benötigt Evidenzindex.json als gebundene Quelle."
    }
    try {
      $evidenceIndexForFinalization = Get-Content -LiteralPath $evidenceIndexPath -Raw -Encoding UTF8 | ConvertFrom-Json
      if ((Get-EvidenceIndexSchemaVersion -Index $evidenceIndexForFinalization) -ne 1) {
        Stop-Finalization -Message "Evidenzindex verwendet nicht die aktuelle Schema-1-Struktur."
      }
    } catch {
      Stop-Finalization -Message "Evidenzindex kann vor der Hashbindung nicht vertragsgemäß gelesen werden: $($_.Exception.Message)"
    }
    $preparedSourceInputs.evidenzindex = Get-ArtifactRecord -File (Get-Item -LiteralPath $evidenceIndexPath) -Root $applicationsRootForWork
  }
  if ($null -ne $passfotoSource -and $passfotoSource.Exists) {
    $preparedSourceInputs.passfoto = Get-ArtifactRecord -File (Get-Item -LiteralPath $passfotoSource.Path)
  }
  $report = [ordered]@{
    schemaVersion = 7
    status = "bereit_zur_sichtpruefung"
    preparedAtUtc = [datetime]::UtcNow.ToString("o")
    runtime = $layoutRuntime
    workFolder = $resolvedWork
    candidateFolder = $candidateDir
    targetFolder = $targetDir
    layoutReport = $layoutReportPath
    layoutReportArtifact = Get-ArtifactRecord -File (Get-Item -LiteralPath $layoutReportPath) -Root $applicationsRootForWork
    pdfReport = $pdfReportPath
    pdfReportArtifact = Get-ArtifactRecord -File (Get-Item -LiteralPath $pdfReportPath) -Root $applicationsRootForWork
    atsReport = $atsReportPath
    atsReportArtifact = Get-ArtifactRecord -File (Get-Item -LiteralPath $atsReportPath) -Root $applicationsRootForWork
    expectedScreenshots = $expectedScreenshots
    documentScope = $documentScope
    personalReview = if ($expectedScreenshots -gt 0) { "png_sichtpruefung" } else { "textpruefung" }
    layoutWarnings = $layoutWarnings
    tokenUsageReport = $tokenUsageReference
    stageOrder = @(Get-FinalizationStageOrder)
    stageRuns = @($script:StageRuns.ToArray())
    sourceInputs = $preparedSourceInputs
    artifacts = $artifacts
  }
  $approvalRecords = @(Get-ContractApprovalRecords -Report $report)
  $report.approvalRequest = [ordered]@{
    approvalId = New-ContractApprovalId
    reviewKind = $report.personalReview
    artifactSetSha256 = Get-ContractArtifactSetHash -Records $approvalRecords
    artifactCount = $approvalRecords.Count
    createdAtUtc = [datetime]::UtcNow.ToString("o")
  }
  $finalReportPath = Resolve-WorkflowContractPath -Candidate $finalReportPath -Root $applicationsRootForWork -ForWrite -PathType Leaf
  Write-AtomicJson -Path $finalReportPath -Value $report -Depth 10
  Update-WorkflowCheckpointNonBlocking -WorkFolder $resolvedWork -Step 'technische_vorbereitung_abgeschlossen'
  Add-Ok "Technische Vorbereitung erfolgreich."
  Write-Host ""
  if ($expectedScreenshots -gt 0) {
    Write-Host "Öffne jetzt die Screenshots unter: $layoutDir"
  } else {
    Write-Host "Der Umfang enthält kein HTML-Dokument. Prüfe die ausgewählten Textdateien im Kandidatenordner persönlich: $candidateDir"
  }
  if ($layoutWarnings.Count -gt 0) {
    Write-Host "Layoutwarnungen müssen visuell bewertet und in der Chat-bestätigten Freigabe mit einer konkreten Notiz begründet werden."
  }
  Write-Host "Nach bestätigter Sichtprüfung die Freigabe-ID im Chat bestätigen und anschließend speichern:"
  Write-Host ".\Tools\bewerbung.ps1 freigabe --arbeitsordner `"$resolvedWork`" --freigabe-id $($report.approvalRequest.approvalId) --bestaetigt"
  exit 0
}

try {
  $finalReportPath = Resolve-WorkflowContractPath -Candidate $finalReportPath -Root $applicationsRootForWork -MustExist -ForWrite -PathType Leaf
} catch {
  Stop-Finalization -Message "Finalisierungsbericht fehlt oder ist kein sicheres reguläres Artefakt. Zuerst erneut vorbereiten: $($_.Exception.Message)"
}
$preparedReportJson = Get-Content -LiteralPath $finalReportPath -Raw -Encoding UTF8
$report = $preparedReportJson | ConvertFrom-Json
$reportSchemaValue = Get-JsonProperty -Object $report -Name "schemaVersion"
if (($reportSchemaValue -isnot [int] -and $reportSchemaValue -isnot [long]) -or [int]$reportSchemaValue -notin @(6, 7)) {
  Stop-Finalization -Message "Finalisierungsbericht verwendet kein unterstütztes Freigabeschema 6 oder 7."
}
$reportSchema = [int]$reportSchemaValue
foreach ($requiredReportProperty in @("status", "runtime", "workFolder", "candidateFolder", "targetFolder", "documentScope", "personalReview", "expectedScreenshots", "layoutWarnings", "layoutReport", "layoutReportArtifact", "pdfReport", "pdfReportArtifact", "atsReport", "atsReportArtifact", "sourceInputs", "artifacts")) {
  if (-not (Test-JsonPropertyExists -Object $report -Name $requiredReportProperty)) {
    Stop-Finalization -Message "Finalisierungsbericht ist unvollständig; Pflichtfeld fehlt: $requiredReportProperty. Erneute Vorbereitung erforderlich."
  }
}
$approvalPath = Resolve-WorkflowContractPath -Candidate (Join-Path $resolvedWork "Sichtfreigabe.json") -Root $applicationsRootForWork -MustExist -ForWrite -PathType Leaf
try {
  $approval = Read-ContractJson -Path $approvalPath
  if ([int](Get-ContractJsonProperty $approval 'schemaVersion') -ne 1 -or [string](Get-ContractJsonProperty $approval 'kind') -cne 'sichtfreigabe' -or
      (Get-ContractJsonProperty $approval 'humanConfirmation') -isnot [bool] -or -not [bool](Get-ContractJsonProperty $approval 'humanConfirmation')) {
    throw 'Sichtfreigabe besitzt kein gültiges bestätigtes Schema.'
  }
  $request = Get-ContractJsonProperty $report 'approvalRequest'
  if ($null -eq $request -or [string](Get-ContractJsonProperty $approval 'approvalId') -cne [string](Get-ContractJsonProperty $request 'approvalId') -or
      [string](Get-ContractJsonProperty $approval 'artifactSetSha256') -cne [string](Get-ContractJsonProperty $request 'artifactSetSha256')) {
    throw 'Sichtfreigabe ist nicht an die aktuelle Freigabe-ID oder den aktuellen Artefaktsatz gebunden.'
  }
  $approvalReport = Get-ContractJsonProperty $approval 'preparedReport'
  if ([string](Get-ContractJsonProperty $approvalReport 'sha256') -ine (Get-FileHash -LiteralPath $finalReportPath -Algorithm SHA256).Hash) { throw 'Sichtfreigabe gehört nicht zum aktuellen Finalisierungsbericht.' }
  $approvalRecords = @(Get-ContractApprovalRecords -Report $report)
  Test-ContractArtifactRecordsCurrent -Records $approvalRecords -Root $resolvedWork
  if ((Get-ContractArtifactSetHash -Records $approvalRecords) -cne [string](Get-ContractJsonProperty $approval 'artifactSetSha256')) { throw 'Artefaktsatz wurde seit der Sichtfreigabe verändert.' }
  $boundApprovalRecords = @(Get-ContractJsonProperty $approval 'artifacts')
  if ($boundApprovalRecords.Count -ne $approvalRecords.Count) { throw 'Sichtfreigabe enthält nicht genau den vorbereiteten Artefaktsatz.' }
  Test-ContractArtifactRecordsCurrent -Records $boundApprovalRecords -Root $resolvedWork
  $boundRecordsForHash = @($boundApprovalRecords | ForEach-Object {
    $boundPath = [string](Get-ContractJsonProperty $_ 'path')
    $absoluteBoundPath = if ([IO.Path]::IsPathRooted($boundPath)) { [IO.Path]::GetFullPath($boundPath) } else { [IO.Path]::GetFullPath((Join-Path $resolvedWork $boundPath)) }
    $normalized = [ordered]@{ path = $absoluteBoundPath; bytes = Get-ContractJsonProperty $_ 'bytes'; sha256 = Get-ContractJsonProperty $_ 'sha256' }
    $normalized
  })
  if ((Get-ContractArtifactSetHash -Records $boundRecordsForHash) -cne [string](Get-ContractJsonProperty $approval 'artifactSetSha256')) { throw 'Sichtfreigabe-Artefakthashes stimmen nicht mit dem gebundenen Satz überein.' }
  $normalizedVisualNote = [regex]::Replace(([string](Get-ContractJsonProperty $approval 'note')).Trim(), '\s+', ' ')
} catch {
  Stop-Finalization -Message "Sichtfreigabe fehlt, ist veraltet oder nicht an den aktuellen Artefaktsatz gebunden: $($_.Exception.Message)"
}
Assert-CurrentRuntimeFingerprint -Fingerprint (Get-JsonProperty -Object $report -Name "runtime") -Context "Finalisierungsbericht" -RequireBrowser:($expectedHtmlCount -gt 0)
if ([string](Get-JsonProperty -Object $report -Name "status") -ne "bereit_zur_sichtpruefung") {
  Stop-Finalization -Message "Finalisierungsbericht befindet sich nicht im veröffentlichbaren Zustand."
}
if (-not (Test-LexicalPathEqual -Left ([string](Get-JsonProperty -Object $report -Name "workFolder")) -Right $resolvedWork) -or
    -not (Test-LexicalPathEqual -Left ([string](Get-JsonProperty -Object $report -Name "candidateFolder")) -Right $candidateDir) -or
    -not (Test-LexicalPathEqual -Left ([string](Get-JsonProperty -Object $report -Name "targetFolder")) -Right $targetDir)) {
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
$currentExpectedScreenshots = Get-ExpectedScreenshotCount -CandidateFolder $candidateDir -WorkflowRoot $applicationsRootForWork
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
  if (-not (Test-LexicalPathEqual -Left $reportedPath -Right $expectedTechnicalReports[$technicalReportName]) -or
      -not (Test-LexicalPathEqual -Left $artifactPath -Right $expectedTechnicalReports[$technicalReportName])) {
    Stop-Finalization -Message "Technischer Berichtspfad stimmt nicht mit dem vorbereiteten Arbeitsordner überein: $technicalReportName"
  }
  Test-ArtifactSetUnchanged -Records @($reportArtifact) -Root $applicationsRootForWork
}
$layoutReportPath = Resolve-WorkflowContractPath -Candidate $layoutReportPath -Root $applicationsRootForWork -MustExist -ForWrite -PathType Leaf
$currentLayoutWarnings = @(Get-LayoutWarnings -Path $layoutReportPath)
if ([string]::Join([char]0x1F, [string[]]$reportLayoutWarnings) -cne [string]::Join([char]0x1F, [string[]]$currentLayoutWarnings)) {
  Stop-Finalization -Message "Layoutwarnungen stimmen nicht mehr mit dem vorbereiteten Layoutbericht überein. Erneute Vorbereitung erforderlich."
}
if ($reportLayoutWarnings.Count -gt 0 -and [string]::IsNullOrWhiteSpace($normalizedVisualNote)) {
  Stop-Finalization -Message "Automatische Layoutwarnungen liegen vor. Die Chat-bestätigte Sichtfreigabe muss eine konkrete Notiz enthalten."
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
Test-ArtifactSetExact -Records $candidateArtifactRecords -Folder $candidateDir -SecurityRoot $applicationsRootForWork
Test-ArtifactSetExact -Records $htmlArtifactRecords -Folder $candidateDir -SecurityRoot $applicationsRootForWork -Filter "*.html"
Test-ArtifactSetExact -Records $pdfArtifactRecords -Folder $candidateDir -SecurityRoot $applicationsRootForWork -Filter "*.pdf"
Test-ArtifactSetExact -Records $screenshotRecords -Folder $layoutDir -SecurityRoot $applicationsRootForWork -Filter "*.png"
Test-TechnicalReportContracts `
  -LayoutReportPath $layoutReportPath `
  -PdfReportPath $pdfReportPath `
  -AtsReportPath $atsReportPath `
  -ExpectedHtmlCount $expectedHtmlCount `
  -HtmlRecords $htmlArtifactRecords `
  -PdfRecords $pdfArtifactRecords `
  -ScreenshotRecords $screenshotRecords `
  -CandidateFolder $candidateDir `
  -LayoutFolder $layoutDir `
  -WorkflowRoot $applicationsRootForWork
$sourceInputs = Get-JsonProperty -Object $report -Name "sourceInputs"
$expectedSourcePaths = [ordered]@{
  stammdaten = [System.IO.Path]::GetFullPath($StammdatenPath)
  profil = [System.IO.Path]::GetFullPath($ProfilPath)
  bewerbungsauftrag = [System.IO.Path]::GetFullPath($auftragPath)
  anforderungsmatrix = [System.IO.Path]::GetFullPath($matrixPath)
}
if ($matrixSchemaForFinalization -ge 5) {
  $expectedSourcePaths.evidenzindex = [System.IO.Path]::GetFullPath($evidenceIndexPath)
}
if ($null -ne $passfotoSource -and $passfotoSource.Exists) {
  $expectedSourcePaths.passfoto = [System.IO.Path]::GetFullPath([string]$passfotoSource.Path)
}
$sourceProperties = @($sourceInputs.PSObject.Properties)
$actualSourceNames = @($sourceProperties.Name | Sort-Object)
if ($sourceProperties.Count -ne $expectedSourcePaths.Count -or
    @(Compare-Object -ReferenceObject @($expectedSourcePaths.Keys | Sort-Object) -DifferenceObject $actualSourceNames).Count -gt 0) {
  Stop-Finalization -Message "Finalisierungsbericht enthält nicht exakt die aktuell erforderlichen Quellnachweise einschließlich des optionalen Passfotos. Erneute Vorbereitung erforderlich."
}
foreach ($sourceName in $expectedSourcePaths.Keys) {
  $sourceRecord = $sourceInputs.PSObject.Properties[$sourceName].Value
  $preparedSourcePath = [System.IO.Path]::GetFullPath([string](Get-JsonProperty -Object $sourceRecord -Name "path"))
  if (-not (Test-PathEqual -Left $preparedSourcePath -Right $expectedSourcePaths[$sourceName])) {
    Stop-Finalization -Message "Beim Veröffentlichungslauf wurde eine andere Quelldatei übergeben: $sourceName"
  }
  $sourceRoot = if ($sourceName -in @("bewerbungsauftrag", "anforderungsmatrix", "evidenzindex")) { $applicationsRootForWork } else { $privateRoot }
  Test-ArtifactSetUnchanged -Records @($sourceRecord) -Root $sourceRoot
}

Invoke-ChildTool -ScriptPath $dialogTool -Arguments @("-AuftragPath", $auftragPath, "-StammdatenPath", $StammdatenPath, "-ProfilPath", $ProfilPath, "-FuerDokumenterstellung")
$stammdatenReportPath = Resolve-WorkflowContractPath -Candidate $stammdatenReportPath -Root $applicationsRootForWork -ForWrite -PathType Leaf
Invoke-ChildTool -ScriptPath $stammdatenTool -Arguments @("-StammdatenPath", $StammdatenPath, "-BewerbungsauftragPath", $auftragPath, "-UngeklaerteLogistikAlsFehler", "-BerichtPath", $stammdatenReportPath)

$qualityPath = Resolve-WorkflowContractPath -Candidate $qualityPath -Root $applicationsRootForWork -MustExist -ForWrite -PathType Leaf
$candidateFiles = @(Get-SafeFileSet -Folder $candidateDir -SecurityRoot $applicationsRootForWork)
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

try {
  $stageDir = Resolve-WorkflowContractPath -Candidate (Join-Path -Path $companyDir -ChildPath (".publish-" + [guid]::NewGuid().ToString("N"))) -Root $applicationsRootForWork -ForWrite -PathType Container
  $backupDir = Resolve-WorkflowContractPath -Candidate (Join-Path -Path $companyDir -ChildPath (".backup-" + [guid]::NewGuid().ToString("N"))) -Root $applicationsRootForWork -ForWrite -PathType Container
  $reportTempPath = Resolve-WorkflowContractPath -Candidate (Join-Path -Path $resolvedWork -ChildPath (".Finalisierungsbericht.publish-" + [guid]::NewGuid().ToString("N") + ".json")) -Root $applicationsRootForWork -ForWrite -PathType Leaf
  $reportBackupPath = Resolve-WorkflowContractPath -Candidate (Join-Path -Path $resolvedWork -ChildPath (".Finalisierungsbericht.backup-" + [guid]::NewGuid().ToString("N") + ".json")) -Root $applicationsRootForWork -ForWrite -PathType Leaf
} catch {
  Stop-Finalization -Message "Interne Veröffentlichungsziele sind nicht sicher: $($_.Exception.Message)"
}

$targetBackedUp = $false
$targetWasEmpty = $false
$targetInstalled = $false
$qualityPath = Resolve-WorkflowContractPath -Candidate $qualityPath -Root $applicationsRootForWork -MustExist -ForWrite -PathType Leaf
$qualityOriginalBytes = [System.IO.File]::ReadAllBytes($qualityPath)
$qualityMayHaveChanged = $false
try {
  $qualityMayHaveChanged = $true
  Update-TechnicalSection -QualityPath $qualityPath -WorkflowRoot $applicationsRootForWork -State "bestaetigt" -LayoutReportPath $layoutReportPath -PdfReportPath $pdfReportPath -AtsReportPath $atsReportPath -LayoutWarnings $reportLayoutWarnings -VisualApprovalNote $normalizedVisualNote -HtmlDocumentCount $expectedHtmlCount
  Invoke-ChildTool -ScriptPath $staticTool -Arguments @("-Ordner", $candidateDir, "-AuftragPath", $auftragPath) -ThrowOnFailure

  $approvedArtifacts = Get-ReportArtifacts -CandidateFolder $candidateDir -LayoutFolder $layoutDir -WorkflowRoot $applicationsRootForWork
  if ($approvedArtifacts.html.Count -ne $expectedHtmlCount -or
      $approvedArtifacts.pdf.Count -ne $expectedHtmlCount -or
      $approvedArtifacts.screenshots.Count -ne $currentExpectedScreenshots -or
      $approvedArtifacts.candidate.Count -ne $candidateArtifactRecords.Count) {
    throw "Artefaktmenge änderte sich während der Veröffentlichungsprüfung."
  }
  $report.artifacts = $approvedArtifacts
  $candidateFiles = @(Get-SafeFileSet -Folder $candidateDir -SecurityRoot $applicationsRootForWork)

  $stageDir = Resolve-WorkflowContractPath -Candidate $stageDir -Root $applicationsRootForWork -ForWrite -PathType Container
  New-Item -Path $stageDir -ItemType Directory | Out-Null
  $stageDir = Resolve-WorkflowContractPath -Candidate $stageDir -Root $applicationsRootForWork -MustExist -ForWrite -PathType Container
  $stageShippingDir = Resolve-WorkflowContractPath -Candidate (Join-Path -Path $stageDir -ChildPath "Versand") -Root $applicationsRootForWork -ForWrite -PathType Container
  $stageInternalDir = Resolve-WorkflowContractPath -Candidate (Join-Path -Path $stageDir -ChildPath "Intern") -Root $applicationsRootForWork -ForWrite -PathType Container
  New-Item -Path $stageShippingDir -ItemType Directory | Out-Null
  New-Item -Path $stageInternalDir -ItemType Directory | Out-Null
  $stageShippingDir = Resolve-WorkflowContractPath -Candidate $stageShippingDir -Root $applicationsRootForWork -MustExist -ForWrite -PathType Container
  $stageInternalDir = Resolve-WorkflowContractPath -Candidate $stageInternalDir -Root $applicationsRootForWork -MustExist -ForWrite -PathType Container
  foreach ($file in $candidateFiles) {
    $sourcePath = Resolve-WorkflowContractPath -Candidate $file.FullName -Root $applicationsRootForWork -MustExist -ForWrite -PathType Leaf
    $destinationFolder = if ($file.Extension -ieq ".pdf" -or $file.Name -match '^Email-Nachricht--.+\.md$') {
      $stageShippingDir
    } else {
      $stageInternalDir
    }
    $destinationFolder = Resolve-WorkflowContractPath -Candidate $destinationFolder -Root $applicationsRootForWork -MustExist -ForWrite -PathType Container
    $destinationPath = Resolve-WorkflowContractPath -Candidate (Join-Path -Path $destinationFolder -ChildPath $file.Name) -Root $applicationsRootForWork -ForWrite -PathType Leaf
    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath
    $null = Resolve-WorkflowContractPath -Candidate $destinationPath -Root $applicationsRootForWork -MustExist -ForWrite -PathType Leaf
  }
  $manifestPath = New-PublicationManifest -Root $stageDir -SecurityRoot $applicationsRootForWork -Auftrag $auftrag -SourceInputs $sourceInputs
  Invoke-ChildTool -ScriptPath $staticTool -Arguments @("-Ordner", $stageDir, "-AuftragPath", $auftragPath) -ThrowOnFailure

  $report.status = "veroeffentlicht"
  $report | Add-Member -NotePropertyName publishedAtUtc -NotePropertyValue ([datetime]::UtcNow.ToString("o")) -Force
  $report | Add-Member -NotePropertyName publishedFolder -NotePropertyValue $targetDir -Force
  $publishedManifestPath = Resolve-WorkflowContractPath -Candidate (Join-Path -Path $targetDir -ChildPath "Manifest.json") -Root $applicationsRootForWork -ForWrite -PathType Leaf
  $report | Add-Member -NotePropertyName publishedManifest -NotePropertyValue ([ordered]@{
    path = $publishedManifestPath
    sha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
  }) -Force
  $report | Add-Member -NotePropertyName visualApprovalNote -NotePropertyValue $normalizedVisualNote -Force
  $reportTempPath = Resolve-WorkflowContractPath -Candidate $reportTempPath -Root $applicationsRootForWork -ForWrite -PathType Leaf
  Write-AtomicJson -Path $reportTempPath -Value $report -Depth 10
  $reportTempPath = Resolve-WorkflowContractPath -Candidate $reportTempPath -Root $applicationsRootForWork -MustExist -ForWrite -PathType Leaf
  $preparedPublishedReport = Get-Content -LiteralPath $reportTempPath -Raw -Encoding UTF8 | ConvertFrom-Json
  if ([string](Get-JsonProperty -Object $preparedPublishedReport -Name "status") -ne "veroeffentlicht") {
    throw "Temporärer Veröffentlichungsbericht konnte nicht validiert werden."
  }

  $targetDir = Resolve-WorkflowContractPath -Candidate $expectedTarget -Root $applicationsRootForWork -ForWrite -PathType Container
  if (Test-Path -LiteralPath $targetDir) {
    if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) {
      throw "Zielpfad ist kein Ordner: $targetDir"
    }
    $targetEntries = @(Get-ChildItem -LiteralPath $targetDir -Force)
    if ($targetEntries.Count -gt 0 -and -not $Ersetzen) {
      throw "Finaler Zielordner ist nicht leer. Verwende -Ersetzen nur für eine bewusst neu geprüfte Veröffentlichung."
    }
    if ($targetEntries.Count -gt 0) {
      $targetDir = Resolve-WorkflowContractPath -Candidate $targetDir -Root $applicationsRootForWork -MustExist -ForWrite -PathType Container
      $backupDir = Resolve-WorkflowContractPath -Candidate $backupDir -Root $applicationsRootForWork -ForWrite -PathType Container
      Move-Item -LiteralPath $targetDir -Destination $backupDir
      $targetBackedUp = $true
    } else {
      $targetWasEmpty = $true
      $targetDir = Resolve-WorkflowContractPath -Candidate $targetDir -Root $applicationsRootForWork -MustExist -ForWrite -PathType Container
      Remove-Item -LiteralPath $targetDir -Force
    }
  }

  $stageDir = Resolve-WorkflowContractPath -Candidate $stageDir -Root $applicationsRootForWork -MustExist -ForWrite -PathType Container
  $targetDir = Resolve-WorkflowContractPath -Candidate $expectedTarget -Root $applicationsRootForWork -ForWrite -PathType Container
  Move-Item -LiteralPath $stageDir -Destination $targetDir
  $targetInstalled = $true
  $reportTempPath = Resolve-WorkflowContractPath -Candidate $reportTempPath -Root $applicationsRootForWork -MustExist -ForWrite -PathType Leaf
  $finalReportPath = Resolve-WorkflowContractPath -Candidate $finalReportPath -Root $applicationsRootForWork -MustExist -ForWrite -PathType Leaf
  $reportBackupPath = Resolve-WorkflowContractPath -Candidate $reportBackupPath -Root $applicationsRootForWork -ForWrite -PathType Leaf
  [System.IO.File]::Replace($reportTempPath, $finalReportPath, $reportBackupPath, $true)
} catch {
  $publishError = $_.Exception.Message
  $rollbackErrors = New-Object System.Collections.Generic.List[string]
  $reportBackupRestored = $false
  if ($qualityMayHaveChanged) {
    try {
      $qualityPath = Resolve-WorkflowContractPath -Candidate $qualityPath -Root $applicationsRootForWork -MustExist -ForWrite -PathType Leaf
      [System.IO.File]::WriteAllBytes($qualityPath, $qualityOriginalBytes)
    } catch { $rollbackErrors.Add("Qualitaetscheck.md: $($_.Exception.Message)") | Out-Null }
  }
  if (Test-Path -LiteralPath $stageDir -PathType Container) {
    try {
      $stageDir = Resolve-WorkflowContractPath -Candidate $stageDir -Root $applicationsRootForWork -MustExist -ForWrite -PathType Container
      Remove-Item -LiteralPath $stageDir -Recurse -Force
    } catch { $rollbackErrors.Add("Staging-Ordner: $($_.Exception.Message)") | Out-Null }
  }
  if ($targetInstalled -and (Test-Path -LiteralPath $targetDir -PathType Container)) {
    try {
      $targetDir = Resolve-WorkflowContractPath -Candidate $expectedTarget -Root $applicationsRootForWork -MustExist -ForWrite -PathType Container
      Remove-Item -LiteralPath $targetDir -Recurse -Force
    } catch { $rollbackErrors.Add("neuer Zielordner: $($_.Exception.Message)") | Out-Null }
  }
  if ($targetBackedUp -and (Test-Path -LiteralPath $backupDir -PathType Container)) {
    try {
      $backupDir = Resolve-WorkflowContractPath -Candidate $backupDir -Root $applicationsRootForWork -MustExist -ForWrite -PathType Container
      $targetDir = Resolve-WorkflowContractPath -Candidate $expectedTarget -Root $applicationsRootForWork -ForWrite -PathType Container
      Move-Item -LiteralPath $backupDir -Destination $targetDir
    } catch { $rollbackErrors.Add("alter Zielordner: $($_.Exception.Message)") | Out-Null }
  } elseif ($targetWasEmpty -and -not (Test-Path -LiteralPath $targetDir)) {
    try {
      $targetDir = Resolve-WorkflowContractPath -Candidate $expectedTarget -Root $applicationsRootForWork -ForWrite -PathType Container
      New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
    } catch { $rollbackErrors.Add("leerer Zielordner: $($_.Exception.Message)") | Out-Null }
  }
  if (Test-Path -LiteralPath $reportBackupPath -PathType Leaf) {
    try {
      $reportBackupPath = Resolve-WorkflowContractPath -Candidate $reportBackupPath -Root $applicationsRootForWork -MustExist -ForWrite -PathType Leaf
      $finalReportPath = Resolve-WorkflowContractPath -Candidate $finalReportPath -Root $applicationsRootForWork -ForWrite -PathType Leaf
      Copy-Item -LiteralPath $reportBackupPath -Destination $finalReportPath -Force
      $reportBackupRestored = $true
    } catch {
      $rollbackErrors.Add("Finalisierungsbericht: $($_.Exception.Message)") | Out-Null
    }
  } elseif (-not (Test-Path -LiteralPath $finalReportPath -PathType Leaf)) {
    try {
      $finalReportPath = Resolve-WorkflowContractPath -Candidate $finalReportPath -Root $applicationsRootForWork -ForWrite -PathType Leaf
      Write-AtomicText -Path $finalReportPath -Content $preparedReportJson
    } catch { $rollbackErrors.Add("Finalisierungsbericht: $($_.Exception.Message)") | Out-Null }
  }
  if (Test-Path -LiteralPath $reportTempPath -PathType Leaf) {
    try {
      $reportTempPath = Resolve-WorkflowContractPath -Candidate $reportTempPath -Root $applicationsRootForWork -MustExist -ForWrite -PathType Leaf
      Remove-Item -LiteralPath $reportTempPath -Force
    } catch { $rollbackErrors.Add("temporärer Bericht: $($_.Exception.Message)") | Out-Null }
  }
  if ($reportBackupRestored -and (Test-Path -LiteralPath $reportBackupPath -PathType Leaf)) {
    try {
      $reportBackupPath = Resolve-WorkflowContractPath -Candidate $reportBackupPath -Root $applicationsRootForWork -MustExist -ForWrite -PathType Leaf
      Remove-Item -LiteralPath $reportBackupPath -Force
    } catch { $rollbackErrors.Add("wiederhergestellte Berichtssicherung: $($_.Exception.Message)") | Out-Null }
  } elseif (Test-Path -LiteralPath $reportBackupPath -PathType Leaf) {
    $rollbackErrors.Add("Berichtssicherung zur manuellen Wiederherstellung erhalten: $reportBackupPath") | Out-Null
  }
  $rollbackSuffix = if ($rollbackErrors.Count -gt 0) { " Rollback unvollständig: $($rollbackErrors -join ' | ')" } else { " Bisheriger Ziel- und Berichtsstand wurden wiederhergestellt." }
  Stop-Finalization -Message "Atomare Veröffentlichung fehlgeschlagen: $publishError.$rollbackSuffix"
}

foreach ($obsoleteBackup in @($backupDir, $reportBackupPath)) {
  if (Test-Path -LiteralPath $obsoleteBackup) {
    try {
      if (Test-LexicalPathEqual -Left $obsoleteBackup -Right $backupDir) {
        $safeObsoleteBackup = Resolve-WorkflowContractPath -Candidate $obsoleteBackup -Root $applicationsRootForWork -MustExist -ForWrite -PathType Container
      } else {
        $safeObsoleteBackup = Resolve-WorkflowContractPath -Candidate $obsoleteBackup -Root $applicationsRootForWork -MustExist -ForWrite -PathType Leaf
      }
      Remove-Item -LiteralPath $safeObsoleteBackup -Recurse -Force
    } catch {
      Write-Host "[WARNUNG] Veröffentlichung war erfolgreich, aber eine Sicherung konnte nicht entfernt werden: $obsoleteBackup ($($_.Exception.Message))" -ForegroundColor Yellow
    }
  }
}
Update-WorkflowCheckpointNonBlocking -WorkFolder $resolvedWork -Step 'veroeffentlicht'
Add-Ok "Bewerbung vollständig und atomar veröffentlicht: $targetDir"
Write-Host "Versandfertige Dateien: $(Join-Path -Path $targetDir -ChildPath 'Versand')"
exit 0
