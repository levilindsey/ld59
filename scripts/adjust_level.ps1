# Apply a targeted adjustment to a previously generated level, then
# re-run the validator. Wraps the Procgen autoload's adjust path.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts/adjust_level.ps1 `
#       -Op validate
#   powershell -ExecutionPolicy Bypass -File scripts/adjust_level.ps1 `
#       -Op carve_rect -Rect "10,5,30,3"
#   powershell -ExecutionPolicy Bypass -File scripts/adjust_level.ps1 `
#       -Op paint_rect -Rect "40,10,8,4" -Type GREEN
#   powershell -ExecutionPolicy Bypass -File scripts/adjust_level.ps1 `
#       -Op remove_entity -Name "BugSpawnRegion_(18, 29)"
#
# Ops:
#   validate        — load the scene, run the validator, report, quit.
#                     No saves, no mutation.
#   carve_rect      — clear a rectangle to NONE. Needs -Rect.
#   paint_rect      — fill a rectangle with a Frequency type. Needs
#                     -Rect and -Type (RED/GREEN/BLUE/YELLOW/LIQUID/
#                     SAND/INDESTRUCTIBLE/WEB_RED/WEB_GREEN/WEB_BLUE/
#                     WEB_YELLOW).
#   remove_entity   — remove a child node from the level root by
#                     exact name. Needs -Name.
#
# Rect format: "x,y,w,h" in tile units.

param(
    [Parameter(Mandatory=$true)][string]$Op,
    [string]$InputPath = "res://src/level/generated_level.tscn",
    [string]$Output = "",
    [string]$Rect = "",
    [string]$Type = "",
    [string]$Name = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrEmpty($Output)) {
    $Output = $InputPath
}

$RepoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $RepoRoot
try {
    $godotArgs = @("--headless", "--", "--procgen-adjust", $Op, "--input", $InputPath, "--output", $Output)
    if ($Rect -ne "") { $godotArgs += @("--rect", $Rect) }
    if ($Type -ne "") { $godotArgs += @("--type", $Type) }
    if ($Name -ne "") { $godotArgs += @("--name", $Name) }
    & godot @godotArgs
} finally {
    Pop-Location
}
