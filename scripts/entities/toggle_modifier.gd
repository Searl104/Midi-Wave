class_name ToggleModifier
extends Modifier
## Acts on its current state, then flips: starting on, hits 1, 3, 5 play. Off silences both the
## sound and the pulse. A hit while off still flips it.


func kind() -> String:
	return "toggle"


func passes_hit() -> bool:
	var active := on
	on = not on
	flip = 1.0
	return active


func describe() -> String:
	var text := " · toggle %s" % ("on" if on else "off")
	if on != start:
		text += ", starts %s" % ("on" if start else "off")
	return text


func dims_label() -> bool:
	return not on


## A ripple: a dot with ripples spreading out when on, still water when off.
func _draw_icon(surface: WaveSurface, c: Vector2, ink: Color) -> void:
	surface.draw_circle(c, 1.6, ink)
	if on:
		var grow := 1.0 + 0.6 * flip
		surface.draw_arc(c, 3.5 * grow, -0.9, 0.9, 10, Color(ink, 1.0), 1.0, true)
		surface.draw_arc(c, 3.5 * grow, PI - 0.9, PI + 0.9, 10, Color(ink, 1.0), 1.0, true)
		surface.draw_arc(c, 6.0 * grow, -0.75, 0.75, 12, Color(ink, 0.6), 1.0, true)
		surface.draw_arc(c, 6.0 * grow, PI - 0.75, PI + 0.75, 12, Color(ink, 0.6), 1.0, true)
	else:
		surface.draw_line(c + Vector2(3.5, 0), c + Vector2(7.5, 0), ink, 1.0, true)
		surface.draw_line(c - Vector2(3.5, 0), c - Vector2(7.5, 0), ink, 1.0, true)
