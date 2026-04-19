class_name FallingCell
extends Area2D
## A single detached terrain cell that falls straight down under
## simple scalar gravity until it lands on solid terrain (or a
## previously-landed cell), at which point it paints itself back into
## `G.terrain` and despawns.
##
## No rigid-body physics, no rotation — replaces the rotating
## `TerrainChunkFragment` chunks because Godot's 2D physics wasn't
## stable enough for small detached groups. Cells in the same island
## are staggered by row (bottom first) so a stack slides cohesively
## instead of self-colliding.


const _GRAVITY_PX_PER_SEC2 := 900.0
const _MAX_SPEED_PX_PER_SEC := 900.0
const _TOUCH_DAMAGE := 8
const _TOUCH_COOLDOWN_SEC := 0.4
const _STUCK_MAX_CELLS := 4
## Safety: if a cell never finds terrain below (level has no floor),
## despawn after this many seconds instead of falling forever.
const _MAX_LIFETIME_SEC := 8.0
## Set true to print landing diagnostics.
const _DEBUG_LANDING := false


var _type: int = Frequency.Type.NONE
var _health: int = 255
var _delay_sec := 0.0
var _velocity_y := 0.0
var _cell_size_px := 8.0
var _canvas_rid: RID = RID()
var _landed := false
var _touch_cooldown_sec := 0.0
var _lifetime_sec := 0.0


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	# Layer 4 = player (bit 3). Only physics-body actors are detected
	# via `body_entered`; bugs/enemies are Area2Ds and ignored for
	# now.
	collision_mask = 1 << 3
	body_entered.connect(_on_body_entered)


# Must be called immediately after `add_child` so the cell knows its
# type before building its mesh/collision. `_ready` alone can't do
# this because it fires on tree-entry, before the spawner has a
# chance to pass in per-cell data.
func configure(
		world_pos: Vector2,
		type: int,
		health: int,
		delay_sec: float) -> void:
	global_position = world_pos
	_type = type
	_health = health
	_delay_sec = delay_sec
	if is_instance_valid(G.terrain) and G.terrain.settings != null:
		_cell_size_px = G.terrain.settings.cell_size_px
	_build_collision_and_mesh()


func _physics_process(delta: float) -> void:
	if _landed:
		return
	_touch_cooldown_sec = maxf(0.0, _touch_cooldown_sec - delta)
	_lifetime_sec += delta
	if _lifetime_sec >= _MAX_LIFETIME_SEC:
		queue_free()
		return
	if _delay_sec > 0.0:
		_delay_sec -= delta
		return
	_velocity_y = minf(
			_velocity_y + _GRAVITY_PX_PER_SEC2 * delta,
			_MAX_SPEED_PX_PER_SEC)
	var pre_y := global_position.y
	global_position.y = pre_y + _velocity_y * delta
	_check_landing(pre_y)


# Scan every cell the falling cell would cross this frame (pre_y to
# post-move y). Land in the first cell above a solid one. Avoids
# tunneling at high speed and guarantees the cell actually moved
# before landing.
func _check_landing(pre_y: float) -> void:
	if not is_instance_valid(G.terrain):
		return
	var cs := _cell_size_px
	var start_cy := int(floor(pre_y / cs))
	var end_cy := int(floor(global_position.y / cs))
	# Check cells strictly below the pre-move cell, up to and
	# including the cell we ended in. A cell already adjacent to
	# solid ground at spawn-time would otherwise land on frame 1
	# with zero displacement.
	for test_cy in range(start_cy + 1, end_cy + 2):
		var probe_y := (test_cy + 0.5) * cs
		var probe := Vector2(global_position.x, probe_y)
		if G.terrain.is_cell_non_empty(probe):
			var landing_cy := test_cy - 1
			global_position.y = (landing_cy + 0.5) * cs
			var landing_cx := int(floor(global_position.x / cs))
			global_position.x = (landing_cx + 0.5) * cs
			if _DEBUG_LANDING:
				print("FallingCell land type=%d at cell (%d,%d) pre_y=%.2f post_y=%.2f"
						% [_type, landing_cx, landing_cy,
								pre_y, global_position.y])
			_land()
			return


func _land() -> void:
	_landed = true
	_velocity_y = 0.0
	if is_instance_valid(G.terrain):
		G.terrain.paint_cell_at_world(
				global_position, _type, _health)
	# Liquid doesn't block the player — no need to evict.
	if _type != Frequency.Type.LIQUID:
		_evict_actors_from_cell()
	queue_free()


# After painting, any actor whose center sits inside this now-solid
# cell gets bumped upward to the first clear cell above. If the
# required push exceeds `_STUCK_MAX_CELLS`, the actor is damaged
# heavily (player) or killed outright (bug/enemy).
func _evict_actors_from_cell() -> void:
	for body in get_overlapping_bodies():
		_try_evict_actor(body)


func _try_evict_actor(body: Node) -> void:
	if not (body is Node2D):
		return
	var actor := body as Node2D
	var cs := _cell_size_px
	var cell_top_y := global_position.y - cs * 0.5
	if actor.global_position.y > global_position.y + cs * 0.5:
		return
	for step in range(_STUCK_MAX_CELLS + 1):
		var try_y := cell_top_y - (step + 0.5) * cs
		var probe := Vector2(actor.global_position.x, try_y)
		if not G.terrain.is_cell_non_empty(probe):
			actor.global_position = Vector2(
					actor.global_position.x,
					cell_top_y - (step + 1) * cs)
			# Pure displacement: don't carry over any falling
			# velocity the actor may have had before the push-up.
			if "velocity" in actor:
				var v: Vector2 = actor.get("velocity")
				actor.set("velocity", Vector2(v.x, 0.0))
			return
	# No room within threshold: lethal.
	if actor.has_method("apply_damage"):
		actor.call("apply_damage", 999)
	else:
		actor.queue_free()


func _on_body_entered(body: Node) -> void:
	# Liquid is non-damaging; players pass through it.
	if _type == Frequency.Type.LIQUID:
		return
	if _landed or _touch_cooldown_sec > 0.0:
		return
	if not (body is Node2D):
		return
	_touch_cooldown_sec = _TOUCH_COOLDOWN_SEC
	if body.has_method("apply_damage"):
		body.call("apply_damage", _TOUCH_DAMAGE)


func _build_collision_and_mesh() -> void:
	var cs := _cell_size_px
	var shape := RectangleShape2D.new()
	shape.size = Vector2(cs, cs)
	var coll := CollisionShape2D.new()
	coll.shape = shape
	add_child(coll)

	_canvas_rid = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(
			_canvas_rid, get_canvas_item())
	RenderingServer.canvas_item_set_visibility_layer(_canvas_rid, 3)
	var color := Frequency.color_of(_type_to_frequency())
	var rect := Rect2(Vector2(-cs * 0.5, -cs * 0.5), Vector2(cs, cs))
	RenderingServer.canvas_item_add_rect(_canvas_rid, rect, color)


func _type_to_frequency() -> int:
	# Terrain types already match Frequency enum for solid colors.
	return _type


func _exit_tree() -> void:
	if _canvas_rid.is_valid():
		RenderingServer.free_rid(_canvas_rid)
		_canvas_rid = RID()
