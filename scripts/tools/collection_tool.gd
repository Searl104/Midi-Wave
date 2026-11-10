class_name CollectionTool
extends Tool
## Paste Collection. Its panel saves the selection under a new name and lists the collections. Click
## a row to load it, then click the surface to place it (Shift keeps it loaded to place more, Alt
## places freely), or drag a row onto the surface. Pasted notes become the selection.

var picked := ""                   ## the loaded collection, which a click places
var _items: Array = []             # the picked collection
var _ghosts: Array = []            # [note, offset] to draw it
var _drop_ghosts: Array = []       # the same for a row being dragged
var _drop_at := Vector2.ZERO
var _drop_name := ""
var _name: LineEdit
var _status: Label
var _list: FileTree
var _open := {}                    # folders showing their contents


func section() -> int:
	return 1


func tool_id() -> String:
	return "collection"


func title() -> String:
	return "Paste Collection"


func has_options() -> bool:
	return true


func build_options(box: VBoxContainer) -> void:
	PanelBuilder.section(box, "SAVE SELECTION", Palette.YELLOW)
	var row := HBoxContainer.new()
	box.add_child(row)
	_name = LineEdit.new()
	_name.placeholder_text = "folder/name"
	_name.max_length = NamedFiles.NAME_MAX
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.tooltip_text = "A name for the selected notes, used once. A slash puts it in a folder."
	_name.text_changed.connect(_name_typed)
	_name.text_submitted.connect(func(_t: String) -> void: _save_pressed())
	row.add_child(_name)
	row.add_child(PanelBuilder.button("Save", _save_pressed, "Saves the selected notes as a new collection."))
	_status = PanelBuilder.hint("")
	_status.add_theme_color_override("font_color", Palette.YELLOW)
	_status.hide()
	box.add_child(_status)
	PanelBuilder.section(box, "COLLECTIONS", Palette.BLUE)
	box.add_child(PanelBuilder.hint("Drag one onto the surface, or click one and then click the surface. Shift-click to place more."))
	box.add_child(PanelBuilder.button("Open Collections Folder", func() -> void: OS.shell_open(NamedFiles.folder(Collections.DIR)),
			"Shows the collection files in your file manager."))
	_list = FileTree.new()
	_list.open = _open
	_list.make_row = _make_row
	box.add_child(_list)
	_rebuild_list()


## Keeps the field to characters a file name can use.
func _name_typed(text: String) -> void:
	var clean := NamedFiles.cleaned(text)
	if clean != text:
		var caret := _name.caret_column - (text.length() - clean.length())
		_name.text = clean
		_name.caret_column = caret


func _save_pressed() -> void:
	var problem := save_selection(_name.text)
	_status.text = problem
	_status.visible = problem != ""
	if problem == "":
		_name.clear()
		_rebuild_list()


## Saves the selected notes. Returns what stopped it, or "".
func save_selection(collection: String) -> String:
	collection = NamedFiles.normalised(collection)
	var notes: Array = surface.notes.filter(func(o: Note) -> bool: return surface.selection.notes.has(o.id))
	if NamedFiles.problem(collection) != "":
		return NamedFiles.problem(collection)
	if notes.is_empty():
		return "Select some notes first."
	if Collections.exists(collection):
		return "That name is already used."
	if not Collections.save(collection, notes):
		return "Couldn't save the file."
	var folder := collection.get_base_dir()
	while folder != "":                # show where it went
		_open[folder] = true
		folder = folder.get_base_dir()
	surface.tools.notice.emit("Saved %s" % collection)
	return ""


func _rebuild_list() -> void:
	_list.show_names(Collections.list())


func _make_row(collection: String) -> Control:
	var row := CollectionRow.new(collection, collection == picked)
	row.picked.connect(pick)
	row.delete_confirmed.connect(delete)
	return row


func toggle_folder(folder: String) -> void:
	_list.toggle(folder)


## Loads `collection` for placing, in this tool.
func pick(collection: String) -> void:
	picked = collection
	_items = Collections.read(collection)
	_ghosts = _ghosts_for(_items)
	surface.tools.set_tool(tool_id())
	surface.tools.close_panel.emit()


func _unload() -> void:
	picked = ""
	_items = []
	_ghosts = []


func delete(collection: String) -> void:
	Collections.remove(collection)
	if collection == picked:
		_unload()
	surface.tools.notice.emit("Deleted %s" % collection)
	_rebuild_list()


func _ghosts_for(items: Array) -> Array:
	var out: Array = []
	for d in items:
		var o := Note.new()
		o.note = int(d["note"])
		o.channel = int(d["channel"])
		o.load_dict(d, Vector2.ZERO)
		out.append([o, Vector2(float(d["x"]), float(d["y"]))])
	return out


## Where a collection's centre goes for a pointer at `screen_pos`: its first note lands on the
## nearest grid point, and the rest keep their places around it.
func landing(items: Array, screen_pos: Vector2, free: bool) -> Vector2:
	var centre := surface.to_world(screen_pos)
	if free or items.is_empty():
		return centre
	var first := centre + Vector2(float(items[0]["x"]), float(items[0]["y"]))
	return centre + surface.snapping.grid_snap(first) - first


## Adds a copy of `items` as one undo step and selects it. Returns how many notes it added.
func place(items: Array, screen_pos: Vector2, free: bool = false) -> int:
	if items.is_empty():
		return 0
	var sel := surface.selection
	surface.history.end_group()
	surface.history.set_stroke(true)
	sel.clear()
	for d in Collections.placed(items, landing(items, screen_pos, free)):
		var id := surface.add_object(Vector2(d["x"], d["y"]), int(d["note"]), int(d["channel"]))
		var o := surface.get_note(id)
		o.load_dict(d, o.pos)
		sel.notes[id] = true
	surface.save_notes()
	surface.history.set_stroke(false)
	surface.history.end_group()
	return items.size()


func handle_input(event: InputEvent) -> bool:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return false
	if mb.pressed:
		if picked == "":
			surface.tools.notice.emit("Load a collection: right-click this tool")
		else:
			place(_items, mb.position, mb.alt_pressed)
			if not mb.shift_pressed:
				_unload()
	return true


## A row is being dragged over the surface.
func hover_drop(collection: String, at: Vector2) -> void:
	if collection != _drop_name:
		_drop_name = collection
		_drop_ghosts = _ghosts_for(Collections.read(collection))
	_drop_at = at


## A row was dropped on the surface.
func drop(collection: String, at: Vector2, free: bool = false) -> int:
	end_drop()
	return place(Collections.read(collection), at, free)


func end_drop() -> void:
	_drop_name = ""
	_drop_ghosts = []


func _draw_ghosts(canvas: WaveSurface, ghosts: Array, at: Vector2) -> void:
	var items: Array = ghosts.map(func(g: Array) -> Dictionary: return {"x": g[1].x, "y": g[1].y})
	var centre := landing(items, at, Input.is_key_pressed(KEY_ALT))
	for g in ghosts:
		g[0].draw_ghost(canvas, canvas.to_screen(centre + g[1]))


func draw_overlay(canvas: WaveSurface) -> void:
	if not _ghosts.is_empty() and canvas.pointer_inside() and canvas.tools.current == self \
			and not (surface.tools.radial and surface.tools.radial.visible):
		_draw_ghosts(canvas, _ghosts, canvas.pointer())


## Drawn in any tool, since a row can be dragged from any.
func draw_drop(canvas: WaveSurface) -> void:
	if not _drop_ghosts.is_empty():
		_draw_ghosts(canvas, _drop_ghosts, _drop_at)


func draw_icon(canvas: CanvasItem, c: Vector2, ink: Color) -> void:
	canvas.draw_arc(c + Vector2(-5, 4), 4.0, 0.0, TAU, 20, ink, 1.6, true)
	canvas.draw_arc(c + Vector2(5, 4), 4.0, 0.0, TAU, 20, ink, 1.6, true)
	canvas.draw_arc(c + Vector2(0, -5), 4.0, 0.0, TAU, 20, ink, 1.6, true)
	canvas.draw_line(c + Vector2(-9, 11), c + Vector2(9, 11), ink, 1.6, true)
