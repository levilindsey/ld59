#ifndef KBTERRAIN_TERRAIN_DENSITY_SPLAT_H
#define KBTERRAIN_TERRAIN_DENSITY_SPLAT_H

#include <godot_cpp/variant/vector2.hpp>
#include <cstdint>

namespace godot {
namespace terrain {

// Circular density modification (carve / fill). Operates in-place on
// a density grid sized (cells+1) x (cells+1) stored row-major.
//
// Carve: subtracts density (to min 0) within `radius_px` of
// `center_px`, with smoothstep falloff across `feather_px`.
// Fill: adds density (to max 255) with the same falloff.
//
// `origin_px` is the world-space position of the chunk's (0, 0)
// density sample. `cell_size_px` is the world size between adjacent
// samples.
//
// Returns true if any cell was modified.
bool carve_circle(
		uint8_t *density,
		int cells_plus_one,
		Vector2 origin_px,
		float cell_size_px,
		Vector2 center_px,
		float radius_px,
		float strength_0_to_1,
		float feather_px = 2.0f);

bool fill_circle(
		uint8_t *density,
		int cells_plus_one,
		Vector2 origin_px,
		float cell_size_px,
		Vector2 center_px,
		float radius_px,
		float strength_0_to_1,
		float feather_px = 2.0f);

// Returns the AABB of cell indices a splat of radius `radius_px +
// feather_px` at `center_px` can touch inside this chunk. Used by
// callers to decide which chunks a splat affects. `out_min`/`out_max`
// are INCLUSIVE cell indices, clamped to [0, cells_plus_one-1].
void cells_affected_by_circle(
		int cells_plus_one,
		Vector2 origin_px,
		float cell_size_px,
		Vector2 center_px,
		float radius_px,
		float feather_px,
		int &out_min_x, int &out_min_y,
		int &out_max_x, int &out_max_y);

} // namespace terrain
} // namespace godot

#endif // KBTERRAIN_TERRAIN_DENSITY_SPLAT_H
