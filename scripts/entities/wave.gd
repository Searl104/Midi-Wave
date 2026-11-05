class_name Wave
extends RefCounted
## One expanding ring. It hits each object at most once, and never the relay that fired it.

const FADE_IN := 40.0              ## world units over which a new wave fades in
const REACH_TOLERANCE := 0.5       ## world units: an object exactly at the reach counts as reached

var origin := Vector2.ZERO         ## world units
var r := 0.0
var strength := 1.0
var source := -1                   ## id of the relay that fired it, -1 = the user
var own_reach := 0.0               ## 0 = the global Reach
var hits: Dictionary = {}


func _init(from: Vector2, wave_strength: float, source_id: int, reach_override: float = 0.0) -> void:
	origin = from
	strength = wave_strength
	source = source_id
	own_reach = reach_override


## Amplitude at distance `d` from a source: strength at 0, falling to 0 at `reach` (the global
## Reach when not given).
static func amplitude(wave_strength: float, d: float, reach_limit: float = -1.0) -> float:
	var limit := Settings.wave_range if reach_limit <= 0.0 else reach_limit
	var x := clampf(1.0 - d / maxf(limit, 1.0), 0.0, 1.0)
	return wave_strength * pow(x, Settings.falloff_curve)


func reach() -> float:
	return own_reach if own_reach > 0.0 else Settings.wave_range


func grow(distance: float) -> void:
	r += distance


func finished() -> bool:
	return r >= reach()


## Hits `o` if this wave has just reached it. A wave that starts on an object hits it at once.
## Hits land on frames, so the wave is usually a little past `o`: that overshoot goes with the hit.
func try_hit(surface: WaveSurface, o: Note, now: int, spawned: Array) -> void:
	if o.id == source or hits.has(o.id):
		return
	var d := origin.distance_to(o.pos)
	if d > reach() + REACH_TOLERANCE:
		return                       # past the end: a slow frame's step doesn't stretch the reach
	if r >= d or d <= Note.RADIUS:
		hits[o.id] = true
		o.hit(surface, Wave.amplitude(strength, d, reach()), now, spawned, maxf(r - d, 0.0))


func _level() -> float:
	return Wave.amplitude(strength, r, reach()) * clampf(r / FADE_IN, 0.0, 1.0)


## Data for water.gdshader: (x, y, radius, amplitude at that radius) in screen px.
func shader_value(surface: WaveSurface) -> Vector4:
	var o := surface.to_screen(origin)
	return Vector4(o.x, o.y, r * surface.z(), _level())


func draw(surface: WaveSurface) -> void:
	var o := surface.to_screen(origin)
	var a := _level()
	var ring_col := Palette.ACCENT if source == -1 else Palette.YELLOW
	var sr := r * surface.z()
	surface.draw_arc(o, sr, 0.0, TAU, 160, Color(ring_col, a * 0.7), 2.0, true)
	if sr > 14.0:
		surface.draw_arc(o, sr - 12.0, 0.0, TAU, 160, Color(1, 1, 1, a * 0.12), 1.0, true)
