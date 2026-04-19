#include "terrain_world.h"

#include "connected_components.h"
#include "density_splat.h"
#include "douglas_peucker.h"
#include "marching_squares.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/physics_server2d.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/classes/viewport.hpp>
#include <godot_cpp/classes/window.hpp>
#include <godot_cpp/classes/world2d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>
#include <cstring>

namespace godot {

using terrain::Chunk;
using terrain::ChunkManager;
using terrain::ConnectedComponents;
using terrain::DetachedIsland;
using terrain::FlowStep;
using terrain::MeshResult;
using terrain::RemeshJob;
using terrain::RemeshResult;
using terrain::WorkerPool;

namespace {

// World-cell type lookup via ChunkManager. Returns TYPE_NONE if the
// containing chunk doesn't exist.
uint8_t world_cell_type(
		terrain::ChunkManager &manager,
		int chunk_cells,
		int32_t world_cx,
		int32_t world_cy) {
	int32_t chunk_x = world_cx / chunk_cells;
	int32_t chunk_y = world_cy / chunk_cells;
	int32_t local_x = world_cx - chunk_x * chunk_cells;
	int32_t local_y = world_cy - chunk_y * chunk_cells;
	if (local_x < 0) { local_x += chunk_cells; chunk_x -= 1; }
	if (local_y < 0) { local_y += chunk_cells; chunk_y -= 1; }
	terrain::Chunk *c = manager.get(Vector2i(chunk_x, chunk_y));
	if (c == nullptr) {
		return TerrainSettings::TYPE_NONE;
	}
	return c->type_per_cell[local_y * chunk_cells + local_x];
}

// Build a collision-density snapshot for a chunk. Starts from the
// real density (cross-chunk consistent via bake + corner refresh)
// and zeros any corner whose all 4 adjacent world cells are
// non-collidable (NONE or LIQUID). Cross-chunk neighbors are queried
// via ChunkManager so boundary corners stay consistent across
// chunks.
std::vector<uint8_t> build_collision_density(
		terrain::ChunkManager &manager,
		const terrain::Chunk &chunk,
		int chunk_cells) {
	std::vector<uint8_t> out = chunk.density;
	const int s = chunk_cells + 1;
	const int32_t base_x = chunk.coords.x * chunk_cells;
	const int32_t base_y = chunk.coords.y * chunk_cells;
	for (int y = 0; y <= chunk_cells; y++) {
		for (int x = 0; x <= chunk_cells; x++) {
			const int32_t wcx_r = base_x + x;
			const int32_t wcy_r = base_y + y;
			bool all_non_collidable = true;
			// 4 adjacent cells sharing this corner:
			//   (wcx_r - 1, wcy_r - 1), (wcx_r, wcy_r - 1),
			//   (wcx_r - 1, wcy_r),     (wcx_r, wcy_r).
			for (int dy = -1; dy <= 0 && all_non_collidable; dy++) {
				for (int dx = -1; dx <= 0; dx++) {
					const uint8_t t = world_cell_type(
							manager, chunk_cells,
							wcx_r + dx, wcy_r + dy);
					if (t != TerrainSettings::TYPE_NONE
							&& t != TerrainSettings::TYPE_LIQUID) {
						all_non_collidable = false;
						break;
					}
				}
			}
			if (all_non_collidable) {
				out[y * s + x] = 0;
			}
		}
	}
	return out;
}

// After a cell's type is cleared, rebuild its 4 corner densities by
// checking whether any of the (up to 4) cells sharing each corner
// still has a non-NONE type. Writes 255 if any non-NONE neighbor
// exists, else 0. Only inspects cells within the same chunk for now;
// cross-chunk overlap corners are slightly approximate but the
// neighbor chunk's own remesh will correct its side.
void refresh_corners_after_clear(
		terrain::Chunk *chunk, int cx, int cy) {
	const int cells = chunk->cells;
	const int s = cells + 1;
	for (int dyc = 0; dyc <= 1; dyc++) {
		for (int dxc = 0; dxc <= 1; dxc++) {
			const int corner_x = cx + dxc;
			const int corner_y = cy + dyc;
			bool any_solid = false;
			for (int a = -1; a <= 0 && !any_solid; a++) {
				for (int b = -1; b <= 0; b++) {
					const int ncx = corner_x + b;
					const int ncy = corner_y + a;
					if (ncx < 0 || ncy < 0
							|| ncx >= cells || ncy >= cells) {
						continue;
					}
					if (chunk->type_per_cell[ncy * cells + ncx]
							!= TerrainSettings::TYPE_NONE) {
						any_solid = true;
						break;
					}
				}
			}
			chunk->density[corner_y * s + corner_x] =
					any_solid ? 255 : 0;
		}
	}
}

// Free the existing per-triangle shape RIDs on a chunk. The body's
// shape list is cleared separately by the caller via
// `body_clear_shapes` before new shapes are added.
void free_shape_rids(PhysicsServer2D *ps, terrain::Chunk *chunk) {
	for (const RID &rid : chunk->shape_rids) {
		if (rid.is_valid()) {
			ps->free_rid(rid);
		}
	}
	chunk->shape_rids.clear();
}

// Replace the chunk's static-body shape list with one
// ConvexPolygonShape2D per fully-solid cell. We use axis-aligned
// quads (not the marching-squares triangulation) so there are no
// diagonal internal edges for Godot's depenetration to push against.
// Fan-triangulating a case-15 cell from one corner produces two
// right triangles sharing a diagonal — when the player penetrates,
// the diagonal pushes the character sideways instead of straight up,
// and the two triangles' opposing normals can trap the character at
// "half-penetrated" equilibrium.
//
// With binary 0/255 density and iso=255, only case 15 (all 4 corners
// inside) has any interior area. Partial cases (1..14) collapse to
// degenerate zero-area interiors, so skipping them loses no collision
// surface.
void rebuild_collision_cells(
		PhysicsServer2D *ps,
		terrain::Chunk *chunk,
		const std::vector<uint8_t> &density,
		int cells,
		float cell_size_px,
		Vector2 origin_px,
		uint8_t iso) {
	if (chunk->static_body_rid.is_valid()) {
		ps->body_clear_shapes(chunk->static_body_rid);
	}
	free_shape_rids(ps, chunk);

	const int stride = cells + 1;
	chunk->shape_rids.reserve(cells * cells);

	PackedVector2Array quad;
	quad.resize(4);

	int count = 0;
	for (int y = 0; y < cells; y++) {
		for (int x = 0; x < cells; x++) {
			const uint8_t d_bl = density[(y + 1) * stride + x];
			const uint8_t d_br = density[(y + 1) * stride + (x + 1)];
			const uint8_t d_tr = density[y * stride + (x + 1)];
			const uint8_t d_tl = density[y * stride + x];
			if (d_bl < iso || d_br < iso || d_tr < iso || d_tl < iso) {
				continue;
			}

			const float x0 = origin_px.x + x * cell_size_px;
			const float y0 = origin_px.y + y * cell_size_px;
			const float x1 = x0 + cell_size_px;
			const float y1 = y0 + cell_size_px;

			// CW in Godot's Y-down coord system: TL → TR → BR → BL.
			quad[0] = Vector2(x0, y0);
			quad[1] = Vector2(x1, y0);
			quad[2] = Vector2(x1, y1);
			quad[3] = Vector2(x0, y1);

			RID shape = ps->convex_polygon_shape_create();
			ps->shape_set_data(shape, quad);
			ps->body_add_shape(chunk->static_body_rid, shape);
			chunk->shape_rids.push_back(shape);
			count++;
		}
	}
	UtilityFunctions::print(
			String("kbterrain rebuild_collision_cells: chunk=")
			+ String::num(chunk->coords.x) + String(",")
			+ String::num(chunk->coords.y) + String(" cells=")
			+ String::num(count));
}

} // namespace

TerrainWorld::TerrainWorld() {
	_manager = std::make_unique<ChunkManager>();
	_worker = std::make_unique<WorkerPool>();
	_flow_step = std::make_unique<FlowStep>();
	_type_to_rgba_lut.assign(256, 0);
}

TerrainWorld::~TerrainWorld() {
	if (_worker) {
		_worker->stop();
	}
	// Free per-chunk RIDs.
	if (_manager) {
		for (auto &pair : _manager->all_mut()) {
			_free_chunk_rids(pair.second.get());
		}
	}
	// Free the parent canvas item.
	if (_parent_canvas_item.is_valid()) {
		RenderingServer::get_singleton()->free_rid(_parent_canvas_item);
	}
}

void TerrainWorld::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_settings", "settings"),
			&TerrainWorld::set_settings);
	ClassDB::bind_method(D_METHOD("get_settings"),
			&TerrainWorld::get_settings);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "settings",
						 PROPERTY_HINT_RESOURCE_TYPE,
						 "TerrainSettings"),
			"set_settings", "get_settings");

	ClassDB::bind_method(
			D_METHOD("set_cells", "coords", "bytes"),
			&TerrainWorld::set_cells);
	ClassDB::bind_method(
			D_METHOD("damage", "world_pos", "radius_px", "damage",
					"frequency_mask"),
			&TerrainWorld::damage);
	ClassDB::bind_method(
			D_METHOD("damage_with_falloff", "world_pos",
					"surface_max_radius_px",
					"surface_full_radius_px",
					"surface_full_damage",
					"surface_min_damage",
					"proximity_max_radius_px",
					"proximity_full_radius_px",
					"proximity_full_damage",
					"proximity_min_damage",
					"frequency_mask"),
			&TerrainWorld::damage_with_falloff);
	ClassDB::bind_method(
			D_METHOD("carve", "world_pos", "radius_px", "strength"),
			&TerrainWorld::carve);
	ClassDB::bind_method(
			D_METHOD("fill", "world_pos", "radius_px", "strength"),
			&TerrainWorld::fill);
	ClassDB::bind_method(
			D_METHOD("sample_density", "world_pos"),
			&TerrainWorld::sample_density);
	ClassDB::bind_method(D_METHOD("is_solid", "world_pos"),
			&TerrainWorld::is_solid);
	ClassDB::bind_method(D_METHOD("is_cell_non_empty", "world_pos"),
			&TerrainWorld::is_cell_non_empty);
	ClassDB::bind_method(
			D_METHOD("is_cell_type_at", "world_pos", "type"),
			&TerrainWorld::is_cell_type_at);
	ClassDB::bind_method(
			D_METHOD("is_cell_collidable", "world_pos"),
			&TerrainWorld::is_cell_collidable);
	ClassDB::bind_method(
			D_METHOD("get_surface_height", "world_x", "search_max_y_px"),
			&TerrainWorld::get_surface_height);
	ClassDB::bind_method(D_METHOD("get_stats"),
			&TerrainWorld::get_stats);
	ClassDB::bind_method(D_METHOD("build_density_image"),
			&TerrainWorld::build_density_image);
	ClassDB::bind_method(D_METHOD("build_type_image"),
			&TerrainWorld::build_type_image);
	ClassDB::bind_method(D_METHOD("get_world_cell_origin"),
			&TerrainWorld::get_world_cell_origin);
	ClassDB::bind_method(D_METHOD("get_world_cell_size"),
			&TerrainWorld::get_world_cell_size);
	ClassDB::bind_method(D_METHOD("sample_fluid_velocity", "world_pos"),
			&TerrainWorld::sample_fluid_velocity);
	ClassDB::bind_method(D_METHOD("clear_all"),
			&TerrainWorld::clear_all);

	ADD_SIGNAL(MethodInfo("chunk_modified",
			PropertyInfo(Variant::VECTOR2I, "coords")));
	ADD_SIGNAL(MethodInfo("tile_destroyed",
			PropertyInfo(Variant::VECTOR2, "world_pos"),
			PropertyInfo(Variant::INT, "type")));
	// Fragment detachment signal: fires once per detached island.
	// GDScript constructs a TerrainChunkFragment RigidBody2D from
	// the pre-baked mesh + collision data.
	ADD_SIGNAL(MethodInfo("fragment_detached",
			PropertyInfo(Variant::VECTOR2, "origin_world"),
			PropertyInfo(Variant::PACKED_VECTOR2_ARRAY, "mesh_verts"),
			PropertyInfo(Variant::PACKED_INT32_ARRAY, "mesh_indices"),
			PropertyInfo(Variant::PACKED_COLOR_ARRAY, "mesh_colors"),
			PropertyInfo(Variant::PACKED_VECTOR2_ARRAY, "collision_segments"),
			PropertyInfo(Variant::VECTOR2I, "island_size_cells"),
			PropertyInfo(Variant::PACKED_BYTE_ARRAY, "cell_types"),
			PropertyInfo(Variant::PACKED_BYTE_ARRAY, "cell_healths")));

	ClassDB::bind_method(
			D_METHOD("paint_cell_at_world", "world_pos", "type", "health"),
			&TerrainWorld::paint_cell_at_world);
}

void TerrainWorld::_notification(int what) {
	switch (what) {
		case NOTIFICATION_ENTER_TREE: {
			_ensure_initialized();
			// Process drains worker results; in editor mode the
			// worker isn't started so process is a cheap no-op.
			set_process(true);
		} break;
		case NOTIFICATION_EXIT_TREE: {
			if (_worker) {
				_worker->stop();
			}
		} break;
		case NOTIFICATION_PROCESS: {
			_on_process();
		} break;
		default:
			break;
	}
}

void TerrainWorld::set_settings(Ref<TerrainSettings> p_settings) {
	_settings = p_settings;
	if (_settings.is_valid()) {
		_cells_cached = _settings->chunk_cells;
		_cell_size_px_cached = _settings->cell_size_px;
		_iso_cached = _settings->iso;
		_simplify_eps_cached = _settings->simplify_epsilon_px;
		_rebuild_type_lut();
	}
}

void TerrainWorld::_ensure_initialized() {
	_editor_mode = Engine::get_singleton()->is_editor_hint();

	if (!_settings.is_valid()) {
		Ref<TerrainSettings> fallback;
		fallback.instantiate();
		set_settings(fallback);
	}
	if (!_parent_canvas_item.is_valid()) {
		_parent_canvas_item =
				RenderingServer::get_singleton()->canvas_item_create();
		RenderingServer::get_singleton()->canvas_item_set_parent(
				_parent_canvas_item, get_canvas_item());
		// Match per-chunk visibility_layer so the parent passes
		// both scene (cull_mask 1) and tag (cull_mask 2) culls.
		RenderingServer::get_singleton()
				->canvas_item_set_visibility_layer(
						_parent_canvas_item, 3);
	}
	// The worker thread only runs at runtime. In editor mode we
	// mesh synchronously (in _queue_remesh) so designers see the
	// MS preview without spawning background threads from inside
	// the Godot editor process.
	if (_worker && !_editor_mode) {
		_worker->start();
	}
}

void TerrainWorld::_rebuild_type_lut() {
	if (_type_to_rgba_lut.size() != 256) {
		_type_to_rgba_lut.assign(256, 0);
	}
	for (int t = 0; t < 256; t++) {
		Color c = _settings.is_valid()
				? _settings->color_for_type(t)
				: Color(0, 0, 0, 0);
		const uint8_t r = static_cast<uint8_t>(
				std::clamp(c.r, 0.0f, 1.0f) * 255.0f + 0.5f);
		const uint8_t g = static_cast<uint8_t>(
				std::clamp(c.g, 0.0f, 1.0f) * 255.0f + 0.5f);
		const uint8_t b = static_cast<uint8_t>(
				std::clamp(c.b, 0.0f, 1.0f) * 255.0f + 0.5f);
		const uint8_t a = static_cast<uint8_t>(
				std::clamp(c.a, 0.0f, 1.0f) * 255.0f + 0.5f);
		_type_to_rgba_lut[t] = terrain::pack_rgba8(r, g, b, a);
	}
}

int TerrainWorld::_frequency_to_bit(int freq) const {
	if (freq <= 0 || freq > 30) {
		return 0;
	}
	return 1 << freq;
}

void TerrainWorld::set_cells(Vector2i coords, const PackedByteArray &bytes) {
	_ensure_initialized();
	const int cells = _cells_cached;
	const int density_size = (cells + 1) * (cells + 1);
	const int per_cell_size = cells * cells;
	const int total = density_size + 2 * per_cell_size;
	if (bytes.size() != total) {
		UtilityFunctions::push_warning(
				"TerrainWorld.set_cells: expected " + String::num(total)
				+ " bytes, got " + String::num(bytes.size()));
		return;
	}

	Chunk *chunk = _manager->get_or_create(coords, cells);
	for (int i = 0; i < density_size; i++) {
		chunk->density[i] = bytes[i];
	}
	for (int i = 0; i < per_cell_size; i++) {
		chunk->type_per_cell[i] = bytes[density_size + i];
	}
	for (int i = 0; i < per_cell_size; i++) {
		chunk->health_per_cell[i] =
				bytes[density_size + per_cell_size + i];
	}
	chunk->generation.fetch_add(1);
	_queue_remesh_and_neighbors(chunk);
}

void TerrainWorld::_queue_remesh(Chunk *chunk) {
	_dirty_chunks.insert(chunk->coords);

	RemeshJob job;
	job.coords = chunk->coords;
	job.submitted_generation = chunk->generation.load();
	job.cells = chunk->cells;
	job.cell_size_px = _cell_size_px_cached;
	job.iso = static_cast<uint8_t>(_iso_cached);
	job.origin_px = chunk->origin_px(_cell_size_px_cached);
	job.density_snapshot = chunk->density;
	job.collision_density_snapshot = build_collision_density(
			*_manager, *chunk, _cells_cached);
	job.type_snapshot = chunk->type_per_cell;
	job.type_to_color_rgba = _type_to_rgba_lut;
	job.simplify_epsilon_px = _simplify_eps_cached;

	// Collision update on the main thread, BEFORE handing the job
	// to the worker. This keeps the player from colliding with
	// phantom shapes at old cell positions while the worker catches
	// up with the render remesh — a detach of many chunks could
	// leave stale collision active for multiple frames otherwise.
	// Duplicates the worker's collision pass (it'll be overwritten
	// when the worker result integrates), but cheap: mesh_chunk on
	// a 32x32 density grid is ~microseconds.
	if (!_editor_mode
			&& !job.collision_density_snapshot.empty()) {
		_update_collision_sync(chunk, job.collision_density_snapshot,
				job.cells, job.cell_size_px, job.origin_px, job.iso);
	}

	if (_editor_mode) {
		// Synchronous: the @tool preview wants to see the result
		// immediately, no worker available.
		RemeshResult result;
		terrain::process_remesh_job(job, result);
		_integrate_one(result);
	} else {
		_worker->submit(std::move(job));
	}
}

void TerrainWorld::_update_collision_sync(
		Chunk *chunk,
		const std::vector<uint8_t> &collision_density,
		int cells,
		float cell_size_px,
		Vector2 origin_px,
		uint8_t iso) {
	terrain::MeshResult coll_mesh;
	terrain::mesh_chunk(
			collision_density.data(),
			cells,
			cell_size_px,
			origin_px,
			iso,
			0xFFFFFFFFu,
			nullptr,
			nullptr,
			coll_mesh);
	PhysicsServer2D *ps = PhysicsServer2D::get_singleton();
	if (!chunk->static_body_rid.is_valid()) {
		chunk->static_body_rid = ps->body_create();
		ps->body_set_mode(chunk->static_body_rid,
				PhysicsServer2D::BODY_MODE_STATIC);
		ps->body_set_collision_layer(chunk->static_body_rid,
				_settings.is_valid()
						? _settings->collision_layer
						: 1);
		ps->body_set_collision_mask(chunk->static_body_rid,
				_settings.is_valid()
						? _settings->collision_mask
						: 0);
		Viewport *vp = get_viewport();
		if (vp != nullptr) {
			Ref<World2D> world_2d = vp->get_world_2d();
			if (world_2d.is_valid()) {
				ps->body_set_space(chunk->static_body_rid,
						world_2d->get_space());
			}
		}
	}
	rebuild_collision_cells(
			ps, chunk, collision_density, cells, cell_size_px,
			origin_px, iso);
}

void TerrainWorld::_queue_remesh_and_neighbors(Chunk *chunk) {
	_queue_remesh(chunk);
	// Neighbor-chunk collision density depends on this chunk's cells
	// along the shared edge. Schedule their remeshes too. Used for
	// relatively rare events (bake, damage, paint, CC detach) where
	// the extra work is acceptable. Flow step deliberately skips
	// this because it mutates hundreds of cells per step and the
	// cascade would backlog the worker.
	const Vector2i coord = chunk->coords;
	const Vector2i neighbors[4] = {
		Vector2i(coord.x - 1, coord.y),
		Vector2i(coord.x + 1, coord.y),
		Vector2i(coord.x, coord.y - 1),
		Vector2i(coord.x, coord.y + 1),
	};
	for (const Vector2i &nc : neighbors) {
		Chunk *n = _manager->get(nc);
		if (n == nullptr) {
			continue;
		}
		_queue_remesh(n);
	}
}


void TerrainWorld::_integrate_results() {
	if (!_worker) {
		return;
	}
	std::vector<RemeshResult> results;
	_worker->drain_results(results, 8);
	for (auto &r : results) {
		_integrate_one(r);
	}
}


void TerrainWorld::_integrate_one(const RemeshResult &r) {
	Chunk *chunk = _manager->get(r.coords);
	if (chunk == nullptr) {
		return;
	}
	if (chunk->generation.load() != r.submitted_generation) {
		// Stale; a newer remesh is queued.
		return;
	}

	RenderingServer *rs = RenderingServer::get_singleton();
	PhysicsServer2D *ps = PhysicsServer2D::get_singleton();

	// Rendering: rebuild the canvas_item's draw commands.
	if (!chunk->canvas_item_rid.is_valid()) {
		chunk->canvas_item_rid = rs->canvas_item_create();
		rs->canvas_item_set_parent(
				chunk->canvas_item_rid,
				_parent_canvas_item.is_valid()
						? _parent_canvas_item
						: get_canvas_item());
		// Visibility layer 1 | 2 = 3 so both the scene camera
		// (cull_mask 1) and the frequency-tag camera (cull_mask 2)
		// see the terrain. The scene view uses it as the visible
		// surface; the tag view uses its palette-coloured pixels as
		// a per-pixel type buffer for the echolocation shader.
		rs->canvas_item_set_visibility_layer(
				chunk->canvas_item_rid, 3);
	}
	rs->canvas_item_clear(chunk->canvas_item_rid);

	const MeshResult &mesh = r.mesh;
	if (!mesh.indices.empty()) {
		PackedVector2Array points;
		PackedColorArray colors;
		PackedInt32Array indices;
		points.resize(mesh.verts.size());
		colors.resize(mesh.colors_rgba.size());
		indices.resize(mesh.indices.size());
		for (size_t i = 0; i < mesh.verts.size(); i++) {
			points[i] = mesh.verts[i];
		}
		for (size_t i = 0; i < mesh.colors_rgba.size(); i++) {
			const uint32_t c = mesh.colors_rgba[i];
			colors[i] = Color(
					static_cast<uint8_t>((c >> 24) & 0xFF) / 255.0f,
					static_cast<uint8_t>((c >> 16) & 0xFF) / 255.0f,
					static_cast<uint8_t>((c >> 8) & 0xFF) / 255.0f,
					static_cast<uint8_t>(c & 0xFF) / 255.0f);
		}
		for (size_t i = 0; i < mesh.indices.size(); i++) {
			indices[i] = mesh.indices[i];
		}
		rs->canvas_item_add_triangle_array(
				chunk->canvas_item_rid,
				indices, points, colors);
	}

	// Collision: skip in editor mode — physics bodies in editor
	// can interfere with editor-mode dragging tools and aren't
	// useful for the @tool preview anyway.
	if (!_editor_mode) {
		if (!chunk->static_body_rid.is_valid()) {
			chunk->static_body_rid = ps->body_create();
			ps->body_set_mode(chunk->static_body_rid,
					PhysicsServer2D::BODY_MODE_STATIC);
			ps->body_set_collision_layer(chunk->static_body_rid,
					_settings.is_valid()
							? _settings->collision_layer
							: 1);
			ps->body_set_collision_mask(chunk->static_body_rid,
					_settings.is_valid()
							? _settings->collision_mask
							: 0);
			Viewport *vp = get_viewport();
			if (vp != nullptr) {
				Ref<World2D> world_2d = vp->get_world_2d();
				if (world_2d.is_valid()) {
					ps->body_set_space(
							chunk->static_body_rid,
							world_2d->get_space());
				}
			}
		}
		if (!r.collision_density.empty()) {
			rebuild_collision_cells(
					ps, chunk, r.collision_density, r.cells,
					r.cell_size_px, r.origin_px, r.iso);
		}
	}

	_dirty_chunks.erase(chunk->coords);
	emit_signal("chunk_modified", chunk->coords);
}

void TerrainWorld::_free_chunk_rids(Chunk *chunk) {
	RenderingServer *rs = RenderingServer::get_singleton();
	PhysicsServer2D *ps = PhysicsServer2D::get_singleton();
	if (chunk->canvas_item_rid.is_valid()) {
		rs->free_rid(chunk->canvas_item_rid);
		chunk->canvas_item_rid = RID();
	}
	if (chunk->static_body_rid.is_valid()) {
		ps->free_rid(chunk->static_body_rid);
		chunk->static_body_rid = RID();
	}
	for (const RID &rid : chunk->shape_rids) {
		if (rid.is_valid()) {
			ps->free_rid(rid);
		}
	}
	chunk->shape_rids.clear();
}

void TerrainWorld::_on_process() {
	_integrate_results();
	_flow_tick_counter++;
	if (_flow_tick_counter >= FLOW_STEP_INTERVAL) {
		_flow_tick_counter = 0;
		_step_flow();
	}
}

// ---- Gameplay API -----------------------------------------------------------

void TerrainWorld::carve(Vector2 world_pos, float radius_px, float strength) {
	_ensure_initialized();
	const float feather = 2.0f;
	const float reach = radius_px + feather;
	auto coords = _manager->chunks_affected_by_splat(
			world_pos, reach, _cells_cached, _cell_size_px_cached);
	for (const Vector2i &c : coords) {
		Chunk *chunk = _manager->get_or_create(c, _cells_cached);
		const Vector2 origin = chunk->origin_px(_cell_size_px_cached);
		const bool changed = terrain::carve_circle(
				chunk->density.data(), chunk->samples_side(),
				origin, _cell_size_px_cached,
				world_pos, radius_px,
				std::clamp(strength, 0.0f, 1.0f), feather);
		if (changed) {
			chunk->generation.fetch_add(1);
			_queue_remesh_and_neighbors(chunk);
		}
	}
}

void TerrainWorld::fill(Vector2 world_pos, float radius_px, float strength) {
	_ensure_initialized();
	const float feather = 2.0f;
	const float reach = radius_px + feather;
	auto coords = _manager->chunks_affected_by_splat(
			world_pos, reach, _cells_cached, _cell_size_px_cached);
	for (const Vector2i &c : coords) {
		Chunk *chunk = _manager->get_or_create(c, _cells_cached);
		const Vector2 origin = chunk->origin_px(_cell_size_px_cached);
		const bool changed = terrain::fill_circle(
				chunk->density.data(), chunk->samples_side(),
				origin, _cell_size_px_cached,
				world_pos, radius_px,
				std::clamp(strength, 0.0f, 1.0f), feather);
		if (changed) {
			chunk->generation.fetch_add(1);
			_queue_remesh_and_neighbors(chunk);
		}
	}
}

bool TerrainWorld::_apply_damage_to_cell(Chunk *chunk, int cx, int cy,
		int surface_dmg, int proximity_dmg,
		int frequency_mask, Vector2 emitter_world_pos,
		Vector2 cell_world_pos,
		std::unordered_set<int64_t> *destroyed_this_pulse,
		int32_t *out_world_cx, int32_t *out_world_cy) {
	if (cx < 0 || cy < 0 || cx >= chunk->cells || cy >= chunk->cells) {
		return false;
	}
	const int idx = chunk->cell_index(cx, cy);
	const uint8_t type = chunk->type_per_cell[idx];
	if (type == TerrainSettings::TYPE_NONE) {
		return false;
	}
	if (type == TerrainSettings::TYPE_INDESTRUCTIBLE) {
		return false;
	}
	if (frequency_mask != 0) {
		const int type_bit = _frequency_to_bit(type);
		if ((frequency_mask & type_bit) == 0) {
			return false;
		}
	}

	// Surface-only + player-facing damage gating. Mirrors the visual
	// stipple / ping-line rules: pulses erode what they can "see".
	//
	// `destroyed_this_pulse` tracks cells already destroyed earlier in
	// this same damage pass so we don't cascade through a column of
	// solid cells in one pulse: a cell freshly destroyed by a prior
	// iteration is treated as STILL SOLID for surface-check purposes,
	// so its previously-interior neighbor stays interior and doesn't
	// get chained into destruction.
	const int cells = chunk->cells;
	const int32_t wcx = chunk->coords.x * cells + cx;
	const int32_t wcy = chunk->coords.y * cells + cy;
	auto pack_coord = [](int32_t x, int32_t y) -> int64_t {
		return (static_cast<int64_t>(x) << 32)
				| (static_cast<int64_t>(y) & 0xFFFFFFFFLL);
	};
	auto neighbor_is_open = [&](int32_t nx, int32_t ny) -> bool {
		if (destroyed_this_pulse != nullptr
				&& destroyed_this_pulse->count(pack_coord(nx, ny))
						> 0) {
			return false;
		}
		const uint8_t t = world_cell_type(*_manager, cells, nx, ny);
		return t == TerrainSettings::TYPE_NONE
				|| t == TerrainSettings::TYPE_LIQUID;
	};
	const bool open_n = neighbor_is_open(wcx, wcy - 1);
	const bool open_s = neighbor_is_open(wcx, wcy + 1);
	const bool open_w = neighbor_is_open(wcx - 1, wcy);
	const bool open_e = neighbor_is_open(wcx + 1, wcy);
	const bool is_surface = open_n || open_s || open_w || open_e;

	// Surface component — only exposed cells take this, scaled by how
	// squarely their outward normal faces the emitter. Back-facing
	// surfaces get 30%, fully front-facing 100%.
	int scaled_surface_dmg = 0;
	if (is_surface && surface_dmg > 0) {
		Vector2 outward(0.0f, 0.0f);
		if (open_n) { outward.y -= 1.0f; }
		if (open_s) { outward.y += 1.0f; }
		if (open_w) { outward.x -= 1.0f; }
		if (open_e) { outward.x += 1.0f; }
		if (outward.length_squared() > 1e-6f) {
			outward = outward.normalized();
		}
		const Vector2 to_emitter_vec =
				emitter_world_pos - cell_world_pos;
		const float to_emitter_len = to_emitter_vec.length();
		float facing = 0.0f;
		if (to_emitter_len > 1e-3f) {
			const float dot_v = outward.dot(
					to_emitter_vec / to_emitter_len);
			facing = dot_v > 0.0f ? dot_v : 0.0f;
		}
		const float facing_mult = 0.3f + 0.7f * facing;
		scaled_surface_dmg = static_cast<int>(
				std::round(static_cast<float>(surface_dmg)
						* facing_mult));
	}

	// Proximity component — short-range direct damage that bypasses
	// the surface check. Small and sharp-falloff, so chunky interiors
	// still chip a bit near the player without long-range spray.
	const int total_dmg = scaled_surface_dmg + proximity_dmg;
	if (total_dmg <= 0) {
		return false;
	}

	int hp = chunk->health_per_cell[idx] - total_dmg;
	if (hp <= 0) {
		chunk->health_per_cell[idx] = 0;
		chunk->type_per_cell[idx] = TerrainSettings::TYPE_NONE;
		refresh_corners_after_clear(chunk, cx, cy);
		emit_signal("tile_destroyed", cell_world_pos, type);
		if (destroyed_this_pulse != nullptr) {
			destroyed_this_pulse->insert(pack_coord(wcx, wcy));
		}
		if (out_world_cx) {
			*out_world_cx = chunk->coords.x * chunk->cells + cx;
		}
		if (out_world_cy) {
			*out_world_cy = chunk->coords.y * chunk->cells + cy;
		}
		return true;
	} else {
		chunk->health_per_cell[idx] = static_cast<uint8_t>(hp);
	}
	return false;
}

void TerrainWorld::damage(Vector2 world_pos, float radius_px, int dmg,
		int frequency_mask) {
	_ensure_initialized();
	const float reach = radius_px;
	auto coords = _manager->chunks_affected_by_splat(
			world_pos, reach, _cells_cached, _cell_size_px_cached);

	// Collect world-cell coords of destroyed cells. Fed to CC pass
	// after the full damage query runs so islands are detected once
	// per damage call rather than per-cell. The `destroyed_this_pulse`
	// set is the same coords packed as int64_t, consulted by
	// `_apply_damage_to_cell` during its neighbor-open check so a
	// cell destroyed earlier in this pass doesn't cascade its
	// newly-exposed neighbors into also-destroyed in the same pass.
	std::vector<int32_t> destroyed_flat;
	std::unordered_set<int64_t> destroyed_this_pulse;

	for (const Vector2i &c : coords) {
		Chunk *chunk = _manager->get(c);
		if (chunk == nullptr) {
			continue;
		}
		const Vector2 origin = chunk->origin_px(_cell_size_px_cached);
		int min_x, min_y, max_x, max_y;
		terrain::cells_affected_by_circle(
				chunk->cells, origin, _cell_size_px_cached,
				world_pos, radius_px, 0.0f,
				min_x, min_y, max_x, max_y);
		if (max_x >= chunk->cells) {
			max_x = chunk->cells - 1;
		}
		if (max_y >= chunk->cells) {
			max_y = chunk->cells - 1;
		}
		if (min_x > max_x || min_y > max_y) {
			continue;
		}

		bool any_change = false;
		const float r_sq = radius_px * radius_px;
		for (int cy = min_y; cy <= max_y; cy++) {
			for (int cx = min_x; cx <= max_x; cx++) {
				const Vector2 cell_center = Vector2(
						origin.x + (cx + 0.5f) * _cell_size_px_cached,
						origin.y + (cy + 0.5f) * _cell_size_px_cached);
				const float dx = cell_center.x - world_pos.x;
				const float dy = cell_center.y - world_pos.y;
				if (dx * dx + dy * dy > r_sq) {
					continue;
				}
				int32_t w_cx = 0, w_cy = 0;
				const bool destroyed = _apply_damage_to_cell(
						chunk, cx, cy, dmg, 0,
						frequency_mask,
						world_pos, cell_center, &destroyed_this_pulse,
						&w_cx, &w_cy);
				if (destroyed) {
					destroyed_flat.push_back(w_cx);
					destroyed_flat.push_back(w_cy);
					any_change = true;
				}
			}
		}

		if (any_change) {
			chunk->generation.fetch_add(1);
			_queue_remesh_and_neighbors(chunk);
		}
	}

	if (!destroyed_flat.empty()) {
		_detach_islands_from_seeds(destroyed_flat);
	}
}

void TerrainWorld::_detach_islands_from_seeds(
		const std::vector<int32_t> &seed_world_cells_flat) {
	std::vector<Vector2i> affected;
	auto islands = ConnectedComponents::detach_islands(
			*_manager,
			_cells_cached,
			_cell_size_px_cached,
			seed_world_cells_flat,
			MAX_DETACH_FLOOD,
			affected);
	// Queue remeshes for chunks whose cells got removed.
	for (const Vector2i &c : affected) {
		Chunk *chunk = _manager->get(c);
		if (chunk == nullptr) {
			continue;
		}
		_queue_remesh_and_neighbors(chunk);
	}
	// For each island: mesh locally, DP-simplify, emit signal.
	for (DetachedIsland &island : islands) {
		const int32_t w = island.width_cells();
		const int32_t h = island.height_cells();
		(void)h;
		MeshResult mesh;
		terrain::mesh_chunk(
				island.local_density.data(),
				w,
				_cell_size_px_cached,
				Vector2(0, 0),
				static_cast<uint8_t>(_iso_cached),
				0u,
				island.local_type.data(),
				_type_to_rgba_lut.data(),
				mesh);
		if (mesh.indices.empty()) {
			continue;
		}
		const float weld_eps_sq =
				(_cell_size_px_cached * 0.01f) *
				(_cell_size_px_cached * 0.01f);
		std::vector<Vector2> collision = terrain::simplify_line_soup(
				mesh.boundary_segments,
				_simplify_eps_cached,
				weld_eps_sq);

		PackedVector2Array verts;
		verts.resize(mesh.verts.size());
		for (size_t i = 0; i < mesh.verts.size(); i++) {
			verts[i] = mesh.verts[i];
		}
		PackedInt32Array indices;
		indices.resize(mesh.indices.size());
		for (size_t i = 0; i < mesh.indices.size(); i++) {
			indices[i] = mesh.indices[i];
		}
		PackedColorArray colors;
		colors.resize(mesh.colors_rgba.size());
		for (size_t i = 0; i < mesh.colors_rgba.size(); i++) {
			const uint32_t c = mesh.colors_rgba[i];
			colors[i] = Color(
					static_cast<uint8_t>((c >> 24) & 0xFF) / 255.0f,
					static_cast<uint8_t>((c >> 16) & 0xFF) / 255.0f,
					static_cast<uint8_t>((c >> 8) & 0xFF) / 255.0f,
					static_cast<uint8_t>(c & 0xFF) / 255.0f);
		}
		PackedVector2Array seg_array;
		seg_array.resize(collision.size());
		for (size_t i = 0; i < collision.size(); i++) {
			seg_array[i] = collision[i];
		}
		PackedByteArray cell_types;
		cell_types.resize(island.local_type.size());
		for (size_t i = 0; i < island.local_type.size(); i++) {
			cell_types[i] = island.local_type[i];
		}
		PackedByteArray cell_healths;
		cell_healths.resize(island.local_health.size());
		for (size_t i = 0; i < island.local_health.size(); i++) {
			cell_healths[i] = island.local_health[i];
		}
		emit_signal("fragment_detached",
				island.origin_px,
				verts,
				indices,
				colors,
				seg_array,
				Vector2i(island.width_cells(), island.height_cells()),
				cell_types,
				cell_healths);
	}
}

void TerrainWorld::paint_cell_at_world(
		Vector2 world_pos, int type, int health) {
	_ensure_initialized();
	if (!_manager) {
		return;
	}
	const Vector2i chunk_coord = ChunkManager::world_to_chunk(
			world_pos, _cells_cached, _cell_size_px_cached);
	Chunk *chunk = _manager->get_or_create(
			chunk_coord, _cells_cached);
	if (chunk == nullptr) {
		return;
	}
	const Vector2 origin = chunk->origin_px(_cell_size_px_cached);
	int cx = static_cast<int>(
			std::floor((world_pos.x - origin.x) / _cell_size_px_cached));
	int cy = static_cast<int>(
			std::floor((world_pos.y - origin.y) / _cell_size_px_cached));
	if (cx < 0 || cy < 0
			|| cx >= _cells_cached || cy >= _cells_cached) {
		return;
	}
	const int idx = chunk->cell_index(cx, cy);
	const uint8_t existing = chunk->type_per_cell[idx];
	// Allow overwriting NONE (empty) and LIQUID (water displaced by
	// a heavier falling solid). Any other occupied cell is
	// preserved — the falling cell's paint no-ops.
	if (existing != TerrainSettings::TYPE_NONE
			&& existing != TerrainSettings::TYPE_LIQUID) {
		return;
	}
	chunk->type_per_cell[idx] = static_cast<uint8_t>(type);
	chunk->health_per_cell[idx] = static_cast<uint8_t>(health);
	refresh_corners_after_clear(chunk, cx, cy);
	chunk->generation.fetch_add(1);
	_queue_remesh_and_neighbors(chunk);
}

void TerrainWorld::_step_flow() {
	if (!_flow_step || _editor_mode) {
		return;
	}
	std::vector<Vector2i> dirty_flow;
	const bool any = _flow_step->step_world(
			*_manager,
			_cells_cached,
			static_cast<uint8_t>(_iso_cached),
			dirty_flow);
	if (!any) {
		return;
	}
	for (const Vector2i &c : dirty_flow) {
		Chunk *chunk = _manager->get(c);
		if (chunk == nullptr) {
			continue;
		}
		_queue_remesh(chunk);
	}
}

Vector2 TerrainWorld::sample_fluid_velocity(Vector2 world_pos) const {
	if (!_flow_step || !_manager) {
		return Vector2();
	}
	return _flow_step->sample_fluid_velocity(
			*_manager, world_pos,
			_cells_cached, _cell_size_px_cached);
}

void TerrainWorld::damage_with_falloff(
		Vector2 world_pos,
		float surface_max_radius_px,
		float surface_full_radius_px,
		int surface_full_dmg,
		int surface_min_dmg,
		float proximity_max_radius_px,
		float proximity_full_radius_px,
		int proximity_full_dmg,
		int proximity_min_dmg,
		int frequency_mask) {
	_ensure_initialized();
	if (surface_max_radius_px <= 0.0f
			&& proximity_max_radius_px <= 0.0f) {
		return;
	}
	if (surface_full_radius_px < 0.0f) { surface_full_radius_px = 0.0f; }
	if (surface_full_radius_px > surface_max_radius_px) {
		surface_full_radius_px = surface_max_radius_px;
	}
	if (proximity_full_radius_px < 0.0f) {
		proximity_full_radius_px = 0.0f;
	}
	if (proximity_full_radius_px > proximity_max_radius_px) {
		proximity_full_radius_px = proximity_max_radius_px;
	}
	const float surface_falloff_band = std::max(
			surface_max_radius_px - surface_full_radius_px, 1e-3f);
	const float proximity_falloff_band = std::max(
			proximity_max_radius_px - proximity_full_radius_px, 1e-3f);
	// Query chunks using the OUTER (surface) radius; proximity is a
	// strict subset so we iterate the union once.
	const float outer_radius_px = std::max(
			surface_max_radius_px, proximity_max_radius_px);
	auto coords = _manager->chunks_affected_by_splat(
			world_pos, outer_radius_px, _cells_cached,
			_cell_size_px_cached);

	// Same pattern as `damage`: collect destroyed cells, then run
	// the connected-components island-detach pass once. The per-
	// pulse set is consulted by the surface-check so cells destroyed
	// earlier in this pass don't re-expose (and chain-damage) their
	// previously-interior neighbors.
	std::vector<int32_t> destroyed_flat;
	std::unordered_set<int64_t> destroyed_this_pulse;

	for (const Vector2i &c : coords) {
		Chunk *chunk = _manager->get(c);
		if (chunk == nullptr) {
			continue;
		}
		const Vector2 origin = chunk->origin_px(_cell_size_px_cached);
		int min_x, min_y, max_x, max_y;
		terrain::cells_affected_by_circle(
				chunk->cells, origin, _cell_size_px_cached,
				world_pos, outer_radius_px, 0.0f,
				min_x, min_y, max_x, max_y);
		if (max_x >= chunk->cells) {
			max_x = chunk->cells - 1;
		}
		if (max_y >= chunk->cells) {
			max_y = chunk->cells - 1;
		}
		if (min_x > max_x || min_y > max_y) {
			continue;
		}

		bool any_change = false;
		const float outer_r_sq = outer_radius_px * outer_radius_px;
		const float surface_r_sq =
				surface_max_radius_px * surface_max_radius_px;
		const float proximity_r_sq =
				proximity_max_radius_px * proximity_max_radius_px;
		for (int cy = min_y; cy <= max_y; cy++) {
			for (int cx = min_x; cx <= max_x; cx++) {
				const Vector2 cell_center = Vector2(
						origin.x + (cx + 0.5f)
								* _cell_size_px_cached,
						origin.y + (cy + 0.5f)
								* _cell_size_px_cached);
				const float dx = cell_center.x - world_pos.x;
				const float dy = cell_center.y - world_pos.y;
				const float d_sq = dx * dx + dy * dy;
				if (d_sq > outer_r_sq) {
					continue;
				}
				const float dist = std::sqrt(d_sq);

				// Surface component — linear falloff.
				int surface_cell_dmg = 0;
				if (d_sq <= surface_r_sq && surface_full_dmg > 0) {
					if (dist <= surface_full_radius_px) {
						surface_cell_dmg = surface_full_dmg;
					} else {
						float t = (dist - surface_full_radius_px)
								/ surface_falloff_band;
						if (t < 0.0f) { t = 0.0f; }
						if (t > 1.0f) { t = 1.0f; }
						surface_cell_dmg = static_cast<int>(
								std::round(
										static_cast<float>(
												surface_full_dmg)
										* (1.0f - t)
										+ static_cast<float>(
												surface_min_dmg)
										* t));
					}
				}

				// Proximity component — cubic ease-out. Sharp drop
				// just past full-radius, softer approach to min. A
				// bit sharper than the old quadratic so only very
				// close cells get big proximity damage.
				int proximity_cell_dmg = 0;
				if (d_sq <= proximity_r_sq
						&& proximity_full_dmg > 0) {
					if (dist <= proximity_full_radius_px) {
						proximity_cell_dmg = proximity_full_dmg;
					} else {
						float t = (dist - proximity_full_radius_px)
								/ proximity_falloff_band;
						if (t < 0.0f) { t = 0.0f; }
						if (t > 1.0f) { t = 1.0f; }
						const float inv = 1.0f - t;
						const float ease_t = 1.0f - inv * inv * inv;
						proximity_cell_dmg = static_cast<int>(
								std::round(
										static_cast<float>(
												proximity_full_dmg)
										* (1.0f - ease_t)
										+ static_cast<float>(
												proximity_min_dmg)
										* ease_t));
					}
				}

				if (surface_cell_dmg <= 0
						&& proximity_cell_dmg <= 0) {
					continue;
				}
				int32_t w_cx = 0, w_cy = 0;
				const bool destroyed = _apply_damage_to_cell(
						chunk, cx, cy,
						surface_cell_dmg, proximity_cell_dmg,
						frequency_mask, world_pos, cell_center,
						&destroyed_this_pulse,
						&w_cx, &w_cy);
				if (destroyed) {
					destroyed_flat.push_back(w_cx);
					destroyed_flat.push_back(w_cy);
					any_change = true;
				}
			}
		}

		if (any_change) {
			chunk->generation.fetch_add(1);
			_queue_remesh_and_neighbors(chunk);
		}
	}

	if (!destroyed_flat.empty()) {
		_detach_islands_from_seeds(destroyed_flat);
	}
}

// ---- Queries ---------------------------------------------------------------

float TerrainWorld::sample_density(Vector2 world_pos) const {
	if (!_manager) {
		return 0.0f;
	}
	const Vector2i coord = ChunkManager::world_to_chunk(
			world_pos, _cells_cached, _cell_size_px_cached);
	auto it = _manager->all().find(coord);
	if (it == _manager->all().end()) {
		return 0.0f;
	}
	Chunk *chunk = it->second.get();
	const Vector2 origin = chunk->origin_px(_cell_size_px_cached);
	const float fx = (world_pos.x - origin.x) / _cell_size_px_cached;
	const float fy = (world_pos.y - origin.y) / _cell_size_px_cached;
	const int x0 = std::clamp(static_cast<int>(std::floor(fx)),
			0, chunk->cells);
	const int y0 = std::clamp(static_cast<int>(std::floor(fy)),
			0, chunk->cells);
	return chunk->density[chunk->density_index(x0, y0)] / 255.0f;
}

bool TerrainWorld::is_solid(Vector2 world_pos) const {
	return sample_density(world_pos) * 255.0f
			>= static_cast<float>(_iso_cached);
}

bool TerrainWorld::is_cell_non_empty(Vector2 world_pos) const {
	if (!_manager) {
		return false;
	}
	const Vector2i coord = ChunkManager::world_to_chunk(
			world_pos, _cells_cached, _cell_size_px_cached);
	auto it = _manager->all().find(coord);
	if (it == _manager->all().end()) {
		return false;
	}
	Chunk *chunk = it->second.get();
	const Vector2 origin = chunk->origin_px(_cell_size_px_cached);
	int cx = static_cast<int>(
			std::floor((world_pos.x - origin.x) / _cell_size_px_cached));
	int cy = static_cast<int>(
			std::floor((world_pos.y - origin.y) / _cell_size_px_cached));
	if (cx < 0 || cy < 0
			|| cx >= _cells_cached || cy >= _cells_cached) {
		return false;
	}
	return chunk->type_per_cell[chunk->cell_index(cx, cy)]
			!= TerrainSettings::TYPE_NONE;
}

bool TerrainWorld::is_cell_collidable(Vector2 world_pos) const {
	if (!_manager) {
		return false;
	}
	const Vector2i coord = ChunkManager::world_to_chunk(
			world_pos, _cells_cached, _cell_size_px_cached);
	auto it = _manager->all().find(coord);
	if (it == _manager->all().end()) {
		return false;
	}
	Chunk *chunk = it->second.get();
	const Vector2 origin = chunk->origin_px(_cell_size_px_cached);
	int cx = static_cast<int>(
			std::floor((world_pos.x - origin.x) / _cell_size_px_cached));
	int cy = static_cast<int>(
			std::floor((world_pos.y - origin.y) / _cell_size_px_cached));
	if (cx < 0 || cy < 0
			|| cx >= _cells_cached || cy >= _cells_cached) {
		return false;
	}
	const uint8_t t = chunk->type_per_cell[chunk->cell_index(cx, cy)];
	return t != TerrainSettings::TYPE_NONE
			&& t != TerrainSettings::TYPE_LIQUID;
}

bool TerrainWorld::is_cell_type_at(Vector2 world_pos, int type) const {
	if (!_manager) {
		return false;
	}
	const Vector2i coord = ChunkManager::world_to_chunk(
			world_pos, _cells_cached, _cell_size_px_cached);
	auto it = _manager->all().find(coord);
	if (it == _manager->all().end()) {
		return false;
	}
	Chunk *chunk = it->second.get();
	const Vector2 origin = chunk->origin_px(_cell_size_px_cached);
	int cx = static_cast<int>(
			std::floor((world_pos.x - origin.x) / _cell_size_px_cached));
	int cy = static_cast<int>(
			std::floor((world_pos.y - origin.y) / _cell_size_px_cached));
	if (cx < 0 || cy < 0
			|| cx >= _cells_cached || cy >= _cells_cached) {
		return false;
	}
	return chunk->type_per_cell[chunk->cell_index(cx, cy)]
			== static_cast<uint8_t>(type);
}

float TerrainWorld::get_surface_height(float world_x,
		float search_max_y_px) const {
	// Walk downward in cell_size_px steps until we hit a solid sample.
	if (!_manager) {
		return NAN;
	}
	const float step = _cell_size_px_cached;
	for (float y = -search_max_y_px; y <= search_max_y_px; y += step) {
		if (is_solid(Vector2(world_x, y))) {
			return y;
		}
	}
	return NAN;
}

void TerrainWorld::clear_all() {
	if (!_manager) {
		return;
	}
	for (auto &pair : _manager->all_mut()) {
		_free_chunk_rids(pair.second.get());
	}
	_manager->all_mut().clear();
	_dirty_chunks.clear();
	if (_flow_step) {
		_flow_step->reset_velocity_cache();
	}
}


Dictionary TerrainWorld::get_stats() const {
	Dictionary d;
	d["loaded_chunks"] = static_cast<int>(
			_manager ? _manager->size() : 0);
	d["dirty_chunks"] = static_cast<int>(_dirty_chunks.size());
	d["pending_jobs"] = static_cast<int>(
			_worker ? _worker->pending_jobs() : 0);
	d["pending_results"] = static_cast<int>(
			_worker ? _worker->pending_results() : 0);
	return d;
}


// Helper: compute chunk-coord bounding box. Returns false when no
// chunks exist (image builders skip bind in that case).
static bool _chunk_coord_bounds(
		const terrain::ChunkManager &manager,
		Vector2i &out_min,
		Vector2i &out_max) {
	if (manager.size() == 0) {
		return false;
	}
	bool first = true;
	for (const auto &kv : manager.all()) {
		const Vector2i c = kv.first;
		if (first) {
			out_min = c;
			out_max = c;
			first = false;
		} else {
			out_min.x = std::min(out_min.x, c.x);
			out_min.y = std::min(out_min.y, c.y);
			out_max.x = std::max(out_max.x, c.x);
			out_max.y = std::max(out_max.y, c.y);
		}
	}
	return true;
}


Vector2i TerrainWorld::get_world_cell_origin() const {
	if (!_manager) {
		return Vector2i();
	}
	Vector2i mn, mx;
	if (!_chunk_coord_bounds(*_manager, mn, mx)) {
		return Vector2i();
	}
	return Vector2i(mn.x * _cells_cached, mn.y * _cells_cached);
}


Vector2i TerrainWorld::get_world_cell_size() const {
	if (!_manager) {
		return Vector2i();
	}
	Vector2i mn, mx;
	if (!_chunk_coord_bounds(*_manager, mn, mx)) {
		return Vector2i();
	}
	return Vector2i(
			(mx.x - mn.x + 1) * _cells_cached,
			(mx.y - mn.y + 1) * _cells_cached);
}


Ref<Image> TerrainWorld::build_density_image() const {
	if (!_manager) {
		return Ref<Image>();
	}
	Vector2i mn, mx;
	if (!_chunk_coord_bounds(*_manager, mn, mx)) {
		return Ref<Image>();
	}
	const int cells = _cells_cached;
	const int width = (mx.x - mn.x + 1) * cells + 1;
	const int height = (mx.y - mn.y + 1) * cells + 1;
	PackedByteArray data;
	data.resize(width * height);
	// Zero-fill so any gap between chunks (sparse worlds) reads as
	// empty density.
	uint8_t *raw = data.ptrw();
	std::fill(raw, raw + width * height, static_cast<uint8_t>(0));
	const int chunk_samples = cells + 1;
	for (const auto &kv : _manager->all()) {
		const terrain::Chunk *chunk = kv.second.get();
		const int base_x = (chunk->coords.x - mn.x) * cells;
		const int base_y = (chunk->coords.y - mn.y) * cells;
		for (int y = 0; y < chunk_samples; y++) {
			const int dst_y = base_y + y;
			const int dst_row = dst_y * width + base_x;
			const int src_row = y * chunk_samples;
			std::memcpy(
					raw + dst_row,
					chunk->density.data() + src_row,
					chunk_samples);
		}
	}
	return Image::create_from_data(
			width, height, false, Image::FORMAT_R8, data);
}


Ref<Image> TerrainWorld::build_type_image() const {
	if (!_manager) {
		return Ref<Image>();
	}
	Vector2i mn, mx;
	if (!_chunk_coord_bounds(*_manager, mn, mx)) {
		return Ref<Image>();
	}
	const int cells = _cells_cached;
	const int width = (mx.x - mn.x + 1) * cells;
	const int height = (mx.y - mn.y + 1) * cells;
	PackedByteArray data;
	data.resize(width * height);
	uint8_t *raw = data.ptrw();
	std::fill(raw, raw + width * height, static_cast<uint8_t>(0));
	for (const auto &kv : _manager->all()) {
		const terrain::Chunk *chunk = kv.second.get();
		const int base_x = (chunk->coords.x - mn.x) * cells;
		const int base_y = (chunk->coords.y - mn.y) * cells;
		for (int y = 0; y < cells; y++) {
			const int dst_y = base_y + y;
			const int dst_row = dst_y * width + base_x;
			const int src_row = y * cells;
			std::memcpy(
					raw + dst_row,
					chunk->type_per_cell.data() + src_row,
					cells);
		}
	}
	return Image::create_from_data(
			width, height, false, Image::FORMAT_R8, data);
}

} // namespace godot
