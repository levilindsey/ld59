#include "douglas_peucker.h"

#include <algorithm>
#include <cmath>
#include <unordered_map>

namespace godot {
namespace terrain {

namespace {

// Perpendicular distance (squared) from point `p` to the infinite
// line through `a` and `b`.
float perpendicular_distance_sq(Vector2 p, Vector2 a, Vector2 b) {
	const float dx = b.x - a.x;
	const float dy = b.y - a.y;
	const float line_len_sq = dx * dx + dy * dy;
	if (line_len_sq <= 0.0f) {
		const float ddx = p.x - a.x;
		const float ddy = p.y - a.y;
		return ddx * ddx + ddy * ddy;
	}
	const float t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / line_len_sq;
	const float px = a.x + t * dx;
	const float py = a.y + t * dy;
	const float ex = p.x - px;
	const float ey = p.y - py;
	return ex * ex + ey * ey;
}

// Iterative RDP.
void rdp(const std::vector<Vector2> &points, int lo, int hi,
		float epsilon_sq, std::vector<bool> &keep) {
	if (hi <= lo + 1) {
		return;
	}
	float max_d2 = 0.0f;
	int max_i = lo;
	for (int i = lo + 1; i < hi; i++) {
		const float d2 = perpendicular_distance_sq(
				points[i], points[lo], points[hi]);
		if (d2 > max_d2) {
			max_d2 = d2;
			max_i = i;
		}
	}
	if (max_d2 > epsilon_sq) {
		keep[max_i] = true;
		rdp(points, lo, max_i, epsilon_sq, keep);
		rdp(points, max_i, hi, epsilon_sq, keep);
	}
}

} // namespace

std::vector<Vector2> simplify_polyline(
		const std::vector<Vector2> &points, float epsilon_px) {
	if (points.size() < 3) {
		return points;
	}
	const float epsilon_sq = epsilon_px * epsilon_px;
	std::vector<bool> keep(points.size(), false);
	keep.front() = true;
	keep.back() = true;
	rdp(points, 0, static_cast<int>(points.size()) - 1, epsilon_sq, keep);
	std::vector<Vector2> out;
	out.reserve(points.size());
	for (size_t i = 0; i < points.size(); i++) {
		if (keep[i]) {
			out.push_back(points[i]);
		}
	}
	return out;
}

// Hash / equality for welded point keys (integer-quantized).
struct PointKey {
	int32_t x;
	int32_t y;
	bool operator==(const PointKey &o) const {
		return x == o.x && y == o.y;
	}
};

struct PointKeyHasher {
	size_t operator()(const PointKey &k) const {
		const uint64_t a = static_cast<uint32_t>(k.x);
		const uint64_t b = static_cast<uint32_t>(k.y);
		return static_cast<size_t>(a * 0x9E3779B97F4A7C15ULL + b);
	}
};

std::vector<Vector2> simplify_line_soup(
		const std::vector<Vector2> &segments,
		float epsilon_px,
		float weld_epsilon_sq_px) {
	if (segments.size() < 4) {
		return segments;
	}

	// Quantize points to integer keys so segment endpoints that are
	// "the same" line up.
	const float quantum = std::sqrt(weld_epsilon_sq_px);
	const float inv = (quantum > 0.0f) ? (1.0f / quantum) : 1.0f;
	auto key_of = [inv](Vector2 p) -> PointKey {
		return PointKey{
			static_cast<int32_t>(std::floor(p.x * inv + 0.5f)),
			static_cast<int32_t>(std::floor(p.y * inv + 0.5f))
		};
	};

	const size_t seg_count = segments.size() / 2;

	// Adjacency: map from point-key to list of segment indices.
	std::unordered_map<PointKey, std::vector<size_t>, PointKeyHasher>
			adj;
	adj.reserve(seg_count * 2);
	for (size_t s = 0; s < seg_count; s++) {
		adj[key_of(segments[s * 2 + 0])].push_back(s);
		adj[key_of(segments[s * 2 + 1])].push_back(s);
	}

	std::vector<bool> consumed(seg_count, false);
	std::vector<Vector2> out;
	out.reserve(segments.size());

	// Walk chains: greedily chain segments from an endpoint until
	// the chain closes or runs out.
	for (size_t start = 0; start < seg_count; start++) {
		if (consumed[start]) {
			continue;
		}
		consumed[start] = true;

		std::vector<Vector2> polyline;
		polyline.push_back(segments[start * 2 + 0]);
		polyline.push_back(segments[start * 2 + 1]);

		// Forward walk from end.
		while (true) {
			Vector2 end = polyline.back();
			const PointKey k = key_of(end);
			auto it = adj.find(k);
			if (it == adj.end()) {
				break;
			}
			bool extended = false;
			for (size_t next_s : it->second) {
				if (consumed[next_s]) {
					continue;
				}
				Vector2 a = segments[next_s * 2 + 0];
				Vector2 b = segments[next_s * 2 + 1];
				if (key_of(a) == k) {
					polyline.push_back(b);
				} else if (key_of(b) == k) {
					polyline.push_back(a);
				} else {
					continue;
				}
				consumed[next_s] = true;
				extended = true;
				break;
			}
			if (!extended) {
				break;
			}
		}

		// Backward walk from start (reverse the polyline, continue).
		std::reverse(polyline.begin(), polyline.end());
		while (true) {
			Vector2 end = polyline.back();
			const PointKey k = key_of(end);
			auto it = adj.find(k);
			if (it == adj.end()) {
				break;
			}
			bool extended = false;
			for (size_t next_s : it->second) {
				if (consumed[next_s]) {
					continue;
				}
				Vector2 a = segments[next_s * 2 + 0];
				Vector2 b = segments[next_s * 2 + 1];
				if (key_of(a) == k) {
					polyline.push_back(b);
				} else if (key_of(b) == k) {
					polyline.push_back(a);
				} else {
					continue;
				}
				consumed[next_s] = true;
				extended = true;
				break;
			}
			if (!extended) {
				break;
			}
		}

		auto simplified = simplify_polyline(polyline, epsilon_px);
		for (size_t i = 0; i + 1 < simplified.size(); i++) {
			out.push_back(simplified[i]);
			out.push_back(simplified[i + 1]);
		}
	}

	return out;
}

} // namespace terrain
} // namespace godot
