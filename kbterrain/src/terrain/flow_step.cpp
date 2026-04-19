#include "flow_step.h"

#include <algorithm>
#include <cmath>

namespace godot {
namespace terrain {

namespace {

// Decay factor per step for per-cell velocity accumulator. ≈ 0.85
// keeps velocity visible across ~6 frames of stillness, then fades.
constexpr int VELOCITY_DECAY_NUM = 6;
constexpr int VELOCITY_DECAY_DEN = 7;

// A move deposits this much signed impulse into the source + target
// velocity fields (opposite signs to simulate momentum exchange).
constexpr int MOVE_VELOCITY_IMPULSE = 40;

inline bool is_flowable_type(uint8_t t) {
	return t == TerrainSettings::TYPE_SAND
			|| t == TerrainSettings::TYPE_LIQUID;
}

} // namespace

FlowStep::FlowStep() {}

FlowStep::ChunkFlow &FlowStep::_get_or_create_flow(
		Vector2i coords, int chunk_cells) {
	auto it = _flow_by_chunk.find(coords);
	if (it == _flow_by_chunk.end()) {
		ChunkFlow cf;
		cf.vel_x.assign(chunk_cells * chunk_cells, 0);
		cf.vel_y.assign(chunk_cells * chunk_cells, 0);
		cf.moved_this_frame.assign(chunk_cells * chunk_cells, 0);
		auto ins = _flow_by_chunk.emplace(coords, std::move(cf));
		return ins.first->second;
	}
	return it->second;
}

void FlowStep::reset_velocity_cache() {
	_flow_by_chunk.clear();
}

bool FlowStep::step_world(
		ChunkManager &manager,
		int chunk_cells,
		uint8_t iso,
		std::vector<Vector2i> &out_dirty_chunks) {
	_step_counter++;
	const bool prefer_right = (_step_counter & 1u) == 0;

	// Decay all velocity accumulators; clear moved flags for the
	// new step.
	for (auto &pair : _flow_by_chunk) {
		ChunkFlow &cf = pair.second;
		for (size_t i = 0; i < cf.vel_x.size(); i++) {
			cf.vel_x[i] = static_cast<int8_t>(
					(static_cast<int>(cf.vel_x[i]) * VELOCITY_DECAY_NUM)
					/ VELOCITY_DECAY_DEN);
			cf.vel_y[i] = static_cast<int8_t>(
					(static_cast<int>(cf.vel_y[i]) * VELOCITY_DECAY_NUM)
					/ VELOCITY_DECAY_DEN);
		}
		std::fill(cf.moved_this_frame.begin(),
				cf.moved_this_frame.end(), 0u);
	}

	bool any_moved = false;

	// Snapshot the chunk list; we iterate by coord so modifications
	// to the map during the step (via _get_or_create_flow on target
	// chunks) don't invalidate iterators.
	std::vector<Vector2i> chunk_coords;
	chunk_coords.reserve(manager.size());
	for (const auto &pair : manager.all()) {
		chunk_coords.push_back(pair.first);
	}

	for (const Vector2i &coord : chunk_coords) {
		Chunk *chunk = manager.get(coord);
		if (chunk == nullptr) {
			continue;
		}
		ChunkFlow &flow = _get_or_create_flow(coord, chunk_cells);

		// Bottom-up scan so a falling cell is only processed once
		// per step.
		for (int cy = chunk_cells - 1; cy >= 0; cy--) {
			const int x_start = prefer_right ? 0 : chunk_cells - 1;
			const int x_end = prefer_right ? chunk_cells : -1;
			const int x_step = prefer_right ? 1 : -1;
			for (int cx = x_start; cx != x_end; cx += x_step) {
				const int idx = chunk->cell_index(cx, cy);
				if (flow.moved_this_frame[idx]) {
					continue;
				}
				const uint8_t t = chunk->type_per_cell[idx];
				bool moved = false;
				if (t == TerrainSettings::TYPE_SAND) {
					moved = _try_sand(*chunk, flow, cx, cy,
							manager, chunk_cells, iso, prefer_right,
							out_dirty_chunks);
				} else if (t == TerrainSettings::TYPE_LIQUID) {
					moved = _try_liquid(*chunk, flow, cx, cy,
							manager, chunk_cells, iso, prefer_right,
							out_dirty_chunks);
				}
				if (moved) {
					any_moved = true;
				}
			}
		}
	}

	if (any_moved) {
		// Deduplicate.
		std::sort(out_dirty_chunks.begin(), out_dirty_chunks.end(),
				[](const Vector2i &a, const Vector2i &b) {
					return a.x == b.x ? a.y < b.y : a.x < b.x;
				});
		out_dirty_chunks.erase(
				std::unique(out_dirty_chunks.begin(),
						out_dirty_chunks.end()),
				out_dirty_chunks.end());
	}
	return any_moved;
}

bool FlowStep::_is_empty(
		Chunk &src_chunk,
		int cx,
		int cy,
		ChunkManager &manager,
		int chunk_cells,
		uint8_t iso,
		Chunk **out_chunk,
		ChunkFlow **out_flow,
		int *out_cx,
		int *out_cy) {
	Chunk *target = &src_chunk;
	int tx = cx, ty = cy;
	Vector2i target_coords = src_chunk.coords;

	if (tx < 0) {
		target_coords.x -= 1;
		tx += chunk_cells;
	} else if (tx >= chunk_cells) {
		target_coords.x += 1;
		tx -= chunk_cells;
	}
	if (ty < 0) {
		target_coords.y -= 1;
		ty += chunk_cells;
	} else if (ty >= chunk_cells) {
		target_coords.y += 1;
		ty -= chunk_cells;
	}

	if (target_coords != src_chunk.coords) {
		target = manager.get(target_coords);
		if (target == nullptr) {
			// Treat missing chunks as solid so cells don't vanish.
			return false;
		}
	}

	const int idx = target->cell_index(tx, ty);
	if (target->type_per_cell[idx] != TerrainSettings::TYPE_NONE) {
		return false;
	}
	// Also treat high-density empty-type cells as solid (carve
	// created a slab of density but no type — rare but defensive).
	const int s = chunk_cells + 1;
	const uint8_t d0 = target->density[ty * s + tx];
	const uint8_t d1 = target->density[ty * s + tx + 1];
	const uint8_t d2 = target->density[(ty + 1) * s + tx];
	const uint8_t d3 = target->density[(ty + 1) * s + tx + 1];
	const uint8_t max_d = std::max({ d0, d1, d2, d3 });
	if (max_d >= iso) {
		return false;
	}

	if (out_chunk) *out_chunk = target;
	if (out_flow) *out_flow = &_get_or_create_flow(target_coords, chunk_cells);
	if (out_cx) *out_cx = tx;
	if (out_cy) *out_cy = ty;
	return true;
}

bool FlowStep::_try_sand(
		Chunk &chunk,
		ChunkFlow &flow,
		int cx,
		int cy,
		ChunkManager &manager,
		int chunk_cells,
		uint8_t iso,
		bool prefer_right,
		std::vector<Vector2i> &dirty) {
	// Down.
	Chunk *dst = nullptr;
	ChunkFlow *dst_flow = nullptr;
	int dx = 0, dy = 0;
	if (_is_empty(chunk, cx, cy + 1, manager, chunk_cells, iso,
				&dst, &dst_flow, &dx, &dy)) {
		return _move_cell(chunk, flow, cx, cy,
				*dst, *dst_flow, dx, dy, chunk_cells, dirty);
	}
	// Diagonal down. Prefer side varies by frame.
	const int first_side = prefer_right ? 1 : -1;
	for (int s_try = 0; s_try < 2; s_try++) {
		const int side = (s_try == 0) ? first_side : -first_side;
		if (_is_empty(chunk, cx + side, cy + 1, manager, chunk_cells,
					iso, &dst, &dst_flow, &dx, &dy)) {
			return _move_cell(chunk, flow, cx, cy,
					*dst, *dst_flow, dx, dy, chunk_cells, dirty);
		}
	}
	return false;
}

bool FlowStep::_try_liquid(
		Chunk &chunk,
		ChunkFlow &flow,
		int cx,
		int cy,
		ChunkManager &manager,
		int chunk_cells,
		uint8_t iso,
		bool prefer_right,
		std::vector<Vector2i> &dirty) {
	if (_try_sand(chunk, flow, cx, cy, manager, chunk_cells,
				iso, prefer_right, dirty)) {
		return true;
	}
	// Sideways spread when down blocked.
	Chunk *dst = nullptr;
	ChunkFlow *dst_flow = nullptr;
	int dx = 0, dy = 0;
	const int first_side = prefer_right ? 1 : -1;
	for (int s_try = 0; s_try < 2; s_try++) {
		const int side = (s_try == 0) ? first_side : -first_side;
		if (_is_empty(chunk, cx + side, cy, manager, chunk_cells,
					iso, &dst, &dst_flow, &dx, &dy)) {
			return _move_cell(chunk, flow, cx, cy,
					*dst, *dst_flow, dx, dy, chunk_cells, dirty);
		}
	}
	return false;
}

bool FlowStep::_move_cell(
		Chunk &src_chunk,
		ChunkFlow &src_flow,
		int src_cx,
		int src_cy,
		Chunk &dst_chunk,
		ChunkFlow &dst_flow,
		int dst_cx,
		int dst_cy,
		int chunk_cells,
		std::vector<Vector2i> &dirty) {
	const int src_idx = src_chunk.cell_index(src_cx, src_cy);
	const int dst_idx = dst_chunk.cell_index(dst_cx, dst_cy);
	const uint8_t type = src_chunk.type_per_cell[src_idx];
	const uint8_t health = src_chunk.health_per_cell[src_idx];

	dst_chunk.type_per_cell[dst_idx] = type;
	dst_chunk.health_per_cell[dst_idx] = health;
	src_chunk.type_per_cell[src_idx] = TerrainSettings::TYPE_NONE;
	src_chunk.health_per_cell[src_idx] = 255;

	dst_flow.moved_this_frame[dst_idx] = 1;
	// Don't set source moved flag — source cell is now empty; a
	// future cell moving into it is fine.

	// Direction of motion in world space (cells are +y = down).
	const int wx_src = src_chunk.coords.x * chunk_cells + src_cx;
	const int wy_src = src_chunk.coords.y * chunk_cells + src_cy;
	const int wx_dst = dst_chunk.coords.x * chunk_cells + dst_cx;
	const int wy_dst = dst_chunk.coords.y * chunk_cells + dst_cy;
	const int delta_vx = (wx_dst - wx_src) * MOVE_VELOCITY_IMPULSE;
	const int delta_vy = (wy_dst - wy_src) * MOVE_VELOCITY_IMPULSE;
	_velocity_add(dst_flow.vel_x[dst_idx], delta_vx);
	_velocity_add(dst_flow.vel_y[dst_idx], delta_vy);
	// Source retains a decayed trail, not a fresh write — helps the
	// sample near moving fronts be smooth.
	_velocity_add(src_flow.vel_x[src_idx], delta_vx / 2);
	_velocity_add(src_flow.vel_y[src_idx], delta_vy / 2);

	// Rebuild density corners around both cells.
	_refresh_corner_density(src_chunk, src_cx, src_cy, chunk_cells);
	_refresh_corner_density(dst_chunk, dst_cx, dst_cy, chunk_cells);

	// Bump generation on any chunk whose data we touched.
	src_chunk.generation.fetch_add(1);
	if (&src_chunk != &dst_chunk) {
		dst_chunk.generation.fetch_add(1);
		dirty.push_back(src_chunk.coords);
		dirty.push_back(dst_chunk.coords);
	} else {
		dirty.push_back(src_chunk.coords);
	}

	return true;
}

void FlowStep::_refresh_corner_density(
		Chunk &chunk,
		int cx,
		int cy,
		int chunk_cells) {
	// For each of the 4 corners of cell (cx, cy), check all 4
	// adjacent cells' type. If any is non-NONE, the corner is
	// 255; otherwise 0.
	const int s = chunk_cells + 1;
	for (int dyc = 0; dyc <= 1; dyc++) {
		for (int dxc = 0; dxc <= 1; dxc++) {
			const int corner_x = cx + dxc;
			const int corner_y = cy + dyc;
			// Look at the 4 cells sharing this corner.
			uint8_t any_filled = 0;
			for (int a = -1; a <= 0; a++) {
				for (int b = -1; b <= 0; b++) {
					const int ncx = corner_x + b;
					const int ncy = corner_y + a;
					if (ncx < 0 || ncy < 0
							|| ncx >= chunk_cells
							|| ncy >= chunk_cells) {
						continue;
					}
					if (chunk.type_per_cell[
							ncy * chunk_cells + ncx]
							!= TerrainSettings::TYPE_NONE) {
						any_filled = 1;
						break;
					}
				}
				if (any_filled) break;
			}
			chunk.density[corner_y * s + corner_x] =
					any_filled ? 255 : 0;
		}
	}
}

Vector2 FlowStep::sample_fluid_velocity(
		const ChunkManager &manager,
		Vector2 world_pos,
		int chunk_cells,
		float cell_size_px) const {
	// Bilinear sample of the cell-centered velocity field at the
	// world position. Only liquid cells contribute; non-liquid cells
	// read as zero.
	const Vector2i chunk_coord = ChunkManager::world_to_chunk(
			world_pos, chunk_cells, cell_size_px);
	auto chunk_it = manager.all().find(chunk_coord);
	if (chunk_it == manager.all().end()) {
		return Vector2();
	}
	const Chunk *chunk = chunk_it->second.get();
	auto flow_it = _flow_by_chunk.find(chunk_coord);
	if (flow_it == _flow_by_chunk.end()) {
		return Vector2();
	}
	const ChunkFlow &flow = flow_it->second;
	const Vector2 origin = chunk->origin_px(cell_size_px);
	const float fx = (world_pos.x - origin.x) / cell_size_px;
	const float fy = (world_pos.y - origin.y) / cell_size_px;
	const int cx = std::clamp(static_cast<int>(std::floor(fx)),
			0, chunk_cells - 1);
	const int cy = std::clamp(static_cast<int>(std::floor(fy)),
			0, chunk_cells - 1);
	const int idx = cy * chunk_cells + cx;
	// Velocity stored as int8 ∈ [-128, 127] representing world-cells
	// per step × MOVE_VELOCITY_IMPULSE, decayed over ~6 steps. Scale
	// back to cells/second by dividing by (impulse * approx_steps).
	// With ~60 flow steps per second the scaling factor is rough but
	// gives a reasonable "fast-moving fluid" signal for gameplay.
	const float scale = cell_size_px
			/ static_cast<float>(MOVE_VELOCITY_IMPULSE);
	if (chunk->type_per_cell[idx] != TerrainSettings::TYPE_LIQUID) {
		return Vector2();
	}
	return Vector2(
			static_cast<float>(flow.vel_x[idx]) * scale,
			static_cast<float>(flow.vel_y[idx]) * scale);
}

} // namespace terrain
} // namespace godot
