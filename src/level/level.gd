class_name Level
extends Node2D


## Fired when any coin is collected. `index` is the coin's slot in
## the "KITTEN" ordering (0..5). `world_pos` is where the coin was
## sitting so VFX can spawn from that position.
signal coin_collected(index: int, world_pos: Vector2)
## Fired when `reset()` clears the collected-coin flags. HUD listens
## to hide the indicator; `PersistentCoinSpawn` listens to re-spawn
## any coins that had been consumed last run.
signal coin_state_reset


const COIN_COUNT := 6

const _RESET_READY_TO_START_GAME_DELAY_SEC := 0.3
const _GAME_OVER_READY_TO_RESET_DELAY_SEC := 1.5

const _PLAYER_CAMERA_OFFSET := Vector2(0, -10)

## Duration of the alpha fade-out applied to every enemy when the
## player wins. Enemies are already frozen in place by their own
## `has_won` early-out; this fade dissolves them so the victory
## framing isn't cluttered by now-inert threats.
const _ENEMY_WIN_FADE_OUT_SEC := 1.0
## Seconds of silence between the main theme fading out on win
## and the end theme fading in. Gives the "BigMeowFinal" cadence
## + finale rainbows room to land before a new piece of music
## takes over.
const _END_THEME_DELAY_SEC := 1.5

var player: Player

var has_started := false
var has_finished := false
var has_won := false

## True once the level's visual systems (including the marching-
## squares terrain chunks) have had time to render. The HUD polls
## this to blanket the screen in black until it flips true, so the
## player never sees the unbaked / mid-bake terrain. Subclasses
## should set it themselves once their specific initialisation
## finishes (TerrainLevel does so after its tile bake + a couple of
## frames of mesh upload).
var is_terrain_ready: bool = false

var _collected_coins: Array[bool] = []


func _enter_tree() -> void:
	G.level = self
	# Initialized here (not `_ready`) so child PersistentCoinSpawn
	# nodes can safely query `is_coin_collected` during their own
	# `_ready` — child `_ready` fires before parent `_ready`, but
	# `_enter_tree` runs parent-first.
	_collected_coins.resize(COIN_COUNT)
	_collected_coins.fill(false)


func _exit_tree() -> void:
	if G.level == self:
		G.level = null


func _ready() -> void:
	# Center the camera's anchor on its position. In Godot 4.5+ the
	# Camera2D default changed to FIXED_TOP_LEFT, which would make
	# the player render at the top-left of the screen given our
	# follow logic in _physics_process.
	%Camera2D.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	reset()


func reset() -> void:
	if is_instance_valid(player):
		player.destroy()

	has_started = false
	has_finished = false
	has_won = false

	_collected_coins.fill(false)
	coin_state_reset.emit()

	G.state.transition(StateMain.State.TITLE)

	await get_tree().create_timer(_RESET_READY_TO_START_GAME_DELAY_SEC).timeout

	start_game()


func mark_coin_collected(index: int, world_pos: Vector2) -> void:
	if index < 0 or index >= COIN_COUNT:
		return
	if _collected_coins[index]:
		return
	_collected_coins[index] = true
	coin_collected.emit(index, world_pos)


func is_coin_collected(index: int) -> bool:
	if index < 0 or index >= COIN_COUNT:
		return false
	return _collected_coins[index]


func total_coins_collected() -> int:
	var count := 0
	for v in _collected_coins:
		if v:
			count += 1
	return count


func start_game() -> void:
	G.print("Starting game", ScaffolderLog.CATEGORY_GAME_STATE)

	has_started = true
	spawn_player()
	G.state.transition(StateMain.State.GAME)


func game_over() -> void:
	G.print("Game over", ScaffolderLog.CATEGORY_GAME_STATE)
	has_finished = true
	await get_tree().create_timer(_GAME_OVER_READY_TO_RESET_DELAY_SEC).timeout
	G.print("Resetting for next game", ScaffolderLog.CATEGORY_GAME_STATE)
	# Drop the HUD blackout over the whole viewport *before* we
	# start ripping down this level, so the player never sees the
	# old-level-teardown + new-level-bake transition. Wait one frame
	# so the opaque rect actually renders, then reload.
	if is_instance_valid(G.hud):
		G.hud.show_blackout_immediately()
		await get_tree().process_frame
	# Full-scene reload instead of in-place `reset()` — the terrain
	# world only bakes once at _ready, so carved cells and detached
	# fragments can't be restored without instantiating a fresh
	# level. `GamePanel.restart_level()` frees this node and spawns
	# a new one.
	if is_instance_valid(G.game_panel):
		G.game_panel.restart_level()
	else:
		reset()


func win() -> void:
	has_won = true
	# Kill the main theme immediately on win, then let the beat
	# of silence land before the end theme fades in. The delay
	# lets the "BigMeowFinal" cadence + finale rainbows breathe
	# without music competing for attention. Runs unpaused so
	# the delayed fade happens in real time alongside the finale
	# animation (State.CREDITS transitions would pause the tree).
	if is_instance_valid(G.audio):
		G.audio.fade_to_end_theme_after(_END_THEME_DELAY_SEC)
	if is_instance_valid(player):
		player.enter_win_pose()
	if is_instance_valid(G.hud):
		G.hud.show_win_overlay()
	for enemy in get_tree().get_nodes_in_group(Enemy.GROUP):
		if not is_instance_valid(enemy):
			continue
		var tween := (enemy as CanvasItem).create_tween()
		tween.tween_property(
				enemy, "modulate:a", 0.0, _ENEMY_WIN_FADE_OUT_SEC)
	if is_instance_valid(G.bugs):
		var spawner := G.bugs as BugSpawner
		if spawner != null:
			for bug in spawner.get_alive_bugs():
				if is_instance_valid(bug):
					bug.visible = false


func _physics_process(delta: float) -> void:
	if is_instance_valid(player):
		%Camera2D.global_position = player.global_position + _PLAYER_CAMERA_OFFSET
	else:
		%Camera2D.global_position = %PlayerSpawnPoint.global_position + _PLAYER_CAMERA_OFFSET
	_tick_camera_shake(delta)


## Linearly-decaying random-offset camera shake. New shake calls
## with a larger amplitude take over; smaller-amplitude calls during
## an active shake are ignored so a quiet event can't shorten a
## louder one. Triggered from `Destination._fire_wayfinding_cue`
## and any other "thump" effects that need a haptic punch.
var _shake_amplitude_px: float = 0.0
var _shake_initial_duration_sec: float = 0.0
var _shake_remaining_sec: float = 0.0


func shake_camera(amplitude_px: float, duration_sec: float) -> void:
	if amplitude_px <= 0.0 or duration_sec <= 0.0:
		return
	if amplitude_px < _shake_amplitude_px and _shake_remaining_sec > 0.0:
		return
	_shake_amplitude_px = amplitude_px
	_shake_initial_duration_sec = duration_sec
	_shake_remaining_sec = duration_sec


func _tick_camera_shake(delta: float) -> void:
	if _shake_remaining_sec <= 0.0:
		if %Camera2D.offset != Vector2.ZERO:
			%Camera2D.offset = Vector2.ZERO
		return
	_shake_remaining_sec -= delta
	if _shake_remaining_sec <= 0.0:
		_shake_amplitude_px = 0.0
		%Camera2D.offset = Vector2.ZERO
		return
	var t: float = (_shake_remaining_sec
			/ maxf(_shake_initial_duration_sec, 0.001))
	var amp: float = _shake_amplitude_px * t
	%Camera2D.offset = Vector2(
			randf_range(-amp, amp),
			randf_range(-amp, amp))


func spawn_player() -> void:
	player = G.settings.player_scene.instantiate()
	%Players.add_child(player)
	var spawn_position: Vector2 = %PlayerSpawnPoint.global_position
	player.global_position = spawn_position
	player.call_deferred("set_global_position", spawn_position)

	player.play_sound("spawn")

	player.call_deferred("_enter_attached_idle_at_spawn")
