class_name Hud
extends PanelContainer


func _enter_tree() -> void:
	G.hud = self


func _ready() -> void:
	# Hide the title, so we can fade it in.
	%Title.modulate.a = 0.0
	%Credits.modulate.a = 0.0

	# Wait for G.settings to be assigned.
	await get_tree().process_frame

	self.visible = G.settings.show_hud
	_apply_credits_colors()


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
	match to_state:
		StateMain.State.TITLE:
			fade_in(%Title)
			fade_out(%GameState)
			fade_out(%Credits)
			fade_in(%Controls)
		StateMain.State.GAME:
			fade_out(%Title)
			fade_in(%GameState)
			fade_out(%Credits)
			fade_out(%Controls)
		StateMain.State.PAUSE:
			fade_out(%Title)
			fade_in(%GameState)
			fade_out(%Credits)
			fade_out(%Controls)
		StateMain.State.CREDITS:
			fade_out(%Title)
			fade_out(%GameState)
			fade_in(%Credits)
			fade_out(%Controls)
		_:
			G.error()
