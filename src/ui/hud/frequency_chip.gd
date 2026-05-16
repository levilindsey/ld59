class_name FrequencyChip
extends PanelContainer
## HUD indicator that shows the player's current echolocation
## frequency as a colored chip, plus a narrow cooldown fill that
## tracks the pulse-ready timer. Polls `G.level.player` every
## frame.


@onready var _swatch: ColorRect = $VBox/HBox/Swatch
@onready var _label: Label = $VBox/HBox/Label
@onready var _cooldown_track: ColorRect = $VBox/CooldownTrack
@onready var _cooldown_fill: ColorRect = $VBox/CooldownTrack/CooldownFill


var _last_shown_frequency: int = -1


func _ready() -> void:
	_refresh(Frequency.Type.NONE)


func _process(_delta: float) -> void:
	var player := _get_player()
	var freq: int = (
			player.current_frequency if is_instance_valid(player)
			else Frequency.Type.NONE)
	if freq != _last_shown_frequency:
		_refresh(freq)
	_update_cooldown(player)


func _refresh(freq: int) -> void:
	_last_shown_frequency = freq
	_swatch.color = Frequency.color_of(freq)
	_label.text = _name_for(freq)


## Drive the cooldown fill's width from the player's cooldown
## fraction (0 = just fired, 1 = ready). Fill is tinted to the
## current frequency color when there's one selected, white for
## NONE.
func _update_cooldown(player: Player) -> void:
	if not is_instance_valid(player):
		_cooldown_fill.visible = false
		return
	_cooldown_fill.visible = true
	var fraction: float = clampf(player.get_cooldown_fraction(), 0.0, 1.0)
	var track_width: float = _cooldown_track.size.x
	_cooldown_fill.size = Vector2(track_width * fraction, _cooldown_track.size.y)
	if _last_shown_frequency == Frequency.Type.NONE:
		_cooldown_fill.color = Color(0.98, 0.98, 0.94, 1.0)
	else:
		_cooldown_fill.color = Frequency.color_of(_last_shown_frequency)


func _get_player() -> Player:
	if is_instance_valid(G.level) and is_instance_valid(G.level.player):
		return G.level.player
	return null


func _name_for(freq: int) -> String:
	match freq:
		Frequency.Type.RED: return "RED"
		Frequency.Type.GREEN: return "GREEN"
		Frequency.Type.BLUE: return "BLUE"
		Frequency.Type.YELLOW: return "YELLOW"
		_: return "--"
