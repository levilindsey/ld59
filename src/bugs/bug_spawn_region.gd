@tool
class_name BugSpawnRegion
extends Area2D
## Authored region placed in level scenes. Contributes `rate_delta`
## bugs-per-second of `frequency` to the BugSpawner's spawn rate
## whenever the player (via BugRegionProbe) overlaps this region.
##
## Multiple regions stack additively per frequency. Negative
## rate_delta is allowed so designers can author dead-zones; the
## total stacked rate is clamped at the spawner.


## Physics layer bit (9) reserved for bug spawn regions. Set
## programmatically so level designers don't have to manage masks.
const _BUG_REGION_LAYER_BIT := 1 << 8

## Editor-only annotation styling.
const _EDITOR_FILL_ALPHA := 0.18
const _EDITOR_OUTLINE_ALPHA := 0.75
const _EDITOR_OUTLINE_WIDTH := 2.0
const _EDITOR_LABEL_FONT_SIZE := 12
const _EDITOR_LABEL_OFFSET := Vector2(4, 14)


@export var frequency: int = Frequency.Type.GREEN:
	set(value):
		frequency = value
		queue_redraw()
## Bugs per second contributed for this frequency while the probe
## overlaps the region. Can be negative to suppress spawns.
@export var rate_delta: float = 1.0:
	set(value):
		rate_delta = value
		queue_redraw()


func _ready() -> void:
	monitoring = false
	monitorable = true
	collision_layer = _BUG_REGION_LAYER_BIT
	collision_mask = 0
	if Engine.is_editor_hint():
		# Refresh annotation when a CollisionShape2D is added, removed,
		# or resized.
		child_order_changed.connect(queue_redraw)


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var color := Frequency.color_of(frequency)
	var fill := Color(color.r, color.g, color.b, _EDITOR_FILL_ALPHA)
	var outline := Color(color.r, color.g, color.b, _EDITOR_OUTLINE_ALPHA)
	var drew_any := false
	for child in get_children():
		if child is CollisionShape2D:
			var cs := child as CollisionShape2D
			if cs.shape is RectangleShape2D:
				var size := (cs.shape as RectangleShape2D).size
				var rect := Rect2(cs.position - size * 0.5, size)
				draw_rect(rect, fill, true)
				draw_rect(rect, outline, false, _EDITOR_OUTLINE_WIDTH)
				if not drew_any:
					_draw_label(rect.position, outline)
					drew_any = true


func _draw_label(anchor: Vector2, color: Color) -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var label := "f=%d rate=%+0.2f" % [frequency, rate_delta]
	draw_string(
			font,
			anchor + _EDITOR_LABEL_OFFSET,
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			_EDITOR_LABEL_FONT_SIZE,
			color)
