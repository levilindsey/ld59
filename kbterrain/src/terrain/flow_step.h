#ifndef KBTERRAIN_TERRAIN_FLOW_STEP_H
#define KBTERRAIN_TERRAIN_FLOW_STEP_H

#include "chunk.h"
#include "chunk_manager.h"
#include "terrain_settings.h"

#include <godot_cpp/variant/vector2i.hpp>

#include <cstdint>
#include <vector>

namespace godot {
namespace terrain {

// Binary-cell falling-sand-style cellular automaton for SAND and
// LIQUID terrain types. Operates on per-cell type grids; density
// corners are kept consistent via a localized rebuild from the
// post-step type neighborhood.
//
// Rules (executed bottom-up for each chunk, alternating L/R scan
// direction per frame to avoid left-bias):
//
//   SAND:
//     - If the cell directly below is empty, move there.
//     - Else try diagonal down (first the frame's preferred side,
//       then the other).
//
//   LIQUID:
//     - Sand rules above, plus:
//     - If still blocked, try sideways (preferred side first).
//
// "Empty" means the destination cell has `TYPE_NONE` and its density
// is below the iso threshold.
//
// Cross-chunk moves are supported via the ChunkManager; if the target
// chunk doesn't exist, the cell is treated as solid (move rejected).
// Chunks touched by a move are added to `out_dirty_chunks` so the
// caller can queue remeshes.
//
// Fluid velocity is tracked per cell as an int8 (dx, dy) running
// exponentially-decayed accumulator: each move adds ±1 to the source
// and target cells' velocity components. Decay applied before each
// step. Sample via `sample_fluid_velocity`.
class FlowStep {
public:
	FlowStep();

	// Advance simulation by one step over all chunks in the manager.
	// Runs in-place on main-thread chunk data. Returns true if any
	// cell moved.
	bool step_world(
			ChunkManager &manager,
			int chunk_cells,
			uint8_t iso,
			std::vector<Vector2i> &out_dirty_chunks);

	// Bilinearly sample the (smoothed) per-cell fluid velocity field
	// at the given world position. Returns Vector2(0, 0) for cells
	// that are not currently liquid or have no recent flow.
	Vector2 sample_fluid_velocity(
			const ChunkManager &manager,
			Vector2 world_pos,
			int chunk_cells,
			float cell_size_px) const;

	// Reset per-cell velocity tracking (e.g., on level reset).
	void reset_velocity_cache();

private:
	// Per-chunk bookkeeping. Keyed by chunk coords; allocated lazily
	// as chunks come into play.
	struct ChunkFlow {
		// cells*cells int8 arrays. Range [-127, 127].
		std::vector<int8_t> vel_x;
		std::vector<int8_t> vel_y;
		// cells*cells bit: 1 if the cell was moved this frame.
		std::vector<uint8_t> moved_this_frame;
	};

	// Frame counter so we can flip scan direction each step.
	uint64_t _step_counter = 0;

	std::unordered_map<Vector2i, ChunkFlow, Vector2iHasher> _flow_by_chunk;

	ChunkFlow &_get_or_create_flow(Vector2i coords, int chunk_cells);

	// Process one cell; may issue a move. Returns true if moved.
	bool _try_sand(
			Chunk &chunk,
			ChunkFlow &flow,
			int cx,
			int cy,
			ChunkManager &manager,
			int chunk_cells,
			uint8_t iso,
			bool prefer_right,
			std::vector<Vector2i> &dirty);

	bool _try_liquid(
			Chunk &chunk,
			ChunkFlow &flow,
			int cx,
			int cy,
			ChunkManager &manager,
			int chunk_cells,
			uint8_t iso,
			bool prefer_right,
			std::vector<Vector2i> &dirty);

	// Execute a cell→cell move (possibly cross-chunk). Returns true
	// on success. Updates density corners, type grids, health, and
	// velocity tracking. Records dirty chunks in `dirty`.
	bool _move_cell(
			Chunk &src_chunk,
			ChunkFlow &src_flow,
			int src_cx,
			int src_cy,
			Chunk &dst_chunk,
			ChunkFlow &dst_flow,
			int dst_cx,
			int dst_cy,
			int chunk_cells,
			std::vector<Vector2i> &dirty);

	// Like `_move_cell` but swaps the src and dst cell contents.
	// Used so sand can fall through liquid — sand goes down, liquid
	// floats up into the vacated cell.
	bool _swap_cells(
			Chunk &src_chunk,
			ChunkFlow &src_flow,
			int src_cx,
			int src_cy,
			Chunk &dst_chunk,
			ChunkFlow &dst_flow,
			int dst_cx,
			int dst_cy,
			int chunk_cells,
			std::vector<Vector2i> &dirty);

	// Attempt a sand move in (offset_x, offset_y). Handles normal
	// move into empty cells AND swap-through-liquid.
	bool _try_sand_move(
			Chunk &chunk,
			ChunkFlow &flow,
			int cx,
			int cy,
			int offset_x,
			int offset_y,
			ChunkManager &manager,
			int chunk_cells,
			uint8_t iso,
			std::vector<Vector2i> &dirty);

	// Is the cell at (cx, cy) in chunk (possibly looked up via
	// manager if cx/cy is out of range) empty for flow purposes?
	// Sets *out_chunk / *out_cx / *out_cy to the target if non-null.
	bool _is_empty(
			Chunk &src_chunk,
			int cx,
			int cy,
			ChunkManager &manager,
			int chunk_cells,
			uint8_t iso,
			Chunk **out_chunk,
			ChunkFlow **out_flow,
			int *out_cx,
			int *out_cy);

	// Recompute density corners around a changed cell from local
	// type neighborhood. Corner density is 255 if any of the 4
	// adjacent cells has type != NONE else 0. Cross-chunk neighbors
	// are not consulted — adjacent chunks queue their own remeshes
	// and the composited render is continuous.
	void _refresh_corner_density(
			Chunk &chunk,
			int cx,
			int cy,
			int chunk_cells);

	static inline void _velocity_add(int8_t &v, int delta) {
		int n = static_cast<int>(v) + delta;
		if (n > 127) n = 127;
		if (n < -128) n = -128;
		v = static_cast<int8_t>(n);
	}
};

} // namespace terrain
} // namespace godot

#endif // KBTERRAIN_TERRAIN_FLOW_STEP_H
