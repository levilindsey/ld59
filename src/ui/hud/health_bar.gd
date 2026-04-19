class_name HealthBar
extends ProgressBar
## Binds this ProgressBar to the player's PlayerHealth node. Polls
## the player each frame so respawn / level reset naturally
## re-targets without needing to (dis)connect signals.
##
## Fills from green at full HP to red at low HP (linear interp over
## the `_WARN_RATIO`..`_HEALTHY_RATIO` band). When the player takes
## damage, the whole bar briefly flashes bright-white via `modulate`
## to draw the eye.


## Fill-color interpolation endpoints. Above `_HEALTHY_RATIO` the
## bar stays solid green; below `_WARN_RATIO` solid red; linearly
## interpolated in between.
const _HEALTHY_RATIO := 2.0 / 3.0
const _WARN_RATIO := 1.0 / 3.0
const _HEALTHY_COLOR := Color(0.3, 0.85, 0.3, 1.0)
const _WARN_COLOR := Color(0.95, 0.25, 0.25, 1.0)

## Duration of the white damage-flash over the modulate layer.
const _DAMAGE_FLASH_DURATION_SEC := 0.25
## Peak modulate multiplier during the flash (white-ish tint).
const _DAMAGE_FLASH_PEAK := Color(2.0, 2.0, 2.0, 1.0)


var _fill_style: StyleBoxFlat = null
var _last_known_health: int = -1
var _flash_tween: Tween = null


func _ready() -> void:
	min_value = 0
	max_value = 100
	value = 100
	show_percentage = false
	# The scene has a StyleBoxFlat assigned; grab it so we can mutate
	# its bg_color each frame based on the current HP ratio.
	var fill: StyleBox = get_theme_stylebox("fill")
	if fill is StyleBoxFlat:
		_fill_style = fill


func _process(_delta: float) -> void:
	var health := _find_player_health()
	if not is_instance_valid(health):
		return
	if max_value != health.max_health:
		max_value = health.max_health
	var new_health: int = health.current_health
	if value != new_health:
		value = new_health
	# Detect a damage event (health dropped since last frame) and
	# start the flash. Initialize on first observation so the
	# opening-frame set doesn't falsely flash.
	if _last_known_health >= 0 and new_health < _last_known_health:
		_play_damage_flash()
	_last_known_health = new_health
	_update_fill_color()


func _update_fill_color() -> void:
	if _fill_style == null:
		return
	var ratio: float = 0.0
	if max_value > 0.0:
		ratio = clampf(value / max_value, 0.0, 1.0)
	var mix_t: float = smoothstep(
			_WARN_RATIO, _HEALTHY_RATIO, ratio)
	_fill_style.bg_color = _WARN_COLOR.lerp(_HEALTHY_COLOR, mix_t)


func _play_damage_flash() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	modulate = _DAMAGE_FLASH_PEAK
	_flash_tween = create_tween()
	_flash_tween.tween_property(
			self, "modulate",
			Color(1.0, 1.0, 1.0, 1.0),
			_DAMAGE_FLASH_DURATION_SEC
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _find_player_health() -> PlayerHealth:
	if not is_instance_valid(G.level) or not is_instance_valid(G.level.player):
		return null
	return G.level.player.get_node_or_null("PlayerHealth")
