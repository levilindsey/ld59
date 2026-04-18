# Kittenbaticorn Implementation Plan

The authoritative living checklist for the echolocation platformer.

Every item is a checkbox. Sessions — Claude or human, on any device —
mark items as they land on `main` using `- [x]`. A phase is complete
when its exit criteria are checked.

Accumulated engineering context — shader tuning values and tradeoffs,
deferred shader work waiting for Phase 2, Godot/AMD/web quirks
discovered along the way, architectural contracts to preserve across
rewrites — lives in [`docs/notes.md`](docs/notes.md). Read that at
the start of any shader or rendering-adjacent session, and append to
it as you learn new quirks or make decisions worth preserving.

## How to use this doc

**When you finish a unit of work on `main`:**

1. Open `PLAN.md`.
2. Change `- [ ]` to `- [x]` on the lines that landed.
3. If scope moved (split a task, discovered a new dep), edit in
   place — don't create a separate TODO.
4. Commit the `PLAN.md` edit with your other changes.

**Before starting a track:**

1. Skim "Parallelization tracks" below; pick an unclaimed track.
2. Check the "Shared files" table for collisions with work that's
   already in flight on another machine/session.
3. Work directly on `main`. No feature branches. `git pull --rebase`
   before you start; push small, focused commits often so other
   sessions see your changes.

**Parallel sessions rule**: all work lands on `main`. Only one
session should edit any single file at a time. Shared files (listed
below) need serialized edits — pull, edit, commit, push before the
next session picks them up.

---

## Top-level architecture (reference)

Dark 2D exploration platformer. Player navigates via echolocation
(small always-on radius + triggered pulse). Eating bugs changes your
echolocation frequency; only matching-frequency pulses damage
matching-frequency tiles and enemies. Statically authored levels.
Marching-squares terrain in a C++ GDExtension with destruction,
creation (sand/liquid), and connected-component detachment.

- **Engine**: Godot 4.6.2-stable.
- **Renderer**: `gl_compatibility` (WebGL2 on web). No compute
  shaders, no MRT, no float RTs.
- **GDExtension**: `kbterrain/`, godot-cpp pinned to
  `godot-4.5-stable` (upstream 4.6 tag not yet cut;
  `compatibility_minimum=4.6` in manifest). googletest pinned at
  v1.15.2. Build via `kbterrain/build_windows.ps1`.
- **Tests**: GoogleTest (C++) via `build_tests.ps1`. GUT (GDScript)
  under `test/` via CI.
- **Web**: threaded + dlink-enabled custom template, self-hosted on
  user's node server with COOP/COEP. Safari gets a fallback page.
  Details in `kbterrain/web-template-setup.md`.

Subsystems:

- **TerrainWorld** (C++) — chunked marching-squares, per-cell
  `{density, type, health}`, damage, flow sim, CC detachment.
- **EcholocationRenderer** (GDScript + shader) — single composite
  ColorRect reading backbuffer via `hint_screen_texture`. Traveling
  wave with Bayer dither and palette-driven frequency gating.
- **BugSystem** — spawn around player at region-modulated rates;
  eating changes player frequency and heals.
- **EnemySystem** — typed, frequency-colored, scalar perception.
- **PhysicsProps** — RigidBody2D objects that fall when terrain
  beneath is carved.
- **PlayerHealth + HUD** — health bar, frequency indicator, echo
  cooldown.
- **EchoAudio** — outgoing chirp + delayed surface-reflected return
  pings. Load-bearing, not polish.

Full rationale, tradeoff discussion, and design alternatives considered
live in the planning archive at
`~/.claude/plans/ok-i-m-actually-going-greedy-pillow.md` on Levi's
machine.

---

## Parallelization tracks

These are designed to proceed **in parallel on `main`** across
multiple machines/sessions. No feature branches — the tracks are a
planning aid for who works on what, not a branching scheme.

| Track | Slug | Primary files | Depends on | Parallel-safe? |
|---|---|---|---|---|
| Shader & visibility | `shader` | `src/echolocation/*` | Nothing | ✅ |
| Terrain C++ core | `terrain-core` | `kbterrain/src/terrain/*` | Nothing (built in isolation) | ✅ |
| Terrain level bake | `terrain-bake` | `src/terrain/terrain_level_loader.gd`, level `.tscn`s | `terrain-core` (API stable) | ⚠️ Sequential after core |
| Flow sim + fragments | `terrain-flow` | `kbterrain/src/terrain/flow_step.*`, `connected_components.*` | `terrain-core` done | ⚠️ Sequential after core |
| Bug system | `bugs` | `src/bugs/*`, `src/core/frequency.gd` | Nothing (stubs) | ✅ |
| Enemy system | `enemies` | `src/enemies/*` | `G.echo.pulse_emitted` (exists) | ✅ |
| Health + HUD | `hud` | `src/player/player_health.gd`, `src/ui/hud/*` | Nothing | ✅ |
| Audio pipeline | `audio` | `src/echolocation/echo_audio_player.gd`, audio assets | Nothing | ✅ |
| Web hosting | `web` | `web/*`, `kbterrain/web-template-setup.md` | Nothing | ✅ |

Claim a track informally: glance at recent commits touching its
primary files and at the checklist below. If nothing's in flight,
start working on `main`.

### Shared files (serialize edits)

These files are touched by multiple tracks. Since everyone works on
`main`, serialize edits: `git pull --rebase` before touching one,
commit and push in a tight loop, and avoid holding local changes on
these files overnight.

| File | Touched by |
|---|---|
| `src/core/global.gd` | shader, bugs, enemies, hud |
| `src/core/main.tscn` | shader, hud |
| `project.godot` | any track adding inputs, layers, or autoloads |
| `addons/kbterrain/kbterrain.gdextension` | terrain-core, terrain-flow |
| `kbterrain/SConstruct` | terrain-core, terrain-flow |
| `kbterrain/src/register_types.cpp` | terrain-core, terrain-flow |
| `CLAUDE.md` | all tracks (document as you go) |
| `PLAN.md` | all tracks (check items as you go) |

### Device-splitting suggestions

- **Desktop (fast compile)**: terrain-core, terrain-flow. SCons +
  C++ iteration is ~3× faster on a beefy CPU.
- **Laptop (portable iteration)**: shader, bugs, enemies, hud,
  audio. Pure GDScript iteration; no C++ rebuild loop.
- **Either**: web hosting, terrain-bake.

Binaries in `addons/kbterrain/bin/` are committed — when you
switch devices, pull `main` and you're ready.

---

## Phase 1 — Dark-room feel gate

**Goal**: validate that echolocation feels good as the core sensation.
Near-radius + traveling-wave pulse, pointillism-on-tiles,
surface-facing prominence, one frequency, no damage yet.

### Engine / build toolchain

- [x] Set compatibility_minimum to 4.6 in `.gdextension` manifest
- [x] Verify C++ extension loads in Godot 4.6.2 editor
- [x] Make `build_tests.ps1` detect the 4.6.2 binary
- [x] Document web template setup (`kbterrain/web-template-setup.md`)
- [x] Add node static-server + COOP/COEP config (`web/server.js`)
- [x] Safari fallback HTML (`web/safari_fallback.html`)
- [ ] Build a custom dlink-enabled threaded web template locally
- [ ] Smoke-test web export (Chrome + Firefox + Safari-fallback)

### Core types

- [x] `Frequency` enum + palette (`src/core/frequency.gd`)
- [x] `EchoPulse` RefCounted (`src/core/echo_pulse.gd`)

### Echolocation renderer

- [x] Composite shader v1 (darkness mask + Bayer dither)
- [x] Traveling-wave pulse math (leading edge + fading trail)
- [x] Multiple concurrent pulses (max over array)
- [x] UV-space coordinates (resolution independent)
- [x] `hint_screen_texture` — render effects ON tile pixels
- [x] Surface gradient + player-facing dot product
- [x] Palette-based frequency gating (wired, inactive)
- [x] `EcholocationRenderer` Node + pulse pool + uniform repack
- [x] Camera2D anchor_mode set to DRAG_CENTER in `level.gd`
- [x] `G.echo` registered in `global.gd`
- [x] Renderer added to `Main.tscn` at layer 100
- [x] `stipple_color` uniform (magenta default) for decoupling
  stipple color from tile art
- [x] Near-radius shows real scene colors; pulse uses stipple color
- [x] Facing threshold smoothstep + raw-luminance `has_content` to
  kill back-facing and open-space stipple leaks
- [x] Game Panel `start_level()` idempotent (`start_in_game=true`
  had been double-instantiating the level)
- [ ] Playtest pass: tune `near_radius_px`, `default_pulse_max_radius_px`,
  `fade_tau_sec`, `bayer_tile_px`, `surface_prominence_strength`,
  `interior_floor` until it *feels* right
- [ ] Decide directional cone vs full circle default
- [ ] Tunable pulse cooldown on the player side

**More shader work is deferred until Phase 2 lands** — procedural
tile rendering, density-field-based surface detection, frequency
palette activation, bug/enemy visibility modes. See
[`docs/notes.md`](docs/notes.md) "Deferred shader work" for the
list and the rationale (SDF from the density field makes the
remaining items significantly cleaner to implement).

### Player

- [x] `current_frequency: int` on `player.gd`, default GREEN
- [x] `set_frequency()` method
- [x] `_unhandled_input` emits pulse on `ability` press
- [ ] Pulse cooldown timer (prevent spam)
- [ ] Visual indicator of current frequency on the player sprite
  (reuse `src/core/outline.gdshader` with a frequency-color uniform)

### Audio (first-pass, load-bearing for feel)

- [x] `echo_audio_player.gd` skeleton subscribes to `pulse_emitted`
- [x] Author outgoing "chirp" sample (synthesized via
  AudioStreamWAV at runtime)
- [x] Author generic "return ping" sample (synthesized)
- [x] Wire both into the player, audible on pulse
  (EchoAudioPlayer instanced in `main.tscn`)

### Phase 1 exit

- [ ] A playtest session with 2-3 people confirms "this feels like
  an echolocation game"
- [ ] near/echo radii are tuned values we intend to keep
- [ ] Web export smoke-tested (Chrome + Firefox + Safari fallback)

---

## Phase 2 — Destructible terrain (single frequency)

**Goal**: TerrainWorld in C++ replaces the TileMap for collision and
rendering. Pulse damages and destroys tiles. One frequency type +
Indestructible.

### C++ core (`kbterrain/src/terrain/`)

- [x] `chunk.{h,cpp}` — per-cell `{density, type, health}`, RIDs,
  `std::atomic<uint64_t> generation`
- [x] `chunk_manager.{h,cpp}` — non-streaming, all chunks live
- [x] `marching_squares.{h,cpp}` — stateless; 16-case `constexpr`
  table; emits verts+indices+boundary segments
- [x] `density_splat.{h,cpp}` — carve/fill with smoothstep falloff
- [x] `douglas_peucker.{h,cpp}` — polyline simplification + line-
  soup chaining
- [x] `worker_pool.{h,cpp}` — single `std::thread` worker,
  generation-counter cancellation
- [x] `terrain_settings.{h,cpp}` — GDCLASS `Resource` with
  per-frequency color palette
- [x] `terrain_world.{h,cpp}` — GDCLASS facade
- [x] `terrain_world.damage(world_pos, radius, damage, frequency_mask)`
- [x] `terrain_world.carve() / fill() / sample_density() / is_solid()`
- [x] `terrain_world.get_surface_height()` for spawn placement
- [x] `terrain_world.set_cells(coord, PackedByteArray)` bulk import
- [x] SConstruct: glob `src/terrain/*.cpp`
- [x] `register_types.cpp`: register `TerrainWorld`, `TerrainSettings`

### C++ tests (GoogleTest)

- [x] `test_marching_squares.h` — 8 tests: empty, full, single
  corner, trapezoid, both diagonal ambiguities, midpoint
  interpolation, multi-cell chunk
- [x] `test_density_splat.h` — 6 tests: carve clears, fill inverse,
  feather falloff, clamp-to-0, AABB clamp, outside-chunk no-op
- [x] `test_douglas_peucker.h` — 5 tests: straight-line collapses,
  zig-zag preservation/collapse, empty input, line-soup chaining
- [x] `test_terrain_world.h` — ChunkManager get/create, world-to-
  chunk mapping, splat-affected-chunks iteration
- [ ] `test_worker_pool.h` — generation-counter cancellation
  (deferred: threading tests are flaky)

### GDScript integration

- [x] `TerrainLevelLoader` GDScript — `bake_from_tile_map_layer`
  and `bake_rect` entry points
- [x] `terrain_level.tscn` with TerrainWorld + hand-coded rect
  test pattern (authoring via TileMap custom data layers deferred
  to Phase 3 when per-tile types arrive)
- [x] `level.gd` subclass `TerrainLevel` bakes terrain on `_ready`,
  spawns player at the top of the test rect, wires pulse → damage
- [x] `Settings.default_level_scene` points to
  `terrain_level.tscn`
- [x] `G.terrain` autoload field registered in `global.gd`
- [ ] `terrain_movement_settings.tres` with `floor_max_angle ≈ 60°`,
  `floor_snap_length = 4` (pending in-editor playtest)
- [ ] Tile custom data layers on the TileSet (`type`,
  `initial_health`) — deferred to Phase 3

### Procedural terrain art

- [x] Placeholder `dirt` (interior) + `grass` (surface strip)
  textures generated in GDScript via
  `PlaceholderTerrainTextures.make_*`
- [x] Composite shader: procedural branch samples interior in
  world-space + surface in rotated-tangent UVs, blends by gradient
  magnitude (band)
- [x] `world_origin` + `world_per_screen_px` uniforms track
  camera transform per frame

### Editor authoring (`@tool` preview)

- [x] `TerrainWorld._editor_mode`: synchronous mesh path (worker
  bypassed) when running under `Engine.is_editor_hint()`
- [x] `TerrainWorld.clear_all()` to wipe chunks + free RIDs before
  re-bake
- [x] `TerrainLevel` is `@tool`; in editor it bakes the child
  TileMapLayer and renders the live MS preview, re-baking on
  `TileMapLayer.changed`
- [x] `terrain_level.tscn` includes a `Tiles` `TileMapLayer` child
  using `default_tile_set.tres` for authoring
- [x] Inspector "Refresh preview" toggle for manual re-bake
- [x] Editor mode skips physics-body creation (avoids stomping
  editor-mode tools); collision is rebuilt at runtime

### GDScript tests (GUT)

- [ ] `test_terrain_player_lands.gd` (pending in-editor verification)
- [ ] `test_terrain_pulse_carves.gd`

### Phase 2 exit

- [x] All 25 C++ tests pass (`build_tests.ps1` green)
- [ ] In-editor: player lands on terrain, pulse carves visible holes,
  procedural grass/dirt renders on tile edges/interiors

---

## Phase 3 — Bug ecosystem + multi-frequency

**Goal**: core loop is real. Eat bugs, change frequency, pulse
damages only matching tiles.

### Multi-frequency tiles + palette

- [x] Commit tile art palette — per-frequency mid-shade colors in
  `Frequency.PALETTE` / `TerrainSettings::color_*`. RED is pinkish,
  GREEN is teal, BLUE is bright cyan-blue, YELLOW is amber-orange,
  LIQUID is a darker water blue, SAND is greyish yellow,
  INDESTRUCTIBLE is near-black charcoal.
- [x] Added `YELLOW` to `Frequency.Type` + `TerrainSettings::Type`
  + new `color_yellow` property (C++ rebuilt, 22 tests pass).
- [x] `PlaceholderTerrainTextures` regenerated as **two atlases**
  (`make_interior_atlas()` + `make_surface_atlas()`). Each has
  `Frequency.ATLAS_SLOT_COUNT = 8` slots, indexed by the Frequency
  enum ordinal.
- [x] Interior atlas has per-type 3-shade palettes (dark/mid/
  light). Surface atlas has per-type accent palettes (rusty for
  RED, lime for GREEN, cyan-mint for BLUE, ochre for YELLOW),
  plus a water-shine treatment for LIQUID. INDESTRUCTIBLE and
  SAND slots in the surface atlas are transparent — the alpha
  channel gates the shader's surface blend so they fall back to
  interior-only naturally.
- [x] `EcholocationRenderer._ready` populates `palette`,
  `palette_freqs`, `palette_count` via
  `PlaceholderTerrainTextures.build_palette_uniforms()`, activating
  per-pixel frequency detection.
- [x] Composite shader samples `interior_atlas` + `surface_atlas`
  at the detected type's slot (`u = type/slot_count + fract(world/
  interior_scale_px)/slot_count`). Surface alpha × gradient
  magnitude drives the band blend.
- [ ] Tile custom data layers on the TileSet (`type`,
  `initial_health`) — enables per-tile authoring in the TileMap.
- [ ] Playtest: verify 4 destroyable types read distinctly; moss/
  shine accents look good; frequency gating feels right.
- [ ] Pick up other deferred shader work from
  [`docs/notes.md`](docs/notes.md) (SDF-based surface detection,
  bug medium-range visibility, enemy perception glow).

### Bug system (GDScript)

- [x] `Bug` scene + script (typed, TTL, drift, opacity fade)
- [x] `BugSpawner` + `BugRegionProbe` (Area2D on player)
- [x] `BugSpawnRegion : Area2D` with `frequency` + `rate_delta`
- [x] Rate stacking (additive, clamped ≥ 0 per frequency)
- [x] Annulus-sampled spawn positions, reject-on-solid up to 8 tries
- [x] Bug consumption: set player frequency
- [x] Bug consumption: heal
- [x] Minimum-rate-floor per frequency (avoid soft-lock)

### Player visuals

- [ ] `set_frequency()` updates outline color uniform
- [x] HUD frequency indicator (colored chip)

### GDScript tests

- [ ] `test_bug_frequency_change.gd`
- [ ] `test_bug_spawn_region_stacking.gd`

### Phase 3 exit

- [ ] In a mixed-frequency test room, eating a bug switches frequency
  and the pulse then only carves matching tiles

---

## Phase 4 — Hazards (flow, fragments, health)

**Goal**: environment hurts the player.

### C++ flow sim

- [ ] `flow_step.{h,cpp}` — sand + liquid CA, double-buffered,
  dirty-cell bitset
- [ ] Flow-remesh sync: flow queues remeshes on main thread
- [ ] `fluid_velocity_at(pos)` sampled each physics frame for
  player-damage from fast fluid

### C++ connected components + fragments

- [ ] `connected_components.{h,cpp}` — union-find over damaged
  chunks
- [ ] CC detachment threshold + indestructible-anchor rules
- [ ] `TerrainChunkFragment` RigidBody2D — mesh + collision from
  MS+DP on subregion
- [ ] Particle burst on detach

### GDScript

- [x] `PlayerHealth` Node on the player
- [x] HUD health bar
- [ ] Damage from fluid velocity + fragment collision (blocked on
  `terrain-flow`)
- [x] Scene reload on death at `%PlayerSpawnPoint` (routed via
  `Player._on_died` → `G.level.game_over()`)

### Tests

- [ ] C++: `test_flow_step.h`, `test_connected_components.h`,
  `test_terrain_fragment_mesh.h`
- [ ] GUT: `test_fragment_falls_and_rests.gd`, `test_sand_piles.gd`

### Phase 4 exit

- [ ] Carving a support detaches a chunk that falls as a RigidBody2D
- [ ] Falling fragments damage the player; sand/liquid behave
  plausibly

---

## Phase 5 — Enemies

**Goal**: something to fight.

- [x] `Enemy` base class (typed, health, scalar perception, FSM)
- [x] `MonsterBird` subclass — flying, arc paths
- [x] `Spider` subclass — floor-crawler via downward raycast
- [ ] `Spider`: wall- and ceiling-crawl via scaffolder surface raycasts
- [x] `FlyingCritter` subclass — small, swarm-ish
- [x] Perception decay + pulse-raises behavior
- [x] `EnemySystem.apply_pulse_damage(pulse)` — damage + knockback
  on matching frequency
- [x] Touch damage → `PlayerHealth.apply_damage`
- [x] `EnemySpawnPoint` (single-shot) + `RespawningEnemySpawnPoint`
  (max active + interval)

### GDScript tests

- [ ] `test_enemy_perception_decay.gd`
- [ ] `test_enemy_takes_pulse_damage.gd`
- [ ] `test_respawning_spawn_point.gd`

### Phase 5 exit

- [ ] In a test scene: enemies pursue on pulse, die to matching-
  frequency pulses with knockback, touch-damage the player

---

## Phase 6 — Audio polish + jam exit

- [ ] EchoAudioPlayer: M-ray surface returns with per-ray delay + pan
- [ ] Pooled `AudioStreamPlayer2D` nodes for concurrent pulses
- [ ] Shader polish: stippling size, per-frequency chromatic tint,
  ring glow fine-tune
- [ ] Particle polish: tile destroy, bug eat, enemy hit
- [ ] Game-over flow + restart
- [ ] Pause respects in-flight pulses (use `G.time`)
- [ ] Final web build + itch.io / custom-host deploy
- [ ] Tests: `test_rle_codec.h`, `test_terrain_save_load.gd` (if time)

---

## Top risks (watch list)

1. **Phase 1 feel gate**. If echolocation doesn't feel good, nothing
   else matters. Tune before building more.
2. **Audio is load-bearing**. Pull chirp + return into Phase 1, not
   Phase 6.
3. **MS slope angle vs `floor_max_angle`**. Needs tuning in Phase 2
   on real authored terrain.
4. **Flow-remesh race**. Flow writes density; worker meshes from
   snapshot. Must drain flow changes before remeshing.
5. **Frequency-gated soft-lock**. Minimum-rate-floor on `BugSpawner`
   prevents this.
6. **Post-process on WebGL2**. SubViewport → black unless Update
   Mode = Always (Godot #86258).
7. **Hot-reload friction**. GDExtension DLL locked while editor is
   open. Iterate GDScript first, port hot paths later.
8. **Custom web template build**. One-time pain. Not at jam
   submission time.
9. **Safari exclusion**. Fallback page documented; acceptable.

---

## Git workflow for parallel work

Everything lands on `main`. No feature branches.

```bash
# Start or resume work
git pull --rebase origin main

# ... work, small focused commits ...

git pull --rebase origin main    # pick up any concurrent pushes
git push
```

Push frequently so other sessions see your changes. Before editing
anything listed under "Shared files" above, pull first to minimize
rebase pain.

**Binaries in `addons/kbterrain/bin/`** are committed. If a
concurrent C++ change pushed a new `.dll` while you were working on
pure GDScript, your rebase may flag the binary as conflicted — take
the remote version: `git checkout --theirs addons/kbterrain/bin/`.
