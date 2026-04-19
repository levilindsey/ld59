class_name AudioMain
extends Node2D


signal cadence_sequence_finished(which: String)


const _POST_CADENCE_GAP_SEC := 0.5


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

# True while a win/death cadence is playing. While set, fade_to_theme
# defers its work so the theme change doesn't un-pause the music
# underneath the cadence.
var _is_cadence_active := false
var _post_cadence_theme := ""


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
	if _is_cadence_active:
		# The cadence owns the theme's pause state until it finishes;
		# stash the requested destination and apply it post-cadence.
		_post_cadence_theme = theme_name
		return
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


func play_win_cadence() -> void:
	_play_cadence(%SuccessCadenceStreamPlayer, "win")


func play_death_cadence() -> void:
	_play_cadence(%FailureCadenceStreamPlayer, "death")


func _play_cadence(player: AudioStreamPlayer, which: String) -> void:
	_is_cadence_active = true
	_post_cadence_theme = ""
	_pause_current_theme()
	if player.finished.is_connected(_on_cadence_finished):
		player.finished.disconnect(_on_cadence_finished)
	player.finished.connect(
		_on_cadence_finished.bind(which), CONNECT_ONE_SHOT)
	player.play()


func _pause_current_theme() -> void:
	if not is_instance_valid(current_theme):
		return
	current_theme.stream_paused = true


func _resume_current_theme() -> void:
	if not is_instance_valid(current_theme):
		return
	current_theme.stream_paused = false


func _on_cadence_finished(which: String) -> void:
	# Use a process-always timer so the gap still ticks while the
	# tree is paused (CREDITS state pauses the tree on win).
	await get_tree().create_timer(
		_POST_CADENCE_GAP_SEC, true, false, true).timeout
	_is_cadence_active = false
	if _post_cadence_theme.is_empty():
		_resume_current_theme()
	else:
		var theme := _post_cadence_theme
		_post_cadence_theme = ""
		fade_to_theme(theme)
	cadence_sequence_finished.emit(which)


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
