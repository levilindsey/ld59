shader_type canvas_item;
// Player damage-hit feedback: flashes the sprite body red, and
// renders an expanding outline "pulse ring" around the sprite's
// 1-pixel border by sampling `TEXTURE` alpha in 8 directions at
// two radii and drawing the shell where outer-radius-neighbors are
// opaque but inner-radius-neighbors are not. Tween-friendly —
// all knobs live as shader uniforms the `Player` script animates.

uniform vec4 flash_color : source_color = vec4(1.0, 0.2, 0.2, 1.0);
uniform float flash_strength : hint_range(0.0, 1.0) = 0.0;

uniform vec4 pulse_color : source_color = vec4(1.0, 0.35, 0.35, 1.0);
uniform float pulse_radius_px : hint_range(0.0, 32.0) = 0.0;
uniform float pulse_width_px : hint_range(0.5, 8.0) = 2.0;
uniform float pulse_alpha : hint_range(0.0, 1.0) = 0.0;


// Safely sample sprite alpha; returns 0 when the UV goes outside the
// drawable region so adjacent atlas frames don't leak into the ring
// detection. `tex` is passed explicitly because Godot's `TEXTURE`
// built-in is only accessible from `fragment()`.
float sample_alpha(sampler2D tex, vec2 uv) {
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		return 0.0;
	}
	return texture(tex, uv).a;
}


// Max sprite alpha among 8 compass directions at `r_px` pixels from
// `uv`. > 0.5 means "sprite is within r_px of this pixel in some
// direction". Used to bracket the pulse ring between two radii.
float alpha_within(
		sampler2D tex, vec2 uv, float r_px, vec2 tex_size) {
	vec2 off = vec2(r_px, r_px) / tex_size;
	float diag = 0.70710678;
	float a = 0.0;
	a = max(a, sample_alpha(tex, uv + vec2(off.x, 0.0)));
	a = max(a, sample_alpha(tex, uv + vec2(-off.x, 0.0)));
	a = max(a, sample_alpha(tex, uv + vec2(0.0, off.y)));
	a = max(a, sample_alpha(tex, uv + vec2(0.0, -off.y)));
	a = max(a, sample_alpha(
			tex, uv + vec2(off.x * diag, off.y * diag)));
	a = max(a, sample_alpha(
			tex, uv + vec2(-off.x * diag, off.y * diag)));
	a = max(a, sample_alpha(
			tex, uv + vec2(off.x * diag, -off.y * diag)));
	a = max(a, sample_alpha(
			tex, uv + vec2(-off.x * diag, -off.y * diag)));
	return a;
}


void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);

	if (tex_color.a > 0.5) {
		// Sprite body — tint toward flash_color. Preserve sprite
		// alpha so the edges stay anti-aliased with the scene.
		vec3 tinted = mix(
				tex_color.rgb, flash_color.rgb, flash_strength);
		COLOR = vec4(tinted, tex_color.a);
	} else {
		// Outside the sprite — render the pulse ring if active.
		vec4 base = tex_color;
		if (pulse_alpha > 0.001 && pulse_radius_px > 0.0) {
			vec2 tex_size = vec2(textureSize(TEXTURE, 0));
			float half_w = pulse_width_px * 0.5;
			float outer = alpha_within(
					TEXTURE, UV,
					pulse_radius_px + half_w, tex_size);
			float inner = alpha_within(
					TEXTURE, UV,
					max(pulse_radius_px - half_w, 0.0), tex_size);
			// On-ring = outer ≥ 0.5 AND inner < 0.5. Use the
			// continuous product so it antialiases nicely.
			float ring = smoothstep(0.2, 0.8, outer)
					* (1.0 - smoothstep(0.2, 0.8, inner));
			base = pulse_color
					* ring
					* pulse_alpha;
		}
		COLOR = base;
	}
}
