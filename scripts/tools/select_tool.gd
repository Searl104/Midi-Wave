class_name SelectTool
extends Tool
## Select and Move. A click picks a note or diamond (Shift adds or removes), a drag moves it and
## the rest of the selection (Alt places freely), and a drag on empty space draws a box. Ctrl-drag
## from a diamond sets its relay's reach. Moving itself is ObjectDrag.

var box_active := false
var _box_add := false              # this box adds to the selection
var _box_start := Vector2.ZERO
var _box_end := Vector2.ZERO
var _narrow_to: Array = []         # [kind, id]: on a release without a move, select only this


func section() -> int:
	return 1


func tool_id() -> String:
	return "select"


func title() -> String:
	return "Select and Move"


func deactivate() -> void:
	box_active = false
	_narrow_to = []


func handle_input(event: InputEvent) -> bool:
	var mb := event as InputEventMouseButton
	if mb:
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return false
		if mb.pressed:
			_press(mb)
		else:
			_release(mb)
		return true
	var mm := event as InputEventMouseMotion
	if mm:
		_motion(mm)
		return box_active or surface.drag.active()
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		return _key(key)
	return false


func _press(mb: InputEventMouseButton) -> void:
	var hit := surface.pick_at(mb.position)
	if mb.ctrl_pressed:
		if not hit.is_empty() and hit[0] == "emitter":
			surface.drag.begin(hit[1], "range", mb.position)
		return
	if hit.is_empty():
		begin_box(mb.position, mb.shift_pressed)
		return
	var emitter: bool = hit[0] == "emitter"
	var sel := surface.selection
	var ids: Dictionary = sel.emitters if emitter else sel.notes
	_narrow_to = []
	if not mb.shift_pressed and ids.has(hit[1]) and sel.count() > 1:
		_narrow_to = hit
	else:
		pick(hit[1], emitter, mb.shift_pressed)
	if ids.has(hit[1]):
		surface.drag.begin(hit[1], hit[0], mb.position)


func _release(mb: InputEventMouseButton) -> void:
	if box_active:
		end_box(mb.position)
		return
	var moved := surface.drag.end()
	if not moved and not _narrow_to.is_empty():
		surface.selection.clear()
		pick(_narrow_to[1], _narrow_to[0] == "emitter")
	_narrow_to = []


func _motion(mm: InputEventMouseMotion) -> void:
	if box_active:
		extend_box(mm.position)
	elif surface.drag.active():
		surface.drag.pointer_to(mm.position, mm.alt_pressed)
	else:
		surface.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND \
				if not surface.pick_at(mm.position).is_empty() else Control.CURSOR_ARROW


func _key(key: InputEventKey) -> bool:
	var sel := surface.selection
	match key.keycode:
		KEY_ESCAPE:
			if sel.has_any():
				sel.clear()
				return true
		KEY_DELETE, KEY_BACKSPACE:
			if not sel.notes.is_empty():
				surface.delete_selection()
				return true
		KEY_C:
			if key.ctrl_pressed:
				sel.copy()
				return true
		KEY_V:
			if key.ctrl_pressed:
				sel.paste_at(surface.pointer())
				return true
	return false


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
