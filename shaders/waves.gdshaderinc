// Shared ripple maths for the water shaders.
// waves[i] = (origin.x, origin.y, radius, amplitude) in pixels / 0-1.

const int MAX_WAVES = 64;   // must match WaveSurface.MAX_WAVES

uniform int wave_count = 0;
uniform vec4 waves[MAX_WAVES];
uniform float ring_width = 34.0;

// Height `h`, its gradient `grad` and the summed ring envelope `energy` at pixel `p`.
void surface_waves(vec2 p, out float h, out vec2 grad, out float energy) {
	h = 0.0;
	grad = vec2(0.0);
	energy = 0.0;
	for (int i = 0; i < MAX_WAVES; i++) {
		if (i >= wave_count) { break; }
		vec4 w = waves[i];
		vec2 d = p - w.xy;
		float dist = length(d) + 0.001;
		float x = (dist - w.z) / ring_width;
		if (abs(x) > 3.5) { continue; }
		float env = exp(-x * x * 1.6);
		float s = sin(x * 5.5);
		h += w.w * env * s;
		energy += w.w * env;
		float dh = w.w * env * (cos(x * 5.5) * 5.5 - s * 3.2 * x);
		grad += dh * d / dist;
	}
}
