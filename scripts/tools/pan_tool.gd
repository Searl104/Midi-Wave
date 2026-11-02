class_name PanTool
extends NavTool
## Drag to move the view.


func tool_id() -> String:
	return "pan"


func title() -> String:
	return "Pan"


func cursor() -> Control.CursorShape:
	return Control.CURSOR_DRAG


func _dragged(delta: Vector2) -> void:
	surface.pan_by(-delta)


## An open hand.
func draw_icon(canvas: CanvasItem, c: Vector2, ink: Color) -> void:
	for f in [[-6.0, -2.0, 1.0], [-2.0, -8.0, 1.0], [2.0, -9.0, 1.0], [6.0, -6.0, 1.0]]:
		canvas.draw_line(c + Vector2(f[0], 2), c + Vector2(f[0], f[1]), ink, 3.0, true)
	canvas.draw_line(c + Vector2(-6, 3), c + Vector2(-10, -1), ink, 3.0, true)
	canvas.draw_circle(c + Vector2(0, 5), 7.0, ink)
