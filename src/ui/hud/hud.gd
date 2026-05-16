class_name Hud
extends PanelContainer


## Modulate alpha applied to the Q / E frequency-selector icons
## while the player still has juice to spend on any frequency.
const _QE_ICON_ALPHA_ACTIVE := 1.0
## Modulate alpha applied once every frequency's juice pool has
## drained — Q / E read as "nothing selectable" until a bug refills
## something.
const _QE_ICON_ALPHA_INACTIVE := 0.25

## Fade-out duration for the loading blackout once the level
## reports its terrain as ready.
const _BLACKOUT_FADE_OUT_SEC := 0.4


## Tracks the Level instance we've "seen" the blackout hidden for,
## so a level reload (new instance) resets the state and pops the
## blackout back up while the fresh terrain bakes.
var _blackout_ready_level_id: int = 0
var _blackout_tween: Tween

## True once the loading blackout has fully faded away for the
## current Level. Player polls this to gate initial input so the
## first detach (and any other control) can't fire while the
## black cover is still up.
var is_blackout_hidden: bool = false

## Set true the first time `show_intro_overlay` runs. The dedication
## message reads once at game launch (alongside the Title + Controls
## fade-in) and is suppressed from later intro-overlay fires (post-
## death respawns, post-win resets), so it feels like a one-shot
## "for X" card rather than a recurring nag.
var _has_shown_dedication: bool = false


@onready var _q_icon: TextureRect = $MarginContainer/GameState/LeftContent/HBoxContainer/Q
@onready var _e_icon: TextureRect = $MarginContainer/GameState/LeftContent/HBoxContainer/E


func _enter_tree() -> void:
	G.hud = self


func _ready() -> void:
	# All HUD elements start hidden — Level/Player/State drive them
	# in via explicit show methods once spawn/win moments arrive.
	# Starting GameState hidden avoids a 1-frame flash of the
	# health + juice bars between the initial TITLE→GAME transition
	# (which fades them in) and the deferred spawn-grace entry
	# (which fades them back out again).
	%Title.modulate.a = 0.0
	%Controls.modulate.a = 0.0
	%Credits.modulate.a = 0.0
	%GameState.modulate.a = 0.0
	%Dedication.modulate.a = 0.0

	# Wait for G.settings to be assigned.
	await get_tree().process_frame

	self.visible = G.settings.show_hud
	_apply_credits_colors()


## Fades in the Title + Controls overlay and fades out the gameplay
## HUD (health + juice bars). Called by the Player when it enters
## the spawn-grace attached-idle pose, and by the Level after win —
## both cases park the player in a non-responsive pose with the
## intro overlay visible instead of the gameplay HUD until the user
## acts.
func show_intro_overlay() -> void:
	fade_in(%Title)
	fade_in(%Controls)
	fade_out(%GameState)
	if not _has_shown_dedication:
		_has_shown_dedication = true
		fade_in(%Dedication)


## Game-win variant of `show_intro_overlay`. Fades in the Title and
## Credits (not Controls — the run is over, so the input legend
## would be redundant) and fades out the gameplay HUD. Called by
## `Level.win()` so the victory framing lingers on credits rather
## than on the starting control sheet.
func show_win_overlay() -> void:
	fade_in(%Title)
	fade_in(%Credits)
	fade_out(%GameState)
	if not _has_shown_dedication:
		_has_shown_dedication = true
		fade_in(%Dedication)


## DEPRECATED entry point — kept so older callers don't break.
## Prefer the two-stage methods below; this just fires both.
func hide_intro_overlay() -> void:
	hide_title_and_dedication()
	hide_controls_overlay()


## First stage of intro dismissal: fades out the Title + Dedication
## and fades in the gameplay HUD (health + juice bars). Fires on
## the player's spawn-grace detach so the bars are immediately
## visible the moment the player has agency, even though the
## Controls legend stays up until the first GREEN echo.
func hide_title_and_dedication() -> void:
	fade_out(%Title)
	fade_out(%Dedication)
	fade_in(%GameState)


## Second stage: fades out the Controls legend only. Called once
## the player has actually used the core mechanic (first GREEN
## echo) so the input hint stays on screen until they've tried it.
func hide_controls_overlay() -> void:
	fade_out(%Controls)


## Pushes `Settings.color_credits_*` into every Label under the
## credits group so the scene's authored font / outline colors
## can be tuned centrally.
func _apply_credits_colors() -> void:
	if G.settings == null:
		return
	var font: Color = G.settings.color_credits_font
	var outline: Color = G.settings.color_credits_outline
	for label in _find_credits_labels(%Credits):
		label.add_theme_color_override("font_color", font)
		label.add_theme_color_override("font_outline_color", outline)


func _find_credits_labels(root: Node) -> Array[Label]:
	var out: Array[Label] = []
	for child in root.get_children():
		if child is Label:
			out.append(child as Label)
		out.append_array(_find_credits_labels(child))
	return out


func fade_in(node: CanvasItem) -> void:
	var tween := create_tween()
	tween.tween_property(
		node,
		"modulate:a",
		1.0,
		0.3)


func fade_out(node: CanvasItem) -> void:
	var tween := create_tween()
	tween.tween_property(
		node,
		"modulate:a",
		0.0,
		0.3)


func _process(_delta: float) -> void:
	_update_qe_icons_from_juice()
	_update_blackout()


## Shows the black screen while the current Level reports its
## terrain is not yet rendered, and fades it out once the level
## flips `is_terrain_ready`. Tracks the level's instance id so a
## game-over reload (new Level instance) snaps the blackout back
## on for the fresh bake.
func _update_blackout() -> void:
	if not is_instance_valid(%BlackoutRect):
		return
	var level_id := 0
	var terrain_ready := false
	if is_instance_valid(G.level):
		level_id = G.level.get_instance_id()
		terrain_ready = G.level.is_terrain_ready
	if level_id != _blackout_ready_level_id:
		# New (or absent) level: snap the blackout fully opaque
		# immediately so the fresh terrain is never visible during
		# its bake window.
		if _blackout_tween and _blackout_tween.is_valid():
			_blackout_tween.kill()
		%BlackoutRect.modulate.a = 1.0
		%BlackoutRect.visible = true
		_blackout_ready_level_id = 0
		is_blackout_hidden = false
	if terrain_ready and _blackout_ready_level_id != level_id:
		_blackout_ready_level_id = level_id
		_fade_out_blackout()


func _fade_out_blackout() -> void:
	if _blackout_tween and _blackout_tween.is_valid():
		_blackout_tween.kill()
	_blackout_tween = create_tween()
	_blackout_tween.tween_property(
			%BlackoutRect,
			"modulate:a",
			0.0,
			_BLACKOUT_FADE_OUT_SEC)
	_blackout_tween.tween_callback(
			Callable(%BlackoutRect, "set_visible").bind(false))
	_blackout_tween.tween_callback(
			Callable(self, "_on_blackout_fully_hidden"))


func _on_blackout_fully_hidden() -> void:
	is_blackout_hidden = true


## Snaps the loading blackout back to fully opaque right now, and
## ensures `_update_blackout`'s next poll keeps it on until the
## *next* Level instance comes in with `is_terrain_ready = true`.
## Called by `Level.game_over()` so the black screen covers the
## whole respawn transition (old level teardown → new level bake →
## terrain mesh) instead of only the new level's bake window.
func show_blackout_immediately() -> void:
	if not is_instance_valid(%BlackoutRect):
		return
	if _blackout_tween and _blackout_tween.is_valid():
		_blackout_tween.kill()
	%BlackoutRect.visible = true
	%BlackoutRect.modulate.a = 1.0
	is_blackout_hidden = false
	# Reset the "already faded for this level" marker so the next
	# `_update_blackout` tick re-arms the cover for the upcoming
	# level.
	_blackout_ready_level_id = 0


## Polls the player's colored-juice pools and fades the Q / E
## frequency-selector icons based on whether anything is selectable.
## Mirrors the polling pattern used by HealthBar / JuiceBarRow so
## respawns and level resets don't need signal (dis)connection.
func _update_qe_icons_from_juice() -> void:
	if not is_instance_valid(_q_icon) or not is_instance_valid(_e_icon):
		return
	var target_alpha := _QE_ICON_ALPHA_INACTIVE
	if (is_instance_valid(G.level)
			and is_instance_valid(G.level.player)):
		var player := G.level.player
		if (player.get_juice(Frequency.Type.RED) > 0
				or player.get_juice(Frequency.Type.GREEN) > 0
				or player.get_juice(Frequency.Type.BLUE) > 0
				or player.get_juice(Frequency.Type.YELLOW) > 0):
			target_alpha = _QE_ICON_ALPHA_ACTIVE
	_q_icon.modulate.a = target_alpha
	_e_icon.modulate.a = target_alpha


func handle_state_transition(to_state: StateMain.State) -> void:
	# Title + Controls + GameState are managed by the intro-overlay
	# show/hide pair, not by state — so the intro overlay can live
	# inside GAME state (spawn grace + post-win) rather than only on
	# a dedicated TITLE screen, and so the health + juice bars don't
	# briefly fade in on the initial TITLE→GAME transition only to
	# be faded back out by the deferred spawn-grace entry.
	match to_state:
		StateMain.State.TITLE:
			fade_out(%Credits)
		StateMain.State.GAME:
			fade_out(%Credits)
		StateMain.State.PAUSE:
			fade_out(%Credits)
		StateMain.State.CREDITS:
			fade_out(%GameState)
			fade_in(%Credits)
		_:
			G.error()
