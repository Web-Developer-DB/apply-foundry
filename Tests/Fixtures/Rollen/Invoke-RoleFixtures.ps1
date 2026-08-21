#requires -Version 7.6
#requires -PSEdition Core

[CmdletBinding()]
param([string]$BerichtPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
$runner = Join-Path $repoRoot 'Tests/Run-RegressionTests.ps1'
$phasePattern = '^(Schema-5-Rollenfixtures prüfen vier synthetische Eignungs- und Dokumentumfänge|Ordnerhelfer legt portablen Schema-5-Auftrag mit Dokumentumfang und Logistik-Snapshot an|Dialogvalidator erzwingt Fragepflichtfelder und konsistente Blocker|Inhaltsprüfer akzeptiert vollständigen Anforderungs- und Zeitraumabgleich|Finalisierung veröffentlicht validiertes Set atomar|Sichtfreigabe bindet ID und Artefaktsatz an den aktuellen Bericht)$'
$arguments = @('-Suite', 'vollstaendig', '-TestNamePattern', $phasePattern)
if (-not [string]::IsNullOrWhiteSpace($BerichtPath)) { $arguments += @('-BerichtPath', $BerichtPath) }
& (Get-Process -Id $PID).Path -NoProfile -File $runner @arguments
exit ([int]$LASTEXITCODE)
