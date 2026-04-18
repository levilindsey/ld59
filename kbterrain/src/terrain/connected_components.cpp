#include "connected_components.h"

#include "terrain_settings.h"

#include <algorithm>
#include <cstdint>
#include <deque>
#include <unordered_set>

namespace godot {
namespace terrain {

namespace {

// Pack (x, y) int32 into a 64-bit key for hash sets.
inline uint64_t key(int32_t x, int32_t y) {
	return (static_cast<uint64_t>(static_cast<uint32_t>(x)) << 32)
			| static_cast<uint64_t>(static_cast<uint32_t>(y));
}

// Fetch a cell's type via ChunkManager. Returns 0 (TYPE_NONE) if the
// chunk doesn't exist. Sets `*out_chunk` and `*out_cx`, `*out_cy`
// (local coords) for callers that need to mutate the cell.
uint8_t cell_type_world(
		ChunkManager &manager,
		int chunk_cells,
		int32_t world_cx,
		int32_t world_cy,
		Chunk **out_chunk,
		int *out_cx,
		int *out_cy) {
	int32_t chunk_x = world_cx / chunk_cells;
	int32_t chunk_y = world_cy / chunk_cells;
	int32_t local_x = world_cx - chunk_x * chunk_cells;
	int32_t local_y = world_cy - chunk_y * chunk_cells;
	// Handle negatives where modulo/divide rounds toward zero in C++.
	if (local_x < 0) {
		local_x += chunk_cells;
		chunk_x -= 1;
	}
	if (local_y < 0) {
		local_y += chunk_cells;
		chunk_y -= 1;
	}
	Chunk *chunk = manager.get(Vector2i(chunk_x, chunk_y));
	if (chunk == nullptr) {
		if (out_chunk) *out_chunk = nullptr;
		return TerrainSettings::TYPE_NONE;
	}
	if (out_chunk) *out_chunk = chunk;
	if (out_cx) *out_cx = local_x;
	if (out_cy) *out_cy = local_y;
	return chunk->type_per_cell[
			local_y * chunk_cells + local_x];
}

} // namespace

std::vector<DetachedIsland> ConnectedComponents::detach_islands(
		ChunkManager &manager,
		int chunk_cells,
		float cell_size_px,
		const std::vector<int32_t> &seed_cells_flat,
		int max_flood_size,
		std::vector<Vector2i> &out_affected_chunks) {
	std::vector<DetachedIsland> islands;
	if (seed_cells_flat.size() < 2) {
		return islands;
	}

	// Visited set tracks cells already explored by any flood. Keeps
	// multiple seeds from re-flooding the same island.
	std::unordered_set<uint64_t> globally_visited;

	const int32_t NEI_DX[4] = { 1, -1, 0, 0 };
	const int32_t NEI_DY[4] = { 0, 0, 1, -1 };

	std::unordered_set<Vector2i, Vector2iHasher> affected_chunks_set;

	for (size_t si = 0; si + 1 < seed_cells_flat.size(); si += 2) {
		const int32_t sx = seed_cells_flat[si];
		const int32_t sy = seed_cells_flat[si + 1];
		// Flood from each surviving 4-neighbor of this destroyed
		// cell.
		for (int n = 0; n < 4; n++) {
			const int32_t nx = sx + NEI_DX[n];
			const int32_t ny = sy + NEI_DY[n];
			if (globally_visited.count(key(nx, ny)) != 0) {
				continue;
			}
			uint8_t seed_type = cell_type_world(
					manager, chunk_cells, nx, ny,
					nullptr, nullptr, nullptr);
			if (seed_type == TerrainSettings::TYPE_NONE) {
				continue;
			}

			// BFS. Collect cells. Stop if we touch an anchor or
			// exceed the flood budget.
			std::deque<std::pair<int32_t, int32_t>> queue;
			std::vector<std::pair<int32_t, int32_t>> found;
			std::unordered_set<uint64_t> local_visited;
			queue.emplace_back(nx, ny);
			local_visited.insert(key(nx, ny));
			bool anchored = false;
			bool over_budget = false;

			while (!queue.empty()) {
				auto [cx, cy] = queue.front();
				queue.pop_front();
				uint8_t t = cell_type_world(
						manager, chunk_cells, cx, cy,
						nullptr, nullptr, nullptr);
				if (t == TerrainSettings::TYPE_NONE) {
					continue;
				}
				if (t == TerrainSettings::TYPE_INDESTRUCTIBLE) {
					anchored = true;
					break;
				}
				found.emplace_back(cx, cy);
				if (static_cast<int>(found.size()) > max_flood_size) {
					over_budget = true;
					break;
				}
				for (int d = 0; d < 4; d++) {
					const int32_t mx = cx + NEI_DX[d];
					const int32_t my = cy + NEI_DY[d];
					if (local_visited.count(key(mx, my)) != 0) {
						continue;
					}
					local_visited.insert(key(mx, my));
					queue.emplace_back(mx, my);
				}
			}

			// Mark every cell we saw (found + queue remainder)
			// globally visited so other seeds don't re-explore.
			for (const auto &p : found) {
				globally_visited.insert(key(p.first, p.second));
			}
			for (uint64_t k : local_visited) {
				globally_visited.insert(k);
			}

			if (anchored || over_budget || found.empty()) {
				continue;
			}

			// Build the detached island. Compute bbox, fill local
			// type + density buffers, and remove the cells from
			// the main world.
			DetachedIsland island;
			island.cell_coords_flat.reserve(found.size() * 2);
			int32_t min_x = INT32_MAX, min_y = INT32_MAX;
			int32_t max_x = INT32_MIN, max_y = INT32_MIN;
			for (const auto &p : found) {
				island.cell_coords_flat.push_back(p.first);
				island.cell_coords_flat.push_back(p.second);
				min_x = std::min(min_x, p.first);
				min_y = std::min(min_y, p.second);
				max_x = std::max(max_x, p.first);
				max_y = std::max(max_y, p.second);
			}
			island.min_cx = min_x;
			island.min_cy = min_y;
			island.max_cx = max_x;
			island.max_cy = max_y;

			const int32_t w = island.width_cells();
			const int32_t h = island.height_cells();
			island.local_type.assign(
					static_cast<size_t>(w) * h, TerrainSettings::TYPE_NONE);
			island.local_density.assign(
					static_cast<size_t>(w + 1) * (h + 1), 0);
			island.origin_px = Vector2(
					static_cast<float>(min_x) * cell_size_px,
					static_cast<float>(min_y) * cell_size_px);

			// Fill local type + mark corresponding corners solid.
			for (const auto &p : found) {
				const int32_t lx = p.first - min_x;
				const int32_t ly = p.second - min_y;
				Chunk *chunk = nullptr;
				int local_cx = 0, local_cy = 0;
				uint8_t t = cell_type_world(
						manager, chunk_cells,
						p.first, p.second,
						&chunk, &local_cx, &local_cy);
				island.local_type[ly * w + lx] = t;
				// Set the 4 corners around this cell to 255.
				for (int dy = 0; dy <= 1; dy++) {
					for (int dx = 0; dx <= 1; dx++) {
						island.local_density[
								(ly + dy) * (w + 1) + lx + dx] = 255;
					}
				}
			}

			// Clear the cells from the main world.
			for (const auto &p : found) {
				Chunk *chunk = nullptr;
				int local_cx = 0, local_cy = 0;
				cell_type_world(
						manager, chunk_cells,
						p.first, p.second,
						&chunk, &local_cx, &local_cy);
				if (chunk == nullptr) {
					continue;
				}
				const int cell_idx =
						local_cy * chunk_cells + local_cx;
				chunk->type_per_cell[cell_idx] =
						TerrainSettings::TYPE_NONE;
				chunk->health_per_cell[cell_idx] = 255;
				// Zero all 4 corners, then any neighbor cell with a
				// surviving type will restore its corner on its own
				// refresh. For a localized post-damage flood-fill
				// this is fine because we only detach cells with no
				// surviving neighbors — corners they share don't
				// belong to any non-NONE cell.
				const int s = chunk_cells + 1;
				chunk->density[local_cy * s + local_cx] = 0;
				chunk->density[local_cy * s + local_cx + 1] = 0;
				chunk->density[(local_cy + 1) * s + local_cx] = 0;
				chunk->density[(local_cy + 1) * s + local_cx + 1] = 0;
				chunk->generation.fetch_add(1);
				affected_chunks_set.insert(chunk->coords);
			}

			islands.push_back(std::move(island));
		}
	}

	out_affected_chunks.clear();
	out_affected_chunks.reserve(affected_chunks_set.size());
	for (const Vector2i &c : affected_chunks_set) {
		out_affected_chunks.push_back(c);
	}
	return islands;
}

} // namespace terrain
} // namespace godot
