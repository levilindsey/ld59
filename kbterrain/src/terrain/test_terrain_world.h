#ifndef KBTERRAIN_TERRAIN_TEST_TERRAIN_WORLD_H
#define KBTERRAIN_TERRAIN_TEST_TERRAIN_WORLD_H

#ifdef KBTERRAIN_TESTS_ENABLED

#include "chunk_manager.h"
#include "density_splat.h"

#include <gtest/gtest.h>

namespace godot {
namespace terrain {

TEST(ChunkManagerTest, GetOrCreateReusesChunk) {
	ChunkManager m;
	Chunk *a = m.get_or_create(Vector2i(0, 0), 32);
	Chunk *b = m.get_or_create(Vector2i(0, 0), 32);
	EXPECT_EQ(a, b);
	EXPECT_EQ(1u, m.size());
}

TEST(ChunkManagerTest, WorldToChunkMaps) {
	// cell_size=8, cells=32 → chunk=256. Position (0,0) → (0,0).
	EXPECT_EQ(Vector2i(0, 0),
			ChunkManager::world_to_chunk(Vector2(0, 0), 32, 8.0f));
	EXPECT_EQ(Vector2i(1, 0),
			ChunkManager::world_to_chunk(Vector2(256, 0), 32, 8.0f));
	EXPECT_EQ(Vector2i(-1, -1),
			ChunkManager::world_to_chunk(Vector2(-1, -1), 32, 8.0f));
}

TEST(ChunkManagerTest, ChunksAffectedByLargeSplatFindsNeighbors) {
	ChunkManager m;
	auto list = m.chunks_affected_by_splat(
			Vector2(256, 256), 40.0f, 32, 8.0f);
	// A splat centered at (256,256) with reach 40 spans across the
	// chunk boundary to neighbors. Should return a 2x2 grid of chunks.
	EXPECT_EQ(4u, list.size());
}

} // namespace terrain
} // namespace godot

#endif // KBTERRAIN_TESTS_ENABLED

#endif // KBTERRAIN_TERRAIN_TEST_TERRAIN_WORLD_H
