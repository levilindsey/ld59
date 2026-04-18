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

	# Share World2D between the root viewport and the tag viewport
	# so both render the same scene tree. The cameras in each
	# viewport filter what they see via canvas_cull_mask; terrain
	# lives on visibility layer 1|2 (visible in both), sprites
	# default to layer 1 (scene only). The tag viewport's pixels
	# are fed to the echolocation composite shader as a per-pixel
	# type buffer for gradient sampling + palette matching.
	var root_viewport := get_viewport()
	var tag_viewport: SubViewport = %TagViewport
	tag_viewport.world_2d = root_viewport.world_2d
	var root_size := root_viewport.get_visible_rect().size
	tag_viewport.size = Vector2i(root_size)
	root_viewport.size_changed.connect(_on_root_viewport_resized)
	# Re-currency the tag camera after world_2d is assigned —
	# changing world_2d after tree entry can clear the camera's
	# auto-current registration.
	var tag_camera: Camera2D = %TagCamera2D
	if is_instance_valid(tag_camera):
		tag_camera.make_current()
	# Tag viewport cull_mask = 3 (layers 1 + 2). Ideally this would
	# be 2 (terrain only, vis_layer 3 has bit 1 set) so the tag
	# texture excluded sprites/parallax — that's the cleaner
	# architecture. But Godot 4.6.2 + this AMD driver appears to
	# have a quirk where canvas_cull_mask = 2 doesn't filter
	# correctly, even though (visibility_layer 3 & cull_mask 2) = 2
	# should pass; cull = 3 works. Workaround: include layer 1, let
	# the shader's palette-match path filter terrain pixels from
	# sprite/parallax pixels (terrain renders at exact palette
	# colors, sprites don't).
	# Side effect: gradient sampling on tag_tex includes player
	# pixels, so the small (~4 px) player-gap artifact in the
	# atlas surface band returns. Acceptable for now.
	tag_viewport.canvas_cull_mask = 3
	if (is_instance_valid(tag_camera)
			and "canvas_cull_mask" in tag_camera):
		tag_camera.set("canvas_cull_mask", 3)

	await get_tree().process_frame

	_move_window()

	G.state.start_game()


func _on_root_viewport_resized() -> void:
	var root_viewport := get_viewport()
	var tag_viewport: SubViewport = %TagViewport
	tag_viewport.size = Vector2i(root_viewport.get_visible_rect().size)


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
