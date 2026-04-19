class_name AudioMain
extends Node2D


@export var theme_fade_duration_sec := 0.2

@export var mute_volume := -80.0

@export var main_theme_volume := 0.0
@export var menu_theme_volume := 0.0

@onready var STREAM_PLAYERS_BY_NAME := {
	"main_theme" = %GirlTheme,
	"menu_theme" = %GirlTheme,
	"girl_jump" = %GirlJump,
	"click" = %ClickStreamPlayer,
	"godot_splash" = %ClickStreamPlayer,
	"scg_splash" = %SnoringCatStreamPlayer,
	"success" = %SuccessCadenceStreamPlayer,
	"failure" = %FailureCadenceStreamPlayer,
	"achievement" = %AchievementStreamPlayer,
}

var initial_volumes := {}

var current_theme: AudioStreamPlayer


func _enter_tree() -> void:
	G.audio = self


func _ready() -> void:
	for player_name in STREAM_PLAYERS_BY_NAME:
		var player: AudioStreamPlayer = STREAM_PLAYERS_BY_NAME[player_name]
		initial_volumes[player_name] = player.volume_db


func play_sound(sound_name: StringName, force_restart := false) -> void:
	if not G.ensure(STREAM_PLAYERS_BY_NAME.has(sound_name)):
		return

	var stream_player: AudioStreamPlayer = STREAM_PLAYERS_BY_NAME[sound_name]
	if not stream_player.playing or force_restart:
		stream_player.play.call()


func stop_sound(sound_name: StringName) -> void:
	if not G.ensure(STREAM_PLAYERS_BY_NAME.has(sound_name)):
		return

	var stream_player: AudioStreamPlayer = STREAM_PLAYERS_BY_NAME[sound_name]
	if stream_player.playing:
		stream_player.stop()


func fade_to_theme(theme_name: String) -> void:
	if is_instance_valid(current_theme):
		fade_out(current_theme)
	current_theme = STREAM_PLAYERS_BY_NAME[theme_name]
	fade_in(current_theme, initial_volumes[theme_name])


func fade_to_menu_theme() -> void:
	fade_to_theme("menu_theme")


func fade_to_main_theme() -> void:
	fade_to_theme("main_theme")


func fade_in(stream_player: AudioStreamPlayer, volume: float) -> void:
	if G.settings.mute_music:
		volume = mute_volume

	if not stream_player.playing:
		stream_player.volume_db = mute_volume
		stream_player.play.call()

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(
		stream_player,
		"volume_db",
		volume,
		theme_fade_duration_sec)

	await tween.step_finished
	# Ensure the stream is still playing, just in case we somehow end up with
	# overlapping tweens (the latest tween should end up winning).
	stream_player.stream_paused = false


func fade_out(stream_player: AudioStreamPlayer) -> void:
	if not stream_player.playing:
		return

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(
		stream_player,
		"volume_db",
		mute_volume,
		theme_fade_duration_sec)

	await tween.step_finished
	# Ensure the stream is still playing, just in case we somehow end up with
	# overlapping tweens (the latest tween should end up winning).
	stream_player.stream_paused = true


func play_player_sound(
	sound_name: String,
	force_restart := false
) -> void:
	var play = func(p_sound_name: StringName):
		play_sound(p_sound_name, force_restart)

	match sound_name:
		"game_win":
			#play.call("game_win")
			pass
		"spawn":
			#play.call("spawn")
			pass
		"jump":
			play.call("girl_jump")
			pass
		"land":
			pass
		"walk":
			pass
		_:
			G.fatal()


func stop_player_sound(sound_name: String) -> void:
	match sound_name:
		"walk":
			pass
