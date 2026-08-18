#requires -Version 7.6
#requires -PSEdition Core

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Arbeitsordner,

  [Parameter(Mandatory = $true)]
  [ValidateSet(
    'auftrag_angelegt',
    'profilabgleich_abgeschlossen',
    'analyse_abgeschlossen',
    'dokumente_abgeschlossen',
    'fachpruefung_abgeschlossen',
    'technische_vorbereitung_abgeschlossen',
    'sichtpruefung_bestaetigt',
    'veroeffentlicht'
  )]
  [string]$Schritt,

  [switch]$AlsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath 'Common/WorkflowCheckpoint.psm1') -Force

try {
  $checkpoint = Write-WorkflowCheckpoint -Arbeitsordner $Arbeitsordner -Schritt $Schritt
} catch {
  [Console]::Error.WriteLine("Fehler: Workflow-Checkpoint konnte nicht sicher aktualisiert werden: $($_.Exception.Message)")
  exit 2
}

if ($AlsJson) {
  $checkpoint | ConvertTo-Json -Depth 5
} else {
  Write-Host "[OK] Workflow-Checkpoint aktualisiert: $($checkpoint.path)" -ForegroundColor Green
  Write-Host "Schritt: $($checkpoint.step)"
  Write-Host "Gebundene Arbeitsartefakte: $($checkpoint.artifactCount)"
}
