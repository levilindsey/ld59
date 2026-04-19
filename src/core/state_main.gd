class_name StateMain
extends Node


signal state_changed(from_state: State, to_state: State)


enum State {
	TITLE,
	GAME,
	PAUSE,
	CREDITS,
}

var state := State.TITLE

var _has_bootstrapped := false


func _enter_tree() -> void:
	G.state = self


func start_game() -> void:
	# Always enter TITLE first so the preview sprite + Title/Controls
	# UI have a moment to show. Level is expected to have been
	# instantiated by GamePanel before this call.
	G.state.transition(State.TITLE)
	if G.settings.start_in_game:
		# Dev convenience: skip the title-screen input and go straight
		# to the playable state.
		await get_tree().process_frame
		G.state.transition(State.GAME)


func transition(to_state: State) -> void:
	var from_state := state
	if to_state == from_state and _has_bootstrapped:
		return
	state = to_state
	_has_bootstrapped = true

	match to_state:
		State.TITLE:
			# Tree unpaused so the TITLE input listener and the
			# preview-sprite animation run normally.
			get_tree().paused = false
			G.audio.fade_to_menu_theme()
		State.GAME:
			get_tree().paused = false
			G.audio.fade_to_main_theme()
		State.PAUSE:
			get_tree().paused = true
			G.audio.fade_to_menu_theme()
		State.CREDITS:
			get_tree().paused = true
			G.audio.fade_to_menu_theme()
		_:
			G.error()

	state_changed.emit(from_state, to_state)
	G.hud.handle_state_transition(to_state)
