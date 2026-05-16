class_name CoinIndicator
extends HBoxContainer
## Top-right HUD indicator for the six collectible "KITTEN" coins.
## Hidden until the player collects the first coin, at which point
## all 6 empty boxes reveal with the collected letter filled in. The
## container is hidden again on `Level.coin_state_reset` (triggered
## by `Level.reset()` after a death / game-over).
##
## Slots are generated procedurally in `_ready` so the .tscn stays
## minimal — the styling is derived from `Settings` to match the
## existing juice / health bars.


const _SLOT_SIZE := Vector2(30, 30)
const _SLOT_BORDER_WIDTH := 1
const _SLOT_CORNER_RADIUS := 4
const _SEPARATION_PX := 6

const _BASE_COLOR := Color(1.0, 0.84, 0.0, 1.0)


var _slots: Array[PanelContainer] = []
var _icons: Array[TextureRect] = []


@onready var _vfx: Node = $CoinVfx


func _ready() -> void:
	add_theme_constant_override("separation", _SEPARATION_PX)
	_build_slots()
	visible = false


func _process(_delta: float) -> void:
	if not is_instance_valid(G.level):
		return
	# Re-check each frame (not a one-shot flag) so the HUD
	# re-connects to whichever Level instance is current. On game-
	# over the whole Level scene reloads, and the previous level's
	# signal connection dies with it.
	if not G.level.coin_state_reset.is_connected(_on_coin_state_reset):
		G.level.coin_state_reset.connect(_on_coin_state_reset)
		var typed_slots: Array[Control] = []
		for slot in _slots:
			typed_slots.append(slot)
		_vfx.hud_slot_nodes = typed_slots
	var any_collected := false
	for i in range(Level.COIN_COUNT):
		var collected := G.level.is_coin_collected(i)
		_icons[i].visible = collected
		if collected:
			any_collected = true
	visible = any_collected


func _on_coin_state_reset() -> void:
	for icon in _icons:
		icon.visible = false
	visible = false


func _build_slots() -> void:
	for i in range(Level.COIN_COUNT):
		var slot := PanelContainer.new()
		slot.custom_minimum_size = _SLOT_SIZE
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.clip_contents = true
		slot.add_theme_stylebox_override("panel", _build_slot_style())
		add_child(slot)
		var icon := TextureRect.new()
		icon.texture = _first_frame_texture(i)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = (
				CanvasItem.TEXTURE_FILTER_NEAREST)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
		icon.visible = false
		slot.add_child(icon)
		_slots.append(slot)
		_icons.append(icon)


## Builds an AtlasTexture pointing at frame 0 of coin `index`'s
## spritesheet — the static "trophy" view shown in the HUD.
func _first_frame_texture(index: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = Coin.sheet_for_index(index)
	atlas.region = Coin.first_frame_region()
	return atlas


func _build_slot_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var base := _BASE_COLOR
	if is_instance_valid(G.settings):
		base = G.settings.color_coin_stipple
	var border_alpha := 0.7
	if is_instance_valid(G.settings):
		border_alpha = G.settings.color_slot_border_alpha
	# Transparent fill — the spritesheet icon reads against the raw
	# game backdrop rather than a coin-tinted panel.
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.border_color = Color(base.r, base.g, base.b, border_alpha)
	style.set_border_width_all(_SLOT_BORDER_WIDTH)
	style.set_corner_radius_all(_SLOT_CORNER_RADIUS)
	return style
