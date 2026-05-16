class_name CoinVfx
extends Node
## Orchestrates the visual effects fired in response to coin pickups:
## per-coin rainbow burst + HUD slot sparkle, plus the final-coin
## finale (screen-edge rainbow arcs + sparkles on every HUD slot).
##
## Lives under the HUD and connects to `Level.coin_collected`. Prefer
## the single connection point over spawning effects from multiple
## call sites so all coin VFX decisions stay in one place.


const _RAINBOW_BURST_SCENE: PackedScene = (
		preload("res://src/vfx/rainbow_burst.tscn"))
const _SPARKLE_OVERLAY_SCENE: PackedScene = (
		preload("res://src/vfx/sparkle_overlay.tscn"))

## Horizontal span of the per-coin rainbow arc. With the default
## `_COIN_BURST_LAUNCH_ANGLE_DEG` launch angle, the arc peaks at
## `_COIN_BURST_RANGE_PX * 0.5 * tan(angle)` above the coin and
## lands back at the coin's height `RANGE_PX` world-units to the
## side.
const _COIN_BURST_RANGE_PX := 220.0
## Base launch angle above horizontal for per-coin rainbow arcs, in
## degrees.
const _COIN_BURST_LAUNCH_ANGLE_DEG := 43.0
## Launch-angle variation around the base angle, in degrees.
## Positive values tilt the launch more toward vertical; negative
## values make it shallower.
const _COIN_BURST_JITTER_DEG := 3.0
const _COIN_BURST_DURATION_SEC := 0.85

const _SLOT_SPARKLE_DURATION_SEC := 0.9
const _SLOT_SPARKLE_DENSITY := 3.5

const _FINALE_BURST_COUNT := 6
const _FINALE_BURST_DURATION_SEC := 1.3
## Viewport-edge sagitta range (perpendicular control offset, in
## screen pixels). Wider range = more varied arc curvature across
## the fan of rainbows sweeping in from the screen edges.
const _FINALE_BURST_SAGITTA_MIN := 120.0
const _FINALE_BURST_SAGITTA_MAX := 240.0
## How far outside the viewport edge the edge-burst origin is
## placed, in screen pixels. Makes the rainbows read as sweeping
## in from offscreen rather than popping into existence at the
## edge.
const _FINALE_EDGE_OUTSET_PX := 40.0
## Overall thickness multiplier applied to every finale rainbow
## (both the edge fan and the player-horn-tip pair).
const _FINALE_BURST_THICKNESS_MULTIPLIER := 1.5
## Additional start-of-arc thickness multiplier for the edge
## bursts so they read as wide ribbons sweeping in rather than
## thin needles launching from offscreen. Only affects edge
## bursts; horn-tip bursts use the default 1.0.
const _FINALE_EDGE_THICKNESS_START_MULTIPLIER := 40.8
## Random rotation, in degrees, applied to each edge burst's chord
## so successive rainbows on the same side launch at visibly
## different angles instead of tracking the same band. Applied
## before the perpendicular control offset is computed, so the
## whole arc (not just the initial tangent) rotates together.
const _FINALE_EDGE_ANGLE_JITTER_DEG := 9.0
## Size multiplier for the two horn-tip rainbows. 4× the standard
## coin-pickup arc length so they span a significant portion of
## the viewport alongside the edge-fan rainbows.
const _FINALE_HORN_TIP_SIZE_MULTIPLIER := 4.0

## Scales the edge-burst chord length past the randomized near-
## center target so the edge rainbows reach all the way across
## the viewport rather than stopping near the middle. At 2.0 the
## target-relative extent doubles, so a rainbow from the left
## edge arcs past center and well into the right half of the
## viewport. Sagitta scales with it so the arc silhouette keeps
## its bow proportion.
const _FINALE_EDGE_CHORD_SCALE := 2.0

## Each finale rainbow's spawn time is offset by a random delay in
## `[0, _FINALE_STAGGER_MAX_SEC]` so the arcs layer in over the
## finale duration rather than all appearing on the same frame.
const _FINALE_STAGGER_MAX_SEC := 1.0
const _FINALE_SPARKLE_DURATION_SEC := 1.6
const _FINALE_SPARKLE_DENSITY := 4.0

## Layer 200 matches the HUD; finale bursts render in screen space so
## they can sweep across the whole viewport.
const _FINALE_CANVAS_LAYER := 201

## Group used by non-coin callers (e.g. `Destination` on game-win)
## to discover the single CoinVfx instance without hard-coding a
## path into the HUD subtree.
const GROUP := &"coin_vfx"


## Set by `coin_indicator.gd` so the orchestrator can find the slot
## nodes to sparkle. Each entry is a Control whose rect is the HUD
## box for that coin index.
var hud_slot_nodes: Array[Control] = []


func _ready() -> void:
	add_to_group(GROUP)
	set_process(true)


func _process(_delta: float) -> void:
	# Re-check each frame so the orchestrator re-connects to
	# whichever Level instance is current. On game-over the level
	# scene reloads, and the previous level's signal dies with it.
	if not is_instance_valid(G.level):
		return
	if not G.level.coin_collected.is_connected(_on_coin_collected):
		G.level.coin_collected.connect(_on_coin_collected)


func _on_coin_collected(index: int, world_pos: Vector2) -> void:
	_spawn_coin_burst()
	_spawn_world_sparkle_burst(world_pos)
	_play_slot_sparkle(index, _SLOT_SPARKLE_DURATION_SEC,
			_SLOT_SPARKLE_DENSITY)
	if G.level.total_coins_collected() >= Level.COIN_COUNT:
		_play_finale()


func _spawn_world_sparkle_burst(world_pos: Vector2) -> void:
	if not is_instance_valid(G.level):
		return
	var burst := CoinSparkles.new()
	burst.mode = CoinSparkles.Mode.BURST
	G.level.add_child(burst)
	burst.global_position = world_pos


func _spawn_coin_burst() -> void:
	if not is_instance_valid(G.level):
		return
	var player := G.level.player
	if not is_instance_valid(player):
		return
	# Origin = player's horn tip (mirrored to match facing). Launch
	# side follows the player's facing so the rainbow always fires
	# *away* from the player in the direction they're pointing.
	var origin: Vector2 = player.get_horn_tip_world_position()
	var side := 1.0 if player.surface_state.is_facing_right else -1.0
	_spawn_burst_at_world(origin, side)


## Public helper: fires a single coin-pickup-style rainbow burst
## from an arbitrary world position. Used by `Destination` on game-
## win so the arrival moment gets the same rainbow vocabulary as a
## coin pickup. `size_multiplier` scales the arc's range;
## `launch_angle_degrees` sets the initial launch angle above
## horizontal (45° = default coin-pickup arc); `jitter_degrees`
## overrides the random angle deviation (pass 0 for a deterministic
## shape on fixed-position emitters like the destination).
## `side_override` pins the launch direction: +1 = right, -1 =
## left, 0 = random (the default, used by generic emitters with no
## facing preference).
func spawn_world_burst(
		origin: Vector2,
		size_multiplier: float = 1.0,
		launch_angle_degrees: float = _COIN_BURST_LAUNCH_ANGLE_DEG,
		jitter_degrees: float = _COIN_BURST_JITTER_DEG,
		distance_fade_reach: float = -1.0,
		side_override: float = 0.0,
		thickness_start_multiplier: float = 1.0) -> void:
	var side: float
	if absf(side_override) > 0.01:
		side = signf(side_override)
	else:
		side = 1.0 if randf() < 0.5 else -1.0
	_spawn_burst_at_world(
			origin,
			side,
			size_multiplier,
			launch_angle_degrees,
			jitter_degrees,
			distance_fade_reach,
			_COIN_BURST_DURATION_SEC,
			1.0,
			thickness_start_multiplier)


func _spawn_burst_at_world(
		origin: Vector2,
		side: float,
		size_multiplier: float = 1.0,
		launch_angle_degrees: float = _COIN_BURST_LAUNCH_ANGLE_DEG,
		jitter_degrees: float = _COIN_BURST_JITTER_DEG,
		distance_fade_reach: float = -1.0,
		duration_sec: float = _COIN_BURST_DURATION_SEC,
		thickness_multiplier: float = 1.0,
		thickness_start_multiplier: float = 1.0) -> void:
	# Quadratic Bézier: P0 = origin, chord ends at origin + (L, 0),
	# control point at origin + (L/2, -H). Initial tangent (P1 - P0)
	# has angle atan(H / (L/2)) above horizontal, so H is derived
	# directly from the requested launch angle: H = (L/2) * tan(θ).
	# Mirrored horizontally for the up-left side.
	var jitter_rad := deg_to_rad(randf_range(
			-jitter_degrees, jitter_degrees))
	# Multiplier of `-side` makes a positive jitter feel "more
	# vertical" regardless of which side the arc flies toward.
	var rot_rad := jitter_rad * (-side)

	var range_px: float = _COIN_BURST_RANGE_PX * size_multiplier
	var arc_height_px: float = (range_px * 0.5
			* tan(deg_to_rad(launch_angle_degrees)))
	var p2_offset := Vector2(side * range_px, 0.0).rotated(rot_rad)
	var c_offset := Vector2(
			side * range_px * 0.5,
			-arc_height_px).rotated(rot_rad)

	var world_end := origin + p2_offset
	var world_control := origin + c_offset

	# Render on the top `CanvasLayer` (above the HUD blackout) so the
	# rainbow reads on top of everything. That layer is screen-space,
	# so translate P0 / P2 / control from world to screen coords via
	# the current viewport canvas transform. The burst snapshot-fixes
	# to the screen at spawn; with a ~0.85s lifetime the lack of
	# camera follow isn't noticeable in practice.
	var xform: Transform2D = get_viewport().get_canvas_transform()
	var screen_origin: Vector2 = xform * origin
	var screen_end: Vector2 = xform * world_end
	var screen_control: Vector2 = xform * world_control
	var screen_mid := (screen_origin + screen_end) * 0.5
	var control_offset := screen_control - screen_mid

	var top_layer := _get_or_create_finale_layer()
	_spawn_burst_between(
			screen_origin,
			screen_end,
			control_offset,
			randf(),
			duration_sec,
			top_layer,
			distance_fade_reach,
			thickness_multiplier,
			thickness_start_multiplier)
	_spawn_pulse_ring(screen_origin, top_layer)


func _spawn_pulse_ring(origin: Vector2, parent: Node) -> void:
	var ring := PulseRing.new()
	ring.position = origin
	parent.add_child(ring)


## Public helper: spawns the same expanding-ring wash used on coin
## pickups at a world-space origin, with configurable opacity + size
## multipliers. Used by the player on echo emission so each pulse
## gets a softer version of the coin-pickup radial feedback without
## duplicating the canvas-layer / world-to-screen plumbing.
func spawn_world_pulse_ring(
		world_origin: Vector2,
		opacity_scale: float = 1.0,
		size_scale: float = 1.0) -> void:
	var xform: Transform2D = get_viewport().get_canvas_transform()
	var screen_origin: Vector2 = xform * world_origin
	var ring := PulseRing.new()
	ring.position = screen_origin
	ring.start_radius_px *= size_scale
	ring.end_radius_px *= size_scale
	var tinted := ring.color
	tinted.a *= opacity_scale
	ring.color = tinted
	_get_or_create_finale_layer().add_child(ring)


func _spawn_burst_between(
		start: Vector2,
		end: Vector2,
		control_offset: Vector2,
		hue_offset: float,
		duration_sec: float,
		parent: Node,
		distance_fade_reach: float = -1.0,
		thickness_multiplier: float = 1.0,
		thickness_start_multiplier: float = 1.0) -> void:
	var burst := _RAINBOW_BURST_SCENE.instantiate()
	burst.start_world = start
	burst.end_world = end
	burst.control_offset = control_offset
	burst.hue_offset = hue_offset
	burst.duration_sec = duration_sec
	burst.distance_fade_reach = distance_fade_reach
	burst.thickness_multiplier = thickness_multiplier
	burst.thickness_start_multiplier = thickness_start_multiplier
	parent.add_child(burst)


func _play_slot_sparkle(
		index: int,
		duration_sec: float,
		density: float) -> void:
	if index < 0 or index >= hud_slot_nodes.size():
		return
	var slot := hud_slot_nodes[index]
	if not is_instance_valid(slot):
		return
	var overlay := _SPARKLE_OVERLAY_SCENE.instantiate()
	overlay.duration_sec = duration_sec
	overlay.density = density
	slot.add_child(overlay)


func _play_finale() -> void:
	_spawn_finale_rainbow_bursts()
	for i in range(hud_slot_nodes.size()):
		_play_slot_sparkle(
				i,
				_FINALE_SPARKLE_DURATION_SEC,
				_FINALE_SPARKLE_DENSITY)
	# Same "success" cadence that plays on destination-reach, so
	# grabbing all six KITTEN coins reads as the same celebratory
	# beat as arriving at the goal.
	if is_instance_valid(G.audio):
		G.audio.play_player_sound("all_coins", true)


func _spawn_finale_rainbow_bursts() -> void:
	# Schedule each edge rainbow at an evenly-spaced delay across
	# `[0, _FINALE_STAGGER_MAX_SEC]` so the arcs drop in on a steady
	# cadence instead of clumping. Sides alternate by index (even =
	# left edge, odd = right edge) so successive bursts sweep in
	# from opposite sides rather than stacking on the same edge.
	# SceneTree timers self-delete after firing so there's nothing
	# to clean up on level reload.
	for i in range(_FINALE_BURST_COUNT):
		var delay_sec: float = (
				float(i) / float(_FINALE_BURST_COUNT)
				* _FINALE_STAGGER_MAX_SEC)
		var use_left_edge: bool = i % 2 == 0
		get_tree().create_timer(delay_sec).timeout.connect(
				_spawn_one_edge_burst.bind(i, use_left_edge))
	# Horn-tip rainbows fire immediately (no stagger delay) so the
	# burst anchors the start of the finale moment. Both sides
	# spawn on the same frame.
	for side in [1.0, -1.0]:
		_spawn_one_horn_tip_burst(side)


func _spawn_one_edge_burst(hue_index: int, use_left_edge: bool) -> void:
	var finale_layer := _get_or_create_finale_layer()
	var viewport_size: Vector2 = (
			get_viewport().get_visible_rect().size)
	var center := viewport_size * 0.5
	# Rainbow sweeps in from just outside the left OR right
	# viewport edge (top/bottom excluded). Target is scaled past
	# near-center so the chord reaches all the way across the
	# viewport. Control offset is perpendicular to the chord,
	# biased upward in screen space, so every arc peaks above the
	# chord and curves downward as it sweeps across.
	var edge_point := _edge_point_outside(viewport_size, use_left_edge)
	var near_target := center + Vector2(
			randf_range(-80.0, 80.0),
			randf_range(-80.0, 80.0))
	var angle_jitter_rad: float = deg_to_rad(randf_range(
			-_FINALE_EDGE_ANGLE_JITTER_DEG,
			_FINALE_EDGE_ANGLE_JITTER_DEG))
	var chord := (
			(near_target - edge_point)
			* _FINALE_EDGE_CHORD_SCALE).rotated(angle_jitter_rad)
	var target: Vector2 = edge_point + chord
	var perp := Vector2(-chord.y, chord.x)
	if perp.length_squared() > 0.0:
		perp = perp.normalized()
	if perp.y > 0.0:
		perp = -perp
	var sagitta: float = randf_range(
			_FINALE_BURST_SAGITTA_MIN,
			_FINALE_BURST_SAGITTA_MAX) * _FINALE_EDGE_CHORD_SCALE
	_spawn_burst_between(
			edge_point,
			target,
			perp * sagitta,
			float(hue_index) / float(_FINALE_BURST_COUNT),
			_FINALE_BURST_DURATION_SEC,
			finale_layer,
			-1.0,
			_FINALE_BURST_THICKNESS_MULTIPLIER,
			_FINALE_EDGE_THICKNESS_START_MULTIPLIER)


func _spawn_one_horn_tip_burst(side: float) -> void:
	# Horn-tip launch uses the same base-angle + jitter logic as a
	# coin pickup, just scaled up. Position is re-fetched at spawn
	# time so it tracks the player if they've moved during the
	# stagger delay.
	if not is_instance_valid(G.level):
		return
	var player := G.level.player
	if not is_instance_valid(player):
		return
	var horn_tip_origin: Vector2 = player.get_horn_tip_world_position()
	_spawn_burst_at_world(
			horn_tip_origin,
			side,
			_FINALE_HORN_TIP_SIZE_MULTIPLIER,
			_COIN_BURST_LAUNCH_ANGLE_DEG,
			_COIN_BURST_JITTER_DEG,
			-1.0,
			_FINALE_BURST_DURATION_SEC,
			_FINALE_BURST_THICKNESS_MULTIPLIER)


static func _edge_point_outside(
		viewport_size: Vector2, use_left_edge: bool) -> Vector2:
	# Pick a random point just outside the chosen LEFT or RIGHT
	# viewport edge — offscreen by `_FINALE_EDGE_OUTSET_PX` — so
	# the rainbow reads as sweeping horizontally across the view
	# rather than dropping in from above/below. Y is still
	# randomized for vertical spread across the fan.
	if use_left_edge:
		return Vector2(
				-_FINALE_EDGE_OUTSET_PX,
				randf_range(0.0, viewport_size.y))
	return Vector2(
			viewport_size.x + _FINALE_EDGE_OUTSET_PX,
			randf_range(0.0, viewport_size.y))


func _get_or_create_finale_layer() -> CanvasLayer:
	var existing := get_node_or_null("FinaleCanvasLayer") as CanvasLayer
	if is_instance_valid(existing):
		return existing
	var layer := CanvasLayer.new()
	layer.name = "FinaleCanvasLayer"
	layer.layer = _FINALE_CANVAS_LAYER
	add_child(layer)
	return layer
