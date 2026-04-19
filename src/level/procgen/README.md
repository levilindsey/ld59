# Procedural level generator

Generates a playable terrain-level scene + targeted adjustments, with
a validator pass after every edit.

## Quick start

```powershell
# Generate a level (random seed).
powershell -ExecutionPolicy Bypass -File scripts/generate_level.ps1

# Generate a specific seed with tuned parameters.
powershell -ExecutionPolicy Bypass -File scripts/generate_level.ps1 `
    -Seed 42 -Width 80 -Height 48 -Budget 10 -Platforms 12

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

1. `ProcgenLayoutPlanner` writes an arena (INDESTRUCTIBLE border,
   thick primary floor, N floating platforms of assorted
   frequencies). Picks spawn (left) + destination (right) standable
   tiles.
2. `ProcgenSetPieceLibrary` stamps a budget of set-pieces:
   - `pool_sand_trap` — liquid basin + thin SAND shell + rim.
   - `web_tunnel` — horizontal corridor with WEB tiles and a paired
     Spider spawner hint placed outside the tunnel.
   - `enemy_pocket` — alcove + one enemy spawner (Spider / Coyote on
     ground, Bird / Critter in air).
   - `bug_region` — no terrain change; a tagged `BugSpawnRegion`.
3. One bug region per gameplay frequency is always emitted so the
   player can't get stuck on a frequency with no matching bugs.
4. A `Destination` node is placed at the chosen goal tile.
5. `ProcgenValidator` runs the lint list; errors → regen with a
   different seed. Warnings ship.
6. `ProcgenTileMapWriter` writes cells to the `Tiles` TileMapLayer
   and spawns the hint nodes as children of the level root.
7. `PackedScene.pack` + `ResourceSaver.save` writes the output.

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

## Known limitations (v1 → v2 backlog)

- **Arena layout only.** Room-graph macro (Spelunky / Dead Cells
  style) is planned for v2.
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
