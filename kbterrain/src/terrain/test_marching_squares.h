#ifndef KBTERRAIN_TERRAIN_TEST_MARCHING_SQUARES_H
#define KBTERRAIN_TERRAIN_TEST_MARCHING_SQUARES_H

#ifdef KBTERRAIN_TESTS_ENABLED

#include "marching_squares.h"

#include <gtest/gtest.h>

namespace godot {
namespace terrain {

namespace ms_test {

// 1x1 cell (2x2 sample grid). Returns a mesh result.
inline MeshResult mesh_1x1(uint8_t tl, uint8_t tr, uint8_t br, uint8_t bl,
		uint8_t iso = 128, float size = 10.0f) {
	// Density grid layout: row-major, (y, x). Row 0 = top.
	//   (0,0)=TL, (0,1)=TR
	//   (1,0)=BL, (1,1)=BR
	uint8_t density[4] = { tl, tr, bl, br };
	MeshResult out;
	mesh_chunk(density, 1, size, Vector2(0, 0), iso,
			/* per_cell_color */ 0xFFFFFFFF,
			/* type_grid */ nullptr,
			/* type_to_color */ nullptr,
			out);
	return out;
}

} // namespace ms_test

TEST(MarchingSquaresTest, EmptyCellProducesNothing) {
	auto out = ms_test::mesh_1x1(0, 0, 0, 0);
	EXPECT_TRUE(out.verts.empty());
	EXPECT_TRUE(out.indices.empty());
	EXPECT_TRUE(out.boundary_segments.empty());
}

TEST(MarchingSquaresTest, FullCellProducesFilledQuadNoBoundary) {
	auto out = ms_test::mesh_1x1(255, 255, 255, 255);
	// 2 triangles with no vertex sharing = 6 indices, 6 verts.
	EXPECT_EQ(6u, out.indices.size());
	EXPECT_EQ(6u, out.verts.size());
	EXPECT_TRUE(out.boundary_segments.empty());
}

TEST(MarchingSquaresTest, SingleCornerProducesSmallTriangle) {
	// BL only inside (case 1).
	auto out = ms_test::mesh_1x1(
			/*tl*/ 0, /*tr*/ 0, /*br*/ 0, /*bl*/ 255);
	EXPECT_EQ(3u, out.verts.size());
	EXPECT_EQ(3u, out.indices.size());
	// One segment connecting left-edge and bottom-edge crossings.
	EXPECT_EQ(2u, out.boundary_segments.size());
}

TEST(MarchingSquaresTest, BottomHalfProducesTrapezoid) {
	// Bottom two inside (case 3).
	auto out = ms_test::mesh_1x1(
			/*tl*/ 0, /*tr*/ 0, /*br*/ 255, /*bl*/ 255);
	// Trapezoid as 2 un-shared triangles: 6 verts, 6 indices.
	EXPECT_EQ(6u, out.verts.size());
	EXPECT_EQ(6u, out.indices.size());
	// One boundary segment.
	EXPECT_EQ(2u, out.boundary_segments.size());
}

TEST(MarchingSquaresTest, DiagonalCase5ProducesTwoTriangles) {
	// BL and TR inside (case 5, ambiguous).
	auto out = ms_test::mesh_1x1(
			/*tl*/ 0, /*tr*/ 255, /*br*/ 0, /*bl*/ 255);
	EXPECT_EQ(6u, out.verts.size());
	EXPECT_EQ(6u, out.indices.size());
	// Two segments (4 endpoints).
	EXPECT_EQ(4u, out.boundary_segments.size());
}

TEST(MarchingSquaresTest, DiagonalCase10ProducesTwoTriangles) {
	// BR and TL inside (case 10, ambiguous).
	auto out = ms_test::mesh_1x1(
			/*tl*/ 255, /*tr*/ 0, /*br*/ 255, /*bl*/ 0);
	EXPECT_EQ(6u, out.verts.size());
	EXPECT_EQ(6u, out.indices.size());
	EXPECT_EQ(4u, out.boundary_segments.size());
}

TEST(MarchingSquaresTest, EdgeInterpolationAtMidpoint) {
	// BL=0, BR=255: iso=128 → bottom-edge crossing at the midpoint.
	auto out = ms_test::mesh_1x1(
			/*tl*/ 0, /*tr*/ 0, /*br*/ 255, /*bl*/ 0,
			/*iso*/ 128, /*size*/ 10.0f);
	// Case 2 (BR only): one triangle + one segment.
	ASSERT_EQ(2u, out.boundary_segments.size());
	// The bottom-edge crossing should be at x ≈ 5 (midpoint).
	// Find the segment endpoint with y ≈ 10 (the bottom).
	bool found_midpoint = false;
	for (auto &v : out.boundary_segments) {
		if (v.y > 9.9f && v.y < 10.1f) {
			// x should be near 5 for a 128/255 threshold on 0→255.
			// t = (128 - 0) / (255 - 0) = 0.5019, so x ≈ 5.02.
			if (v.x > 4.8f && v.x < 5.2f) {
				found_midpoint = true;
			}
		}
	}
	EXPECT_TRUE(found_midpoint);
}

TEST(MarchingSquaresTest, MultiCellChunkRuns) {
	// 4x4 density grid = 3x3 cells; fill lower half solid, upper empty.
	constexpr int CELLS = 3;
	constexpr int STRIDE = CELLS + 1;
	uint8_t density[STRIDE * STRIDE] = {};
	for (int y = 0; y < STRIDE; y++) {
		for (int x = 0; x < STRIDE; x++) {
			density[y * STRIDE + x] = (y >= 2) ? 255 : 0;
		}
	}
	MeshResult out;
	mesh_chunk(density, CELLS, 8.0f, Vector2(0, 0), 128,
			0xFF0000FF, nullptr, nullptr, out);
	// Bottom row of cells should be fully solid; middle row half; top
	// row empty. Just assert we got some verts and boundary.
	EXPECT_GT(out.verts.size(), 0u);
	EXPECT_GT(out.boundary_segments.size(), 0u);
}

} // namespace terrain
} // namespace godot

#endif // KBTERRAIN_TESTS_ENABLED

#endif // KBTERRAIN_TERRAIN_TEST_MARCHING_SQUARES_H
