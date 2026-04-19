#ifndef KBTERRAIN_TERRAIN_CHUNK_H
#define KBTERRAIN_TERRAIN_CHUNK_H

#include <godot_cpp/variant/rid.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <atomic>
#include <cstdint>
#include <vector>

namespace godot {
namespace terrain {

// A single chunk of terrain data. Stores density, type, and health
// per cell, plus the RIDs Godot uses to render and collide it.
//
// Density layout: (cells+1) x (cells+1) u8, row-major, where cells
// is the TerrainSettings::chunk_cells value. The +1 row/col overlap
// with the neighbor chunk so marching-squares edges line up; edits
// that touch the overlap must mirror into the neighbor.
//
// Type and health grids are cells x cells, row-major. They describe
// the cell's dominant type (Frequency enum) and hit points.
class Chunk {
public:
	Vector2i coords;
	int cells;

	// (cells+1)*(cells+1) density samples, 0..255.
	std::vector<uint8_t> density;
	// cells*cells cell-data grids.
	std::vector<uint8_t> type_per_cell;
	std::vector<uint8_t> health_per_cell;

	// Generation counter. Incremented on any density/type edit.
	// The worker captures this at remesh submit time and the main
	// thread compares on integration to discard stale results.
	std::atomic<uint64_t> generation;

	// Godot render and physics handles. Owned by the Chunk;
	// freed in ChunkManager::free_chunk_rids.
	RID canvas_item_rid;
	RID static_body_rid;
	// One ConvexPolygonShape2D per mesh triangle. Filled shapes give
	// robust depenetration against CharacterBody2D; ConcavePolygonShape2D
	// segments would, but their segment-vs-filled-shape collision in
	// Godot 2D allows half-shape penetration.
	std::vector<RID> shape_rids;

	Chunk(Vector2i p_coords, int p_cells);
	Chunk(const Chunk &) = delete;
	Chunk &operator=(const Chunk &) = delete;

	inline int samples_side() const { return cells + 1; }

	// Row-major index helpers.
	inline int density_index(int x, int y) const {
		return y * (cells + 1) + x;
	}
	inline int cell_index(int x, int y) const {
		return y * cells + x;
	}

	// Returns the world-space origin (upper-left) of the chunk for
	// the given cell_size.
	inline Vector2 origin_px(float cell_size_px) const {
		return Vector2(
				coords.x * cells * cell_size_px,
				coords.y * cells * cell_size_px);
	}
};

} // namespace terrain
} // namespace godot

#endif // KBTERRAIN_TERRAIN_CHUNK_H
