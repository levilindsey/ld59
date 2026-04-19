# Regenerate the procedural placeholder textures as PNG files under
# `assets/images/placeholders/`. Overwrites any existing PNGs — edit
# the PNG directly (Aseprite, etc.) if you want to keep hand-tuned
# art, and avoid re-running this script afterwards.
#
# Usage (from the repo root):
#   powershell -ExecutionPolicy Bypass -File scripts/dump_placeholder_textures.ps1
#
# Requires Godot 4.6.x on PATH.

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $RepoRoot
try {
    & godot --headless --path . -s scripts/dump_placeholder_textures.gd
} finally {
    Pop-Location
}

Write-Host "Placeholder textures regenerated under assets/images/placeholders/" -ForegroundColor Green
Write-Host "Re-import in the editor (or run --headless --import) so Godot picks up the new pixels."
