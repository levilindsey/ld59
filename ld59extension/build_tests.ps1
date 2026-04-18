# Build and run C++ unit tests for the ld59extension GDExtension.
#
# Rebuilds the extension with tests=yes (embedding GoogleTest and all
# test_*.h test cases), installs it into addons/ld59extension/bin/,
# then launches Godot headless on the project. On module init, the
# extension runs RUN_ALL_TESTS() and prints a sentinel line. This
# script greps for that sentinel to determine pass/fail.

$ErrorActionPreference = "Stop"

function Write-Success { param($msg) Write-Host $msg -ForegroundColor Green }
function Write-Info    { param($msg) Write-Host $msg -ForegroundColor Cyan }
function Write-Err     { param($msg) Write-Host $msg -ForegroundColor Red }

Set-Location $PSScriptRoot

Write-Info "=== Building ld59extension with tests=yes (template_debug) ==="
scons platform=windows target=template_debug tests=yes
if ($LASTEXITCODE -ne 0) { Write-Err "Test build failed."; exit 1 }
scons platform=windows target=template_debug tests=yes install

$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

Write-Info ""
Write-Info "=== Running Godot headless to trigger tests ==="
if (-not (Get-Command godot -ErrorAction SilentlyContinue)) {
	Write-Err "godot not found on PATH."
	exit 1
}

# --quit (vs --quit-after) exits immediately after startup. The
# extension's module init fires during startup, so tests still run.
#
# Godot emits game-level stderr errors during its brief run (e.g.
# missing main-scene nodes), which PowerShell's default
# ErrorActionPreference=Stop turns into a terminating error. Drop to
# Continue around the invocation and redirect output to a file
# instead of piping, so we capture Godot's stdout (where the test
# sentinel lives) without PowerShell short-circuiting.
$LogPath = Join-Path $env:TEMP "ld59extension_tests.log"
if (Test-Path $LogPath) { Remove-Item $LogPath }

$prevEap = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
	& godot --headless --path "$ProjectRoot" --quit *>&1 |
		Tee-Object -FilePath $LogPath | Out-Null
} finally {
	$ErrorActionPreference = $prevEap
}

$output = if (Test-Path $LogPath) { Get-Content $LogPath -Raw } else { "" }
Write-Host $output

if ($output -match "ld59extension test result: ALL TESTS PASSED!") {
	Write-Success "=== ld59extension tests: PASSED ==="
	exit 0
} elseif ($output -match "ld59extension test result: SOME TESTS FAILED!") {
	Write-Err "=== ld59extension tests: FAILED ==="
	exit 1
} else {
	Write-Err "=== ld59extension tests: DID NOT RUN (sentinel not found) ==="
	exit 1
}
