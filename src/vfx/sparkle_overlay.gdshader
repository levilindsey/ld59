shader_type canvas_item;
render_mode blend_add, unshaded;


// Tweened 0 → 1 → 0 over the effect's lifetime. Gates the whole
// overlay's brightness so the effect faded in / out cleanly.
uniform float progress : hint_range(0.0, 1.0) = 0.0;

// Sparkle color when a cell doesn't roll a rainbow tint. Defaults
// to plain white; can be slightly tinted per-effect if desired.
uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Number of sparkle grid cells across the overlay's UV space. A
// denser grid = more sparkles. Different scales per usage (per-slot
// HUD vs. full-coin world-space).
uniform float density : hint_range(0.5, 16.0) = 4.0;

// Half-size (UV) of each sparkle glyph. Smaller = tighter pinpoints.
uniform float sparkle_size : hint_range(0.01, 0.5) = 0.22;

// Twinkle frequency in Hz (uses TIME). Stylized, respects pause
// because the host node respects `SceneTreePauseMode`.
uniform float twinkle_hz : hint_range(0.5, 8.0) = 3.0;

// Fraction of sparkles that use a rainbow sprinkle color instead of
// `base_color`. 0 = all white; 1 = all rainbow.
uniform float sparkle_rainbow_chance : hint_range(0.0, 1.0) = 0.18;

// Shared ROYGBV palette — same values as the coin stipple
// sprinkles. Pushed by the spawning script from `G.settings`.
uniform vec4 sparkle_rainbow_colors[6] : source_color;


float cell_hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
}


void fragment() {
	// Grid the overlay space so each cell hosts one sparkle with a
	// deterministic center, size, and color. Per-cell hash never
	// changes between frames so the rainbow/white selection is
	// stable (not shimmering). Only the twinkle brightness uses TIME.
	vec2 uv = UV;
	vec2 grid = uv * density;
	vec2 cell = floor(grid);
	vec2 local = fract(grid);

	// Jitter each sparkle's center within its cell so they don't line
	// up on a grid.
	float hash = cell_hash(cell);
	float hash_b = cell_hash(cell + vec2(1.7, 3.1));
	vec2 center = vec2(
			0.2 + hash * 0.6,
			0.2 + hash_b * 0.6);

	// 4-pointed star: max of two crossed thin bars, each tapering
	// from a bright core to soft edges. Gives the classic
	// cartoon-sparkle look with no texture lookup.
	vec2 d = (local - center);
	float horiz = smoothstep(
			sparkle_size, 0.0, abs(d.x))
			* smoothstep(sparkle_size * 0.35, 0.0, abs(d.y));
	float vert = smoothstep(
			sparkle_size, 0.0, abs(d.y))
			* smoothstep(sparkle_size * 0.35, 0.0, abs(d.x));
	float star = max(horiz, vert);

	// Per-cell twinkle phase and envelope. Stars pulse in/out of
	// brightness asynchronously. `progress` gates the whole overlay.
	float phase = hash * TAU;
	float twinkle = 0.5 + 0.5 * sin(TIME * twinkle_hz * TAU + phase);
	float brightness = star * twinkle * progress;

	// Per-cell color roll: mostly `base_color`, occasionally a
	// ROYGBV sprinkle drawn from the same palette the coin stipple
	// uses. Independent sub-hash keeps this stable across frames.
	float tint_roll = fract(hash * 31.7);
	vec3 tint = base_color.rgb;
	if (tint_roll < sparkle_rainbow_chance) {
		int idx = int(floor(fract(hash * 53.13) * 6.0));
		tint = sparkle_rainbow_colors[idx].rgb;
	}

	COLOR = vec4(tint * brightness, brightness);
}
