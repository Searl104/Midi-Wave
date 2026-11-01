shader_type canvas_item;
// Abyssal theme: a thin glassy surface over endless dark water.
//
// Depth cues, near to far:
//  - Marine snow: layers of drifting motes that sink away from the surface forever. Each layer
//    recedes (shrinks toward the vanishing point, dims, turns bluer), fades out in the deep and
//    is reborn near the surface with new motes, so the fall never ends.
//  - Parallax: panning the view moves deep layers less than near ones. Beat spacing (the canvas
//    zoom) doesn't touch the depths: only panning moves them.
//  - Light shafts: layers of narrow beams from the surface that live and fade, sway and carry
//    drifting specks, converging on (and fading before) the vanishing point at the
//    centre of the window, where the dark is deepest.
//  - Bioluminescence: rare glints in the primary colours, pulsing slowly far below.
// The surface refracts everything under it, more with depth, and a passing wave briefly
// lights the snow beneath it.

#include "res://shaders/waves.gdshaderinc"

uniform vec2 surface_size = vec2(1280.0, 800.0);
uniform vec3 accent : source_color = vec3(0.18, 0.48, 1.0);
uniform vec2 view_px = vec2(0.0);     // pan: the world point at the window centre, less half the window
uniform float sink_speed = 0.018;     // layers per second the snow sinks
uniform float depth_scale = 7.0;      // how fast things shrink with depth
uniform float refraction = 16.0;      // px of displacement per unit of surface slope
uniform float snow_density = 1.0;     // multiplier on how many motes each layer keeps
uniform float glint_amount = 1.0;     // multiplier on how many bioluminescent glints appear
uniform float shaft_strength = 1.0;   // multiplier on the light shafts

const int LAYERS = 12;
const float CELL = 110.0;             // layer-space spacing of motes

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec2 hash2(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

// Smooth 1D value noise, periodic in `period`.
float noise1(float x, float period) {
	float i = floor(x);
	float f = fract(x);
	float a = hash(vec2(mod(i, period), 3.1));
	float b = hash(vec2(mod(i + 1.0, period), 3.1));
	return mix(a, b, f * f * (3.0 - 2.0 * f));
}

void fragment() {
	vec2 p = UV * surface_size;
	vec2 c = surface_size * 0.5;            // vanishing point
	float diag = length(surface_size) * 0.5;

	float h;
	vec2 grad;
	float energy;
	surface_waves(p, h, grad, energy);

	// --- The deep: a well of dark water, darkest at the vanishing point.
	float rn = length(p - c) / diag;        // 0 at the centre, 1 at the corners
	vec3 abyss = vec3(0.004, 0.007, 0.014);
	vec3 shallows = vec3(0.026, 0.05, 0.075);
	vec3 col = mix(abyss, shallows, smoothstep(0.05, 1.0, rn));

	// --- Light shafts from the surface, falling away into the deep. Three layers at different
	// depths: each is a fan of narrow beams converging on the vanishing point. Beams are born,
	// brighten and fade out on their own slow clocks, sway with the swell above, and carry
	// drifting specks of light down their length, so the fan never sits still. Deeper layers
	// pan less (parallax), start further in, and are dimmer and bluer; every beam fades out
	// before it reaches the dark centre, which reads as distance rather than glare.
	float t = TIME;
	vec2 pr = p + grad * refraction * 0.6;
	vec3 shaft_col = vec3(0.0);
	for (int L = 0; L < 3; L++) {
		float fl = float(L);
		float depth = 0.25 + 0.3 * fl;                       // 0.25, 0.55, 0.85
		float near = 1.0 - depth;
		// Parallax: near layers shift and turn more as the view pans.
		vec2 rv = pr - c + view_px * 0.12 * near;
		float rn2 = length(rv) / diag;
		float turn = view_px.x / diag * 0.05 * near;
		float sway = 0.006 * sin(t * 0.21 + fl * 2.1) + 0.004 * sin(t * 0.13 + fl * 4.7);
		float n_beams = 22.0 + 9.0 * fl;
		float a = (atan(rv.y, rv.x) / 6.2831853 + 0.5 + turn + sway) * n_beams;
		float id = mod(floor(a), n_beams);
		float f = fract(a) - 0.5;
		float h1 = hash(vec2(id, fl + 1.3));
		float h2 = hash(vec2(id, fl + 7.9));
		float h3 = hash(vec2(id, fl + 13.1));
		// Each beam's own life: fades in and out over tens of seconds.
		float life = noise1(t * (0.025 + 0.05 * h3) + h1 * 97.0, 4096.0);
		life = smoothstep(0.45, 0.95, life);
		// A narrow beam with soft edges, off-centre in its slot.
		float w = mix(0.14, 0.38, h2);
		float beam = smoothstep(w, 0.0, abs(f - (h1 - 0.5) * 0.4));
		beam *= beam;                                      // soft, diffuse edges
		// Starts near the edge (the surface), reaches less far in the deeper the layer.
		float reach = smoothstep(0.2 + 0.25 * depth, 0.9 + 0.15 * depth, rn2);
		// Specks drifting down the beam toward the deep.
		float specks = 0.55 + 0.45 * noise1(rn2 * 26.0 + t * (0.35 + 0.25 * h3) + id * 3.7, 4096.0);
		float k = beam * life * reach * specks * (0.35 + 0.65 * near);
		shaft_col += mix(vec3(0.24, 0.42, 0.58), vec3(0.10, 0.22, 0.45), depth) * k;
	}
	// The swell above makes the shafts flicker a little where ripples pass.
	shaft_col *= 1.0 + clamp(energy, 0.0, 1.5) * 0.6;
	col += shaft_col * 0.62 * shaft_strength;

	// --- Marine snow, sinking forever.
	float wave_light = clamp(energy, 0.0, 1.5);
	for (int i = 0; i < LAYERS; i++) {
		float fi = float(i);
		float phase = fi / float(LAYERS) + t * sink_speed;
		float z = fract(phase);                       // 0 = just under the surface, 1 = lost below
		float gen = floor(phase);                     // new motes each time a layer is reborn
		float s = 1.0 / (1.0 + z * depth_scale);      // shrink with depth
		float m = s;                                  // on-screen magnification of this layer
		float fade = smoothstep(0.0, 0.12, z) * pow(1.0 - z, 1.6);

		// Refraction grows with depth; parallax shrinks with it.
		vec2 pp = p + grad * refraction * (0.3 + 1.7 * z);
		vec2 q = (pp - c) / m + view_px * s / m;
		q += vec2(sin(t * 0.07 + fi * 1.7), cos(t * 0.05 + fi * 2.3)) * 24.0;   // slow drift

		vec2 cell = floor(q / CELL);
		vec2 seed = cell + vec2(fi * 17.0, gen * 31.0);
		vec2 rnd = hash2(seed);
		// Deep layers pack more cells onto the screen; thin them so density stays even.
		float keep = 0.5 * snow_density * pow(s, 1.7);
		float present = step(1.0 - keep, hash(seed + 5.3));
		vec2 local = (fract(q / CELL) - 0.5 - (rnd - 0.5) * 0.7) * CELL * m;   // screen px
		float d = length(local);

		float size = mix(1.1, 2.6, rnd.x) * mix(1.3, 0.45, z) + 0.35;
		// Motes just under the surface are out of focus: bigger, softer, fainter.
		float blur = 5.0 * (1.0 - smoothstep(0.0, 0.3, z)) * rnd.y;
		float mote = smoothstep(size + blur, 0.0, d) * size / (size + blur * 0.6)
				+ 0.12 * smoothstep(size * 3.0, 0.0, d);
		vec3 tint = mix(vec3(0.72, 0.82, 0.92), vec3(0.18, 0.34, 0.6), z);
		float lit = 0.22 + wave_light * (1.0 - z) * 1.2;
		col += tint * mote * present * fade * lit;

		// Bioluminescence: a rare glint, pulsing, in one of the three primaries.
		float g = hash(seed + 11.7);
		if (g > 1.0 - 0.05 * glint_amount * pow(s, 1.7) && z > 0.2) {
			float pick = hash(seed + 23.9);
			vec3 hue = pick < 0.34 ? vec3(0.18, 0.48, 1.0) : (pick < 0.67 ? vec3(1.0, 0.25, 0.27) : vec3(1.0, 0.82, 0.2));
			float pulse = 0.5 + 0.5 * sin(t * (0.6 + rnd.y * 0.9) + g * 40.0);
			pulse = pulse * pulse;
			float glow = smoothstep(size * 7.0, 0.0, d);
			col += hue * glow * glow * pulse * fade * 0.55 + hue * smoothstep(size * 1.4, 0.0, d) * pulse * fade * 0.6;
		}
	}

	// --- The surface: a thin film of glass catching the light.
	vec3 n = normalize(vec3(-grad * 0.55, 1.0));
	vec3 light = normalize(vec3(-0.45, -0.6, 0.66));   // screen y points down
	float diff = dot(n, light) - light.z;
	float spec = pow(max(dot(reflect(-light, n), vec3(0.0, 0.0, 1.0)), 0.0), 48.0);
	float sheen = smoothstep(1.4, 0.0, length(UV - vec2(0.22, 0.12)));
	col += vec3(0.05, 0.06, 0.075) * sheen * 0.6;
	col += vec3(0.7, 0.8, 0.95) * diff * 0.42;
	col += vec3(0.9, 0.95, 1.0) * spec * 0.85;
	col += accent * max(h, 0.0) * 0.2;

	col += (hash(p + fract(t)) - 0.5) * 0.007;    // grain so the dark doesn't band
	COLOR = vec4(col, 1.0);
}
