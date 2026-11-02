class_name DrawTool
extends Tool
## Places notes on grid points; a stroke places one per division along its path, and is one undo
## step.

var _active := false
var _points: Array = []            # world points placed in this stroke


func section() -> int:
	return 1


func tool_id() -> String:
	return "draw"


func title() -> String:
	return "Draw"


func deactivate() -> void:
	end_stroke()


func begin_stroke(pos: Vector2) -> void:
	surface.selection.clear()
	_active = true
	_points = []
	surface.history.set_stroke(true)
	extend_stroke(pos)


func extend_stroke(screen_pos: Vector2) -> void:
	if not _active:
		return
	var w := surface.snapping.grid_snap(surface.to_world(screen_pos))
	var gap := Snapping.ring_step() * 0.99      # at most one object per division along a stroke
	for q in _points:
		if (q as Vector2).distance_to(w) < gap:
			return
	if not _points.is_empty() and surface.note_at(surface.to_screen(w)) != -1:
		return                                  # don't stack onto existing notes mid-stroke
	_points.append(w)
	surface.add_object(w, Scales.quantize(surface.last_pitch, Settings.root_note, Settings.scale_name), surface.last_channel)
	surface.save_notes()


func end_stroke() -> void:
	if _active:
		_active = false
		_points = []
		surface.history.set_stroke(false)


func draw_icon(canvas: CanvasItem, c: Vector2, ink: Color) -> void:
	var d := Vector2(1, -1).normalized()
	var nrm := Vector2(d.y, -d.x)
	var tip := c + Vector2(-8, 8)
	var back := tip + d * 18.0
	canvas.draw_colored_polygon(PackedVector2Array([tip, tip + d * 5.0 + nrm * 3.0, back + nrm * 3.0,
			back - nrm * 3.0, tip + d * 5.0 - nrm * 3.0]), ink)
