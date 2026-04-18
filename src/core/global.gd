# class_name G
extends Node
## Add global state here for easy access.


var time := ScaffolderTime.new()
@warning_ignore("shadowed_global_identifier")
var log := ScaffolderLog.new()
var utils := Utils.new()
var geometry := Geometry.new()

var main: Main
var settings: Settings
var audio: AudioMain
var hud: Hud
var state: StateMain

var game_panel: GamePanel
var session: Session
var level: Level

# Echolocation: visibility renderer + pulse emitter. Assigned in
# EcholocationRenderer._enter_tree. Typed as CanvasLayer to avoid a
# cross-script class_name dependency at autoload parse time; actual
# type is EcholocationRenderer.
var echo: CanvasLayer

# Marching-squares terrain. Assigned by TerrainLevel._ready. Typed
# as Node for the same class_name-dependency reason; actual type is
# TerrainWorld.
var terrain: Node

# Bug spawner. Assigned in BugSpawner._enter_tree so the shader can
# pull live bug positions + frequencies per frame without a scene-
# tree search. Typed as Node2D to avoid a cross-script class_name
# dependency at autoload parse time; actual type is BugSpawner.
var bugs: Node2D


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		settings = load("res://settings.tres")

	time.name = "Time"
	add_child(time)

	log.name = "Log"
	add_child(log)

	utils.name = "Utils"
	add_child(utils)

	geometry.name = "Geometry"
	add_child(geometry)


# --- Include some convenient access to logging/error utilities ---------------

var is_verbose: bool:
	get:
		return log.is_verbose


func print(
		message = "",
		category := ScaffolderLog.CATEGORY_DEFAULT,
		verbosity := ScaffolderLog.Verbosity.NORMAL,
		force_enable := false,
) -> void:
	log.print(message, category, verbosity, force_enable)


func verbose(
		message = "",
		category := ScaffolderLog.CATEGORY_DEFAULT,
		force_enable := false,
) -> void:
	log.print(message, category, ScaffolderLog.Verbosity.VERBOSE, force_enable)


func warning(message = "", category := ScaffolderLog.CATEGORY_DEFAULT) -> void:
	log.warning(message, category)


func error(message = "", category := ScaffolderLog.CATEGORY_DEFAULT) -> void:
	log.error(message, category, false)


func fatal(message = "", category := ScaffolderLog.CATEGORY_DEFAULT) -> void:
	log.error(message, category, true)


func ensure(condition: bool, message = "") -> bool:
	return log.ensure(condition, message)


func ensure_valid(object, message = "") -> bool:
	return log.ensure(is_instance_valid(object), message)


func check(condition: bool, message = "") -> bool:
	return log.check(condition, message)


func check_valid(object, message = "") -> bool:
	return log.check(is_instance_valid(object), message)

# -----------------------------------------------------------------------------
