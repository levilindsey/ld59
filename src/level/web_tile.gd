class_name WebTile
extends Area2D
## Placeable spider-web tile. Slows the player while overlapping
## (detected via a sensor Area2D under the player on the `web_tile`
## physics layer). Non-colliding for everyone else, so spiders and
## bugs traverse it freely.
##
## Takes damage from matching-frequency pulses. Destroys itself at 0
## health.


const _WEB_LAYER_BIT := 1 << 9

## Group name every runtime WebTile joins so the echolocation
## renderer can iterate them alongside bugs + enemies when packing
## the tag-halo uniform. Mirrors the "enemies" / "bug_spawn_regions"
## group pattern.
const GROUP := "web_tiles"

## Matching-frequency pulse damage at the pulse center, as a
## fraction of `max_health`. 1.0 means a point-blank pulse is
## enough to shred any web in one hit. Mirrors Enemy's constants
## so web destruction feels consistent with enemy destruction.
const _CLOSE_RANGE_DAMAGE_FRACTION := 1.0
## Matching-frequency pulse damage at the pulse's max radius, as a
## fraction of `max_health`. 1/5 means five matching pulses at the
## edge of the shell are needed to clear a web.
const _FAR_RANGE_DAMAGE_FRACTION := 0.2


## Frequency this web tile belongs to. Drives both its tint and which
## pulse frequency can damage it.
@export var frequency: Frequency.Type = Frequency.Type.GREEN
## 1/5 the 255 baseline of a normal terrain cell — webs are meant
## to feel flimsy so the player can burn through them quickly.
@export_range(1, 500) var max_health: int = 51

## World-space radius of the echolocation tag halo. Read by
## `EcholocationRenderer` to synthesize a pointillist silhouette so
## pulses reveal the web the same way they reveal bugs. ~8 matches
## the 16×16 tile's visual half-extent.
@export_range(2.0, 48.0) var tag_radius_px: float = 8.0

var _health: int


func _ready() -> void:
	monitoring = false
	monitorable = true
	collision_layer = _WEB_LAYER_BIT
	collision_mask = 0
	_health = max_health
	add_to_group(GROUP)
	_apply_frequency_tint()
	_apply_settings_modulates()
	if is_instance_valid(G.echo):
		G.echo.pulse_emitted.connect(_on_pulse_emitted)


func _apply_settings_modulates() -> void:
	if G.settings == null:
		return
	var body := get_node_or_null("Body") as CanvasItem
	if body != null:
		body.modulate = G.settings.color_web_body_modulate
	var strand_a := get_node_or_null("StrandA") as CanvasItem
	if strand_a != null:
		strand_a.modulate = G.settings.color_web_strand_modulate
	var strand_b := get_node_or_null("StrandB") as CanvasItem
	if strand_b != null:
		strand_b.modulate = G.settings.color_web_strand_modulate


func _on_pulse_emitted(pulse: EchoPulse) -> void:
	if pulse.frequency != frequency:
		return
	var offset := global_position - pulse.center
	var max_radius_sq := pulse.max_radius_px * pulse.max_radius_px
	if offset.length_squared() > max_radius_sq:
		return
	# Distance-attenuated damage, mirroring Enemy.receive_pulse: a
	# point-blank matching pulse clears the web in one hit, while an
	# edge-of-shell pulse takes `1 / _FAR_RANGE_DAMAGE_FRACTION` hits.
	# The caller's `pulse.damage` is intentionally ignored — web
	# destruction is gated by proximity, not pulse authored damage.
	var distance := offset.length()
	var t := clampf(
			distance / maxf(pulse.max_radius_px, 1.0), 0.0, 1.0)
	var fraction := lerpf(
			_CLOSE_RANGE_DAMAGE_FRACTION,
			_FAR_RANGE_DAMAGE_FRACTION,
			t)
	var attenuated_damage := int(ceil(float(max_health) * fraction))
	_health -= attenuated_damage
	if _health <= 0:
		queue_free()


func _apply_frequency_tint() -> void:
	var color := Frequency.color_of(frequency)
	modulate = Color(color.r, color.g, color.b, modulate.a)
