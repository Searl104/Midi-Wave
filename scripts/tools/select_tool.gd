class_name SelectTool
extends Tool
## Picks objects and emitter diamonds, one at a time or with a box. Moving them is ObjectDrag.

var box_active := false
var _box_add := false              # this box adds to the selection
var _box_start := Vector2.ZERO
var _box_end := Vector2.ZERO


func section() -> int:
	return 1


func tool_id() -> String:
	return "select"


func title() -> String:
	return "Select"


func deactivate() -> void:
	box_active = false


## Selects an object (`emitter` = its diamond). With `add` it's toggled in the selection; a pick
## outside the selection replaces it.
func pick(id: int, emitter: bool = false, add: bool = false) -> void:
	var sel := surface.selection
	var ids: Dictionary = sel.emitters if emitter else sel.notes
	if add:
		if ids.has(id):
			ids.erase(id)
		else:
			ids[id] = true
	elif not ids.has(id):
		sel.clear()
		ids[id] = true


func begin_box(pos: Vector2, add: bool = false) -> void:
	box_active = true
	_box_add = add
	_box_start = pos
	_box_end = pos


func extend_box(pos: Vector2) -> void:
	_box_end = pos


## A box selects what's inside it; one too small to be a drag is a click, which clears.
func end_box(pos: Vector2, add: bool = false) -> void:
	box_active = false
	_box_add = _box_add or add
	_box_end = pos
	if _box_start.distance_to(_box_end) > ObjectDrag.THRESHOLD:
		surface.selection.select_in_rect(Rect2(_box_start, _box_end - _box_start), _box_add)
	elif not _box_add:
		surface.selection.clear()


func draw_overlay(canvas: WaveSurface) -> void:
	if box_active:
		var box := Rect2(_box_start, _box_end - _box_start).abs()
		canvas.draw_rect(box, Color(Palette.ACCENT, 0.08))
		canvas.draw_rect(box, Color(Palette.ACCENT.lightened(0.3), 0.8), false, 1.0)


func draw_icon(canvas: CanvasItem, c: Vector2, ink: Color) -> void:
	var a := c + Vector2(-5, -9)
	canvas.draw_colored_polygon(PackedVector2Array([a, a + Vector2(0, 16), a + Vector2(4, 12), a + Vector2(7, 18),
			a + Vector2(9.5, 17), a + Vector2(6.5, 11), a + Vector2(11.5, 11)]), ink)
