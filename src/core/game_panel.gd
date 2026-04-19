class_name GamePanel
extends Node2D


var level: Level


func _enter_tree() -> void:
	G.game_panel = self
	G.session = Session.new()


func _ready() -> void:
	G.state.state_changed.connect(_on_state_changed)
	# Bring the level online before Main triggers the initial TITLE
	# transition, so the title-screen preview sprite and input listener
	# exist on frame 1.
	ensure_level_instantiated()


func _on_state_changed(
		_from_state: StateMain.State,
		to_state: StateMain.State) -> void:
	match to_state:
		StateMain.State.TITLE:
			ensure_level_instantiated()
		StateMain.State.GAME:
			ensure_level_instantiated()
			if (
				is_instance_valid(level)
				and not is_instance_valid(level.player)
			):
				level.spawn_player()


func ensure_level_instantiated() -> void:
	if is_instance_valid(level):
		return
	level = G.settings.default_level_scene.instantiate()
	add_child(level)


func destroy_level() -> void:
	if not is_instance_valid(level):
		return
	var old := level
	level = null
	old.queue_free()


func reset_level() -> void:
	destroy_level()
	# Let queue_free() finalize before re-instantiating.
	await get_tree().process_frame
	ensure_level_instantiated()


## Async game-over flow. Owned by GamePanel (not Level) so the
## coroutine survives the level destruction in the middle.
func trigger_game_over() -> void:
	G.audio.play_death_cadence()
	await G.audio.cadence_sequence_finished
	destroy_level()
	await get_tree().process_frame
	G.state.transition(StateMain.State.TITLE)
	# The state_changed handler above re-instantiates the level.


# Legacy compatibility shims — retained so callers elsewhere in the
# codebase don't need a coordinated rename. Session accounting is
# no longer tied to state transitions.
func start_game() -> void:
	G.session.reset()
	G.session.is_game_ended = false


func end_game() -> void:
	G.session.is_game_ended = true


func reset() -> void:
	pass


func on_return_from_screen() -> void:
	pass


func start_level() -> void:
	ensure_level_instantiated()
