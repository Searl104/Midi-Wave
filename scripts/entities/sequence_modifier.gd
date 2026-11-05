class_name SequenceModifier
extends Modifier
## A list of On and Off steps. Each hit takes the next step: an Off step silences the sound and the
## pulse, and the list repeats. It says only whether the next activation sounds, as timing belongs
## to the surface. Stop returns it to step 1.

const MAX_STEPS := 16
const DOT_GAP := 7.0               ## px between the dots beside the tab
const DOT_START := 10.0            ## px from the tab's centre to step zero of the row
const DOT_HIDDEN := 0.4            ## a dot this close to the icon is behind the tab
const DOT_FADE := 4.0              ## a dot this many steps out has faded away
const SLIDE_RATE := 14.0           ## how quickly the dots settle

var steps: Array = [true, false]
var pos := 0                       ## the step the next hit takes
var slide := 0.0                   ## steps the dots still have to travel
var _slide_speed := 0.0


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
	slide += 1.0                       # added, so a hit during a slide keeps the dots moving
	flip = 1.0
	return on


func reset() -> void:
	pos = 0
	slide = 0.0
	_slide_speed = 0.0


## The dots ease toward their places: a critically damped spring has no sudden starts or stops.
func tick(delta: float) -> void:
	super.tick(delta)
	var dt := minf(delta, 0.05)
	_slide_speed += (-2.0 * SLIDE_RATE * _slide_speed - SLIDE_RATE * SLIDE_RATE * slide) * dt
	slide += _slide_speed * dt


func resting() -> bool:
	return not steps[pos]


func describe() -> String:
	return " · sequence, step %d of %d" % [pos + 1, steps.size()]


func dims_label() -> bool:
	return resting()


func draw(surface: WaveSurface, p: Vector2, col: Color) -> void:
	super.draw(surface, p, col)
	_draw_dots(surface, p)


## A carousel of dots through the tab: steps just played on the left, steps to come on the right,
## and the next step at the icon, which shows its state. Dots fade with distance, so three show
## each side, and slide left on each hit.
func _draw_dots(surface: WaveSurface, p: Vector2) -> void:
	var count := steps.size()
	var row := p + Vector2(0, Note.RADIUS + Modifier.RING + 4.0)
	for i in count:
		var ahead := posmod(i - pos, count)
		if ahead > count / 2:
			ahead -= count
		var place := ahead + slide
		var far := absf(place)
		if far < DOT_HIDDEN or far >= DOT_FADE:
			continue
		var at := row + Vector2(signf(place) * (DOT_START + far * DOT_GAP), 0)
		var ink: Color = Palette.BLUE if steps[i] else Palette.TEXT_DIM
		surface.draw_circle(at, 2.2, Color(ink, minf((DOT_FADE - far) / (DOT_FADE - 1.0), (far - DOT_HIDDEN) / DOT_HIDDEN)))


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
