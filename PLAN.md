# ld59 Implementation Plan

The authoritative living checklist for the echolocation platformer.

Every item is a checkbox. Sessions — Claude or human, on any device —
mark items as they land on `main` using `- [x]`. A phase is complete
when its exit criteria are checked.

## How to use this doc

**When you finish a unit of work on `main`:**

1. Open `PLAN.md`.
2. Change `- [ ]` to `- [x]` on the lines that landed.
3. If scope moved (split a task, discovered a new dep), edit in
   place — don't create a separate TODO.
4. Commit the `PLAN.md` edit with your other changes.

**Before starting a track:**

1. Skim "Parallelization tracks" below; pick an unclaimed track.
2. Check the "Shared files" table for collisions with in-flight
   tracks on other branches.
3. Work on a branch named `track/<slug>` (e.g. `track/shader`).
4. Merge to `main` when your track's exit criteria are met.

**Parallel sessions rule**: only one session should edit any file
at a time. Coordinate via branches. Shared files (listed below)
need serialized edits — the last merger rebases.

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
- **GDExtension**: `ld59extension/`, godot-cpp pinned to
  `godot-4.5-stable` (upstream 4.6 tag not yet cut;
  `compatibility_minimum=4.6` in manifest). googletest pinned at
  v1.15.2. Build via `ld59extension/build_windows.ps1`.
- **Tests**: GoogleTest (C++) via `build_tests.ps1`. GUT (GDScript)
  under `test/` via CI.
- **Web**: threaded + dlink-enabled custom template, self-hosted on
  user's node server with COOP/COEP. Safari gets a fallback page.
  Details in `ld59extension/web-template-setup.md`.

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

These are designed to proceed **in parallel on separate branches**
with minimal shared-file collisions.

| Track | Slug | Primary files | Depends on | Parallel-safe? |
|---|---|---|---|---|
| Shader & visibility | `shader` | `src/echolocation/*` | Nothing | ✅ |
| Terrain C++ core | `terrain-core` | `ld59extension/src/terrain/*` | Nothing (built in isolation) | ✅ |
| Terrain level bake | `terrain-bake` | `src/terrain/terrain_level_loader.gd`, level `.tscn`s | `terrain-core` (API stable) | ⚠️ Sequential after core |
| Flow sim + fragments | `terrain-flow` | `ld59extension/src/terrain/flow_step.*`, `connected_components.*` | `terrain-core` done | ⚠️ Sequential after core |
| Bug system | `bugs` | `src/bugs/*`, `src/core/frequency.gd` | Nothing (stubs) | ✅ |
| Enemy system | `enemies` | `src/enemies/*` | `G.echo.pulse_emitted` (exists) | ✅ |
| Health + HUD | `hud` | `src/player/player_health.gd`, `src/ui/hud/*` | Nothing | ✅ |
| Audio pipeline | `audio` | `src/echolocation/echo_audio_player.gd`, audio assets | Nothing | ✅ |
| Web hosting | `web` | `web/*`, `ld59extension/web-template-setup.md` | Nothing | ✅ |

Claim a track by grepping branches for `track/<slug>`; if none
exists, check it out and begin.

### Shared files (serialize edits)

These files are touched by multiple tracks and must be merged with
care. If you modify any of them, rebase onto `main` before merging.

| File | Touched by |
|---|---|
| `src/core/global.gd` | shader, bugs, enemies, hud |
| `src/core/main.tscn` | shader, hud |
| `project.godot` | any track adding inputs, layers, or autoloads |
| `addons/ld59extension/ld59extension.gdextension` | terrain-core, terrain-flow |
| `ld59extension/SConstruct` | terrain-core, terrain-flow |
| `ld59extension/src/register_types.cpp` | terrain-core, terrain-flow |
| `CLAUDE.md` | all tracks (document as you go) |
| `PLAN.md` | all tracks (check items as you go) |

### Device-splitting suggestions

- **Desktop (fast compile)**: terrain-core, terrain-flow. SCons +
  C++ iteration is ~3× faster on a beefy CPU.
- **Laptop (portable iteration)**: shader, bugs, enemies, hud,
  audio. Pure GDScript iteration; no C++ rebuild loop.
- **Either**: web hosting, terrain-bake.

Binaries in `addons/ld59extension/bin/` are committed — when you
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
- [x] Document web template setup (`ld59extension/web-template-setup.md`)
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
- [ ] Playtest pass: tune `near_radius_px`, `default_pulse_max_radius_px`,
  `fade_tau_sec`, `bayer_tile_px`, `surface_prominence_strength`,
  `interior_floor` until it *feels* right
- [ ] Decide directional cone vs full circle default
- [ ] Tunable pulse cooldown on the player side

### Player

- [x] `current_frequency: int` on `player.gd`, default GREEN
- [x] `set_frequency()` method
- [x] `_unhandled_input` emits pulse on `ability` press
- [ ] Pulse cooldown timer (prevent spam)
- [ ] Visual indicator of current frequency on the player sprite
  (reuse `src/core/outline.gdshader` with a frequency-color uniform)

### Audio (first-pass, load-bearing for feel)

- [x] `echo_audio_player.gd` skeleton subscribes to `pulse_emitted`
- [ ] Author outgoing "chirp" sample
- [ ] Author generic "return ping" sample
- [ ] Wire both into the player, audible on pulse

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

### C++ core (`ld59extension/src/terrain/`)

- [ ] `chunk.{h,cpp}` — per-cell `{density, type, health}`, RIDs,
  `std::atomic<uint64_t> generation`, state enum, fast-path flags
- [ ] `chunk_manager.{h,cpp}` — non-streaming, all chunks live
- [ ] `marching_squares.{h,cpp}` — stateless; 16-case `constexpr`
  table; emits verts+indices+boundary segments
- [ ] `density_splat.{h,cpp}` — carve/fill with smoothstep falloff
- [ ] `douglas_peucker.{h,cpp}` — polyline simplification
- [ ] `worker_pool.{h,cpp}` — single `std::thread` worker
- [ ] `terrain_settings.{h,cpp}` — GDCLASS `Resource`
- [ ] `terrain_world.{h,cpp}` — GDCLASS facade
- [ ] `terrain_world.damage(world_pos, radius, damage, frequency_mask)`
- [ ] `terrain_world.carve() / fill() / sample_density() / is_solid()`
- [ ] `terrain_world.get_surface_height()` for spawn placement
- [ ] `terrain_world.set_cells(coord, PackedByteArray)` bulk import
- [ ] SConstruct: glob `src/terrain/*.cpp`
- [ ] `register_types.cpp`: register `TerrainWorld`, `TerrainSettings`

### C++ tests (GoogleTest)

- [ ] `test_marching_squares.h` — all 16 cases + interpolation
- [ ] `test_density_splat.h` — carve/fill math, idempotence
- [ ] `test_douglas_peucker.h` — straight lines reduce; zig-zag
  preserved
- [ ] `test_worker_pool.h` — generation-counter cancellation
- [ ] `test_terrain_bake.h` — set_cells round-trips

### GDScript integration

- [ ] `TerrainLevelLoader` GDScript — walks TileMapLayer, reads
  tile custom data (`type`, `initial_health`), bulk-pushes to
  `TerrainWorld`
- [ ] Tile custom data layers on the TileSet (`type`, `initial_health`)
- [ ] `terrain_test_level.tscn` with TileMap authoring → bake
- [ ] `terrain_movement_settings.tres` with `floor_max_angle ≈ 60°`,
  `floor_snap_length = 4`
- [ ] `level.gd` awaits `generation_completed`, spawns player at
  `get_surface_height(spawn_x)`
- [ ] Pulse emission calls `G.terrain.damage(...)`

### GDScript tests (GUT)

- [ ] `test_terrain_player_lands.gd`
- [ ] `test_terrain_pulse_carves.gd`

### Phase 2 exit

- [ ] Pulse carves a visible, walkable hole
- [ ] `scons tests=yes` passes all MS tests
- [ ] GUT tests pass in CI

---

## Phase 3 — Bug ecosystem + multi-frequency

**Goal**: core loop is real. Eat bugs, change frequency, pulse
damages only matching tiles.

### Multi-frequency tiles + palette

- [ ] Commit tile art palette (per-frequency colors)
- [ ] Populate `palette`, `palette_freqs`, `palette_count` uniforms
  in `EcholocationRenderer`
- [ ] Enable frequency gating in the composite shader (already wired)
- [ ] Tile custom data: per-tile `type` drives render color

### Bug system (GDScript)

- [ ] `Bug` scene + script (typed, TTL, drift, opacity fade)
- [ ] `BugSpawner` + `BugRegionProbe` (Area2D on player)
- [ ] `BugSpawnRegion : Area2D` with `frequency` + `rate_delta`
- [ ] Rate stacking (additive, clamped ≥ 0 per frequency)
- [ ] Annulus-sampled spawn positions, reject-on-solid up to 8 tries
- [ ] Bug consumption: heal + set player frequency
- [ ] Minimum-rate-floor per frequency (avoid soft-lock)

### Player visuals

- [ ] `set_frequency()` updates outline color uniform
- [ ] HUD frequency indicator (colored chip)

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

- [ ] `PlayerHealth` Node on the player
- [ ] HUD health bar
- [ ] Damage from fluid velocity + fragment collision
- [ ] Scene reload on death at `%PlayerSpawnPoint`

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

- [ ] `Enemy` base class (typed, health, scalar perception, FSM)
- [ ] `MonsterBird` subclass — flying, arc paths
- [ ] `Spider` subclass — wall-crawler (use scaffolder surface raycasts)
- [ ] `FlyingCritter` subclass — small, swarm-ish
- [ ] Perception decay + pulse-raises behavior
- [ ] `EnemySystem.apply_pulse_damage(pulse)` — damage + knockback
  on matching frequency
- [ ] Touch damage → `PlayerHealth.apply_damage`
- [ ] `EnemySpawnPoint` (single-shot) + `RespawningEnemySpawnPoint`
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

```bash
# Start a track
git checkout main && git pull
git checkout -b track/shader

# ... work, commit ...

# Before merging back
git checkout main && git pull
git checkout track/shader
git rebase main              # resolve conflicts here
# Re-run C++ tests + GUT tests if your track touched tested code

git checkout main
git merge track/shader --ff-only    # clean linear history
git push
git branch -d track/shader
```

**Binaries in `addons/ld59extension/bin/`** are committed. When a C++
track pushes a new `.dll`, other in-flight branches may conflict on
merge — just take the newer binary. If your branch hasn't touched
`ld59extension/src/`, `git checkout main -- addons/ld59extension/bin/`
during rebase resolves it.
