class_name GamePanel
extends Node2D


var level: Level


func _enter_tree() -> void:
	G.game_panel = self
	G.session = Session.new()


func start_game() -> void:
	G.session.reset()
	G.session.is_game_ended = false

	start_level()


func end_game() -> void:
	G.session.is_game_ended = true


func reset() -> void:
	pass


func on_return_from_screen() -> void:
	if G.session.is_game_ended:
		start_game()


func start_level() -> void:
	level = G.settings.default_level_scene.instantiate()
	add_child(level)
