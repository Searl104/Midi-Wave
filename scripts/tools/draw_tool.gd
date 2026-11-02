class_name DrawTool
extends Tool
## Places the current type on grid points; a stroke places one per division along its path, and
## is one undo step. Picking Draw again switches between Notes and Relays.

var place_type: int = SurfaceObject.Mode.NOTE
var _active := false
var _points: Array = []            # world points placed in this stroke


func tool_id() -> String:
	return "draw"


func title() -> String:
	return "Draw"


func repick() -> void:
	toggle_type()


func deactivate() -> void:
	end_stroke()


func toggle_type() -> void:
	place_type = SurfaceObject.Mode.RELAY if place_type == SurfaceObject.Mode.NOTE else SurfaceObject.Mode.NOTE


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
	surface.add_object(w, Scales.quantize(surface.last_pitch, Settings.root_note, Settings.scale_name), surface.last_channel, place_type)
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
	# What it places: Note = solid dot, Relay = hollow ring with a diamond.
	var b := c + Vector2(9, 9)
	if place_type == SurfaceObject.Mode.RELAY:
		canvas.draw_arc(b, 4.0, 0.0, TAU, 16, Palette.YELLOW, 1.5, true)
		canvas.draw_colored_polygon(PackedVector2Array([b + Vector2(0, -2), b + Vector2(2, 0), b + Vector2(0, 2), b + Vector2(-2, 0)]), Palette.YELLOW)
	else:
		canvas.draw_circle(b, 4.0, Palette.ACCENT.lightened(0.2))
