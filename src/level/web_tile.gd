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


## Frequency this web tile belongs to. Drives both its tint and which
## pulse frequency can damage it.
@export var frequency: Frequency.Type = Frequency.Type.GREEN
## 1/5 the 255 baseline of a normal terrain cell — webs are meant
## to feel flimsy so the player can burn through them quickly.
@export_range(1, 500) var max_health: int = 51

var _health: int


func _ready() -> void:
	monitoring = false
	monitorable = true
	collision_layer = _WEB_LAYER_BIT
	collision_mask = 0
	_health = max_health
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
	if offset.length_squared() > pulse.max_radius_px * pulse.max_radius_px:
		return
	_health -= pulse.damage
	if _health <= 0:
		queue_free()


func _apply_frequency_tint() -> void:
	var color := Frequency.color_of(frequency)
	modulate = Color(color.r, color.g, color.b, modulate.a)
