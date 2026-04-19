class_name Level
extends Node2D


const _READY_FOR_INPUT_DELAY_SEC := 0.3

const _PLAYER_CAMERA_OFFSET := Vector2(0, -10)

var player: Player

var has_started := false
var has_finished := false
var has_won := false
var is_ready_for_input_to_activate_next_game := false

var _is_game_over_in_progress := false


func _enter_tree() -> void:
	G.level = self


func _exit_tree() -> void:
	if G.level == self:
		G.level = null


func _ready() -> void:
	# Center the camera's anchor on its position. In Godot 4.5+ the
	# Camera2D default changed to FIXED_TOP_LEFT, which would make
	# the player render at the top-left of the screen given our
	# follow logic in _physics_process.
	%Camera2D.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	reset()


func reset() -> void:
	if is_instance_valid(player):
		player.destroy()

	has_started = false
	has_finished = false
	has_won = false
	is_ready_for_input_to_activate_next_game = false

	_show_spawn_preview()

	# Debounce: swallow whatever keypress triggered a death/win so it
	# doesn't also start the next game the instant the new level
	# instantiates. `process_always` on the timer keeps it ticking if
	# the tree happens to be paused during the transition.
	await get_tree().create_timer(
			_READY_FOR_INPUT_DELAY_SEC, true, false, true).timeout

	is_ready_for_input_to_activate_next_game = true


func start_game() -> void:
	has_started = true
	is_ready_for_input_to_activate_next_game = false
	G.state.transition(StateMain.State.GAME)


func game_over() -> void:
	if _is_game_over_in_progress:
		return
	_is_game_over_in_progress = true
	has_finished = true
	G.game_panel.trigger_game_over()


func win() -> void:
	if has_won:
		return
	has_won = true
	G.audio.play_win_cadence()
	G.state.transition(StateMain.State.CREDITS)


func _input(event: InputEvent) -> void:
	if not is_ready_for_input_to_activate_next_game:
		return

	if (
		event.is_action_pressed("move_up") or
		event.is_action_pressed("move_down") or
		event.is_action_pressed("move_left") or
		event.is_action_pressed("move_right") or
		event.is_action_pressed("jump") or
		event.is_action_pressed("select_prev_frequency") or
		event.is_action_pressed("select_next_frequency")
	):
		start_game()


func _physics_process(_delta: float) -> void:
	if is_instance_valid(player):
		%Camera2D.global_position = (
				player.global_position + _PLAYER_CAMERA_OFFSET)
	else:
		%Camera2D.global_position = (
				%PlayerSpawnPoint.global_position
				+ _PLAYER_CAMERA_OFFSET)


func spawn_player() -> void:
	_hide_spawn_preview()
	player = G.settings.player_scene.instantiate()
	%Players.add_child(player)
	var spawn_position: Vector2 = %PlayerSpawnPoint.global_position
	player.global_position = spawn_position
	player.call_deferred("set_global_position", spawn_position)

	player.play_sound("spawn")


func _hide_spawn_preview() -> void:
	var preview := get_node_or_null("%SpawnPreviewSprite")
	if is_instance_valid(preview):
		preview.visible = false


func _show_spawn_preview() -> void:
	var preview := get_node_or_null("%SpawnPreviewSprite")
	if is_instance_valid(preview):
		preview.visible = true
