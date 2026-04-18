#include "terrain_settings.h"

#include <godot_cpp/core/class_db.hpp>

namespace godot {

TerrainSettings::TerrainSettings() {}

Color TerrainSettings::color_for_type(int type) const {
	switch (type) {
		case TYPE_INDESTRUCTIBLE:
			return color_indestructible;
		case TYPE_RED:
			return color_red;
		case TYPE_GREEN:
			return color_green;
		case TYPE_BLUE:
			return color_blue;
		case TYPE_YELLOW:
			return color_yellow;
		case TYPE_LIQUID:
			return color_liquid;
		case TYPE_SAND:
			return color_sand;
		case TYPE_WEB_RED:
			return color_web_red;
		case TYPE_WEB_GREEN:
			return color_web_green;
		case TYPE_WEB_BLUE:
			return color_web_blue;
		case TYPE_WEB_YELLOW:
			return color_web_yellow;
		default:
			return Color(0, 0, 0, 0);
	}
}

void TerrainSettings::_bind_methods() {
	BIND_ENUM_CONSTANT(TYPE_NONE);
	BIND_ENUM_CONSTANT(TYPE_INDESTRUCTIBLE);
	BIND_ENUM_CONSTANT(TYPE_RED);
	BIND_ENUM_CONSTANT(TYPE_GREEN);
	BIND_ENUM_CONSTANT(TYPE_BLUE);
	BIND_ENUM_CONSTANT(TYPE_LIQUID);
	BIND_ENUM_CONSTANT(TYPE_SAND);
	BIND_ENUM_CONSTANT(TYPE_YELLOW);
	BIND_ENUM_CONSTANT(TYPE_WEB_RED);
	BIND_ENUM_CONSTANT(TYPE_WEB_GREEN);
	BIND_ENUM_CONSTANT(TYPE_WEB_BLUE);
	BIND_ENUM_CONSTANT(TYPE_WEB_YELLOW);

	ClassDB::bind_method(D_METHOD("get_chunk_cells"),
			&TerrainSettings::get_chunk_cells);
	ClassDB::bind_method(D_METHOD("set_chunk_cells", "v"),
			&TerrainSettings::set_chunk_cells);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "chunk_cells"),
			"set_chunk_cells", "get_chunk_cells");

	ClassDB::bind_method(D_METHOD("get_cell_size_px"),
			&TerrainSettings::get_cell_size_px);
	ClassDB::bind_method(D_METHOD("set_cell_size_px", "v"),
			&TerrainSettings::set_cell_size_px);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cell_size_px"),
			"set_cell_size_px", "get_cell_size_px");

	ClassDB::bind_method(D_METHOD("get_iso"), &TerrainSettings::get_iso);
	ClassDB::bind_method(D_METHOD("set_iso", "v"),
			&TerrainSettings::set_iso);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "iso"),
			"set_iso", "get_iso");

	ClassDB::bind_method(D_METHOD("get_collision_layer"),
			&TerrainSettings::get_collision_layer);
	ClassDB::bind_method(D_METHOD("set_collision_layer", "v"),
			&TerrainSettings::set_collision_layer);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "collision_layer",
						 PROPERTY_HINT_LAYERS_2D_PHYSICS),
			"set_collision_layer", "get_collision_layer");

	ClassDB::bind_method(D_METHOD("get_collision_mask"),
			&TerrainSettings::get_collision_mask);
	ClassDB::bind_method(D_METHOD("set_collision_mask", "v"),
			&TerrainSettings::set_collision_mask);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "collision_mask",
						 PROPERTY_HINT_LAYERS_2D_PHYSICS),
			"set_collision_mask", "get_collision_mask");

	ClassDB::bind_method(D_METHOD("get_simplify_epsilon_px"),
			&TerrainSettings::get_simplify_epsilon_px);
	ClassDB::bind_method(D_METHOD("set_simplify_epsilon_px", "v"),
			&TerrainSettings::set_simplify_epsilon_px);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "simplify_epsilon_px"),
			"set_simplify_epsilon_px", "get_simplify_epsilon_px");

#define BIND_COLOR(name)                                                       \
	ClassDB::bind_method(D_METHOD("get_" #name),                               \
			&TerrainSettings::get_##name);                                     \
	ClassDB::bind_method(D_METHOD("set_" #name, "v"),                          \
			&TerrainSettings::set_##name);                                     \
	ADD_PROPERTY(PropertyInfo(Variant::COLOR, #name),                          \
			"set_" #name, "get_" #name)
	BIND_COLOR(color_indestructible);
	BIND_COLOR(color_red);
	BIND_COLOR(color_green);
	BIND_COLOR(color_blue);
	BIND_COLOR(color_yellow);
	BIND_COLOR(color_liquid);
	BIND_COLOR(color_sand);
	BIND_COLOR(color_web_red);
	BIND_COLOR(color_web_green);
	BIND_COLOR(color_web_blue);
	BIND_COLOR(color_web_yellow);
#undef BIND_COLOR

	ClassDB::bind_method(D_METHOD("color_for_type", "type"),
			&TerrainSettings::color_for_type);
}

} // namespace godot
