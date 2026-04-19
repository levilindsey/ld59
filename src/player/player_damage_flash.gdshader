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

// Static silhouette outline, used by enemies to advertise their
// frequency. Width 0 disables it so materials that don't opt in
// (player, bugs) stay visually unchanged.
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_width_px : hint_range(0.0, 8.0) = 0.0;


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
	// `COLOR` at fragment entry carries the CanvasItem modulate
	// chain (vertex stage default: COLOR = MODULATE). Bugs tint
	// their white spritesheet to frequency color via `modulate`;
	// preserve it here so the body renders in its frequency color.
	vec4 modulate_rgba = COLOR;

	if (tex_color.a > 0.5) {
		// Sprite body — tint toward flash_color. Preserve sprite
		// alpha so the edges stay anti-aliased with the scene.
		vec3 tinted = mix(
				tex_color.rgb, flash_color.rgb, flash_strength);
		COLOR = vec4(
				tinted * modulate_rgba.rgb,
				tex_color.a * modulate_rgba.a);
	} else {
		// Outside the sprite — optionally draw the frequency outline
		// and overlay the pulse ring. The ring's color is authored
		// by the game (damage red, eaten-pulse frequency color) and
		// should NOT be multiplied by modulate RGB — doing so would
		// double-tint a bug's eaten pulse. Apply modulate alpha only
		// so the outline and ring fade in lockstep with the sprite.
		vec2 tex_size = vec2(textureSize(TEXTURE, 0));
		vec4 base = tex_color;
		if (outline_width_px > 0.0) {
			float neighbor = alpha_within(
					TEXTURE, UV, outline_width_px, tex_size);
			if (neighbor > 0.5) {
				base = outline_color;
			}
		}
		if (pulse_alpha > 0.001 && pulse_radius_px > 0.0) {
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
			float ring_opacity = ring * pulse_alpha;
			base.rgb = mix(base.rgb, pulse_color.rgb, ring_opacity);
			base.a = base.a + (1.0 - base.a) * ring_opacity;
		}
		COLOR = vec4(base.rgb, base.a * modulate_rgba.a);
	}
}
