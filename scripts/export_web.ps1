# Exports the Kittenbaticorn project to build/web/ using the "Web"
# preset in export_presets.cfg, then zips build/web/ into a deploy
# artifact for hosting upload (itch.io, Cloudflare Pages, etc).
#
# Prereqs:
#   - Godot 4.6.x on PATH.
#   - Custom dlink+threads web template installed (run
#     kbterrain/build_web_template.ps1 first).
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts/export_web.ps1
#
# Options:
#   -Debug    Export the debug variant (default: release).
#   -NoZip    Skip the zip step; leave build/web/ as-is.

param(
    [switch]$Debug,
    [switch]$NoZip
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ExportDir = Join-Path $RepoRoot "build\web"
$OutputHtml = Join-Path $ExportDir "index.html"

# Clean previous export so deleted files don't linger in the zip.
if (Test-Path $ExportDir) {
    Write-Host "Clearing $ExportDir..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $ExportDir
}
New-Item -ItemType Directory -Force -Path $ExportDir | Out-Null

# Copy the COOP/COEP _headers file into the export root so Cloudflare
# Pages / Netlify pick it up when the directory is deployed as-is.
$HeadersSrc = Join-Path $RepoRoot "web\_headers"
if (Test-Path $HeadersSrc) {
    Copy-Item $HeadersSrc (Join-Path $ExportDir "_headers")
}

Push-Location $RepoRoot
try {
    $exportFlag = if ($Debug) { "--export-debug" } else { "--export-release" }
    Write-Host "Running godot $exportFlag `"Web`" $OutputHtml" -ForegroundColor Cyan
    & godot --headless $exportFlag "Web" $OutputHtml
    # Godot's headless export sometimes exits with a non-zero or null
    # code even when it successfully wrote every file (internal
    # ObjectDB-leak warning bumps exit status). Treat the presence of
    # the output html as the source of truth.
} finally {
    Pop-Location
}

if (-not (Test-Path $OutputHtml)) {
    throw "Export failed: $OutputHtml missing. Check Godot output above."
}

Write-Host "Export complete: $ExportDir" -ForegroundColor Green
Get-ChildItem $ExportDir | Select-Object Name, Length | Format-Table

if ($NoZip) {
    exit 0
}

$ZipPath = Join-Path $RepoRoot "build\kittenbaticorn-web.zip"
if (Test-Path $ZipPath) {
    Remove-Item -Force $ZipPath
}
Write-Host "Zipping $ExportDir -> $ZipPath..." -ForegroundColor Cyan
Compress-Archive -Path (Join-Path $ExportDir "*") -DestinationPath $ZipPath
$size = (Get-Item $ZipPath).Length / 1MB
Write-Host ("Deploy artifact: $ZipPath ({0:N1} MB)" -f $size) -ForegroundColor Green
Write-Host ""
Write-Host "Next: upload the zip to itch.io (check 'SharedArrayBuffer support')"
Write-Host "      or deploy build/web/ to a host with COOP/COEP headers."
