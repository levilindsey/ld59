# Generate a procedural level. Wraps the headless Godot runner.
#
# Usage (from the repo root):
#   powershell -ExecutionPolicy Bypass -File scripts/generate_level.ps1
#   powershell -ExecutionPolicy Bypass -File scripts/generate_level.ps1 -Seed 42
#   powershell -ExecutionPolicy Bypass -File scripts/generate_level.ps1 `
#       -Seed 42 -Width 80 -Height 48 -Budget 8 -Platforms 10 `
#       -Output res://src/level/generated_level.tscn
#
# Requires Godot 4.6.x on PATH.

param(
    [int]$Seed = -1,
    [int]$Width = 72,
    [int]$Height = 40,
    [int]$Budget = 6,
    [int]$Platforms = 8,
    [string]$Template = "res://src/level/terrain_level.tscn",
    [string]$Output = "res://src/level/generated_level.tscn"
)

$ErrorActionPreference = "Stop"

if ($Seed -lt 0) {
    # Godot's randi returns 0..2^31-1; match that range for consistency.
    $Seed = Get-Random -Minimum 0 -Maximum 2147483647
    Write-Host "No seed given; using random seed $Seed" -ForegroundColor Yellow
}

$RepoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $RepoRoot
try {
    # The Procgen autoload reads `--procgen-seed` etc. on _ready and
    # runs the generator, then quits. This path works under full
    # engine boot (autoloads available) unlike `-s`.
    & godot --headless -- `
            --procgen-seed $Seed `
            --width $Width `
            --height $Height `
            --budget $Budget `
            --platforms $Platforms `
            --template $Template `
            --output $Output
    # Godot often exits with non-zero/null code even after successful
    # headless runs (ObjectDB leak warnings bump status). Trust the
    # output file rather than $LASTEXITCODE.
} finally {
    Pop-Location
}

$OutputFsPath = $Output -replace "^res://", ""
$OutputAbsPath = Join-Path $RepoRoot $OutputFsPath
if (-not (Test-Path $OutputAbsPath)) {
    throw "Generator did not produce $OutputAbsPath. See log above."
}

Write-Host "Generated level: $Output" -ForegroundColor Green
Write-Host "To play: edit settings.tres and point default_level_scene at it,"
Write-Host "         or run the level scene directly in the editor."
