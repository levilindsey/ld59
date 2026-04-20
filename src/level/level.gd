class_name Level
extends Node2D


const _RESET_READY_TO_START_GAME_DELAY_SEC := 0.3
const _GAME_OVER_READY_TO_RESET_DELAY_SEC := 3.0

const _PLAYER_CAMERA_OFFSET := Vector2(0, -10)

var player: Player

var has_started := false
var has_finished := false
var has_won := false


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

	G.state.transition(StateMain.State.TITLE)

	await get_tree().create_timer(_RESET_READY_TO_START_GAME_DELAY_SEC).timeout

	start_game()


func start_game() -> void:
	G.print("Starting game", ScaffolderLog.CATEGORY_GAME_STATE)

	has_started = true
	spawn_player()
	G.state.transition(StateMain.State.GAME)


func game_over() -> void:
	G.print("Game over", ScaffolderLog.CATEGORY_GAME_STATE)
	has_finished = true
	await get_tree().create_timer(_GAME_OVER_READY_TO_RESET_DELAY_SEC).timeout
	G.print("Resetting for next game", ScaffolderLog.CATEGORY_GAME_STATE)
	reset()


func win() -> void:
	has_won = true
	if is_instance_valid(player):
		player.enter_win_pose()
	if is_instance_valid(G.hud):
		G.hud.show_intro_overlay()


func _physics_process(_delta: float) -> void:
	if is_instance_valid(player):
		%Camera2D.global_position = player.global_position + _PLAYER_CAMERA_OFFSET
	else:
		%Camera2D.global_position = %PlayerSpawnPoint.global_position + _PLAYER_CAMERA_OFFSET


func spawn_player() -> void:
	player = G.settings.player_scene.instantiate()
	%Players.add_child(player)
	var spawn_position: Vector2 = %PlayerSpawnPoint.global_position
	player.global_position = spawn_position
	player.call_deferred("set_global_position", spawn_position)

	player.play_sound("spawn")

	player.call_deferred("_enter_attached_idle_at_spawn")
