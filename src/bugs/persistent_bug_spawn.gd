@tool
class_name PersistentBugSpawn
extends Node2D
## Authored spawn point for a single persistent bug. At runtime a bug
## is instantiated once, parented under the BugSpawner (so the
## echolocation tag-halo pass picks it up), and leashed to this
## spawn's position via `wander_radius_px`. Persistent bugs never
## time out or fade out. They're still consumed on player contact.
##
## In the editor, draws a filled frequency-colored disk sized to the
## chosen size variant's collision radius plus a wander-radius ring.


## Collision radii mirror Bug._SMALL/BIG_COLLISION_RADIUS. Duplicated
## here (rather than referenced) because Bug's copies are private.
const _SMALL_COLLISION_RADIUS := 15.0
const _BIG_COLLISION_RADIUS := 28.0

const _EDITOR_CIRCLE_SEGMENTS := 48
const _EDITOR_FILL_ALPHA := 0.35
const _EDITOR_OUTLINE_WIDTH := 2.0
const _EDITOR_LEASH_WIDTH := 1.0
const _EDITOR_LEASH_COLOR := Color(1.0, 1.0, 1.0, 0.25)
const _EDITOR_LABEL_MARGIN_PX := 4.0


@export var frequency: Frequency.Type = Frequency.Type.GREEN:
	set(value):
		frequency = value
		queue_redraw()

@export var size_variant: Bug.SizeVariant = Bug.SizeVariant.SMALL:
	set(value):
		size_variant = value
		queue_redraw()

## How far the persistent bug can drift from this spawn before its
## drift is pointed back at the anchor. Kept small by default so
## persistent bugs stay within eyesight of the intended spot.
@export_range(0.0, 512.0) var wander_radius_px: float = 48.0:
	set(value):
		wander_radius_px = value
		queue_redraw()


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_spawn_persistent_bug()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var color := Frequency.color_of(frequency)
	var radius := _collision_radius_for_size()
	var fill_color := color
	fill_color.a = _EDITOR_FILL_ALPHA
	draw_circle(Vector2.ZERO, radius, fill_color)
	draw_arc(
			Vector2.ZERO,
			radius,
			0.0,
			TAU,
			_EDITOR_CIRCLE_SEGMENTS,
			color,
			_EDITOR_OUTLINE_WIDTH)
	if wander_radius_px > radius:
		draw_arc(
				Vector2.ZERO,
				wander_radius_px,
				0.0,
				TAU,
				_EDITOR_CIRCLE_SEGMENTS,
				_EDITOR_LEASH_COLOR,
				_EDITOR_LEASH_WIDTH)
	var font: Font = ThemeDB.fallback_font
	var font_size: int = ThemeDB.fallback_font_size
	var label := (
			"BIG" if size_variant == Bug.SizeVariant.BIG else "SMALL")
	var label_size := font.get_string_size(
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var label_position := Vector2(
			-label_size.x * 0.5,
			radius + label_size.y + _EDITOR_LABEL_MARGIN_PX)
	draw_string(
			font,
			label_position,
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			color)


func _spawn_persistent_bug() -> void:
	if not G.ensure_valid(
			G.bugs,
			"PersistentBugSpawn requires a BugSpawner in the scene"):
		return
	var spawner := G.bugs as BugSpawner
	if not G.ensure_valid(
			spawner.bug_scene,
			"BugSpawner.bug_scene is unset"):
		return
	var bug: Bug = spawner.bug_scene.instantiate()
	bug.frequency = frequency
	bug.size_variant = size_variant
	bug.is_persistent = true
	bug.anchor_position = global_position
	bug.leash_radius_px = wander_radius_px
	spawner.add_child(bug)
	bug.global_position = global_position


func _collision_radius_for_size() -> float:
	if size_variant == Bug.SizeVariant.BIG:
		return _BIG_COLLISION_RADIUS
	return _SMALL_COLLISION_RADIUS
