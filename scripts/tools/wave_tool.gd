class_name WaveTool
extends Tool
## Waves and note triggers. The layout is locked while it's in use.


func tool_id() -> String:
	return "wave"


func title() -> String:
	return "Wave"


func edits_layout() -> bool:
	return false


## Plays whatever is at a screen position: a note or relay, else a new wave there.
func play_at(pos: Vector2) -> void:
	var hit := surface.note_at(pos)
	if hit != -1:
		surface.click_note(hit)
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
