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

## Distance (world px) past the viewport edge at which to emit the
## companion echo pulse during a periodic cue. Large enough that the
## pulse wavefront is obviously off-screen when it fires, small
## enough that its ripple reaches into the viewport within the
## pulse's normal radius.
const _OFFSCREEN_CUE_MARGIN_PX := 32.0


## Frequency tint; cosmetic only (does not gate the win).
@export var frequency: Frequency.Type = Frequency.Type.YELLOW:
	set(value):
		frequency = value
		queue_redraw()
		if not Engine.is_editor_hint() and is_inside_tree():
			_apply_frequency_tint()

## Interval between periodic spatial "BigMeow" plays. The
## AudioStreamPlayer2D's built-in 2D attenuation / panning gives the
## player a directional wayfinding cue — the goal "calls out" so
## players roaming in the dark can orient toward it.
@export_range(1.0, 120.0) var periodic_meow_interval_sec: float = 20.0

## Accumulator for the periodic meow timer. Starts at 0 so the first
## call-out fires after one full interval, giving the player time to
## explore before the destination first announces itself.
var _time_since_meow_sec: float = 0.0


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


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	# Skip while the level isn't in active-gameplay state: no periodic
	# call-out during spawn grace (player still pinned to the ceiling,
	# title is showing) or after win (the arrival BigMeow just played
	# and the level is frozen).
	if not is_instance_valid(G.level) or G.level.has_won:
		return
	var player := G.level.player
	if not is_instance_valid(player) or player.is_non_interactive:
		return
	_time_since_meow_sec += delta
	if _time_since_meow_sec >= periodic_meow_interval_sec:
		_time_since_meow_sec = 0.0
		_fire_wayfinding_cue()


## Spatial audio + off-screen echo pulse pointing toward this
## destination. Skipped entirely when the destination is already on-
## screen (the player can see it, so neither cue adds anything).
func _fire_wayfinding_cue() -> void:
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam == null:
		return
	var zoom := cam.zoom
	if zoom.x <= 0.0 or zoom.y <= 0.0:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	# Camera2D uses DRAG_CENTER anchor (set by Level._ready), so the
	# camera's global_position is the viewport's world-space center.
	var cam_world := cam.global_position
	var half_world := Vector2(
			viewport_size.x * 0.5 / zoom.x,
			viewport_size.y * 0.5 / zoom.y)
	var offset := global_position - cam_world
	# On-screen? Skip both cues — the player can already see the
	# destination so wayfinding hints are noise.
	if (absf(offset.x) <= half_world.x
			and absf(offset.y) <= half_world.y):
		return

	var meow_player := (get_node_or_null(^"%BigMeowPlayer")
			as AudioStreamPlayer2D)
	if meow_player != null and not meow_player.playing:
		meow_player.play()

	if not is_instance_valid(G.echo):
		return
	var dir := offset.normalized() if offset != Vector2.ZERO else Vector2.RIGHT
	# Intersect the ray `cam_world + t * dir` with the expanded
	# viewport rect (viewport edge + margin). The smaller of the x /
	# y intercepts is where the ray exits the rect — that's the
	# "just off-screen in the direction of the destination" point.
	var t_x: float = INF
	if absf(dir.x) > 1e-6:
		t_x = (half_world.x + _OFFSCREEN_CUE_MARGIN_PX) / absf(dir.x)
	var t_y: float = INF
	if absf(dir.y) > 1e-6:
		t_y = (half_world.y + _OFFSCREEN_CUE_MARGIN_PX) / absf(dir.y)
	var t: float = minf(t_x, t_y)
	var pulse_pos := cam_world + dir * t
	G.echo.emit_pulse(pulse_pos, Frequency.Type.NONE)


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
