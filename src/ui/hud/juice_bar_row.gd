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
	_apply_slot_themes()


## Apply every colored slot's bg / border / fill from
## `Settings.color_frequency_*` (derivation params shared with
## HealthBar), apply the NONE slot's explicit colors, and tint
## each slot's echo icon to that slot's hue lerped toward white
## (Settings.color_icon_pastel_t).
func _apply_slot_themes() -> void:
	var s: Settings = G.settings
	if s == null:
		return
	for freq: int in _SLOT_ORDER:
		var slot: PanelContainer = _slots.get(freq, null)
		if slot == null:
			continue
		var bar := slot.get_node_or_null("Bar") as ProgressBar
		if bar == null:
			continue
		if freq == Frequency.Type.NONE:
			_apply_slot_none(slot, bar, s)
		else:
			_apply_slot_colored(slot, bar, Frequency.color_of(freq), s)
		_apply_echo_icon_tint(bar, _echo_icon_base_color(freq, s), s)


func _apply_slot_colored(
		slot: PanelContainer,
		bar: ProgressBar,
		base: Color,
		s: Settings) -> void:
	var panel := slot.get_theme_stylebox("panel") as StyleBoxFlat
	if panel != null:
		var d := s.color_slot_bg_darkness
		panel.bg_color = Color(
				base.r * d, base.g * d, base.b * d, s.color_slot_bg_alpha)
		panel.border_color = Color(
				base.r, base.g, base.b, s.color_slot_border_alpha)
	var fill := bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill != null:
		fill.bg_color = base


func _apply_slot_none(
		slot: PanelContainer,
		bar: ProgressBar,
		s: Settings) -> void:
	var panel := slot.get_theme_stylebox("panel") as StyleBoxFlat
	if panel != null:
		panel.bg_color = s.color_slot_none_bg
		panel.border_color = s.color_slot_none_border
	var fill := bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill != null:
		fill.bg_color = s.color_slot_none_fill


func _apply_echo_icon_tint(
		bar: ProgressBar, base: Color, s: Settings) -> void:
	var icon := bar.get_node_or_null("EchoIcon") as CanvasItem
	if icon == null:
		return
	icon.modulate = base.lerp(Color.WHITE, s.color_icon_pastel_t)


func _echo_icon_base_color(freq: int, s: Settings) -> Color:
	if freq == Frequency.Type.NONE:
		return s.color_slot_none_echo_base
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
