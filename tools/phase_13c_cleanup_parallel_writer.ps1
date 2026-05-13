$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$parallelWriter = Join-Path $root "lib\features\writer\presentation\paged_document"
$badPagedSurface = Join-Path $root "lib\features\text_system\page\text_system_paged_document_surface.dart"

if (Test-Path $parallelWriter) {
  Remove-Item $parallelWriter -Recurse -Force
  Write-Host "Removed accidental parallel paged writer: $parallelWriter"
} else {
  Write-Host "No accidental parallel paged writer folder found."
}

if (Test-Path $badPagedSurface) {
  Remove-Item $badPagedSurface -Force
  Write-Host "Removed unstable page-local TextField projection: $badPagedSurface"
} else {
  Write-Host "No unstable page-local projection file found."
}

Write-Host "Next: flutter analyze"
