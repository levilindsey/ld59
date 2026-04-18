#ifndef KBTERRAIN_TERRAIN_DOUGLAS_PEUCKER_H
#define KBTERRAIN_TERRAIN_DOUGLAS_PEUCKER_H

#include <godot_cpp/variant/vector2.hpp>
#include <vector>

namespace godot {
namespace terrain {

// Ramer-Douglas-Peucker polyline simplification.
// Points are a single polyline (not a pair-encoded line soup).
// `epsilon_px` is the maximum perpendicular distance a removed point
// may have from the simplified line. Returns a new vector containing
// the simplified polyline with endpoints preserved.
std::vector<Vector2> simplify_polyline(
		const std::vector<Vector2> &points, float epsilon_px);

// Simplify a pair-encoded line soup (as produced by
// `mesh_chunk().boundary_segments`) by first chaining connected
// segments into polylines, then simplifying each polyline, then
// re-encoding back to pairs.
//
// `weld_epsilon_sq_px` controls how close two endpoints must be to
// be treated as the same vertex for chaining. A typical value is
// (cell_size * 0.01)^2.
std::vector<Vector2> simplify_line_soup(
		const std::vector<Vector2> &segments,
		float epsilon_px,
		float weld_epsilon_sq_px);

} // namespace terrain
} // namespace godot

#endif // KBTERRAIN_TERRAIN_DOUGLAS_PEUCKER_H
