class_name TapTool
extends Tool
## Plays the surface. A left click on empty space starts a wave; on an object it taps just that
## object, with no wave. The layout is locked while it's in use.


func tool_id() -> String:
	return "tap"


func title() -> String:
	return "Tap"


func edits_layout() -> bool:
	return false


func handle_input(event: InputEvent) -> bool:
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		tap_at(mb.position)
		return true
	return false


## Taps the object at a screen position, or starts a wave there if there's none.
func tap_at(pos: Vector2) -> void:
	var hit := surface.get_note(surface.note_at(pos))
	if hit:
		hit.tap(surface)
	else:
		surface.spawn_wave(pos)


## A teardrop: a circle with a point, the sides tangent to it.
func draw_icon(canvas: CanvasItem, c: Vector2, ink: Color) -> void:
	var ctr := c + Vector2(0, 3)
	var r := 6.5
	var tip := ctr + Vector2(0, -13.0)
	var pts := PackedVector2Array([tip])
	var a0 := -PI / 2.0 + acos(r / 13.0)
	var a1 := -PI / 2.0 - acos(r / 13.0) + TAU
	for k in 25:
		var a := lerpf(a0, a1, k / 24.0)
		pts.append(ctr + Vector2(cos(a), sin(a)) * r)
	canvas.draw_colored_polygon(pts, ink)
