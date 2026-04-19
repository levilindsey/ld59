# Builds the custom Godot 4.6 web export template with GDExtension
# (`dlink_enabled=yes`) and threading (`threads=yes`) support, and
# installs it into Godot's template cache where the editor picks it
# up automatically.
#
# One-time per machine. After this succeeds, opening the Kittenbaticorn
# project and running the "Web" export preset produces a runnable
# HTML/wasm bundle in `build/web/`.
#
# Usage (from the repo root):
#   powershell -ExecutionPolicy Bypass -File kbterrain/build_web_template.ps1
#
# Optional parameters (defaults are usually fine):
#   -GodotSrcDir <path>   where to clone Godot engine source
#                         (default: ~/godot-src-4.6-stable)
#   -EmsdkDir    <path>   where to install Emscripten SDK
#                         (default: ~/emsdk)
#   -DebugOnly            skip the release build
#   -ReleaseOnly          skip the debug build
#   -SkipInstall          build but don't copy into Godot's template cache

param(
    [string]$GodotSrcDir = "$env:USERPROFILE\godot-src-4.6-stable",
    [string]$EmsdkDir = "$env:USERPROFILE\emsdk",
    [switch]$DebugOnly,
    [switch]$ReleaseOnly,
    [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"

$BuildDebug = -not $ReleaseOnly
$BuildRelease = -not $DebugOnly

$GodotBranch = "4.6-stable"
$EmscriptenVersion = "4.0.11"
# Godot looks up templates at `<version>.<status>/` where <version> is
# the full `X.Y.Z` string Godot reports (not just `X.Y`). Install into
# both the short (4.6.stable) and full (4.6.2.stable) variants so
# whichever Godot the user runs finds them. 4.6.2 is the current
# target per PLAN.md; add more entries here when upgrading.
$GodotTemplateCaches = @(
    "$env:APPDATA\Godot\export_templates\4.6.stable",
    "$env:APPDATA\Godot\export_templates\4.6.2.stable"
)

Write-Host "=== Godot web template build ===" -ForegroundColor Cyan
Write-Host "Godot source: $GodotSrcDir"
Write-Host "Emsdk:        $EmsdkDir"
Write-Host "Template cache dirs:"
foreach ($c in $GodotTemplateCaches) { Write-Host "  $c" }
Write-Host ""

# Checks / installs.
function Ensure-Command($cmd, $install_hint) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Error "Required command '$cmd' not found. $install_hint"
    }
}
Ensure-Command "git" "Install git (https://git-scm.com/)."
Ensure-Command "python" "Install Python 3.8+ (https://www.python.org/)."
Ensure-Command "scons" "scons not on PATH. Install with: python -m pip install scons"

# Godot source checkout.
if (-not (Test-Path $GodotSrcDir)) {
    Write-Host "Cloning Godot source ($GodotBranch)..." -ForegroundColor Yellow
    git clone --depth 1 -b $GodotBranch `
            https://github.com/godotengine/godot.git $GodotSrcDir
} else {
    Write-Host "Godot source present at $GodotSrcDir (skipping clone)."
}

# Emscripten SDK.
if (-not (Test-Path $EmsdkDir)) {
    Write-Host "Cloning Emscripten SDK..." -ForegroundColor Yellow
    git clone https://github.com/emscripten-core/emsdk.git $EmsdkDir
}

$emsdkBat = Join-Path $EmsdkDir "emsdk.bat"
if (-not (Test-Path $emsdkBat)) {
    Write-Error "emsdk.bat not found at $emsdkBat"
}
Write-Host "Pinning Emscripten to $EmscriptenVersion..." -ForegroundColor Yellow
& $emsdkBat install $EmscriptenVersion
if ($LASTEXITCODE -ne 0) { throw "emsdk install failed" }
& $emsdkBat activate $EmscriptenVersion
if ($LASTEXITCODE -ne 0) { throw "emsdk activate failed" }

# Prepend emsdk paths to $env:PATH manually. `emsdk_env.ps1` /
# `emsdk construct_env` don't reliably propagate env changes back to
# our PowerShell scope across versions, so we add the paths directly.
Write-Host "Activating emsdk environment (manual PATH prepend)..." `
        -ForegroundColor Yellow
$emscriptenDir = Join-Path $EmsdkDir "upstream\emscripten"
if (-not (Test-Path (Join-Path $emscriptenDir "emcc.bat"))) {
    Write-Error "emcc.bat not found at $emscriptenDir. emsdk install may not have produced the wasm-binaries tool."
}
$nodeBin = (Get-ChildItem "$EmsdkDir\node" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName)
$pyBin = (Get-ChildItem "$EmsdkDir\python" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName)
$env:EMSDK = $EmsdkDir
$env:EMSDK_NODE = if ($nodeBin) { "$nodeBin\bin\node.exe" } else { "" }
$env:EMSDK_PYTHON = if ($pyBin) { "$pyBin\python.exe" } else { "" }
$pathPrefix = "$EmsdkDir;$emscriptenDir"
if ($nodeBin) { $pathPrefix += ";$nodeBin\bin" }
if ($pyBin) { $pathPrefix += ";$pyBin" }
$env:PATH = "$pathPrefix;$env:PATH"

# Verify emcc.
if (-not (Get-Command emcc -ErrorAction SilentlyContinue)) {
    Write-Error "emcc still not on PATH after manual activation."
}
$emccVersion = (& emcc --version) -join "`n"
if ($emccVersion -notmatch [regex]::Escape($EmscriptenVersion)) {
    Write-Warning "emcc does not report $EmscriptenVersion. Continuing anyway."
}

# Build templates.
Push-Location $GodotSrcDir
try {
    # Parallelize with CPU-1 jobs so the shell stays responsive.
    $jobs = [Math]::Max(1, [Environment]::ProcessorCount - 1)
    if ($BuildDebug) {
        Write-Host "Building template_debug (web, dlink, threads, -j$jobs)..." `
                -ForegroundColor Cyan
        scons platform=web dlink_enabled=yes threads=yes `
                target=template_debug "-j$jobs"
        if ($LASTEXITCODE -ne 0) {
            throw "scons template_debug build failed"
        }
    }
    if ($BuildRelease) {
        Write-Host "Building template_release (web, dlink, threads, -j$jobs)..." `
                -ForegroundColor Cyan
        scons platform=web dlink_enabled=yes threads=yes `
                target=template_release "-j$jobs"
        if ($LASTEXITCODE -ne 0) {
            throw "scons template_release build failed"
        }
    }
} finally {
    Pop-Location
}

# Install into template cache.
if ($SkipInstall) {
    Write-Host "Skipping install step (-SkipInstall given)." -ForegroundColor Yellow
    Write-Host "Outputs in: $GodotSrcDir\bin\"
    exit 0
}

foreach ($cacheDir in $GodotTemplateCaches) {
    New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
    if ($BuildDebug) {
        $src = Join-Path $GodotSrcDir "bin\godot.web.template_debug.wasm32.dlink.zip"
        $dst = Join-Path $cacheDir "web_dlink_debug.zip"
        if (-not (Test-Path $src)) {
            Write-Error "Expected output missing: $src"
        }
        Copy-Item -Force $src $dst
        Write-Host "Installed: $dst" -ForegroundColor Green
    }
    if ($BuildRelease) {
        $src = Join-Path $GodotSrcDir "bin\godot.web.template_release.wasm32.dlink.zip"
        $dst = Join-Path $cacheDir "web_dlink_release.zip"
        if (-not (Test-Path $src)) {
            Write-Error "Expected output missing: $src"
        }
        Copy-Item -Force $src $dst
        Write-Host "Installed: $dst" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Cyan
Write-Host "Next: open the project in Godot 4.6, Project > Export, select"
Write-Host "`"Web`", and click Export Project -> build/web/index.html."
Write-Host "Then run the project web server: npm install && node web/server.js"
