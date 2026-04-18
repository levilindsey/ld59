class_name Player
extends Character


var half_size := Vector2.INF


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


func _update_actions() -> void:
	super._update_actions()


func _process_animation() -> void:
	super._process_animation()


func play_sound(sound_name: String, force_restart := false) -> void:
	if G.level.has_won:
		return
	G.audio.play_player_sound(sound_name, force_restart)
