shader_type canvas_item;
// Frosted glass: blurs what's behind the item and tints it with the item's own color.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float blur_px = 6.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.72;

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * blur_px;
	vec3 sum = vec3(0.0);
	float total = 0.0;
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			float wgt = 1.0 / (1.0 + float(x * x + y * y));
			sum += texture(screen_tex, SCREEN_UV + vec2(float(x), float(y)) * px).rgb * wgt;
			total += wgt;
		}
	}
	vec3 behind = sum / total;
	COLOR = vec4(mix(behind, COLOR.rgb, opacity), COLOR.a);
}
