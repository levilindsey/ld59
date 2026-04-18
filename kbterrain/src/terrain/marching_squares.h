#ifndef KBTERRAIN_TERRAIN_MARCHING_SQUARES_H
#define KBTERRAIN_TERRAIN_MARCHING_SQUARES_H

#include <godot_cpp/variant/vector2.hpp>
#include <cstdint>
#include <vector>

namespace godot {
namespace terrain {

// Marching-squares mesh extraction from a uint8 density field.
//
// Density layout: we sample the 4 corners of each cell. For a chunk
// of N x N cells, the density grid has (N+1) x (N+1) samples, stored
// row-major: index = y * (N+1) + x.
//
// Cell corner bit assignment (for the 16-case table):
//   bit 0 = bottom-left corner  (x,   y+1)
//   bit 1 = bottom-right corner (x+1, y+1)
//   bit 2 = top-right corner    (x+1, y)
//   bit 3 = top-left corner     (x,   y)
// So case 5 = BL | TR (diagonal).
//
// A corner contributes its bit when density[corner] >= iso.
//
// Each cell emits:
//   - 0..2 interior triangle fans covering the "inside" (>= iso)
//     portion of the cell, for rendering a filled mesh.
//   - 0..2 line segments (pairs of endpoints) along the contour,
//     for rendering an edge outline or building a collision shape.
//
// Edge interpolation places contour endpoints on cell edges using:
//     t = (iso - d_a) / (d_b - d_a)
// clamped to [0, 1].
struct MeshResult {
	// Triangle mesh: indexed triangle list. verts are xy in world px,
	// indices are triangles (triples).
	std::vector<Vector2> verts;
	std::vector<uint16_t> indices;

	// Per-vertex colors (same length as verts). Used to encode the
	// tile type / frequency into the mesh so the composite shader
	// can identify it per pixel.
	std::vector<uint32_t> colors_rgba;

	// Boundary line-soup: pairs of endpoints (size is always even).
	// Collision uses this as ConcavePolygonShape2D segment data.
	std::vector<Vector2> boundary_segments;

	void clear() {
		verts.clear();
		indices.clear();
		colors_rgba.clear();
		boundary_segments.clear();
	}
};

// Pack RGBA8 into a uint32_t in Godot's Color::to_rgba32() layout.
inline uint32_t pack_rgba8(uint8_t r, uint8_t g, uint8_t b, uint8_t a) {
	return (static_cast<uint32_t>(r) << 24)
			| (static_cast<uint32_t>(g) << 16)
			| (static_cast<uint32_t>(b) << 8)
			| static_cast<uint32_t>(a);
}

// Mesh a single chunk of `cells x cells` cells, with density stored
// as `(cells+1) x (cells+1)` uint8 samples. `origin_px` is the
// world-space upper-left of the chunk, `cell_size_px` is the world
// size of one cell. All cells emit under `per_cell_color_rgba` unless
// `type_grid` is non-null, in which case per-cell type lookups are
// used instead — `type_grid[y * cells + x]` is the type at that
// cell; `type_to_color_rgba[type]` maps type → RGBA8. Types should
// be 0..255.
//
// `iso` is the density threshold: cells with any corner >= iso
// contribute to the mesh.
void mesh_chunk(
		const uint8_t *density,
		int cells,
		float cell_size_px,
		Vector2 origin_px,
		uint8_t iso,
		uint32_t per_cell_color_rgba,
		const uint8_t *type_grid,
		const uint32_t *type_to_color_rgba,
		MeshResult &out);

} // namespace terrain
} // namespace godot

#endif // KBTERRAIN_TERRAIN_MARCHING_SQUARES_H
