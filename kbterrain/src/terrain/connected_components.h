#ifndef KBTERRAIN_TERRAIN_CONNECTED_COMPONENTS_H
#define KBTERRAIN_TERRAIN_CONNECTED_COMPONENTS_H

#include "chunk.h"
#include "chunk_manager.h"

#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <cstdint>
#include <vector>

namespace godot {
namespace terrain {

// A single island of terrain cells that's become disconnected from
// any anchor (INDESTRUCTIBLE cell or out-of-bounds edge). The detach
// pipeline extracts one of these, removes its cells from the main
// world, and spawns a RigidBody2D fragment from the same data.
struct DetachedIsland {
	// World-cell coordinates of every cell in the island.
	// Format: pairs of (world_cell_x, world_cell_y) as int32 — flat
	// vector because std::vector<Vector2i> is heavier than we need.
	// world_cell = chunk_coord * cells + cell_in_chunk.
	std::vector<int32_t> cell_coords_flat;

	// Axis-aligned bounding box of the island in world-cell coords.
	int32_t min_cx = 0;
	int32_t min_cy = 0;
	int32_t max_cx = 0;
	int32_t max_cy = 0;

	// Dense local density buffer for marching-squares. Size
	// (width+1) * (height+1). width = max_cx - min_cx + 1, etc.
	std::vector<uint8_t> local_density;
	// Dense local type buffer, size width * height.
	std::vector<uint8_t> local_type;
	// Dense local health buffer, size width * height. Zero for empty
	// cells; mirrors the cell's health in the main world at the moment
	// of detach so merge-back can restore the exact state.
	std::vector<uint8_t> local_health;

	// Origin in world pixels (upper-left of the bounding box).
	Vector2 origin_px;

	int32_t width_cells() const { return max_cx - min_cx + 1; }
	int32_t height_cells() const { return max_cy - min_cy + 1; }
};

class ConnectedComponents {
public:
	// After a batch of damage has destroyed cells, find every
	// connected island of remaining-solid cells that doesn't touch
	// an anchor. Returns detached islands with their local density
	// and type buffers already extracted.
	//
	// `seed_cells` is the world-cell coords of cells whose neighbors
	// might now be isolated (typically: cells that were destroyed).
	// Flood-fill scans from each seed's 4-neighbors, bounded by
	// `max_flood_size` (islands larger than this are assumed to be
	// part of the main world and not detached).
	//
	// On return, islands with cells removed from the main world —
	// the caller should queue remeshes for all chunks listed in
	// `out_affected_chunks`.
	static std::vector<DetachedIsland> detach_islands(
			ChunkManager &manager,
			int chunk_cells,
			float cell_size_px,
			const std::vector<int32_t> &seed_cells_flat,
			int max_flood_size,
			std::vector<Vector2i> &out_affected_chunks);
};

} // namespace terrain
} // namespace godot

#endif // KBTERRAIN_TERRAIN_CONNECTED_COMPONENTS_H
