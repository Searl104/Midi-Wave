class_name ToolManager
extends RefCounted
## The tools in toolbar order, which one is active, and where input goes. Holding the middle button
## spring-loads Pan (Zoom with Shift): that tool works until the button comes up, then the one
## before it returns. Rings open from any tool, so this also routes the radial menu to whichever
## ring tool opened it.

signal tool_changed(tool_id: String)
signal mode_changed(editing: bool)

var surface: WaveSurface
var tools: Array[Tool] = []
var current: Tool
var last_edit: Tool                ## the editing tool to go back to from the Tap tool
var _editing := true               # false in the Tap tool; a nav tool leaves this as it was
var _spring_from: Tool = null      # the tool to return to when the middle button comes up
var radial: RadialMenu
var open_ring: RingTool = null     ## the ring tool using the radial menu
var _settings_rings: Dictionary = {}   # rings tabs open, by Modifier.ring_id(); not on the toolbar


func _init(owner_surface: WaveSurface) -> void:
	surface = owner_surface
	tools = [TapTool.new(surface), SelectTool.new(surface), DrawTool.new(surface), PitchTool.new(surface),
			ChannelTool.new(surface), ModifierTool.new(surface),
			PanTool.new(surface), ZoomTool.new(surface)]
	_settings_rings = {"relay_settings": RelaySettingsRing.new(surface), "toggle_settings": ToggleSettingsRing.new(surface)}
	current = get_tool("select")
	last_edit = current


func get_tool(id: String) -> Tool:
	for t in tools:
		if t.tool_id() == id:
			return t
	return null


func current_id() -> String:
	return current.tool_id()


## False while the Tap tool is in use: the layout is locked.
func is_editing() -> bool:
	return _editing


## Picks a tool. Picking the active one lets it respond (Draw switches what it places).
func pick(id: String) -> void:
	_spring_from = null
	if id == current_id():
		current.repick()
		tool_changed.emit(id)
	else:
		set_tool(id)


func set_tool(id: String) -> void:
	var t := get_tool(id)
	if t == null or t == current:
		return
	surface.drag.end()
	current.deactivate()
	var was_editing := is_editing()
	current = t
	if not t.navigates():
		_editing = t.edits_layout()
		if _editing:
			last_edit = t
	surface.mouse_default_cursor_shape = t.cursor()
	t.activate()
	if is_editing() != was_editing:
		if not is_editing():
			surface.selection.clear()
		mode_changed.emit(is_editing())
	tool_changed.emit(id)


## Undo and redo work in every editing tool. Esc closes an open ring.
func _handle_key(key: InputEventKey) -> bool:
	if key.keycode == KEY_ESCAPE and radial and radial.visible:
		radial.close()
		return true
	if not is_editing() or not key.ctrl_pressed:
		return false
	match key.keycode:
		KEY_Z:
			if key.shift_pressed:
				surface.redo()
			else:
				surface.undo()
			return true
		KEY_Y:
			surface.redo()
			return true
	return false


## Takes an input event from the surface. Returns true if it was used.
func handle_input(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and _handle_key(key):
		return true
	var mb := event as InputEventMouseButton
	var middle := mb != null and mb.button_index == MOUSE_BUTTON_MIDDLE
	if middle and mb.pressed and _spring_from == null:
		_spring_from = current
		set_tool("zoom" if mb.shift_pressed else "pan")
	if mb and mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and is_editing():
		var tab := surface.tab_at(mb.position)
		if not tab.is_empty():
			open_tab(tab[0], tab[1], mb.position)
			return true
	var used := current.handle_input(event)
	if middle and not mb.pressed:
		end_spring()
		used = true
	return used


## Returns to the tool from before the spring-load, if there is one.
func end_spring() -> void:
	if _spring_from == null:
		return
	var back := _spring_from
	_spring_from = null
	if back == current:
		current.deactivate()
	else:
		set_tool(back.tool_id())


func springing() -> bool:
	return _spring_from != null


## Flips between the Tap tool and the last editing tool.
func toggle_tap() -> void:
	set_tool(last_edit.tool_id() if not is_editing() else "tap")


func draw_overlay(canvas: WaveSurface) -> void:
	current.draw_overlay(canvas)


# --- Rings ---------------------------------------------------------------------------------

func attach_radial(menu: RadialMenu) -> void:
	radial = menu
	radial.outer_chosen.connect(func(id: Variant) -> void:
		if open_ring:
			open_ring.pick_outer(id))
	radial.inner_chosen.connect(func(id: Variant) -> void:
		if open_ring:
			open_ring.pick_inner(id))
	radial.center_chosen.connect(func(id: Variant) -> void:
		if open_ring:
			open_ring.pick_center(id))
	radial.hover_changed.connect(func(ring: String, id: Variant) -> void:
		if open_ring:
			open_ring.hovered(ring, id))


func close_ring() -> void:
	if radial and radial.visible:
		radial.close()


## Opens `ring_id`'s ring for an object (-1 = no object: the pitch ring places a new one).
func open_ring_for(ring_id: String, note_id: int, at: Vector2) -> void:
	open_ring = _settings_rings[ring_id] if _settings_rings.has(ring_id) else get_tool(ring_id)
	open_ring.open(radial, note_id, at)


## Opens a modifier's settings ring at `at`.
func open_tab(note: Note, modifier: Modifier, at: Vector2) -> void:
	open_ring_for(modifier.ring_id(), note.id, at)


## The default ring, on a note or on empty space.
func open_default_ring(note_id: int, at: Vector2) -> void:
	open_ring_for("pitch", note_id, at)
