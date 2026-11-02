shader_type canvas_item;
// Tidal theme: dark, glossy sand ripples on a plane below the water.
//
//  - The sand is a seamless scan (assets/tidal, from Poly Haven's "Aerial Beach 01", CC0): its
//    colour map, darkened, under a glossy finish from its normal and roughness maps.
//  - Caustics: light focused by the water dances across the sand.
//  - It sits on a parallax plane: it pans at plane_depth of the surface's rate (beat spacing, the
//    canvas zoom, doesn't scale it), so it
//    stays put under the water like a sea floor.
//  - Ripples on the water refract the sand, and a passing wave makes its highlights flare.

#include "res://shaders/waves.gdshaderinc"

uniform vec2 surface_size = vec2(1280.0, 800.0);
uniform vec3 accent : source_color = vec3(0.18, 0.48, 1.0);
uniform vec2 view_px = vec2(0.0);       // pan: the world point at the window centre, less half the window
uniform sampler2D sand_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D sand_rough : hint_default_white, repeat_enable, filter_linear_mipmap;
uniform sampler2D sand_color : source_color, hint_default_black, repeat_enable, filter_linear_mipmap;
uniform float color_amount = 1.0;       // 0 = black sand, 1 = the scan's colour, darkened
uniform float caustics = 1.0;           // caustic light strength
uniform float caustic_px = 330.0;       // on-screen size of one caustic tile
uniform float caustic_time = 0.0;       // caustic clock, advanced by the app at caustic_speed
uniform float caustic_speed = 0.35;     // (read by the app, so a speed change never jumps)
uniform float tile_px = 1800.0;          // on-screen size of one texture tile
uniform float plane_depth = 0.65;       // pan rate of the sand relative to the surface
uniform float bump = 1.15;               // normal map strength
uniform float refraction = 22.0;        // px of displacement per unit of surface slope
uniform float shine = 1.0;              // multiplier on the sand's gloss and highlights

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

// Tileable water caustics (after joltz0r's well-known iterative warp): bright webbed lines.
float caustic(vec2 uv, float time) {
	vec2 p = mod(uv * 6.2831853, 6.2831853) - 250.0;
	vec2 i = p;
	float c = 1.0;
	float inten = 0.005;
	for (int n = 0; n < 5; n++) {
		float t = time * (1.0 - (3.5 / float(n + 1)));
		i = p + vec2(cos(t - i.x) + sin(t + i.y), sin(t - i.y) + cos(t + i.x));
		c += 1.0 / length(vec2(p.x / (sin(i.x + t) / inten), p.y / (cos(i.y + t) / inten)));
	}
	c /= 5.0;
	c = 1.17 - pow(c, 1.4);
	return clamp(pow(abs(c), 8.0), 0.0, 2.0);
}

void fragment() {
	vec2 p = UV * surface_size;
	vec2 c = surface_size * 0.5;

	float h;
	vec2 grad;
	float energy;
	surface_waves(p, h, grad, energy);

	// --- The sand plane, below the water: slower pan, refracted by the ripples.
	vec2 pp = p + grad * refraction;
	vec2 q = (pp - c) + view_px * plane_depth;              // plane coordinates (px)
	vec2 uv = q / tile_px;

	vec3 tn = texture(sand_normal, uv, 0.8).rgb * 2.0 - 1.0;   // OpenGL normal map (y up); bias softens grain
	vec3 n = normalize(vec3(tn.x * bump, -tn.y * bump, max(tn.z, 0.05)));   // screen y points down
	float rough = texture(sand_rough, uv, 0.8).r;
	vec3 albedo = texture(sand_color, uv, 0.5).rgb * 0.17 * color_amount;   // darkened sand

	rough *= 0.6;                                            // a steady damp gloss

	// --- Lighting: dark glossy sand, key light from the top-left.
	vec3 light = normalize(vec3(-0.45, -0.6, 0.66));
	vec3 view = vec3(0.0, 0.0, 1.0);
	vec3 hv = normalize(light + view);
	float ndl = max(dot(n, light), 0.0);
	float gloss = mix(260.0, 24.0, rough);
	float spec = pow(max(dot(n, hv), 0.0), gloss) * mix(1.4, 0.18, rough);

	// A soft environment: the reflected view ray picks up a cool sky toward the light.
	vec3 r = reflect(-view, n);
	float sky = smoothstep(-0.2, 0.9, dot(normalize(r.xy + 1e-4), normalize(light.xy))) * length(r.xy);
	float wet_shine = 0.7 * shine;

	vec3 base = vec3(0.010, 0.011, 0.014) + albedo;
	vec3 col = base * (0.3 + 0.8 * ndl);                              // sand, lit from the top-left

	// Caustics: light focused by the water, drifting across the sand plane. Two layers at
	// different scales and speeds keep the web from looking tiled.
	float ct = caustic_time;
	float caust = caustic(q / caustic_px, ct) * 0.7 + caustic(q / (caustic_px * 1.7) + 0.37, ct * 0.8) * 0.45;
	caust = pow(caust, 1.3) * 1.4 * caustics * (0.55 + 0.45 * ndl);
	col += (base * 2.6 + vec3(0.06, 0.085, 0.1)) * caust;

	col += vec3(0.16, 0.19, 0.24) * sky * (1.0 - rough) * wet_shine;      // glossy sheen on the flanks
	col += vec3(0.85, 0.9, 1.0) * spec * wet_shine;                       // crest highlights
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
