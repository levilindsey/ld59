shader_type canvas_item;
render_mode blend_add, unshaded;


const int RAINBOW_COUNT = 7;


// 0.0 = nothing lit. 1.0 = streak fully extended from P0 to P1.
// Tweened during the burst's lifetime.
uniform float progress : hint_range(0.0, 1.0) = 0.0;

// Soft leading-edge width (in UV.x units). The tip sparkles white
// for a short window behind `progress`.
uniform float head_width : hint_range(0.01, 1.0) = 0.28;

// Per-burst hue rotation so separate bursts read as different
// rainbows rather than identical copies.
uniform float hue_offset : hint_range(0.0, 1.0) = 0.0;

// Fades the whole streak out after `progress` hits 1.0.
uniform float alpha_scale : hint_range(0.0, 2.0) = 1.0;

// Width (in UV.y units) of the AA fade at the stripe's outer
// edge. Kept narrow so the stripe reads as sharp — the softness
// lives in the outer glow halo instead, not inside the stripe.
uniform float stripe_edge_softness : hint_range(0.0, 0.2) = 0.03;

// Fraction of `|UV.y|` that marks the visible stripe's edge. The
// region outside this (up to `|UV.y| = 1`) is the outer glow halo.
// Must match the mesh generator's `_STRIPE_EDGE_UV` (driven by
// `_GLOW_EXTENT` in rainbow_burst.gd).
uniform float stripe_edge_uv : hint_range(0.01, 1.0) = 0.556;

// Peak alpha of the outer glow halo relative to the core stripe.
// Reads as a soft haze, not a second stripe.
uniform float glow_intensity : hint_range(0.0, 1.0) = 0.45;

// Fade-with-distance exponent applied along the arc. Brightness is
// multiplied by `pow(1.0 - t * distance_fade_reach, exponent)`
// where t is the arc parameter (0 at origin, 1 at tip). 0 = no
// fade; higher exponents pull the falloff toward the origin so the
// burst reads as a bright base with a dim, wispy tail.
uniform float distance_fade_exponent : hint_range(0.0, 8.0) = 1.5;

// Fraction of the arc over which the distance fade completes.
// `1.0` = fade hits zero at the tip (baseline); `0.5` = fade would
// only reach zero at *twice* the mesh length, so the visible tip
// still retains a chunk of its brightness. Lower values stretch the
// taper further past the tip and make the whole burst read brighter.
uniform float distance_fade_reach : hint_range(0.0, 1.0) = 0.5;

// Rainbow palette, pushed from `G.settings.color_rainbow_*` at
// spawn time. Sampled linearly across the cross-arc axis so
// tweaking a slot in Settings re-hues every burst spawned after
// the change.
uniform vec4 rainbow_colors[RAINBOW_COUNT] : source_color;


void fragment() {
	// Mesh encodes UV.x = t along the arc (0..1), UV.y = signed
	// cross-arc distance in [-1, 1]. The mesh is wider than the
	// visible stripe (stripe edge at `|UV.y| = stripe_edge_uv`) so
	// the outer region can render a soft glow halo that tapers to
	// zero at `|UV.y| = 1`.
	float t = UV.x;
	float c = UV.y;
	float ac = abs(c);

	// Core stripe mask: full alpha right up to `stripe_edge_uv`,
	// with only a hairline AA fade so the interior reads crisp
	// (no blur). All the softness lives in the outer glow below.
	float stripe = 1.0 - smoothstep(
			stripe_edge_uv - stripe_edge_softness,
			stripe_edge_uv,
			ac);

	// Outer glow mask: starts at the stripe edge, fades to zero at
	// the mesh outer edge (|c|=1), capped at `glow_intensity`.
	float glow = (1.0 - smoothstep(stripe_edge_uv, 1.0, ac))
			* glow_intensity;

	float tube = max(stripe, glow);

	// Reveal: only fragments behind the moving tip are lit.
	float revealed = step(t, progress);

	// Sample the rainbow palette across the cross-arc axis so the
	// colors read as parallel stripes running the full length of
	// the rainbow. Remap the stripe region [-stripe_edge_uv,
	// stripe_edge_uv] to [-1, 1] so the palette spans the visible
	// stripe only; the glow region clamps to the outermost slot on
	// each side (halo inherits the nearest-edge color).
	float strip_u = clamp(c / stripe_edge_uv, -1.0, 1.0);
	float strip = (strip_u + 1.0) * 0.5;
	strip = fract(strip + hue_offset);
	float seg = strip * float(RAINBOW_COUNT - 1);
	int i0 = int(floor(seg));
	if (i0 < 0) {
		i0 = 0;
	}
	if (i0 >= RAINBOW_COUNT - 1) {
		i0 = RAINBOW_COUNT - 2;
	}
	int i1 = i0 + 1;
	float seg_u = fract(seg);
	vec3 rgb = mix(
			rainbow_colors[i0].rgb,
			rainbow_colors[i1].rgb,
			seg_u);

	// Bright tip halo: the leading `head_width` fades toward white.
	float tip_glow = smoothstep(
			head_width, 0.0, progress - t) * revealed;
	rgb = mix(rgb, vec3(1.0, 1.0, 1.0), tip_glow * 0.8);

	float distance_vis = pow(
			max(1.0 - t * distance_fade_reach, 0.0),
			distance_fade_exponent);
	float brightness = revealed * tube * alpha_scale * distance_vis;
	COLOR = vec4(rgb * brightness, brightness);
}
