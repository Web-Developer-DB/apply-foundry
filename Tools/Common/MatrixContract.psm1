#requires -Version 7.6
#requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'JsonContract.psm1') -Force

$script:MatrixSupportedSchemaVersions = @(1, 2, 3, 4, 5)
$script:MatrixCurrentSchemaVersion = 5

function Get-MatrixSchemaVersion {
  param(
    [Parameter(Mandatory)][object]$Matrix,
    [switch]$AllowMissing
  )

  $raw = Get-ContractJsonProperty -Object $Matrix -Name 'schemaVersion'
  if ($null -eq $raw -and $AllowMissing) { return $null }
  if ($raw -isnot [int] -and $raw -isnot [long]) {
    throw 'Anforderungsmatrix enthält keine ganzzahlige schemaVersion.'
  }
  $schema = [int]$raw
  if ($schema -notin $script:MatrixSupportedSchemaVersions) {
    throw "Anforderungsmatrix verwendet keine unterstützte schemaVersion 1 bis 5: $schema"
  }
  return $schema
}

function Test-MatrixSchemaVersion {
  param([object]$Matrix, [int]$Expected)
  try {
    return (Get-MatrixSchemaVersion -Matrix $Matrix) -eq $Expected
  } catch {
    return $false
  }
}

function Get-MatrixContractInfo {
  param([Parameter(Mandatory)][object]$Matrix)
  $schema = Get-MatrixSchemaVersion -Matrix $Matrix
  return [ordered]@{
    schemaVersion = $schema
    currentSchemaVersion = $script:MatrixCurrentSchemaVersion
    requiresStellenanzeigeAbdeckung = ($schema -ge 4)
    requiresEvidenzindex = ($schema -ge 4)
    requiresRecruiterStrategie = ($schema -ge 3)
    requiresAnschreibenStrategie = ($schema -ge 5)
  }
}

function New-MatrixDraft {
  param([bool]$IncludeLetter = $true)

  return [ordered]@{
    schemaVersion = $script:MatrixCurrentSchemaVersion
    requirements = @(
      [ordered]@{
        id = 'muss-1'
        anforderung = 'durch den Agenten aus der Stellenbeschreibung zu extrahieren'
        typ = 'muss'
        kategorie = 'fachlich'
        gewichtung = 'hoch'
        status = 'unklar'
        belegart = ''
        beleg = ''
        stellenFundstellen = @()
        belegRefIds = @()
        behandlung = 'vor Erstellung der Kandidatendateien klären'
      }
    )
    recruiterStrategie = [ordered]@{
      kernbotschaft = 'durch den Agenten aus Zielrolle, Stellenanforderungen und den stärksten belegten Profilargumenten abzuleiten'
      profilSubstanz = 'noch_zu_pruefen'
      profilSubstanzBegruendung = 'vor der Dokumenterstellung anhand der relevanten Profildaten zu prüfen'
      prioritaetsAnforderungen = @('muss-1')
      profilHighlights = @()
      transferbruecken = @()
      auslassungen = @()
    }
    anschreibenStrategie = [ordered]@{
      status = if ($IncludeLetter) { 'ausstehend' } else { 'nicht_erforderlich' }
      argumente = @()
      abweichungBegruendung = ''
    }
    externeQuellen = @()
    stellenanzeigeAbdeckung = [ordered]@{
      sourceSha256 = 'aus Stellenbeschreibung.md übernehmen'
      fundstellen = @()
    }
  }
}

function Get-MatrixMigrationSteps {
  return @(
    [ordered]@{ id = 'matrix/1-zu-2'; from = 1; to = 2 },
    [ordered]@{ id = 'matrix/2-zu-3'; from = 2; to = 3 },
    [ordered]@{ id = 'matrix/3-zu-4'; from = 3; to = 4 },
    [ordered]@{ id = 'matrix/4-zu-5'; from = 4; to = 5 }
  )
}

Export-ModuleMember -Function @(
  'Get-MatrixSchemaVersion',
  'Test-MatrixSchemaVersion',
  'Get-MatrixContractInfo',
  'New-MatrixDraft',
  'Get-MatrixMigrationSteps'
)
