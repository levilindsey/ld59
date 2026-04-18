shader_type canvas_item;

uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_width : hint_range(0.0, 10.0) = 1.0;
uniform bool outline_enabled = true;

void fragment() {
	vec4 color = texture(TEXTURE, UV);

	if (!outline_enabled) {
		COLOR = color;
	} else if (color.a < 0.5) {
		// Check neighboring pixels in a plus pattern.
		float outline = 0.0;
		vec2 texture_size = vec2(textureSize(TEXTURE, 0));
		vec2 pixel_size = outline_width / texture_size;

		// Check 4 directions for opaque pixels.
		outline += texture(TEXTURE, UV + vec2(pixel_size.x, 0.0)).a;
		outline += texture(TEXTURE, UV + vec2(-pixel_size.x, 0.0)).a;
		outline += texture(TEXTURE, UV + vec2(0.0, pixel_size.y)).a;
		outline += texture(TEXTURE, UV + vec2(0.0, -pixel_size.y)).a;

		if (outline > 0.5) {
			COLOR = outline_color;
		} else {
			COLOR = color;
		}
	} else {
		COLOR = color;
	}
}
