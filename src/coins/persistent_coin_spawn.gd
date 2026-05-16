@tool
class_name PersistentCoinSpawn
extends Node2D
## Authored spawn point for a single collectible coin. At runtime a
## coin is instantiated and parented under this spawn node, positioned
## at `global_position`, and configured with this spawn's
## `coin_index`. Re-spawns whenever `Level.coin_state_reset` fires so
## restarts restore any previously-collected coins.
##
## In the editor, draws a gold disk + the coin's letter label so the
## designer can eyeball which slot each authored spot maps to.


const _EDITOR_FILL_ALPHA := 0.45
const _EDITOR_OUTLINE_WIDTH := 2.0
const _EDITOR_CIRCLE_SEGMENTS := 32
const _EDITOR_GOLD := Color(1.0, 0.84, 0.0, 1.0)
const _EDITOR_LABEL_MARGIN_PX := 4.0
const _EDITOR_LABEL_FONT_SIZE := 14
const _EDITOR_COIN_RADIUS_PX := 10.0


## Index 0..5. Determines which letter of "KITTEN" this spawn
## contributes. Must be unique across the level — duplicate indexes
## in the same level would collide on the shared collected-flags
## array.
@export_range(0, 5) var coin_index: int = 0:
	set(value):
		coin_index = clampi(value, 0, Coin.LETTERS.size() - 1)
		queue_redraw()

## Scene to instantiate. Typically left at the default `coin.tscn`.
@export var coin_scene: PackedScene = (
		preload("res://src/coins/coin.tscn"))


var _spawned_coin: Coin


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_try_spawn()
	_connect_to_level_signals()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	# Fill disk.
	var fill_color := _EDITOR_GOLD
	fill_color.a = _EDITOR_FILL_ALPHA
	draw_circle(Vector2.ZERO, _EDITOR_COIN_RADIUS_PX, fill_color)
	draw_arc(
			Vector2.ZERO,
			_EDITOR_COIN_RADIUS_PX,
			0.0,
			TAU,
			_EDITOR_CIRCLE_SEGMENTS,
			_EDITOR_GOLD,
			_EDITOR_OUTLINE_WIDTH)
	# Letter.
	var font: Font = ThemeDB.fallback_font
	var font_size := _EDITOR_LABEL_FONT_SIZE
	var label_text := _letter()
	var label_size := font.get_string_size(
			label_text,
			HORIZONTAL_ALIGNMENT_CENTER,
			-1,
			font_size)
	var label_pos := Vector2(
			-label_size.x * 0.5,
			_EDITOR_COIN_RADIUS_PX
					+ label_size.y
					+ _EDITOR_LABEL_MARGIN_PX)
	draw_string(
			font,
			label_pos,
			label_text,
			HORIZONTAL_ALIGNMENT_CENTER,
			label_size.x,
			font_size,
			_EDITOR_GOLD)


func _letter() -> String:
	if (coin_index < 0
			or coin_index >= Coin.LETTERS.size()):
		return "?"
	return Coin.LETTERS[coin_index]


func _connect_to_level_signals() -> void:
	if not is_instance_valid(G.level):
		return
	if not G.level.coin_state_reset.is_connected(_on_coin_state_reset):
		G.level.coin_state_reset.connect(_on_coin_state_reset)


func _on_coin_state_reset() -> void:
	_try_spawn()


func _try_spawn() -> void:
	# If a previous coin is still alive (e.g., reset fired before the
	# player collected it), leave it alone.
	if is_instance_valid(_spawned_coin):
		return
	if not G.ensure_valid(G.level, "PersistentCoinSpawn needs a Level"):
		return
	if G.level.is_coin_collected(coin_index):
		return
	if not G.ensure_valid(
			coin_scene, "PersistentCoinSpawn.coin_scene is unset"):
		return
	var coin: Coin = coin_scene.instantiate()
	coin.coin_index = coin_index
	add_child(coin)
	coin.global_position = global_position
	_spawned_coin = coin
