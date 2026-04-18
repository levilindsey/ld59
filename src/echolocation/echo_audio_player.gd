class_name EchoAudioPlayer
extends Node
## Synthesizes and plays echolocation audio: an outgoing "chirp" on
## every pulse emit, plus a delayed "return ping" simulating a
## first-surface reflection. Streams are generated as AudioStreamWAV
## resources at _ready so the project carries no authored audio
## dependencies for these sounds.
##
## Uses a small round-robin pool of AudioStreamPlayers so overlapping
## pulses don't cut each other off. Pitch is scaled by the pulse's
## frequency enum so RED/GREEN/BLUE sound distinct without needing
## multiple baked streams.


const _SAMPLE_RATE := 22050

const _CHIRP_DURATION_SEC := 0.16
const _CHIRP_START_HZ := 900.0
const _CHIRP_END_HZ := 220.0

const _PING_DURATION_SEC := 0.12
const _PING_HZ := 330.0

## Delay after emit before the return ping plays.
const _RETURN_DELAY_SEC := 0.28

const _POOL_SIZE := 4

## Pitch multipliers keyed by Frequency.Type. Missing keys fall back
## to 1.0 — the RED/GREEN/BLUE trio is the only set that matters.
const _PITCH_BY_FREQUENCY := {
	Frequency.Type.RED: 0.85,
	Frequency.Type.GREEN: 1.0,
	Frequency.Type.BLUE: 1.25,
}


@export_range(-40.0, 12.0) var chirp_volume_db := -6.0
@export_range(-40.0, 12.0) var return_volume_db := -12.0


var _chirp_stream: AudioStreamWAV
var _return_stream: AudioStreamWAV

var _chirp_pool: Array[AudioStreamPlayer] = []
var _return_pool: Array[AudioStreamPlayer] = []
var _chirp_cursor: int = 0
var _return_cursor: int = 0


func _ready() -> void:
	_chirp_stream = _build_chirp_stream()
	_return_stream = _build_ping_stream()

	var bus := "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	_chirp_pool = _build_pool(_POOL_SIZE, _chirp_stream, bus, chirp_volume_db)
	_return_pool = _build_pool(_POOL_SIZE, _return_stream, bus, return_volume_db)

	if is_instance_valid(G.echo):
		G.echo.pulse_emitted.connect(_on_pulse_emitted)
	else:
		G.warning(
				"EchoAudioPlayer: G.echo not ready; "
				+ "no echo audio will play")


func _on_pulse_emitted(pulse: EchoPulse) -> void:
	var pitch: float = _PITCH_BY_FREQUENCY.get(pulse.frequency, 1.0)

	var chirp: AudioStreamPlayer = _chirp_pool[_chirp_cursor]
	_chirp_cursor = (_chirp_cursor + 1) % _POOL_SIZE
	chirp.pitch_scale = pitch
	chirp.play()

	# Return ping is slightly higher-pitched and delayed. Use a
	# one-shot timer so we don't block _on_pulse_emitted.
	await get_tree().create_timer(_RETURN_DELAY_SEC, false).timeout

	var ret: AudioStreamPlayer = _return_pool[_return_cursor]
	_return_cursor = (_return_cursor + 1) % _POOL_SIZE
	ret.pitch_scale = pitch * 1.1
	ret.play()


func _build_pool(
		size: int,
		stream: AudioStream,
		bus: String,
		volume_db: float,
) -> Array[AudioStreamPlayer]:
	var pool: Array[AudioStreamPlayer] = []
	pool.resize(size)
	for i in range(size):
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.bus = bus
		player.volume_db = volume_db
		add_child(player)
		pool[i] = player
	return pool


func _build_chirp_stream() -> AudioStreamWAV:
	var sample_count := int(_SAMPLE_RATE * _CHIRP_DURATION_SEC)
	var pcm := PackedByteArray()
	pcm.resize(sample_count * 2)

	for i in range(sample_count):
		var t := float(i) / _SAMPLE_RATE
		var progress := t / _CHIRP_DURATION_SEC
		# Exponential frequency glide from start → end Hz.
		var hz: float = _CHIRP_START_HZ * pow(
				_CHIRP_END_HZ / _CHIRP_START_HZ, progress)
		# Phase = integral of 2π·hz(t) dt. Approximate by summing.
		# (Since we sample densely, a per-sample running sum is fine.)
		var envelope := _chirp_envelope(progress)
		var sample: float = sin(TAU * hz * t) * envelope
		_write_sample(pcm, i, sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = _SAMPLE_RATE
	stream.stereo = false
	stream.data = pcm
	return stream


func _build_ping_stream() -> AudioStreamWAV:
	var sample_count := int(_SAMPLE_RATE * _PING_DURATION_SEC)
	var pcm := PackedByteArray()
	pcm.resize(sample_count * 2)

	for i in range(sample_count):
		var t := float(i) / _SAMPLE_RATE
		var progress := t / _PING_DURATION_SEC
		var envelope := _ping_envelope(progress)
		# Two sines stacked an octave apart for a more "bell" feel.
		var sample: float = (
				sin(TAU * _PING_HZ * t) * 0.7
				+ sin(TAU * _PING_HZ * 2.0 * t) * 0.3
		) * envelope
		_write_sample(pcm, i, sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = _SAMPLE_RATE
	stream.stereo = false
	stream.data = pcm
	return stream


## Chirp envelope: fast attack, long tapered decay.
func _chirp_envelope(progress: float) -> float:
	var attack := 0.05
	if progress < attack:
		return progress / attack
	return pow(1.0 - (progress - attack) / (1.0 - attack), 1.8)


## Ping envelope: instant attack, exponential decay.
func _ping_envelope(progress: float) -> float:
	return exp(-4.0 * progress)


func _write_sample(pcm: PackedByteArray, index: int, value: float) -> void:
	var clamped := clampf(value, -1.0, 1.0)
	var int16 := int(clamped * 32767.0)
	var byte_index := index * 2
	pcm[byte_index] = int16 & 0xff
	pcm[byte_index + 1] = (int16 >> 8) & 0xff
