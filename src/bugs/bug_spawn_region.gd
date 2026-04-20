@tool
class_name BugSpawnRegion
extends Node2D
## Authored region placed in level scenes. Contributes `rate_delta`
## bugs-per-second of `frequency` to the BugSpawner's spawn rate
## whenever the player is inside the region's rectangular extent.
##
## The region implies its own area (see `size`). No CollisionShape2D
## or physics overlap is used. Multiple regions stack additively per
## frequency. Negative rate_delta is allowed so designers can author
## dead-zones; the total stacked rate is clamped at the spawner.


## Group that every runtime BugSpawnRegion joins. The BugSpawner
## iterates this group each tick to aggregate spawn rates.
const GROUP := "bug_spawn_regions"

## Editor-only annotation styling.
const _EDITOR_FILL_ALPHA := 0.18
const _EDITOR_OUTLINE_ALPHA := 0.75
const _EDITOR_OUTLINE_WIDTH := 2.0
const _EDITOR_LABEL_FONT_SIZE := 12
const _EDITOR_LABEL_OFFSET := Vector2(4, 14)


@export var frequency: Frequency.Type = Frequency.Type.GREEN:
	set(value):
		frequency = value
		queue_redraw()

## Bugs per second contributed for this frequency while the player
## is inside the region. Can be negative to suppress spawns.
@export var rate_delta: float = 1.0:
	set(value):
		rate_delta = value
		queue_redraw()

## Rectangular extent of the region in pixels, centered on this
## node's position. Used for both the point-in-rect test and the
## in-editor debug annotation.
@export var size: Vector2 = Vector2(320, 256):
	set(value):
		size = value
		queue_redraw()


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group(GROUP)


## True iff `world_pos` lies inside the region's rect.
func contains_point(world_pos: Vector2) -> bool:
	var local := world_pos - global_position
	var half := size * 0.5
	return (
			local.x >= -half.x
			and local.x <= half.x
			and local.y >= -half.y
			and local.y <= half.y)


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var color := Frequency.color_of(frequency)
	var fill := Color(color.r, color.g, color.b, _EDITOR_FILL_ALPHA)
	var outline := Color(color.r, color.g, color.b, _EDITOR_OUTLINE_ALPHA)
	var rect := Rect2(-size * 0.5, size)
	draw_rect(rect, fill, true)
	draw_rect(rect, outline, false, _EDITOR_OUTLINE_WIDTH)
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var label := "f=%d rate=%+0.2f" % [frequency, rate_delta]
	draw_string(
			font,
			rect.position + _EDITOR_LABEL_OFFSET,
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			_EDITOR_LABEL_FONT_SIZE,
			outline)
