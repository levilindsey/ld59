class_name Player
extends Character


## Horizontal speed multiplier applied while any WebTile overlaps the
## player's WebSensor.
const _WEB_SPEED_MULTIPLIER := 0.25

## Absolute cap on `|velocity.y|` while overlapping a web. Applied
## after the scaffolder's action handlers run, so gravity and jump
## impulses are still computed normally but the resulting motion is
## slow. Clamping (rather than scaling) avoids compound-drag weirdness
## across frames at varying physics steps.
const _WEB_MAX_VERTICAL_SPEED_PX_PER_SEC := 120.0


var _is_in_web := false


var half_size := Vector2.INF

## Player's active echolocation frequency. Changes when eating a
## matching-frequency bug (Phase 3). Drives which tiles an emitted
## pulse damages and the pulse's visual tint.
var current_frequency: int = Frequency.Type.GREEN


func _ready() -> void:
	super._ready()
	half_size = Geometry.calculate_half_width_height(
		collision_shape.shape,
		false)
	%PlayerHealth.died.connect(_on_died)


func destroy() -> void:
	queue_free()


func _process(delta: float) -> void:
	super._process(delta)


func _physics_process(delta: float) -> void:
	if G.level.has_won:
		return

	_sample_web_overlap()
	_current_max_horizontal_speed_multiplier = (
			_WEB_SPEED_MULTIPLIER if _is_in_web else 1.0)
	super._physics_process(delta)
	if _is_in_web:
		velocity.y = clampf(
				velocity.y,
				-_WEB_MAX_VERTICAL_SPEED_PX_PER_SEC,
				_WEB_MAX_VERTICAL_SPEED_PX_PER_SEC)


func _sample_web_overlap() -> void:
	var sensor: Area2D = get_node_or_null(^"%WebSensor") as Area2D
	if not is_instance_valid(sensor):
		_is_in_web = false
		return
	for area in sensor.get_overlapping_areas():
		if area is WebTile:
			_is_in_web = true
			return
	_is_in_web = false


func _unhandled_input(event: InputEvent) -> void:
	if G.level.has_won or G.level.has_finished:
		return
	if event.is_action_pressed("ability"):
		_emit_echo_pulse()


func _emit_echo_pulse() -> void:
	if not is_instance_valid(G.echo):
		return
	G.echo.emit_pulse(global_position, current_frequency)


func set_frequency(freq: int) -> void:
	current_frequency = freq


func apply_damage(amount: int) -> void:
	%PlayerHealth.apply_damage(amount)


func apply_heal(amount: int) -> void:
	%PlayerHealth.apply_heal(amount)


func _on_died() -> void:
	if is_instance_valid(G.level):
		G.level.game_over()


func _update_actions() -> void:
	super._update_actions()


func _process_animation() -> void:
	super._process_animation()


func play_sound(sound_name: String, force_restart := false) -> void:
	if G.level.has_won:
		return
	G.audio.play_player_sound(sound_name, force_restart)
