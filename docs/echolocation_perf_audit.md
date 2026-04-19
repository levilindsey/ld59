# Echolocation Pulse — Performance Audit

Context: pulses emitted during gameplay occasionally stutter. This is
a triage document mapping what runs on each pulse emit, ranking the
hot paths by likely cost, and proposing optimizations in order of
ROI. No code changes yet — the goal is to know where to look before
spending implementation time.

Pulse call graph (on player fire):

```
Player._emit_echo_pulse()
  G.echo.emit_pulse(pos, freq)
    └─ EcholocationRenderer.emit_pulse(...)
         ├─ _schedule_pings_for_pulse(pulse)   ←  (GDScript, sync)
         └─ pulse_emitted.emit(pulse)
              ├─ TerrainLevel._on_pulse_emitted(pulse)
              │    └─ G.terrain.damage_with_falloff(...)  ← (C++, sync)
              │         └─ _apply_damage_to_cell(...)     × many
              │              └─ emit_signal("tile_destroyed", ...) × destroyed-cells
              │                   └─ EcholocationRenderer._on_tile_destroyed(...)
              │                        ├─ _spawn_debris_particles(pos, type)
              │                        └─ damage_age_tex stamp
              │              └─ emit_signal("chunk_modified", coords) × touched-chunks
              │                   └─ EcholocationRenderer._on_chunk_modified(...)  → sets dirty flag
              └─ EchoAudioPlayer._on_pulse_emitted(pulse)
                   └─ play() (cheap)
# Next frame:
EcholocationRenderer._process(delta)
  └─ (if _terrain_textures_dirty) _rebuild_terrain_textures()
       ├─ G.terrain.build_density_image()   ← (C++)
       ├─ G.terrain.build_type_image()      ← (C++)
       ├─ G.terrain.build_health_image()    ← (C++)
       └─ _type_image_bytes = type_image.get_data()   ← cache refresh for ping scheduler
```

## Cost bill per pulse emit

Current-default radii and counts (from source):
- `_DAMAGE_MAX_RADIUS_PX = 5040.0` (terrain_level.gd:186) → **surface damage reach ≈ 630 cells**.
- `_PROXIMITY_DAMAGE_MAX_RADIUS_PX = 280.0` → tight proximity component.
- `default_pulse_max_radius_px = 1000.0` (renderer export) → **ping scheduler's bbox ≈ 125-cell radius**.
- `_BOUNCE_RAY_COUNT` → now replaced by bulk surface scan (no fixed ray count).
- `_MAX_PINGS = 128`; `_MAX_PARTICLES = 256`.

Dominant hot paths:

### 1. Ping surface scan (GDScript) — `_schedule_pings_for_pulse`
At `pulse.max_radius_px = 1000` and cell_size = 8:
- Local bbox = 250 × 250 = **62 500 cells**.
- Scanned 4 times (N/S/W/E faces) → 250 k cell inspections.
- Per inspection: 1–2 `PackedByteArray` reads (`_type_byte_at`), a run-state update, and segment schedule on terminal edges.
- Segment scheduling per run: distance + arc + facing + LoS DDA call (worst case 200 steps of byte reads).
- Lots of tight GDScript — **probably the single biggest stutter contributor**. Rough ceiling: **30–120 ms** depending on terrain density.

### 2. C++ damage iteration — `damage_with_falloff`
Outer radius = `max(surface_max, proximity_max) = 5040`. Circle area ≈ π·630² ≈ **1.25 M cells** iterated.
Per cell:
- Distance-squared + two falloff lerps (cheap).
- If both damages are 0 (outside all bands): `continue`. Cheap.
- If either damage > 0: `_apply_damage_to_cell` call.
  - For cells whose type doesn't match `frequency_mask`: early-out after 1 byte read + bit check. Cheap.
  - For cells that DO match: 4 × `world_cell_type()` calls (each a `ChunkManager::get` hash lookup + array index), composite-normal math, `health_per_cell` subtract.
- Typical matching-type cell count in a radius: ~2–15% of iterated cells → 25 k – 180 k matching cells × ~4 hash lookups = 100 k – 720 k hash hits.
- Rough ceiling: **10–40 ms**. Second biggest.

### 3. Image rebuild on chunk_modified
`_on_chunk_modified` just flips a bool. The actual rebuild happens once per frame in `_process`, coalescing all dirty chunks in this pulse. So:
- `build_density_image()` + `build_type_image()` + `build_health_image()` × 3 per frame.
- Each: iterate all chunks in the world, `memcpy` per-row of `density`/`type_per_cell`/`health_per_cell`. For a small jam level (~100 × 50 cells, 1–2 chunks), that's a few KB each — **sub-ms**.
- Three separate `ImageTexture.update()` calls — fine.
- `_type_image_bytes = type_image.get_data()` — another copy the ping scheduler needs. Cheap at small scale.
- **Not a stutter contributor at current level sizes.** Would grow linearly with world size.

### 4. Particle + ping pool spawns
Per pulse, up to `_PARTICLES_PER_DESTROYED_CELL × destroyed-cells` new `EchoParticle` `RefCounted` instances and up to 128 new `EchoPing` instances. GDScript `RefCounted.new()` is ~1–5 µs.
- Say 80 cells destroyed × 6 particles + 64 pings = **~550 allocs** → **0.5–3 ms**.
- Not dominant. Worth addressing if pool exhaustion warnings start showing up.

### 5. Shader uniform pack/upload
Per frame (every frame): `set_shader_parameter` calls for `pulses[]`, `pings[]`, `ping_segments[]`, `ping_normals[]`, `particles[]`, plus the three texture samplers. Even when nothing changes, the uniform arrays get re-packed and re-pushed.
- Each array is `_MAX_PULSES=8 / _MAX_PINGS=128 / _MAX_PARTICLES=256` × vec4 = up to 256 × 16 bytes = 4 KB.
- Godot 4 `set_shader_parameter` with `PackedVector4Array` is fast but not free.
- Rough: **0.2–1 ms per frame**. Steady-state cost, not spike.

### 6. Signal fan-out on `tile_destroyed`
Every destroyed cell emits one signal. Handler per signal: stamp + spawn particles. For 80 destroyed cells, 80 signal emits → GDScript handler work ~0.5–2 ms total. Not dominant but scales with destruction count.

## Profiling: how to measure for real

Before changing code, measure. The cheap instrumentation paths:

1. **Godot's built-in Performance/Profiler tab** — captures per-frame script time. Open it, trigger pulses, watch the spike frame. The "Frame" and "Physics Frame" bars plus per-script hotspots show which function tops the list.

2. **Manual GDScript timing** with `Time.get_ticks_usec()` around the candidates. Add temp `print` at key boundaries:
   - `_schedule_pings_for_pulse`
   - `_rebuild_terrain_textures`
   - `_on_tile_destroyed`
   - The `_process` body (end-to-end)
   The `G.print` macro is already used in the project; no new infra needed.

3. **C++ timing** via `OS::get_ticks_usec()` or a simple `std::chrono::steady_clock` around `damage_with_falloff`'s cell loop. Print the total microseconds with cell count + destroyed count. Requires a rebuild.

4. **Render-thread spikes** — if the shader compile hiccups on first run, that's a one-time cost. Watch for first-pulse-only stuttering; later pulses running clean points to shader pipeline warmup, not CPU.

Typical cadence: log for 5–10 pulses, look at median + max. The first pulse after scene load may include warmup costs (GPU pipeline, first-time `Image.create_from_data`, etc.) that won't repeat.

## Optimization catalog

Ordered by ROI (cheap wins first). Each entry: **expected impact** / **effort** / **risk**.

> **Status (2026-04-19):** cheap wins **A, B, C, D** have all landed
> on `main`. F, G, H, I, J, K still open — consider after measuring
> whether the stutter is resolved at current scale.

### Cheap wins (≤1 hour, low risk)

**A. ✅ LANDED. Decouple ping scan radius from pulse travel radius.**  
The ping scheduler currently scans within `pulse.max_radius_px` = 1000 px. The visual pulse wave only becomes visible within `stipple_fade_end_px ≈ 420` anyway, and bounce lines beyond a few hundred px don't visually register. Adding a dedicated `_PING_SCAN_MAX_RADIUS_PX = 600` (or similar) and using that instead of `pulse.max_radius_px` in `_schedule_pings_for_pulse`'s bbox cuts the scan by **(600/1000)² = 0.36×** → **2.8× speedup on the scan**.  
Impact: large. Effort: one-line const + bbox calc. Risk: none (visual cutoff is already shorter than the ping range).

**B. ✅ LANDED. Reduce `_DAMAGE_MAX_RADIUS_PX`.**  
5040 px is extreme — the camera's visible frame at zoom 2 is ~576 × 324 world px. Most cells at 4000+ px are off-screen and the player can't see them chip. A range of 1500–2000 still easily crosses the screen diagonal and gives "hit the wall far away" feel.  
Impact: huge. Radius² scaling. 5040 → 1500 = **11× less work** in `damage_with_falloff`. Effort: const tweak. Risk: mild game-feel regression — far cells no longer chip. Cosmetic re-tune.

**C. ✅ LANDED. Skip the outer-radius cell loop sooner when neither component applies.**  
In `damage_with_falloff`'s inner loop: if `d_sq > surface_r_sq` AND `d_sq > proximity_r_sq`, `continue` BEFORE computing any falloff math. Current code handles this implicitly because both damages end up 0, but the `sqrt(d_sq)` call still fires for each cell in the outer bbox. Hoist the early-exit.  
Impact: small–medium (saves a `sqrt` per non-damaging cell — about 1.1 M `sqrt` calls at max radius).  Effort: 3 lines. Risk: none.

**D. ✅ LANDED. Early type-mismatch in the outer loop, before `_apply_damage_to_cell`.**  
Inline the type-byte read + `frequency_mask` check in the outer loop. Skip the function call, skip all falloff math for non-matching cells.  
Impact: medium. Saves function-call overhead × 1.1 M mismatching cells. Maybe 5–15 ms.  
Effort: ~20 lines — lift type check from `_apply_damage_to_cell` up into the caller. Risk: must keep the two callers (`damage`, `damage_with_falloff`) in sync with the inlined check.

**E. Budget the ping scheduler.**  
After N segments scheduled (say, the cap `_MAX_PINGS / 2 = 64`), stop scanning. The scan is inherently sorted in scan-line order, so distant segments get dropped first. Prevents worst-case dense-terrain explosions.  
Impact: bounds the worst case. Effort: one early-return. Risk: visual — a chaotic dense cell could miss pings on its far side.

### Medium wins (few hours, moderate risk)

**F. Pre-sized particle + ping pools with value-type structs.**  
Replace `EchoParticle` and `EchoPing` (both `RefCounted`) with plain-struct arrays of floats in the renderer. Each "slot" is a few floats in parallel arrays; `null` becomes a `active: bool` field. Eliminates per-pulse allocations.  
Impact: 1–3 ms per pulse saved; removes GC pressure entirely.  
Effort: rewrite the pool classes. Risk: mild — changes the API slightly.

**G. Move ping scan to C++.**  
The scan walks cached `_type_image_bytes` 4× in GDScript. In C++ it'd be a few hundred microseconds instead of tens of milliseconds. Add `TerrainWorld::enumerate_surface_segments(center, radius, arc, arc_dir) -> PackedFloat32Array` (flat list of `x0, y0, x1, y1, nx, ny` per segment).  
Impact: **huge — reduces the dominant hot path from ~50 ms to ~0.5 ms.** Probably the biggest single win available.  
Effort: 1–2 hours (C++ method + bind + renderer consumes the packed array). Risk: C++ rebuild; need to keep GDScript fallback around for hot-reload.

**H. Batch `tile_destroyed` emits.**  
C++ currently emits one signal per destroyed cell. For a 50-cell destruction, 50 hops across the engine boundary + 50 handler runs. Instead emit a single `cells_destroyed(PackedVector2Array world_positions, PackedInt32Array types)` at the end of the damage call. GDScript handler loops through the arrays.  
Impact: 1–5 ms savings per dense pulse.  
Effort: change signal signature + C++ caller + GDScript handler + `EcholocationRenderer` spawn logic.  
Risk: compatibility — need to migrate any other `tile_destroyed` listeners (check in `EchoAudioPlayer`, `EnemySystem`, etc.).

### Big wins (day+, higher risk / requires more scaffolding)

**I. Per-type cell index in C++.**  
`TerrainWorld` maintains a `std::unordered_map<int, std::vector<Vector2i>>` of world-cell coords keyed by type. `damage_with_falloff` iterates only the list matching `pulse.frequency`, pre-filtering by distance. Avoids iterating 1.1 M non-matching cells entirely.  
Impact: **enormous** at large radii. Damage cost becomes proportional to matching-cell count (a few thousand at most) instead of total radius area.  
Effort: substantial — maintain the index on every type change (`_apply_damage_to_cell`, `set_cells`, `paint_cell_at_world`, flow CA). Risk: easy to get the index out of sync; bugs manifest as "wrong cells damaged" or "cells that should have died didn't."

**J. Chunk-level damage culling.**  
Before iterating cells, quickly check each chunk: does it contain any cell of the pulse's frequency? Maintain a `has_type_X: bool` per chunk, updated on damage. Skip chunks that don't. Cheaper cousin of (I).  
Impact: medium–large. A pulse passing over a mostly-RED region with a GREEN pulse can skip all-RED chunks entirely.  
Effort: moderate. Risk: low as long as the flag is maintained wherever type changes.

**K. Time-slice damage across frames.**  
Damage doesn't need to be applied instantaneously; the visual pulse ring takes ~1.2 s to sweep. Collect affected chunks on emit, process N chunks per frame using the pulse's current wave radius to gate "has the wavefront reached this chunk yet." Physics-style tick.  
Impact: eliminates frame spikes even at huge radii; damage smoothly applies as the wave passes.  
Effort: large — need a damage scheduler + per-frame progression + signal buffering.  
Risk: semantics change — damage is no longer instantaneous. Interacts with pulse cooldown, chaining, etc.

**L. Throttle `_rebuild_terrain_textures` on mid-pulse damage.**  
Currently fires every frame a chunk is dirty. With the partial-damage path emitting `chunk_modified` on every pulse that touches a chunk, the three image rebuilds can run every pulse even if nothing visually changed (health dropped from 200 to 150 but the shader overlay is the same atlas tier).  
Impact: scales with world size. Small jam level = negligible; big authored level = meaningful.  
Effort: add a `min_health_change_for_rebuild` heuristic or only rebuild `health_tex` (not density/type) on partial-damage events. Risk: cracks won't animate smoothly.

## Recommended sequence

1. **Measure first** (profiler tab or manual timing). Confirm the stutter's timing signature — one-shot spike, periodic, scaling with destruction count, etc.
2. **A + B + C + D together** — all one-line-ish constant/inlining changes. Expected combined speedup: 3–5× on pulse emit. Ship these before touching the big stuff.
3. **F** (struct pools) — low risk, removes GC spikes.
4. **G** (C++ ping scan) — if profiling confirms the GDScript loop is the top-of-list, this is the single-best leverage change.
5. **H** (batched `tile_destroyed`) — only if signal fan-out shows up.
6. **I** or **J** (type-indexed damage) — only if the damage iteration is still the bottleneck AND radius can't be reduced further. Start with **J** (cheaper).
7. **K** (time-sliced damage) — last resort if instant spikes remain unacceptable.

## Notes

- The stutter may be cache-miss-driven. `damage_with_falloff` iterates cells row-major, but `world_cell_type` lookups may cross chunks (cache-unfriendly). Pre-sorting affected chunks by coordinate locality could help. Profile first.
- Shader compile is a one-time cost on first pulse — if only the FIRST pulse stutters, it's GPU pipeline warmup, not algorithmic cost. Fix by triggering a harmless dry-run pulse during level load.
- The `_MAX_PARTICLES = 256` uniform array adds ~4 KB to shader push per frame. On WebGL2 this is under the limit but worth watching.
- Nothing above touches the rendering shader itself, which is per-pixel and GPU-bound. If frame rate drops steadily (not a spike), that's a different audit — profile GPU via `godot --debug-stringnames` or RenderDoc.
