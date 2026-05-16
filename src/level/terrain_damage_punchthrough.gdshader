shader_type canvas_item;
render_mode blend_mix, unshaded;
// Punch-through overlay applied directly to the terrain chunk
// canvas_items rendered by the `kbterrain` C++ GDExtension. The
// terrain is drawn as per-cell palette-colored triangles; this
// shader reads the same health + damage-tier atlas that the
// echolocation composite uses, and multiplies the output alpha
// down to zero where cracks are authored so the parallax
// background shows through.
//
// Applying here (not in the composite) is the only way to get
// true transparency: the composite runs on top of this rendering,
// so any alpha it tries to produce still sees the opaque terrain
// polygons underneath. Dropping alpha in the terrain's own pass
// lets `hint_screen_texture` readers (and any layer below) see
// the parallax instead.


uniform sampler2D health_tex : filter_nearest, repeat_disable;
uniform sampler2D damage_tier_atlas : repeat_disable, filter_nearest;

// World-px offset corresponding to health_tex's (0, 0) texel and
// the width/height of the health texture in cells. Both match the
// composite's density uniforms — populated from the same
// TerrainWorld data on the GDScript side.
uniform vec2 density_world_origin_px = vec2(0.0, 0.0);
uniform float density_cell_size_px = 8.0;
uniform vec2 density_world_cell_size = vec2(128.0, 128.0);

uniform int damage_tier_count = 5;
// Health value (0..1) a pristine cell sits at. Raw health is
// stored as an R8 byte (128/255 ≈ 0.502 by default), so a
// pristine reading should map to damage_frac = 0.
uniform float health_max_norm : hint_range(0.01, 1.0) = 0.502;
// Distance between crack-atlas repetitions, in world pixels.
// Matches the composite shader's `interior_scale_px` so cracks
// line up with the echo-reveal rendering above.
uniform float interior_scale_px : hint_range(4.0, 128.0) = 32.0;
// 0 = no punch-through (terrain stays fully opaque through
// cracks), 1 = cracks become fully transparent.
uniform float crack_alpha_strength : hint_range(0.0, 1.0) = 1.0;


varying vec2 v_world_px;


void vertex() {
	// The C++ marching-squares worker emits vertices directly in
	// world pixels (chunk origin + cell offset), and the chunk
	// canvas_items have identity transforms, so VERTEX itself is
	// already in world-px coords for sampling world-positioned
	// textures. Pass it through to the fragment unchanged.
	v_world_px = VERTEX;
}


vec2 world_to_cell_center_uv(vec2 world_px) {
	vec2 cell = (world_px - density_world_origin_px)
			/ density_cell_size_px;
	return (floor(cell) + vec2(0.5)) / density_world_cell_size;
}


void fragment() {
	if (crack_alpha_strength > 0.0 && damage_tier_count > 1) {
		float health_norm = texture(
				health_tex,
				world_to_cell_center_uv(v_world_px)).r;
		float damage_frac = clamp(
				(health_max_norm - health_norm)
						/ max(health_max_norm, 0.001),
				0.0,
				1.0);
		if (damage_frac > 0.01) {
			float tier_f = damage_frac
					* float(damage_tier_count);
			int tier = clamp(
					int(tier_f),
					0,
					damage_tier_count - 1);
			float tier_u_base = float(tier)
					/ float(damage_tier_count);
			float tier_u_width = 1.0
					/ float(damage_tier_count);
			float interior_u_frac = fract(
					v_world_px.x / interior_scale_px);
			float interior_v = fract(
					v_world_px.y / interior_scale_px);
			vec2 crack_uv = vec2(
					tier_u_base + interior_u_frac * tier_u_width,
					interior_v);
			float crack = texture(
					damage_tier_atlas, crack_uv).r;
			float crack_mask = smoothstep(0.2, 0.5, crack);
			COLOR.a *= 1.0 - crack_mask * crack_alpha_strength;
		}
	}
}
