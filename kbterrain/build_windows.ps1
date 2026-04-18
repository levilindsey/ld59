# Build script for the kbterrain GDExtension on Windows.

param(
	[switch]$Debug,
	[switch]$Release,
	[switch]$Both
)

$ErrorActionPreference = "Stop"

function Write-Success { param($msg) Write-Host $msg -ForegroundColor Green }
function Write-Info    { param($msg) Write-Host $msg -ForegroundColor Cyan }
function Write-Warn    { param($msg) Write-Host $msg -ForegroundColor Yellow }
function Write-Err     { param($msg) Write-Host $msg -ForegroundColor Red }

Write-Info "=== kbterrain Windows Build ==="

if (-not $Debug -and -not $Release -and -not $Both) {
	Write-Info "No target specified, building both debug and release."
	$Both = $true
}
if ($Both) {
	$Debug = $true
	$Release = $true
}

Set-Location $PSScriptRoot

Write-Info "Checking prerequisites..."
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
	Write-Err "Python not found on PATH."
	exit 1
}
if (-not (Get-Command scons -ErrorAction SilentlyContinue)) {
	Write-Warn "SCons not found, installing via pip..."
	python -m pip install scons
}

if (-not (Test-Path "godot-cpp\SConstruct")) {
	Write-Err "godot-cpp submodule is missing. Run: git submodule update --init --recursive"
	exit 1
}

if ($Debug) {
	Write-Info "Building template_debug..."
	scons platform=windows target=template_debug
	if ($LASTEXITCODE -ne 0) { Write-Err "Debug build failed."; exit 1 }
	scons platform=windows target=template_debug install
}

if ($Release) {
	Write-Info "Building template_release..."
	scons platform=windows target=template_release
	if ($LASTEXITCODE -ne 0) { Write-Err "Release build failed."; exit 1 }
	scons platform=windows target=template_release install
}

Write-Success "=== Build complete ==="
Write-Info "Output: addons\kbterrain\bin\"
Get-ChildItem -Path "..\addons\kbterrain\bin" -Filter "*.dll" -ErrorAction SilentlyContinue |
	ForEach-Object { Write-Info "  - $($_.Name)" }
