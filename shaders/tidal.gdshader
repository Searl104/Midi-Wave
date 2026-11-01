shader_type canvas_item;
// Tidal theme: black, glossy sand ripples on a plane below the water.
//
//  - The sand is a seamless scan (assets/tidal, from Poly Haven's "Aerial Beach 01", CC0) shown
//    only through its normal and roughness maps, so it reads as polished black obsidian.
//  - It sits on a parallax plane: it pans and zooms at plane_depth of the surface's rate, so it
//    stays put under the water like a sea floor.
//  - A slow tide line sweeps across it: wet sand turns glassy, then dries back to a duller shine.
//  - Ripples on the water refract the sand, and a passing wave makes its highlights flare.

#include "res://shaders/waves.gdshaderinc"

uniform vec2 surface_size = vec2(1280.0, 800.0);
uniform vec3 accent : source_color = vec3(0.18, 0.48, 1.0);
uniform vec2 view_px = vec2(0.0);       // pan: view offset in screen px (world offset x zoom)
uniform float zoom = 1.0;               // canvas zoom (beat spacing / BEAT_UNIT)
uniform sampler2D sand_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D sand_rough : hint_default_white, repeat_enable, filter_linear_mipmap;
uniform float tile_px = 1800.0;          // on-screen size of one texture tile at zoom 1
uniform float plane_depth = 0.65;       // pan/zoom rate of the sand relative to the surface
uniform float bump = 1.15;               // normal map strength
uniform float refraction = 22.0;        // px of displacement per unit of surface slope
uniform float tide_speed = 0.035;       // tide cycles per second

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 p = UV * surface_size;
	vec2 c = surface_size * 0.5;

	float h;
	vec2 grad;
	float energy;
	surface_waves(p, h, grad, energy);

	// --- The sand plane, below the water: slower pan and zoom, refracted by the ripples.
	float m = pow(max(zoom, 0.05), plane_depth);
	vec2 pp = p + grad * refraction;
	vec2 q = (pp - c) / m + view_px * plane_depth / m;      // plane coordinates (px at zoom 1)
	vec2 uv = q / tile_px;

	vec3 tn = texture(sand_normal, uv, 0.8).rgb * 2.0 - 1.0;   // OpenGL normal map (y up); bias softens grain
	vec3 n = normalize(vec3(tn.x * bump, -tn.y * bump, max(tn.z, 0.05)));   // screen y points down
	float rough = texture(sand_rough, uv, 0.8).r;

	// Tide: a soft wet band sweeping slowly across the sand, plus a thin bright tide line.
	vec2 tide_dir = normalize(vec2(0.35, 1.0));
	float tx = dot(q, tide_dir) / 2600.0 - TIME * tide_speed;
	float wet = smoothstep(0.15, 0.85, 0.5 + 0.5 * sin(tx * 6.2831853));
	float line = exp(-pow((fract(tx) - 0.62) * 34.0, 2.0));
	rough = mix(rough, rough * 0.25, wet);

	// --- Lighting: near-black glossy material, key light from the top-left.
	vec3 light = normalize(vec3(-0.45, -0.6, 0.66));
	vec3 view = vec3(0.0, 0.0, 1.0);
	vec3 hv = normalize(light + view);
	float ndl = max(dot(n, light), 0.0);
	float gloss = mix(260.0, 24.0, rough);
	float spec = pow(max(dot(n, hv), 0.0), gloss) * mix(1.4, 0.18, rough);

	// A soft environment: the reflected view ray picks up a cool sky toward the light.
	vec3 r = reflect(-view, n);
	float sky = smoothstep(-0.2, 0.9, dot(normalize(r.xy + 1e-4), normalize(light.xy))) * length(r.xy);
	float shine = mix(0.35, 1.0, wet);

	vec3 col = vec3(0.010, 0.011, 0.014) * (0.6 + ndl);               // black base
	col += vec3(0.16, 0.19, 0.24) * sky * (1.0 - rough) * shine;      // glossy sheen on the flanks
	col += vec3(0.85, 0.9, 1.0) * spec * shine;                       // crest highlights
	col += vec3(0.25, 0.32, 0.4) * line * (0.4 + 0.6 * ndl) * 0.25;   // tide line
	col *= 1.0 + clamp(energy, 0.0, 1.5) * 0.9;                       // a passing wave flares it

	// Depth under the water: darker toward the window edges.
	float vignette = smoothstep(1.2, 0.3, length(UV - 0.5));
	col *= 0.55 + 0.45 * vignette;

	// --- The water surface on top: a thin glass film.
	vec3 sn = normalize(vec3(-grad * 0.55, 1.0));
	float diff = dot(sn, light) - light.z;
	float sspec = pow(max(dot(reflect(-light, sn), view), 0.0), 48.0);
	col += vec3(0.7, 0.8, 0.95) * diff * 0.4;
	col += vec3(0.9, 0.95, 1.0) * sspec * 0.85;
	col += accent * max(h, 0.0) * 0.18;

	col += (hash(p) - 0.5) * 0.007;
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
