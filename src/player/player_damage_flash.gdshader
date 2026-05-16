shader_type canvas_item;
// Combines a simple 4-neighbor silhouette outline (same approach
// as `assets/shaders/sprite_outline.gdshader`) with the damage-hit
// body flash and the expanding damage pulse ring.
//
// - Sprite body (`tex_color.a > 0.5`) is tinted toward `flash_color`
//   by `flash_strength`.
// - Transparent padding within the quad is painted with
//   `outline_color` when any of its 4 cardinal neighbors (at
//   `outline_width_px` atlas pixels) is opaque.
// - During a damage pulse, an outward-expanding ring is drawn along
//   the silhouette between `pulse_radius_px - pulse_width_px/2` and
//   `pulse_radius_px + pulse_width_px/2`.
//
// `textureSize(TEXTURE, 0)` is used directly (rather than
// `TEXTURE_PIXEL_SIZE`) because Godot's AtlasTexture path makes
// `TEXTURE_PIXEL_SIZE` return the REGION size, which scales
// horizontal offsets wrong on horizontal-strip atlases.

uniform vec4 flash_color : source_color = vec4(1.0, 0.2, 0.2, 1.0);
uniform float flash_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 pulse_color : source_color = vec4(1.0, 0.35, 0.35, 1.0);
uniform float pulse_radius_px : hint_range(0.0, 32.0) = 0.0;
uniform float pulse_width_px : hint_range(0.5, 8.0) = 2.0;
uniform float pulse_alpha : hint_range(0.0, 1.0) = 0.0;
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_width_px : hint_range(0.0, 16.0) = 0.0;
// Fades the sprite body (opaque pixels of the atlas) without
// affecting the outline or pulse overlays. Used on player death
// to hide the corpse while still letting the death pulse animate
// outward from the silhouette.
uniform float body_alpha : hint_range(0.0, 1.0) = 1.0;


// 4-neighbor opaque test at `r_px` atlas pixels from `uv`. Used by
// the silhouette outline, where a 1-pixel cardinal-only ring is
// visually fine.
float any_neighbor_opaque(
		sampler2D tex, vec2 uv, float r_px, vec2 pixel_size) {
	vec2 off = pixel_size * r_px;
	float a = 0.0;
	a = max(a, texture(tex, uv + vec2(off.x, 0.0)).a);
	a = max(a, texture(tex, uv + vec2(-off.x, 0.0)).a);
	a = max(a, texture(tex, uv + vec2(0.0, off.y)).a);
	a = max(a, texture(tex, uv + vec2(0.0, -off.y)).a);
	return a;
}


// 16-direction opaque test at `r_px` atlas pixels from `uv`. Used
// by the damage pulse ring so it expands smoothly around thin
// protrusions too. 8 directions (45° spacing) miss 1-pixel horns
// that stick out at non-45° angles; bumping to 16 directions
// (22.5° spacing) closes those gaps — max perpendicular miss
// shrinks from `r * sin(22.5°) ≈ 0.38r` to `r * sin(11.25°) ≈ 0.2r`.
const vec2 _PULSE_DIRS[16] = vec2[16](
		vec2( 1.00000,  0.00000),
		vec2( 0.92388,  0.38268),
		vec2( 0.70711,  0.70711),
		vec2( 0.38268,  0.92388),
		vec2( 0.00000,  1.00000),
		vec2(-0.38268,  0.92388),
		vec2(-0.70711,  0.70711),
		vec2(-0.92388,  0.38268),
		vec2(-1.00000,  0.00000),
		vec2(-0.92388, -0.38268),
		vec2(-0.70711, -0.70711),
		vec2(-0.38268, -0.92388),
		vec2( 0.00000, -1.00000),
		vec2( 0.38268, -0.92388),
		vec2( 0.70711, -0.70711),
		vec2( 0.92388, -0.38268)
);


float any_neighbor_opaque_16(
		sampler2D tex, vec2 uv, float r_px, vec2 pixel_size) {
	float a = 0.0;
	for (int d = 0; d < 16; d++) {
		vec2 off = pixel_size * r_px * _PULSE_DIRS[d];
		a = max(a, texture(tex, uv + off).a);
	}
	return a;
}


void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	vec2 pixel_size = 1.0 / vec2(textureSize(TEXTURE, 0));

	if (tex_color.a > 0.5) {
		// Sprite body — tint toward flash_color, then fade by
		// `body_alpha` (1 = normal, 0 = invisible).
		vec3 tinted = mix(
				tex_color.rgb, flash_color.rgb, flash_strength);
		COLOR = vec4(tinted, tex_color.a * body_alpha);
	} else {
		vec4 base = vec4(0.0);
		if (outline_width_px > 0.0) {
			float neighbor = any_neighbor_opaque(
					TEXTURE, UV, outline_width_px, pixel_size);
			if (neighbor > 0.5) {
				base = outline_color;
			}
		}
		if (pulse_alpha > 0.001 && pulse_radius_px > 0.0) {
			float half_w = pulse_width_px * 0.5;
			// 16-direction sampling so the ring stays continuous
			// around thin diagonal protrusions (horns, antennae,
			// etc.) that would fall into 45° gaps with 8-direction
			// sampling.
			float outer = any_neighbor_opaque_16(
					TEXTURE, UV,
					pulse_radius_px + half_w, pixel_size);
			float inner = any_neighbor_opaque_16(
					TEXTURE, UV,
					max(pulse_radius_px - half_w, 0.0), pixel_size);
			float ring = smoothstep(0.2, 0.8, outer)
					* (1.0 - smoothstep(0.2, 0.8, inner));
			float ring_opacity = ring * pulse_alpha;
			base.rgb = mix(base.rgb, pulse_color.rgb, ring_opacity);
			base.a = max(base.a, ring_opacity);
		}
		COLOR = base;
	}
}
