class_name Settings
extends Resource


# --- General configuration ---

@export var dev_mode := true
@export var draw_annotations := false
@export var show_debug_console := false
@export var show_debug_player_state := false

@export var start_in_game := true
@export var full_screen := false
@export var move_preview_windows_to_other_display := true
@export var mute_music := false
@export var pauses_on_focus_out := true
@export var is_screenshot_hotkey_enabled := true

@export var show_hud := true

# --- Game-specific configuration ---

@export var default_gravity_acceleration := 5000.0

@export var player_scene: PackedScene
@export var default_level_scene: PackedScene

## Debug / playtesting helper. When true, the player spawns with
## MAX_JUICE in every colored frequency so all pulse colors can be
## used immediately without hunting bugs.
@export var start_with_full_juice := false


@export_group("Colors / Frequency Palette")
## Authoritative palette for frequency/type hues. Applied to
## `Frequency.PALETTE` at startup (`Frequency.configure_palette`)
## and pushed into the level's `TerrainSettings` so C++ tile tint
## stays in sync.
@export var color_frequency_none := Color(0, 0, 0, 0)
@export var color_frequency_indestructible := Color(0.12, 0.12, 0.14, 1)
@export var color_frequency_red := Color(0.95, 0.38, 0.48, 1)
@export var color_frequency_green := Color(0.28, 0.82, 0.65, 1)
@export var color_frequency_blue := Color(0.45, 0.80, 0.98, 1)
@export var color_frequency_liquid := Color(0.16, 0.36, 0.68, 1)
@export var color_frequency_sand := Color(0.80, 0.74, 0.52, 1)
## Yellow / yellow-orange frequency. Biased toward yellow over
## orange by default.
@export var color_frequency_yellow := Color(0.95, 0.82, 0.22, 1)
## Alpha applied to WEB_* variants. RGB is taken from the base
## frequency (e.g., WEB_RED.rgb = color_frequency_red.rgb).
@export_range(0.0, 1.0) var color_frequency_web_alpha := 0.55


@export_group("Colors / Derivation")
## Shared formulas applied to derive juice-slot and health-bar bg/
## border from a base fill color. See `JuiceBarRow` and `HealthBar`.
## bg_color = Color(fill.rgb * slot_bg_darkness, slot_bg_alpha).
@export_range(0.0, 1.0) var color_slot_bg_darkness := 0.25
@export_range(0.0, 1.0) var color_slot_bg_alpha := 0.85
## border_color = Color(fill.rgb, slot_border_alpha).
@export_range(0.0, 1.0) var color_slot_border_alpha := 0.45
## icon.modulate = lerp(base_color, WHITE, icon_pastel_t). Higher
## values read as lighter + less saturated (both shift together
## when lerping toward white).
@export_range(0.0, 1.0) var color_icon_pastel_t := 0.4


@export_group("Colors / HUD / Health Bar")
## Fill color at full HP (interp upper endpoint).
@export var color_health_healthy := Color(0.3, 0.85, 0.3, 1.0)
## Fill color at low HP (interp lower endpoint).
@export var color_health_warn := Color(0.95, 0.25, 0.25, 1.0)
## Peak modulate multiplier during the damage flash.
@export var color_health_damage_flash_peak := Color(2.0, 2.0, 2.0, 1.0)


@export_group("Colors / HUD / Juice None Slot")
## The NONE juice slot is gray-themed, not palette-driven, so bg /
## border / fill are explicit rather than derived from a base hue.
@export var color_slot_none_bg := Color(0.1, 0.1, 0.12, 0.7)
@export var color_slot_none_border := Color(0.55, 0.55, 0.6, 0.5)
@export var color_slot_none_fill := Color(0.55, 0.55, 0.6, 0.35)
## Fallback base used as the echo-icon hue on the NONE slot.
@export var color_slot_none_echo_base := Color(0.55, 0.55, 0.6, 1.0)


@export_group("Colors / HUD / Credits")
@export var color_credits_font := Color(0.98, 0.98, 0.94, 1)
@export var color_credits_outline := Color(0.12, 0.10, 0.18, 1)


@export_group("Colors / Shaders / Damage Flash")
## Full-body red flash applied to the player and enemies on damage,
## via the shared `player_damage_flash.gdshader`.
@export var color_damage_flash := Color(1.0, 0.2, 0.2, 1.0)
## Lighter red for the outline ring pulse.
@export var color_damage_pulse := Color(1.0, 0.35, 0.35, 1.0)


@export_group("Colors / Scene Modulates")
## Modulates on white sprites where the value controls opacity;
## RGB=(1,1,1) keeps the sprite unchanged, alpha controls blend.
@export var color_web_body_modulate := Color(1, 1, 1, 0.55)
@export var color_web_strand_modulate := Color(1, 1, 1, 0.4)
@export var color_bug_glow_modulate := Color(1, 1, 1, 0.35)


@export_group("Logs")
## Logs with these categories won't be shown.
@export var excluded_log_categories: Array[StringName] = [
	#ScaffolderLog.CATEGORY_DEFAULT,
	#ScaffolderLog.CATEGORY_CORE_SYSTEMS,
	ScaffolderLog.CATEGORY_SYSTEM_INITIALIZATION,
	ScaffolderLog.CATEGORY_PLAYER_ACTIONS,
	#ScaffolderLog.CATEGORY_INTERACTION,
	#ScaffolderLog.CATEGORY_BEHAVIORS,
	#ScaffolderLog.CATEGORY_GAME_STATE,
]
## If true, warning logs will be shown regardless of category filtering.
@export var force_include_log_warnings := true
@export var include_category_in_logs := true
@export var include_peer_id_in_logs := true
@export var verbosity := ScaffolderLog.Verbosity.NORMAL
@export_group("")
