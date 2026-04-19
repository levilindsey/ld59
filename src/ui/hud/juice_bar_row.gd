class_name JuiceBarRow
extends HBoxContainer
## Five-slot juice readout: a blank NONE slot plus four colored
## frequency bars (RED/GREEN/BLUE/YELLOW). Each colored slot shows
## how much juice the player currently holds for that frequency
## (0..Player.MAX_JUICE). The currently-selected slot is overlaid
## by an animated `SelectionBox` border whose brightness + width
## track the echo cooldown — dim while cooling, bright and
## breathing once ready.
##
## Polls `G.level.player` each frame; matches the polling pattern
## used by `HealthBar` and the old `FrequencyChip`.


const _SLOT_ORDER: Array[int] = [
	Frequency.Type.NONE,
	Frequency.Type.RED,
	Frequency.Type.GREEN,
	Frequency.Type.BLUE,
	Frequency.Type.YELLOW,
]

## Echo icon modulate = lerp(base_hue, WHITE, _ECHO_ICON_PASTEL_T).
## Higher t reads as lighter + less saturated.
const _ECHO_ICON_PASTEL_T := 0.4

## Fallback hue used for the NONE slot's echo icon (the slot is
## gray-themed, not driven by a Frequency palette entry).
const _ECHO_ICON_NONE_BASE := Color(0.55, 0.55, 0.6, 1.0)


var _slots: Dictionary = {}

@onready var _selection_box: Control = $SelectionBox


func _ready() -> void:
	_collect_slots()
	_apply_echo_icon_tints()


## Per-slot echo icon modulate = that slot's hue lerped toward
## white so the icon reads as a lighter / less-saturated tint of
## the slot color.
func _apply_echo_icon_tints() -> void:
	for freq: int in _SLOT_ORDER:
		var slot: PanelContainer = _slots.get(freq, null)
		if slot == null:
			continue
		var bar := slot.get_node_or_null("Bar") as ProgressBar
		if bar == null:
			continue
		var icon := bar.get_node_or_null("EchoIcon") as CanvasItem
		if icon == null:
			continue
		var base := _echo_icon_base_color(freq)
		icon.modulate = base.lerp(Color.WHITE, _ECHO_ICON_PASTEL_T)


func _echo_icon_base_color(freq: int) -> Color:
	if freq == Frequency.Type.NONE:
		return _ECHO_ICON_NONE_BASE
	return Frequency.color_of(freq)


func _collect_slots() -> void:
	# Map each slot PanelContainer by frequency so the selection box
	# can look up where to overlay.
	_slots = {
		Frequency.Type.NONE: $SlotNone,
		Frequency.Type.RED: $SlotRed,
		Frequency.Type.GREEN: $SlotGreen,
		Frequency.Type.BLUE: $SlotBlue,
		Frequency.Type.YELLOW: $SlotYellow,
	}


func _process(_delta: float) -> void:
	var player := _get_player()
	if not is_instance_valid(player):
		return
	_refresh_bars(player)
	_refresh_selection(player)


func _refresh_bars(player: Player) -> void:
	for freq in _SLOT_ORDER:
		var slot: PanelContainer = _slots.get(freq, null)
		if slot == null:
			continue
		var bar := slot.get_node_or_null("Bar") as ProgressBar
		if bar == null:
			continue
		if freq == Frequency.Type.NONE:
			# Always-available marker — render as full so it reads
			# as "ready". No juice tracking.
			bar.max_value = 1.0
			bar.value = 1.0
		else:
			bar.max_value = float(Player.MAX_JUICE)
			bar.value = float(player.get_juice(freq))
		# Hide the echo icon when the bar is empty so empty slots
		# read as "locked / needs juice" at a glance.
		var icon := bar.get_node_or_null("EchoIcon") as CanvasItem
		if icon != null:
			icon.visible = bar.value > 0.0


func _refresh_selection(player: Player) -> void:
	var freq := player.current_frequency
	var slot: PanelContainer = _slots.get(freq, null)
	if slot == null:
		_selection_box.visible = false
		return
	_selection_box.visible = true
	# SelectionBox uses `top_level = true`, so it lives in global
	# screen coordinates. Track the slot's global rect each frame.
	_selection_box.position = slot.global_position
	_selection_box.size = slot.size
	_selection_box.set_meta(
			"cooldown_fraction", player.get_cooldown_fraction())
	_selection_box.queue_redraw()


func _get_player() -> Player:
	if is_instance_valid(G.level) and is_instance_valid(G.level.player):
		return G.level.player
	return null
