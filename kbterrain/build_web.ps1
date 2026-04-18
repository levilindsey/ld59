# Build script for the kbterrain GDExtension for Web (Emscripten).
#
# Prereq: the Emscripten SDK (emsdk) must be activated in the shell
# before running this. Typically:
#     & <emsdk>\emsdk_env.ps1
# which puts emcc, em++, and friends on PATH.

param(
	[switch]$Debug,
	[switch]$Release,
	[switch]$Both
)

$ErrorActionPreference = "Stop"

function Write-Success { param($msg) Write-Host $msg -ForegroundColor Green }
function Write-Info    { param($msg) Write-Host $msg -ForegroundColor Cyan }
function Write-Err     { param($msg) Write-Host $msg -ForegroundColor Red }

Write-Info "=== kbterrain Web Build ==="

if (-not $Debug -and -not $Release -and -not $Both) {
	Write-Info "No target specified, building both debug and release."
	$Both = $true
}
if ($Both) {
	$Debug = $true
	$Release = $true
}

Set-Location $PSScriptRoot

if (-not (Get-Command emcc -ErrorAction SilentlyContinue)) {
	Write-Err "emcc not found on PATH. Activate the Emscripten SDK first."
	exit 1
}

if (-not (Test-Path "godot-cpp\SConstruct")) {
	Write-Err "godot-cpp submodule is missing. Run: git submodule update --init --recursive"
	exit 1
}

if ($Debug) {
	Write-Info "Building template_debug..."
	scons platform=web target=template_debug
	if ($LASTEXITCODE -ne 0) { Write-Err "Debug build failed."; exit 1 }
	scons platform=web target=template_debug install
}

if ($Release) {
	Write-Info "Building template_release..."
	scons platform=web target=template_release
	if ($LASTEXITCODE -ne 0) { Write-Err "Release build failed."; exit 1 }
	scons platform=web target=template_release install
}

Write-Success "=== Build complete ==="
Write-Info "Output: addons\kbterrain\bin\"
Get-ChildItem -Path "..\addons\kbterrain\bin" -Filter "*.wasm" -ErrorAction SilentlyContinue |
	ForEach-Object { Write-Info "  - $($_.Name)" }
