@tool
class_name EnemySpawnPoint
extends Node2D
## Single-shot enemy spawn. Spawns one `enemy_scene` at this node's
## world position on _ready. Use RespawningEnemySpawnPoint for
## continuous/capped respawns.
##
## In the editor, draws a crosshair marker tinted by
## `frequency_override` (neutral gray if NONE) and labels the spawn
## with the enemy scene's filename.


## Radii and widths for the in-editor marker.
const _EDITOR_MARKER_RADIUS := 9.0
const _EDITOR_CROSS_HALF_LENGTH := 7.0
const _EDITOR_FILL_ALPHA := 0.25
const _EDITOR_OUTLINE_WIDTH := 2.0
const _EDITOR_ARC_SEGMENTS := 32
const _EDITOR_LABEL_MARGIN_PX := 4.0
const _EDITOR_NO_FREQ_COLOR := Color(0.85, 0.85, 0.85, 1.0)


## Scene instantiated on spawn. Typically one of
## `monster_bird.tscn`, `spider.tscn`, `flying_critter.tscn`.
@export var enemy_scene: PackedScene:
	set(value):
		enemy_scene = value
		queue_redraw()

## Optional override for the spawned enemy's frequency. If left as
## `Frequency.Type.NONE` the scene's baked-in frequency is kept.
@export var frequency_override: int = Frequency.Type.NONE:
	set(value):
		frequency_override = value
		queue_redraw()


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	spawn_one()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var color := _editor_color()
	var fill := Color(color.r, color.g, color.b, _EDITOR_FILL_ALPHA)
	draw_circle(Vector2.ZERO, _EDITOR_MARKER_RADIUS, fill)
	draw_arc(
			Vector2.ZERO,
			_EDITOR_MARKER_RADIUS,
			0.0,
			TAU,
			_EDITOR_ARC_SEGMENTS,
			color,
			_EDITOR_OUTLINE_WIDTH)
	var h := _EDITOR_CROSS_HALF_LENGTH
	draw_line(
			Vector2(-h, 0), Vector2(h, 0), color, _EDITOR_OUTLINE_WIDTH)
	draw_line(
			Vector2(0, -h), Vector2(0, h), color, _EDITOR_OUTLINE_WIDTH)
	_draw_label(color)


## Instantiate `enemy_scene`, position it at this node, and parent
## it here so level reset tears it down with the spawn point.
## Returns the new Enemy or null on failure.
func spawn_one() -> Enemy:
	if not G.ensure_valid(
			enemy_scene,
			"EnemySpawnPoint.enemy_scene is unset"):
		return null

	var enemy: Enemy = enemy_scene.instantiate()
	if frequency_override != Frequency.Type.NONE:
		enemy.frequency = frequency_override
	add_child(enemy)
	enemy.global_position = global_position
	return enemy


func _editor_color() -> Color:
	if frequency_override == Frequency.Type.NONE:
		return _EDITOR_NO_FREQ_COLOR
	return Frequency.color_of(frequency_override)


func _draw_label(color: Color) -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var font_size := ThemeDB.fallback_font_size
	var label := _editor_label_text()
	var label_size := font.get_string_size(
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var label_position := Vector2(
			-label_size.x * 0.5,
			-_EDITOR_MARKER_RADIUS - _EDITOR_LABEL_MARGIN_PX)
	draw_string(
			font,
			label_position,
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			color)


## Overridden by subclasses to add extra info to the editor label.
func _editor_label_text() -> String:
	if enemy_scene == null or enemy_scene.resource_path.is_empty():
		return "enemy?"
	return enemy_scene.resource_path.get_file().get_basename()
