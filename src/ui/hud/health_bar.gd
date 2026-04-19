class_name HealthBar
extends PanelContainer
## Binds the inner `Bar` ProgressBar to the player's PlayerHealth
## node. Polls the player each frame so respawn / level reset
## naturally re-targets without needing to (dis)connect signals.
##
## The fill color interpolates from green at full HP to red at low
## HP. The panel's background + border + the heart icon modulate
## all follow the same hue so the whole bar reads as one shifting
## color:
##   - bg    = fill.rgb * _BG_DARKEN at _BG_ALPHA
##   - border = fill.rgb at _BORDER_ALPHA
##   - heart = lerp(fill, WHITE, _HEART_PASTEL_T)
##
## When the player takes damage the whole panel briefly modulates
## bright-white to draw the eye.


## Fill-color interpolation endpoints. Above `_HEALTHY_RATIO` the
## bar stays solid at the "healthy" color; below `_WARN_RATIO`
## solid at the "warn" color; linearly interpolated in between.
## Colors come from Settings so the whole HUD palette stays
## centrally tunable.
const _HEALTHY_RATIO := 2.0 / 3.0
const _WARN_RATIO := 1.0 / 3.0

## Duration of the white damage-flash over the modulate layer.
const _DAMAGE_FLASH_DURATION_SEC := 0.25


var _panel_style: StyleBoxFlat = null
var _fill_style: StyleBoxFlat = null
var _last_known_health: int = -1
var _flash_tween: Tween = null

@onready var _bar: ProgressBar = $Bar
@onready var _heart_icon: TextureRect = $Bar/HeartIcon


func _ready() -> void:
	var panel: StyleBox = get_theme_stylebox("panel")
	if panel is StyleBoxFlat:
		_panel_style = panel
	var fill: StyleBox = _bar.get_theme_stylebox("fill")
	if fill is StyleBoxFlat:
		_fill_style = fill


func _process(_delta: float) -> void:
	var health := _find_player_health()
	if not is_instance_valid(health):
		return
	if _bar.max_value != health.max_health:
		_bar.max_value = health.max_health
	var new_health: int = health.current_health
	if _bar.value != new_health:
		_bar.value = new_health
	# Detect a damage event (health dropped since last frame) and
	# start the flash. Initialize on first observation so the
	# opening-frame set doesn't falsely flash.
	if _last_known_health >= 0 and new_health < _last_known_health:
		_play_damage_flash()
	_last_known_health = new_health
	_update_theme_colors()


func _update_theme_colors() -> void:
	if _fill_style == null or _panel_style == null:
		return
	var s: Settings = G.settings
	if s == null:
		return
	var ratio: float = 0.0
	if _bar.max_value > 0.0:
		ratio = clampf(_bar.value / _bar.max_value, 0.0, 1.0)
	var mix_t: float = smoothstep(
			_WARN_RATIO, _HEALTHY_RATIO, ratio)
	var fill_color: Color = s.color_health_warn.lerp(
			s.color_health_healthy, mix_t)
	_fill_style.bg_color = fill_color
	var darken := s.color_slot_bg_darkness
	_panel_style.bg_color = Color(
			fill_color.r * darken,
			fill_color.g * darken,
			fill_color.b * darken,
			s.color_slot_bg_alpha)
	_panel_style.border_color = Color(
			fill_color.r,
			fill_color.g,
			fill_color.b,
			s.color_slot_border_alpha)
	if _heart_icon != null:
		_heart_icon.modulate = fill_color.lerp(
				Color.WHITE, s.color_icon_pastel_t)


func _play_damage_flash() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	var peak: Color = Color(2.0, 2.0, 2.0, 1.0)
	if G.settings != null:
		peak = G.settings.color_health_damage_flash_peak
	modulate = peak
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
