# Engineering notes

Context accumulated during Phase 1 that will be useful when picking
up later phases. Referenced from `PLAN.md`.

---

## Shader state (Phase 1 exit)

**Pipeline**: single composite `ColorRect` in a CanvasLayer at
layer=100, on top of gameplay at layer=0. Reads the scene backbuffer
via `hint_screen_texture`, outputs a fully opaque overlay:
- Near-radius around the player = real scene colors (smooth reveal,
  no dither).
- Pulse-revealed pixels (traveling wave + Bayer dither) = magenta
  stipple by default, via the `stipple_color` uniform.
- Everything else = solid black. Ring glow added on top as an
  additive layer so the wave front is readable over dark.

**Surface detection**: luminance gradient of the backbuffer at
`±gradient_tap_px` (default 8 px) offsets, clamped and amplified.
Gradient magnitude drives the surface-prominence weight; gradient
direction (negated) is the outward surface normal. `facing` is
`smoothstep(facing_threshold_lo, facing_threshold_hi, dot(normal,
to_player))`. Interior-floor mix lets flat interiors dither lightly
when desired.

**Frequency palette**: wired but inactive. `palette_count = 0` means
"match everything." When Phase 3 ships tile art, populate `palette`
(up to 16 RGBA colors), `palette_freqs` (int enum per slot), and
`palette_count`. Shader does nearest-palette-match per pixel to
derive its frequency, compares against `current_frequency`, and
only stipples on matching pixels.

**Tuning values that produced a good feel in Phase 1**:
| param | value | notes |
|---|---|---|
| `surface_prominence_strength` | 1.0 | full gating |
| `interior_floor` | 0.0 | hard-cut tile interiors |
| `background_luma_threshold` | 0.2 | Godot default clear color is ~0.17 |
| `gradient_tap_px` | 8.0 | half a 16 px tile — finds tile boundaries, not pixel-art detail |
| `facing_threshold_lo` / `hi` | 0.3 / 0.8 | avoids grazing-angle leaks |
| `near_radius_px` | 80 | half-tuned |
| `default_pulse_speed_px_per_sec` | 600 | |
| `lifetime_sec` | 1.2 | |
| `fade_tau_sec` | 0.35 | |
| `edge_boost` | 1.5 | |
| `edge_width_px` | 12 | bright ring |
| `ring_width_px` | 4 | shock ring visual |
| `bayer_tile_px` | 4 | stipple density |

These live in `src/echolocation/echolocation_renderer.tscn` as
`shader_parameter/...` defaults so the inspector picks them up.

## Deferred shader work (pick up after Phase 2)

Blocked on Phase 2 marching-squares density field landing because
those are easier and cleaner with an SDF than with luminance-
gradient approximations.

- [ ] **Procedural tile rendering**: swap the backbuffer-color reveal
  for a per-frequency tileable interior texture plus a rotated
  tileable surface texture (sampled with tangent-aligned UVs).
  Art pipeline decision: user authors ~2 textures per frequency,
  not ~30 unique tile sprites. The existing surface-prominence +
  facing math becomes the band-blend input between interior and
  surface textures.
- [x] **Density field as gradient source**: replaced the luminance
  Sobel with a 2-tap central difference on `density_tex`. Cleaner,
  no noise from pixel-art internal detail, sub-pixel accuracy.
- [ ] **True distance-from-surface (sub-pixel band)**: the density
  field gives a real SDF, but the current rendering still uses
  `grad_mag` as a band proxy rather than solving for iso-line
  distance. Exploit the density SDF for sub-pixel-accurate surface
  band widths.
- [ ] **Activate frequency palette gating**: populate the palette
  uniforms from Phase 3 tile art.
- [ ] **Bug medium-range visibility**: bugs emit their own "signal,"
  visible beyond the near-radius but closer than echo-only objects.
  Will need a second visibility band that tests against a "is this
  pixel a bug" flag (derived from palette or tag buffer).
- [ ] **Enemy perception feedback**: enemies that have perceived the
  player could glow faintly in their frequency color.
- [ ] **Directional pulse tuning**: cone mode (`echo_arc_radians < TAU`)
  works but hasn't been playtested. Decide: always circular, or
  player-toggled.
- [ ] **Pulse cooldown visual** on the player / HUD.

## Architectural contracts to preserve

These APIs/data shapes should remain stable so parallel tracks don't
collide with the shader rewrite:

- `G.echo: EcholocationRenderer` — autoload-style handle set in
  `_enter_tree`.
- `G.echo.emit_pulse(center, frequency, max_radius_px, damage,
  speed_px_per_sec, arc_radians, arc_direction_radians) -> EchoPulse`
  — construct and register a pulse.
- `G.echo.pulse_emitted(EchoPulse)` / `pulse_completed(EchoPulse)`
  signals.
- `EchoPulse` fields: `center`, `frequency`, `speed_px_per_sec`,
  `lifetime_sec`, `age_sec`, `max_radius_px`, `damage`,
  `arc_radians`, `arc_direction_radians`.
- Shader uniform names: `player_uv`, `screen_size_px`, `pulses[]`
  (vec4 center_uv.xy, age, speed_px), `pulse_colors[]`,
  `pulse_cones[]` (vec4 arc, direction, unused, unused),
  `pulse_count`, `current_frequency`, `palette[]`, `palette_freqs[]`,
  `palette_count`.
- Pulse pool size: `MAX_PULSES = 8` (WebGL2-safe uniform array size).

If Phase 2+ code needs a different uniform shape, add new uniforms
alongside rather than renaming. The renderer GDScript is the
integration point; change one file, not callers.

---

## Project quirks discovered

### Double-level instantiation (fixed, but fragile flow)

`settings.start_in_game = true` + `Level.reset() → transition(TITLE)
→ GamePanel.end_game() → is_game_ended = true` cascade causes
`StateMain.transition(GAME)` to call `game_panel.on_return_from_screen()`
after the initial `start_game()`, which re-triggers a second level
because `is_game_ended` was flipped back to true mid-flow.

Fixed by guarding `GamePanel.start_level()` with
`if is_instance_valid(level): return`. The underlying state-machine
logic is still load-bearing weird — anyone touching `StateMain.transition()`,
`Level.reset()`, or `GamePanel.on_return_from_screen()` should trace
the call graph before changing behavior.

### Window/viewport stretch mismatch

`project.godot` sets `window/stretch/mode = "canvas_items"` with the
default viewport 1152×648. On a typical 4K monitor the actual window
ends up ~2880×1548 (2.5× scale). Godot's canvas_items stretch is
non-uniform when the window aspect doesn't match.

Consequence for shaders: **FRAGCOORD reads in window pixels, not
canvas pixels**, while `get_canvas_transform() * world_pos` reads in
canvas pixels. Mixing them produces an offset. The composite shader
works in **UV space (0..1) with explicit `screen_size_px` uniform**
so it's independent of which space FRAGCOORD happens to use.

Carry this pattern forward to all future screen-space shaders.

### `return` in fragment shaders triggers compile errors on AMD

AMD Radeon drivers (user's setup: RX 6800 XT, Godot 4.6.2) reject
early `return` inside `void fragment()`. Use else-branches or write
to `COLOR` then fall through instead. Reproduced and worked around
in the composite shader's debug mode.

### Camera2D anchor default changed in 4.5+

Godot 4.5+ default `Camera2D.anchor_mode` is `FIXED_TOP_LEFT`, not
`DRAG_CENTER`. Camera-follow logic that sets
`camera.global_position = player.global_position + offset` places
the player at screen top-left under FIXED_TOP_LEFT.

Set `ANCHOR_MODE_DRAG_CENTER` explicitly in `level.gd:_ready()` (done).
If a new level scene is authored, verify its Camera2D does this too.

### hint_screen_texture auto-backbuffer-copy

In Godot 4, declaring `uniform sampler2D ... : hint_screen_texture,
...;` triggers an automatic backbuffer copy per material, no manual
`BackBufferCopy` node needed. Verified working on Windows + AMD +
Godot 4.6.2 + WebGL2 target configuration (in theory; web not yet
smoke-tested).

### Godot 4.6 + godot-cpp 4.5-stable forward-compat

`godot-cpp` has not yet cut a `godot-4.6-stable` tag upstream (as of
Apr 2026). Extension built against `godot-cpp 4.5-stable` loads and
runs cleanly in Godot 4.6.2 editor. `compatibility_minimum = "4.6"`
is declared in the `.gdextension` manifest. When upstream publishes
the 4.6 tag, bump the submodule pin and rebuild.

### Scene file size

`default_level.tscn` is huge (a giant `PackedByteArray` of TileMap
tile data, ~500 KB) and Godot's `Edit` / `Read` tooling refuses to
open it for safety. Workaround: do changes via scripts (e.g.
`level.gd:_ready` setting `Camera2D.anchor_mode`) rather than
editing the scene file directly. Phase 2 replaces the TileMap with
a `TerrainLevelLoader` bake, at which point the tile data no longer
lives in the scene file.

### Emscripten version pinning for web

Web export template must be built with Emscripten 4.0.0+. The tested
version from Godot 4.6 CI is 4.0.11. Avoid 4.0.3 through 4.0.6
(GDExtension regression, Godot issue #105717). Documented in
`kbterrain/web-template-setup.md`.

### MSVC build byproducts

The Windows build drops `.exp`, `.lib`, `.pdb` files alongside the
committed `.dll` in `addons/kbterrain/bin/`. `.gitignore` filters
them out. If a new platform build lands, extend the filter.

### Godot hot-reload for shader structural changes

Shader uniform additions and changes to `hint_*` types sometimes
don't hot-reload cleanly. If a shader edit seems to have no visible
effect: stop the running game, right-click the `.gdshader` file in
FileSystem → Reimport, then re-run. In the worst case, restart the
Godot editor.

### `@tool` TerrainWorld in editor

Phase 2 originally bailed on `is_editor_hint()` to avoid the C++
worker thread fighting with editor scene-save and reimports. Phase
2.5 added a synchronous mesh path so `TerrainLevel` can be `@tool`
and live-render the marching-squares preview while the designer
edits a TileMapLayer.

Rules:

- The C++ worker thread is **not** started in editor mode
  (`_ensure_initialized` checks `_editor_mode`). Re-mesh runs
  synchronously on the calling thread via `process_remesh_job` +
  `_integrate_one`.
- Physics RIDs are **not** created in editor mode (would interfere
  with editor-mode tools and aren't useful for visual preview). They
  are created on first remesh at runtime.
- `clear_all()` wipes every chunk + frees RIDs. Used by the editor
  preview before each re-bake to avoid stale chunks lingering when
  tiles are erased.
- A child class extending `TerrainWorld` should override `_ready`
  / `_input` / `_physics_process` carefully if it's `@tool` —
  early-return on `Engine.is_editor_hint()` for any handler that
  references runtime-only autoload state (G.echo, G.terrain, etc).
  See `src/level/terrain_level.gd` for the pattern.

This is the only `@tool` exception in the codebase. Other systems
(echolocation, bugs, enemies) stay runtime-only.
