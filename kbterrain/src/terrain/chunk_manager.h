#ifndef KBTERRAIN_TERRAIN_CHUNK_MANAGER_H
#define KBTERRAIN_TERRAIN_CHUNK_MANAGER_H

#include "chunk.h"

#include <godot_cpp/variant/vector2i.hpp>

#include <memory>
#include <unordered_map>
#include <vector>

namespace godot {
namespace terrain {

struct Vector2iHasher {
	size_t operator()(const Vector2i &v) const noexcept {
		const uint64_t a = static_cast<uint32_t>(v.x);
		const uint64_t b = static_cast<uint32_t>(v.y);
		return static_cast<size_t>(a * 0x9E3779B97F4A7C15ULL + b);
	}
};

class ChunkManager {
public:
	ChunkManager() = default;

	// Get or create a chunk at the given coordinates. Ownership
	// stays with the manager; returned pointer is valid until
	// `remove()` is called or the manager destructs.
	Chunk *get_or_create(Vector2i coords, int cells);

	// Returns nullptr if no chunk exists at the coord.
	Chunk *get(Vector2i coords);

	// Remove a chunk from the map. Caller is responsible for freeing
	// RIDs before calling this.
	void remove(Vector2i coords);

	// Returns coords of chunks whose density buffer overlaps the
	// AABB of a splat of radius+feather `reach_px` at `center_px`.
	std::vector<Vector2i> chunks_affected_by_splat(
			Vector2 center_px, float reach_px, int cells,
			float cell_size_px) const;

	// Iteration helpers.
	size_t size() const { return _chunks.size(); }
	const std::unordered_map<Vector2i, std::unique_ptr<Chunk>, Vector2iHasher> &
	all() const { return _chunks; }
	std::unordered_map<Vector2i, std::unique_ptr<Chunk>, Vector2iHasher> &
	all_mut() { return _chunks; }

	// Convert world position to chunk coords for the given chunk size.
	static Vector2i world_to_chunk(Vector2 pos_px, int cells,
			float cell_size_px);

private:
	std::unordered_map<Vector2i, std::unique_ptr<Chunk>, Vector2iHasher>
			_chunks;
};

} // namespace terrain
} // namespace godot

#endif // KBTERRAIN_TERRAIN_CHUNK_MANAGER_H
