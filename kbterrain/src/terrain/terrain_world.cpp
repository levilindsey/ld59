#include "terrain_world.h"

#include "density_splat.h"
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

namespace godot {

using terrain::Chunk;
using terrain::ChunkManager;
using terrain::MeshResult;
using terrain::RemeshJob;
using terrain::RemeshResult;
using terrain::WorkerPool;

TerrainWorld::TerrainWorld() {
	_manager = std::make_unique<ChunkManager>();
	_worker = std::make_unique<WorkerPool>();
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
	ClassDB::bind_method(
			D_METHOD("get_surface_height", "world_x", "search_max_y_px"),
			&TerrainWorld::get_surface_height);
	ClassDB::bind_method(D_METHOD("get_stats"),
			&TerrainWorld::get_stats);
	ClassDB::bind_method(D_METHOD("clear_all"),
			&TerrainWorld::clear_all);

	ADD_SIGNAL(MethodInfo("chunk_modified",
			PropertyInfo(Variant::VECTOR2I, "coords")));
	ADD_SIGNAL(MethodInfo("tile_destroyed",
			PropertyInfo(Variant::VECTOR2, "world_pos"),
			PropertyInfo(Variant::INT, "type")));
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
		UtilityFunctions::print(
				"[kbterrain] _parent_canvas_item created, "
				"visibility_layer=3");
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
	_queue_remesh(chunk);
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
	job.type_snapshot = chunk->type_per_cell;
	job.type_to_color_rgba = _type_to_rgba_lut;
	job.simplify_epsilon_px = _simplify_eps_cached;

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
		UtilityFunctions::print(
				"[kbterrain] chunk canvas_item created, "
				"visibility_layer=3");
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
		if (!chunk->shape_rid.is_valid()) {
			chunk->shape_rid = ps->concave_polygon_shape_create();
			ps->body_add_shape(chunk->static_body_rid, chunk->shape_rid);
		}

		PackedVector2Array seg_array;
		seg_array.resize(r.collision_segments.size());
		for (size_t i = 0; i < r.collision_segments.size(); i++) {
			seg_array[i] = r.collision_segments[i];
		}
		ps->shape_set_data(chunk->shape_rid, seg_array);
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
	if (chunk->shape_rid.is_valid()) {
		ps->free_rid(chunk->shape_rid);
		chunk->shape_rid = RID();
	}
}

void TerrainWorld::_on_process() {
	_integrate_results();
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
			_queue_remesh(chunk);
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
			_queue_remesh(chunk);
		}
	}
}

void TerrainWorld::_apply_damage_to_cell(Chunk *chunk, int cx, int cy,
		int dmg, int frequency_mask, Vector2 world_pos) {
	if (cx < 0 || cy < 0 || cx >= chunk->cells || cy >= chunk->cells) {
		return;
	}
	const int idx = chunk->cell_index(cx, cy);
	const uint8_t type = chunk->type_per_cell[idx];
	if (type == TerrainSettings::TYPE_NONE) {
		return;
	}
	if (type == TerrainSettings::TYPE_INDESTRUCTIBLE) {
		return;
	}
	if (frequency_mask != 0) {
		const int type_bit = _frequency_to_bit(type);
		if ((frequency_mask & type_bit) == 0) {
			return;
		}
	}
	int hp = chunk->health_per_cell[idx] - dmg;
	if (hp <= 0) {
		chunk->health_per_cell[idx] = 0;
		chunk->type_per_cell[idx] = TerrainSettings::TYPE_NONE;
		// Clear the density at all 4 surrounding samples.
		const int s = chunk->cells + 1;
		chunk->density[cy * s + cx] = 0;
		chunk->density[cy * s + cx + 1] = 0;
		chunk->density[(cy + 1) * s + cx] = 0;
		chunk->density[(cy + 1) * s + cx + 1] = 0;
		emit_signal("tile_destroyed", world_pos, type);
	} else {
		chunk->health_per_cell[idx] = static_cast<uint8_t>(hp);
	}
}

void TerrainWorld::damage(Vector2 world_pos, float radius_px, int dmg,
		int frequency_mask) {
	_ensure_initialized();
	const float reach = radius_px;
	auto coords = _manager->chunks_affected_by_splat(
			world_pos, reach, _cells_cached, _cell_size_px_cached);
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
		// Cell-index clamp for the type/health grids (cells, not +1).
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
				const int idx_before = chunk->cell_index(cx, cy);
				const uint8_t type_before = chunk->type_per_cell[idx_before];
				_apply_damage_to_cell(chunk, cx, cy, dmg,
						frequency_mask, cell_center);
				if (chunk->type_per_cell[idx_before] != type_before) {
					any_change = true;
				}
			}
		}

		if (any_change) {
			chunk->generation.fetch_add(1);
			_queue_remesh(chunk);
		}
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

} // namespace godot
