class_name SequenceModifier
extends Modifier
## A list of On and Off steps. Each hit takes the next step: an Off step silences the sound and the
## pulse, and the list repeats. It says only whether the next activation sounds, as timing belongs
## to the surface. Stop returns it to step 1.

const MAX_STEPS := 16
const DOT_GAP := 0.3               ## angle between the dots over the note
const DOT_RADIUS := Note.RADIUS + Modifier.RING + 7.0

var steps: Array = [true, false]
var pos := 0                       ## the step the next hit takes


func kind() -> String:
	return "sequence"


func ring_id() -> String:
	return "sequence_settings"


func has_ring() -> bool:
	return true


## Saved Rests and Toggles load as the same pattern, turned to start where they started.
func load_dict(d: Dictionary, _p: Vector2) -> void:
	if d.get("steps") is Array and not d["steps"].is_empty():
		steps = d["steps"].slice(0, MAX_STEPS).map(func(s: Variant) -> bool: return bool(s))
		return
	var value := clampi(int(d.get("value", 1)), 1, MAX_STEPS - 1)
	var saved: Variant = d.get("start", 0)
	var left: int = clampi((0 if saved else 1) if saved is bool else int(saved), 0, value)
	steps = []
	for i in value + 1:
		steps.append((i + left) % (value + 1) == 0)


func to_dict() -> Dictionary:
	return {"kind": kind(), "steps": steps.duplicate()}


func live_state() -> Array:
	return [pos]


func restore_state(state: Array) -> void:
	pos = state[0] % steps.size()


func tab_contains(surface: WaveSurface, note: Note, at: Vector2) -> bool:
	return Rect2(_tab_centre(surface, note) - Vector2(12, 7), Vector2(24, 14)).has_point(at)


## New steps start On. Removing steps forgets them.
func set_count(count: int) -> void:
	var old := steps.size()
	steps.resize(clampi(count, 1, MAX_STEPS))
	for i in range(old, steps.size()):
		steps[i] = true
	pos %= steps.size()
	flip = 1.0


func set_step(index: int, on: bool) -> void:
	if index >= 0 and index < steps.size():
		steps[index] = on
		flip = 1.0


func passes_hit() -> bool:
	var on: bool = steps[pos]
	pos = (pos + 1) % steps.size()
	flip = 1.0
	return on


func reset() -> void:
	pos = 0


func resting() -> bool:
	return not steps[pos]


func describe() -> String:
	return " · sequence, step %d of %d" % [pos + 1, steps.size()]


func dims_label() -> bool:
	return resting()


func draw(surface: WaveSurface, p: Vector2, col: Color) -> void:
	super.draw(surface, p, col)
	_draw_dots(surface, p)


## An arc of dots over the note, turned to keep the next step at the top. Steps to come run
## clockwise from it, and those just played sit behind it.
func _draw_dots(surface: WaveSurface, p: Vector2) -> void:
	var count := steps.size()
	for i in count:
		var ahead := posmod(i - pos, count)
		if ahead > count / 2:
			ahead -= count
		var at := p + Vector2.from_angle(-PI / 2.0 + (ahead + flip) * DOT_GAP) * DOT_RADIUS
		var ink := Palette.BLUE if steps[i] else Palette.TEXT_DIM
		if i == pos:
			surface.draw_circle(at, 4.0, Palette.TEXT)
		surface.draw_circle(at, 3.0 if i == pos else 2.3, ink)


## Ripples spreading out, or still water when the next step is Off.
func _draw_icon(surface: WaveSurface, c: Vector2, ink: Color) -> void:
	surface.draw_circle(c, 1.6, ink)
	if resting():
		surface.draw_line(c + Vector2(-9, 0), c + Vector2(-3.5, 0), ink, 1.0, true)
		surface.draw_line(c + Vector2(3.5, 0), c + Vector2(9, 0), ink, 1.0, true)
		return
	var grow := 1.0 + 0.6 * flip
	surface.draw_arc(c, 3.5 * grow, -0.9, 0.9, 10, Color(ink, 1.0), 1.0, true)
	surface.draw_arc(c, 3.5 * grow, PI - 0.9, PI + 0.9, 10, Color(ink, 1.0), 1.0, true)
	surface.draw_arc(c, 6.0 * grow, -0.75, 0.75, 12, Color(ink, 0.6), 1.0, true)
	surface.draw_arc(c, 6.0 * grow, PI - 0.75, PI + 0.75, 12, Color(ink, 0.6), 1.0, true)
