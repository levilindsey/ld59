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
uniform float gradient_tap_px : hint_range(0.5, 32.0) = 8.0;

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

// Stipple color override. When alpha > 0, pulse-revealed pixels are
// painted this color instead of the scene pixel underneath. Keeps
// the visual language of echolocation separate from the underlying
// tile art.
uniform vec4 stipple_color : source_color = vec4(1.0, 0.0, 1.0, 1.0);

// Facing threshold: below this, the surface is considered fully
// back-facing and no pulse stipple appears. Higher = more strict.
uniform float facing_threshold_lo : hint_range(0.0, 1.0) = 0.3;
uniform float facing_threshold_hi : hint_range(0.0, 1.0) = 0.8;

// Debug: bypass effects and draw a crosshair at player_uv so the
// world→screen transform can be verified at a glance.
uniform bool debug_show_anchor = false;

// --- Procedural tile rendering ---------------------------------------------
// Per-type textures are packed into horizontal atlases — one tile
// slot per Frequency.Type. The shader detects which type the
// underlying scene pixel represents via palette-match, then samples
// the matching slot of each atlas.
//
// Interior atlas: `atlas_slot_count` tiles wide, each `TILE_PX`
// square. World-space wrap within each slot via fract().
// Surface atlas: same width, `SURFACE_HEIGHT_PX` tall. Rotated-
// tangent UV with surface alpha acting as the "has surface" gate
// (alpha=0 slots fall back to interior only).
uniform bool procedural_tile_rendering = true;
uniform sampler2D interior_atlas : source_color, repeat_disable,
		filter_nearest;
uniform sampler2D surface_atlas : source_color, repeat_disable,
		filter_nearest;
uniform int atlas_slot_count = 8;
uniform float interior_scale_px : hint_range(4.0, 128.0) = 32.0;
uniform float surface_scale_along_px : hint_range(4.0, 128.0) = 32.0;
uniform float surface_band_px : hint_range(1.0, 32.0) = 12.0;
// Screen→world transform. Assumes DRAG_CENTER Camera2D; Y-down.
uniform vec2 world_origin = vec2(0.0, 0.0);
uniform float world_per_screen_px = 1.0;

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
		// Verification mode: just output what hint_screen_texture
		// gives us, tinted green. If the user sees a green-tinted
		// view of the game world, hint_screen_texture is working.
		// If they see black, it isn't.
		vec3 dbg_scene = texture(screen_tex, SCREEN_UV).rgb;
		COLOR = vec4(dbg_scene * vec3(0.3, 1.5, 0.3), 1.0);
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

		// Gradient: approximate surface-facing direction. Using a
		// wider tap (gradient_tap_px) finds whole-tile boundaries
		// rather than in-tile pixel-art detail.
		vec2 grad = vec2(lR - lL, lD - lU);
		float grad_mag = length(grad);
		// Amplify: a modest luminance diff should be a strong edge.
		grad_mag = clamp(grad_mag * 4.0, 0.0, 1.0);

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
		float facing_raw = dot(outward_normal, to_player_dir);
		// Sharper cutoff on back-facing / grazing surfaces so only
		// clearly-toward-player edges stipple.
		float facing = smoothstep(
				facing_threshold_lo,
				facing_threshold_hi,
				facing_raw);

		// Surface prominence combines "how edgy" with "how facing".
		// When surface_prominence_strength is 0 we pass everything;
		// at 1 we gate fully by prominence_raw (with interior_floor
		// giving a minimum).
		float prominence_raw = grad_mag * facing;
		float prominence = mix(
				1.0,
				mix(interior_floor, 1.0, prominence_raw),
				surface_prominence_strength);

		// Don't light up the backdrop clear color. Test against the
		// raw center luminance only; adding gradient padding here
		// leaks "content" into backdrop pixels next to tile edges
		// and creates stippling in the open space beyond walls.
		float has_content = step(background_luma_threshold, l0);

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

		// Base color for this pixel. When procedural rendering is on
		// and this pixel is over a tile, sample the type's slot in
		// the interior and surface atlases. The surface atlas's
		// alpha channel serves as the "has surface" gate — slots
		// without surface art (INDESTRUCTIBLE, SAND) are transparent
		// there, so the blend falls back to interior only.
		vec3 scene_rgb = c0;
		vec3 tile_rgb = c0;
		if (procedural_tile_rendering && has_content > 0.5
				&& palette_count > 0) {
			// Which type is this pixel? palette match on scene color.
			int type_id = detect_frequency(c0);
			float slot_count_f = max(float(atlas_slot_count), 1.0);
			float u_base = float(type_id) / slot_count_f;
			float u_width = 1.0 / slot_count_f;

			vec2 world_pos = world_origin
					+ UV * screen_size_px * world_per_screen_px;

			// Interior: wrap within the tile, shift into this type's
			// atlas slot.
			float interior_u_frac = fract(
					world_pos.x / interior_scale_px);
			float interior_v = fract(
					world_pos.y / interior_scale_px);
			vec2 interior_uv = vec2(
					u_base + interior_u_frac * u_width,
					interior_v);
			vec3 interior_rgb = texture(
					interior_atlas, interior_uv).rgb;

			// Surface band: rotate the UV so the texture's x axis
			// runs along the surface tangent, y goes from outside
			// (top of strip) into the tile (deeper = closer to
			// interior).
			vec2 normal = (grad_mag > 0.001)
					? (-normalize(grad)) : vec2(0.0, -1.0);
			vec2 tangent = vec2(-normal.y, normal.x);
			float along = fract(
					dot(world_pos, tangent) / surface_scale_along_px);
			float v = clamp(1.0 - grad_mag, 0.0, 1.0);
			vec2 surface_uv = vec2(
					u_base + along * u_width, v);
			vec4 surface_sample = texture(
					surface_atlas, surface_uv);

			// Blend surface over interior. band_mix fades in the
			// surface as gradient magnitude grows (closer to edge);
			// surface_sample.a gates slots without surface art.
			float band_mix = smoothstep(0.2, 0.8, grad_mag)
					* surface_sample.a;
			tile_rgb = mix(
					interior_rgb, surface_sample.rgb, band_mix);
		}
		// scene_rgb used for near-radius (real scene colors for the
		// player's immediate surroundings).
		vec3 stipple_rgb;
		if (stipple_color.a > 0.0) {
			stipple_rgb = stipple_color.rgb;
		} else {
			stipple_rgb = tile_rgb;
		}

		// Revealed = (near_vis OR dithered_pulse_reveal). Near-field
		// shows the procedural tile rendering (interior + surface
		// atlases) so the player sees textured terrain around them
		// always. Pulse-revealed pixels use stipple_rgb (magenta by
		// default). Ring glow is added on top everywhere so the
		// wave front stays readable in dark areas.
		vec3 revealed_rgb = mix(stipple_rgb, tile_rgb, near_vis);
		vec3 out_rgb = mix(ring_rgb, revealed_rgb + ring_rgb, reveal);
		float out_alpha = 1.0; // fully opaque overlay

		// Small dark floor so the ring never punches fully to
		// base color on perfect black.
		out_rgb = max(out_rgb, vec3(0.0));

		COLOR = vec4(out_rgb, out_alpha);
	}
}
