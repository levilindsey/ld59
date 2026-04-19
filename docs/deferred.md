# Deferred Items, Open Decisions, Known Limitations

A living index of work that's been **discussed but not finished** during
the recent extended sessions. Pull from here when picking the next
parallel-track task. New items go here, not in `PLAN.md` (which is the
authoritative phase checklist for *intended-and-actively-tracked* work).

---

## 1. Deferred Features

### 1.1 Per-hit return pings — visual + audio — **DONE**
Raycast scheduler shipped in `echolocation_renderer._schedule_pings_for_pulse`
(24 rays / pulse via GDScript DDA against `G.terrain.is_cell_non_empty`).
Visuals packed into `pings[MAX_PINGS]` uniform (32 slots) — bright dot +
expanding ringlet per fired ping. Audio: `EchoAudioPlayer` connects to
`G.echo.ping_fired`; per-ping plays through an `AudioStreamPlayer2D`
positioned at the hit's world position, so Godot's 2D audio engine
auto-pans stereo based on hit direction relative to the Camera2D.
Built-in inverse-distance attenuation is disabled (`attenuation = 0`)
so the manual `volume_db` curve is the single source of distance-
volume truth. Pool bumped to 8.
**Deferred (future polish)**: promote the GDScript DDA to a C++ bulk
`raycast_arc()` if profiling flags it (not needed at 3 pulses/sec,
24 rays).

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
PLAN.md Phase 4 listed this as polish. The FallingCell-based detach
path ships without it. When an un-anchored island detaches, a
one-shot dust/particle effect at the detach seam would make it read
as "sheared off" rather than "dissolved into tiles."

### 1.11 Enemy spawn point wiring for Coyote
`Coyote.tscn` is implemented but no level scene currently references
it via an `EnemySpawnPoint.enemy_scene` export. First level that
wants coyotes needs to drag the scene onto a spawn point (single-shot
or respawning). Same gap applies if additional web-tile clusters are
authored before the TileMap custom-data route is fully playtested.

### 1.12 FallingCell landing at spawn position "restores" the chunk
If a detached chunk's bottom row is resting against non-INDESTRUCTIBLE
terrain (e.g., colored neighbor cells that happen to also be part of
the main world but aren't anchor-typed), each FallingCell's landing
probe finds the cell directly below as collidable on frame 1 and
paints back at its *original* position. Net: the chunk looks like it
didn't collapse. **Only triggers** when the chunk-to-main-world
contact is via a solid (not air/liquid) shared edge.
**Mitigations considered**:
- Require FallingCell to move a minimum distance before painting
  (say, 2 px). Clean but discards "chunk just shifts slightly" cases.
- Skip the paint if landing_cy equals spawn_cy.
**Why deferred**: rare in authored levels (most detachable chunks
hang in air); noisy to fix correctly. Covered by the new CC
diagnostic prints (item 5.7) so authors can spot it via logs.

### 1.13 CC detach diagnostic prints still live
`connected_components.cpp` currently `UtilityFunctions::print`s on
every BFS — `[CC] detaching island at seed ...` and
`[CC] skipping detach at seed ... anchored=... over_budget=...`.
Useful while debugging the "chunk didn't collapse" report but spammy
at scale. Gate behind a `#ifdef KBTERRAIN_CC_DEBUG` (or similar
runtime flag) before ship.

### 1.14 FallingCell `_actor_column_has_collidable` helper is unused
Leftover from a prior eviction rewrite. Now that eviction uses exact
AABB overlap + push-out, the helper doesn't have a caller. Safe to
delete; parked instead of cleaning immediately in case another
eviction path needs it.

### 1.15 Falling-cell merge-back when player overlaps: preserve velocity?
`_try_evict_actor` currently zeros `velocity.y` after pushing the
actor out. Good for fall-through avoidance, but in cases where sand
pushes the player *sideways* (e.g., a pile collapses against them)
the horizontal part of velocity is untouched. Revisit if side-hit
collisions feel wrong.

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

### 2.3 Frequency-tag SubViewport architecture — **REMOVED**
Replaced by the density/type texture approach in §4.1 (now shipped).
TagViewport + TagCamera2D nodes deleted from `main.tscn`; palette-match
/ `detect_frequency` / `palette_match_threshold` gone from the shader.
The AMD `canvas_cull_mask = 3` quirk is no longer load-bearing on any
code path.

### 2.4 Player sprite vs collision relative offset
**Status**: collision is sized 23×6 (rotated → 6×23), 2 px taller
than the 14×21 sprite. This hides the bottom-row pixel overlap with
terrain top. Author may want to revisit if visible character ever
needs to sit lower or higher within the body.

### 2.5 Damage CC island detach — re-enabled + tuned
**Status**: re-enabled. The fallback arena now bakes an
INDESTRUCTIBLE border via `bake_rect_with_border` (default 2 cells
thick), and authored levels can paint anchor cells via the TileSet
custom data. `damage_with_falloff` calls
`_detach_islands_from_seeds` as normal.
**Budget**: `MAX_DETACH_FLOOD` bumped from 5000 to 50000 to let
legitimately-large chunks fully explore before the "assume main
world" safety fires. Diagnostic prints installed (see 1.13).
**Remaining risk**: CC only treats `INDESTRUCTIBLE` as an anchor.
Any colored path back to the main world counts as "still attached,"
even if the player's mental model is that they severed the chunk.
When authoring, make sure every solid path back to an anchor is
cleanly cuttable by the player's frequency, or expect the chunk to
stay put.

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

### 2.8 Flow-sim rule tuning — "drop-aware teleport" constants
The top-layer lateral spread uses `_LATERAL_REACH = 32` and
`_MAX_DROP = 64`. These control how far water "sees" when looking
for a drain. Works well for jam-scale levels; revisit if pool
widths exceed 32 cells (top-layer won't find drains across pool)
or if pit depths exceed 64 cells (won't teleport all the way down).

### 2.9 Wedge-kick tuning on jump
`_WEDGE_KICK_PX_PER_SEC = 220` horizontal, `_WEDGE_POP_UP_PX_PER_SEC
= 240` vertical. Values picked without playtesting multiple gap
sizes — could feel too weak in a narrow 1-cell V, too strong in a
wider diagonal gap. Tune against real stuck cases.

### 2.10 Continuous `_unstick_from_terrain` threshold
Fires only when a collidable cell is *fully embedded* in the player's
vertical extent (cell top & bottom both strictly inside the player's
AABB). Normal floor resting — penetration ~1-3 px — never triggers.
Tight tradeoff: a sand cell landing and overlapping the player by
5-7 px won't register as stuck and depends on FallingCell's one-shot
eviction to push the player out. If that path ever misses, the
continuous check won't rescue. Watch for "half-stuck" visuals where
the player is partially inside a cell for a frame.

---

## 3. Accepted Limitations / Trade-offs

### 3.1 godot-cpp pinned at 4.5-stable
godot-cpp has no 4.6-stable tag yet (April 2026). Extension built
against 4.5-cpp loads cleanly in Godot 4.6.2 via
`compatibility_minimum = "4.6"`. Bump pin when upstream ships.

### 3.2 Hot-reload friction
GDExtension DLLs are file-locked while the editor runs. Workflow:
prototype hot logic in GDScript, port stable shapes to C++.

### 3.3 SubViewport rendering on web — **NO LONGER APPLICABLE**
The tag SubViewport was removed (see §2.3 / §4.1). Godot issue #86258
no longer affects this project. Leaving the note as a breadcrumb in
case any future code paths add a SubViewport.

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

### 3.11 Lateral water oscillation on flat pool surface
Top-layer liquid cells with empty lateral neighbors alternate
directions every step (prefer_right flips by parity). On a truly
flat pool with an extra cell on top, this manifests as the top cell
shimmying back and forth by 1 px at 30 Hz. Accepted: the
alternative rules that killed the shimmer (vel_x commit, column-
depth rule) introduced *worse* behavior (mound trapping, blocked
spread). The drop-aware lateral teleport handles the real-problem
case — tall mounds — and leaves the cosmetic shimmy. Looks like
"water shimmering" at the rim rather than actual jitter.

### 3.12 Fragment chunks now per-cell FallingCells, not RigidBody2D
PLAN.md Phase 4 described `TerrainChunkFragment` as a rigid body
that spins and tumbles. We bailed on that path because Godot's 2D
rigid-body physics was unstable for small detached groups (wedging,
tunneling, velocity explosions). Replaced with `FallingCell.gd`:
each cell falls straight down under scalar gravity, stagger-
delayed by row (bottom falls first), lands on the first collidable
below it, and paints back into the terrain. No rotation, no rigid
body. Visually less dynamic but orders of magnitude more
predictable. `terrain_chunk_fragment.{gd,tscn}` files remain in the
repo unused; delete when a cleanup pass happens.

### 3.13 Water cells are non-collidable in physics
`TerrainWorld` runs marching squares **twice per chunk** — once on
the real density field for rendering (so water renders normally),
then again on a collision-only density field where LIQUID cells'
corners are zeroed (so no collision segments are emitted along
water-air or water-solid interfaces). The collision-density build
runs on the main thread with cross-chunk `ChunkManager` access so
shared boundary corners stay consistent with neighbor chunks. Pool
surfaces are non-colliding — the player swims through — while the
pool's solid walls/floor stay collidable.

### 3.14 Synchronous collision shape update on main thread
`_queue_remesh` runs `mesh_chunk` on the collision-density snapshot
and calls `shape_set_data` **synchronously** before handing the job
to the worker. The worker's async remesh still handles the render
mesh; its collision output (when it eventually integrates) overwrites
with the same data. Reason: without the sync step, a big detach
left stale collision shapes active for several frames while the
worker queue cleared, and the player collided with "phantom" chunks
at old positions. The duplicated work is cheap (microseconds per
chunk).

### 3.15 Neighbor-chunk remesh cascade scoped to rare events
`_queue_remesh_and_neighbors` (which also re-queues the 4 axial
neighbor chunks) is called for bake / damage / paint / CC detach.
Flow-step uses plain `_queue_remesh` (no cascade) because flow
mutates hundreds of cells per tick and the 5× cascade overwhelmed
the worker queue, making flow appear to "freeze" visually. Trade-
off: water moving across a chunk seam briefly has stale collision on
the neighbor chunk until something else triggers its remesh. Barely
observable in practice.

### 3.16 Player wedge-kick is input-gated, not continuous
`_apply_wedge_kick_if_stuck` fires only on jump-press, not every
frame. If the player gets wedged without pressing jump (e.g., falling
into a 1-cell V), they're stuck until they press jump. Deliberate —
continuous nudging would fight normal contact-with-wall behavior
(sliding along a vertical wall, for instance).

---

## 4. Architectural Follow-Ups

### 4.1 Density-field SDF in shader (replace tag viewport) — **DONE**
C++ `TerrainWorld::build_density_image()` + `build_type_image()` produce
world-spanning R8 images from `density` / `type_per_cell`; renderer
wraps them in `ImageTexture`s, re-uploads on `chunk_modified` via
`ImageTexture.update()`. Shader samples `density_tex` with a 2-tap
central difference for the surface gradient (replaces the 12-tap
multi-scale luminance Sobel) and `type_tex` directly for per-pixel
type (replaces the palette-match path). Tag SubViewport removed.
**Deferred follow-ups**: incremental per-chunk blit if a profiling pass
flags full-rebuild cost; sub-pixel surface-band rendering (the density
field enables it, but the current rendering doesn't exploit it yet).

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

### 4.4 Flow sim — ballistic lateral teleport
Top-layer liquid cells scan out to `_LATERAL_REACH = 32` cells each
direction, look for the furthest supported empty cell whose downward
scan finds a non-empty settle floor, and teleport directly to that
settle position (drop > 0 only). Runs as a second pass after the
main bottom-up flow scan. Effect: water drains tall mounds in one
or two steps instead of 1 cell/step, so a water source that drops
onto a container doesn't pile up indefinitely.
**Known edge**: drop == 0 deliberately declines the move. That's
what keeps a single-cell rim stable on a flat pool; it's also the
source of the residual shimmy described in 3.11.
**Breaks on walls** was a bug — lateral scan must `break` (not
`continue`) on a blocked path cell, else water teleports through
containers. Fixed; don't regress this.

### 4.5 FallingCell merge-back semantics
Each FallingCell paints back into terrain when it lands, and
`paint_cell_at_world` allows overwriting NONE or LIQUID cells (so
sand can displace water). Any other occupied target refuses the
paint. One-shot eviction runs after paint: `_evict_actors_from_cell`
AABB-checks the player and any `get_overlapping_bodies()` returns,
then `_try_evict_actor` pushes them out using the cell vs actor
AABB, preferring the smaller-displacement direction, falling back
to a few cells further if blocked. Lethal if no clearance within
`_STUCK_MAX_CELLS + 1` steps.

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

### 5.7 CC detach diagnostic prints
`connected_components.cpp` is currently logging every BFS outcome
(detach / skip-anchored / skip-over-budget). Use this to debug the
"chunk didn't collapse" case — the log tells you which failure
fired. Remove or gate-with-define before ship.

### 5.8 Damage & CC corner-density refresh
Both the per-cell `_apply_damage_to_cell` destroy path and the CC
detach path now rebuild corner densities from the surrounding type
neighborhood after clearing a cell, instead of blindly zeroing all 4
corners. Fixes the "ground under a detached chunk is no longer
solid" symptom (corner shared with surviving neighbor stays 255).
Keep this invariant if new cell-removal paths appear.

### 5.9 `is_solid()` is corner-density-based; use `is_cell_collidable()` for cell queries
`TerrainWorld.is_solid(pos)` samples the raw density field
(top-left corner of containing cell), so a cell whose corner was
poked to 255 by an adjacent anchor reads as "solid" even when its
own type is NONE. Added `is_cell_non_empty` / `is_cell_type_at` /
`is_cell_collidable` that query `type_per_cell` directly. Use those
for anything cell-granular (FallingCell landing checks, player
stuck detection, water-vs-solid tests). `is_solid` still has its
place for continuous queries like raycasts into density, but never
for "what type is THIS cell."

### 5.10 Flow step `_try_sand_move` must gate the liquid-swap path on source type
Sand source + LIQUID target → swap. Any other source + LIQUID
target → decline. If the source-type gate is missing, a LIQUID cell
above another LIQUID cell `_swap_cells` with itself (no-op but
returns success), which blocks the caller from trying sideways in
the same scan and manifested as water freezing mid-fall. Keep the
gate in place.

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

### 6.7 DLL lock requires full Godot restart
Windows file-locks `libkbterrain.windows.template_debug.x86_64.dll`
while any Godot process has it loaded. A new build lands as
`~libkbterrain…` next to the in-use one. Full editor restart picks
up the new DLL; an in-editor "Reload" or re-opening the project
window is not sufficient. Confirmed via run logs showing the "new"
DLL still behaving as the previous compile.

### 6.8 Chunk `FLOW_STEP_INTERVAL` ticked at 2 (30 Hz)
`terrain_world.h` sets `FLOW_STEP_INTERVAL = 2`, i.e., flow_step
runs every 2 physics frames (effective 30 Hz). Tried 1 (every
frame, 60 Hz) to speed water spread; the doubled per-frame activity
caused visible vibration on pool surfaces the user rejected.
Kept at 2 as the compromise between responsiveness and visual
calm; the drop-aware lateral teleport does the heavy lifting for
spread speed.

### 6.9 Settings debug flag `start_with_full_juice`
`settings.tres` exposes a bool that seeds the player with
`MAX_JUICE = 10` in every colored frequency on `_ready`. Useful for
playtesting pulse behavior without bug-hunting. Default in the
script is `false`; the committed `.tres` instance override is `true`
right now (for current testing). Flip the `.tres` value before a
public build.

---

*Last updated: April 19, 2026. Generated from session-history audit
plus current-session knowledge. Includes the FallingCell per-cell
detach rewrite, liquid-aware two-pass collision meshing, sync
collision shape updates, neighbor-chunk cascade scoping, drop-aware
lateral water spread, swim physics, wedge-kick on jump, conservative
continuous player stuck check, sand-through-water swap, CC budget
bump + diagnostics, and corner-density refresh for damage/CC paths.*
