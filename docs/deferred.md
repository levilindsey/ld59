# Deferred Items, Open Decisions, Known Limitations

A living index of work that's been **discussed but not finished** during
the recent extended sessions. Pull from here when picking the next
parallel-track task. New items go here, not in `PLAN.md` (which is the
authoritative phase checklist for *intended-and-actively-tracked* work).

---

## 1. Deferred Features

### 1.1 Per-hit return pings — visual + audio
**Status**: designed, not implemented.
**Description**: At pulse emit time, raycast N rays (~24) from the player
in the configured arc; for each hit point compute `delay = 2 * dist /
pulse_speed`. At the scheduled time, fire a small bright dot + faint
outward ringlet at the hit point (color = pulse frequency) AND a short
audio "ping" panned by hit-angle, attenuated by distance.
**Design decisions made**: Visual rendering goes through a shader
uniform array (`pings[MAX_PINGS]`, ~32 slots, packed `vec4(x, y,
age_sec, freq_id)`), not spawned scene nodes; integrates with the
existing pulse/tagged-sprites uniform pattern. Audio uses a pooled
`AudioStreamPlayer` with `pitch_scale` + `pan` set per-ping.
**Why deferred**: Substantial new system (raycast scheduler + shader
uniforms + audio plumbing) — kept slipping under more-urgent fixes.

### 1.2 Damage-tier visualization shader
**Status**: design recommendation made; **starting implementation now**.
**Decision**: discrete 4–5-tier crack atlas (pristine / scratched /
cracked / chipped / about-to-shatter), alpha-blended between adjacent
tiers based on cell health; NOT continuous procedural noise (clashes
with pixel-art aesthetic).
**Open**: per-frequency tinting (tint cracks by tile palette color so
green-tile cracks read as dark green) — likely yes, single-line shader
add. Whether to expose the crack overlay strength as a tunable.

### 1.3 Wall / ceiling crawling for `Spider` enemy
**Status**: floor-crawling raycast variant exists; vertical surface
locomotion not implemented.
**Plan**: reuse the scaffolder's existing surface raycast infrastructure;
add wall and ceiling state machines.

### 1.4 Cone vs full-circle pulse default
**Status**: cone code path wired (`echo_arc_radians`,
`arc_direction_radians`, shader `pulse_cones[]`), never playtested.
**Open decision**: ship circle-by-default, or expose a toggle. Punt
until Phase 5 playtest.

### 1.5 Final game-over flow / restart UX
**Status**: instant scene reload on death is the placeholder.
**Plan**: proper game-over screen with retry / quit, hooked off
`PlayerHealth.died`.

### 1.6 Web build + jam-submission deploy
**Status**: build toolchain fully shipped. Custom dlink+threads web
export template built and installed in both `4.6.stable/` and
`4.6.2.stable/` Godot template caches; kbterrain extension built
for wasm32 (`libkbterrain.web.template_{debug,release}.wasm32.wasm`);
project exported to `build/web/`; deploy zip at
`build/kittenbaticorn-web.zip` (~22 MB). Local smoke test works at
`http://localhost:8080` via `web/server.js` (COOP/COEP headers
confirmed). **Not yet deployed to a real host.**
**Remaining**: upload the zip to itch.io (check "SharedArrayBuffer
support") OR push `build/web/` to Cloudflare Pages / Netlify (both
pick up the `_headers` file already copied into the export root) OR
rsync to a self-hosted box behind HTTPS.
**Constraints**: Emscripten pinned to 4.0.11 (skip 4.0.3–4.0.6 due
to GDExtension regression). HTTPS required for SharedArrayBuffer in
production.

### 1.7 Coyote enemy — placeholder art
`src/enemies/coyote.tscn` uses white-pixel rectangles for
body/head/tail/legs. Behavior (ground-chase, wall-bounce jump,
vertical-jump-at-player, gravity + ground raycast) works. Needs a
real spritesheet + animation states (idle / run / jump / fall)
matching the kittenbaticorn art style.

### 1.8 Spider web tile — placeholder art
`src/level/web_tile.tscn` uses a semi-transparent 16×16 square + two
45° white-line "strands". Needs real web art; consider
frequency-tinted variations and a "tattered" sprite when
`_health` drops below a threshold.

### 1.9 Player wall / ceiling animations missing
`character.gd._process_animation` calls `animator.play("climb_up")`,
`play("climb_down")`, `play("rest_on_wall")`, `play("crawl_on_ceiling")`
when the player enters wall/ceiling states. None of those animations
exist in `player_animator.tscn`. AnimatedSprite2D emits warnings and
the sprite freezes on its last frame if those states are ever
reached. Either author frames or extend
`PlayerAnimator._ANIMATION_NAME_MAPPING` to route them onto existing
animations (e.g. wall → `jump_rise`, ceiling-crawl → `walk`).

### 1.10 Fragment detach particle burst
PLAN.md Phase 4 listed this as polish. CC detach path ships without
it. When an un-anchored island becomes a `TerrainChunkFragment`, a
one-shot dust/particle effect at the detach seam would make it read
as "sheared off" rather than "materialized."

### 1.11 Enemy spawn point wiring for Coyote
`Coyote.tscn` is implemented but no level scene currently references
it via an `EnemySpawnPoint.enemy_scene` export. First level that
wants coyotes needs to drag the scene onto a spawn point (single-shot
or respawning). Same gap applies if additional web-tile clusters are
authored before the TileMap custom-data route is fully playtested.

---

## 2. Pending Design Decisions

### 2.1 Tile custom data layers (`type`, `initial_health`) — **DONE**
Schema authored on `default_tile_set.tres`; loader reads per-tile
`type` + `initial_health`; WEB_* tiles route to Area2D spawns.
Health falls back to 255 when `initial_health` is unset (0 treated
as unset, since Godot returns default 0 for never-written int
custom data).
**Open follow-through**:
- Not every atlas tile has `custom_data_0` assigned — untagged
  tiles silently fall back to `default_terrain_type`. Do a full
  TileSet audit before an authored level ships.
- `custom_data_1` (health) is currently unset on every atlas tile,
  so everything is 255 HP. Decide per-type values (web low, sand
  medium, indestructible n/a) before bulk-authoring.

### 2.2 Bug spawn-region stacking semantics
**Status**: implementation is additive with min-rate-floor safety;
not formally specified or fully playtested.
**Open**: do we want regions to multiply rather than add? do negative
deltas suppress positives? — need playtest data.

### 2.3 Frequency-tag SubViewport architecture
**Status**: implemented in Phase 1 form. Currently uses a Godot 4.6.2
+ AMD-driver workaround (`canvas_cull_mask = 3` rather than the
intended `2`) because pure-bit-1 cull doesn't filter as the math says
it should — the tag viewport ends up containing parallax + player too,
and the shader's tight (0.02) palette-match threshold is what cleanly
separates terrain pixels from sprite pixels at sample time.
**Open**: report Godot bug upstream, or revisit when 4.6.3+ ships, or
adopt the SDF-from-density-texture approach (Section 4.1) which makes
the tag viewport unnecessary.

### 2.4 Player sprite vs collision relative offset
**Status**: collision is sized 23×6 (rotated → 6×23), 2 px taller
than the 14×21 sprite. This hides the bottom-row pixel overlap with
terrain top. Author may want to revisit if visible character ever
needs to sit lower or higher within the body.

### 2.5 Damage CC island detach
**Status**: **re-enabled.** The fallback arena now bakes an
INDESTRUCTIBLE border via `bake_rect_with_border` (default 2 cells
thick), and authored levels can paint anchor cells via the TileSet
custom data. `damage_with_falloff` now calls
`_detach_islands_from_seeds` as normal.
**Remaining risk**: if a future level ships with NO anchor cells
(an island floating in space), the whole thing will detach on first
pulse. Belt-and-suspenders option: cap the flood size check to some
fraction of the level bounds, but that adds complexity. Punt unless
an author trips it.

### 2.6 WEB frequency type consistency across layers
`terrain_level.gd` references `Frequency.Type.WEB` and the TileSet
has `custom_data_0` values extending past `YELLOW = 7` (8, 10, 11
observed). **Verify**:
- `Frequency.Type` enum defines WEB (and any other new values) at
  the expected integer positions.
- `TerrainSettings::Type` (C++) mirrors the same values exactly
  (`terrain_settings.h` comment says "must match
  `src/core/frequency.gd`"; silent divergence would mean web tiles
  take damage on the wrong frequency or never take damage).
- `_frequency_to_bit` in `terrain_world.cpp` handles the new
  values (it short-circuits on `freq > 30` but hasn't been audited
  for the specific new ones).
- The composite shader's palette and per-tile atlas slots include
  WEB (otherwise web tiles render with a missing/default color).

### 2.7 Per-tile `initial_health` values in the TileSet
`custom_data_1` schema exists but every atlas tile currently leaves
it unset, so the loader falls back to 255 for everything. Once the
damage-tier shader (1.2) lands, per-tile durability differences
start mattering — pick values (e.g. web 64, sand 128, RGB/Y 255,
indestructible n/a since the damage path early-outs on that type).

---

## 3. Accepted Limitations / Trade-offs

### 3.1 godot-cpp pinned at 4.5-stable
godot-cpp has no 4.6-stable tag yet (April 2026). Extension built
against 4.5-cpp loads cleanly in Godot 4.6.2 via
`compatibility_minimum = "4.6"`. Bump pin when upstream ships.

### 3.2 Hot-reload friction
GDExtension DLLs are file-locked while the editor runs. Workflow:
prototype hot logic in GDScript, port stable shapes to C++.

### 3.3 SubViewport rendering on web
Godot issue #86258: SubViewports can render black on WebGL2 unless
`render_target_update_mode = ALWAYS`. Already set on the tag viewport.

### 3.4 Defensive null-checks added to scaffolder character code
Three patches were added during this session because Godot's
`is_on_floor()` / `is_on_wall()` / `is_on_ceiling()` predicates can
flip true on contacts whose normals our `Collision` class classified
differently:
- `_reuse_previous_surface_contact_if_missing` — soft-fails instead of
  `G.ensure`'ing.
- `_update_attachment_contact` — early-returns instead of
  `G.ensure`'ing then dereferencing.
- `air_default_action.gd:53` — null-guards `ceiling_contact.normal.x`.

The **root fix** (passing `character.floor_max_angle` +
`character.up_direction` into `Collision._init` so per-collision side
classification matches Godot's predicates) **was applied**, so the
defensive patches are belt-and-suspenders and shouldn't trigger in
practice. They can stay as cheap safety nets.

### 3.5 Bug halo radius hand-tuned to Glow sprite
`_BUG_TAG_RADIUS_PX = 6` (world px) matches the bug `Glow` sprite's
half-extent. If Glow art changes scale, halo radius needs to update.

### 3.6 Player collision must touch terrain (physics constraint)
Several attempts to make the collision shape *visually* float above
terrain failed because `CharacterBody2D` can't rest with a gap.
Mitigation: collision is 1 px taller than the sprite on each side,
so the *visible* sprite never reaches a contact surface; the
collision rectangle still sits tangent to terrain.

### 3.7 Iso-line snap (iso = 255)
With binary 0/255 corner densities from the bake, iso=255 snaps
the boundary to the inside-corner positions — visual + collision
align with authored tile bounds (no half-cell extension). Trade-off:
once we want true continuous smooth surfaces (sand piles, liquid
splats), iso may need to be a per-context value or partial-density
splat needs to use a different threshold.

### 3.8 Web export template install is Godot-version-brittle
`kbterrain/build_web_template.ps1` copies the built zips into BOTH
`%APPDATA%/Godot/export_templates/4.6.stable/` and
`.../4.6.2.stable/`. Godot looks up the cache path by the full
`X.Y.Z.stable` version string it reports, so a point upgrade
(e.g. 4.6.3) will again fail with "Template file not found" until
the list is extended and re-run. Either re-run the build script
with the new version added to `$GodotTemplateCaches`, or symlink
the existing zips into the new path.

### 3.9 Web bundle size dominated by Godot engine
Final zip is ~22 MB. `index.side.wasm` alone is ~40 MB uncompressed
(~13 MB in-zip), and that's Godot's threaded web runtime — not
something we can trim without a custom single-threaded template
(`threads=no`) + a `threads=no` extension + runtime
synchronous-meshing fallback. Out of scope for the jam; revisit if
target bandwidth becomes a constraint.

### 3.10 Flow CA "binary cell" simplification
`flow_step` moves whole cells (type flips, density corners
recomputed from neighborhood) rather than analog mass transfer.
Inside actively-flowing regions, carved (partial-density) corners
are squared off on the fly — visible as a cleanup pass on sand
slopes. Fine for the jam aesthetic; if we want smooth sand piles
or compressible liquid later, flow has to go analog (w-shadow mass
transfer) and density corners become source of truth, not type.

---

## 4. Architectural Follow-Ups

### 4.1 Density-field SDF in shader (replace tag viewport)
**Status**: written up in `docs/notes.md` deferred-shader-work list.
**Description**: Once the marching-squares density field is exposed to
the shader as an actual texture (R8 per cell, sampled bilinearly),
several things become cleaner:
- Eliminate the tag SubViewport entirely (per-pixel type via density
  texture sampling instead).
- True signed-distance to surface for bandwidth (replace luminance-
  gradient hack).
- Sub-pixel surface band rendering.
**Blocked on**: nothing — the data already exists in C++; just needs
exposing as a texture uniform updated per-chunk-modification.

### 4.2 Refactor StateMain transitions
**Status**: state flow has multiple defensive guards (the
`if is_instance_valid(level): return` in `GamePanel.start_level` is
load-bearing) that mask a fragile call graph.
**Plan**: split lifecycle (scene load/unload), UI state (title /
game / pause / over), and gameplay state (alive / dying / dead) into
separate state machines.
**When**: post-jam.

### 4.3 Per-chunk damage texture pipeline (for damage shader, item 1.2)
**Decision needed before implementing 1.2**: how does the shader read
per-cell health?
- **Option A**: bake `health/255` into mesh vertex color alpha. Cheap
  (no extra textures), but vertices sit at iso line crossings, so
  health-per-vertex ≠ health-per-cell in transition cells.
- **Option B**: separate per-chunk R8 texture (32×32) updated on
  every cell health change; sampled in the chunk's canvas_item shader.
  Strictly correct, more plumbing.
- **Option C** (recommended path): vertex color alpha, with each cell's
  TRIANGLES all using the same per-cell alpha (no Gouraud blend
  inside a cell — they all share one cell's health). Simpler than B,
  more correct than naive A.

---

## 5. Workarounds to Revisit

### 5.1 Damage CC detach — resolved
See 2.5. Re-enabled after the fallback arena learned to bake an
INDESTRUCTIBLE border (and the TileSet custom-data path let
authored levels paint anchors). Keep this entry as a breadcrumb so
if the "single unanchored island" bug resurfaces on a new level
shape, the fix direction is obvious.

### 5.2 Editor-mode synchronous mesh path
`TerrainWorld._editor_mode` runs marching squares synchronously in
`_queue_remesh`. Necessary for `@tool` preview — keep.

### 5.3 Test coverage gaps
Many GUT integration tests listed in `PLAN.md` are stubs. Ship-
defer until post-jam. Phase 4 specifically missing:
`test_flow_step.h`, `test_connected_components.h`,
`test_terrain_fragment_mesh.h` (C++); `test_fragment_falls_and_rests.gd`,
`test_sand_piles.gd` (GUT).

### 5.4 `godot --headless --export-release` flaky exit code
Godot sometimes exits with non-zero or null `$LASTEXITCODE` after a
successful export (internal ObjectDB-leak warning bumps status).
`scripts/export_web.ps1` treats the presence of the output
`index.html` as the source of truth rather than the exit code. Watch
this if a future Godot release fixes shutdown — the extra tolerance
would mask a real failure.

### 5.5 PowerShell arg interpolation with scons
`-j$jobs` caused scons to see the literal string `$jobs`. The fix
is `"-j$jobs"` (quoted). Same pattern will recur if we add more
parametric scons invocations; in general, when passing PowerShell
variables through to external tools, quote the composite argument.

### 5.6 `emsdk_env.ps1` doesn't propagate env to the caller
`emsdk_env.ps1` → `emsdk.ps1 construct_env` runs in a subprocess
whose env changes die with it; the parent shell's `$env:PATH` is
never updated. `build_web_template.ps1` manually prepends
`$EmsdkDir`, `$EmsdkDir\upstream\emscripten`, and the node/python
tool dirs to `$env:PATH`. Keep the manual prepend in any future
script that needs `emcc` on PATH.

---

## 6. Infrastructure Notes

### 6.1 Tag viewport `canvas_cull_mask` quirk
Use `cull_mask = 3` not `2`. Documented in `main.gd` with code
comment.

### 6.2 Camera2D anchor mode
Godot 4.5+ defaulted `Camera2D.anchor_mode` to FIXED_TOP_LEFT. Our
code explicitly sets `DRAG_CENTER`; any new level scene must do the
same or camera follow breaks.

### 6.3 Build product timestamp asymmetry
`build_windows.ps1` sometimes only links the release DLL and skips
debug as "up to date" even when source changed. Workaround: run
`scons platform=windows target=template_debug -c && scons
platform=windows target=template_debug install` to force.

### 6.4 Web export preset `extensions_support` + `thread_support`
Both MUST be `true` in `export_presets.cfg`'s `[preset.0.options]`
for the custom dlink+threads template to actually get used. If they
regress to `false`, Godot silently falls back to the stock web
template, which either refuses the GDExtension or runs without
threads (our C++ terrain worker deadlocks on `std::thread`). Already
set correctly; watch for accidental regressions on future edits via
the Godot export UI.

### 6.5 `default_bus_layout` path (not UID) in project.godot
`buses/default_bus_layout` references `res://default_bus_layout.tres`
directly rather than `uid://…`. UID-based project-level resource
references emitted `Unrecognized UID` warnings during
`godot --headless --export-release`. Stick with `res://` paths for
resources referenced from `project.godot` to avoid the UID cache
miss during headless export.

### 6.6 Web export filter
`export_presets.cfg`'s Web preset has
`exclude_filter="web/*, kbterrain/*, scripts/*, docs/*, test/*,
build/*, addons/gut/*, *.md, *.ps1"`. Dropped ~2.6 MB (17%) from
the pck compared to the unfiltered baseline by excluding the npm
deps, GUT framework, and other host-side artifacts. If new top-level
directories appear that contain non-shippable assets (source,
scripts, test data), extend the filter.

---

*Last updated: April 18, 2026 (desktop session). Generated from
session-history audit plus current-session knowledge. Includes
web-deploy toolchain build-out, Phase 4 CC detach re-enable after
anchor authoring landed, Phase 3 TileSet custom-data shipping, and
bundle-size filter work.*
