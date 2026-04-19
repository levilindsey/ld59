@tool
class_name Destination
extends Area2D
## Win-condition object placed by the level generator (or by hand).
## When the player's body enters this area, the level transitions to
## its "won" state via `G.level.win()`. Frequency-tinted sprite so
## players visually recognize it as a terminal goal rather than a
## pickup or prop.
##
## In the editor, draws a frequency-colored ring labeled "GOAL" so
## level designers can distinguish destinations at a glance even
## though the runtime sprite tint is not applied in editor.


const _EDITOR_RING_RADIUS := 22.0
const _EDITOR_RING_WIDTH := 2.5
const _EDITOR_ARC_SEGMENTS := 48
const _EDITOR_LABEL := "GOAL"
const _EDITOR_LABEL_MARGIN_PX := 4.0

## Delay between the "BigMeow" spatial hit on arrival and the global
## "success" cadence. Matches the failure cadence offset on death so
## win/loss share the same musical rhythm.
const _SUCCESS_CADENCE_DELAY_SEC := 0.9


## Frequency tint; cosmetic only (does not gate the win).
@export var frequency: Frequency.Type = Frequency.Type.YELLOW:
	set(value):
		frequency = value
		queue_redraw()
		if not Engine.is_editor_hint() and is_inside_tree():
			_apply_frequency_tint()


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	monitoring = true
	monitorable = false
	# Player is on layer 4 (bit 3); mask matches only the player.
	collision_layer = 0
	collision_mask = 1 << 3
	body_entered.connect(_on_body_entered)
	_apply_frequency_tint()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var color := Frequency.color_of(frequency)
	draw_arc(
			Vector2.ZERO,
			_EDITOR_RING_RADIUS,
			0.0,
			TAU,
			_EDITOR_ARC_SEGMENTS,
			color,
			_EDITOR_RING_WIDTH)
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var font_size := ThemeDB.fallback_font_size
	var label_size := font.get_string_size(
			_EDITOR_LABEL, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var label_position := Vector2(
			-label_size.x * 0.5,
			-_EDITOR_RING_RADIUS - _EDITOR_LABEL_MARGIN_PX)
	draw_string(
			font,
			label_position,
			_EDITOR_LABEL,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			color)


func _on_body_entered(body: Node) -> void:
	if not (body is Player):
		return
	var meow_player := get_node_or_null(^"%BigMeowPlayer") as AudioStreamPlayer2D
	if meow_player != null:
		meow_player.play()
	if is_instance_valid(G.audio):
		G.audio.play_player_sound_delayed(
				"success", _SUCCESS_CADENCE_DELAY_SEC)
	if is_instance_valid(G.level):
		G.level.win()


func _apply_frequency_tint() -> void:
	var color := Frequency.color_of(frequency)
	modulate = Color(color.r, color.g, color.b, modulate.a)
