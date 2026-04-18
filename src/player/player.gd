class_name Player
extends Character


## Horizontal speed multiplier applied while any WebTile overlaps the
## player's WebSensor. Vertical movement is unaffected.
const _WEB_SPEED_MULTIPLIER := 0.25


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

	_update_web_slowdown()
	super._physics_process(delta)


func _update_web_slowdown() -> void:
	var sensor: Area2D = get_node_or_null(^"%WebSensor") as Area2D
	if not is_instance_valid(sensor):
		_current_max_horizontal_speed_multiplier = 1.0
		return
	var in_web := false
	for area in sensor.get_overlapping_areas():
		if area is WebTile:
			in_web = true
			break
	_current_max_horizontal_speed_multiplier = (
			_WEB_SPEED_MULTIPLIER if in_web else 1.0)


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
