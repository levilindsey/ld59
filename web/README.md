# Web deployment

One-time setup + per-change deploy for the Kittenbaticorn web build.

## Prereqs (one time per machine)

1. Godot 4.6.x on PATH (`godot --version`).
2. Custom web template installed:
   ```powershell
   powershell -ExecutionPolicy Bypass -File kbterrain/build_web_template.ps1
   ```
   See `kbterrain/web-template-setup.md` for details.
3. Node + npm. Then from this folder:
   ```powershell
   npm install
   ```

## Export

From the repo root:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/export_web.ps1
```

Output:
- `build/web/index.html` (+ the rest of the web build)
- `build/kittenbaticorn-web.zip` (deploy artifact)

Pass `-Debug` for the debug template, `-NoZip` to skip zipping.

## Local smoke test

```powershell
node web/server.js
# Opens on http://localhost:8080
```

The server sends `Cross-Origin-Opener-Policy: same-origin` and
`Cross-Origin-Embedder-Policy: require-corp`, which SharedArrayBuffer
(and therefore the C++ extension's threaded terrain worker) requires.

## Deploy

Any of these work; pick one.

### itch.io

Upload `build/kittenbaticorn-web.zip`, set it as an HTML project, and
check **SharedArrayBuffer support** in the project settings. itch.io
auto-serves COOP/COEP headers for checked projects.

### Cloudflare Pages / Netlify

Upload `build/web/` as the site root. The `_headers` file in that
directory (copied automatically by `scripts/export_web.ps1`) sets
COOP/COEP for both hosts.

### Self-host

Deploy `build/web/` behind `web/server.js` on a node-capable box.
Serve over HTTPS — SharedArrayBuffer requires a secure context.

## Gotchas

| Symptom | Fix |
|---|---|
| "Template file not found: web_dlink_release.zip" on export | Run `build_web_template.ps1` and make sure Godot's export-template cache has `4.6.stable/web_dlink_release.zip`. |
| Browser console: "GDExtension libraries are not supported" | `export_presets.cfg` → `variant/extensions_support` must be `true`. Already set in this repo; re-check if regressed. |
| "SharedArrayBuffer is not defined" in console | Headers missing. Confirm the host is actually sending COOP/COEP (devtools → Network → response headers). |
| Safari refuses to load | Expected — no fallback support yet. Serve `web/safari_fallback.html`. |
