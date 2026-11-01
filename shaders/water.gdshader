shader_type canvas_item;
// Glass theme: dark glass lit from the top-left, rippled by up to 64 waves.

#include "res://shaders/waves.gdshaderinc"

uniform vec2 surface_size = vec2(1280.0, 800.0);
uniform vec3 accent : source_color = vec3(0.18, 0.48, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 p = UV * surface_size;
	float h;
	vec2 grad;
	float energy;
	surface_waves(p, h, grad, energy);

	vec3 n = normalize(vec3(-grad * 0.55, 1.0));
	vec3 light = normalize(vec3(-0.45, -0.6, 0.66));   // screen y points down
	float diff = dot(n, light) - light.z;
	float spec = pow(max(dot(reflect(-light, n), vec3(0.0, 0.0, 1.0)), 0.0), 48.0);

	// Base: near-black glass with a soft sheen from the top-left and a vignette.
	float sheen = smoothstep(1.3, 0.0, length(UV - vec2(0.25, 0.15)));
	float vignette = smoothstep(1.15, 0.35, length(UV - 0.5));
	vec3 col = mix(vec3(0.02, 0.022, 0.028), vec3(0.085, 0.09, 0.105), sheen) * (0.55 + 0.45 * vignette);

	col += vec3(0.75, 0.8, 0.9) * diff * 0.5;
	col += vec3(0.9, 0.93, 1.0) * spec * 0.9;
	col += accent * max(h, 0.0) * 0.22;

	// Tiny grain so gradients don't band.
	col += (hash(p) - 0.5) * 0.008;
	COLOR = vec4(col, 1.0);
}
