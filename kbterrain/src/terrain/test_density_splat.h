#ifndef KBTERRAIN_TERRAIN_TEST_DENSITY_SPLAT_H
#define KBTERRAIN_TERRAIN_TEST_DENSITY_SPLAT_H

#ifdef KBTERRAIN_TESTS_ENABLED

#include "density_splat.h"

#include <gtest/gtest.h>

#include <vector>

namespace godot {
namespace terrain {

// Fill a (N+1)^2 buffer with a single value for tests.
static std::vector<uint8_t> filled(int cells_plus_one, uint8_t v) {
	return std::vector<uint8_t>(cells_plus_one * cells_plus_one, v);
}

TEST(DensitySplatTest, CarveEmptiesCenterCell) {
	auto d = filled(17, 255);
	// cell_size = 8, so chunk is 0..128. Center splat at (64, 64),
	// radius 4, feather 0.
	const bool changed = carve_circle(
			d.data(), 17, Vector2(0, 0), 8.0f,
			Vector2(64, 64), 4.0f, 1.0f, 0.0f);
	EXPECT_TRUE(changed);
	// Sample at cell (8, 8) = position (64, 64) → should be 0.
	EXPECT_EQ(0, d[8 * 17 + 8]);
	// A corner sample (0, 0) should be unchanged.
	EXPECT_EQ(255, d[0]);
}

TEST(DensitySplatTest, FillIsInverseOfCarve) {
	auto d = filled(17, 0);
	fill_circle(d.data(), 17, Vector2(0, 0), 8.0f,
			Vector2(64, 64), 4.0f, 1.0f, 0.0f);
	EXPECT_EQ(255, d[8 * 17 + 8]);
}

TEST(DensitySplatTest, CarveFeatherFallsOffOutsideRadius) {
	auto d = filled(17, 255);
	// Radius 16 with feather 16 → total 32 px reach.
	carve_circle(d.data(), 17, Vector2(0, 0), 8.0f,
			Vector2(64, 64), 16.0f, 1.0f, 16.0f);
	// Center cell (8,8) → fully carved.
	EXPECT_EQ(0, d[8 * 17 + 8]);
	// Cell (10,8) is 16 px from center (1 cell sampled at +16 world) →
	// at the radius boundary, still fully carved.
	EXPECT_EQ(0, d[8 * 17 + 10]);
	// Cell (12,8) is 32 px from center → past feather, unchanged.
	EXPECT_EQ(255, d[8 * 17 + 12]);
	// Cell (11,8) is 24 px from center → feather midpoint, partial.
	const int partial = d[8 * 17 + 11];
	EXPECT_GT(partial, 0);
	EXPECT_LT(partial, 255);
}

TEST(DensitySplatTest, CarveClampsToZero) {
	auto d = filled(17, 100);
	// Repeated full-strength carve should leave cells at 0 and stay.
	for (int i = 0; i < 5; i++) {
		carve_circle(d.data(), 17, Vector2(0, 0), 8.0f,
				Vector2(64, 64), 4.0f, 1.0f, 0.0f);
	}
	EXPECT_EQ(0, d[8 * 17 + 8]);
}

TEST(DensitySplatTest, CellsAffectedAabbClampsToChunk) {
	int min_x, min_y, max_x, max_y;
	cells_affected_by_circle(
			17, Vector2(0, 0), 8.0f, Vector2(-100, -100), 4.0f, 0.0f,
			min_x, min_y, max_x, max_y);
	// Splat entirely outside chunk → inverted range (min > max).
	EXPECT_GT(min_x, max_x);
}

TEST(DensitySplatTest, SplatOutsideChunkDoesNothing) {
	auto d = filled(17, 255);
	const bool changed = carve_circle(
			d.data(), 17, Vector2(0, 0), 8.0f,
			Vector2(-100, -100), 4.0f, 1.0f, 0.0f);
	EXPECT_FALSE(changed);
	EXPECT_EQ(255, d[0]);
}

} // namespace terrain
} // namespace godot

#endif // KBTERRAIN_TESTS_ENABLED

#endif // KBTERRAIN_TERRAIN_TEST_DENSITY_SPLAT_H
