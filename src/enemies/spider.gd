class_name Spider
extends Enemy
## Wall/floor/ceiling-crawling enemy. Tracks a surface-normal
## "anchor" each frame; the sprite rotates so its feet face the
## anchor surface and its movement rides along the surface tangent.
##
## The anchor is updated by a ray along the current anchor normal.
## If the ray misses (the spider has walked past a convex edge),
## the spider probes the four cardinal directions for the nearest
## surface and re-anchors there. This lets it transition smoothly
## from floor to wall to ceiling around corners.
##
## When no surface is within probe range in any direction, the
## spider falls under gravity until it catches a new surface.


## Distance from the spider's origin to the sprite "feet" surface
## point. The node position sits `_FOOT_OFFSET_PX` off the surface
## along the anchor normal.
const _FOOT_OFFSET_PX := 6.0
## How far along `_anchor_normal` the anchor ray's origin is
## offset before casting. Prevents the ray from starting INSIDE a
## solid when the spider has clipped slightly past its expected
## foot position (e.g., a high-velocity fall landing a frame too
## late), which would otherwise make Godot return no hits and
## leave the spider stuck falling through the floor. Sized to
## exceed one frame of `_MAX_FALL_SPEED_PX_PER_SEC` travel at a
## generous 20 FPS floor.
const _RAY_START_OFFSET_PX := 10.0
## Max range of the surface-probe rays. Must exceed the per-frame
## movement distance so the spider doesn't walk itself off-surface
## between frames.
const _SURFACE_RAY_LENGTH_PX := 40.0
## Fallback gravity used when the spider is truly airborne (all
## four probes miss).
const _GRAVITY_PX_PER_SEC_SQ := 900.0
## Hard cap on airborne fall speed. Kept below the ray-origin
## offset (in per-frame terms at expected frame rates) so a
## spider that briefly lost its anchor doesn't overshoot the
## landing surface so badly that the anchor ray can't find it.
const _MAX_FALL_SPEED_PX_PER_SEC := 200.0

const _PURSUIT_SPEED_PX_PER_SEC := 33.0
## Magnitude (pixels) of the tie-breaker bias added along the
## tangent's world-y direction when the raw tangential pursuit
## projection is too small to pick a direction. On an up-pointing
## tangent (LEFT-wall / bump climb) this nudges the spider
## upward; on a down-pointing tangent (RIGHT-wall / hanging-wall
## descent) it nudges downward. Only fires when the player's
## tangential offset is below `_PURSUIT_BIAS_TIE_PX` — a player
## clearly above/below the spider still gets pursued in that
## actual direction.
const _PURSUIT_CLIMB_BIAS_PX := 24.0
## Tangential-projection magnitude below which the tangent-y
## climb/descend bias kicks in. Kept small (~3 px) so the bias
## only resolves truly ambiguous pursuits (player at the same y
## as the spider on a bump or hanging wall). Above this, the
## raw `to_player.dot(tangent)` dominates and the spider climbs
## toward players that are actually above or descends toward
## players that are actually below.
const _PURSUIT_BIAS_TIE_PX := 3.0
const _WANDER_SPEED_PX_PER_SEC := 10.0
const _WANDER_RADIUS_PX := 64.0
const _WANDER_IDLE_MIN_SEC := 0.6
const _WANDER_IDLE_MAX_SEC := 1.8

## Bit 0 = layer 1 "normal_surfaces" (tilemap), bit 9 = layer 10
## "web_tile" so the spider also anchors to cobwebs.
const _SURFACE_MASK := 1 | (1 << 9)
## Mask used for the forward-tangent wall-hit probe. Webs are thin
## and should not halt horizontal motion — only solid terrain does.
## Keeping webs in the main `_SURFACE_MASK` still lets the spider
## anchor to them when walking off a convex edge onto a web.
const _FORWARD_OBSTACLE_MASK := 1
## Movement speed (along the surface tangent) below which the
## animator plays idle instead of walk.
const _IDLE_SPEED_THRESHOLD_PX_PER_SEC := 2.0
## Range of the forward-tangent probe used to detect a wall in the
## spider's path. Without this, a floor-walking spider will slide
## straight through a vertical wall without re-anchoring to it.
const _FORWARD_PROBE_RANGE_PX := 14.0
## Speed below which the forward probe is skipped. Very small
## (not zero) so a nearly-idle spider still catches concave
## corners when it starts moving, but a fully-stopped one
## doesn't waste a raycast per frame. 0.01 was too strict —
## mid-wander speeds that dip just under the old threshold could
## walk the spider straight into a wall before picking up speed.
const _FORWARD_PROBE_MIN_SPEED := 0.001
## Maximum allowed teleport distance when re-anchoring to a
## surface. Snaps bigger than this (e.g., the climb-up probe
## finding a ceiling 20+ px away) are rejected; the spider
## unanchors instead and gravity carries it toward the surface
## naturally over a few frames. Sized to allow the legitimate
## ~8 px convex-corner transition at the top of a stair riser
## (foot-offset 6 + a little slack) while still blocking
## arbitrary teleports to far-away overhead surfaces.
const _MAX_SNAP_DIST_SQ := 10.0 * 10.0
## Range of the pursuit climb-up probe. Cast straight up through
## the full surface mask (walls + webs) when the spider is
## chasing a player meaningfully above it. Kept tight so the
## probe can only grab nearby surfaces — anything farther is a
## fall-then-re-land situation, not an instant climb.
const _CLIMB_PROBE_RANGE_PX := 10.0
## Minimum vertical distance (positive = player above) before
## the climb-up probe runs. Below this the spider stays on its
## current anchor and pursues tangentially; avoids thrashing
## between surfaces when the player is roughly level with us.
const _CLIMB_DETECT_MIN_DY_PX := 12.0
## Minimum projection of the vector-to-player onto the prospective
## new tangent required to commit a climb-up re-anchor. Below
## this the new surface wouldn't let us make horizontal progress
## along its tangent, so snapping onto it would leave the spider
## frozen on the web/wall it just latched to.
const _CLIMB_MIN_TANGENTIAL_DISTANCE_PX := 12.0
## Number of consecutive frames a pursuing spider can have near-
## zero pursuit speed before it detaches. Catches the case where
## a prior anchor (usually an 8-probe fallback onto a web) left
## the spider on a surface whose tangent doesn't line up with the
## player direction — unsticking lets gravity carry it back to a
## more productive position.
const _STUCK_FRAMES_BEFORE_DETACH := 30
## Frames to suppress `_snap_to_surface` after a stuck-detach so
## the spider actually falls clear of the surface it got stuck on
## instead of re-anchoring to it on the very next tick.
const _POST_DETACH_SNAP_COOLDOWN_FRAMES := 10


@export var animated_sprite: AnimatedSprite2D


var _time_sec := 0.0
## Unit vector pointing AWAY from the currently-anchored surface
## (i.e., the surface normal at the spider's feet). Floor = UP,
## right wall (spider on left face) = LEFT, ceiling = DOWN, etc.
## Defaults to UP so a freshly-spawned spider falls onto a floor.
var _anchor_normal: Vector2 = Vector2.UP
## True while a surface was found within probe range last frame.
var _is_anchored: bool = false
## Consecutive frames the spider has been anchored + pursuing +
## making no tangential progress. Reset the moment it starts
## moving; incremented otherwise. Crosses
## `_STUCK_FRAMES_BEFORE_DETACH` → force-detach.
var _stuck_frames: int = 0
## Countdown after a stuck-detach during which
## `_snap_to_surface` early-returns without trying to re-anchor.
## Ticks down one per frame; when zero the normal snap loop
## resumes.
var _snap_cooldown_frames: int = 0

## Throttle for the 8-probe snap loop while wandering with the
## player out of perception range. Counts physics ticks since the
## last snap; when it reaches `_WANDER_SNAP_PERIOD_FRAMES` the snap
## runs and the counter resets. Pursuit, unanchored, post-detach
## cooldown, and player-in-range states force every-frame snap by
## resetting the counter.
const _WANDER_SNAP_PERIOD_FRAMES := 4
## More aggressive throttle on the `web_low` feature (set in the
## web export preset) — web builds can tolerate longer between
## anchor refreshes since the player is still bound by the same
## wander conditions and chunk-modified force-snap.
const _WANDER_SNAP_PERIOD_FRAMES_WEB := 8
## Multiplier on `proximity_perception_radius_px` defining the
## "player nearby" radius that disables wander throttling. A 1.5x
## buffer means the throttle drops the moment the player is close
## enough to credibly enter perception within a few frames, so
## pursuit transitions don't visibly lag.
const _WANDER_DETECTION_RADIUS_MULTIPLIER := 1.5
var _wander_snap_frame_counter: int = 0
## Set by `_on_terrain_chunk_modified` when terrain changes near
## the spider; consumed by the next `_should_run_snap` to force a
## fresh re-anchor so the spider doesn't fall through cells the
## player just carved out from under it.
var _force_snap_next_frame: bool = false


func _ready() -> void:
	super._ready()
	if (is_instance_valid(G.terrain)
			and not G.terrain.chunk_modified.is_connected(
				_on_terrain_chunk_modified)):
		G.terrain.chunk_modified.connect(_on_terrain_chunk_modified)


func _exit_tree() -> void:
	if (is_instance_valid(G.terrain)
			and G.terrain.chunk_modified.is_connected(
				_on_terrain_chunk_modified)):
		G.terrain.chunk_modified.disconnect(
				_on_terrain_chunk_modified)


func _on_terrain_chunk_modified(_coords: Vector2i) -> void:
	# Cheap and unconditional: even if the modified chunk is far
	# from this spider, forcing one snap cycle costs at most one
	# 8-probe iteration. Filtering by chunk distance would require
	# knowing the world cell-size and adds branching for negligible
	# savings.
	_force_snap_next_frame = true


func _update_behavior(delta: float, player: Player) -> void:
	_time_sec += delta

	if _should_run_snap(player):
		_snap_to_surface()

	# Tangent along the anchor surface. The sprite walks along this
	# direction. Rotating the anchor normal 90° CCW gives the
	# tangent pointing to the surface's "right" in the spider's
	# body frame.
	var tangent := Vector2(-_anchor_normal.y, _anchor_normal.x)

	var speed_along_surface: float = 0.0
	if is_pursuing() and is_instance_valid(player):
		var to_player: Vector2 = player.global_position - global_position
		var along: float = _pursuit_along_tangent(to_player, tangent)
		if absf(along) > 2.0:
			speed_along_surface = signf(along) * _PURSUIT_SPEED_PX_PER_SEC
	else:
		var wander_v: Vector2 = _compute_wander_velocity(
				delta,
				_WANDER_SPEED_PX_PER_SEC,
				_WANDER_RADIUS_PX,
				_WANDER_IDLE_MIN_SEC,
				_WANDER_IDLE_MAX_SEC)
		# Wander was computed in world space; project onto tangent.
		speed_along_surface = wander_v.dot(tangent)

	if _is_anchored:
		# Before committing motion, probe forward along the tangent
		# in the direction of travel. If we're about to walk into a
		# wall (floor-anchored spider hitting a vertical surface, or
		# any concave corner), re-anchor to the obstructing surface
		# so the next frame's tangent runs UP/DOWN that surface
		# instead of passing through it.
		if absf(speed_along_surface) > _FORWARD_PROBE_MIN_SPEED:
			var forward_dir: Vector2 = (
					tangent * signf(speed_along_surface))
			var space := get_world_2d().direct_space_state
			var forward_hit: Dictionary = _raycast(
					space,
					global_position,
					forward_dir * _FORWARD_PROBE_RANGE_PX,
					_FORWARD_OBSTACLE_MASK)
			if not forward_hit.is_empty():
				_apply_surface_hit(forward_hit)
				tangent = Vector2(
						-_anchor_normal.y, _anchor_normal.x)
				# Recompute motion along the new tangent so the
				# spider keeps heading toward its target rather
				# than snapping to zero velocity.
				if is_pursuing() and is_instance_valid(player):
					var to_player_after: Vector2 = (
							player.global_position
							- global_position)
					var along_after: float = _pursuit_along_tangent(
							to_player_after, tangent)
					speed_along_surface = (
							signf(along_after)
							* _PURSUIT_SPEED_PX_PER_SEC
							if absf(along_after) > 2.0 else 0.0)
		# Climb-up probe: when pursuing a player meaningfully
		# above, look for a surface directly overhead (walls or
		# webs via the full surface mask). The probe is short so
		# any hit is within `_MAX_SNAP_DIST_SQ` — unreachable
		# overheads don't yank the spider, but a web at floor
		# level or a wall reachable in one step does re-anchor.
		if (is_pursuing()
				and is_instance_valid(player)
				and _anchor_normal.y <= 0.5):
			var dy_player: float = (
					player.global_position.y - global_position.y)
			if dy_player < -_CLIMB_DETECT_MIN_DY_PX:
				var climb_space := get_world_2d().direct_space_state
				var climb_hit: Dictionary = _raycast(
						climb_space,
						global_position,
						Vector2.UP * _CLIMB_PROBE_RANGE_PX)
				if not climb_hit.is_empty():
					# Reject the climb if the would-be anchor's
					# tangent doesn't line up with the direction to
					# the player — otherwise the spider snaps onto
					# a horizontal web above an even-lateral player
					# and freezes (speed_along_surface = 0 along a
					# perpendicular tangent). Only snap when we can
					# actually make progress on the new surface.
					var prospective_normal: Vector2 = climb_hit[
							"normal"]
					var prospective_tangent := Vector2(
							-prospective_normal.y,
							prospective_normal.x)
					var to_player_prospect: Vector2 = (
							player.global_position
							- global_position)
					if (absf(to_player_prospect.dot(
							prospective_tangent))
							>= _CLIMB_MIN_TANGENTIAL_DISTANCE_PX
							and _try_apply_short_surface_hit(
									climb_hit)):
						tangent = Vector2(
								-_anchor_normal.y,
								_anchor_normal.x)
						var to_player_up: Vector2 = (
								player.global_position
								- global_position)
						var along_up: float = _pursuit_along_tangent(
								to_player_up, tangent)
						speed_along_surface = (
								signf(along_up)
								* _PURSUIT_SPEED_PX_PER_SEC
								if absf(along_up) > 2.0 else 0.0)
		# Stuck-unstick: a pursuing spider with no tangential
		# progress for several frames forcibly detaches so gravity
		# can carry it off the perpendicular-tangent surface it
		# got caught on. Non-pursuing (wandering) spiders are
		# allowed to sit still on their anchor indefinitely.
		if (is_pursuing()
				and is_instance_valid(player)
				and absf(speed_along_surface) < 1.0):
			_stuck_frames += 1
			if _stuck_frames > _STUCK_FRAMES_BEFORE_DETACH:
				_is_anchored = false
				_anchor_normal = Vector2.UP
				_stuck_frames = 0
				_snap_cooldown_frames = (
						_POST_DETACH_SNAP_COOLDOWN_FRAMES)
		else:
			_stuck_frames = 0
		# Ride the anchor surface. No gravity — the per-frame ray
		# re-snap keeps us attached even across convex corners.
		_velocity = tangent * speed_along_surface
	else:
		# Fully airborne. Fall + a little horizontal drift from
		# whatever velocity we had.
		_velocity.x = tangent.x * speed_along_surface
		_velocity.y = minf(
				_velocity.y + _GRAVITY_PX_PER_SEC_SQ * delta,
				_MAX_FALL_SPEED_PX_PER_SEC)

	_update_animation(speed_along_surface, tangent)


## Decides whether to run the 8-probe `_snap_to_surface` this
## physics tick. Wandering spiders far from the player skip it on
## (N-1)/N ticks; everyone else runs every tick to stay responsive.
func _should_run_snap(player: Player) -> bool:
	if _force_snap_next_frame:
		_force_snap_next_frame = false
		_wander_snap_frame_counter = 0
		return true
	# Pursuit, unanchored, and post-detach cooldown all need fresh
	# probes every tick — throttling them risks visible AI stalls
	# or fall-through bugs.
	if (is_pursuing()
			or not _is_anchored
			or _snap_cooldown_frames > 0):
		_wander_snap_frame_counter = 0
		return true
	# Player within the buffered perception radius → keep snapping
	# every tick so the spider doesn't stutter when the player
	# crosses the perception boundary.
	if is_instance_valid(player):
		var threshold: float = (
				proximity_perception_radius_px
				* _WANDER_DETECTION_RADIUS_MULTIPLIER)
		var distance_sq: float = (
				global_position.distance_squared_to(
						player.global_position))
		if distance_sq <= threshold * threshold:
			_wander_snap_frame_counter = 0
			return true
	_wander_snap_frame_counter += 1
	var period: int = (_WANDER_SNAP_PERIOD_FRAMES_WEB
			if OS.has_feature("web_low")
			else _WANDER_SNAP_PERIOD_FRAMES)
	if _wander_snap_frame_counter >= period:
		_wander_snap_frame_counter = 0
		return true
	return false


## Rotates the sprite so "down" in its authored art aligns with
## `-_anchor_normal` (feet point toward the surface), and flips
## it horizontally based on movement direction along the tangent.
func _update_animation(
		speed_along_surface: float, tangent: Vector2) -> void:
	if animated_sprite == null:
		return
	animated_sprite.rotation = _anchor_normal.angle() + PI / 2.0
	if absf(speed_along_surface) < _IDLE_SPEED_THRESHOLD_PX_PER_SEC:
		if animated_sprite.animation != &"idle":
			animated_sprite.play(&"idle")
	else:
		if animated_sprite.animation != &"walk":
			animated_sprite.play(&"walk")
		# The spider's walk frames are authored facing left, so the
		# sprite needs to be flipped when moving right-along-tangent
		# (same flip convention the floor-only version used).
		animated_sprite.flip_h = speed_along_surface > 0.0


func _on_pursuit_started() -> void:
	var voice := get_node_or_null(^"%VoicePlayer") as AudioStreamPlayer2D
	if voice != null:
		voice.play()


## Re-snap to whatever surface is currently anchoring us. First
## casts along the existing anchor normal (this catches the normal
## "keep walking along the current surface" case). If that misses
## (convex edge or we just launched off a floor), probes the four
## cardinal directions and picks the nearest hit, treating it as
## the new anchor. If every probe misses, sets `_is_anchored=false`
## so the caller can fall under gravity.
func _snap_to_surface() -> void:
	# Honor the post-detach cooldown set by the stuck-unstick
	# path in `_update_behavior`. While > 0 we leave the spider
	# unanchored so gravity carries them clear of whatever they
	# got stuck on. Without this, the anchor ray on the very
	# next tick re-catches the same web/ceiling and we loop.
	if _snap_cooldown_frames > 0:
		_snap_cooldown_frames -= 1
		_is_anchored = false
		return
	var space := get_world_2d().direct_space_state
	# Try the current anchor first. Start the ray a few pixels
	# back along the anchor normal so it's always outside the
	# surface we're trying to find — a spider that overshot into
	# a solid on a high-velocity fall would otherwise cast from
	# inside, Godot returns no hit, and the fall continues
	# indefinitely.
	var anchor_origin: Vector2 = (
			global_position + _anchor_normal * _RAY_START_OFFSET_PX)
	var hit: Dictionary = _raycast(
			space,
			anchor_origin,
			-_anchor_normal
					* (_SURFACE_RAY_LENGTH_PX + _RAY_START_OFFSET_PX))
	if not hit.is_empty():
		var hit_pos: Vector2 = hit["position"]
		var hit_distance_sq: float = (
				global_position.distance_squared_to(hit_pos))
		# A normal-anchor hit lives `_FOOT_OFFSET_PX` away from the
		# spider. If the hit is much farther (more than ~2×
		# FOOT_OFFSET), the spider has walked off the edge of the
		# old surface and the anchor ray reached past the corner to
		# something far below (or across). Defer the snap: try the
		# convex-corner continuation first so the spider can wrap
		# onto the perpendicular surface at the corner instead of
		# teleporting to the distant surface.
		var far_snap_threshold_sq: float = (
				(_FOOT_OFFSET_PX * 2.0)
				* (_FOOT_OFFSET_PX * 2.0))
		if hit_distance_sq <= far_snap_threshold_sq:
			_apply_surface_hit(hit)
			return
		var corner_first_hit: Dictionary = _convex_corner_probe(space)
		if not corner_first_hit.is_empty():
			_apply_surface_hit(corner_first_hit)
			return
		# No convex corner nearby — fall back to the distant hit
		# rather than leaving the spider airborne when a surface is
		# genuinely right there (e.g., landing from a fall).
		_apply_surface_hit(hit)
		return
	# Anchor ray missed. Try the convex-corner continuation before
	# the 8-probe so wall-top transitions pick the perpendicular
	# surface instead of the nearest cardinal hit.
	var corner_hit: Dictionary = _convex_corner_probe(space)
	if not corner_hit.is_empty():
		_apply_surface_hit(corner_hit)
		return
	# Still no hit — look for any nearby surface. Pick the nearest
	# of 8 probes covering the 4 cardinal + 4 diagonal directions,
	# so surfaces oriented on a diagonal (a web strung at 45°, a
	# sloped cell edge) are caught just like axis-aligned ones.
	var best_hit: Dictionary = {}
	var best_dist_sq: float = INF
	var diag: float = sqrt(0.5)
	var probe_dirs: Array[Vector2] = [
		Vector2.DOWN,
		Vector2.UP,
		Vector2.LEFT,
		Vector2.RIGHT,
		Vector2(diag, diag),
		Vector2(-diag, diag),
		Vector2(diag, -diag),
		Vector2(-diag, -diag),
	]
	for dir in probe_dirs:
		# Offset each probe's origin opposite to its ray direction
		# by `_RAY_START_OFFSET_PX` so the ray always starts
		# outside any collider in that direction. Without this, a
		# spider that clipped into a floor after descending past
		# the bottom of a wall would have every probe ray starting
		# inside the floor collider, all miss, and the spider
		# would fall through the world.
		var probe_origin: Vector2 = (
				global_position - dir * _RAY_START_OFFSET_PX)
		var probe: Dictionary = _raycast(
				space,
				probe_origin,
				dir * (_SURFACE_RAY_LENGTH_PX + _RAY_START_OFFSET_PX))
		if probe.is_empty():
			continue
		var hit_pos: Vector2 = probe["position"]
		var d_sq: float = global_position.distance_squared_to(hit_pos)
		if d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best_hit = probe
	if best_hit.is_empty():
		_is_anchored = false
		return
	_apply_surface_hit(best_hit)


## Returns the pursuit speed projection onto `tangent`. Falls back
## to a tangent-oriented climb/descend bias when the raw
## projection is too small to pick a direction confidently —
## specifically the stuck-on-wall case where the player sits at
## the spider's vertical level while it's anchored to a wall
## (tangent is vertical, `to_player.dot(tangent)` ≈ 0). The bias
## sign tracks `tangent.y` so a LEFT-wall tangent (world-up
## aligned) chooses "climb" and a RIGHT-wall tangent (world-down
## aligned) chooses "descend." Outside the ambiguous range the
## raw projection wins, so a player clearly above or below is
## still pursued in the honest direction.
func _pursuit_along_tangent(
		to_player: Vector2, tangent: Vector2) -> float:
	var raw: float = to_player.dot(tangent)
	if absf(raw) < _PURSUIT_BIAS_TIE_PX and absf(tangent.y) > 0.1:
		return signf(tangent.y) * _PURSUIT_CLIMB_BIAS_PX
	return raw


## Probes for a perpendicular surface meeting the old anchor at
## a convex corner. Returns an empty dictionary if velocity is
## near-zero (spider wasn't walking) or no perpendicular surface
## is within range. The probe origin is biased a hair past the
## old anchor's foot position (`_FOOT_OFFSET_PX + 1`) into the
## old surface — so a spider perched at the right edge of a
## floor casts a LEFT ray that enters the floor's right face from
## outside and hits it cleanly, without Godot's ray-on-boundary
## ambiguity.
func _convex_corner_probe(
		space: PhysicsDirectSpaceState2D) -> Dictionary:
	if _velocity.length_squared() <= 0.01:
		return {}
	var motion_dir: Vector2 = _velocity.normalized()
	var corner_origin: Vector2 = (
			global_position
			- _anchor_normal * (_FOOT_OFFSET_PX + 1.0))
	return _raycast(
			space,
			corner_origin,
			-motion_dir * _SURFACE_RAY_LENGTH_PX)


func _apply_surface_hit(hit: Dictionary) -> void:
	_is_anchored = true
	var surface_pos: Vector2 = hit["position"]
	var surface_normal: Vector2 = hit["normal"]
	_anchor_normal = surface_normal
	global_position = surface_pos + surface_normal * _FOOT_OFFSET_PX


## Variant of `_apply_surface_hit` that rejects the re-anchor if
## the teleport distance would exceed `_MAX_SNAP_DIST_SQ`. Used by
## the climb-up probe specifically — that probe scans for surfaces
## above the spider, and without the guard a distant ceiling
## feature many pixels overhead would yank the spider up
## instantly. Anchor-ray and forward-probe re-anchors are always
## close-range by construction, so they skip this check; guarding
## them was the cause of spiders clipping through floors when a
## single frame's fall exceeded the threshold.
func _try_apply_short_surface_hit(hit: Dictionary) -> bool:
	var surface_pos: Vector2 = hit["position"]
	var surface_normal: Vector2 = hit["normal"]
	var new_pos: Vector2 = (
			surface_pos + surface_normal * _FOOT_OFFSET_PX)
	if (new_pos.distance_squared_to(global_position)
			> _MAX_SNAP_DIST_SQ):
		return false
	_is_anchored = true
	_anchor_normal = surface_normal
	global_position = new_pos
	return true


static func _raycast(
		space: PhysicsDirectSpaceState2D,
		origin: Vector2,
		offset: Vector2,
		mask: int = _SURFACE_MASK) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.new()
	query.from = origin
	query.to = origin + offset
	query.collision_mask = mask
	query.collide_with_bodies = true
	# Cobwebs are Area2Ds on the web_tile layer, not physics bodies.
	# The surface mask already excludes other non-surface areas
	# (enemies, bug regions), so widening here to areas is safe.
	query.collide_with_areas = true
	return space.intersect_ray(query)
