#requires -Version 7.6
#requires -PSEdition Core

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Arbeitsordner
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/OrderPaths.psm1") -Force
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/Passfoto.psm1") -Force
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Common/Platform.psm1") -Force

function Stop-Passfoto {
  param([Parameter(Mandatory)][string]$Message, [int]$Code = 1)
  Write-Host "[FEHLER] $Message" -ForegroundColor Red
  exit $Code
}

function Get-JsonProperty {
  param([object]$Object, [string]$Name)
  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

try {
  $workInput = [System.IO.Path]::GetFullPath($Arbeitsordner).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
  )
  $workFilesFolder = Split-Path -Path $workInput -Parent
  $companyFolder = Split-Path -Path $workFilesFolder -Parent
  $applicationsRoot = Split-Path -Path $companyFolder -Parent
  $privateRoot = Split-Path -Path $applicationsRoot -Parent
  $comparison = Get-PathStringComparison
  if (-not [string]::Equals((Split-Path -Path $workFilesFolder -Leaf), '_Arbeitsdateien', $comparison) -or
      -not [string]::Equals((Split-Path -Path $applicationsRoot -Leaf), 'Bewerbungen', $comparison) -or
      -not [string]::Equals((Split-Path -Path $privateRoot -Leaf), 'Private', $comparison)) {
    throw "Arbeitsordner muss unter Private/Bewerbungen/<Firma>/_Arbeitsdateien liegen."
  }
  $applicationsRoot = Resolve-SafePath -Candidate $applicationsRoot -Root $applicationsRoot -AllowRoot -MustExist -ForWrite -PathType Container
  $resolvedWork = Resolve-SafePath -Candidate $workInput -Root $applicationsRoot -MustExist -ForWrite -PathType Container
  $auftragPath = Resolve-SafePath -Candidate (Join-Path $resolvedWork 'Bewerbungsauftrag.json') -Root $applicationsRoot -MustExist -ForWrite -PathType Leaf
  $auftrag = Get-Content -LiteralPath $auftragPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $paths = Resolve-BewerbungsauftragPathSet -Auftrag $auftrag -Arbeitsordner $resolvedWork -BewerbungenRoot $applicationsRoot
  $candidateDir = Resolve-SafePath -Candidate $paths.KandidatOrdner -Root $applicationsRoot -MustExist -ForWrite -PathType Container
  $dataRoot = Resolve-SafePath -Candidate (Join-Path $privateRoot 'Daten') -Root $privateRoot -MustExist -PathType Container
} catch {
  Stop-Passfoto -Message "Unsicherer Arbeits-, Auftrags- oder Datenpfad: $($_.Exception.Message)" -Code 2
}

$schema = [int](Get-JsonProperty -Object $auftrag -Name 'schemaVersion')
$scope = Get-JsonProperty -Object $auftrag -Name 'dokumentumfang'
$cvKind = if ($schema -ge 4) {
  [string](Get-JsonProperty -Object $scope -Name 'lebenslauf')
} elseif ([string](Get-JsonProperty -Object $auftrag -Name 'dokumentmodus') -eq 'anschreiben_mit_universalem_lebenslauf') {
  'universal_unveraendert'
} else {
  'individuell'
}
if ($cvKind -eq 'universal_unveraendert') {
  Stop-Passfoto -Message "Ein universeller Lebenslauf ist ein unveränderter SHA-256-Snapshot und darf nicht um ein Passfoto ergänzt werden."
}
if ($cvKind -ne 'individuell') {
  Stop-Passfoto -Message "Der Bewerbungsauftrag enthält keinen individuellen Lebenslauf."
}

$cvFiles = @(Get-ChildItem -LiteralPath $candidateDir -File -Filter 'Lebenslauf - *.html')
if ($cvFiles.Count -ne 1) {
  Stop-Passfoto -Message "Für die Passfoto-Integration wird genau ein individueller Kandidaten-Lebenslauf erwartet; gefunden: $($cvFiles.Count)."
}
try {
  $cvPath = Resolve-SafePath -Candidate $cvFiles[0].FullName -Root $candidateDir -MustExist -ForWrite -PathType Leaf
  $sourceState = Get-PassfotoSourceState -DataRoot $dataRoot
  $html = Get-Content -LiteralPath $cvPath -Raw -Encoding UTF8
  $updated = Update-PassfotoHtml -Html $html -SourceState $sourceState
} catch {
  Stop-Passfoto -Message $_.Exception.Message
}

if ($updated -cne $html) {
  $temporaryPath = Join-Path -Path $candidateDir -ChildPath ('.passfoto-' + [guid]::NewGuid().ToString('N') + '.tmp')
  try {
    $temporaryPath = Resolve-SafePath -Candidate $temporaryPath -Root $candidateDir -ForWrite -PathType Leaf
    [System.IO.File]::WriteAllText($temporaryPath, $updated, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::Move($temporaryPath, $cvPath, $true)
  } finally {
    if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
      Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
  }
}

$status = if ($sourceState.Exists) { 'eingebettet' } else { 'nicht_vorhanden' }
Write-Host "[OK] Passfoto-Status: $status."
if ($sourceState.Exists) {
  Write-Host "[OK] Passfoto.png wurde bytegleich und vollständig eingebettet ($($sourceState.Width)x$($sourceState.Height) Pixel, SHA-256 gebunden)."
} else {
  Write-Host "[OK] Private/Daten/Passfoto.png fehlt; der Lebenslauf bleibt ohne Foto."
}
exit 0
