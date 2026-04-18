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
