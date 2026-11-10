class_name ToolManager
extends RefCounted
## The tools in toolbar order, which one is active, and where input goes. Pitch, Channel and Modifier
## aren't tools you switch to: picking one sets `ring_option`, the ring a right-click on a note opens
## in any editing tool. A right-click on a modifier's tab opens its settings instead. Holding the middle button
## spring-loads Pan (Zoom with Shift): that tool works until the button comes up, then the one
## before it returns. Rings open from any tool, so this also routes the radial menu to whichever
## ring tool opened it.

signal tool_changed(tool_id: String)
signal mode_changed(editing: bool)
signal notice(text: String)
signal close_panel                 ## a tool is done with its panel

var surface: WaveSurface
var tools: Array[Tool] = []
var current: Tool
var ring_option: RingTool          ## which ring a right-click on a note opens
var _editing := true               # false in the Tap tool; a nav tool leaves this as it was
var _spring_from: Tool = null      # the tool to return to when the middle button comes up
var radial: RadialMenu
var open_ring: RingTool = null     ## the ring tool using the radial menu
var _settings_rings: Dictionary = {}   # rings tabs open, by Modifier.ring_id(); not on the toolbar


func _init(owner_surface: WaveSurface) -> void:
	surface = owner_surface
	tools = [TapTool.new(surface), SelectTool.new(surface), DrawTool.new(surface), BindTool.new(surface), GridTool.new(surface), VelocityTool.new(surface), CollectionTool.new(surface), PitchTool.new(surface),
			ChannelTool.new(surface), ModifierTool.new(surface),
			PanTool.new(surface), ZoomTool.new(surface)]
	_settings_rings = {"relay_settings": RelaySettingsRing.new(surface), "sequence_settings": SequenceSettingsRing.new(surface)}
	ring_option = get_tool("pitch")
	current = get_tool("select")


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
	if get_tool(id) is RingTool:
		set_ring_option(id)
		tool_changed.emit(current_id())
		return
	_spring_from = null
	if id == current_id():
		current.repick()
		tool_changed.emit(id)
	else:
		set_tool(id)


## Chooses the ring right-click opens on a note.
func set_ring_option(id: String) -> void:
	var t := get_tool(id) as RingTool
	if t:
		ring_option = t


func set_tool(id: String) -> void:
	var t := get_tool(id)
	if t == null or t == current or t is RingTool:
		return
	surface.drag.end()
	current.deactivate()
	var was_editing := is_editing()
	current = t
	if not t.navigates():
		_editing = t.edits_layout()
	surface.mouse_default_cursor_shape = t.cursor()
	t.activate()
	if is_editing() != was_editing:
		if not is_editing():
			surface.selection.clear()
		mode_changed.emit(is_editing())
	tool_changed.emit(id)


## A binding input went down: the armed Bind tool takes it, otherwise it fires.
func binding_pressed(binding: String) -> void:
	if current is BindTool and current.armed():
		current.bind(binding)
	else:
		surface.press_binding(binding)


func binding_released(binding: String) -> void:
	surface.release_binding(binding)


## Which keypad digit a key is, or -1. Matched by physical key, so Num Lock doesn't matter.
func _keypad_digit(key: InputEventKey) -> int:
	var pad: int = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	return pad - KEY_KP_0 if pad >= KEY_KP_0 and pad <= KEY_KP_9 else -1


## Mute and nudge work in every tool, including Tap.
func _handle_tweak(key: InputEventKey) -> bool:
	match key.keycode:
		KEY_M:
			if not key.ctrl_pressed and not key.alt_pressed:
				surface.toggle_mute()
				return true
		KEY_COMMA, KEY_PERIOD, KEY_LESS, KEY_GREATER:
			if not key.ctrl_pressed and not key.alt_pressed and not (radial and radial.visible):
				var up := key.keycode == KEY_PERIOD or key.keycode == KEY_GREATER
				var octave := key.shift_pressed or key.keycode == KEY_LESS or key.keycode == KEY_GREATER
				surface.nudge_pitch(1 if up else -1, octave)
				return true
	return false


## Stop, Tab, keypad bindings, tool keys and undo. Tab cycles the ring choice (Shift+Tab goes
## back); a tool key picks its tool, as a toolbar click does; undo and redo work in every editing
## tool; Esc closes an open ring. The active tool gets any other key.
func _handle_key(key: InputEventKey) -> bool:
	var digit := _keypad_digit(key)
	if digit != -1:
		if key.pressed and not key.echo:
			binding_pressed("kp%d" % digit)
		elif not key.pressed:
			binding_released("kp%d" % digit)
		return true
	if not key.pressed or key.echo:
		return false
	if key.keycode == KEY_SPACE or key.keycode == KEY_KP_ENTER or key.physical_keycode == KEY_KP_ENTER:
		surface.stop()
		return true
	if _handle_tweak(key):
		return true
	if key.keycode == KEY_TAB and not key.ctrl_pressed and not key.alt_pressed:
		cycle_ring_option(-1 if key.shift_pressed else 1)
		return true
	if key.keycode == KEY_ESCAPE and radial and radial.visible:
		radial.close()
		return true
	var tool_id := ToolKeys.tool_for(key)
	if tool_id != "":
		if not springing():
			close_ring()
			close_panel.emit()
			pick(tool_id)
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
	if key and _handle_key(key):
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
		var hit := surface.note_at(mb.position)
		if hit != -1 and not surface.drag.active():
			open_ring_for(ring_option.tool_id(), hit, mb.position, true)
			return true
		if current.ring_target() != -1 and surface.pick_at(mb.position).is_empty() and not surface.drag.active():
			open_ring_for(ring_option.tool_id(), current.ring_target(), mb.position, true)
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


## Moves the ring choice to the next ring on the bar (`step` -1: the previous one), wrapping
## around, as clicking it on the bar does.
func cycle_ring_option(step: int) -> void:
	var rings := tools.filter(func(t: Tool) -> bool: return t is RingTool)
	if rings.is_empty():
		return
	var i := rings.find(ring_option)
	set_ring_option(rings[posmod(i + step, rings.size())].tool_id())
	tool_changed.emit(current_id())


func draw_overlay(canvas: WaveSurface) -> void:
	current.draw_overlay(canvas)
	get_tool("collection").draw_drop(canvas)


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
	radial.dial_changed.connect(func(value: float) -> void:
		if open_ring:
			open_ring.pick_dial(value))
	radial.closed.connect(func() -> void:
		if open_ring:
			open_ring.ring_closed())
	radial.hover_changed.connect(func(ring: String, id: Variant) -> void:
		if open_ring:
			open_ring.hovered(ring, id))


func close_ring() -> void:
	if radial and radial.visible:
		radial.close()


## Opens `ring_id`'s ring for an object (-1 = no object: the pitch ring places a new one).
func open_ring_for(ring_id: String, note_id: int, at: Vector2, hold: bool = false) -> void:
	open_ring = _settings_rings[ring_id] if _settings_rings.has(ring_id) else get_tool(ring_id)
	open_ring.open(radial, note_id, at, hold)


## Opens a modifier's settings ring at `at`, held for a quick pick.
func open_tab(note: Note, modifier: Modifier, at: Vector2) -> void:
	open_ring_for(modifier.ring_id(), note.id, at, true)


## The default ring, on a note or on empty space.
func open_default_ring(note_id: int, at: Vector2) -> void:
	open_ring_for("pitch", note_id, at)
