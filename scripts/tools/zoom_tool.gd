class_name ZoomTool
extends NavTool
## Drag right or up to zoom in, left or down to zoom out, about the point first pressed.

const SPEED := 0.006               ## zoom change per pixel dragged


func tool_id() -> String:
	return "zoom"


func title() -> String:
	return "Zoom"


func cursor() -> Control.CursorShape:
	return Control.CURSOR_VSIZE


func _dragged(delta: Vector2) -> void:
	surface.zoom_at(_start, exp((delta.x - delta.y) * SPEED))


## A magnifying glass.
func draw_icon(canvas: CanvasItem, c: Vector2, ink: Color) -> void:
	var lens := c + Vector2(-2, -2)
	canvas.draw_arc(lens, 7.0, 0.0, TAU, 28, ink, 2.0, true)
	canvas.draw_line(lens + Vector2(5.2, 5.2), c + Vector2(9, 9), ink, 3.0, true)
