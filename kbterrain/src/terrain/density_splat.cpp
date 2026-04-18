#include "density_splat.h"

#include <algorithm>
#include <cmath>

namespace godot {
namespace terrain {

namespace {

// Returns 0..1 attenuation: 1 inside radius, ramps down across
// [radius, radius + feather] to 0 outside.
inline float splat_falloff(float distance_px, float radius_px,
		float feather_px) {
	if (distance_px <= radius_px) {
		return 1.0f;
	}
	if (distance_px >= radius_px + feather_px || feather_px <= 0.0f) {
		return 0.0f;
	}
	const float t = (distance_px - radius_px) / feather_px;
	// Smoothstep from 1 at t=0 down to 0 at t=1.
	return 1.0f - (t * t * (3.0f - 2.0f * t));
}

} // namespace

void cells_affected_by_circle(
		int cells_plus_one,
		Vector2 origin_px,
		float cell_size_px,
		Vector2 center_px,
		float radius_px,
		float feather_px,
		int &out_min_x, int &out_min_y,
		int &out_max_x, int &out_max_y) {
	const float r = radius_px + feather_px;
	const float min_x_world = center_px.x - r - origin_px.x;
	const float min_y_world = center_px.y - r - origin_px.y;
	const float max_x_world = center_px.x + r - origin_px.x;
	const float max_y_world = center_px.y + r - origin_px.y;

	const int last = cells_plus_one - 1;
	out_min_x = std::max(0,
			static_cast<int>(std::floor(min_x_world / cell_size_px)));
	out_min_y = std::max(0,
			static_cast<int>(std::floor(min_y_world / cell_size_px)));
	out_max_x = std::min(last,
			static_cast<int>(std::ceil(max_x_world / cell_size_px)));
	out_max_y = std::min(last,
			static_cast<int>(std::ceil(max_y_world / cell_size_px)));
}

static bool apply_circle(
		uint8_t *density,
		int cells_plus_one,
		Vector2 origin_px,
		float cell_size_px,
		Vector2 center_px,
		float radius_px,
		float strength_0_to_1,
		float feather_px,
		int sign) {
	int min_x, min_y, max_x, max_y;
	cells_affected_by_circle(
			cells_plus_one, origin_px, cell_size_px, center_px,
			radius_px, feather_px, min_x, min_y, max_x, max_y);
	if (min_x > max_x || min_y > max_y) {
		return false;
	}

	const float max_attenuation = 255.0f * strength_0_to_1;
	bool changed = false;

	for (int y = min_y; y <= max_y; y++) {
		for (int x = min_x; x <= max_x; x++) {
			const Vector2 sample_pos = Vector2(
					origin_px.x + x * cell_size_px,
					origin_px.y + y * cell_size_px);
			const float dx = sample_pos.x - center_px.x;
			const float dy = sample_pos.y - center_px.y;
			const float dist = std::sqrt(dx * dx + dy * dy);
			const float falloff = splat_falloff(
					dist, radius_px, feather_px);
			if (falloff <= 0.0f) {
				continue;
			}
			const float amount = falloff * max_attenuation;
			const int i = y * cells_plus_one + x;
			int current = density[i];
			int delta = static_cast<int>(sign > 0
					? +std::round(amount)
					: -std::round(amount));
			int new_value = current + delta;
			if (new_value < 0) {
				new_value = 0;
			} else if (new_value > 255) {
				new_value = 255;
			}
			if (new_value != current) {
				density[i] = static_cast<uint8_t>(new_value);
				changed = true;
			}
		}
	}
	return changed;
}

bool carve_circle(
		uint8_t *density,
		int cells_plus_one,
		Vector2 origin_px,
		float cell_size_px,
		Vector2 center_px,
		float radius_px,
		float strength_0_to_1,
		float feather_px) {
	return apply_circle(density, cells_plus_one, origin_px, cell_size_px,
			center_px, radius_px, strength_0_to_1, feather_px, -1);
}

bool fill_circle(
		uint8_t *density,
		int cells_plus_one,
		Vector2 origin_px,
		float cell_size_px,
		Vector2 center_px,
		float radius_px,
		float strength_0_to_1,
		float feather_px) {
	return apply_circle(density, cells_plus_one, origin_px, cell_size_px,
			center_px, radius_px, strength_0_to_1, feather_px, +1);
}

} // namespace terrain
} // namespace godot
