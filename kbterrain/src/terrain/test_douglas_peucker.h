#ifndef KBTERRAIN_TERRAIN_TEST_DOUGLAS_PEUCKER_H
#define KBTERRAIN_TERRAIN_TEST_DOUGLAS_PEUCKER_H

#ifdef KBTERRAIN_TESTS_ENABLED

#include "douglas_peucker.h"

#include <gtest/gtest.h>

namespace godot {
namespace terrain {

TEST(DouglasPeuckerTest, StraightLineCollapsesToEndpoints) {
	std::vector<Vector2> line;
	for (int i = 0; i <= 20; i++) {
		line.push_back(Vector2(static_cast<float>(i), 0.0f));
	}
	auto out = simplify_polyline(line, 0.1f);
	EXPECT_EQ(2u, out.size());
	EXPECT_FLOAT_EQ(0.0f, out.front().x);
	EXPECT_FLOAT_EQ(20.0f, out.back().x);
}

TEST(DouglasPeuckerTest, ZigZagPreservedWithTightEpsilon) {
	std::vector<Vector2> zig;
	// Alternating 0/1 y over 10 x steps.
	for (int i = 0; i < 10; i++) {
		zig.push_back(Vector2(static_cast<float>(i),
				(i % 2 == 0) ? 0.0f : 1.0f));
	}
	auto tight = simplify_polyline(zig, 0.1f);
	EXPECT_GT(tight.size(), 5u);
}

TEST(DouglasPeuckerTest, ZigZagCollapsesWithLooseEpsilon) {
	std::vector<Vector2> zig;
	for (int i = 0; i < 10; i++) {
		zig.push_back(Vector2(static_cast<float>(i),
				(i % 2 == 0) ? 0.0f : 0.3f));
	}
	auto loose = simplify_polyline(zig, 2.0f);
	EXPECT_EQ(2u, loose.size());
}

TEST(DouglasPeuckerTest, EmptyAndSingleInputUnchanged) {
	std::vector<Vector2> empty;
	EXPECT_TRUE(simplify_polyline(empty, 1.0f).empty());
	std::vector<Vector2> one = { Vector2(5, 5) };
	EXPECT_EQ(1u, simplify_polyline(one, 1.0f).size());
}

TEST(DouglasPeuckerTest, LineSoupSimplifiesChainedSegments) {
	// Four connected segments forming a single straight line.
	std::vector<Vector2> soup = {
		Vector2(0, 0), Vector2(1, 0),
		Vector2(1, 0), Vector2(2, 0),
		Vector2(2, 0), Vector2(3, 0),
		Vector2(3, 0), Vector2(4, 0),
	};
	auto out = simplify_line_soup(soup, 0.1f, 0.01f);
	// Should simplify to one segment (two points).
	EXPECT_EQ(2u, out.size());
}

} // namespace terrain
} // namespace godot

#endif // KBTERRAIN_TESTS_ENABLED

#endif // KBTERRAIN_TERRAIN_TEST_DOUGLAS_PEUCKER_H
