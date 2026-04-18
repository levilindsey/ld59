shader_type canvas_item;
render_mode blend_mix, unshaded;
// Echolocation composite. Rendered as a fullscreen ColorRect in a
// CanvasLayer above the gameplay layer. Reads the gameplay
// backbuffer via hint_screen_texture and emits:
//   - a smooth "near-radius" reveal of everything around the player
//   - a dithered pointillism reveal inside active pulse fronts,
//     biased toward edges that face the player, and (once the
//     palette is populated) gated to the player's current frequency
//   - a bright "shock ring" at each pulse's traveling wave front
// Everything else is drawn solid black.
//
// Coordinate system: UV across the fullscreen ColorRect, distances
// computed in canvas pixels via screen_size_px.

const int MAX_PULSES = 8;
const int MAX_PALETTE = 16;

uniform vec2 player_uv = vec2(0.5, 0.5);
uniform vec2 screen_size_px = vec2(1152.0, 648.0);

// Backbuffer of the layer-0 content (tiles, player, bugs, enemies,
// props). Pixel art — sample nearest.
uniform sampler2D screen_tex : hint_screen_texture,
		repeat_disable, filter_nearest;

// Offset in UV to use when taking gradient taps. 2 texels = 2/screen
// is roughly correct; computed in-shader from screen_size_px.
uniform float gradient_tap_px : hint_range(0.5, 8.0) = 2.0;

// Near-field: always-on circular reveal around the player.
uniform float near_radius_px : hint_range(0.0, 512.0) = 80.0;
uniform float near_fade_px : hint_range(0.0, 128.0) = 32.0;

// Pulses. xy=center_uv, z=age_sec, w=speed_px_per_sec.
uniform vec4 pulses[MAX_PULSES];
uniform vec4 pulse_colors[MAX_PULSES];
uniform vec4 pulse_cones[MAX_PULSES];
uniform int pulse_count = 0;

// Pulse shape tuning.
uniform float edge_width_px : hint_range(1.0, 64.0) = 12.0;
uniform float fade_tau_sec : hint_range(0.05, 2.0) = 0.35;
uniform float lifetime_sec : hint_range(0.1, 4.0) = 1.2;
uniform float edge_boost : hint_range(1.0, 4.0) = 1.5;
uniform float ring_width_px : hint_range(1.0, 16.0) = 4.0;
uniform float ring_glow_strength : hint_range(0.0, 2.0) = 1.2;

// Surface-prominence tuning.
// 0 = no gradient influence, 1 = full gradient gating of pulse.
uniform float surface_prominence_strength : hint_range(0.0, 1.0)
		= 0.9;
// Minimum fraction of pulse intensity on flat interiors, so they
// aren't completely invisible.
uniform float interior_floor : hint_range(0.0, 1.0) = 0.12;

// Bayer dither for pointillism (8x8 ordered).
uniform sampler2D bayer_tex : source_color, repeat_enable,
		filter_nearest;
uniform float bayer_tile_px : hint_range(1.0, 16.0) = 4.0;

// Frequency palette. Unused when palette_count == 0; in that mode
// the shader treats every pixel as "matches." Populate in Phase 3.
uniform vec4 palette[MAX_PALETTE];
uniform int palette_freqs[MAX_PALETTE];
uniform int palette_count = 0;
// Threshold for counting a pixel as "background" (low luminance /
// transparent). In Phase 1 we use this to keep the shader from
// sparkling the backdrop clear color.
uniform float background_luma_threshold : hint_range(0.0, 1.0) = 0.02;

// Current frequency of the player (Frequency.Type enum value).
uniform int current_frequency = 0;

// Debug: bypass effects and draw a crosshair at player_uv so the
// world→screen transform can be verified at a glance.
uniform bool debug_show_anchor = false;

const float TAU_ = 6.28318530718;


// ---- pulse math (traveling wave) ------------------------------------------

float pulse_vis(vec2 px, vec4 p, vec4 cone) {
	vec2 d_vec = px - p.xy * screen_size_px;
	float d = length(d_vec);
	float t = p.z;
	float speed = p.w;
	float wave_r = speed * t;

	float age_here = t - d / max(speed, 0.001);
	float reached = step(0.0, age_here);

	float cone_mask = 1.0;
	if (cone.x < TAU_ - 0.01) {
		float half_arc = cone.x * 0.5;
		vec2 aim = vec2(cos(cone.y), sin(cone.y));
		float cos_ang = dot(
				normalize(d_vec + vec2(1e-6)), aim);
		cone_mask = step(cos(half_arc), cos_ang);
	}

	float edge = exp(-pow((d - wave_r) / edge_width_px, 2.0))
			* edge_boost;
	float trail = exp(-age_here / fade_tau_sec);
	float env = 1.0 - smoothstep(
			lifetime_sec * 0.7, lifetime_sec, t);

	return reached * cone_mask * max(edge, trail) * env;
}


float pulse_ring_glow(vec2 px, vec4 p, vec4 cone) {
	vec2 d_vec = px - p.xy * screen_size_px;
	float d = length(d_vec);
	float t = p.z;
	float speed = p.w;
	float wave_r = speed * t;

	float cone_mask = 1.0;
	if (cone.x < TAU_ - 0.01) {
		float half_arc = cone.x * 0.5;
		vec2 aim = vec2(cos(cone.y), sin(cone.y));
		float cos_ang = dot(
				normalize(d_vec + vec2(1e-6)), aim);
		cone_mask = step(cos(half_arc), cos_ang);
	}

	float env = 1.0 - smoothstep(
			lifetime_sec * 0.7, lifetime_sec, t);
	return cone_mask
			* exp(-pow((d - wave_r) / ring_width_px, 2.0)) * env;
}


// ---- palette lookup -------------------------------------------------------

// Returns the frequency id of the palette entry closest to `c`, or
// 0 if palette_count is 0 (frequency gating disabled).
int detect_frequency(vec3 c) {
	if (palette_count <= 0) {
		return 0;
	}
	int best_i = 0;
	float best_d = 1e9;
	for (int i = 0; i < MAX_PALETTE; i++) {
		if (i >= palette_count) {
			break;
		}
		float dd = distance(c, palette[i].rgb);
		if (dd < best_d) {
			best_d = dd;
			best_i = i;
		}
	}
	return palette_freqs[best_i];
}


// ---- main -----------------------------------------------------------------

void fragment() {
	vec2 px = UV * screen_size_px;
	vec2 player_px = player_uv * screen_size_px;

	if (debug_show_anchor) {
		vec2 cross_delta = px - player_px;
		vec4 dbg_color = vec4(0.0, 0.0, 0.0, 0.0);
		if (length(cross_delta) < 6.0) {
			dbg_color = vec4(1.0, 0.2, 0.2, 1.0);
		} else if (abs(cross_delta.y) < 1.5
				|| abs(cross_delta.x) < 1.5) {
			dbg_color = vec4(0.0, 1.0, 1.0, 1.0);
		}
		COLOR = dbg_color;
	} else {
		// Sample scene color at center + 4 neighbors for a gradient.
		vec2 tap_uv = vec2(gradient_tap_px, gradient_tap_px)
				/ screen_size_px;
		vec3 c0 = texture(screen_tex, SCREEN_UV).rgb;
		vec3 cL = texture(screen_tex,
				SCREEN_UV - vec2(tap_uv.x, 0.0)).rgb;
		vec3 cR = texture(screen_tex,
				SCREEN_UV + vec2(tap_uv.x, 0.0)).rgb;
		vec3 cU = texture(screen_tex,
				SCREEN_UV - vec2(0.0, tap_uv.y)).rgb;
		vec3 cD = texture(screen_tex,
				SCREEN_UV + vec2(0.0, tap_uv.y)).rgb;

		const vec3 luma = vec3(0.299, 0.587, 0.114);
		float l0 = dot(c0, luma);
		float lL = dot(cL, luma);
		float lR = dot(cR, luma);
		float lU = dot(cU, luma);
		float lD = dot(cD, luma);

		// Gradient: approximate surface-facing direction.
		vec2 grad = vec2(lR - lL, lD - lU);
		float grad_mag = length(grad);

		// "To player" direction for the facing dot product.
		vec2 to_player = player_px - px;
		float to_player_len = length(to_player);
		vec2 to_player_dir = (to_player_len > 0.001)
				? (to_player / to_player_len) : vec2(0.0, 1.0);

		// Gradient points from dark→bright; for alpha-style art on
		// a dark backdrop it points INTO the tile. Normal points
		// opposite — out of the tile. Negate to get outward normal.
		vec2 outward_normal = (grad_mag > 0.001)
				? (-normalize(grad)) : vec2(0.0);
		float facing = max(0.0, dot(outward_normal, to_player_dir));

		// Surface prominence combines "how edgy" with "how facing".
		// Clamp gradient contribution so fully flat interiors keep
		// a small floor.
		float edge_strength = clamp(grad_mag * 6.0, 0.0, 1.0);
		float prominence_raw = edge_strength * facing;
		float prominence = mix(
				1.0,
				mix(interior_floor, 1.0, prominence_raw),
				surface_prominence_strength);

		// Don't light up the backdrop clear color. If this pixel is
		// darker than background_luma_threshold and there's no
		// nearby gradient, the pulse contribution is killed.
		float has_content = step(
				background_luma_threshold, l0 + grad_mag * 4.0);

		// Frequency gating via palette (skipped when empty).
		float frequency_match = 1.0;
		if (palette_count > 0) {
			int detected = detect_frequency(c0);
			frequency_match = (detected == current_frequency)
					? 1.0 : 0.0;
		}

		// Near-field reveals EVERYTHING smoothly (background + tiles
		// + player) with no dither, no frequency gating, no surface
		// bias. This is the "you always see around you" light.
		float near_vis = 1.0 - smoothstep(
				near_radius_px,
				near_radius_px + near_fade_px,
				to_player_len);

		// Pulse contribution — dithered, surface-biased, frequency-
		// gated.
		float raw_pulse_vis = 0.0;
		vec3 ring_rgb = vec3(0.0);
		float ring_alpha = 0.0;
		for (int i = 0; i < MAX_PULSES; i++) {
			if (i >= pulse_count) {
				break;
			}
			float v = pulse_vis(px, pulses[i], pulse_cones[i]);
			raw_pulse_vis = max(raw_pulse_vis, v);
			float r = pulse_ring_glow(
					px, pulses[i], pulse_cones[i])
					* ring_glow_strength;
			ring_rgb += pulse_colors[i].rgb * r;
			ring_alpha = max(ring_alpha, r);
		}

		float pulse_reveal = raw_pulse_vis
				* prominence
				* frequency_match
				* has_content;

		// Dither the pulse reveal so it reads as stippling.
		float bayer = texture(
				bayer_tex, px / bayer_tile_px / 8.0).r;
		float dithered_pulse_reveal = step(
				1.0 - pulse_reveal, bayer);

		// Combined reveal (smooth near-field OR dithered pulse).
		float reveal = clamp(
				max(near_vis, dithered_pulse_reveal), 0.0, 1.0);

		// The scene pixel under this fragment.
		vec3 scene_rgb = c0;

		// Revealed: show the scene plus any ring glow. Unrevealed:
		// solid black. Ring glow leaks slightly into dark areas so
		// the wave front is always readable.
		vec3 out_rgb = mix(
				ring_rgb,
				scene_rgb + ring_rgb,
				reveal);
		float out_alpha = 1.0; // fully opaque overlay

		// Small dark floor so the ring never punches fully to
		// base color on perfect black.
		out_rgb = max(out_rgb, vec3(0.0));

		COLOR = vec4(out_rgb, out_alpha);
	}
}
