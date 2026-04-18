class_name Player
extends Character


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


func destroy() -> void:
	queue_free()


func _process(delta: float) -> void:
	super._process(delta)


func _physics_process(delta: float) -> void:
	if G.level.has_won:
		return

	super._physics_process(delta)


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


func _update_actions() -> void:
	super._update_actions()


func _process_animation() -> void:
	super._process_animation()


func play_sound(sound_name: String, force_restart := false) -> void:
	if G.level.has_won:
		return
	G.audio.play_player_sound(sound_name, force_restart)
