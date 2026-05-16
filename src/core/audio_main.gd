class_name AudioMain
extends Node2D


@export var theme_fade_duration_sec := 0.2

@export var mute_volume := -80.0

@export var main_theme_volume := 0.0
@export var menu_theme_volume := 0.0

@onready var STREAM_PLAYERS_BY_NAME := {
	"main_theme" = %MainTheme,
	"end_theme" = %EndTheme,
	"menu_theme" = %MainTheme,
	"player_jump" = %PlayerJump,
	"player_land" = %PlayerLand,
	"player_death" = %PlayerDeath,
	"player_little_meow" = %PlayerLittleMeow,
	"player_damage" = %PlayerDamage,
	"player_echo" = %PlayerEcho,
	"player_eat_bug" = %PlayerEatBug,
	"player_select" = %PlayerSelect,
	"player_coin" = %PlayerCoin,
	"player_splash" = %PlayerSplash,
	"click" = %ClickStreamPlayer,
	"godot_splash" = %ClickStreamPlayer,
	"scg_splash" = %SnoringCatStreamPlayer,
	"success" = %SuccessCadenceStreamPlayer,
	"all_coins" = %CoinCadenceStreamPlayer,
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
	# Looping fallback: Godot 4's web AudioStreamWAV loop_mode is
	# unreliable on the AudioWorklet backend (loops fine on desktop,
	# doesn't loop on Chrome/Firefox web). Manually re-trigger play
	# on `finished`. Gated by `current_theme` so a stream that was
	# faded-out + paused doesn't auto-restart.
	%MainTheme.finished.connect(_on_theme_finished.bind(%MainTheme))
	%EndTheme.finished.connect(_on_theme_finished.bind(%EndTheme))


func _on_theme_finished(stream_player: AudioStreamPlayer) -> void:
	if current_theme != stream_player:
		return
	stream_player.play()


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


func fade_to_end_theme() -> void:
	fade_to_theme("end_theme")


## Immediately fades out the current theme, waits `delay_sec`
## seconds, then fades in the end theme. Used on game-win so
## there's a beat of silence between the main theme stopping
## and the end theme starting.
func fade_to_end_theme_after(delay_sec: float) -> void:
	if is_instance_valid(current_theme):
		fade_out(current_theme)
		current_theme = null
	if delay_sec > 0.0:
		await get_tree().create_timer(delay_sec, true).timeout
	current_theme = STREAM_PLAYERS_BY_NAME["end_theme"]
	fade_in(current_theme, initial_volumes["end_theme"])


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
		"success":
			play.call("success")
			pass
		"failure":
			play.call("failure")
			pass
		"detach":
			play.call("player_little_meow")
			pass
		"jump":
			play.call("player_jump")
			pass
		"land":
			play.call("player_land")
			pass
		"damage":
			play.call("player_damage")
			pass
		"death":
			play.call("player_death")
			pass
		"eat_bug":
			play.call("player_eat_bug")
			pass
		"echo":
			play.call("player_echo")
			pass
		"select":
			play.call("player_select")
			pass
		"coin":
			play.call("player_coin")
			pass
		"splash":
			play.call("player_splash")
			pass
		"all_coins":
			play.call("all_coins")
			pass
		"walk":
			pass
		_:
			G.fatal()


func stop_player_sound(sound_name: String) -> void:
	match sound_name:
		"walk":
			pass


## Plays a player sound after a delay, running the timer on
## AudioMain itself so the sound fires even if the originating node
## (e.g. the player on death) has been queue_freed in the interim.
func play_player_sound_delayed(
		sound_name: String,
		delay_sec: float,
		force_restart := true) -> void:
	if delay_sec > 0.0:
		await get_tree().create_timer(delay_sec, true).timeout
	play_player_sound(sound_name, force_restart)
