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
**Status**: build script (`kbterrain/build_web.ps1`) + custom
Emscripten-template setup documented in
`kbterrain/web-template-setup.md`; not actually exported.
**Constraints**: pin Emscripten 4.0.11 (skip 4.0.3–4.0.6 due to
GDExtension regression). Custom-host with COOP/COEP headers.

---

## 2. Pending Design Decisions

### 2.1 Tile custom data layers (`type`, `initial_health`) — **DONE**
Schema authored on `default_tile_set.tres`; loader reads per-tile
`type` + `initial_health`; WEB_* tiles route to Area2D spawns.
Health falls back to 255 when `initial_health` is unset (0 treated
as unset, since Godot returns default 0 for never-written int
custom data).

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
**Status**: `_detach_islands_from_seeds` is **disabled inside
`damage_with_falloff`** because the test rect has no INDESTRUCTIBLE
border to anchor the flood, so the entire region was being detached
as one giant unanchored island. The user has since added a
`test_rect_border_cells` (default 2) authoring path that bakes an
INDESTRUCTIBLE perimeter. **Re-enable the CC pass** (or move the
disable behind a flag) once levels reliably ship with anchor cells.

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

### 5.1 Damage CC disabled
See 2.5 — re-enable after INDESTRUCTIBLE-border becomes the level-
authoring norm.

### 5.2 Editor-mode synchronous mesh path
`TerrainWorld._editor_mode` runs marching squares synchronously in
`_queue_remesh`. Necessary for `@tool` preview — keep.

### 5.3 Test coverage gaps
Many GUT integration tests listed in `PLAN.md` are stubs. Ship-
defer until post-jam.

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

---

*Last updated: April 18, 2026. Generated from session-history audit
plus current-session knowledge.*
