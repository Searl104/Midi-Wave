class_name ToolManager
extends RefCounted
## The tools in toolbar order, which one is active, and the rings. Rings open from any tool, so
## this also routes the radial menu to whichever ring tool opened it.

signal tool_changed(tool_id: String)
signal mode_changed(editing: bool)

var surface: WaveSurface
var tools: Array[Tool] = []
var current: Tool
var last_edit: Tool                ## the editing tool to go back to from the Wave tool
var radial: RadialMenu
var open_ring: RingTool = null     ## the ring tool using the radial menu


func _init(owner_surface: WaveSurface) -> void:
	surface = owner_surface
	tools = [WaveTool.new(surface), SelectTool.new(surface), DrawTool.new(surface), PitchTool.new(surface),
			ChannelTool.new(surface), PulseTool.new(surface), ModifierTool.new(surface)]
	current = get_tool("select")
	last_edit = current


func get_tool(id: String) -> Tool:
	for t in tools:
		if t.tool_id() == id:
			return t
	return null


func current_id() -> String:
	return current.tool_id()


## False while the Wave tool is in use: the layout is locked.
func is_editing() -> bool:
	return current.edits_layout()


## Picks a tool. Picking the active one lets it respond (Draw switches what it places).
func pick(id: String) -> void:
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
	if is_editing():
		last_edit = t
	t.activate()
	if is_editing() != was_editing:
		if not is_editing():
			surface.selection.clear()
		mode_changed.emit(is_editing())
	tool_changed.emit(id)


## Flips between the Wave tool and the last editing tool.
func toggle_wave() -> void:
	set_tool(last_edit.tool_id() if not is_editing() else "wave")


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
	open_ring = get_tool(ring_id)
	open_ring.open(radial, note_id, at)


## The default ring: pitch, or pulse on a relay, which has no pitch to play.
func open_default_ring(note_id: int, at: Vector2) -> void:
	open_ring_for("pulse" if surface.get_note(note_id) is Relay else "pitch", note_id, at)
