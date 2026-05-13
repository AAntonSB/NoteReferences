# Phase 13C restore cleanup
# Run from the project root: C:\Dev\NoteApp\note_references

$ErrorActionPreference = "Stop"

$pathsToRemove = @(
  "lib/features/writer/presentation/paged_document",
  "lib/features/writer/presentation",
  "lib/features/writer",
  "PHASE_13C_INTEGRATION_NOTES.md",
  "README_PHASE_13C.md",
  "README_PHASE_13AB.md"
)

foreach ($path in $pathsToRemove) {
  if (Test-Path $path) {
    if ((Get-Item $path).PSIsContainer) {
      # Only remove parent writer folders if they are empty after deleting paged_document.
      if ($path -eq "lib/features/writer/presentation" -or $path -eq "lib/features/writer") {
        $children = Get-ChildItem $path -Force
        if ($children.Count -eq 0) {
          Remove-Item $path -Recurse -Force
          Write-Host "Removed empty folder $path"
        }
      } else {
        Remove-Item $path -Recurse -Force
        Write-Host "Removed $path"
      }
    } else {
      Remove-Item $path -Force
      Write-Host "Removed $path"
    }
  }
}

Write-Host "Restore cleanup complete. Now run: flutter analyze"
