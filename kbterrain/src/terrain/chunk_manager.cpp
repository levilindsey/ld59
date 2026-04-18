#include "chunk_manager.h"

#include <cmath>

namespace godot {
namespace terrain {

Chunk *ChunkManager::get_or_create(Vector2i coords, int cells) {
	auto it = _chunks.find(coords);
	if (it != _chunks.end()) {
		return it->second.get();
	}
	auto ptr = std::make_unique<Chunk>(coords, cells);
	Chunk *raw = ptr.get();
	_chunks.emplace(coords, std::move(ptr));
	return raw;
}

Chunk *ChunkManager::get(Vector2i coords) {
	auto it = _chunks.find(coords);
	return (it == _chunks.end()) ? nullptr : it->second.get();
}

void ChunkManager::remove(Vector2i coords) {
	_chunks.erase(coords);
}

Vector2i ChunkManager::world_to_chunk(Vector2 pos_px, int cells,
		float cell_size_px) {
	const float chunk_size_px = cells * cell_size_px;
	const int cx = static_cast<int>(
			std::floor(pos_px.x / chunk_size_px));
	const int cy = static_cast<int>(
			std::floor(pos_px.y / chunk_size_px));
	return Vector2i(cx, cy);
}

std::vector<Vector2i> ChunkManager::chunks_affected_by_splat(
		Vector2 center_px, float reach_px, int cells,
		float cell_size_px) const {
	const float chunk_size_px = cells * cell_size_px;
	const int min_cx = static_cast<int>(std::floor(
			(center_px.x - reach_px) / chunk_size_px));
	const int max_cx = static_cast<int>(std::floor(
			(center_px.x + reach_px) / chunk_size_px));
	const int min_cy = static_cast<int>(std::floor(
			(center_px.y - reach_px) / chunk_size_px));
	const int max_cy = static_cast<int>(std::floor(
			(center_px.y + reach_px) / chunk_size_px));

	std::vector<Vector2i> out;
	for (int cy = min_cy; cy <= max_cy; cy++) {
		for (int cx = min_cx; cx <= max_cx; cx++) {
			out.push_back(Vector2i(cx, cy));
		}
	}
	return out;
}

} // namespace terrain
} // namespace godot
