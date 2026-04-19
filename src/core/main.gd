class_name Main
extends Node2D


@export var settings: Settings


var is_paused := true:
	get:
		return is_paused
	set(value):
		is_paused = value


func _enter_tree() -> void:
	G.main = self
	G.settings = settings

	Scaffolder.set_up()


func _ready() -> void:
	G.print("main._ready", ScaffolderLog.CATEGORY_SYSTEM_INITIALIZATION)

	randomize()

	get_tree().paused = true

	await get_tree().process_frame

	_move_window()

	G.state.start_game()


func _notification(notification_type: int) -> void:
	match notification_type:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			# Handle the Android back button to navigate within the app instead of
			# quitting the app.
			if false:
				close_app()
			else:
				pass
		NOTIFICATION_WM_CLOSE_REQUEST:
			close_app()
		NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			if G.settings.pauses_on_focus_out:
				is_paused = true
		_:
			pass


func _unhandled_input(event: InputEvent) -> void:
	if G.settings.dev_mode:
		if event is InputEventKey:
			match event.physical_keycode:
				KEY_P:
					if G.settings.is_screenshot_hotkey_enabled:
						G.utils.take_screenshot()
				KEY_O:
					if is_instance_valid(G.hud):
						G.hud.visible = not G.hud.visible
						G.print(
							"Toggled HUD visibility: %s" %
							("visible" if G.hud.visible else "hidden"),
							ScaffolderLog.CATEGORY_CORE_SYSTEMS)
				KEY_ESCAPE:
					if G.settings.pauses_on_focus_out:
						is_paused = true
				_:
					pass


func close_app() -> void:
	if G.utils.were_screenshots_taken:
		G.utils.open_screenshot_folder()
	G.print("Main.close_app", ScaffolderLog.CATEGORY_CORE_SYSTEMS)
	get_tree().call_deferred("quit")


func _move_window() -> void:
	if not OS.has_feature("editor"):
		return

	var screen_count := DisplayServer.get_screen_count()
	# Default to current screen (which windows start on).
	var target_screen := DisplayServer.window_get_current_screen()

	# Check if we should move to another monitor.
	if G.settings.move_preview_windows_to_other_display and screen_count > 1:
		# Move client window(s) to screen 0 (secondary monitor).
		target_screen = 0

	if G.settings.full_screen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		DisplayServer.window_set_current_screen(target_screen)
	else:
		var usable_rect := DisplayServer.screen_get_usable_rect(target_screen)
		var window_width := floori(usable_rect.size.x * 0.75)
		var window_height := floori(usable_rect.size.y * 0.75)

		# Set size.
		DisplayServer.window_set_size(Vector2i(window_width, window_height))

		# Center the window.
		@warning_ignore("integer_division")
		var position_x := usable_rect.position.x + (
			(usable_rect.size.x - window_width) / 2
		)
		@warning_ignore("integer_division")
		var position_y := usable_rect.position.y + (
			(usable_rect.size.y - window_height) / 2
		)
		DisplayServer.window_set_position(Vector2i(position_x, position_y))
