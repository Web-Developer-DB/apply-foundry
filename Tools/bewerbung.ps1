#requires -Version 7.6
#requires -PSEdition Core

[CmdletBinding(PositionalBinding = $false)]
param(
  [Parameter(Position = 0)]
  [string]$Subcommand,

  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$CliArguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:CommandOrder = @(
  "diagnose",
  "neu",
  "status",
  "checkpoint",
  "stammdaten",
  "dialog-pruefen",
  "dialog-uebernehmen",
  "inhalt",
  "pruefen",
  "layout",
  "pdf",
  "ats",
  "finalisieren",
  "tokenbericht",
  "tests"
)

function Stop-Cli {
  param([Parameter(Mandatory = $true)][string]$Message)

  [Console]::Error.WriteLine("Fehler: $Message")
  exit 2
}

function New-CliOption {
  param(
    [Parameter(Mandatory = $true)][string]$Parameter,
    [ValidateSet("string", "switch", "enum", "int", "long", "datetime", "documents")]
    [string]$Kind = "string",
    [string[]]$Allowed = @(),
    [Nullable[long]]$Min,
    [Nullable[long]]$Max,
    [string]$Placeholder = "WERT"
  )

  return @{
    Parameter = $Parameter
    Kind = $Kind
    Allowed = @($Allowed)
    Min = $Min
    Max = $Max
    Placeholder = $Placeholder
  }
}

$script:Commands = @{
  "diagnose" = @{
    RelativePath = "Pruefe-Umgebung.ps1"
    Summary = "Laufzeit und Plattform read-only pruefen"
    Required = @()
    Options = [ordered]@{
      "--browser" = New-CliOption -Parameter "Browser" -Kind enum -Allowed @("auto", "chrome", "edge", "chromium", "firefox") -Placeholder "NAME"
      "--browser-executable-path" = New-CliOption -Parameter "BrowserExecutablePath" -Placeholder "PFAD"
      "--als-json" = New-CliOption -Parameter "AlsJson" -Kind switch
      "--browser-erforderlich" = New-CliOption -Parameter "BrowserErforderlich" -Kind switch
    }
  }
  "neu" = @{
    RelativePath = "Neue-Bewerbung.ps1"
    Summary = "Neuen Bewerbungsauftrag anlegen oder exakt fortsetzen"
    Required = @("--firma")
    Options = [ordered]@{
      "--firma" = New-CliOption -Parameter "Firma" -Placeholder "NAME"
      "--rolle" = New-CliOption -Parameter "Rolle" -Placeholder "NAME"
      "--dokumentmodus" = New-CliOption -Parameter "Dokumentmodus" -Kind enum -Allowed @("vollbewerbung", "anschreiben_mit_universalem_lebenslauf", "individuelle_auswahl") -Placeholder "MODUS"
      "--umfang" = New-CliOption -Parameter "UmfangAuswahl" -Kind enum -Allowed @("A", "B", "C", "D", "E") -Placeholder "A-E"
      "--dokumente" = New-CliOption -Parameter "Dokumente" -Kind documents -Placeholder "LISTE"
      "--umfang-quelle" = New-CliOption -Parameter "UmfangQuelle" -Kind enum -Allowed @("auswahl", "direkter_auftrag", "fortgesetzter_auftrag") -Placeholder "QUELLE"
      "--email-allein-bestaetigt" = New-CliOption -Parameter "EmailAlleinBestaetigt" -Kind switch
      "--universal-lebenslauf-path" = New-CliOption -Parameter "UniversalLebenslaufPath" -Placeholder "PFAD"
      "--datum" = New-CliOption -Parameter "Datum" -Placeholder "YYYY-MM-DD"
      "--stellenbeschreibung-path" = New-CliOption -Parameter "StellenbeschreibungPath" -Placeholder "PFAD"
      "--stammdaten-path" = New-CliOption -Parameter "StammdatenPath" -Placeholder "PFAD"
      "--profil-path" = New-CliOption -Parameter "ProfilPath" -Placeholder "PFAD"
      "--bewerbungen-root" = New-CliOption -Parameter "BewerbungenRoot" -Placeholder "PFAD"
      "--fortsetzen" = New-CliOption -Parameter "Fortsetzen" -Kind switch
    }
  }
  "status" = @{
    RelativePath = "Ermittle-Bewerbungsstatus.ps1"
    Summary = "Gespeicherten Bewerbungsstand ermitteln"
    Required = @()
    Options = [ordered]@{
      "--arbeitsordner" = New-CliOption -Parameter "Arbeitsordner" -Placeholder "PFAD"
      "--als-json" = New-CliOption -Parameter "AlsJson" -Kind switch
    }
  }
  "checkpoint" = @{
    RelativePath = "Aktualisiere-WorkflowCheckpoint.ps1"
    Summary = "Kompakten, hashgebundenen Workflow-Checkpoint aktualisieren"
    Required = @("--arbeitsordner", "--schritt")
    Options = [ordered]@{
      "--arbeitsordner" = New-CliOption -Parameter "Arbeitsordner" -Placeholder "PFAD"
      "--schritt" = New-CliOption -Parameter "Schritt" -Kind enum -Allowed @("auftrag_angelegt", "profilabgleich_abgeschlossen", "analyse_abgeschlossen", "dokumente_abgeschlossen", "fachpruefung_abgeschlossen", "technische_vorbereitung_abgeschlossen", "sichtpruefung_bestaetigt", "veroeffentlicht") -Placeholder "NAME"
      "--als-json" = New-CliOption -Parameter "AlsJson" -Kind switch
    }
  }
  "stammdaten" = @{
    RelativePath = "Pruefe-Stammdaten.ps1"
    Summary = "Stammdaten pruefen"
    Required = @()
    Options = [ordered]@{
      "--stammdaten-path" = New-CliOption -Parameter "StammdatenPath" -Placeholder "PFAD"
      "--warnungen-als-fehler" = New-CliOption -Parameter "WarnungenAlsFehler" -Kind switch
      "--ungeklaerte-logistik-als-fehler" = New-CliOption -Parameter "UngeklaerteLogistikAlsFehler" -Kind switch
      "--bewerbungsauftrag-path" = New-CliOption -Parameter "BewerbungsauftragPath" -Placeholder "PFAD"
      "--bericht-path" = New-CliOption -Parameter "BerichtPath" -Placeholder "PFAD"
    }
  }
  "dialog-pruefen" = @{
    RelativePath = "Pruefe-Dialogstatus.ps1"
    Summary = "Dialogstatus eines Auftrags pruefen"
    Required = @("--auftrag-path")
    Options = [ordered]@{
      "--auftrag-path" = New-CliOption -Parameter "AuftragPath" -Placeholder "PFAD"
      "--stammdaten-path" = New-CliOption -Parameter "StammdatenPath" -Placeholder "PFAD"
      "--profil-path" = New-CliOption -Parameter "ProfilPath" -Placeholder "PFAD"
      "--fuer-dokumenterstellung" = New-CliOption -Parameter "FuerDokumenterstellung" -Kind switch
    }
  }
  "dialog-uebernehmen" = @{
    RelativePath = "Uebernehme-Dialogangabe.ps1"
    Summary = "Bestaetigte Dialogangabe kontrolliert uebernehmen"
    Required = @("--auftrag-path", "--angabe-id", "--speicherentscheidung")
    Options = [ordered]@{
      "--auftrag-path" = New-CliOption -Parameter "AuftragPath" -Placeholder "PFAD"
      "--angabe-id" = New-CliOption -Parameter "AngabeId" -Placeholder "ID"
      "--speicherentscheidung" = New-CliOption -Parameter "Speicherentscheidung" -Kind enum -Allowed @("nur_auftrag", "dauerhaft") -Placeholder "ENTSCHEIDUNG"
      "--profil-path" = New-CliOption -Parameter "ProfilPath" -Placeholder "PFAD"
      "--abschnitt" = New-CliOption -Parameter "Abschnitt" -Placeholder "NAME"
      "--formulierung" = New-CliOption -Parameter "Formulierung" -Placeholder "TEXT"
      "--erwarteter-datei-hash" = New-CliOption -Parameter "ErwarteterDateiHash" -Placeholder "SHA256"
      "--zustimmung-bestaetigt" = New-CliOption -Parameter "ZustimmungBestaetigt" -Kind switch
    }
  }
  "inhalt" = @{
    RelativePath = "Pruefe-Bewerbungsinhalt.ps1"
    Summary = "Kandidateninhalte fachlich pruefen"
    Required = @("--ordner", "--auftrag-path", "--anforderungsmatrix-path")
    Options = [ordered]@{
      "--ordner" = New-CliOption -Parameter "Ordner" -Placeholder "PFAD"
      "--stammdaten-path" = New-CliOption -Parameter "StammdatenPath" -Placeholder "PFAD"
      "--profil-path" = New-CliOption -Parameter "ProfilPath" -Placeholder "PFAD"
      "--auftrag-path" = New-CliOption -Parameter "AuftragPath" -Placeholder "PFAD"
      "--anforderungsmatrix-path" = New-CliOption -Parameter "AnforderungsmatrixPath" -Placeholder "PFAD"
      "--warnungen-als-fehler" = New-CliOption -Parameter "WarnungenAlsFehler" -Kind switch
      "--bericht-path" = New-CliOption -Parameter "BerichtPath" -Placeholder "PFAD"
    }
  }
  "pruefen" = @{
    RelativePath = "Pruefe-Bewerbung.ps1"
    Summary = "Kandidatenstruktur statisch pruefen"
    Required = @("--ordner")
    Options = [ordered]@{
      "--ordner" = New-CliOption -Parameter "Ordner" -Placeholder "PFAD"
      "--auftrag-path" = New-CliOption -Parameter "AuftragPath" -Placeholder "PFAD"
      "--warnungen-als-fehler" = New-CliOption -Parameter "WarnungenAlsFehler" -Kind switch
    }
  }
  "layout" = @{
    RelativePath = "Layoutcheck-Bewerbung.ps1"
    Summary = "HTML-Layout pruefen und Seitenscreenshots erzeugen"
    Required = @("--ordner")
    Options = [ordered]@{
      "--ordner" = New-CliOption -Parameter "Ordner" -Placeholder "PFAD"
      "--browser" = New-CliOption -Parameter "Browser" -Kind enum -Allowed @("auto", "chrome", "edge", "chromium", "firefox") -Placeholder "NAME"
      "--browser-executable-path" = New-CliOption -Parameter "BrowserExecutablePath" -Placeholder "PFAD"
      "--nur-vorbereiten" = New-CliOption -Parameter "NurVorbereiten" -Kind switch
      "--pdf" = New-CliOption -Parameter "Pdf" -Kind switch
      "--erlaube-firefox-fallback" = New-CliOption -Parameter "ErlaubeFirefoxFallback" -Kind switch
      "--width" = New-CliOption -Parameter "Width" -Kind int -Min 320 -Max 10000 -Placeholder "PIXEL"
      "--height" = New-CliOption -Parameter "Height" -Kind int -Min 320 -Max 10000 -Placeholder "PIXEL"
      "--timeout-seconds" = New-CliOption -Parameter "TimeoutSeconds" -Kind int -Min 1 -Max 600 -Placeholder "SEKUNDEN"
      "--output-root" = New-CliOption -Parameter "OutputRoot" -Placeholder "PFAD"
      "--bericht-path" = New-CliOption -Parameter "BerichtPath" -Placeholder "PFAD"
      "--dichtepruefung-deaktivieren" = New-CliOption -Parameter "DichtepruefungDeaktivieren" -Kind switch
    }
  }
  "pdf" = @{
    RelativePath = "Exportiere-PDF.ps1"
    Summary = "Gepruefte HTML-Dateien als PDF exportieren"
    Required = @("--ordner")
    Options = [ordered]@{
      "--ordner" = New-CliOption -Parameter "Ordner" -Placeholder "PFAD"
      "--auftrag-path" = New-CliOption -Parameter "AuftragPath" -Placeholder "PFAD"
      "--browser" = New-CliOption -Parameter "Browser" -Kind enum -Allowed @("auto", "chrome", "edge", "chromium") -Placeholder "NAME"
      "--browser-executable-path" = New-CliOption -Parameter "BrowserExecutablePath" -Placeholder "PFAD"
      "--mit-layoutcheck" = New-CliOption -Parameter "MitLayoutcheck" -Kind switch
      "--nicht-ueberschreiben" = New-CliOption -Parameter "NichtUeberschreiben" -Kind switch
      "--min-pdf-bytes" = New-CliOption -Parameter "MinPdfBytes" -Kind int -Min 100 -Max 100000000 -Placeholder "BYTES"
      "--timeout-seconds" = New-CliOption -Parameter "TimeoutSeconds" -Kind int -Min 1 -Max 600 -Placeholder "SEKUNDEN"
      "--output-root" = New-CliOption -Parameter "OutputRoot" -Placeholder "PFAD"
      "--bericht-path" = New-CliOption -Parameter "BerichtPath" -Placeholder "PFAD"
    }
  }
  "ats" = @{
    RelativePath = "Pruefe-ATS.ps1"
    Summary = "PDF-Textschicht und ATS-Abdeckung pruefen"
    Required = @("--ordner", "--auftrag-path")
    Options = [ordered]@{
      "--ordner" = New-CliOption -Parameter "Ordner" -Placeholder "PFAD"
      "--stammdaten-path" = New-CliOption -Parameter "StammdatenPath" -Placeholder "PFAD"
      "--auftrag-path" = New-CliOption -Parameter "AuftragPath" -Placeholder "PFAD"
      "--min-textabdeckung-prozent" = New-CliOption -Parameter "MinTextabdeckungProzent" -Kind int -Min 40 -Max 100 -Placeholder "PROZENT"
      "--bericht-path" = New-CliOption -Parameter "BerichtPath" -Placeholder "PFAD"
      "--pdf-export-bericht-path" = New-CliOption -Parameter "PdfExportBerichtPath" -Placeholder "PFAD"
    }
  }
  "finalisieren" = @{
    RelativePath = "Finalisiere-Bewerbung.ps1"
    Summary = "Technische Vorbereitung oder lokale Veroeffentlichung ausfuehren"
    Required = @("--arbeitsordner")
    Options = [ordered]@{
      "--arbeitsordner" = New-CliOption -Parameter "Arbeitsordner" -Placeholder "PFAD"
      "--browser" = New-CliOption -Parameter "Browser" -Kind enum -Allowed @("auto", "chrome", "edge", "chromium") -Placeholder "NAME"
      "--browser-executable-path" = New-CliOption -Parameter "BrowserExecutablePath" -Placeholder "PFAD"
      "--stammdaten-path" = New-CliOption -Parameter "StammdatenPath" -Placeholder "PFAD"
      "--profil-path" = New-CliOption -Parameter "ProfilPath" -Placeholder "PFAD"
      "--veroeffentlichen" = New-CliOption -Parameter "Veroeffentlichen" -Kind switch
      "--visuell-geprueft" = New-CliOption -Parameter "VisuellGeprueft" -Kind switch
      "--visuelle-freigabe-notiz" = New-CliOption -Parameter "VisuelleFreigabeNotiz" -Placeholder "TEXT"
      "--ersetzen" = New-CliOption -Parameter "Ersetzen" -Kind switch
      "--timeout-seconds" = New-CliOption -Parameter "TimeoutSeconds" -Kind int -Min 1 -Max 600 -Placeholder "SEKUNDEN"
    }
  }
  "tokenbericht" = @{
    RelativePath = "Aktualisiere-Tokenbericht.ps1"
    Summary = "Gemessene Nutzungsdaten in den privaten Bericht uebernehmen"
    Required = @("--arbeitsordner", "--messbereich")
    Options = [ordered]@{
      "--arbeitsordner" = New-CliOption -Parameter "Arbeitsordner" -Placeholder "PFAD"
      "--messbereich" = New-CliOption -Parameter "Messbereich" -Kind enum -Allowed @("lebenslauf", "gesamte_bewerbung", "technische_vorbereitung") -Placeholder "NAME"
      "--messumfang" = New-CliOption -Parameter "Messumfang" -Kind enum -Allowed @("abschnitt", "gesamte_agentensitzung") -Placeholder "NAME"
      "--nutzungsdaten-verfuegbar" = New-CliOption -Parameter "NutzungsdatenVerfuegbar" -Kind switch
      "--anbieter" = New-CliOption -Parameter "Anbieter" -Placeholder "NAME"
      "--modell" = New-CliOption -Parameter "Modell" -Placeholder "NAME"
      "--vorgangs-id" = New-CliOption -Parameter "VorgangsId" -Placeholder "ID"
      "--messquelle" = New-CliOption -Parameter "Messquelle" -Placeholder "NAME"
      "--beginn" = New-CliOption -Parameter "Beginn" -Kind datetime -Placeholder "ZEITPUNKT"
      "--ende" = New-CliOption -Parameter "Ende" -Kind datetime -Placeholder "ZEITPUNKT"
      "--eingabe-tokens" = New-CliOption -Parameter "EingabeTokens" -Kind long -Min 0 -Max ([long]::MaxValue) -Placeholder "ANZAHL"
      "--ausgabe-tokens" = New-CliOption -Parameter "AusgabeTokens" -Kind long -Min 0 -Max ([long]::MaxValue) -Placeholder "ANZAHL"
      "--cache-lese-tokens" = New-CliOption -Parameter "CacheLeseTokens" -Kind long -Min 0 -Max ([long]::MaxValue) -Placeholder "ANZAHL"
      "--cache-schreib-tokens" = New-CliOption -Parameter "CacheSchreibTokens" -Kind long -Min 0 -Max ([long]::MaxValue) -Placeholder "ANZAHL"
      "--reasoning-tokens" = New-CliOption -Parameter "ReasoningTokens" -Kind long -Min 0 -Max ([long]::MaxValue) -Placeholder "ANZAHL"
      "--gesamt-tokens" = New-CliOption -Parameter "GesamtTokens" -Kind long -Min 0 -Max ([long]::MaxValue) -Placeholder "ANZAHL"
    }
  }
  "tests" = @{
    RelativePath = "../Tests/Run-RegressionTests.ps1"
    Summary = "Projektweite synthetische Regressionstests ausfuehren"
    Required = @()
    Options = [ordered]@{
      "--mit-browser" = New-CliOption -Parameter "MitBrowser" -Kind switch
    }
  }
}

function Write-GlobalHelp {
  Write-Output "Einheitlicher Bewerbungsworkflow fuer Windows und Linux"
  Write-Output ""
  Write-Output "Aufruf:"
  Write-Output "  pwsh -NoProfile -File Tools/bewerbung.ps1 <subcommand> [optionen]"
  Write-Output "  ./Tools/bewerbung.sh <subcommand> [optionen]"
  Write-Output ""
  Write-Output "Subcommands:"
  foreach ($name in $script:CommandOrder) {
    Write-Output ("  {0,-20} {1}" -f $name, $script:Commands[$name].Summary)
  }
  Write-Output ""
  Write-Output "Details: <subcommand> --help"
}

function Write-CommandHelp {
  param([Parameter(Mandatory = $true)][string]$Name)

  $definition = $script:Commands[$Name]
  Write-Output $definition.Summary
  Write-Output ""
  Write-Output "Aufruf: $Name [optionen]"
  if ($definition.Options.Count -eq 0) {
    return
  }
  Write-Output ""
  Write-Output "Optionen:"
  foreach ($entry in $definition.Options.GetEnumerator()) {
    $suffix = if ($entry.Value.Kind -eq "switch") { "" } else { " $($entry.Value.Placeholder)" }
    $required = if ($definition.Required -contains $entry.Key) { " (Pflicht)" } else { "" }
    Write-Output ("  {0}{1}" -f ($entry.Key + $suffix), $required)
  }
  Write-Output "  -h, --help"
}

function ConvertTo-CliValue {
  param(
    [Parameter(Mandatory = $true)][string]$RawValue,
    [Parameter(Mandatory = $true)][string]$OptionName,
    [Parameter(Mandatory = $true)][hashtable]$Option
  )

  if ([string]::IsNullOrWhiteSpace($RawValue)) {
    Stop-Cli "Leerer Wert fuer $OptionName ist nicht zulaessig."
  }
  if ($RawValue -match '[\x00-\x1F\x7F]') {
    Stop-Cli "Steuerzeichen im Wert fuer $OptionName sind nicht zulaessig."
  }

  switch ($Option.Kind) {
    "string" {
      return $RawValue
    }
    "enum" {
      foreach ($allowedValue in $Option.Allowed) {
        if ([string]::Equals($RawValue, $allowedValue, [System.StringComparison]::OrdinalIgnoreCase)) {
          return $allowedValue
        }
      }
      Stop-Cli "Ungueltiger Wert fuer $OptionName. Erlaubt: $($Option.Allowed -join ', ')."
    }
    "int" {
      $parsed = 0
      if (-not [int]::TryParse($RawValue, [System.Globalization.NumberStyles]::Integer, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
        Stop-Cli "$OptionName erfordert eine ganze Zahl."
      }
      if (($null -ne $Option.Min -and $parsed -lt $Option.Min) -or ($null -ne $Option.Max -and $parsed -gt $Option.Max)) {
        Stop-Cli "Wert fuer $OptionName liegt ausserhalb des erlaubten Bereichs $($Option.Min)-$($Option.Max)."
      }
      return $parsed
    }
    "long" {
      $parsed = [long]0
      if (-not [long]::TryParse($RawValue, [System.Globalization.NumberStyles]::Integer, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
        Stop-Cli "$OptionName erfordert eine ganze Zahl."
      }
      if (($null -ne $Option.Min -and $parsed -lt $Option.Min) -or ($null -ne $Option.Max -and $parsed -gt $Option.Max)) {
        Stop-Cli "Wert fuer $OptionName liegt ausserhalb des erlaubten Bereichs $($Option.Min)-$($Option.Max)."
      }
      return $parsed
    }
    "datetime" {
      $parsed = [datetime]::MinValue
      $styles = [System.Globalization.DateTimeStyles]::AllowWhiteSpaces -bor [System.Globalization.DateTimeStyles]::RoundtripKind
      if (-not [datetime]::TryParse($RawValue, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) {
        Stop-Cli "$OptionName erfordert einen gueltigen ISO-Zeitpunkt."
      }
      return $parsed
    }
    "documents" {
      $allowedDocuments = @("lebenslauf", "anschreiben", "email_nachricht")
      $normalized = [System.Collections.Generic.List[string]]::new()
      $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
      foreach ($part in $RawValue.Split(",", [System.StringSplitOptions]::None)) {
        $document = $part.Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($document) -or $allowedDocuments -notcontains $document) {
          Stop-Cli "Ungueltiges Dokument in $OptionName. Erlaubt: $($allowedDocuments -join ', ')."
        }
        if (-not $seen.Add($document)) {
          Stop-Cli "Dokument '$document' wurde in $OptionName mehrfach angegeben."
        }
        $normalized.Add($document)
      }
      return ,([string[]]$normalized.ToArray())
    }
    default {
      throw "Interner CLI-Fehler: unbekannter Optionstyp '$($Option.Kind)'."
    }
  }
}

if ([string]::IsNullOrWhiteSpace($Subcommand)) {
  Write-GlobalHelp
  exit 0
}

if ($Subcommand -in @("-h", "--help", "help")) {
  if (@($CliArguments).Count -ne 0) {
    Stop-Cli "Die globale Hilfe akzeptiert keine weiteren Argumente."
  }
  Write-GlobalHelp
  exit 0
}

if ($Subcommand -match '[\x00-\x1F\x7F]') {
  Stop-Cli "Ungueltiges Subcommand."
}

$commandName = $Subcommand.ToLowerInvariant()
if (-not $script:Commands.ContainsKey($commandName)) {
  Stop-Cli "Unbekanntes Subcommand '$Subcommand'. Mit --help werden alle Subcommands angezeigt."
}

$definition = $script:Commands[$commandName]
$arguments = @($CliArguments)
if ($arguments.Count -gt 0 -and $arguments[0] -in @("-h", "--help")) {
  if ($arguments.Count -ne 1) {
    Stop-Cli "Die Subcommand-Hilfe akzeptiert keine weiteren Argumente."
  }
  Write-CommandHelp -Name $commandName
  exit 0
}

$boundParameters = @{}
for ($index = 0; $index -lt $arguments.Count; $index++) {
  $token = [string]$arguments[$index]
  if (-not $token.StartsWith("--", [System.StringComparison]::Ordinal)) {
    Stop-Cli "Unerwartetes Argument '$token'. Es sind nur GNU-Langoptionen zulaessig."
  }

  $optionName = $token
  $inlineValue = $null
  $hasInlineValue = $false
  $equalsIndex = $token.IndexOf("=", [System.StringComparison]::Ordinal)
  if ($equalsIndex -ge 0) {
    $optionName = $token.Substring(0, $equalsIndex)
    $inlineValue = $token.Substring($equalsIndex + 1)
    $hasInlineValue = $true
  }

  if (-not $definition.Options.Contains($optionName)) {
    Stop-Cli "Option '$optionName' ist fuer '$commandName' nicht zulaessig."
  }

  $option = $definition.Options[$optionName]
  $parameterName = [string]$option.Parameter
  if ($boundParameters.ContainsKey($parameterName)) {
    Stop-Cli "Option '$optionName' wurde mehrfach angegeben."
  }

  if ($option.Kind -eq "switch") {
    if ($hasInlineValue) {
      Stop-Cli "Schalter '$optionName' akzeptiert keinen Wert."
    }
    $boundParameters[$parameterName] = $true
    continue
  }

  if ($hasInlineValue) {
    $rawValue = [string]$inlineValue
  } else {
    if (($index + 1) -ge $arguments.Count) {
      Stop-Cli "Fehlender Wert fuer $optionName."
    }
    $index++
    $rawValue = [string]$arguments[$index]
  }
  $boundParameters[$parameterName] = ConvertTo-CliValue -RawValue $rawValue -OptionName $optionName -Option $option
}

foreach ($requiredOptionName in $definition.Required) {
  $requiredParameter = [string]$definition.Options[$requiredOptionName].Parameter
  if (-not $boundParameters.ContainsKey($requiredParameter)) {
    Stop-Cli "Pflichtoption $requiredOptionName fehlt fuer '$commandName'."
  }
}

if ($commandName -ne "diagnose") {
  try {
    $platformModule = Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "Common") -ChildPath "Platform.psm1"
    Import-Module -Name $platformModule -Force -ErrorAction Stop
    $platform = Get-PlatformInfo
  } catch {
    Stop-Cli "Plattform konnte nicht sicher geprüft werden: $($_.Exception.Message)"
  }
  if (-not $platform.Supported) {
    $distribution = if ($platform.IsLinux) { " $($platform.DistributionId) $($platform.DistributionVersion)" } else { "" }
    Stop-Cli "Nicht unterstützte Umgebung: $($platform.Name)$distribution, Architektur $($platform.Architecture). Unterstützt werden Windows x64 und Ubuntu 24.04 x86_64."
  }
}

$targetPath = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath $definition.RelativePath))
if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
  [Console]::Error.WriteLine("Fehler: Zugeordnetes Werkzeug fehlt: $targetPath")
  exit 1
}

try {
  $global:LASTEXITCODE = 0
  & $targetPath @boundParameters
  $toolExitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
} catch {
  [Console]::Error.WriteLine("Fehler: Subcommand '$commandName' konnte nicht ausgefuehrt werden: $($_.Exception.Message)")
  exit 1
}

if ($toolExitCode -eq 0) {
  exit 0
}
if ($toolExitCode -eq 2) {
  exit 2
}
exit 1
