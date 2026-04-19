class_name StateMain
extends Node


enum State {
	TITLE,
	GAME,
	PAUSE,
	CREDITS,
}

var state := State.TITLE


func _enter_tree() -> void:
	G.state = self


func start_game() -> void:
	var to_state := State.GAME if G.settings.start_in_game else State.TITLE
	G.state.transition(to_state)


func transition(to_state: State) -> void:
	var from_state := state
	state = to_state

	if to_state == from_state:
		return

	match to_state:
		State.TITLE:
			if not G.session.is_game_ended:
				G.game_panel.end_game()
			get_tree().paused = true
			G.audio.fade_to_menu_theme()
		State.GAME:
			if G.session.is_game_ended:
				G.game_panel.start_game()
			get_tree().paused = false
			G.audio.fade_to_main_theme()
			G.game_panel.on_return_from_screen()
		State.PAUSE:
			get_tree().paused = true
			G.audio.fade_to_menu_theme()
		State.CREDITS:
			if not G.session.is_game_ended:
				G.game_panel.end_game()
			get_tree().paused = true
			G.audio.fade_to_menu_theme()
		_:
			G.error()

	G.hud.handle_state_transition(to_state)
