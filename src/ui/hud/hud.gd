class_name Hud
extends PanelContainer


func _enter_tree() -> void:
	G.hud = self


func _ready() -> void:
	# All HUD elements start hidden — Level/Player/State drive them
	# in via explicit show methods once spawn/win moments arrive.
	# Starting GameState hidden avoids a 1-frame flash of the
	# health + juice bars between the initial TITLE→GAME transition
	# (which fades them in) and the deferred spawn-grace entry
	# (which fades them back out again).
	%Title.modulate.a = 0.0
	%Controls.modulate.a = 0.0
	%Credits.modulate.a = 0.0
	%GameState.modulate.a = 0.0

	# Wait for G.settings to be assigned.
	await get_tree().process_frame

	self.visible = G.settings.show_hud
	_apply_credits_colors()


## Fades in the Title + Controls overlay and fades out the gameplay
## HUD (health + juice bars). Called by the Player when it enters
## the spawn-grace attached-idle pose, and by the Level after win —
## both cases park the player in a non-responsive pose with the
## intro overlay visible instead of the gameplay HUD until the user
## acts.
func show_intro_overlay() -> void:
	fade_in(%Title)
	fade_in(%Controls)
	fade_out(%GameState)


## Fades the Title + Controls overlay back out and restores the
## gameplay HUD. Called by the Player when spawn grace ends (first
## detach input).
func hide_intro_overlay() -> void:
	fade_out(%Title)
	fade_out(%Controls)
	fade_in(%GameState)


## Pushes `Settings.color_credits_*` into every Label under the
## credits group so the scene's authored font / outline colors
## can be tuned centrally.
func _apply_credits_colors() -> void:
	if G.settings == null:
		return
	var font: Color = G.settings.color_credits_font
	var outline: Color = G.settings.color_credits_outline
	for label in _find_credits_labels(%Credits):
		label.add_theme_color_override("font_color", font)
		label.add_theme_color_override("font_outline_color", outline)


func _find_credits_labels(root: Node) -> Array[Label]:
	var out: Array[Label] = []
	for child in root.get_children():
		if child is Label:
			out.append(child as Label)
		out.append_array(_find_credits_labels(child))
	return out


func fade_in(node: CanvasItem) -> void:
	var tween := create_tween()
	tween.tween_property(
		node,
		"modulate:a",
		1.0,
		0.3)


func fade_out(node: CanvasItem) -> void:
	var tween := create_tween()
	tween.tween_property(
		node,
		"modulate:a",
		0.0,
		0.3)


func handle_state_transition(to_state: StateMain.State) -> void:
	# Title + Controls + GameState are managed by the intro-overlay
	# show/hide pair, not by state — so the intro overlay can live
	# inside GAME state (spawn grace + post-win) rather than only on
	# a dedicated TITLE screen, and so the health + juice bars don't
	# briefly fade in on the initial TITLE→GAME transition only to
	# be faded back out by the deferred spawn-grace entry.
	match to_state:
		StateMain.State.TITLE:
			fade_out(%Credits)
		StateMain.State.GAME:
			fade_out(%Credits)
		StateMain.State.PAUSE:
			fade_out(%Credits)
		StateMain.State.CREDITS:
			fade_out(%GameState)
			fade_in(%Credits)
		_:
			G.error()
