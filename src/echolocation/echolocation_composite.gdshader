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
const int MAX_PINGS = 128;
const int MAX_PARTICLES = 256;
// Must match `Frequency.Type.LIQUID` in src/core/frequency.gd.
// LIQUID cells bypass surface-depth gating so water reads through
// its full body, not just at its boundary.
const int LIQUID_TYPE_ID = 5;

uniform vec2 player_uv = vec2(0.5, 0.5);
uniform vec2 screen_size_px = vec2(1152.0, 648.0);

// Backbuffer of the layer-0 content (tiles, player, bugs, enemies,
// props). Pixel art — sample nearest. Used only for the near-field
// visual reveal (textured_rgb fallback = c0). Type classification
// and gradient sampling go through `density_tex` + `type_tex`, so
// player and parallax pixels never contaminate those signals.
uniform sampler2D screen_tex : hint_screen_texture,
		repeat_disable, filter_nearest;

// World-spanning density field, R8 per cell (actually per density
// sample, with one extra row/column per chunk for the shared edge).
// Built from the C++ TerrainWorld::build_density_image(); re-uploaded
// on `chunk_modified`. Bilinear filtered so the fragment shader gets
// a smooth, sub-pixel-accurate distance-to-surface via its gradient
// (replacing the 12-tap luminance-gradient hack that used to sample a
// tag SubViewport).
uniform sampler2D density_tex : filter_linear, repeat_disable;
// World-spanning per-cell type id, R8. Bytes are Frequency.Type enum
// values (0 = NONE = empty). Nearest filtering so the byte comes
// through intact — no blending between cell types. Replaces the
// palette-match path that used to run on `tag_tex`.
uniform sampler2D type_tex : filter_nearest, repeat_disable;
// Upper-left world-px position corresponding to pixel (0, 0) of the
// density/type textures. Computed from the chunk-coord bounding box.
uniform vec2 density_world_origin_px = vec2(0.0, 0.0);
// Dimensions of the type texture in cells (width, height). The
// density texture is (width + 1, height + 1).
uniform vec2 density_world_cell_size = vec2(1.0, 1.0);
// Cell size in world px. Matches TerrainSettings.cell_size_px.
uniform float density_cell_size_px : hint_range(1.0, 64.0) = 8.0;

// Radius in world px of the central-difference tap used to compute
// the density gradient (= inferred surface direction + distance
// proxy). The density field is bilinear-filtered so a single 2-tap
// central difference is sufficient — no multi-scale hack needed.
uniform float density_grad_tap_px : hint_range(0.5, 16.0) = 4.0;

// Near-field: always-on circular reveal around the player.
uniform float near_radius_px : hint_range(0.0, 512.0) = 80.0;
uniform float near_fade_px : hint_range(0.0, 128.0) = 32.0;

// Distance attenuation for pulse stippling (separate from the
// traveling-wave envelope). Pixels closer than `stipple_fade_start_px`
// stipple at full density; from there to `stipple_fade_end_px` the
// density fades smoothly to zero. This expresses the intuition that
// echolocation reveals close detail clearly and dims with distance.
uniform float stipple_fade_start_px : hint_range(0.0, 2000.0)
		= 180.0;
uniform float stipple_fade_end_px : hint_range(0.0, 2000.0)
		= 420.0;

// Pulses. xy=center_uv, z=age_sec, w=speed_px_per_sec.
uniform vec4 pulses[MAX_PULSES];
uniform vec4 pulse_colors[MAX_PULSES];
uniform vec4 pulse_cones[MAX_PULSES];
// Per-pulse frequency ids (Frequency.Type). Used so a cell's stipple
// can match ANY active pulse's frequency — not just the player's
// currently-selected one — so cells that are currently being damaged
// by an in-flight pulse still stipple brightly.
uniform int pulse_freqs[MAX_PULSES];
uniform int pulse_count = 0;

// Bounce-back pings. One entry per surface segment; scheduled by
// the renderer's bulk surface scan. Packing:
//   pings[i]         = (hit_uv.xy, age_sec, frequency)
//   ping_segments[i] = (start_uv.xy, end_uv.xy)
//   ping_normals[i]  = (outward_normal.xy, unused, unused)
// `hit_uv` is the point on the segment closest to the pulse
// emitter; `start_uv`/`end_uv` define the colinear surface segment;
// `ping_normals` is the surface's outward normal (screen-space unit
// vector). The line grows along the segment from `hit_uv`, then
// drifts outward along the normal as the ping fades.
// `age_sec < 0` encodes "pending / skip" defensively.
uniform vec4 pings[MAX_PINGS];
uniform vec4 ping_segments[MAX_PINGS];
uniform vec4 ping_normals[MAX_PINGS];
uniform int ping_count = 0;

// Debris particles — one per destroyed cell × `_PARTICLES_PER_DESTROYED_CELL`.
// Packing: xy = screen_uv, z = radius_px (screen), w = frequency id.
// Rendered as solid colored disks (no dither). Inside the near-field
// they tint with the tile atlas; outside, the flat palette color.
uniform vec4 particles[MAX_PARTICLES];
uniform int particle_count = 0;

// Ping visual tuning.
uniform float ping_line_thickness_px : hint_range(0.5, 8.0) = 1.0;
uniform float ping_line_glow_px : hint_range(0.0, 6.0) = 1.0;
uniform float ping_grow_duration_frac : hint_range(0.05, 1.0) = 0.35;
uniform float ping_lifetime_sec : hint_range(0.1, 2.0) = 0.5;
// After the growth phase ends, the whole line drifts away from the
// surface and toward the player by this many pixels over the rest
// of the ping's lifetime. Suggests the echo's wavefront returning
// home — not just a flash on the wall.
uniform float ping_translate_distance_px : hint_range(0.0, 256.0)
		= 96.0;

// Damage-region flash. `damage_age_tex` is an R8 world-cell texture
// where 1.0 = just damaged, 0.0 = never or long-ago. The renderer
// stamps damaged cells and decays the value each frame. The flash
// covers the ENTIRE damaged region (not just its outline); brightness
// follows a delay → ramp-up → ramp-down curve so the effect reads as
// "the echo returning" rather than an instant flash.
uniform sampler2D damage_age_tex : filter_nearest, repeat_disable;
// Peak brightness multiplier. Very faint by default — the effect is
// supposed to suggest "a soft echo wash", not overpower the terrain.
uniform float damage_flash_intensity : hint_range(0.0, 2.0) = 0.4;
// Saturation: 0 = pure white, 1 = pure tile palette color. Default
// leaves a faint tint so RED damage reads slightly pink-white, GREEN
// slightly mint-white, etc.
uniform float damage_flash_saturation : hint_range(0.0, 1.0) = 0.2;
// Delay fraction (in "damage age" terms) before the flash starts
// rising from zero. At stored_value > (1 - delay), brightness = 0.
uniform float damage_flash_delay_frac : hint_range(0.0, 0.9) = 0.35;
// Where in the decay the brightness peaks. Stored values between
// (1 - delay) and peak give the rising ramp; from peak down to 0
// the brightness fades linearly to zero.
uniform float damage_flash_peak_frac : hint_range(0.05, 1.0) = 0.55;

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
uniform float grad_floor : hint_range(0.0, 0.7) = 0.05;
// Power curve applied to grad_mag after the noise-floor cut. Values
// > 1 dim the tail of the gradient much faster than its head, so
// the deep end of the surface→interior band reads as faintly
// stippled while the surface itself stays bright.
uniform float gradient_fade_curve : hint_range(0.5, 6.0) = 1.5;

// Bayer dither for pointillism (8x8 ordered). Smaller tile = finer
// stipples. Shader cost is constant regardless of tile size — it's
// one texture lookup + compare per pixel either way.
uniform sampler2D bayer_tex : source_color, repeat_enable,
		filter_nearest;
uniform float bayer_tile_px : hint_range(0.5, 16.0) = 2.0;

// Frequency palette. Used only for looking up the display color for
// a type id produced by `type_tex` or by a tagged sprite. Unused when
// `palette_count == 0` (in that mode every tagged pixel renders with
// vec3(0) stipple color).
uniform vec4 palette[MAX_PALETTE];
uniform int palette_freqs[MAX_PALETTE];
uniform int palette_count = 0;

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

// Stipple-density factor applied to non-matching tagged pixels.
// Matching pixels stipple at full density (1.0); non-matching pixels
// stipple at this fraction. Keeps other-type terrain legible as
// fainter speckles while the matching color still dominates.
uniform float non_matching_stipple_factor : hint_range(0.0, 1.0)
		= 0.5;

// Cheap in-shader "bloom" applied to matching-type stipples:
// - bayer tile is scaled up so each matching dot covers more pixels.
// - Bayer threshold becomes a smoothstep so dot edges fall off softly
//   (fake halo glow).
// - The matching stipple color picks up one more brightness multiplier
//   after the saturation boost, pushing past 1.0 for an HDR-ish
//   overbright feel (clamps at the display).
uniform float matching_bloom_size_multiplier : hint_range(1.0, 3.0)
		= 2.5;
uniform float matching_bloom_soft_width : hint_range(0.0, 0.5)
		= 0.32;
uniform float matching_bloom_brightness_bump : hint_range(1.0, 3.0)
		= 2.4;

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
// Damage-tier crack overlay atlas — horizontal strip of per-tier
// crack patterns (L8). Sampled .r as crack intensity (0 = clean, 1 =
// full crack); darkens the tile's interior art accordingly.
// `health_tex` is R8 per-cell with 1.0 = full HP, 0 = destroyed.
uniform sampler2D damage_tier_atlas : repeat_disable, filter_nearest;
uniform sampler2D health_tex : filter_nearest, repeat_disable;
uniform int damage_tier_count = 5;
uniform float damage_overlay_strength : hint_range(0.0, 1.5) = 0.9;
uniform int atlas_slot_count = 8;
uniform float interior_scale_px : hint_range(4.0, 128.0) = 32.0;
uniform float surface_scale_along_px : hint_range(4.0, 128.0) = 32.0;
// Depth (world px) the surface accent band extends from the cell
// surface INTO the solid. Default matches `density_cell_size_px` so
// the accent stays within the surface cell's own bounds and doesn't
// bleed into interior cells below.
uniform float surface_depth_px : hint_range(1.0, 32.0) = 8.0;
// RGB distance from the expected terrain palette color above which
// the near-field atlas override is skipped and the scene pixel (c0)
// is kept instead. The composite classifies terrain by world-space
// `type_tex`, not by what's actually drawn at the screen pixel, so
// a player / bug / enemy sprite overlapping a terrain cell (e.g.,
// the player swimming in LIQUID) gets repainted as terrain unless
// this check lets it through. Tolerance is chroma distance in sRGB
// 0..1 space.
uniform float overlay_sprite_diff_threshold : hint_range(0.0, 1.0)
		= 0.08;
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

// Look up the palette color for a type id. Palette is small (≤16);
// loop is cheap. Returns vec3(0) if the type id is not in the palette.
vec3 palette_color_for_type(int type_id) {
	for (int j = 0; j < MAX_PALETTE; j++) {
		if (j >= palette_count) {
			break;
		}
		if (palette_freqs[j] == type_id) {
			return palette[j].rgb;
		}
	}
	return vec3(0.0);
}


// ---- world ↔ density-texture coords ---------------------------------------

// Convert world-px to density-texture UV. Density texture is
// (cells_wide + 1, cells_high + 1) samples. Corner i sits at world
// pos `i * density_cell_size_px`, and its texel center in UV is at
// `(i + 0.5) / (cells + 1)` — so we add 0.5 in cell units before
// normalizing. Omitting the 0.5 shifts all density samples by half a
// texel (= half a cell in world pixels), which offsets the whole
// surface gradient and is why interior / accent textures end up
// half-a-cell off from the authored cell boundary.
vec2 world_to_density_uv(vec2 world_px) {
	vec2 cell = (world_px - density_world_origin_px)
			/ density_cell_size_px;
	return (cell + vec2(0.5)) / (density_world_cell_size + vec2(1.0));
}


// Convert world-px to type-texture UV. Type texture is
// (cells_wide, cells_high). Offset by half a cell so nearest-filter
// samples the cell that contains world_px, not its upper-left corner.
vec2 world_to_type_uv(vec2 world_px) {
	vec2 cell = (world_px - density_world_origin_px)
			/ density_cell_size_px;
	return (cell + vec2(0.5)) / density_world_cell_size;
}


// Sample the per-type interior-atlas color at an arbitrary world
// position. Extracted from the main `if (is_bg_tile)` block so the
// debris-particle pass can reuse it (particles borrow the tile's
// texture art inside the near-field).
vec3 sample_tile_interior_atlas(vec2 pos, int type_id) {
	float slot_count_f = max(float(atlas_slot_count), 1.0);
	float u_base = float(type_id) / slot_count_f;
	float u_width = 1.0 / slot_count_f;
	float interior_u_frac = fract(pos.x / interior_scale_px);
	float interior_v = fract(pos.y / interior_scale_px);
	vec2 interior_uv = vec2(
			u_base + interior_u_frac * u_width,
			interior_v);
	return texture(interior_atlas, interior_uv).rgb;
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
		// Sample scene color at center (for visual reveal).
		vec3 c0 = texture(screen_tex, SCREEN_UV).rgb;
		const vec3 luma = vec3(0.299, 0.587, 0.114);
		float l0 = dot(c0, luma);

		// World-space position of this fragment. Used for sampling
		// the density + type textures (which live in world-px space,
		// not screen-uv space).
		vec2 world_pos = world_origin
				+ UV * screen_size_px * world_per_screen_px;

		// --- Multi-scale density-field gradient --------------------
		// Single-scale taps give a binary response (surface cell has
		// a gradient, deep interior has zero) which reads as a flat
		// stipple rim rather than a depth-gradient band. Sample the
		// density at three scales (close, mid, far) so pixels a few
		// cells deep into the interior still pick up a faint "a
		// surface is this direction" signal at the farther taps; the
		// weighted max gives a smooth stipple-density fade from
		// surface into interior over ~3-4 cells.
		//
		// The close-scale gradient is used for surface-normal /
		// tangent (more locally accurate); the combined magnitude
		// drives stipple density and the depth fade.
		float tap_close = density_grad_tap_px;
		float tap_mid = density_grad_tap_px * 3.0;
		float tap_far = density_grad_tap_px * 6.0;
		float d_close_L = texture(density_tex,
				world_to_density_uv(
						world_pos - vec2(tap_close, 0.0))).r;
		float d_close_R = texture(density_tex,
				world_to_density_uv(
						world_pos + vec2(tap_close, 0.0))).r;
		float d_close_U = texture(density_tex,
				world_to_density_uv(
						world_pos - vec2(0.0, tap_close))).r;
		float d_close_D = texture(density_tex,
				world_to_density_uv(
						world_pos + vec2(0.0, tap_close))).r;
		vec2 grad_close = vec2(
				d_close_R - d_close_L, d_close_D - d_close_U);

		float d_mid_L = texture(density_tex,
				world_to_density_uv(
						world_pos - vec2(tap_mid, 0.0))).r;
		float d_mid_R = texture(density_tex,
				world_to_density_uv(
						world_pos + vec2(tap_mid, 0.0))).r;
		float d_mid_U = texture(density_tex,
				world_to_density_uv(
						world_pos - vec2(0.0, tap_mid))).r;
		float d_mid_D = texture(density_tex,
				world_to_density_uv(
						world_pos + vec2(0.0, tap_mid))).r;
		vec2 grad_mid = vec2(
				d_mid_R - d_mid_L, d_mid_D - d_mid_U);

		float d_far_L = texture(density_tex,
				world_to_density_uv(
						world_pos - vec2(tap_far, 0.0))).r;
		float d_far_R = texture(density_tex,
				world_to_density_uv(
						world_pos + vec2(tap_far, 0.0))).r;
		float d_far_U = texture(density_tex,
				world_to_density_uv(
						world_pos - vec2(0.0, tap_far))).r;
		float d_far_D = texture(density_tex,
				world_to_density_uv(
						world_pos + vec2(0.0, tap_far))).r;
		vec2 grad_far = vec2(
				d_far_R - d_far_L, d_far_D - d_far_U);

		vec2 density_grad = grad_close;
		// Clamp each scale to [0, 1] INDEPENDENTLY before combining.
		// This way the far scale (which saturates even for pixels
		// several cells deep) contributes a fixed ceiling rather
		// than dominating. The weighted max then gives:
		//   surface cell  → close scale wins (1.0)
		//   1 cell deep   → mid scale capped at 0.5
		//   2 cells deep  → far scale capped at 0.25
		//   3 cells deep  → far scale partial, capped at ~0.125
		//   4+ cells deep → zero
		// i.e. a visible stipple gradient ~4 cells into solid.
		float mag_close = clamp(length(grad_close) * gradient_gain,
				0.0, 1.0);
		float mag_mid = clamp(length(grad_mid) * gradient_gain,
				0.0, 1.0);
		float mag_far = clamp(length(grad_far) * gradient_gain,
				0.0, 1.0);
		float grad_mag = max(
				mag_close,
				max(mag_mid * 0.5, mag_far * 0.25));
		// Noise-floor subtract: deep solid interior (smoothly 1
		// everywhere) and deep empty exterior (smoothly 0
		// everywhere) both give near-zero gradient; the floor trims
		// any residue from numerical noise.
		grad_mag = clamp(
				(grad_mag - grad_floor) / max(1.0 - grad_floor, 1e-3),
				0.0,
				1.0);
		// Power curve: dims the tail faster than the head so the
		// deep end of the surface→interior gradient reads as faintly
		// stippled while the surface stipples stay bright.
		grad_mag = pow(grad_mag, gradient_fade_curve);

		// Surface-atlas-specific proximity signal. Reuses the same
		// 2-tap gradient; the multiplier lets the surface band be
		// sharper or thicker than the stipple fade without a second
		// gradient tap.
		float surface_proximity = clamp(
				length(density_grad) * gradient_gain * 1.5, 0.0, 1.0);
		vec2 surface_normal = (length(density_grad) > 1e-4)
				? (-normalize(density_grad)) : vec2(0.0, -1.0);

		// Same gradient feeds the facing ramp — density gradient
		// points from empty→solid, so the outward normal (used for
		// "surface facing the player") is its negation.
		vec2 grad = density_grad;

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
		//   1. Direct `type_tex` sample — the C++ terrain writes its
		//      per-cell Frequency.Type id into this R8 world-spanning
		//      texture. NONE (0) means empty. This replaces the
		//      palette-match on a tag SubViewport, giving sub-pixel-
		//      stable classification independent of render artifacts.
		//
		//   2. Tagged-sprite halo. Bugs and (eventually) enemies push
		//      their screen position + frequency into
		//      `tagged_sprites`. Any pixel inside a halo inherits
		//      that sprite's frequency — handles small and semi-
		//      transparent sprites whose type isn't in the terrain
		//      texture at all.
		//
		// Sprite tags win where they overlap tiles — a bug sitting on
		// a tile reports bug frequency so matching-pulse stipples
		// reveal the bug, not the tile.
		int bg_type_id = int(
				texture(type_tex, world_to_type_uv(world_pos)).r
						* 255.0 + 0.5);
		bool is_bg_tile = bg_type_id != 0;
		vec3 bg_type_color = is_bg_tile
				? palette_color_for_type(bg_type_id) : vec3(0.0);

		// LIQUID cells always read — bypass the gradient-derived
		// prominence so water in a fully-submerged region (where the
		// density gradient is zero) still stipples. Pulse envelope,
		// frequency_match, distance_falloff etc. still gate normally.
		if (bg_type_id == LIQUID_TYPE_ID) {
			prominence = 1.0;
		}

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
		vec3 tag_type_color = is_sprite_tag
				? palette_color_for_type(tag_type_id) : vec3(0.0);

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

		// Near-field reveals EVERYTHING smoothly (background + tiles
		// + player) with no dither, no frequency gating, no surface
		// bias. This is the "you always see around you" light.
		float near_vis = 1.0 - smoothstep(
				near_radius_px,
				near_radius_px + near_fade_px,
				to_player_len);

		// Pulse contribution — dithered, surface-biased, frequency-
		// gated. Also track whether any active pulse's frequency
		// matches this cell's type so the cell can be considered
		// "matching" (and get the full bloom treatment) whenever it
		// is being damaged by an in-flight pulse, even if the player
		// has already switched away to a different frequency.
		float raw_pulse_vis = 0.0;
		vec3 ring_rgb = vec3(0.0);
		float ring_alpha = 0.0;
		bool any_matching_pulse_active = false;
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
			if (type_id != 0 && pulse_freqs[i] == type_id) {
				any_matching_pulse_active = true;
			}
		}

		// Matching: either the cell's type matches the player's
		// currently-selected frequency, OR some in-flight pulse is
		// currently damaging this cell's type. Gives the full bloom
		// treatment (bigger soft-edge dots + brightness bump) and
		// full stipple density. Non-matching tagged pixels stipple
		// dimly at `non_matching_stipple_factor`.
		bool is_matching = is_tagged && (
				type_id == current_frequency
				|| any_matching_pulse_active);
		float frequency_match = is_tagged
				? (is_matching ? 1.0 : non_matching_stipple_factor)
				: 0.0;

		// Distance falloff: stipple density tapers off the further
		// the pixel is from the player, dropping to zero past
		// stipple_fade_end_px. Layered on top of the traveling-wave
		// envelope, so close cells reveal densely under a pulse and
		// far cells barely reveal at all.
		float distance_falloff = 1.0 - smoothstep(
				stipple_fade_start_px,
				stipple_fade_end_px,
				to_player_len);

		float pulse_reveal = raw_pulse_vis
				* prominence
				* frequency_match
				* has_content
				* distance_falloff;

		// Dither the pulse reveal so it reads as stippling.
		// Matching-type pixels sample the Bayer pattern at a coarser
		// scale so each dot covers more pixels (bigger dots), and
		// threshold with a smoothstep so dot edges fall off softly
		// (fake bloom halo). Non-matching pixels keep the tight
		// single-pixel hard-edge stipple.
		float bayer_scale_px = is_matching
				? bayer_tile_px * matching_bloom_size_multiplier
				: bayer_tile_px;
		float bayer = texture(
				bayer_tex, px / bayer_scale_px / 8.0).r;
		float threshold = 1.0 - pulse_reveal;
		float dithered_pulse_reveal;
		if (is_matching) {
			dithered_pulse_reveal = smoothstep(
					threshold - matching_bloom_soft_width,
					threshold + matching_bloom_soft_width,
					bayer);
		} else {
			dithered_pulse_reveal = step(threshold, bayer);
		}
		// Without a pulse, pulse_reveal = 0 → threshold = 1. The
		// matching-branch smoothstep still returns > 0 for the highest-
		// threshold Bayer cells (bayer > threshold - soft_width), which
		// lit up matching-type tiles even with no active echo. Gate the
		// result so stipples only show during a pulse.
		dithered_pulse_reveal *= step(0.001, pulse_reveal);

		// Combined reveal (smooth near-field OR dithered pulse).
		float reveal = clamp(
				max(near_vis, dithered_pulse_reveal), 0.0, 1.0);

		// --- Near-field color: textured tiles + raw scene ----------
		// Only terrain tiles (is_bg_tile) get atlas texturing — bug
		// sprites, player, HUD pass through c0 so they look like
		// themselves under the near-field reveal.
		//
		// `is_bg_tile` is classified from world-space `type_tex`, so a
		// pixel where a non-terrain sprite (player swimming in LIQUID,
		// bug on a tile) is drawn in front of terrain also reports
		// true. Guard with a palette-color diff: if the actual rendered
		// pixel (c0) is far from the terrain's flat palette color, an
		// overlay sprite owns this pixel and we keep c0 instead of
		// overwriting it with the atlas texture.
		vec3 textured_rgb = c0;
		bool overlay_sprite_here = is_bg_tile
				&& distance(c0, bg_type_color)
						> overlay_sprite_diff_threshold;
		// `is_bg_tile` comes from a type-texture sample with a +0.5
		// offset that can bleed half a cell beyond the authored
		// solid region. Reinforce with a density-at-fragment gate:
		// only run the texturing path where the fragment is actually
		// inside the solid (d_here near 1). Outside that, leave c0.
		float d_here_outer = texture(
				density_tex, world_to_density_uv(world_pos)).r;
		bool inside_solid_cell = d_here_outer >= 0.99;
		if (is_bg_tile && !overlay_sprite_here && inside_solid_cell) {
			float slot_count_f = max(float(atlas_slot_count), 1.0);
			float u_base = float(bg_type_id) / slot_count_f;
			float u_width = 1.0 / slot_count_f;

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

			// --- Damage-tier crack overlay --------------------------
			// Look up the cell's current health (R8 texture), map the
			// damage fraction to a tier index, sample the crack atlas,
			// and darken the interior art where cracks land. Cells at
			// full HP (health_norm == 1) skip the overlay entirely;
			// cells at 20% HP show the heaviest tier, just short of
			// shattering. Gives progressive visual feedback as cells
			// chip down over multiple pulses, instead of popping cold.
			float health_norm = texture(
					health_tex,
					world_to_type_uv(world_pos)).r;
			float damage_frac = 1.0 - health_norm;
			if (damage_frac > 0.01 && damage_tier_count > 1) {
				float tier_f = damage_frac
						* float(damage_tier_count);
				int tier = clamp(
						int(tier_f),
						0, damage_tier_count - 1);
				float tier_u_base = float(tier)
						/ float(damage_tier_count);
				float tier_u_width = 1.0
						/ float(damage_tier_count);
				vec2 crack_uv = vec2(
						tier_u_base + interior_u_frac
								* tier_u_width,
						interior_v);
				float crack = texture(
						damage_tier_atlas, crack_uv).r;
				// Darker "crevice" color under the cracks — keeps the
				// frequency tint but reads as shadow / fracture.
				vec3 crack_rgb = interior_rgb * 0.2;
				interior_rgb = mix(
						interior_rgb,
						crack_rgb,
						crack * damage_overlay_strength);
			}

			// Surface band — aligned with authored cell boundaries.
			//
			// We render the accent STRICTLY INSIDE the solid cells:
			// opaque at the cell's surface edge, fading to transparent
			// `surface_depth_px` pixels INTO the solid. No accent
			// extends outside cell bounds.
			//
			// Approach: sample density at a position shifted OUTWARD
			// from the solid by `surface_depth_px`. That shifted
			// sample is 0 when the fragment is close to the surface
			// (outward probe lands in air) and 1 when the fragment is
			// deep inside the solid (outward probe still in solid).
			// Used directly as the atlas v-axis, this maps "distance
			// from surface" to the atlas's vertical fade.
			//
			// Tangent is snapped to the dominant cardinal direction so
			// the `along` coordinate stays monotonic along a given
			// wall — avoids flicker at cell boundaries where the raw
			// gradient direction could rotate.
			vec2 snapped_normal;
			if (abs(surface_normal.x) > abs(surface_normal.y)) {
				snapped_normal = vec2(
						sign(surface_normal.x), 0.0);
			} else {
				snapped_normal = vec2(
						0.0, sign(surface_normal.y));
			}
			vec2 tangent = vec2(
					-snapped_normal.y, snapped_normal.x);
			float along = fract(
					dot(world_pos, tangent) / surface_scale_along_px);
			vec2 outward_probe = world_pos
					+ snapped_normal * surface_depth_px;
			float d_out = texture(
					density_tex, world_to_density_uv(outward_probe)).r;
			float v = clamp(d_out, 0.0, 1.0);
			vec2 surface_uv = vec2(
					u_base + along * u_width, v);
			vec4 surface_sample = texture(
					surface_atlas, surface_uv);

			// Visibility gate: only render accent where the fragment
			// itself is INSIDE solid. We already know
			// `inside_solid_cell` from the outer guard, so the atlas
			// alpha (authored per-column fade) is the only additional
			// shaping the mix needs here.
			float band_mix = surface_sample.a;
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
			// Additional bloom bump — pushes the color past 1.0 so
			// the combined pulse + stipple reads as an overbright
			// glow. Display clamp handles the final output.
			stipple_rgb *= matching_bloom_brightness_bump;
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

		// --- Bounce-back pings ----------------------------------------
		// Each ping is a line drawn along the continuous colinear
		// surface segment the ray hit. During the first
		// `ping_grow_duration_frac` of the ping's lifetime the lit
		// portion grows outward from `hit_px` toward both segment
		// endpoints (reaching whichever endpoint is closer first);
		// the whole line then fades to zero over the remaining
		// lifetime. Lines are additive over the non-tagged layer
		// (same visual plane as the pulse ring glow).
		vec3 ping_rgb = vec3(0.0);
		for (int i = 0; i < MAX_PINGS; i++) {
			if (i >= ping_count) {
				break;
			}
			float age = pings[i].z;
			if (age < 0.0) {
				continue;
			}
			vec2 hit_px = pings[i].xy * screen_size_px;
			vec2 start_px = ping_segments[i].xy * screen_size_px;
			vec2 end_px = ping_segments[i].zw * screen_size_px;
			vec2 seg = end_px - start_px;
			float seg_length = length(seg);
			// Degenerate (zero-length) segment: fall back to a point
			// pulse at hit_px so the ping is at least visible.
			vec2 tangent;
			if (seg_length < 1e-3) {
				tangent = vec2(1.0, 0.0);
			} else {
				tangent = seg / seg_length;
			}
			vec2 seg_perp = vec2(-tangent.y, tangent.x);

			// Grow / fade phases and overall envelope.
			float t = clamp(age / ping_lifetime_sec, 0.0, 1.0);
			float grow_t = clamp(t / ping_grow_duration_frac, 0.0, 1.0);
			float fade_t = 1.0 - smoothstep(
					ping_grow_duration_frac, 1.0, t);

			// Line drift: after the grow phase, the line translates
			// perpendicular to the surface in the outward-normal
			// direction — physically the echo radiating outward from
			// the surface into empty space. Pixel is offset by the
			// negative of the line's translation to achieve the same
			// visual (equivalent to moving the line).
			vec2 normal_dir = ping_normals[i].xy;
			float translate_t = clamp(
					(t - ping_grow_duration_frac)
					/ max(1.0 - ping_grow_duration_frac, 1e-3),
					0.0, 1.0);
			vec2 line_offset = normal_dir
					* translate_t * ping_translate_distance_px;
			vec2 px_local = px - line_offset;

			// Project the pixel onto the segment: `along_hit` is the
			// position of the hit point on the segment, `along_pixel`
			// the current (drifted) pixel's position. Negative or
			// > seg_length means outside the segment bounds.
			float along_hit = dot(hit_px - start_px, tangent);
			float along_pixel = dot(px_local - start_px, tangent);
			float perp_pixel = dot(px_local - start_px, seg_perp);
			float dist_from_hit_along = abs(along_pixel - along_hit);

			// Growth: at grow_t=0 reveal is zero; at grow_t=1 it
			// reaches the farther endpoint (closer reached earlier).
			float max_reach = max(
					along_hit, seg_length - along_hit);
			float reveal_reach = grow_t * max_reach;

			// On-segment gate (only light up pixels between the two
			// endpoints). Small smoothstep softens the segment ends.
			float on_segment = smoothstep(-1.0, 0.0, along_pixel)
					* smoothstep(
							-1.0, 0.0, seg_length - along_pixel);

			// Line SDF: perpendicular distance from the segment
			// central axis, with an exponential falloff past the
			// nominal thickness for the glow halo.
			float perp_abs = abs(perp_pixel);
			float core = smoothstep(
					ping_line_thickness_px + ping_line_glow_px,
					ping_line_thickness_px,
					perp_abs);
			float halo = exp(-(perp_abs * perp_abs)
					/ max(ping_line_glow_px * ping_line_glow_px
							+ ping_line_thickness_px
									* ping_line_thickness_px,
							1e-3));
			float line_strength = max(core, halo * 0.6);

			// Along-segment reveal — smoothstep at the leading edge
			// so the growing line's tip is soft rather than a hard
			// cutoff.
			float reveal_window = smoothstep(
					reveal_reach + 1.0,
					reveal_reach,
					dist_from_hit_along);

			float brightness = on_segment
					* line_strength
					* reveal_window
					* fade_t;

			int ping_type_id = int(pings[i].w);
			vec3 ping_color = palette_color_for_type(ping_type_id);
			if (ping_type_id == 0
					|| dot(ping_color, ping_color) < 1e-6) {
				ping_color = vec3(1.0);
			}
			ping_rgb += ping_color * brightness;
		}
		// Pings are NOT masked by ring_mask — the line sits on the
		// tile surface during its grow phase, and we want it visible
		// there (not hidden "behind" the tile like the pulse ring
		// is). Additive blend makes matching-type tiles briefly
		// sparkle and empty-space lines (during the drift phase)
		// glow over the sky.
		out_rgb += ping_rgb;

		// --- Damage-region whole-area flash --------------------------
		// Entire damaged region lights up (not just its outline). The
		// stored damage_age_tex value decays from 1→0 over the ping
		// lifetime; we map it through a curve that gives a short
		// delay followed by a quick rise + slower fall. Color is
		// mostly white with a light tint of the tile's palette so the
		// effect feels like a soft returning echo wash, not a
		// frequency-colored highlight.
		vec2 dmg_uv = world_to_type_uv(world_pos);
		float dmg_here = texture(damage_age_tex, dmg_uv).r;
		if (dmg_here > 0.001) {
			// Ramp-in: brightness stays 0 while stored value is in
			// the top `damage_flash_delay_frac` of its range (just-
			// stamped cells are "waiting for the echo"). Between
			// `1 - delay_frac` and `peak_frac`, smoothstep up. Then
			// between `peak_frac` and `0`, smoothstep back down.
			float delay_edge = 1.0 - damage_flash_delay_frac;
			float ramp_in = 1.0
					- smoothstep(damage_flash_peak_frac,
							delay_edge, dmg_here);
			float ramp_out = smoothstep(
					0.0, damage_flash_peak_frac, dmg_here);
			float envelope = ramp_in * ramp_out;

			vec3 tile_tint = is_bg_tile
					? palette_color_for_type(bg_type_id)
					: vec3(1.0);
			if (dot(tile_tint, tile_tint) < 1e-3) {
				tile_tint = vec3(1.0);
			}
			// Mix toward white based on saturation (0 = pure white).
			vec3 flash_color = mix(
					vec3(1.0), tile_tint, damage_flash_saturation);
			out_rgb += flash_color
					* envelope
					* damage_flash_intensity;
		}

		// --- Debris particles ----------------------------------------
		// Solid colored disks — no dither, no distance gating. Inside
		// the near-field the color blends toward the tile's atlas art
		// ("closer matching the original cell texture"); outside, the
		// flat palette color ("same color as the stippling"). Rendered
		// last so particles visibly pop over terrain and sky alike.
		for (int pi = 0; pi < MAX_PARTICLES; pi++) {
			if (pi >= particle_count) { break; }
			vec2 p_px = particles[pi].xy * screen_size_px;
			float p_radius = particles[pi].z;
			int p_freq = int(particles[pi].w);
			float d = distance(px, p_px);
			if (d >= p_radius) { continue; }
			float edge = smoothstep(p_radius, p_radius - 1.0, d);
			if (edge <= 0.0) { continue; }
			vec3 atlas_color = sample_tile_interior_atlas(
					world_pos, p_freq);
			vec3 flat_color = palette_color_for_type(p_freq);
			if (p_freq == 0 || dot(flat_color, flat_color) < 1e-6) {
				flat_color = vec3(1.0);
			}
			vec3 p_color = mix(flat_color, atlas_color, near_vis);
			// Slight overbright so a palette-colored disk pops on
			// the dark echo-void background.
			p_color *= 1.3;
			out_rgb = mix(out_rgb, p_color, edge);
		}

		// Small dark floor so the ring never punches negative on
		// pathological uniform values.
		out_rgb = max(out_rgb, vec3(0.0));

		COLOR = vec4(out_rgb, 1.0);
	}
}
