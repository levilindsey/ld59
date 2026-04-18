class_name FrequencyChip
extends PanelContainer
## HUD indicator that shows the player's current echolocation
## frequency as a colored chip. Polls `G.level.player.current_frequency`
## every frame and refreshes the swatch + label on change.


@onready var _swatch: ColorRect = $HBox/Swatch
@onready var _label: Label = $HBox/Label


var _last_shown_frequency: int = -1


func _ready() -> void:
	_refresh(Frequency.Type.NONE)


func _process(_delta: float) -> void:
	var player := _get_player()
	var freq: int = (
			player.current_frequency if is_instance_valid(player)
			else Frequency.Type.NONE)
	if freq == _last_shown_frequency:
		return
	_refresh(freq)


func _refresh(freq: int) -> void:
	_last_shown_frequency = freq
	_swatch.color = Frequency.color_of(freq)
	_label.text = _name_for(freq)


func _get_player() -> Player:
	if is_instance_valid(G.level) and is_instance_valid(G.level.player):
		return G.level.player
	return null


func _name_for(freq: int) -> String:
	match freq:
		Frequency.Type.RED: return "RED"
		Frequency.Type.GREEN: return "GREEN"
		Frequency.Type.BLUE: return "BLUE"
		_: return "--"
