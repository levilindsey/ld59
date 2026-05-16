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

## Delay before the *first* wayfinding cue, measured from the frame
## the player becomes interactive (spawn-grace detach). Shorter than
## the steady-state interval so players get an early orientation
## nudge right after leaving the ceiling, before the full-interval
## rhythm kicks in.
const _INITIAL_CUE_DELAY_SEC := 5.0

## Spacing between the three staggered "BigMeowFinal" plays on
## arrival. The first fires immediately, #2 after one interval, #3
## after two — a quick cascade that punctuates the win moment
## without stepping on the success cadence that follows.
const _FINAL_MEOW_STAGGER_SEC := 0.3

## Scales the `CoinVfx.spawn_world_burst` horizontal range. Shorter
## than a regular coin pickup on purpose — the arrival burst reads
## as a focused "bloom up from the goal" rather than sweeping across
## the screen.
const _WIN_BURST_SIZE_MULTIPLIER := 0.5

## Initial launch angle above horizontal, in degrees. Shallower than
## the 45° coin-pickup default to give the arrival rainbow a flatter
## silhouette over its shortened span.
const _WIN_BURST_LAUNCH_ANGLE_DEG := 40.0

## Zero jitter: the destination is a fixed emitter, so a
## deterministic arc shape reads better than the randomized
## per-coin variation.
const _WIN_BURST_JITTER_DEG := 0.0

## Half of the rainbow shader's default `distance_fade_reach` (0.5),
## which stretches the fade over *twice* the visible arc length so
## the win-burst tip stays noticeably brighter than a regular coin-
## pickup tip.
const _WIN_BURST_DISTANCE_FADE_REACH := 0.25

## Initial arc thickness at the emitter, in screen pixels (the
## rainbow's base `_THICKNESS_START_PX` is 1.0, so a multiplier of
## 3 yields a 3-pixel-wide start). Wider than a regular coin
## pickup so the win-burst reads as a bigger, more triumphant
## ribbon launching from the horn tip.
const _WIN_BURST_THICKNESS_START_MULTIPLIER := 3.0


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
@export_range(1.0, 120.0) var periodic_meow_interval_sec: float = 6.67

## Accumulator for the periodic meow timer. Only advances while the
## player is interactive, and resets whenever they revert to a
## non-interactive pose (spawn grace, death respawn) so the cue
## cadence always restarts fresh relative to the current detach.
var _time_since_meow_sec: float = 0.0

## Whether the 5-second initial cue has already fired this
## interactive session. Reset alongside `_time_since_meow_sec`
## whenever the player becomes non-interactive so a respawn resets
## the first-cue timing too.
var _has_fired_first_cue: bool = false

## True while the player's body is overlapping this Area2D. The win
## condition also requires the player to be touching the floor, so
## we latch presence here and check the surface state each frame
## until both are true (or the player leaves).
var _is_player_inside: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	monitoring = true
	monitorable = false
	# Player is on layer 4 (bit 3); mask matches only the player.
	collision_layer = 0
	collision_mask = 1 << 3
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
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
		# Player is pinned (spawn grace or post-respawn). Hold the
		# cue clock at zero and reset the first-cue flag so the next
		# detach starts a fresh 5-second countdown.
		_time_since_meow_sec = 0.0
		_has_fired_first_cue = false
		return
	# Win condition: player must be both inside the Area2D and
	# touching the floor. Airborne overlap alone (e.g. falling
	# through) does not end the run.
	if _is_player_inside and player.surface_state.is_touching_floor:
		_trigger_win()
		return
	_time_since_meow_sec += delta
	var target_sec: float = (
			periodic_meow_interval_sec
			if _has_fired_first_cue
			else _INITIAL_CUE_DELAY_SEC)
	if _time_since_meow_sec >= target_sec:
		_time_since_meow_sec = 0.0
		_has_fired_first_cue = true
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
		_play_meow_echoes(meow_player)
	# Camera shake punch on the wayfinding cue. Tunable knobs.
	if is_instance_valid(G.level):
		G.level.shake_camera(2.5, 0.4)

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
	var ring_color := Color(0.72, 0.42, 1.0, 1.0)
	if is_instance_valid(G.settings):
		ring_color = G.settings.color_destination_pulse
	G.echo.emit_pulse(
			pulse_pos,
			Frequency.Type.NONE,
			-1.0,
			10,
			-1.0,
			TAU,
			0.0,
			ring_color,
			true)


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
	_is_player_inside = true


func _on_body_exited(body: Node) -> void:
	if not (body is Player):
		return
	_is_player_inside = false


func _trigger_win() -> void:
	_play_final_meow(^"%BigMeowFinalPlayer", 0.0)
	_play_final_meow(
			^"%BigMeowFinalPlayer2", _FINAL_MEOW_STAGGER_SEC)
	_play_final_meow(
			^"%BigMeowFinalPlayer3", _FINAL_MEOW_STAGGER_SEC * 2.0)
	if is_instance_valid(G.audio):
		G.audio.play_player_sound_delayed(
				"success", _SUCCESS_CADENCE_DELAY_SEC)
	var coin_vfx := (get_tree()
			.get_first_node_in_group(CoinVfx.GROUP) as CoinVfx)
	if coin_vfx != null:
		var horn_tip := get_node_or_null(^"%HornTip") as Node2D
		var burst_origin: Vector2 = (horn_tip.global_position
				if horn_tip != null else global_position)
		coin_vfx.spawn_world_burst(
				burst_origin,
				_WIN_BURST_SIZE_MULTIPLIER,
				_WIN_BURST_LAUNCH_ANGLE_DEG,
				_WIN_BURST_JITTER_DEG,
				_WIN_BURST_DISTANCE_FADE_REACH,
				-1.0,
				_WIN_BURST_THICKNESS_START_MULTIPLIER)
	if is_instance_valid(G.level):
		G.level.win()


func _play_final_meow(node_path: NodePath, delay_sec: float) -> void:
	var player := get_node_or_null(node_path) as AudioStreamPlayer2D
	if player == null:
		return
	if delay_sec <= 0.0:
		player.play()
		return
	var timer := get_tree().create_timer(delay_sec)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(player):
			player.play())


## Plays the wayfinding meow as three overlapping echoes staggered
## 0.5 sec apart, with each successive echo softer than the last.
## Picks ONE stream from the AudioStreamRandomizer up front and
## reuses it for all three echoes — the user wants the echoes to
## sound like the same vocalization repeating, not three different
## variants. Each echo runs in its own duplicated
## AudioStreamPlayer2D so they overlap (a single player would
## interrupt the previous play on the next call to play()).
func _play_meow_echoes(template: AudioStreamPlayer2D) -> void:
	var base_db: float = template.volume_db
	# Pick the actual stream from the randomizer once. Falls back to
	# whatever the template has set if it isn't a randomizer (e.g.,
	# a single AudioStream).
	var picked_stream: AudioStream = template.stream
	var randomizer := template.stream as AudioStreamRandomizer
	if randomizer != null and randomizer.streams_count > 0:
		var idx: int = randi() % randomizer.streams_count
		picked_stream = randomizer.get_stream(idx)
	# Echo volume scheme (multipliers on the player's authored
	# volume, in linear amplitude):
	#   1st: 1.1x — slightly louder than a single play.
	#   2nd: 0.15x of the 1st = 0.165x.
	#   3rd: 0.20x of the 2nd = 0.033x.
	var multipliers: Array[float] = [1.1, 0.165, 0.033]
	for i in multipliers.size():
		if not is_inside_tree():
			return
		var echo := template.duplicate() as AudioStreamPlayer2D
		template.add_sibling(echo)
		echo.stream = picked_stream
		echo.volume_db = base_db + linear_to_db(multipliers[i])
		echo.finished.connect(echo.queue_free)
		echo.play()
		if i < multipliers.size() - 1:
			await get_tree().create_timer(0.5).timeout


func _apply_frequency_tint() -> void:
	var color := Frequency.color_of(frequency)
	modulate = Color(color.r, color.g, color.b, modulate.a)
