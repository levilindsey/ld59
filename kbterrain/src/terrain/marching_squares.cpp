#include "marching_squares.h"

#include <algorithm>

namespace godot {
namespace terrain {

namespace {

// Edge indices:
//   0 = bottom (BL↔BR), 1 = right (BR↔TR),
//   2 = top    (TR↔TL), 3 = left  (TL↔BL)
// Corner indices (matching the bit layout):
//   0 = BL, 1 = BR, 2 = TR, 3 = TL

// For a given 4-bit case, which pairs of edges are connected as
// boundary segments (one or two pairs). -1 terminates the list.
// For ambiguous cases (5 and 10) we pick the "corners joined"
// resolution.
struct CaseEdges {
	int segments[4]; // up to 2 segments = 4 edges
	int count;
};

// clang-format off
static constexpr CaseEdges CASE_TABLE[16] = {
	// 0: empty
	{{-1, -1, -1, -1}, 0},
	// 1: BL inside → edge 3 to edge 0 (left to bottom)
	{{3, 0, -1, -1}, 1},
	// 2: BR inside → edge 0 to edge 1
	{{0, 1, -1, -1}, 1},
	// 3: BL+BR (bottom) → edge 3 to edge 1
	{{3, 1, -1, -1}, 1},
	// 4: TR inside → edge 1 to edge 2
	{{1, 2, -1, -1}, 1},
	// 5: BL+TR (diagonal). Pick "corners connected" — two segments.
	//    BL-isolated: edge 3 to edge 0. TR-isolated: edge 1 to edge 2.
	{{3, 0, 1, 2}, 2},
	// 6: BR+TR (right) → edge 0 to edge 2
	{{0, 2, -1, -1}, 1},
	// 7: BL+BR+TR (all but TL) → edge 3 to edge 2
	{{3, 2, -1, -1}, 1},
	// 8: TL inside → edge 2 to edge 3
	{{2, 3, -1, -1}, 1},
	// 9: BL+TL (left) → edge 2 to edge 0
	{{2, 0, -1, -1}, 1},
	// 10: BR+TL diagonal — corners connected.
	//     BR-isolated: edge 0 to edge 1. TL-isolated: edge 2 to 3.
	{{0, 1, 2, 3}, 2},
	// 11: BL+BR+TL (all but TR) → edge 2 to edge 1
	{{2, 1, -1, -1}, 1},
	// 12: TR+TL (top) → edge 1 to edge 3
	{{1, 3, -1, -1}, 1},
	// 13: BL+TR+TL (all but BR) → edge 1 to edge 0
	{{1, 0, -1, -1}, 1},
	// 14: BR+TR+TL (all but BL) → edge 0 to edge 3
	{{0, 3, -1, -1}, 1},
	// 15: all inside
	{{-1, -1, -1, -1}, 0},
};
// clang-format on

// Interpolate along an edge between two samples, returning t in [0, 1].
inline float edge_t(int d_a, int d_b, int iso) {
	const int diff = d_b - d_a;
	if (diff == 0) {
		return 0.5f;
	}
	float t = static_cast<float>(iso - d_a) / static_cast<float>(diff);
	if (t < 0.0f) {
		return 0.0f;
	}
	if (t > 1.0f) {
		return 1.0f;
	}
	return t;
}

// Compute the world-space endpoint for edge `e` of a cell whose
// upper-left corner is at `origin` and whose size is `size`. The
// corner densities are d[BL], d[BR], d[TR], d[TL] in that order.
Vector2 edge_endpoint(int e, Vector2 origin, float size,
		const int d[4], int iso) {
	switch (e) {
		case 0: { // bottom: BL (0,1) to BR (1,1)
			const float t = edge_t(d[0], d[1], iso);
			return Vector2(origin.x + t * size, origin.y + size);
		}
		case 1: { // right: BR (1,1) to TR (1,0)
			const float t = edge_t(d[1], d[2], iso);
			return Vector2(origin.x + size, origin.y + size - t * size);
		}
		case 2: { // top: TR (1,0) to TL (0,0)
			const float t = edge_t(d[2], d[3], iso);
			return Vector2(origin.x + size - t * size, origin.y);
		}
		case 3: { // left: TL (0,0) to BL (0,1)
			const float t = edge_t(d[3], d[0], iso);
			return Vector2(origin.x, origin.y + t * size);
		}
		default:
			return Vector2();
	}
}

// Corner positions (upper-left origin, y grows downward in 2D).
inline Vector2 corner_pos(int c, Vector2 origin, float size) {
	// 0 = BL, 1 = BR, 2 = TR, 3 = TL
	switch (c) {
		case 0:
			return Vector2(origin.x, origin.y + size);
		case 1:
			return Vector2(origin.x + size, origin.y + size);
		case 2:
			return Vector2(origin.x + size, origin.y);
		case 3:
			return Vector2(origin.x, origin.y);
		default:
			return Vector2();
	}
}

// Add a single triangle to `out`.
inline void emit_triangle(MeshResult &out, Vector2 a, Vector2 b, Vector2 c,
		uint32_t color_rgba) {
	const uint16_t i0 = static_cast<uint16_t>(out.verts.size());
	out.verts.push_back(a);
	out.verts.push_back(b);
	out.verts.push_back(c);
	out.colors_rgba.push_back(color_rgba);
	out.colors_rgba.push_back(color_rgba);
	out.colors_rgba.push_back(color_rgba);
	out.indices.push_back(i0);
	out.indices.push_back(static_cast<uint16_t>(i0 + 1));
	out.indices.push_back(static_cast<uint16_t>(i0 + 2));
}

// Emit the filled interior for one cell case. This fan-triangulates
// the "inside" polygon from a chosen anchor vertex. Polygon vertices
// are collected in CW order by walking corners and edge crossings.
void emit_interior(int cs, Vector2 origin, float size, const int d[4],
		int iso, uint32_t color_rgba, MeshResult &out) {
	// Collect polygon vertices in a fixed walk order:
	// BL → (edge0) → BR → (edge1) → TR → (edge2) → TL → (edge3) → BL.
	// At each corner, include it if inside. At each edge, include the
	// crossing if the adjacent corners differ in inside/outside.
	Vector2 poly[8];
	int n = 0;

	auto push = [&](Vector2 p) { poly[n++] = p; };

	// BL corner
	if (cs & 0x1) {
		push(corner_pos(0, origin, size));
	}
	// edge 0 (BL↔BR)
	if (((cs >> 0) & 1) != ((cs >> 1) & 1)) {
		push(edge_endpoint(0, origin, size, d, iso));
	}
	// BR corner
	if (cs & 0x2) {
		push(corner_pos(1, origin, size));
	}
	// edge 1 (BR↔TR)
	if (((cs >> 1) & 1) != ((cs >> 2) & 1)) {
		push(edge_endpoint(1, origin, size, d, iso));
	}
	// TR corner
	if (cs & 0x4) {
		push(corner_pos(2, origin, size));
	}
	// edge 2 (TR↔TL)
	if (((cs >> 2) & 1) != ((cs >> 3) & 1)) {
		push(edge_endpoint(2, origin, size, d, iso));
	}
	// TL corner
	if (cs & 0x8) {
		push(corner_pos(3, origin, size));
	}
	// edge 3 (TL↔BL)
	if (((cs >> 3) & 1) != ((cs >> 0) & 1)) {
		push(edge_endpoint(3, origin, size, d, iso));
	}

	if (n < 3) {
		return;
	}

	// Fan triangulate from poly[0]. Note: this isn't correct for
	// ambiguous diagonal cases (5, 10). Handle those separately.
	if (cs == 5 || cs == 10) {
		// Two disjoint triangles. Case 5: BL and TR isolated islands.
		// Case 10: BR and TL isolated.
		if (cs == 5) {
			// BL triangle: BL, edge0 crossing, edge3 crossing.
			emit_triangle(out,
					corner_pos(0, origin, size),
					edge_endpoint(0, origin, size, d, iso),
					edge_endpoint(3, origin, size, d, iso),
					color_rgba);
			// TR triangle: TR, edge2 crossing, edge1 crossing.
			emit_triangle(out,
					corner_pos(2, origin, size),
					edge_endpoint(2, origin, size, d, iso),
					edge_endpoint(1, origin, size, d, iso),
					color_rgba);
		} else {
			// BR triangle: BR, edge1 crossing, edge0 crossing.
			emit_triangle(out,
					corner_pos(1, origin, size),
					edge_endpoint(1, origin, size, d, iso),
					edge_endpoint(0, origin, size, d, iso),
					color_rgba);
			// TL triangle: TL, edge3 crossing, edge2 crossing.
			emit_triangle(out,
					corner_pos(3, origin, size),
					edge_endpoint(3, origin, size, d, iso),
					edge_endpoint(2, origin, size, d, iso),
					color_rgba);
		}
		return;
	}

	for (int i = 1; i < n - 1; i++) {
		emit_triangle(out, poly[0], poly[i], poly[i + 1], color_rgba);
	}
}

} // namespace

void mesh_chunk(
		const uint8_t *density,
		int cells,
		float cell_size_px,
		Vector2 origin_px,
		uint8_t iso,
		uint32_t per_cell_color_rgba,
		const uint8_t *type_grid,
		const uint32_t *type_to_color_rgba,
		MeshResult &out,
		uint8_t collision_skip_type) {
	out.clear();
	(void)collision_skip_type;

	const int stride = cells + 1;

	for (int y = 0; y < cells; y++) {
		for (int x = 0; x < cells; x++) {
			// Sample densities at the 4 corners.
			// d[0]=BL, d[1]=BR, d[2]=TR, d[3]=TL.
			const int d[4] = {
				density[(y + 1) * stride + x], // BL
				density[(y + 1) * stride + (x + 1)], // BR
				density[y * stride + (x + 1)], // TR
				density[y * stride + x], // TL
			};

			int cs = 0;
			if (d[0] >= iso) {
				cs |= 0x1;
			}
			if (d[1] >= iso) {
				cs |= 0x2;
			}
			if (d[2] >= iso) {
				cs |= 0x4;
			}
			if (d[3] >= iso) {
				cs |= 0x8;
			}

			if (cs == 0) {
				continue;
			}

			uint32_t color = per_cell_color_rgba;
			uint8_t type_here = 0;
			if (type_grid != nullptr && type_to_color_rgba != nullptr) {
				type_here = type_grid[y * cells + x];
				color = type_to_color_rgba[type_here];
			}

			const Vector2 origin = Vector2(
					origin_px.x + x * cell_size_px,
					origin_px.y + y * cell_size_px);

			// Only emit interior triangles for fully-solid, typed cells.
			// `cs == 15` rules out partial cases (degenerate at
			// iso=255; half-cell trapezoids at iso<255). `type_here
			// != 0` rules out hollow case-15 cells — cells whose
			// corners are all 255 because neighbor cells are painted,
			// but whose own type is NONE. Emitting those would produce
			// transparent triangles that some drivers still raster
			// with visible artifacts. Combined, the mesh lives
			// strictly inside authored cell boundaries.
			if (cs == 15 && type_here != 0) {
				emit_interior(
						cs, origin, cell_size_px, d, iso, color, out);
			}

			const CaseEdges &ce = CASE_TABLE[cs];
			for (int s = 0; s < ce.count; s++) {
				const int e_a = ce.segments[s * 2 + 0];
				const int e_b = ce.segments[s * 2 + 1];
				const Vector2 pa = edge_endpoint(
						e_a, origin, cell_size_px, d, iso);
				const Vector2 pb = edge_endpoint(
						e_b, origin, cell_size_px, d, iso);
				out.boundary_segments.push_back(pa);
				out.boundary_segments.push_back(pb);
			}
		}
	}
}

} // namespace terrain
} // namespace godot
