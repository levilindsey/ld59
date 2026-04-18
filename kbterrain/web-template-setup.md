# Web export template setup

Godot's official web export templates ship **without** GDExtension
support. To export Kittenbaticorn for web (with our C++ extension), build a
custom `dlink_enabled=yes threads=yes` template from the Godot
engine source.

This is a one-time setup per dev machine.

## Prerequisites

- Godot 4.6-stable source checkout
  (`git clone -b 4.6-stable https://github.com/godotengine/godot.git`).
- Python 3.8+ and SCons 4.0+.
- **Emscripten SDK 4.0.11**. Avoid 4.0.3 through 4.0.6 — they
  contain a GDExtension regression (Godot issue #105717).

```bash
# Install emsdk and pin to the tested version.
cd <emsdk checkout>
./emsdk install 4.0.11
./emsdk activate 4.0.11
source ./emsdk_env.sh   # or emsdk_env.ps1 on Windows
```

Verify: `emcc --version` should report `4.0.11`.

## Build

Inside the Godot 4.6-stable source directory:

```bash
scons platform=web dlink_enabled=yes target=template_release
scons platform=web dlink_enabled=yes target=template_debug
```

Outputs, in `bin/`:

- `godot.web.template_release.wasm32.dlink.zip`
- `godot.web.template_debug.wasm32.dlink.zip`

## Install

Rename each zip to the name Godot's export preset expects:

- `godot.web.template_release.wasm32.dlink.zip` → `web_dlink_release.zip`
- `godot.web.template_debug.wasm32.dlink.zip` → `web_dlink_debug.zip`

Copy into Godot's template cache:

- **Windows**: `%APPDATA%\Godot\export_templates\4.6.stable\`
- **Linux**:   `~/.local/share/godot/export_templates/4.6.stable/`
- **macOS**:   `~/Library/Application Support/Godot/export_templates/4.6.stable/`

Godot → Editor → Manage Export Templates → "Install From File" also
works per-zip but requires correct naming first.

## Godot export preset

For Kittenbaticorn's web export:

- **Extension Support**: ON (required for GDExtension).
- **Thread Support**: ON (required for `std::thread` in the
  extension's terrain worker).
- **PWA**: ON (optional but helps repeat-visit load time).

## Serving the build

Our C++ extension uses `std::thread`, which on wasm requires
`SharedArrayBuffer`, which requires these response headers:

```
Cross-Origin-Opener-Policy:   same-origin
Cross-Origin-Embedder-Policy: require-corp
```

The repo contains a tiny node static server that sets them. See
`web/server.js`.

## Failure modes

| Symptom | Cause |
|---|---|
| Export dialog: "Template file not found: web_dlink_release.zip" | Custom template not installed or misnamed. Re-run install steps. |
| Browser console: "GDExtension libraries are not supported by this engine version" | Export used the non-dlink template. Turn on "Extension Support" and re-export. |
| Cryptic wasm link errors at build time | Wrong Emscripten version. Check `emcc --version`; reinstall 4.0.11. |
| Runtime page fails with "SharedArrayBuffer is not defined" | Server didn't send COOP/COEP. Verify via devtools network tab. |
| Safari refuses to load | Expected. Safari has no `credentialless` support yet. Serve the fallback HTML from `web/safari_fallback.html`. |

## Single-threaded fallback (optional)

If we ever need to target Safari, build an additional
single-threaded variant:

```bash
scons platform=web dlink_enabled=yes threads=no target=template_release
```

Output: `godot.web.template_release.wasm32.nothreads.dlink.zip` →
rename to `web_dlink_nothreads_release.zip`. Export with "Thread
Support" OFF. The C++ extension must also be built with
`threads=no` and our code must detect `!crossOriginIsolated` to
fall back to synchronous main-thread meshing.
