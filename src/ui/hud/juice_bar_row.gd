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


var _slots: Dictionary = {}
@onready var _selection_box: Control = $SelectionBox


func _ready() -> void:
	_collect_slots()


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
