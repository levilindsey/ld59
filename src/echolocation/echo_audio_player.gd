class_name EchoAudioPlayer
extends Node
## Minimal Phase 1 echo audio: plays an outgoing "chirp" one-shot on
## pulse emit and schedules a single delayed "return" one-shot.
## Phase 6 will expand to M-ray returns with pan derived from surface
## direction.


const _RETURN_DELAY_SEC := 0.3

@export var chirp_stream: AudioStream
@export var return_stream: AudioStream

var _chirp_player: AudioStreamPlayer
var _return_player: AudioStreamPlayer


func _ready() -> void:
	_chirp_player = AudioStreamPlayer.new()
	_chirp_player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	add_child(_chirp_player)

	_return_player = AudioStreamPlayer.new()
	_return_player.bus = _chirp_player.bus
	add_child(_return_player)

	if is_instance_valid(G.echo):
		G.echo.pulse_emitted.connect(_on_pulse_emitted)


func _on_pulse_emitted(pulse: EchoPulse) -> void:
	if chirp_stream != null:
		_chirp_player.stream = chirp_stream
		_chirp_player.play()

	if return_stream != null:
		await get_tree().create_timer(
				_RETURN_DELAY_SEC, false).timeout
		_return_player.stream = return_stream
		_return_player.play()
