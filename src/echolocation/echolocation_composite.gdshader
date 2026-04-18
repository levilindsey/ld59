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
const int MAX_TAGGED_SPRITES = 32;

uniform vec2 player_uv = vec2(0.5, 0.5);
uniform vec2 screen_size_px = vec2(1152.0, 648.0);

// Backbuffer of the layer-0 content (tiles, player, bugs, enemies,
// props). Pixel art — sample nearest. Used only for the near-field
// visual reveal (textured_rgb fallback = c0). Type classification
// and gradient sampling now use `tag_tex` instead, so player and
// parallax pixels don't contaminate those signals.
uniform sampler2D screen_tex : hint_screen_texture,
		repeat_disable, filter_nearest;

// Frequency-tag viewport texture. A parallel SubViewport that
// shares World2D with the scene but is rendered by a camera with
// canvas_cull_mask = 2, so it only sees visibility-layer-2 items
// (terrain is on layer 1|2; bugs/enemies/props can join later).
// Every pixel is either transparent (no tagged content) or the
// exact palette color of the tile/sprite sitting there — giving
// the shader an unambiguous per-pixel type map.
uniform sampler2D tag_tex : repeat_disable, filter_nearest;

// Offset in UV to use when taking gradient taps. A wider tap gives
// a thicker "surface band" that fades into the interior, so pulse
// stippling gets a spatial gradient instead of being a thin rim.
uniform float gradient_tap_px : hint_range(0.5, 32.0) = 12.0;

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
// 0 = no gradient influence (uniform stipple density everywhere a
// tile is); 1 = stipple density follows grad_mag × facing exactly,
// so surfaces stipple strongly and deep interiors don't stipple
// at all. Default 1.0 gives the pointillism-only-at-surfaces look.
uniform float surface_prominence_strength : hint_range(0.0, 1.0)
		= 1.0;
// Minimum fraction of pulse intensity on flat interiors. Default 0
// so deep interiors stay black under a pulse — only the surface
// band and its fade-in toward interior stipple.
uniform float interior_floor : hint_range(0.0, 1.0) = 0.0;
// Multiplier applied to raw luminance-gradient magnitude at each
// scale before the per-scale weights kick in. Higher = surfaces
// saturate to full prominence faster (stronger surface lines);
// lower = longer, gentler gradient band from surface into interior.
uniform float gradient_gain : hint_range(0.5, 12.0) = 3.0;

// Noise floor subtracted from combined grad magnitude, then the
// remainder is rescaled to [0, 1]. Prevents faint multi-scale
// signals in deep interiors (e.g., far-tap picking up a distant
// wall across a gap) from producing sparse sub-threshold stipples.
// Raise if you still see a few stipple dots in deep tile interior;
// lower if the surface-to-interior fade feels too abrupt.
// Default chosen aggressive because the far tap's binary
// "detected-an-edge" response tends to plateau across the interior
// band before dropping out; a high floor trims that plateau.
uniform float grad_floor : hint_range(0.0, 0.7) = 0.4;

// Bayer dither for pointillism (8x8 ordered). Smaller tile = finer
// stipples. Shader cost is constant regardless of tile size — it's
// one texture lookup + compare per pixel either way.
uniform sampler2D bayer_tex : source_color, repeat_enable,
		filter_nearest;
uniform float bayer_tile_px : hint_range(0.5, 16.0) = 2.0;

// Frequency palette. Unused when palette_count == 0; in that mode
// the shader treats every pixel as "matches." Populate in Phase 3.
uniform vec4 palette[MAX_PALETTE];
uniform int palette_freqs[MAX_PALETTE];
uniform int palette_count = 0;
// Maximum RGB distance a pixel's color can be from a palette entry
// to still count as "matches that type." Terrain meshes emit exact
// palette colors, so a tight threshold is correct; too-loose lets
// anti-aliased sprite pixels (player outline, bug edges) false-
// match and render as flat palette color, producing a "ghost of the
// sprite" artifact on nearby tiles.
uniform float palette_match_threshold : hint_range(0.0, 1.5) = 0.02;

// Tagged sprites: per-frame array of bugs (and future enemies)
// whose screen position + frequency we need the shader to know
// about. Palette-match on the backbuffer alone can't reliably
// identify small semi-transparent sprites; the tag halo gives each
// sprite a shader-side bounding circle so pulse stipples reveal it
// at its type color regardless of alpha/blending. Lightweight stand-
// in for a full frequency-tag SubViewport until enemies with
// irregular shapes need one.
// Packing: xy = screen-pixel center, z = halo radius in pixels,
// w = Frequency enum id.
uniform vec4 tagged_sprites[MAX_TAGGED_SPRITES];
uniform int tagged_sprite_count = 0;
// Threshold for counting a pixel as "background" (low luminance /
// transparent). In Phase 1 we use this to keep the shader from
// sparkling the backdrop clear color.
uniform float background_luma_threshold : hint_range(0.0, 1.0) = 0.02;

// Current frequency of the player (Frequency.Type enum value).
uniform int current_frequency = 0;

// Brightness + saturation boost applied to stipples whose type
// matches `current_frequency`. Non-matching tile/object types still
// stipple in their own palette color — the boost just makes the
// player's current frequency visually pop.
uniform float matching_brightness_boost : hint_range(1.0, 2.5)
		= 1.25;
uniform float matching_saturation_boost : hint_range(1.0, 2.5)
		= 1.35;

// Stipple color override. When alpha > 0, pulse-revealed pixels are
// painted this color instead of the tile / scene pixel underneath.
// Default alpha=0 so dots match the underlying tile-type color;
// bump alpha to debug dot placement with a loud tint.
uniform vec4 stipple_color : source_color = vec4(1.0, 0.0, 1.0, 0.0);

// Facing ramp (piecewise):
// - `facing_threshold_lo`: how far behind the normal can point
//   before it bottoms out at `back_facing_visibility` (the floor —
//   no longer 0). A surface with dot(normal, to_player) <=
//   -facing_threshold_lo produces facing=back_facing_visibility.
// - `facing_threshold_hi`: how directly the normal must face the
//   player to reach full visibility. dot >= facing_threshold_hi
//   produces facing=1.
// - `perpendicular_strength`: visibility at exactly perpendicular
//   (dot=0). Gives surfaces seen edge-on partial visibility.
// - `back_facing_visibility`: visibility for surfaces whose normal
//   points away from the player. Small but non-zero so back walls
//   stipple faintly under a pulse instead of vanishing.
uniform float facing_threshold_lo : hint_range(0.0, 1.0) = 0.3;
uniform float facing_threshold_hi : hint_range(0.0, 1.0) = 0.8;
uniform float perpendicular_strength : hint_range(0.0, 1.0) = 0.5;
uniform float back_facing_visibility : hint_range(0.0, 1.0) = 0.18;

// Debug: bypass effects and draw a crosshair at player_uv so the
// world→screen transform can be verified at a glance.
uniform bool debug_show_anchor = false;
// Debug: render the raw tag_tex contents so you can confirm the
// frequency-tag SubViewport is rendering the terrain correctly.
// Tile pixels should appear in their flat palette color; everything
// else should be black/transparent.
uniform bool debug_show_tag = false;

// --- Procedural tile texturing (near-field only) ---------------------------
// Tiles in the scene render as flat palette color (the simplest
// reliable source for the shader's palette-match classification). The
// composite shader then overlays per-type interior + surface textures
// inside the near-field so the close-by view has real art, not just a
// flat wash. The stipple path outside near-field stays flat palette
// color so echo dots read as one color per type.
uniform sampler2D interior_atlas : source_color, repeat_disable,
		filter_nearest;
uniform sampler2D surface_atlas : source_color, repeat_disable,
		filter_nearest;
uniform int atlas_slot_count = 8;
uniform float interior_scale_px : hint_range(4.0, 128.0) = 32.0;
uniform float surface_scale_along_px : hint_range(4.0, 128.0) = 32.0;
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

// Finds the palette entry closest to `c`. Writes the matched
// frequency id into `type_id` and the palette color into
// `type_color`, and returns true when the match is within
// `palette_match_threshold`. Pixels outside the threshold
// (sprites, HUD, mid-gradient edges) return false and the outputs
// stay zeroed — the caller treats those as non-tile.
bool detect_frequency(vec3 c, out int type_id, out vec3 type_color) {
	type_id = 0;
	type_color = vec3(0.0);
	if (palette_count <= 0) {
		return false;
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
	if (best_d > palette_match_threshold) {
		return false;
	}
	type_id = palette_freqs[best_i];
	type_color = palette[best_i].rgb;
	return true;
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
	} else if (debug_show_tag) {
		vec4 tag_pixel = texture(tag_tex, SCREEN_UV);
		COLOR = vec4(tag_pixel.rgb, 1.0);
	} else {
		// Sample scene color at center (for visual reveal).
		vec3 c0 = texture(screen_tex, SCREEN_UV).rgb;
		// Sample tag-viewport color at center (for type
		// classification + gradient). Tag viewport only contains
		// terrain (and later bug/enemy tags), so palette-matching
		// and gradient sampling here are clean — no player or
		// parallax contamination.
		vec3 tag0 = texture(tag_tex, SCREEN_UV).rgb;
		const vec3 luma = vec3(0.299, 0.587, 0.114);
		float l0 = dot(c0, luma);

		// --- Multi-scale gradient ---------------------------------
		// A single central-difference tap gives a binary edge/no-
		// edge response at `gradient_tap_px`, which produces a
		// hard-edged stipple rim. Sample at three scales instead so
		// pixels at increasing depth inside a tile detect edges at
		// wider and wider radii, with decreasing weight — the result
		// is a smooth surface→interior fade over ~a few cells.
		// Close scale = strong contribution near the true surface;
		// far scale = weak contribution from pixels several cells
		// deep; in the deepest interior every scale returns zero
		// and stippling drops to nothing.
		// All gradient taps sample `tag_tex` so sprites and parallax
		// can't skew the gradient direction or magnitude (which was
		// the cause of the "gap under the player" artifact).
		vec2 tap_close_uv = vec2(gradient_tap_px * 0.33,
				gradient_tap_px * 0.33) / screen_size_px;
		vec2 tap_mid_uv = vec2(gradient_tap_px, gradient_tap_px)
				/ screen_size_px;
		vec2 tap_far_uv = vec2(gradient_tap_px * 3.0,
				gradient_tap_px * 3.0) / screen_size_px;

		vec3 cL_s = texture(tag_tex,
				SCREEN_UV - vec2(tap_close_uv.x, 0.0)).rgb;
		vec3 cR_s = texture(tag_tex,
				SCREEN_UV + vec2(tap_close_uv.x, 0.0)).rgb;
		vec3 cU_s = texture(tag_tex,
				SCREEN_UV - vec2(0.0, tap_close_uv.y)).rgb;
		vec3 cD_s = texture(tag_tex,
				SCREEN_UV + vec2(0.0, tap_close_uv.y)).rgb;

		vec3 cL_m = texture(tag_tex,
				SCREEN_UV - vec2(tap_mid_uv.x, 0.0)).rgb;
		vec3 cR_m = texture(tag_tex,
				SCREEN_UV + vec2(tap_mid_uv.x, 0.0)).rgb;
		vec3 cU_m = texture(tag_tex,
				SCREEN_UV - vec2(0.0, tap_mid_uv.y)).rgb;
		vec3 cD_m = texture(tag_tex,
				SCREEN_UV + vec2(0.0, tap_mid_uv.y)).rgb;

		vec3 cL_l = texture(tag_tex,
				SCREEN_UV - vec2(tap_far_uv.x, 0.0)).rgb;
		vec3 cR_l = texture(tag_tex,
				SCREEN_UV + vec2(tap_far_uv.x, 0.0)).rgb;
		vec3 cU_l = texture(tag_tex,
				SCREEN_UV - vec2(0.0, tap_far_uv.y)).rgb;
		vec3 cD_l = texture(tag_tex,
				SCREEN_UV + vec2(0.0, tap_far_uv.y)).rgb;

		vec2 grad_close = vec2(
				dot(cR_s, luma) - dot(cL_s, luma),
				dot(cD_s, luma) - dot(cU_s, luma));
		vec2 grad_mid = vec2(
				dot(cR_m, luma) - dot(cL_m, luma),
				dot(cD_m, luma) - dot(cU_m, luma));
		vec2 grad_far = vec2(
				dot(cR_l, luma) - dot(cL_l, luma),
				dot(cD_l, luma) - dot(cU_l, luma));

		// Per-scale weights: close scale saturates at the surface,
		// mid and far contribute progressively weaker signals so the
		// band fades smoothly from surface to interior.
		float mag_close = length(grad_close) * gradient_gain * 1.0;
		float mag_mid = length(grad_mid) * gradient_gain * 0.5;
		float mag_far = length(grad_far) * gradient_gain * 0.25;
		float grad_mag = clamp(
				max(mag_close, max(mag_mid, mag_far)), 0.0, 1.0);
		// Noise-floor subtract: anything below grad_floor falls to
		// zero, so deep-interior pixels whose far tap faintly picks
		// up an off-axis wall stop producing sub-threshold stipples.
		// Remainder is rescaled so the surface peak stays at 1.
		grad_mag = clamp(
				(grad_mag - grad_floor) / max(1.0 - grad_floor, 1e-3),
				0.0,
				1.0);

		// Surface-atlas-specific proximity signal. Uses only the
		// close (4 px) scale so the surface accent texture stays a
		// narrow rim at the actual tile edge instead of smearing
		// down into what the multi-scale grad_mag now treats as the
		// stipple fade band. Shrinking this scale also shrinks the
		// halo of gradient contamination from the player sprite
		// that sits on top of tiles (the "gap" artifact).
		float surface_proximity = clamp(
				length(grad_close) * gradient_gain * 1.5, 0.0, 1.0);
		vec2 surface_normal = (length(grad_close) > 1e-4)
				? (-normalize(grad_close)) : vec2(0.0, -1.0);

		// Direction for the facing ramp. Mid scale is the most
		// stable (close flickers at tile corners, far smears across
		// gaps). Fall back to whichever scale has a non-trivial
		// reading.
		vec2 grad;
		if (length(grad_mid) > 1e-4) {
			grad = grad_mid;
		} else if (length(grad_close) > 1e-4) {
			grad = grad_close;
		} else {
			grad = grad_far;
		}

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
		// Piecewise facing ramp:
		//   facing_raw ≤ -facing_threshold_lo   → back_facing_visibility
		//   facing_raw == 0                     → perpendicular_strength
		//   facing_raw ≥  facing_threshold_hi   → 1
		// Smooth between these control points so back-facing surfaces
		// stipple faintly (rather than vanishing entirely).
		float facing;
		if (facing_raw >= 0.0) {
			float front_t = smoothstep(
					0.0, facing_threshold_hi, facing_raw);
			facing = mix(perpendicular_strength, 1.0, front_t);
		} else {
			float back_t = smoothstep(
					-facing_threshold_lo, 0.0, facing_raw);
			facing = mix(back_facing_visibility,
					perpendicular_strength, back_t);
		}

		// Surface prominence combines "how edgy" with "how facing".
		// When surface_prominence_strength is 0 we pass everything;
		// at 1 we gate fully by prominence_raw (with interior_floor
		// giving a minimum).
		float prominence_raw = grad_mag * facing;
		float prominence = mix(
				1.0,
				mix(interior_floor, 1.0, prominence_raw),
				surface_prominence_strength);

		// --- Classify this pixel ------------------------------------
		// Two sources of "type" information:
		//
		//   1. Palette nearest-match on c0. Terrain tiles render as
		//      exact palette color in the scene, so this identifies
		//      them reliably. Sprites (player, HUD, parallax) fail
		//      the tight threshold and are treated as non-tile.
		//
		//   2. Tagged-sprite halo. Bugs and (eventually) enemies push
		//      their screen position + frequency into
		//      `tagged_sprites`. Any pixel inside a halo inherits
		//      that sprite's frequency. Handles small and semi-
		//      transparent sprites whose pixels don't palette-match
		//      reliably on their own.
		//
		// Sprite tags win where they overlap tiles — a bug sitting on
		// a tile reports bug frequency so matching-pulse stipples
		// reveal the bug, not the tile.
		int bg_type_id = 0;
		vec3 bg_type_color = vec3(0.0);
		bool is_bg_tile = detect_frequency(
				tag0, bg_type_id, bg_type_color);

		int tag_type_id = 0;
		bool is_sprite_tag = false;
		for (int i = 0; i < MAX_TAGGED_SPRITES; i++) {
			if (i >= tagged_sprite_count) {
				break;
			}
			vec2 d = px - tagged_sprites[i].xy;
			if (length(d) < tagged_sprites[i].z) {
				is_sprite_tag = true;
				tag_type_id = int(tagged_sprites[i].w);
				break;
			}
		}
		vec3 tag_type_color = vec3(0.0);
		if (is_sprite_tag && palette_count > 0) {
			for (int j = 0; j < MAX_PALETTE; j++) {
				if (j >= palette_count) {
					break;
				}
				if (palette_freqs[j] == tag_type_id) {
					tag_type_color = palette[j].rgb;
					break;
				}
			}
		}

		bool is_tagged = is_bg_tile || is_sprite_tag;
		int type_id = is_sprite_tag ? tag_type_id : bg_type_id;
		vec3 type_color = is_sprite_tag
				? tag_type_color : bg_type_color;

		// Don't light up the backdrop clear color. Tagged pixels
		// (tiles or sprites) always count; other pixels only if
		// they exceed the luma floor.
		float has_content = is_tagged
				? 1.0
				: step(background_luma_threshold, l0);

		// Tagged pixels always stipple under a pulse, regardless of
		// type. `is_matching` separately marks pixels whose type
		// equals the player's current frequency — those get a
		// brightness + saturation boost below so the matching color
		// reads more prominently than other types.
		float frequency_match = is_tagged ? 1.0 : 0.0;
		bool is_matching =
				is_tagged && type_id == current_frequency;

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

		// --- Near-field color: textured tiles + raw scene ----------
		// Only terrain tiles (is_bg_tile) get atlas texturing — bug
		// sprites, player, HUD pass through c0 so they look like
		// themselves under the near-field reveal.
		vec3 textured_rgb = c0;
		if (is_bg_tile) {
			float slot_count_f = max(float(atlas_slot_count), 1.0);
			float u_base = float(bg_type_id) / slot_count_f;
			float u_width = 1.0 / slot_count_f;

			vec2 world_pos = world_origin
					+ UV * screen_size_px * world_per_screen_px;

			// Interior: wrap within a tile-sized cell, then shift
			// into this type's atlas slot on the x axis.
			float interior_u_frac = fract(
					world_pos.x / interior_scale_px);
			float interior_v = fract(
					world_pos.y / interior_scale_px);
			vec2 interior_uv = vec2(
					u_base + interior_u_frac * u_width,
					interior_v);
			vec3 interior_rgb = texture(
					interior_atlas, interior_uv).rgb;

			// Surface band: sample along the surface tangent, with
			// depth v driven by surface_proximity (close-scale
			// gradient). Using the close scale here — instead of the
			// multi-scale grad_mag — keeps the surface accent texture
			// as a narrow rim at the actual tile edge. grad_mag is
			// reserved for stipple-density fade; reusing it here
			// would smear the surface art deep into the interior
			// (the stretched-color artifact).
			vec2 tangent = vec2(-surface_normal.y, surface_normal.x);
			float along = fract(
					dot(world_pos, tangent) / surface_scale_along_px);
			float v = clamp(1.0 - surface_proximity, 0.0, 1.0);
			vec2 surface_uv = vec2(
					u_base + along * u_width, v);
			vec4 surface_sample = texture(
					surface_atlas, surface_uv);

			float band_mix = smoothstep(0.2, 0.8, surface_proximity)
					* surface_sample.a;
			textured_rgb = mix(
					interior_rgb, surface_sample.rgb, band_mix);
		}

		// --- Echo-pulse stipple color: flat palette per type -------
		// Tagged pixels (tiles + bug/enemy halos) stipple with their
		// flat palette color. Interiors and surfaces of a tile share
		// the same dot color. Non-tagged pixels fall back to c0 but
		// won't actually stipple — frequency_match is 0 for them.
		vec3 stipple_rgb = is_tagged ? type_color : c0;
		// Matching-type stipples get a brightness + saturation
		// bump — same hue as the palette color, just pushed brighter
		// and farther from its luminance midpoint. Non-matching
		// types stay at their base palette color.
		if (is_matching) {
			float lum = dot(stipple_rgb, luma);
			stipple_rgb = mix(
					vec3(lum),
					stipple_rgb,
					matching_saturation_boost);
			stipple_rgb *= matching_brightness_boost;
		}
		// Optional debug tint — author stipple_color with alpha > 0
		// to repaint every dot a loud color for placement checks.
		stipple_rgb = mix(stipple_rgb, stipple_color.rgb,
				stipple_color.a);

		// --- Combine --------------------------------------------------
		// Near-field reveal fades the textured view up by near_vis.
		// Pulse reveal paints flat stipples where the dither matrix
		// allows, gated by frequency_match + has_content (so no dots
		// on sprites or empty backdrop) and attenuated by
		// (1 - near_vis) so stippling disappears inside the close-by
		// region — the textured near-field owns that visual space.
		// Component-wise max keeps each contribution at its natural
		// brightness; for non-tile pixels both contributions share
		// c0, so max collapses to c0 * max(near_vis, stipple_term).
		// Ring glow draws over anything not tagged — parallax,
		// empty backdrop, player sprite — and is suppressed only
		// where a tile or a tagged sprite (bug, future enemy) sits,
		// so the expanding color ring passes visibly over the sky
		// but not across tile / bug art.
		vec3 near_contribution = textured_rgb * near_vis;
		vec3 pulse_contribution = stipple_rgb * dithered_pulse_reveal
				* (1.0 - near_vis);
		float ring_mask = is_tagged ? 0.0 : 1.0;
		vec3 out_rgb = max(near_contribution, pulse_contribution)
				+ ring_rgb * ring_mask;

		// Small dark floor so the ring never punches negative on
		// pathological uniform values.
		out_rgb = max(out_rgb, vec3(0.0));

		COLOR = vec4(out_rgb, 1.0);
	}
}
