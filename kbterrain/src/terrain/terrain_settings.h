#ifndef KBTERRAIN_TERRAIN_TERRAIN_SETTINGS_H
#define KBTERRAIN_TERRAIN_TERRAIN_SETTINGS_H

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/color.hpp>

namespace godot {

class TerrainSettings : public Resource {
	GDCLASS(TerrainSettings, Resource)

public:
	// Frequency enum values (must match src/core/frequency.gd).
	// Local enum to avoid cross-script references. These are C++
	// constants for Phase 2 bookkeeping; the GDScript side uses the
	// same integer values.
	enum Type {
		TYPE_NONE = 0,
		TYPE_INDESTRUCTIBLE = 1,
		TYPE_RED = 2,
		TYPE_GREEN = 3,
		TYPE_BLUE = 4,
		TYPE_LIQUID = 5,
		TYPE_SAND = 6,
		TYPE_YELLOW = 7,
	};

	TerrainSettings();

	// Grid configuration.
	int chunk_cells = 32;
	float cell_size_px = 8.0f;
	// iso threshold in [0, 255]; cells with density >= iso are solid.
	// Default 255: with binary 0/255 densities from the bake, the
	// iso line passes exactly through the inside-corner positions,
	// so the visual mesh + collision polygon align with the authored
	// tile boundaries (no half-cell extension on the perimeter).
	int iso = 255;

	// Collision tuning.
	int collision_layer = 1; // physics layer 1 = normal_surfaces.
	int collision_mask = 0;
	float simplify_epsilon_px = 0.75f;

	// Per-type render color (used as vertex color when rendering
	// meshes, and picked up by the composite shader's palette match).
	// Keep in sync with src/core/frequency.gd PALETTE.
	Color color_indestructible = Color(0.12f, 0.12f, 0.14f, 1.0f);
	Color color_red = Color(0.95f, 0.38f, 0.48f, 1.0f);
	Color color_green = Color(0.28f, 0.82f, 0.65f, 1.0f);
	Color color_blue = Color(0.45f, 0.80f, 0.98f, 1.0f);
	Color color_yellow = Color(0.98f, 0.70f, 0.25f, 1.0f);
	Color color_liquid = Color(0.16f, 0.36f, 0.68f, 1.0f);
	Color color_sand = Color(0.80f, 0.74f, 0.52f, 1.0f);

	// Getters / setters.
	int get_chunk_cells() const { return chunk_cells; }
	void set_chunk_cells(int v) { chunk_cells = v; }

	float get_cell_size_px() const { return cell_size_px; }
	void set_cell_size_px(float v) { cell_size_px = v; }

	int get_iso() const { return iso; }
	void set_iso(int v) { iso = v; }

	int get_collision_layer() const { return collision_layer; }
	void set_collision_layer(int v) { collision_layer = v; }

	int get_collision_mask() const { return collision_mask; }
	void set_collision_mask(int v) { collision_mask = v; }

	float get_simplify_epsilon_px() const { return simplify_epsilon_px; }
	void set_simplify_epsilon_px(float v) { simplify_epsilon_px = v; }

	Color get_color_indestructible() const { return color_indestructible; }
	void set_color_indestructible(Color v) { color_indestructible = v; }
	Color get_color_red() const { return color_red; }
	void set_color_red(Color v) { color_red = v; }
	Color get_color_green() const { return color_green; }
	void set_color_green(Color v) { color_green = v; }
	Color get_color_blue() const { return color_blue; }
	void set_color_blue(Color v) { color_blue = v; }
	Color get_color_yellow() const { return color_yellow; }
	void set_color_yellow(Color v) { color_yellow = v; }
	Color get_color_liquid() const { return color_liquid; }
	void set_color_liquid(Color v) { color_liquid = v; }
	Color get_color_sand() const { return color_sand; }
	void set_color_sand(Color v) { color_sand = v; }

	// Look up the render color for a Type enum value.
	Color color_for_type(int type) const;

protected:
	static void _bind_methods();
};

} // namespace godot

VARIANT_ENUM_CAST(godot::TerrainSettings::Type);

#endif // KBTERRAIN_TERRAIN_TERRAIN_SETTINGS_H
