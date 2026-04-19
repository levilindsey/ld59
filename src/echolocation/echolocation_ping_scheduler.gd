class_name EcholocationPingScheduler
extends RefCounted
## Helper for `EcholocationRenderer`. Walks the cached terrain type
## image to find outward-facing surface segments near a pulse and
## spawns an EchoPing per segment into the renderer's ping pool.
## Kept as a separate file so the renderer script stays under
## gdlint's file-length cap.
##
## Terrain state is synced in via `sync_terrain_state` whenever the
## renderer rebuilds its density/type textures; scheduling itself is
## stateless aside from that cache.


## Maximum world-px distance scanned for surfaces. Decoupled from
## `pulse.max_radius_px` because the visible stipple wave fades out
## well before the pulse's damage radius, so ping lines beyond this
## cap don't register visually anyway. Capping the scan gives a
## large speedup: bbox area scales as radius², so cutting from
## 1000 → 600 is a ~2.8× reduction in cells inspected.
const _PING_SCAN_MAX_RADIUS_PX := 600.0
## Minimum dot(outward_normal, toward_pulse) required to keep a
## segment. Segments whose normal points AWAY from the pulse (i.e.,
## back-of-wall surfaces hidden from the player) get culled. 0.0
## keeps everything ≥ perpendicular; positive values tighten to
## only strongly-facing surfaces.
const _PING_PLAYER_FACING_THRESHOLD := 0.0
## Safety cap on LoS DDA walk length (in grid cells crossed). A miss
## past this length is treated as "not occluded" so the segment
## schedules. At cell_size=8 px, 200 cells = 1600 px — more than any
## pulse radius we actually use.
const _PING_LOS_MAX_STEPS := 200


var _type_image_bytes := PackedByteArray()
var _type_image_width: int = 0
var _type_image_height: int = 0
var _type_image_origin_cells := Vector2i.ZERO
var _cell_size_px: float = 8.0


## Called by `EcholocationRenderer._rebuild_terrain_textures` to push
## the newest type image into this scheduler's cache. Cheap: the
## PackedByteArray assignment is copy-on-write.
func sync_terrain_state(
		bytes: PackedByteArray,
		width: int,
		height: int,
		origin_cells: Vector2i,
		cell_size_px: float,
) -> void:
	_type_image_bytes = bytes
	_type_image_width = width
	_type_image_height = height
	_type_image_origin_cells = origin_cells
	_cell_size_px = cell_size_px


## Enumerate every outward-facing surface segment near `pulse.center`
## and write a ping per segment into `ping_pool`. `elapsed_sec` +
## `ping_delay_scale` drive each ping's scheduled_time_sec. Stops
## scanning early once the pool fills up; remaining segments are
## silently dropped.
##
## Cost scales with the pulse's damage-radius bounding box (in cells),
## not with a fixed ray count — a 400 px pulse at 8 px/cell scans a
## ~100×100 = 10k-cell window, four times, for ~40k byte reads +
## minimal arithmetic. Sub-millisecond in practice.
func schedule_pings_for_pulse(
		pulse: EchoPulse,
		ping_pool: Array[EchoPing],
		elapsed_sec: float,
		ping_delay_scale: float,
) -> void:
	var cell_size := _cell_size_px
	var type_w := _type_image_width
	var type_h := _type_image_height
	if (_type_image_bytes.is_empty()
			or cell_size <= 0.0
			or type_w <= 0
			or type_h <= 0):
		return

	var origin_cells := _type_image_origin_cells
	var scan_radius_px: float = minf(
			pulse.max_radius_px, _PING_SCAN_MAX_RADIUS_PX)
	var pulse_cell_x: int = (int(floor(pulse.center.x / cell_size))
			- origin_cells.x)
	var pulse_cell_y: int = (int(floor(pulse.center.y / cell_size))
			- origin_cells.y)
	var radius_cells: int = int(ceil(scan_radius_px / cell_size))
	var min_cx: int = maxi(0, pulse_cell_x - radius_cells)
	var max_cx: int = mini(type_w - 1, pulse_cell_x + radius_cells)
	var min_cy: int = maxi(0, pulse_cell_y - radius_cells)
	var max_cy: int = mini(type_h - 1, pulse_cell_y + radius_cells)
	if min_cx > max_cx or min_cy > max_cy:
		return

	var is_full_circle: bool = pulse.arc_radians >= TAU - 0.01
	var cos_half_arc: float = cos(pulse.arc_radians * 0.5)
	var aim_x: float = cos(pulse.arc_direction_radians)
	var aim_y: float = sin(pulse.arc_direction_radians)
	var radius_sq: float = scan_radius_px * scan_radius_px

	# Single flag shared across the four direction scans so we can
	# bail out without stacking up one `return` per direction.
	var pool_exhausted := false

	# NORTH faces — cell solid, cell above (cy - 1) empty. Outward
	# normal points -y (up in screen coords).
	var normal_north := Vector2(0.0, -1.0)
	for cy in range(min_cy, max_cy + 1):
		if pool_exhausted:
			break
		var run_start: int = -1
		for cx in range(min_cx, max_cx + 2):
			var has_face: bool = false
			if cx <= max_cx and _type_byte_at(cx, cy) != 0:
				if cy <= 0 or _type_byte_at(cx, cy - 1) == 0:
					has_face = true
			if has_face:
				if run_start < 0:
					run_start = cx
			elif run_start >= 0:
				var run_end: int = cx - 1
				var sx: float = (
						(run_start + origin_cells.x) * cell_size)
				var ex: float = (
						(run_end + 1 + origin_cells.x) * cell_size)
				var y: float = (cy + origin_cells.y) * cell_size
				if not _try_schedule_segment_ping(
						pulse, ping_pool, elapsed_sec,
						ping_delay_scale,
						Vector2(sx, y), Vector2(ex, y),
						normal_north, is_full_circle, cos_half_arc,
						aim_x, aim_y, radius_sq):
					pool_exhausted = true
					break
				run_start = -1

	# SOUTH faces — cell below (cy + 1) empty. Normal +y (down).
	var normal_south := Vector2(0.0, 1.0)
	for cy in range(min_cy, max_cy + 1):
		if pool_exhausted:
			break
		var run_start: int = -1
		for cx in range(min_cx, max_cx + 2):
			var has_face: bool = false
			if cx <= max_cx and _type_byte_at(cx, cy) != 0:
				if (cy >= type_h - 1
						or _type_byte_at(cx, cy + 1) == 0):
					has_face = true
			if has_face:
				if run_start < 0:
					run_start = cx
			elif run_start >= 0:
				var run_end: int = cx - 1
				var sx: float = (
						(run_start + origin_cells.x) * cell_size)
				var ex: float = (
						(run_end + 1 + origin_cells.x) * cell_size)
				var y: float = ((cy + 1 + origin_cells.y)
						* cell_size)
				if not _try_schedule_segment_ping(
						pulse, ping_pool, elapsed_sec,
						ping_delay_scale,
						Vector2(sx, y), Vector2(ex, y),
						normal_south, is_full_circle, cos_half_arc,
						aim_x, aim_y, radius_sq):
					pool_exhausted = true
					break
				run_start = -1

	# WEST faces — cell to left (cx - 1) empty. Normal -x (left).
	var normal_west := Vector2(-1.0, 0.0)
	for cx in range(min_cx, max_cx + 1):
		if pool_exhausted:
			break
		var run_start: int = -1
		for cy in range(min_cy, max_cy + 2):
			var has_face: bool = false
			if cy <= max_cy and _type_byte_at(cx, cy) != 0:
				if cx <= 0 or _type_byte_at(cx - 1, cy) == 0:
					has_face = true
			if has_face:
				if run_start < 0:
					run_start = cy
			elif run_start >= 0:
				var run_end: int = cy - 1
				var sy: float = (
						(run_start + origin_cells.y) * cell_size)
				var ey: float = (
						(run_end + 1 + origin_cells.y) * cell_size)
				var x: float = (cx + origin_cells.x) * cell_size
				if not _try_schedule_segment_ping(
						pulse, ping_pool, elapsed_sec,
						ping_delay_scale,
						Vector2(x, sy), Vector2(x, ey),
						normal_west, is_full_circle, cos_half_arc,
						aim_x, aim_y, radius_sq):
					pool_exhausted = true
					break
				run_start = -1

	# EAST faces — cell to right (cx + 1) empty. Normal +x (right).
	var normal_east := Vector2(1.0, 0.0)
	for cx in range(min_cx, max_cx + 1):
		if pool_exhausted:
			break
		var run_start: int = -1
		for cy in range(min_cy, max_cy + 2):
			var has_face: bool = false
			if cy <= max_cy and _type_byte_at(cx, cy) != 0:
				if (cx >= type_w - 1
						or _type_byte_at(cx + 1, cy) == 0):
					has_face = true
			if has_face:
				if run_start < 0:
					run_start = cy
			elif run_start >= 0:
				var run_end: int = cy - 1
				var sy: float = (
						(run_start + origin_cells.y) * cell_size)
				var ey: float = (
						(run_end + 1 + origin_cells.y) * cell_size)
				var x: float = ((cx + 1 + origin_cells.x)
						* cell_size)
				if not _try_schedule_segment_ping(
						pulse, ping_pool, elapsed_sec,
						ping_delay_scale,
						Vector2(x, sy), Vector2(x, ey),
						normal_east, is_full_circle, cos_half_arc,
						aim_x, aim_y, radius_sq):
					pool_exhausted = true
					break
				run_start = -1


func _type_byte_at(cx: int, cy: int) -> int:
	if (cx < 0 or cy < 0
			or cx >= _type_image_width
			or cy >= _type_image_height):
		return 0
	return _type_image_bytes[cy * _type_image_width + cx]


## Return true when the straight line from `from_world` to `to_world`
## passes through any non-empty cell between its origin and target.
## Uses Amanatides-Woo grid DDA on `_type_image_bytes`, so no C++
## crossings. The origin cell (whatever cell contains `from_world`)
## and the target cell (whatever contains `to_world`) are NOT
## checked — we only care about intermediate cells that would occlude
## the pulse's line of sight. Out-of-bounds cells pass (treated as
## empty, so segments near the world edge don't false-positive).
func _los_occluded(from_world: Vector2, to_world: Vector2) -> bool:
	if _type_image_bytes.is_empty() or _cell_size_px <= 0.0:
		return false

	var cell_size := _cell_size_px
	var from_cx_f: float = (from_world.x / cell_size
			- float(_type_image_origin_cells.x))
	var from_cy_f: float = (from_world.y / cell_size
			- float(_type_image_origin_cells.y))
	var to_cx_f: float = (to_world.x / cell_size
			- float(_type_image_origin_cells.x))
	var to_cy_f: float = (to_world.y / cell_size
			- float(_type_image_origin_cells.y))

	var target_cx: int = int(floor(to_cx_f))
	var target_cy: int = int(floor(to_cy_f))
	var cx: int = int(floor(from_cx_f))
	var cy: int = int(floor(from_cy_f))

	var dx: float = to_cx_f - from_cx_f
	var dy: float = to_cy_f - from_cy_f
	var abs_dx: float = absf(dx)
	var abs_dy: float = absf(dy)
	var step_x: int = 0 if abs_dx < 1e-9 else (1 if dx > 0.0 else -1)
	var step_y: int = 0 if abs_dy < 1e-9 else (1 if dy > 0.0 else -1)

	# Same cell or epsilon-short segment: nothing between origin and
	# target, so no occluder can be in the way.
	var is_trivial := ((cx == target_cx and cy == target_cy)
			or (step_x == 0 and step_y == 0))
	var blocked := false
	if not is_trivial:
		var t_delta_x: float = INF if step_x == 0 else 1.0 / abs_dx
		var t_delta_y: float = INF if step_y == 0 else 1.0 / abs_dy
		var t_max_x: float = INF
		if step_x > 0:
			t_max_x = (float(cx + 1) - from_cx_f) / abs_dx
		elif step_x < 0:
			t_max_x = (from_cx_f - float(cx)) / abs_dx
		var t_max_y: float = INF
		if step_y > 0:
			t_max_y = (float(cy + 1) - from_cy_f) / abs_dy
		elif step_y < 0:
			t_max_y = (from_cy_f - float(cy)) / abs_dy
		for _step in range(_PING_LOS_MAX_STEPS):
			if t_max_x < t_max_y:
				cx += step_x
				t_max_x += t_delta_x
			else:
				cy += step_y
				t_max_y += t_delta_y
			# Reached target — line of sight is clear.
			if cx == target_cx and cy == target_cy:
				break
			# Off the grid — treat as empty (not a blocker).
			if (cx < 0 or cy < 0
					or cx >= _type_image_width
					or cy >= _type_image_height):
				break
			# Intermediate cell is solid → blocks the ray.
			if _type_byte_at(cx, cy) != 0:
				blocked = true
				break
	return blocked


## Schedule a ping for the given surface segment if it's in range and
## within the pulse's arc, and its outward normal faces the pulse
## emitter. Returns false only when the ping pool is exhausted
## (caller halts further scan).
func _try_schedule_segment_ping(
		pulse: EchoPulse,
		ping_pool: Array[EchoPing],
		elapsed_sec: float,
		ping_delay_scale: float,
		seg_start: Vector2,
		seg_end: Vector2,
		normal: Vector2,
		is_full_circle: bool,
		cos_half_arc: float,
		aim_x: float,
		aim_y: float,
		radius_sq: float,
) -> bool:
	var seg_vec: Vector2 = seg_end - seg_start
	var seg_len_sq: float = seg_vec.length_squared()
	if seg_len_sq < 1e-6:
		return true

	# Player-facing cull: the segment's outward normal must be
	# pointing roughly toward the pulse emitter. Skips back-of-wall
	# surfaces that are hidden from the player.
	var seg_midpoint: Vector2 = seg_start + seg_vec * 0.5
	var to_pulse: Vector2 = pulse.center - seg_midpoint
	var to_pulse_len: float = to_pulse.length()
	if to_pulse_len > 1e-3:
		var facing: float = normal.dot(to_pulse) / to_pulse_len
		if facing < _PING_PLAYER_FACING_THRESHOLD:
			return true

	var to_start: Vector2 = pulse.center - seg_start
	var proj_t: float = to_start.dot(seg_vec) / seg_len_sq
	proj_t = clampf(proj_t, 0.0, 1.0)
	var closest: Vector2 = seg_start + seg_vec * proj_t
	var dx: float = closest.x - pulse.center.x
	var dy: float = closest.y - pulse.center.y
	var dist_sq: float = dx * dx + dy * dy
	var dist: float = sqrt(dist_sq)
	var out_of_arc: bool = (not is_full_circle
			and dist > 1e-3
			and (dx * aim_x + dy * aim_y) / dist < cos_half_arc)
	# Combined skip conditions — any one of them means the segment
	# is invisible to this pulse. Bundled so the function stays below
	# gdlint's max-returns cap.
	if (dist_sq > radius_sq
			or out_of_arc
			or _los_occluded(pulse.center, closest)):
		return true

	var slot: int = _find_free_ping_slot(ping_pool)
	if slot < 0:
		return false

	var ping := EchoPing.new()
	ping.world_pos = closest
	ping.segment_start = seg_start
	ping.segment_end = seg_end
	ping.segment_normal = normal
	ping.frequency = pulse.frequency
	ping.hit_angle_rad = atan2(dy, dx)
	ping.hit_distance_px = dist
	ping.scheduled_time_sec = (elapsed_sec
			+ 2.0 * dist / pulse.speed_px_per_sec
			* ping_delay_scale)
	ping.age_sec = -1.0
	ping_pool[slot] = ping
	return true


func _find_free_ping_slot(ping_pool: Array[EchoPing]) -> int:
	for i in range(ping_pool.size()):
		if ping_pool[i] == null:
			return i
	return -1
