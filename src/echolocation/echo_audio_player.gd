class_name EchoAudioPlayer
extends Node
## Synthesizes and plays echolocation audio: an outgoing "chirp" on
## every pulse emit, and one "ping" per bounce-back (fired by
## `EcholocationRenderer.ping_fired`). Each return-ping plays at the
## scheduled time computed from the pulse's ray-cast hit distance, so
## nearby surfaces ping back sooner than distant ones. Volume is
## attenuated by hit distance. Streams are generated as AudioStreamWAV
## resources at _ready so the project carries no authored audio
## dependencies for these sounds.
##
## Uses small round-robin pools of AudioStreamPlayers so overlapping
## pulses + pings don't cut each other off. Pitch is scaled by the
## pulse's frequency enum so RED/GREEN/BLUE sound distinct without
## needing multiple baked streams.


const _SAMPLE_RATE := 22050

const _CHIRP_DURATION_SEC := 0.16
const _CHIRP_START_HZ := 900.0
const _CHIRP_END_HZ := 220.0

const _PING_DURATION_SEC := 0.12
const _PING_HZ := 330.0

## Number of simultaneous outgoing chirp players.
const _CHIRP_POOL_SIZE := 4

## Number of simultaneous ping players. A single pulse can schedule
## up to 24 pings; while they're spread across ~1 second as the echo
## travels + returns, 8 overlapping slots is plenty for typical
## player pacing.
const _PING_POOL_SIZE := 8

## Attenuation reference distance (world px) for ping volume. Hits at
## this range play at `return_volume_db`; closer hits play unchanged,
## further hits drop by ~6 dB per doubling of distance.
const _PING_ATTENUATION_REFERENCE_PX := 100.0

## Floor for distance-attenuated ping volume, in dB below
## `return_volume_db`. Prevents far-range pings from going silent.
const _PING_ATTENUATION_FLOOR_DB := -18.0

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
## Return pings use `AudioStreamPlayer2D` so Godot's 2D audio engine
## auto-pans based on the ping's `global_position` relative to the
## scene Camera2D. Built-in distance attenuation is disabled
## (`attenuation = 0`) so the custom `volume_db` curve in
## `_on_ping_fired` stays the single source of distance-volume truth.
var _return_pool: Array[AudioStreamPlayer2D] = []
var _chirp_cursor: int = 0
var _return_cursor: int = 0


func _ready() -> void:
	_chirp_stream = _build_chirp_stream()
	_return_stream = _build_ping_stream()

	var bus := "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	_chirp_pool = _build_chirp_pool(
			_CHIRP_POOL_SIZE, _chirp_stream, bus, chirp_volume_db)
	_return_pool = _build_return_pool(
			_PING_POOL_SIZE, _return_stream, bus, return_volume_db)

	if is_instance_valid(G.echo):
		G.echo.pulse_emitted.connect(_on_pulse_emitted)
		G.echo.ping_fired.connect(_on_ping_fired)
	else:
		G.warning(
				"EchoAudioPlayer: G.echo not ready; "
				+ "no echo audio will play")


func _on_pulse_emitted(pulse: EchoPulse) -> void:
	var pitch: float = _PITCH_BY_FREQUENCY.get(pulse.frequency, 1.0)

	var chirp: AudioStreamPlayer = _chirp_pool[_chirp_cursor]
	_chirp_cursor = (_chirp_cursor + 1) % _CHIRP_POOL_SIZE
	chirp.pitch_scale = pitch
	chirp.play()


func _on_ping_fired(ping: EchoPing) -> void:
	var pitch: float = _PITCH_BY_FREQUENCY.get(ping.frequency, 1.0) * 1.1
	# Distance attenuation: log10(1 + dist/ref) * 20 dB gives a gentle
	# curve — nearby hits stay near full volume, distant hits fade.
	# Clamped at a floor so the very farthest hits stay audible.
	var attenuation_db: float = -20.0 * log(
			1.0 + ping.hit_distance_px / _PING_ATTENUATION_REFERENCE_PX
	) / log(10.0)
	attenuation_db = maxf(attenuation_db, _PING_ATTENUATION_FLOOR_DB)

	var ret: AudioStreamPlayer2D = _return_pool[_return_cursor]
	_return_cursor = (_return_cursor + 1) % _PING_POOL_SIZE
	ret.pitch_scale = pitch
	ret.volume_db = return_volume_db + attenuation_db
	# Position in world — the 2D audio engine computes stereo pan
	# from this relative to the active Camera2D's global_position.
	ret.global_position = ping.world_pos
	ret.play()


func _build_chirp_pool(
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


func _build_return_pool(
		size: int,
		stream: AudioStream,
		bus: String,
		volume_db: float,
) -> Array[AudioStreamPlayer2D]:
	var pool: Array[AudioStreamPlayer2D] = []
	pool.resize(size)
	for i in range(size):
		var player := AudioStreamPlayer2D.new()
		player.stream = stream
		player.bus = bus
		player.volume_db = volume_db
		# Disable the engine's built-in inverse-distance attenuation
		# so our custom volume_db math in `_on_ping_fired` is the sole
		# distance-volume source. Pan still auto-computes from
		# global_position relative to the Camera2D.
		player.attenuation = 0.0
		# Generous max_distance so the hard cutoff at the edge of
		# audible range doesn't clip pings we want to stay audible;
		# our volume_db floor handles the quiet tail.
		player.max_distance = 4000.0
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
