$ErrorActionPreference = "Stop"

$badFile = Join-Path $PSScriptRoot "..\lib\features\text_system\page\text_system_paged_document_surface.dart"

if (Test-Path $badFile) {
  Remove-Item $badFile -Force
  Write-Host "Removed unstable paged projection: $badFile"
} else {
  Write-Host "No unstable paged projection file found."
}

Write-Host "Run: flutter analyze"
