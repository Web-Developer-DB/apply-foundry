[CmdletBinding()]
param(
  [switch]$MitBrowser
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$toolsRoot = Join-Path -Path $repoRoot -ChildPath "Tools"
$powerShellExe = (Get-Process -Id $PID).Path
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("bewerbungs-agent-tests-" + [guid]::NewGuid().ToString("N"))
$passed = New-Object System.Collections.Generic.List[string]
$failed = New-Object System.Collections.Generic.List[string]

function Invoke-ChildScript {
  param(
    [string]$ScriptPath,
    [string[]]$Arguments
  )

  $output = & $powerShellExe -NoProfile -File $ScriptPath @Arguments 2>&1
  return [pscustomobject]@{
    ExitCode = $LASTEXITCODE
    Output = @($output)
  }
}

function Assert-True {
  param(
    [bool]$Condition,
    [string]$Message
  )

  if (-not $Condition) {
    throw $Message
  }
}

function Invoke-Test {
  param(
    [string]$Name,
    [scriptblock]$Body
  )

  try {
    & $Body
    $passed.Add($Name) | Out-Null
    Write-Host "[OK] $Name" -ForegroundColor Green
  } catch {
    $failed.Add("${Name}: $($_.Exception.Message)") | Out-Null
    Write-Host "[FEHLER] ${Name}: $($_.Exception.Message)" -ForegroundColor Red
  }
}

function New-ValidApplicationFixture {
  param(
    [string]$Root,
    [string]$Company = "Audit-Firma",
    [string]$Role = "2026-07-14--Audit-Rolle"
  )

  $folder = Join-Path -Path $Root -ChildPath "Private/Bewerbungen/$Company/$Role"
  New-Item -Path $folder -ItemType Directory -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $folder "Stellenbeschreibung.md") -Encoding UTF8 -Value "Fiktive Teststelle"
  Set-Content -LiteralPath (Join-Path $folder "Analyse.md") -Encoding UTF8 -Value "Fiktive Analyse"
  Set-Content -LiteralPath (Join-Path $folder "Qualitaetscheck.md") -Encoding UTF8 -Value "Fiktiver Qualitätscheck"
  Set-Content -LiteralPath (Join-Path $folder "Druck-Hinweis.md") -Encoding UTF8 -Value "Fiktiver Druckhinweis"
  Set-Content -LiteralPath (Join-Path $folder "Email-Nachricht--Audit-Firma.md") -Encoding UTF8 -Value @"
Betreff: Bewerbung als Audit-Rolle - Test Person

Sehr geehrte Damen und Herren,

anbei sende ich Ihnen meine Bewerbungsunterlagen.

Mit freundlichen Grüßen
Test Person
"@

  $html = @"
<!doctype html>
<html lang="de">
<head>
  <meta charset="utf-8">
  <style>
    @page { size: A4; margin: 0; }
    * { box-sizing: border-box; }
    html, body { margin: 0; padding: 0; }
    .page { width: 210mm; height: 297mm; margin: 0; overflow: hidden; background: #fff; }
  </style>
</head>
<body><main class="page"><h1>Fiktiver Testinhalt</h1></main></body>
</html>
"@
  Set-Content -LiteralPath (Join-Path $folder "Lebenslauf - TEST.PERSON.html") -Encoding UTF8 -Value $html
  Set-Content -LiteralPath (Join-Path $folder "Anschreiben - TEST.PERSON.html") -Encoding UTF8 -Value $html
  return $folder
}

function Test-PngSignature {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return $false
  }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -lt 8) {
    return $false
  }
  $signature = @(137, 80, 78, 71, 13, 10, 26, 10)
  for ($index = 0; $index -lt $signature.Count; $index++) {
    if ($bytes[$index] -ne $signature[$index]) {
      return $false
    }
  }
  return $true
}

New-Item -Path $testRoot -ItemType Directory | Out-Null
try {
  Invoke-Test -Name "PowerShell-Dateien sind syntaktisch gültig" -Body {
    foreach ($file in Get-ChildItem -LiteralPath $toolsRoot -Filter "*.ps1" -File) {
      $tokens = $null
      $parseErrors = $null
      [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
      Assert-True -Condition ($parseErrors.Count -eq 0) -Message "$($file.Name) enthält Parserfehler."
    }
  }

  Invoke-Test -Name "Gültige Bewerbung besteht den statischen Prüfer" -Body {
    $folder = New-ValidApplicationFixture -Root (Join-Path $testRoot "valid")
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Pruefe-Bewerbung.ps1") -Arguments @("-Ordner", $folder)
    Assert-True -Condition ($result.ExitCode -eq 0) -Message "Gültige Fixture wurde abgelehnt: $($result.Output -join ' | ')"
  }

  Invoke-Test -Name "Initiativbewerbung gilt als konkreter E-Mail-Betreff" -Body {
    $folder = New-ValidApplicationFixture -Root (Join-Path $testRoot "initiative-subject")
    $path = Join-Path $folder "Email-Nachricht--Audit-Firma.md"
    $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $text = $text.Replace("Betreff: Bewerbung als Audit-Rolle", "Betreff: Initiativbewerbung IT")
    Set-Content -LiteralPath $path -Value $text -Encoding UTF8
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Pruefe-Bewerbung.ps1") -Arguments @("-Ordner", $folder)
    Assert-True -Condition ($result.ExitCode -eq 0) -Message "Korrekte Initiativbewerbung wurde abgelehnt: $($result.Output -join ' | ')"
  }

  Invoke-Test -Name "Mehrfach defekte Bewerbung wird abgelehnt" -Body {
    $folder = New-ValidApplicationFixture -Root (Join-Path $testRoot "invalid")
    Remove-Item -LiteralPath (Join-Path $folder "Analyse.md") -Force
    New-Item -Path (Join-Path $folder "Analyse.md") -ItemType Directory | Out-Null
    Set-Content -LiteralPath (Join-Path $folder "Qualitaetscheck.md") -Value "" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $folder "Email-Nachricht--Audit-Firma.md") -Value "Anbei die Bewerbung." -Encoding UTF8
    $badHtml = @"
Text vor dem Doctype
<!doctype html><html lang="de"><head><style>
@page { size: A4; margin: 0; }
.page { width: 210mm; min-height: 297mm; }
.page .secret { overflow: hidden; }
</style></head><body>
<main class="page"><div class="secret">Seite 1</div></main>
<main class="page">Seite 2</main>
</body></html>
"@
    Set-Content -LiteralPath (Join-Path $folder "Lebenslauf - TEST.PERSON.html") -Value $badHtml -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $folder "Anschreiben - TEST.PERSON.html") -Value $badHtml -Encoding UTF8
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Pruefe-Bewerbung.ps1") -Arguments @("-Ordner", $folder)
    Assert-True -Condition ($result.ExitCode -ne 0) -Message "Defekte Fixture wurde fälschlich akzeptiert."
  }

  Invoke-Test -Name "Automatisch ladende externe Ressourcen werden abgelehnt" -Body {
    $folder = New-ValidApplicationFixture -Root (Join-Path $testRoot "external")
    $path = Join-Path $folder "Anschreiben - TEST.PERSON.html"
    $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $text = $text.Replace('<meta charset="utf-8">', '<meta charset="utf-8"><link rel="stylesheet" href="https://example.invalid/external.css">')
    Set-Content -LiteralPath $path -Value $text -Encoding UTF8
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Pruefe-Bewerbung.ps1") -Arguments @("-Ordner", $folder)
    Assert-True -Condition ($result.ExitCode -ne 0) -Message "Externe Ressource wurde fälschlich akzeptiert."
  }

  Invoke-Test -Name "Relative lokale Ressourcen werden ebenfalls abgelehnt" -Body {
    $folder = New-ValidApplicationFixture -Root (Join-Path $testRoot "relative-resource")
    $path = Join-Path $folder "Anschreiben - TEST.PERSON.html"
    $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $text = $text.Replace('<h1>Fiktiver Testinhalt</h1>', '<h1>Fiktiver Testinhalt</h1><img src="lokales-foto.png" alt="Test">')
    Set-Content -LiteralPath $path -Value $text -Encoding UTF8
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Pruefe-Bewerbung.ps1") -Arguments @("-Ordner", $folder)
    Assert-True -Condition ($result.ExitCode -ne 0) -Message "Relative automatisch geladene Ressource wurde fälschlich akzeptiert."
  }

  Invoke-Test -Name "Unmögliches Kalenderdatum wird vor jeder Ausgabe abgelehnt" -Body {
    $root = Join-Path $testRoot "invalid-date-root"
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Neue-Bewerbung.ps1") -Arguments @("-Firma", "Audit Firma", "-Rolle", "Audit Rolle", "-Datum", "2026-99-99", "-BewerbungenRoot", $root)
    Assert-True -Condition ($result.ExitCode -eq 2) -Message "Ungültiges Datum lieferte Exitcode $($result.ExitCode)."
    Assert-True -Condition (-not (Test-Path -LiteralPath $root)) -Message "Trotz ungültigem Datum wurde ein Ausgabeordner erstellt."
  }

  Invoke-Test -Name "Verzeichnis als Stellenbeschreibung wird ohne Teilstruktur abgelehnt" -Body {
    $source = Join-Path $testRoot "source-directory"
    New-Item -Path $source -ItemType Directory | Out-Null
    $root = Join-Path $testRoot "directory-source-root"
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Neue-Bewerbung.ps1") -Arguments @("-Firma", "Audit Firma", "-Rolle", "Audit Rolle", "-Datum", "2026-07-14", "-StellenbeschreibungPath", $source, "-BewerbungenRoot", $root)
    Assert-True -Condition ($result.ExitCode -eq 2) -Message "Verzeichnisquelle lieferte Exitcode $($result.ExitCode)."
    Assert-True -Condition (-not (Test-Path -LiteralPath $root)) -Message "Trotz ungültiger Quelle wurde ein Ausgabeordner erstellt."
  }

  Invoke-Test -Name "Datei als BewerbungenRoot wird als Fehler gemeldet" -Body {
    $rootFile = Join-Path $testRoot "root-is-file"
    Set-Content -LiteralPath $rootFile -Value "keine Verzeichnisstruktur" -Encoding UTF8
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Neue-Bewerbung.ps1") -Arguments @("-Firma", "Audit Firma", "-Rolle", "Audit Rolle", "-Datum", "2026-07-14", "-BewerbungenRoot", $rootFile)
    Assert-True -Condition ($result.ExitCode -eq 2) -Message "Datei als Root lieferte Exitcode $($result.ExitCode)."
    Assert-True -Condition (-not ($result.Output -match '^Bewerbungsordner:')) -Message "Fehlerhafter Lauf meldete einen Bewerbungsordner als Erfolg."
  }

  Invoke-Test -Name "Slug-Kollision überschreibt keine vorhandene Bewerbung" -Body {
    $root = Join-Path $testRoot "collision-root"
    $sourceOne = Join-Path $testRoot "job-one.md"
    $sourceTwo = Join-Path $testRoot "job-two.md"
    Set-Content -LiteralPath $sourceOne -Value "JOB-ONE" -Encoding UTF8
    Set-Content -LiteralPath $sourceTwo -Value "JOB-TWO" -Encoding UTF8
    $first = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Neue-Bewerbung.ps1") -Arguments @("-Firma", "A+B", "-Rolle", "Audit", "-Datum", "2026-07-14", "-StellenbeschreibungPath", $sourceOne, "-BewerbungenRoot", $root)
    $second = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Neue-Bewerbung.ps1") -Arguments @("-Firma", "A B", "-Rolle", "Audit", "-Datum", "2026-07-14", "-StellenbeschreibungPath", $sourceTwo, "-BewerbungenRoot", $root)
    Assert-True -Condition ($first.ExitCode -eq 0) -Message "Erster Lauf schlug fehl."
    Assert-True -Condition ($second.ExitCode -eq 2) -Message "Kollisionslauf wurde nicht mit Exitcode 2 abgelehnt."
    $finalJob = Join-Path $root "A-B/2026-07-14--Audit/Stellenbeschreibung.md"
    Assert-True -Condition ((Get-Content -LiteralPath $finalJob -Raw -Encoding UTF8).Trim() -eq "JOB-ONE") -Message "Vorhandene Stellenbeschreibung wurde verändert."
  }

  Invoke-Test -Name "Exakt dieselbe Bewerbung kann explizit fortgesetzt werden" -Body {
    $root = Join-Path $testRoot "resume-root"
    $source = Join-Path $testRoot "resume-job.md"
    Set-Content -LiteralPath $source -Value "GLEICHE-STELLE" -Encoding UTF8
    $arguments = @("-Firma", "Audit Firma", "-Rolle", "Audit Rolle", "-Datum", "2026-07-14", "-StellenbeschreibungPath", $source, "-BewerbungenRoot", $root)
    $first = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Neue-Bewerbung.ps1") -Arguments $arguments
    $second = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Neue-Bewerbung.ps1") -Arguments @($arguments + "-Fortsetzen")
    Assert-True -Condition (($first.ExitCode -eq 0) -and ($second.ExitCode -eq 0)) -Message "Sicheres Fortsetzen schlug fehl."
  }

  Invoke-Test -Name "Unvollständige Bewerbung kann nicht blind fortgesetzt werden" -Body {
    $root = Join-Path $testRoot "incomplete-resume-root"
    New-Item -Path (Join-Path $root "Audit-Firma/2026-07-14--Audit-Rolle") -ItemType Directory -Force | Out-Null
    $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Neue-Bewerbung.ps1") -Arguments @("-Firma", "Audit Firma", "-Rolle", "Audit Rolle", "-Datum", "2026-07-14", "-BewerbungenRoot", $root, "-Fortsetzen")
    Assert-True -Condition ($result.ExitCode -eq 2) -Message "Unvollständige Bewerbung wurde mit Exitcode $($result.ExitCode) fortgesetzt."
  }

  Invoke-Test -Name "Verzeichnis kann Stellenbeschreibung beim Fortsetzen nicht ersetzen" -Body {
    $root = Join-Path $testRoot "job-directory-resume-root"
    $source = Join-Path $testRoot "job-directory-resume.md"
    Set-Content -LiteralPath $source -Value "FIKTIVE STELLE" -Encoding UTF8
    $arguments = @("-Firma", "Audit Firma", "-Rolle", "Audit Rolle", "-Datum", "2026-07-14", "-BewerbungenRoot", $root)
    $first = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Neue-Bewerbung.ps1") -Arguments $arguments
    Assert-True -Condition ($first.ExitCode -eq 0) -Message "Vorbereitung der Fixture schlug fehl."
    $jobPath = Join-Path $root "Audit-Firma/2026-07-14--Audit-Rolle/Stellenbeschreibung.md"
    New-Item -Path $jobPath -ItemType Directory | Out-Null
    $second = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Neue-Bewerbung.ps1") -Arguments @($arguments + @("-StellenbeschreibungPath", $source, "-Fortsetzen"))
    Assert-True -Condition ($second.ExitCode -ne 0) -Message "Stellenbeschreibungs-Verzeichnis wurde beim Fortsetzen akzeptiert."
    Assert-True -Condition (@(Get-ChildItem -LiteralPath $jobPath -Force).Count -eq 0) -Message "Quelldatei wurde in das Stellenbeschreibungs-Verzeichnis kopiert."
  }

  $gitBash = Join-Path $env:USERPROFILE "scoop/apps/git/current/bin/bash.exe"
  if (Test-Path -LiteralPath $gitBash -PathType Leaf) {
    Invoke-Test -Name "Bash-Regressionssuite besteht" -Body {
      & $gitBash (Join-Path $PSScriptRoot "Bash/test-neue-bewerbung.sh")
      Assert-True -Condition ($LASTEXITCODE -eq 0) -Message "Bash-Regressionssuite lieferte Exitcode $LASTEXITCODE."
    }
  } else {
    Write-Host "[INFO] Git Bash nicht gefunden; Bash-Lauf wird in CI ausgeführt."
  }

  if ($MitBrowser) {
    $chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"
    if (-not (Test-Path -LiteralPath $chrome -PathType Leaf)) {
      Write-Host "[INFO] Chrome nicht gefunden; Browser-Regressionsfälle übersprungen."
    } else {
      Invoke-Test -Name "Layoutcheck akzeptiert keine unveränderten Pseudo-PNGs" -Body {
        $folder = New-ValidApplicationFixture -Root (Join-Path $testRoot "layout-browser")
        $companyDir = Split-Path -Path $folder -Parent
        $roleDir = Split-Path -Path $folder -Leaf
        $layoutDir = Join-Path $companyDir "_Arbeitsdateien/$roleDir/Layoutcheck"
        New-Item -Path $layoutDir -ItemType Directory -Force | Out-Null
        $fake = New-Object byte[] 6001
        for ($index = 0; $index -lt $fake.Length; $index++) {
          $fake[$index] = 65
        }
        $fakePaths = @(
          (Join-Path $layoutDir "Anschreiben---TEST.PERSON--chrome.png"),
          (Join-Path $layoutDir "Lebenslauf---TEST.PERSON--chrome.png")
        )
        foreach ($path in $fakePaths) {
          [System.IO.File]::WriteAllBytes($path, $fake)
          (Get-Item -LiteralPath $path).IsReadOnly = $true
        }
        $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Layoutcheck-Bewerbung.ps1") -Arguments @("-Ordner", $folder, "-Browser", "chrome", "-TimeoutSeconds", "60")
        Assert-True -Condition ($result.ExitCode -eq 0) -Message "Layoutcheck konnte die Pseudo-PNGs nicht durch frische Screenshots ersetzen: $($result.Output -join ' | ')"
        foreach ($path in $fakePaths) {
          Assert-True -Condition (Test-PngSignature -Path $path) -Message "Layoutcheck akzeptierte eine unveränderte Pseudo-PNG-Datei."
        }
      }

      Invoke-Test -Name "PDF-Export lehnt zusätzliche Druckseiten ab" -Body {
        $folder = New-ValidApplicationFixture -Root (Join-Path $testRoot "overflow-pdf")
        foreach ($html in Get-ChildItem -LiteralPath $folder -Filter "*.html" -File) {
          $text = Get-Content -LiteralPath $html.FullName -Raw -Encoding UTF8
          $text = $text.Replace('</body>', '<section style="width:210mm;height:297mm;background:#fff">Absichtlich zusätzliche Druckseite</section></body>')
          Set-Content -LiteralPath $html.FullName -Value $text -Encoding UTF8
        }
        $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Exportiere-PDF.ps1") -Arguments @("-Ordner", $folder, "-Browser", "chrome", "-TimeoutSeconds", "60")
        Assert-True -Condition ($result.ExitCode -ne 0) -Message "PDF mit zusätzlichen Druckseiten wurde fälschlich akzeptiert."
        Assert-True -Condition (($result.Output -join "`n") -match "PDF-Seitenzahl stimmt nicht mit dem HTML überein") -Message "Export scheiterte nicht aus dem erwarteten Seitenzahl-Grund: $($result.Output -join ' | ')"
        Assert-True -Condition (@(Get-ChildItem -LiteralPath $folder -Filter "*.pdf" -File).Count -eq 0) -Message "Fehlgeschlagener Export hinterließ finale PDFs."
      }

      Invoke-Test -Name "Erfolgreicher PDF-Export ersetzt alte Dateien nach Validierung" -Body {
        $folder = New-ValidApplicationFixture -Root (Join-Path $testRoot "valid-pdf")
        $first = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Exportiere-PDF.ps1") -Arguments @("-Ordner", $folder, "-Browser", "chrome", "-TimeoutSeconds", "60")
        Assert-True -Condition ($first.ExitCode -eq 0) -Message "Erster gültiger PDF-Export schlug fehl: $($first.Output -join ' | ')"
        $pdfs = @(Get-ChildItem -LiteralPath $folder -Filter "*.pdf" -File)
        Assert-True -Condition ($pdfs.Count -eq 2) -Message "Es wurden nicht genau zwei PDFs erzeugt."
        $hashes = @{}
        foreach ($pdf in $pdfs) {
          $hashes[$pdf.FullName] = (Get-FileHash -LiteralPath $pdf.FullName -Algorithm SHA256).Hash
          $pdf.IsReadOnly = $true
        }
        foreach ($html in Get-ChildItem -LiteralPath $folder -Filter "*.html" -File) {
          $text = Get-Content -LiteralPath $html.FullName -Raw -Encoding UTF8
          $text = $text.Replace("Fiktiver Testinhalt", "Geänderter sichtbarer Testinhalt")
          Set-Content -LiteralPath $html.FullName -Value $text -Encoding UTF8
        }
        $second = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Exportiere-PDF.ps1") -Arguments @("-Ordner", $folder, "-Browser", "chrome", "-TimeoutSeconds", "60")
        Assert-True -Condition ($second.ExitCode -eq 0) -Message "Zweiter gültiger PDF-Export schlug fehl: $($second.Output -join ' | ')"
        foreach ($pdf in Get-ChildItem -LiteralPath $folder -Filter "*.pdf" -File) {
          Assert-True -Condition ($hashes[$pdf.FullName] -ne (Get-FileHash -LiteralPath $pdf.FullName -Algorithm SHA256).Hash) -Message "Alter PDF-Inhalt wurde trotz Erfolg unverändert weiterverwendet."
        }
      }

      Invoke-Test -Name "PDF-Zielverzeichnis wird nicht als Datei behandelt" -Body {
        $folder = New-ValidApplicationFixture -Root (Join-Path $testRoot "pdf-target-directory")
        $invalidTarget = Join-Path $folder "Anschreiben - TEST.PERSON.pdf"
        New-Item -Path $invalidTarget -ItemType Directory | Out-Null
        $result = Invoke-ChildScript -ScriptPath (Join-Path $toolsRoot "Exportiere-PDF.ps1") -Arguments @("-Ordner", $folder, "-Browser", "chrome", "-TimeoutSeconds", "60")
        Assert-True -Condition ($result.ExitCode -ne 0) -Message "PDF-Zielverzeichnis wurde als gültige Datei behandelt."
        Assert-True -Condition (($result.Output -join "`n") -match "keine reguläre Datei") -Message "Unerwarteter Fehlergrund für PDF-Zielverzeichnis: $($result.Output -join ' | ')"
      }
    }
  }
} finally {
  if (Test-Path -LiteralPath $testRoot -PathType Container) {
    Get-ChildItem -LiteralPath $testRoot -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { $_.IsReadOnly = $false }
    $fullTestRoot = [System.IO.Path]::GetFullPath($testRoot)
    $fullTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($fullTestRoot.StartsWith($fullTempRoot, [System.StringComparison]::OrdinalIgnoreCase) -and ((Split-Path -Leaf $fullTestRoot) -like "bewerbungs-agent-tests-*")) {
      Remove-Item -LiteralPath $fullTestRoot -Recurse -Force
    }
  }
}

Write-Host ""
Write-Host "Testergebnis: $($passed.Count) bestanden, $($failed.Count) fehlgeschlagen."
foreach ($failure in $failed) {
  Write-Host "- $failure" -ForegroundColor Red
}

if ($failed.Count -gt 0) {
  exit 1
}
exit 0
