# Procedural level generator

Generates a playable terrain-level scene + targeted adjustments, with
a validator pass after every edit.

## Quick start

```powershell
# Generate a level (random seed).
powershell -ExecutionPolicy Bypass -File scripts/generate_level.ps1

# Generate a specific seed with tuned parameters.
powershell -ExecutionPolicy Bypass -File scripts/generate_level.ps1 `
    -Seed 42 -Width 80 -Height 48 -Chambers 6 -PlatformsPerChamber 2

# Validate an existing generated level.
powershell -ExecutionPolicy Bypass -File scripts/adjust_level.ps1 -Op validate

# Carve a rectangle.
powershell -ExecutionPolicy Bypass -File scripts/adjust_level.ps1 `
    -Op carve_rect -Rect "30,20,6,2"

# Paint a rectangle with a specific tile type.
powershell -ExecutionPolicy Bypass -File scripts/adjust_level.ps1 `
    -Op paint_rect -Rect "40,18,8,2" -Type GREEN

# Remove a generated child node by name.
powershell -ExecutionPolicy Bypass -File scripts/adjust_level.ps1 `
    -Op remove_entity -Name "BugSpawnRegion_(18, 29)"
```

Default output: `res://src/level/generated_level.tscn`. To play it,
edit `settings.tres`: set `default_level_scene` to the generated
file (change back when done).

## Pipeline

1. `ProcgenLayoutPlanner` plans a chamber sequence:
   - Divides the level into `chamber_count` equal-width chambers in
     a single row, wrapped in an INDESTRUCTIBLE border.
   - Assigns per-chamber themes: chamber 0 = `entry`, chamber N-1 =
     `exit`, interior chambers cycle through
     `config.interior_themes` (default `transit`, `combat`,
     `hazard`).
   - Carves INDESTRUCTIBLE inter-chamber walls with a 2-tile-tall
     doorway at floor level so the player walks between chambers.
   - Carves a noise-jittered floor in each chamber (all chambers
     share the same base Y so doorways line up).
   - Runs the theme handler for each chamber, which stamps its
     gameplay beat and emits entity hints:
     - `entry` / `exit` — plain floor + 1 decorative platform.
     - `transit` — `platforms_per_chamber` floating platforms + a
       bug region.
     - `combat` — 1 platform + an `enemy_pocket` set-piece (blob
       cavity with a Spider / Coyote / Bird / Critter spawner).
     - `hazard` — a `pool_sand_trap` (elliptical basin + SAND shell)
       OR a `web_tunnel` (rectangular corridor with WEB gates and a
       Spider spawner).
2. `ProcgenLevel` adds one bug region per gameplay frequency that
   wasn't already covered by a chamber — guarantees no
   frequency-lock.
3. Smoothing pass (`ProcgenShapes.smooth_once` × 2) rounds off
   jagged corners on colored + hazard types. INDESTRUCTIBLE and the
   perimeter are skipped so the anchor contract is preserved.
4. Spawn + destination tiles are guaranteed standable
   (`_ensure_standable`) in case smoothing shaved the stand cell.
5. `Destination` is placed by the `exit` theme.
6. `ProcgenValidator` runs; errors → regen with a derived seed.
7. `ProcgenTileMapWriter` writes cells to the `Tiles` TileMapLayer
   and spawns the hint nodes as children of the level root.
8. `PackedScene.pack` + `ResourceSaver.save` writes the output.

## Validator checks

Ordered by severity:

- `spawn_oob` / `spawn_blocked` / `spawn_no_floor` — spawn tile must
  be empty with a solid tile directly below.
- `goal_oob` / `goal_blocked` / `goal_no_floor` — destination tile,
  same constraint.
- `unreachable_goal` — BFS spawn → goal fails under hard
  reachability (all colored tiles treated as passable; only
  INDESTRUCTIBLE / LIQUID / SAND block).
- `border_gap` — the level perimeter must be unbroken
  INDESTRUCTIBLE (anchor guarantee for the connected-components
  detach pass).
- `sand_shell_too_thin` / `sand_shell_too_thick` — any SAND column
  under LIQUID must be 1–3 tiles.
- `liquid_unsupported` — LIQUID cells without a hard support below.
- `hint_oob` / `hint_in_solid` — entity hints placed inside walls.
- `web_far_from_spider` / `web_without_spider` — WEB tiles need a
  Spider spawner within 8 tiles.
- `anchor_deficit` — INDESTRUCTIBLE count too low for a full border.
- `density_low` / `density_high` — solid-cell ratio outside 0.2–0.7.

## Seeds + determinism

Same master seed + same code = same level. The generator splits the
master seed into named sub-streams (`layout`, `hazard`, `entity`) so
tuning one subsystem doesn't shift the output of another. Regen
failures bump the seed by a fixed delta so retries explore different
layouts deterministically.

Every run prints `attempts=N seed_used=<derived>` so you can
reproduce a specific layout by passing `-Seed <derived>` directly.

## Adjust ops (v1)

| op              | args                               | effect |
|-----------------|------------------------------------|--------|
| `validate`      | —                                  | re-runs the validator. |
| `carve_rect`    | `-Rect x,y,w,h`                    | clears tiles to NONE. |
| `paint_rect`    | `-Rect x,y,w,h -Type <name>`       | fills with a Frequency type. |
| `remove_entity` | `-Name "exact node name"`          | deletes a child by name. |

Type names: `RED`, `GREEN`, `BLUE`, `YELLOW`, `LIQUID`, `SAND`,
`INDESTRUCTIBLE`, `WEB_RED`, `WEB_GREEN`, `WEB_BLUE`, `WEB_YELLOW`.

Every adjust that mutates the scene re-runs the full validator;
errors cause the save to be refused.

## Known limitations (v2 → v3 backlog)

- **1D chamber sequence only.** Full 2D room-graph (Spelunky /
  Dead Cells / Isaac-style) with branching + vertical transitions
  is v3. Current layout is a left-to-right corridor of themed
  chambers.
- **Simplified reachability.** Uses a single-tile-jump BFS rather
  than a full jump-arc graph; may miss some unreachability cases
  where a platform requires a 2-tile precision jump.
- **No lock-and-key frequency gates yet** (soft reachability). The
  generator doesn't orchestrate a deliberate "pick up GREEN bug →
  unlock GREEN gate" traversal path.
- **Post-hoc validator can't verify spider-proximity** — it only
  sees the saved scene's nodes, not the hint objects. A warning is
  emitted if WEB tiles are present; re-generate or add a Spider
  spawner by hand.
- **Per-tile health not exercised.** TileSet custom_data_1 exists
  but no stamp currently overrides per-cell HP values.
