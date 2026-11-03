class_name RestModifier
extends Modifier
## After firing, sits out `value` hits: Rest 1 plays hits 1, 3, 5. Resting silences both the sound
## and the pulse, and every hit counts down. It can start partway through its count, which offsets
## it against other notes.

const MAX_VALUE := 8

var value := 1                     ## hits it sits out after firing, 1-8
var left := 0                      ## hits still to sit out; 0 = the next hit fires
var start_left := 0                ## what Stop returns `left` to


func kind() -> String:
	return "rest"


func ring_id() -> String:
	return "rest_settings"


func has_ring() -> bool:
	return true


## Reads `start` as a count, or as an old toggle's bool, where Off was one hit left.
func load_dict(d: Dictionary, _p: Vector2) -> void:
	value = clampi(int(d.get("value", 1)), 1, MAX_VALUE)
	var saved: Variant = d.get("start", 0)
	set_start_left((0 if saved else 1) if saved is bool else int(saved))


func to_dict() -> Dictionary:
	return {"kind": kind(), "value": value, "start": start_left}


func live_state() -> Array:
	return [left]


func restore_state(state: Array) -> void:
	left = mini(state[0], value)


func tab_contains(surface: WaveSurface, note: Note, at: Vector2) -> bool:
	return Rect2(_tab_centre(surface, note) - Vector2(12, 7), Vector2(24, 14)).has_point(at)


## Keeps both counts within the new value.
func set_value(v: int) -> void:
	value = clampi(v, 1, MAX_VALUE)
	start_left = mini(start_left, value)
	left = mini(left, value)
	flip = 1.0


## A count the user sets is its intended start: sets current and start.
func set_start_left(count: int) -> void:
	start_left = clampi(count, 0, value)
	left = start_left
	flip = 1.0


func passes_hit() -> bool:
	flip = 1.0
	if left > 0:
		left -= 1
		return false
	left = value
	return true


func reset() -> void:
	left = start_left


func save_start() -> void:
	start_left = left


func resting() -> bool:
	return left > 0


func off_start() -> bool:
	return left != start_left


func starts_ready() -> bool:
	return start_left == 0


func describe() -> String:
	var text := " · rest %d" % value
	if left > 0:
		text += ", %d left" % left
	if off_start():
		text += ", starts with %d left" % start_left
	return text


func dims_label() -> bool:
	return resting()


## Ripples spreading out when ready, and the hits left while resting.
func _draw_icon(surface: WaveSurface, c: Vector2, ink: Color) -> void:
	if resting():
		surface.draw_string(surface.get_theme_default_font(), c + Vector2(-12, 4), str(left),
				HORIZONTAL_ALIGNMENT_CENTER, 24, 11, Palette.TEXT)
		return
	var grow := 1.0 + 0.6 * flip
	surface.draw_circle(c, 1.6, ink)
	surface.draw_arc(c, 3.5 * grow, -0.9, 0.9, 10, Color(ink, 1.0), 1.0, true)
	surface.draw_arc(c, 3.5 * grow, PI - 0.9, PI + 0.9, 10, Color(ink, 1.0), 1.0, true)
	surface.draw_arc(c, 6.0 * grow, -0.75, 0.75, 12, Color(ink, 0.6), 1.0, true)
	surface.draw_arc(c, 6.0 * grow, PI - 0.75, PI + 0.75, 12, Color(ink, 0.6), 1.0, true)
