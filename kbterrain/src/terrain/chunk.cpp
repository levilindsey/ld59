#include "chunk.h"

namespace godot {
namespace terrain {

Chunk::Chunk(Vector2i p_coords, int p_cells)
		: coords(p_coords),
		  cells(p_cells),
		  density((p_cells + 1) * (p_cells + 1), 0),
		  type_per_cell(p_cells * p_cells, 0),
		  health_per_cell(p_cells * p_cells, 255),
		  generation(1),
		  canvas_item_rid(),
		  static_body_rid(),
		  shape_rids() {}

} // namespace terrain
} // namespace godot
