# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

LD59 is a single-player 2D game built with Godot 4.6 (specifically
4.6.2-stable) for the Ludum Dare 59 game jam. The repo shares the
`scaffolder/` character/movement framework with other Godot projects
in this workspace, but this project has no networking, backend, or
cross-play concerns.

## Claude Code Settings

Do NOT use the local memory system (`~/.claude/projects/*/memory/`).
This project is worked on across multiple machines. All persistent
context belongs in this file so it stays in sync via git.

## Implementation plan

`PLAN.md` at the repo root is the **authoritative, living checklist**
for the project. It breaks the work into phases and parallelizable
tracks with checkbox tasks. Read it at the start of any non-trivial
session and mark items complete as they land on `main`.

**Parallel sessions**: multiple Claude sessions (or human + Claude)
may run concurrently on different tracks. Conventions:

- Each track works on a branch named `track/<slug>` matching the
  Parallelization tracks table in `PLAN.md`.
- Before editing any file in the "Shared files" table of `PLAN.md`,
  check that no other active branch has touched it first. Rebase onto
  `main` before merging.
- Commit `PLAN.md` checkbox updates alongside the work that satisfies
  them — the checklist is the system of record.

If you start a session without clear instructions, consult `PLAN.md`
and pick an unclaimed track whose dependencies are satisfied.

## Project Structure

- `src/core/` — Autoload (`global.gd` → `G`), entry scene
  (`main`), `game_panel`, `audio_main`, `state_main`,
  `session`, `settings`, `outline.gdshader`, `main_theme.tres`.
- `src/scaffolder/` — Reusable framework: `character/`,
  `time/`, `geometry.gd`, `draw_utils.gd`, `utils.gd`,
  `scaffolder.gd`, `scaffolder_log.gd`.
- `src/player/` — `player.gd`, `player.tscn`,
  `player_animator.tscn`, `player_movement_settings.tres`.
- `src/level/` — `level.gd`, `default_level.tscn`,
  `background.tscn`, `default_tile_set.tres`.
- `src/ui/hud/` — In-game HUD.
- `src/ui/super_hud/` — Top-level HUD host with `debug_console`.
- `assets/` — `audio/`, `fonts/`, `images/` (including
  `images/gui/` for buttons/logos), `shaders/`.
- `build/` — Export outputs (`web/`, `windows/`).

## Character System (src/scaffolder/character/)

Reusable character framework shared with other Godot projects
in this workspace:

- **Character** (`character.gd`) — Extends `CharacterBody2D`;
  manages velocity, collision, action state, surface contact.
- **CharacterAnimator** (`character_animator.gd`) — Drives
  sprite/animation state from character state.
- **CharacterSurfaceState** (`character_surface_state.gd`) —
  Tracks platform contact via raycasts.
- **MovementSettings** (`movement_settings.gd`) — Tunable
  movement parameters, typically stored as `.tres`.
- `action/` subsystem:
  - `character_action_state.gd` — Per-frame state machine.
  - `character_action_handler.gd` — Base class for handlers.
  - `character_action_type.gd` — Enum of action kinds.
  - `character_action_source.gd` — Base class for input
    sources (player, scripted instructions, playback).
  - `player_action_source.gd`,
    `instructions_action_source.gd`,
    `instructions_playback.gd` — Concrete sources.
  - `action_handlers/` — One handler per movement state
    (floor/wall/ceiling/air variants).

### Adding Character Actions

1. Create handler in
   `src/scaffolder/character/action/action_handlers/`.
2. Follow the existing handler pattern: modify velocity
   based on surface state and input.
3. Register in `character_action_state.gd`.

## Configuration

- `settings.tres` — Runtime settings resource.
- `default_bus_layout.tres` — Audio bus layout.
- `project.godot` — Input actions, physics layers, rendering
  config.
- Renderer: `gl_compatibility` (desktop + mobile).
- Stretch mode: `canvas_items`.

### Input Actions

Defined in `project.godot`:
`move_up`, `move_down`, `move_left`, `move_right`, `jump`,
`ability`, `attach`, `face_left`, `face_right`. All have both
keyboard and gamepad bindings (except `attach`, `face_left`,
and `face_right`, which are currently unbound and reserved
for future mappings).

### Physics Layers

1. `normal_surfaces`
2. `fall_through_floors`
3. `walk_through_walls`
4. `player`
5. `enemy`
6. `player_projectile`
7. `enemy_projectile`
8. `hack_for_edge_detection`

## Code Style

Follow the
[Godot GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html)
with the project-specific additions below.

### Formatting

- **Indentation:** Tabs (4-space width), enforced by
  `.editorconfig`.
- **Line length:** 80 characters maximum.
- **Blank lines:** Two blank lines between functions/methods.
- **Line wrapping:** Prefer parentheses over backslashes for
  line continuation. Conversely, unwrap lines onto a single
  line when they fit within the 80-character limit.
- **Operator placement:** When wrapping expressions across
  multiple lines, place operators at the start of the next
  line, not the end of the previous line.
- **Trailing commas:** Include trailing commas in multi-line
  function calls, arrays, and dictionaries.

```gdscript
# Correct: parens for wrapping, operator at start of line.
var is_valid := (
	is_instance_valid(node)
	and node.is_inside_tree()
	and not node.is_queued_for_deletion()
)

# Correct: trailing comma in multi-line call.
some_function(
	first_arg,
	second_arg,
)

# Wrong: backslash continuation.
var is_valid := is_instance_valid(node) \
	and node.is_inside_tree()

# Wrong: operator at end of line.
var is_valid := (
	is_instance_valid(node) and
	node.is_inside_tree()
)
```

### Naming Conventions

- **Classes/enums:** `PascalCase`
- **Functions/variables:** `snake_case`
- **Constants:** `UPPER_SNAKE_CASE`
- **Private members:** Prefix with underscore (`_my_var`,
  `_my_method`)
- **Signals:** Past tense (`player_died`, `match_started`)
- **Booleans:** Prefix with `is_`, `can_`, `has_`
- **No prefixes:** Avoid prefixes in variable names (e.g., use
  `speed` not `player_speed` when already inside a player
  class). The underscore prefix for private members is the
  exception.
- **No abbreviations:** Use full words in identifiers (e.g.,
  `diagnostic` not `diag`, `configuration` not `config`,
  `information` not `info`). Standard domain abbreviations
  (`fps`, `rpc`, `usec`, `id`) are acceptable.

### Type Annotations

- Use `:=` for inferred types on variable declarations.
- Always specify return types on functions.
- Use explicit type hints for `@export` vars and function
  parameters.

```gdscript
var speed := 10.0
const _MAX_SPEED := 200.0
@export var jump_height: float = 64.0

func get_speed() -> float:
	return speed
```

### Negation

- Prefer `not` over `!` for boolean negation.
- Do use `!=` for inequality comparisons.

```gdscript
# Correct.
if not is_alive:
	return
if count != 0:
	process()

# Wrong.
if !is_alive:
	return
```

### Comments and Prose

- End all comments with a period.
- Use `##` for doc comments (Godot documentation comments),
  `#` for regular comments.
- Never use em dashes, en dashes, or hyphens as grammatical
  em dashes. Use a period and start a new sentence instead.
- Wrap comments at 80 characters, matching the code line
  limit.

```gdscript
## Advances the entity by the given number of frames.
## Each frame applies a fixed movement step.
func _simulate_frames(count: int) -> void:

# Wrong: em dash in comment.
# The entity moves forward — unless blocked.

# Correct: period and new sentence.
# The entity moves forward. It stops when blocked.
```

### File Structure

Follow the Godot-recommended ordering within each script:

1. `@tool`
2. `class_name`
3. `extends`
4. Doc comment (`##`)
5. `signal` declarations
6. `enum` declarations
7. `const` declarations
8. `@export` variables
9. Public variables
10. Private variables (`_`-prefixed)
11. `@onready` variables
12. `_init()`, `_enter_tree()`, `_exit_tree()`, `_ready()`
13. `_process()`, `_physics_process()`
14. Other virtual/callback methods
15. Public methods
16. Private methods

### Constants Over Inline Values

Use file-level `const` declarations instead of hard-coding
static values inline in functions. Private constants use
underscore prefix.

```gdscript
# Correct: file-level constant.
const _RESPAWN_DELAY_FRAMES := 30

func _respawn() -> void:
	timer = _RESPAWN_DELAY_FRAMES

# Wrong: magic number inline.
func _respawn() -> void:
	timer = 30
```

### Scene Templates Over Scripts

Prefer configuring state in `.tscn` scene files rather than
in scripts:

- **Animations:** Configure `AnimatedSprite2D.sprite_frames`
  animations in the scene editor, not in code.
- **Resource references:** Use `@export` vars and assign
  resources in the scene inspector. NEVER use `preload()` or
  `load()` for resource references in scripts.
- **Node references:** Use `%NodeName` unique-name syntax in
  scenes when referencing sibling/child nodes.

**Editing `.tscn` files directly (without the Godot editor):**
Scene files can be edited as text. The key fields are:
- `load_steps=N` in the header — increment N for each new
  `[ext_resource]` entry added.
- `[ext_resource type="PackedScene" path="res://..." id="X"]`
  — declares a scene dependency. Use a unique `id` string.
  `uid=` is optional; omit it if the scene has no UID yet.
- `[node name="Foo" parent="." instance=ExtResource("X")]`
  — instantiates the scene as a child node.
- Export vars on an instanced node are set directly on the
  node entry, e.g. `doc_type = 0`. Enum values are integers
  (0, 1, 2…) matching declaration order.

```gdscript
# Correct: export var assigned in scene inspector.
@export var death_effect: PackedScene

# Wrong: preload in script.
const _DEATH_EFFECT := preload(
	"res://src/effects/death_effect.tscn"
)
```

### Direct Access Over Local Copies

Do not assign local or class-level variable copies of
autoload properties (`G`) or unique-name nodes (`%`). Access
them directly where needed.

```gdscript
# Correct: access autoload properties directly.
if G.session.is_active:
	G.settings.save()

# Wrong: local copy of autoload property.
var session := G.session
if session.is_active:
	pass

# Correct: access unique-name node directly.
%AnimatedSprite2D.play("idle")

# Wrong: local or class-level copy.
@onready var sprite := %AnimatedSprite2D
```

### Performance

- Prefer `distance_squared_to()` over `distance_to()` when
  feasible, to avoid unnecessary `sqrt` calculations.

### GDScript Formatter

If the GDScript formatter addon is installed, format code
before committing.

## UI

Interactive UI should be navigable with gamepad and keyboard
(U/D, L/R), not only mouse/touch. Shared button art lives in
`assets/images/gui/` (`button_normal`, `button_hover`,
`button_pressed`). `src/ui/super_hud/` hosts the
`debug_console` overlay on top of the in-game HUD
(`src/ui/hud/`).

## Commit Policy

- Do not commit partial or broken work. All changes for a
  feature must be working end-to-end before committing.
- Never ask the user whether to commit. They will tell you
  when they want to commit.

## CLI Tool Availability

`godot` and other Godot tooling are only in the PowerShell
PATH, not the bash PATH. **Never run `godot` directly from
bash.** Always use `powershell -ExecutionPolicy Bypass -File
<script>` or `powershell -Command "<command>"` when invoking
it.

## Testing with GUT

No tests exist yet. If adding them, use GUT (Godot Unit Test)
9.x. Place tests under `res://test/` (e.g., `test/unit/`,
`test/integration/`).

### Test File Structure

- Files must start with `test_` prefix (e.g.,
  `test_geometry.gd`).
- Extend `GutTest` base class.
- Use `func test_*()` naming for test methods.
- Configuration in `res://.gutconfig.json`.

### Common Assertions

```gdscript
# Equality.
assert_eq(actual, expected, "optional message")
assert_ne(actual, expected)

# Null checks.
assert_null(value)
assert_not_null(value)

# Boolean.
assert_true(condition, "message")
assert_false(condition)

# Numeric comparisons.
assert_gt(value, threshold)
assert_lt(value, threshold)
assert_almost_eq(actual, expected, tolerance)

# Godot types.
assert_almost_eq(vector1, vector2, tolerance)
assert_has(array_or_dict, value)
assert_does_not_have(array_or_dict, value)

# Signals.
watch_signals(object)
assert_signal_emitted(object, "signal_name")
assert_signal_not_emitted(object, "signal_name")
```

### Test Lifecycle Methods

```gdscript
extends GutTest

func before_all(): pass    # Once before all tests.
func before_each(): pass   # Before each test.
func after_each(): pass    # After each test.
func after_all(): pass     # Once after all tests.
```

### Test Doubles (Mocking)

```gdscript
# Double a script.
var MyClass = preload("res://src/my_class.gd")
var DoubledClass = double(MyClass)
var instance = DoubledClass.new()

# Stub return values.
stub(instance, 'method_name').to_return(42)
stub(instance, 'method_name').to_call_super()

# Spies.
assert_called(instance, 'method_name')
assert_call_count(instance, 'method_name', 3)
assert_called_with(instance, 'method_name', [arg1, arg2])
```

- Inner classes need `register_inner_classes(ClassName)`
  before doubling.
- Don't create doubles in `before_all()`. Use `before_each()`.
- Use `partial_double()` to keep some original functionality.

### Parameterized Tests

```gdscript
var test_cases = ParameterFactory.named_parameters(
	['input', 'expected'],
	[
		[0, 0],
		[5, 25],
	]
)

func test_square(p=use_parameters(test_cases)):
	assert_eq(square(p.input), p.expected)
```

### Running Tests

```bash
# Specific test (most reliable).
powershell -Command "godot --headless -s --path . addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_foo.gd -gexit"

# All unit tests.
powershell -Command "godot --headless -s --path . addons/gut/gut_cmdln.gd -gdir=res://test/unit -gexit"
```

Always use `-gexit` to get proper exit codes. Directory-based
runs sometimes fail to discover tests. Prefer specific file
runs.

### Best Practices

1. **One concept per test.**
2. **Descriptive names** —
   `test_character_lands_on_floor_resets_air_jump` not
   `test_jump`.
3. **AAA pattern** — Arrange, Act, Assert.
4. **Use fixtures** in `before_each`.
5. **Mock external dependencies.**
6. **Test edge cases** — empty, null, boundary values.
7. **Keep tests fast.**
8. **Deterministic tests** — no randomness, no timing
   dependencies in unit tests.
9. **Clean up** — use `add_child_autofree()` for nodes.

## Engine version

Target: **Godot 4.6.2-stable**. The `godot-cpp` submodule is pinned
at tag `godot-4.5-stable` because godot-cpp has not yet cut a
`godot-4.6-stable` tag (as of Apr 2026). The extension built against
godot-cpp 4.5 is forward-compatible with Godot 4.6.2 editor via the
`compatibility_minimum = "4.6"` declaration in the `.gdextension`
manifest. When the upstream `godot-4.6-stable` tag is published, bump
the submodule pin and rebuild.

## GDExtension (C++)

Computation-intensive logic lives in a native GDExtension. The
extension name is `ld59extension`. Classes defined in C++ are
registered with Godot's `ClassDB` and callable from GDScript like
any other Godot class.

### Layout

- `ld59extension/` — C++ source tree. Contains `SConstruct`,
  `src/`, build scripts, and git submodules (`godot-cpp`,
  `googletest`). A top-level `.gdignore` prevents the Godot editor
  from scanning this tree.
- `addons/ld59extension/ld59extension.gdextension` — manifest that
  declares the extension to Godot.
- `addons/ld59extension/bin/` — compiled `.dll`/`.wasm` binaries,
  **committed to the repo**.

### Submodules

```bash
git submodule update --init --recursive
```

Pinned versions: `godot-cpp` at tag `godot-4.5-stable`,
`googletest` at tag `v1.15.2`.

### Building locally

Target platforms: Windows + Web. Binaries are committed; rebuild
and commit when changing C++ code.

```powershell
# Windows (debug + release).
powershell -ExecutionPolicy Bypass -File ld59extension\build_windows.ps1

# Web (requires Emscripten SDK activated in the shell).
powershell -ExecutionPolicy Bypass -File ld59extension\build_web.ps1
```

Or invoke SCons directly from `ld59extension/`:

```powershell
scons platform=windows target=template_debug install
scons platform=web target=template_release install
```

CI **does not** build the extension. Contributors must rebuild and
commit the binaries themselves.

### C++ unit tests

GoogleTest is embedded into the extension when built with
`tests=yes`. Test files are colocated with source as
`src/test_*.h`, gated by the `LD59EXTENSION_TESTS_ENABLED`
preprocessor define. The test runner is invoked from
`register_types.cpp` during module initialisation and prints a
sentinel line (`ld59extension test result: ALL TESTS PASSED!`)
that `build_tests.ps1` greps for.

```powershell
powershell -ExecutionPolicy Bypass -File ld59extension\build_tests.ps1
```

To add a test:

1. Create `ld59extension/src/test_<thing>.h` with
   `#ifdef LD59EXTENSION_TESTS_ENABLED` guards and `TEST(...)`
   cases (see `test_ld59extension_example.h`).
2. `#include "test_<thing>.h"` inside the
   `LD59EXTENSION_TESTS_ENABLED` block of `register_types.cpp`.

### Adding a new C++ class

1. Write `src/my_class.h` and `src/my_class.cpp` following
   `ld59extension_example.{h,cpp}` (`GDCLASS`, `_bind_methods`).
2. In `register_types.cpp`, `#include "my_class.h"` and call
   `ClassDB::register_class<MyClass>()` inside
   `initialize_ld59extension_module()`.
3. Rebuild.

### Web export caveat

GDExtensions on Web require the Godot web export template to be
built with `dlink_enabled=yes`. The default templates shipped with
Godot 4.5 may lack this. If web export fails on `dlink_load`,
either build a custom web template with
`scons platform=web dlink_enabled=yes` or use a dlink-enabled
template from a later Godot release.
