class_name GridTool
extends Tool
## Sets grid origins. Click a note or remote diamond to add it, click again to remove it, and drag
## from one to set its grid's reach (Alt: unsnapped). Dragged back onto the origin, a grid returns
## to its automatic reach. Origins are marked while the tool is active.

var _origin: Array = []            # [note, for_emitter] under the press, or empty
var _start := Vector2.ZERO
var _dragging := false


func tool_id() -> String:
	return "grid"


func title() -> String:
	return "Grid"


func section() -> int:
	return 1


func has_options() -> bool:
	return true


func build_options(box: VBoxContainer) -> void:
	box.add_child(PanelBuilder.button("Clear All", clear_all, "Removes every grid. This can be undone."))
	PanelBuilder.section(box, "SNAPPING", Palette.ACCENT)
	PanelBuilder.check(box, "Snap to grids", "snap_enabled")
	PanelBuilder.slider(box, "Snap distance", "snap_distance", 4.0, 30.0, 1.0, func(v: float) -> String: return "%d px" % v)
	PanelBuilder.check(box, "Snap to spokes", "snap_spokes")
	PanelBuilder.check(box, "Snap to centres", "snap_centres")
	PanelBuilder.section(box, "GUIDES", Palette.YELLOW)
	PanelBuilder.pick(box, "Spokes per grid", "spoke_count", Settings.SPOKE_OPTIONS,
			Settings.SPOKE_OPTIONS.map(func(c: int) -> String: return "None" if c == 0 else str(c)))
	PanelBuilder.pick(box, "Guides extend to", "guides_to_edge", [true, false], ["Window edge", "Wave reach"])
	PanelBuilder.check(box, "Division rings", "guide_divisions")
	PanelBuilder.slider(box, "Guide brightness", "guide_brightness", 0.3, 1.5, 0.05, func(v: float) -> String: return "%d%%" % roundi(v * 100))


func clear_all() -> void:
	var cleared := surface.snapping.clear_grids()
	surface.tools.notice.emit("Grids cleared" if cleared > 0 else "No grids on")


func deactivate() -> void:
	if _dragging:
		surface.save_notes()
	_origin = []
	_dragging = false


## The origin at a screen position: [note, for_emitter], or [] if none. Docked diamonds and dim
## handles aren't origins.
func origin_at(pos: Vector2) -> Array:
	var id := surface.note_at(pos)
	if id != -1:
		return [surface.get_note(id), false]
	for o in surface.notes:
		var e: Emitter = o.emitter()
		if e and not e.attached and pos.distance_to(surface.to_screen(e.pos)) <= Emitter.HANDLE_RADIUS + 4.0:
			return [o, true]
	return []


func handle_input(event: InputEvent) -> bool:
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_origin = origin_at(mb.position)
			_start = mb.position
			_dragging = false
		else:
			_release()
		return true
	var mm := event as InputEventMouseMotion
	if mm and not _origin.is_empty():
		if _dragging or mm.position.distance_to(_start) > ObjectDrag.THRESHOLD:
			_dragging = true
			_set_reach(mm.position, mm.alt_pressed)
		return true
	return false


func _release() -> void:
	if not _origin.is_empty():
		if _dragging:
			surface.save_notes()
		else:
			surface.snapping.toggle_grid(_origin[0], _origin[1])
	_origin = []
	_dragging = false


func _origin_pos(entry: Array) -> Vector2:
	var o: Note = entry[0]
	return o.emitter().pos if entry[1] else o.pos


func _grid_of(entry: Array) -> Grid:
	var o: Note = entry[0]
	return o.emitter().grid if entry[1] else o.grid


## The distance from the origin becomes the reach, snapped to timing divisions unless `free`.
func _set_reach(screen_pos: Vector2, free: bool) -> void:
	if _grid_of(_origin) == null:
		var fresh := Grid.new()
		if _origin[1]:
			_origin[0].emitter().grid = fresh
		else:
			_origin[0].grid = fresh
	var r := _origin_pos(_origin).distance_to(surface.to_world(screen_pos))
	var step := Snapping.ring_step()
	if r <= Note.RADIUS / surface.z():
		r = 0.0                                  # back on the origin: automatic
	elif not free:
		r = maxf(roundf(r / step) * step, step)
	_grid_of(_origin).reach = r


func draw_overlay(canvas: WaveSurface) -> void:
	for o in surface.notes:
		if o.grid:
			canvas.draw_brackets(canvas.to_screen(o.pos), o.bracket_half() + 2.0, 1.5, 0.6, 0.3)
		var e: Emitter = o.emitter()
		if e and e.grid and not e.attached:
			canvas.draw_brackets(canvas.to_screen(e.pos), Emitter.HANDLE_RADIUS + 6.0, 1.5, 0.6, 0.3)
	if _dragging:
		var o: Note = _origin[0]
		var at := canvas.to_screen(_origin_pos(_origin))
		var limit: float = o.emitter().grid_limit() if _origin[1] else o.grid_limit()
		canvas.draw_arc(at, limit * canvas.z(), 0.0, TAU, 128, Color(Palette.ACCENT.lightened(0.4), 0.8), 2.0, true)
		var text := "auto · " if _grid_of(_origin).reach <= 0.0 else ""
		text += Snapping.format_beats(limit / Settings.BEAT_UNIT)
		canvas.draw_string(canvas.get_theme_default_font(), at + Vector2(Note.RADIUS + 14.0, -Note.RADIUS - 10.0), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.TEXT)


## A ring crossed by two spokes.
func draw_icon(canvas: CanvasItem, c: Vector2, ink: Color) -> void:
	canvas.draw_arc(c, 9.0, 0.0, TAU, 28, ink, 1.5, true)
	canvas.draw_arc(c, 4.5, 0.0, TAU, 20, Color(ink, 0.7), 1.5, true)
	canvas.draw_line(c + Vector2(-11, 0), c + Vector2(11, 0), Color(ink, 0.8), 1.0, true)
	canvas.draw_line(c + Vector2(0, -11), c + Vector2(0, 11), Color(ink, 0.8), 1.0, true)
