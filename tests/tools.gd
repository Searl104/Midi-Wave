extends Node
## Exercises every tool's operations directly. Run: godot --headless --path . res://tests/tools.tscn

var surface: WaveSurface
var tools: ToolManager
var radial: RadialMenu
var failures := 0
var checks := 0


func _ready() -> void:
	Midi.log_when_closed = false
	surface = WaveSurface.new()
	add_child(surface)
	surface.size = Vector2(1280, 800)
	radial = RadialMenu.new()
	add_child(radial)
	radial.size = Vector2(1280, 800)
	tools = surface.tools
	tools.attach_radial(radial)
	surface.clear_notes()
	_switching()
	_select_and_move()
	_navigation()
	_tap()
	_select()
	_draw_tool()
	_pitch()
	_channel()
	_modifiers()
	_tabs()
	_quick_pick()
	_ring_options()
	_tab()
	_bindings()
	_group_rings()
	_grid_tool()
	_tool_options()
	_sequence()
	_collections()
	_held_during_cooldown()
	_midi_controls()
	_note_lengths()
	_channel_volume()
	_timing()
	_slow_frame()
	_wave_end()
	_tweaks()
	_saves()
	_default_ring()
	print("TOOLS %s: %d checks, %d failed" % ["OK" if failures == 0 else "FAILED", checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("  failed: ", what)


func _switching() -> void:
	var seen: Array = []
	tools.tool_changed.connect(func(id: String) -> void: seen.append(id))
	var modes: Array = []
	tools.mode_changed.connect(func(editing: bool) -> void: modes.append(editing))
	_check(tools.tools.size() == 11, "eleven tools")
	_check(tools.get_tool("pulse") == null, "no Pulse tool")
	_check(tools.current_id() == "select", "starts on select")
	tools.set_tool("nothing")
	_check(tools.current_id() == "select", "unknown tool ignored")
	tools.set_tool("draw")
	tools.toggle_tap()
	_check(tools.current_id() == "tap" and not tools.is_editing(), "tap locks the layout")
	tools.toggle_tap()
	_check(tools.current_id() == "draw", "back to the last editing tool")
	_check(modes == [false, true], "mode changes reported")
	tools.pick("draw")
	_check(seen.size() >= 3, "tool changes reported")
	for t in tools.tools:
		if not t.navigates() and t.tool_id() != "tap":
			_check(t.handle_input(InputEventMouseButton.new()) == false, "%s takes no input yet" % t.tool_id())
	tools.set_tool("select")


func _press(button: MouseButton, down: bool, at: Vector2, shift: bool = false, ctrl: bool = false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = down
	e.position = at
	e.shift_pressed = shift
	e.ctrl_pressed = ctrl
	surface._gui_input(e)


func _move(at: Vector2, alt: bool = false) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.alt_pressed = alt
	surface._gui_input(e)


func _click(at: Vector2, shift: bool = false) -> void:
	_press(MOUSE_BUTTON_LEFT, true, at, shift)
	_press(MOUSE_BUTTON_LEFT, false, at, shift)


func _drag(from: Vector2, to: Vector2, alt: bool = false, ctrl: bool = false) -> void:
	_press(MOUSE_BUTTON_LEFT, true, from, false, ctrl)
	_move(to, alt)
	_press(MOUSE_BUTTON_LEFT, false, to, false, ctrl)


func _key(code: Key, ctrl: bool = false, shift: bool = false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.ctrl_pressed = ctrl
	e.shift_pressed = shift
	tools.handle_input(e)


func _ids(d: Dictionary) -> Array:
	var out: Array = d.keys()
	out.sort()
	return out


func _select_and_move() -> void:
	tools.set_tool("select")
	_check(tools.current.title() == "Select and Move", "named")
	var sel := surface.selection
	var a := surface.add_note_at(Vector2(200, 200), 60, 0)
	var b := surface.add_note_at(Vector2(350, 200), 62, 0)
	var r := surface.add_note_at(Vector2(500, 200), 64, 0)
	surface.add_modifier(r, "relay")
	var ro := surface.get_note(r)
	var e: Emitter = ro.emitter()
	# Click, Shift-click, empty space.
	_click(Vector2(200, 200))
	_check(_ids(sel.notes) == [a], "click selects")
	_click(Vector2(350, 200), true)
	_check(_ids(sel.notes) == [a, b], "Shift-click adds")
	_click(Vector2(350, 200), true)
	_check(_ids(sel.notes) == [a], "Shift-click removes")
	_click(Vector2(700, 600))
	_check(not sel.has_any(), "a click on empty space clears")
	# Group: a click narrows on release, a drag keeps it.
	_click(Vector2(200, 200))
	_click(Vector2(350, 200), true)
	_press(MOUSE_BUTTON_LEFT, true, Vector2(350, 200))
	_check(sel.notes.size() == 2, "group held until release")
	_press(MOUSE_BUTTON_LEFT, false, Vector2(350, 200))
	_check(_ids(sel.notes) == [b], "click narrows the group")
	_click(Vector2(200, 200), true)
	var layout := JSON.stringify(Settings.notes)
	var steps := surface.history.undo_steps()
	_check(JSON.stringify(Settings.notes) == layout and surface.history.undo_steps() == steps, "selecting isn't an edit")
	_drag(Vector2(200, 200), Vector2(240, 260), true)
	_check(sel.notes.size() == 2, "drag keeps the group")
	_check(surface.to_screen(surface.get_note(a).pos) == Vector2(240, 260), "held note follows")
	_check(surface.to_screen(surface.get_note(b).pos) == Vector2(390, 260), "the group keeps its shape")
	surface.history.end_group()
	# An unselected note replaces the selection and moves.
	_drag(Vector2(500, 200), Vector2(520, 240), true)
	_check(_ids(sel.notes) == [r], "drag replaces the selection")
	_check(surface.to_screen(ro.pos) == Vector2(520, 240), "and moves it")
	surface.history.end_group()
	# Docked diamond: click selects; drag places; remote diamonds stay when notes move.
	var dock: Vector2 = e.dock_screen_pos(surface, ro)
	_click(dock)
	_check(_ids(sel.emitters) == [r] and sel.notes.is_empty(), "click selects the diamond")
	_drag(dock, Vector2(800, 500), true)
	_check(not e.attached and surface.to_screen(e.pos) == Vector2(800, 500), "drag places the diamond")
	surface.history.end_group()
	_click(Vector2(700, 650))
	_drag(Vector2(520, 240), Vector2(560, 280), true)
	_check(surface.to_screen(e.pos) == Vector2(800, 500), "a single note leaves its diamond")
	surface.history.end_group()
	_click(Vector2(240, 260), true)
	_drag(Vector2(240, 260), Vector2(250, 270), true)
	_check(surface.to_screen(e.pos) == Vector2(800, 500), "so does a group")
	surface.history.end_group()
	_click(Vector2(800, 500), true)
	_check(sel.emitters.has(r), "Shift-click adds the diamond")
	_drag(Vector2(250, 270), Vector2(260, 280), true)
	_check(surface.to_screen(e.pos) == Vector2(810, 510), "selected, it moves too")
	surface.history.end_group()
	# Dim handle: click selects the remote diamond; drag places it; on the note it docks.
	_click(Vector2(1100, 700))
	dock = e.dock_screen_pos(surface, ro)
	_click(dock)
	_check(_ids(sel.emitters) == [r], "the dim handle selects the diamond")
	_drag(dock, Vector2(900, 300), true)
	_check(surface.to_screen(e.pos) == Vector2(900, 300), "and drags it")
	surface.history.end_group()
	_drag(Vector2(900, 300), surface.to_screen(ro.pos), true)
	_check(e.attached, "dropped on the note it docks")
	surface.history.end_group()
	# Ctrl-drag: reach from a diamond, nothing elsewhere.
	_click(Vector2(1100, 700))
	var from: Vector2 = e.dock_screen_pos(surface, ro)
	layout = JSON.stringify(Settings.notes)
	_drag(surface.to_screen(surface.get_note(a).pos), Vector2(100, 100), false, true)
	_check(JSON.stringify(Settings.notes) == layout, "Ctrl-drag on a note does nothing")
	_drag(from, surface.to_screen(ro.pos) + Vector2(300, 0), false, true)
	_check(is_equal_approx(e.own_reach, 300.0 / surface.z()), "Ctrl-drag sets reach")
	surface.history.end_group()
	_drag(from, surface.to_screen(ro.pos), false, true)
	_check(e.own_reach == 0.0, "back on the note: global")
	surface.history.end_group()
	# Box, and a Shift box.
	_drag(Vector2(100, 100), Vector2(450, 320))
	_check(sel.notes.keys().size() == 2 and not sel.notes.has(r), "a box selects")
	_click(Vector2(1100, 700))
	_drag(Vector2(100, 100), Vector2(450, 320))
	_press(MOUSE_BUTTON_LEFT, true, Vector2(500, 200), true)
	_move(Vector2(650, 400))
	_press(MOUSE_BUTTON_LEFT, false, Vector2(650, 400), true)
	_check(sel.notes.size() == 3, "a Shift box adds")
	# Snapping without Alt, freely with it.
	_click(Vector2(1100, 700))
	var bo := surface.get_note(b)
	var ao := surface.get_note(a)
	surface.snapping.toggle_grid(ao, false)
	var near: Vector2 = surface.to_screen(ao.pos) + Vector2(203, 2)
	_drag(surface.to_screen(bo.pos), near)
	_check(surface.to_screen(bo.pos).is_equal_approx(surface.to_screen(ao.pos) + Vector2(200, 0)), "snaps to the grid")
	surface.history.end_group()
	var before: Vector2 = bo.pos
	_drag(surface.to_screen(bo.pos), surface.to_screen(bo.pos) + Vector2(3, 3), true)
	_check(bo.pos == before, "under the threshold nothing moves")
	var loose: Vector2 = near + Vector2(12, 3)
	_drag(surface.to_screen(bo.pos), loose, true)
	_check(surface.to_screen(bo.pos) == loose, "Alt places freely")
	surface.history.end_group()
	surface.snapping.clear_grids()
	surface.history.end_group()
	# Hover.
	surface.set_pointer(Vector2(1100, 700))
	_check(surface.hovered_note() == -1, "nothing hovered")
	surface.set_pointer(surface.to_screen(ao.pos))
	_check(surface.hovered_note() == a, "hover finds a note")
	# Keys.
	var count := surface.notes.size()
	_click(surface.to_screen(ao.pos))
	surface.history.end_group()
	_key(KEY_C, true)
	surface.set_pointer(Vector2(900, 600))
	_key(KEY_V, true)
	_check(surface.notes.size() == count + 1, "copy and paste")
	_check(surface.to_screen(surface.notes[-1].pos).is_equal_approx(Vector2(900, 600)), "paste lands at the pointer")
	surface.history.end_group()
	_key(KEY_DELETE)
	_check(surface.notes.size() == count, "Delete removes")
	surface.history.end_group()
	_key(KEY_Z, true)
	_check(surface.notes.size() == count + 1, "Ctrl+Z")
	surface.history.end_group()
	_key(KEY_Z, true, true)
	_check(surface.notes.size() == count, "Ctrl+Shift+Z")
	surface.history.end_group()
	_key(KEY_Z, true)
	_key(KEY_Y, true)
	_check(surface.notes.size() == count, "Ctrl+Y")
	_click(surface.to_screen(ao.pos))
	_key(KEY_ESCAPE)
	_check(not sel.has_any(), "Esc clears")
	_click(surface.to_screen(ao.pos))
	_key(KEY_BACKSPACE)
	_check(surface.get_note(a) == null, "Backspace removes")
	tools.set_tool("tap")
	surface.history.end_group()
	var steps_now := surface.history.undo_steps()
	_key(KEY_Z, true)
	_check(surface.history.undo_steps() == steps_now, "undo is locked in Tap")
	# Esc closes a ring first.
	tools.set_tool("select")
	_click(surface.to_screen(bo.pos))
	tools.open_ring_for("pitch", b, Vector2(600, 400))
	_key(KEY_ESCAPE)
	_check(not radial.visible and sel.has_any(), "Esc closes the ring first")
	sel.clear()
	surface.clear_notes()


func _navigation() -> void:
	var id := surface.add_note_at(Vector2(300, 300), 60, 0)
	var layout := JSON.stringify(Settings.notes)
	surface.selection.notes = {id: true}
	var saved_view := surface.view_offset
	# Middle-drag spring-loads Pan and then returns.
	tools.set_tool("select")
	_press(MOUSE_BUTTON_MIDDLE, true, Vector2(100, 100))
	_check(tools.current_id() == "pan" and tools.springing(), "middle spring-loads pan")
	_move(Vector2(160, 130))
	_check(surface.to_screen(saved_view) == Vector2(60, 30), "pan follows the pointer")
	_press(MOUSE_BUTTON_MIDDLE, false, Vector2(160, 130))
	_check(tools.current_id() == "select" and not tools.springing(), "release returns to the tool")
	_check(tools.is_editing() and surface.selection.notes.has(id), "mode and selection kept")
	# Shift + middle spring-loads Zoom, about the pressed point.
	var pivot := Vector2(400, 300)
	var world := surface.to_world(pivot)
	var spacing: float = Settings.beat_spacing
	_press(MOUSE_BUTTON_MIDDLE, true, pivot, true)
	_check(tools.current_id() == "zoom", "shift-middle spring-loads zoom")
	_move(pivot + Vector2(50, 0))
	_check(Settings.beat_spacing > spacing, "right zooms in")
	_check(surface.to_world(pivot).is_equal_approx(world), "the pressed point stays put")
	var more: float = Settings.beat_spacing
	_move(pivot + Vector2(50, -40))
	_check(Settings.beat_spacing > more, "up zooms in")
	_move(pivot + Vector2(-50, 100))
	_check(Settings.beat_spacing < spacing, "left and down zoom out")
	for i in 40:
		_move(pivot + Vector2(-50 - 200 * i, 100))
	_check(Settings.beat_spacing == Settings.BEAT_SPACING_MIN, "stops at the minimum")
	_press(MOUSE_BUTTON_MIDDLE, false, pivot, true)
	_check(tools.current_id() == "select", "zoom returns too")
	Settings.set_value("beat_spacing", spacing)
	# From the Wave tool, stays locked; picked from the bar, left-drag works and stays.
	tools.set_tool("tap")
	_press(MOUSE_BUTTON_MIDDLE, true, Vector2.ZERO)
	_check(not tools.is_editing(), "still locked while panning from Tap")
	_press(MOUSE_BUTTON_MIDDLE, false, Vector2.ZERO)
	_check(tools.current_id() == "tap", "back to Tap")
	tools.pick("pan")
	var before := surface.view_offset
	_press(MOUSE_BUTTON_LEFT, true, Vector2(100, 100))
	_move(Vector2(120, 100))
	_press(MOUSE_BUTTON_LEFT, false, Vector2(120, 100))
	_check(surface.view_offset != before and tools.current_id() == "pan", "left-drag pans and the tool stays")
	var settled := surface.view_offset
	_move(Vector2(300, 300))
	_check(surface.view_offset == settled, "no drag after release")
	# Middle while Pan is active keeps it; losing focus ends a spring-load.
	_press(MOUSE_BUTTON_MIDDLE, true, Vector2.ZERO)
	_press(MOUSE_BUTTON_MIDDLE, false, Vector2.ZERO)
	_check(tools.current_id() == "pan", "stays on Pan")
	tools.set_tool("select")
	_press(MOUSE_BUTTON_MIDDLE, true, Vector2.ZERO)
	tools.end_spring()
	_check(tools.current_id() == "select", "focus loss returns")
	_move(Vector2(50, 50))
	_check(JSON.stringify(Settings.notes) == layout, "navigation leaves the layout alone")
	surface.selection.clear()
	surface.view_offset = Vector2.ZERO
	surface.clear_notes()


func _tap() -> void:
	var note := surface.add_note_at(Vector2(300, 300), 60, 0)
	var relay := surface.add_note_at(Vector2(500, 300), 62, 0)
	surface.add_modifier(relay, "relay")
	surface.set_relay_sound(relay, false)
	var sent: Array = []
	var spy := func(b: PackedByteArray) -> void: sent.append(b)
	Midi.message_sent.connect(spy)
	tools.set_tool("tap")
	_press(MOUSE_BUTTON_LEFT, true, Vector2(800, 600))
	_check(surface.waves.size() == 1 and surface.waves[0].source == -1, "empty space starts a surface wave")
	_check(sent.is_empty(), "and plays nothing yet")
	_press(MOUSE_BUTTON_LEFT, false, Vector2(800, 600))
	_check(surface.waves.size() == 1, "the release does nothing")
	surface.stop()
	_press(MOUSE_BUTTON_LEFT, true, Vector2(302, 302))
	_press(MOUSE_BUTTON_LEFT, false, Vector2(302, 302))
	var o := surface.get_note(note)
	_check(sent.size() == 1 and (sent[0][0] & 0xF0) == 0x90 and sent[0][1] == o.note, "a note plays")
	_check(surface.waves.is_empty(), "alone: no wave")
	_check(o.playing, "and ends on its note length")
	surface.step(Settings.note_length_for(0) + 0.01)
	_check(not o.playing and sent.size() == 2, "note off follows")
	# Toggles: a tap counts as a hit.
	sent.clear()
	surface.add_modifier(note, "sequence")
	_press(MOUSE_BUTTON_LEFT, true, Vector2(300, 300))
	_check(sent.size() == 1 and surface.get_note(note).get_modifier("sequence").pos == 1, "an On step plays")
	surface.step(1.0)
	sent.clear()
	_press(MOUSE_BUTTON_LEFT, true, Vector2(300, 300))
	_check(sent.is_empty() and surface.get_note(note).get_modifier("sequence").pos == 0, "an Off step is silent, and still steps on")
	surface.remove_modifier(note, "sequence")
	# Mute: a tap overrides it, for notes and relays.
	surface.get_note(note).muted = true
	_press(MOUSE_BUTTON_LEFT, true, Vector2(300, 300))
	_check(sent.size() == 1 and surface.waves.is_empty(), "a muted note plays")
	surface.step(1.0)
	sent.clear()
	_press(MOUSE_BUTTON_LEFT, true, Vector2(500, 300))
	_check(surface.waves.size() == 1 and surface.waves[0].source == relay and sent.is_empty(), "a relay fires its pulse")
	surface.stop()
	_press(MOUSE_BUTTON_LEFT, true, Vector2(500, 300))
	_check(surface.waves.is_empty() and surface.held_tap == relay, "a tap during a cooldown waits")
	surface.step(1.0)
	_check(surface.waves.size() == 1 and surface.held_tap == -1, "held, it fires as the cooldown ends")
	surface.step(1.0)
	_check(surface.waves.size() == 1, "once")
	surface.stop()
	surface.step(1.0)
	_press(MOUSE_BUTTON_LEFT, false, Vector2(500, 300))
	surface.stop()
	_press(MOUSE_BUTTON_LEFT, true, Vector2(500, 300))
	_press(MOUSE_BUTTON_LEFT, false, Vector2(500, 300))
	surface.stop()
	_press(MOUSE_BUTTON_LEFT, true, Vector2(500, 300))
	_check(surface.held_tap == relay and surface.waves.is_empty(), "a second press waits")
	_press(MOUSE_BUTTON_LEFT, false, Vector2(500, 300))
	surface.step(1.0)
	_check(surface.waves.is_empty(), "released in time, it doesn't fire")
	surface.step(1.0)
	surface.get_note(relay).muted = true
	_press(MOUSE_BUTTON_LEFT, true, Vector2(500, 300))
	_check(surface.waves.size() == 1, "a muted relay fires")
	surface.stop()
	surface.step(1.0)
	# Diamonds don't react: the click goes through.
	var e := surface.get_note(relay).emitter()
	e.attached = false
	e.pos = surface.to_world(Vector2(800, 200))
	_press(MOUSE_BUTTON_LEFT, true, Vector2(800, 200))
	_check(surface.waves.size() == 1 and surface.waves[0].source == -1, "a diamond on empty space: a surface wave")
	surface.stop()
	e.pos = surface.get_note(note).pos
	sent.clear()
	_press(MOUSE_BUTTON_LEFT, true, Vector2(300, 300))
	_check(sent.size() == 1 and surface.waves.is_empty(), "a diamond on a note: the note plays alone")
	surface.get_note(relay).muted = false
	surface.get_note(note).muted = false
	_press(MOUSE_BUTTON_RIGHT, true, Vector2(800, 600))
	_check(surface.waves.is_empty(), "other buttons do nothing")
	Midi.message_sent.disconnect(spy)
	tools.set_tool("select")
	surface.stop()
	surface.clear_notes()


func _select() -> void:
	var a := surface.add_note_at(Vector2(200, 200), 60, 0)
	var b := surface.add_note_at(Vector2(260, 200), 62, 0)
	var select: SelectTool = tools.get_tool("select")
	select.pick(a)
	_check(surface.selection.notes.keys() == [a], "pick selects")
	select.pick(b)
	_check(surface.selection.notes.keys() == [b], "a pick outside replaces")
	select.pick(a, false, true)
	_check(surface.selection.notes.size() == 2, "add")
	select.pick(a, false, true)
	_check(surface.selection.notes.keys() == [b], "add again removes")
	select.begin_box(Vector2(150, 150))
	select.extend_box(Vector2(300, 300))
	_check(select.box_active, "box under way")
	select.end_box(Vector2(300, 300))
	_check(surface.selection.notes.size() == 2 and not select.box_active, "box selects")
	select.begin_box(Vector2(600, 600))
	select.end_box(Vector2(601, 601))
	_check(not surface.selection.has_any(), "a click clears")
	select.begin_box(Vector2(150, 150), true)
	select.end_box(Vector2(220, 220))
	select.begin_box(Vector2(240, 150), true)
	select.end_box(Vector2(280, 250))
	_check(surface.selection.notes.size() == 2, "box adds")
	var drag := surface.drag
	drag.begin(a, "note", Vector2(200, 200))
	drag.pointer_to(Vector2(202, 201), true)
	_check(not drag.moved and surface.get_note(a).pos == surface.to_world(Vector2(200, 200)), "under the threshold nothing moves")
	drag.pointer_to(Vector2(300, 300), true)
	_check(drag.moved and surface.get_note(b).pos == surface.to_world(Vector2(360, 300)), "the group follows")
	_check(drag.end(), "reports a move")
	surface.selection.clear()
	surface.clear_notes()


func _draw_tool() -> void:
	var draw: DrawTool = tools.get_tool("draw")
	var sel := surface.selection
	surface.add_note_at(Vector2(100, 700), 60, 0)
	sel.notes = {surface.notes[0].id: true}
	tools.set_tool("draw")
	_check(not sel.has_any(), "entering Draw clears the selection")
	surface.clear_notes()
	surface.history.end_group()
	var brush := draw.brush
	# Click places; the note plays once.
	var sent: Array = []
	var spy := func(m: PackedByteArray) -> void:
		if (m[0] & 0xF0) == 0x90:
			sent.append(m)
	Midi.message_sent.connect(spy)
	var steps := surface.history.undo_steps()
	_click(Vector2(300, 300))
	_check(surface.notes.size() == 1 and surface.notes[0].note == brush.note, "a click places the brush")
	_check(sent.size() == 1, "and plays it once")
	_check(surface.history.undo_steps() == steps + 1, "one undo step")
	Midi.message_sent.disconnect(spy)
	surface.history.end_group()
	# Press places, drag positions, all one step.
	steps = surface.history.undo_steps()
	_press(MOUSE_BUTTON_LEFT, true, Vector2(500, 300))
	_check(surface.notes.size() == 2, "placed on press")
	_move(Vector2(560, 400), true)
	_press(MOUSE_BUTTON_LEFT, false, Vector2(560, 400))
	_check(surface.to_screen(surface.notes[1].pos) == Vector2(560, 400), "the drag positions it")
	_check(surface.history.undo_steps() == steps + 1, "placing and dragging is one undo step")
	surface.history.end_group()
	_check(surface.undo() and surface.notes.size() == 1, "undo removes it")
	surface.history.end_group()
	surface.redo()
	surface.history.end_group()
	# Existing notes move, and nothing is placed.
	var a: int = surface.notes[0].id
	_drag(Vector2(300, 300), Vector2(320, 340), true)
	_check(surface.notes.size() == 2 and surface.to_screen(surface.get_note(a).pos) == Vector2(320, 340), "drags an existing note")
	_check(not sel.has_any(), "without selecting it")
	surface.history.end_group()
	_click(Vector2(320, 340))
	_check(surface.notes.size() == 2, "a click on a note places nothing")
	# Snapping: the ghost lands where the note will.
	var ao := surface.get_note(a)
	surface.snapping.toggle_grid(ao, false)
	surface.history.end_group()
	var near := Vector2(523, 342)
	var land := draw.landing(near, false)
	_check(land.is_equal_approx(ao.pos + Vector2(200, 0) / surface.z()), "snaps to a grid point")
	_check(surface.to_screen(draw.landing(near, true)) == near, "Alt lands freely")
	_click(near)
	_check(surface.notes[-1].pos.is_equal_approx(land), "the note lands on the ghost")
	surface.history.end_group()
	surface.snapping.clear_grids()
	surface.history.end_group()
	surface.remove_note(surface.notes[-1].id)
	surface.history.end_group()
	# Right-click on empty space sets the brush; on a note it edits the note.
	tools.pick("channel")
	_press(MOUSE_BUTTON_RIGHT, true, Vector2(700, 500))
	_check(radial.visible and tools.open_ring.note_id == WaveSurface.BRUSH_ID, "the ring opens on the brush")
	radial.outer_chosen.emit(5)
	radial.close()
	_check(brush.channel == 5 and ao.channel != 5, "and sets it")
	tools.pick("pitch")
	_press(MOUSE_BUTTON_RIGHT, true, Vector2(700, 500))
	_check(radial.center_item.is_empty(), "no delete on the brush")
	var pitch: int = radial.outer_items[2].id
	radial.outer_chosen.emit(pitch)
	radial.close()
	_check(brush.note == pitch and surface.notes.size() == 2, "pitch sets it too, placing nothing")
	tools.pick("modifier")
	_press(MOUSE_BUTTON_RIGHT, true, Vector2(700, 500))
	radial.outer_chosen.emit("relay")
	radial.outer_chosen.emit("sequence")
	radial.close()
	_check(brush.relay() != null and brush.get_modifier("sequence") != null, "modifiers go on the brush")
	_check(not Settings.notes.is_empty() and surface.get_note(a).relay() == null, "and only there")
	var channel_before: int = ao.channel
	tools.pick("channel")
	_press(MOUSE_BUTTON_RIGHT, true, Vector2(320, 340))
	_check(tools.open_ring.note_id == a, "on a note it edits the note")
	radial.outer_chosen.emit(9)
	radial.close()
	_check(ao.channel == 9 and brush.channel == 5, "and leaves the brush")
	surface.set_note_channel(a, channel_before)
	surface.history.end_group()
	tools.pick("pitch")
	# Placing carries the modifiers, with a fresh copy.
	_click(Vector2(800, 200))
	var placed: Note = surface.notes[-1]
	_check(placed.channel == 5 and placed.relay() and placed.get_modifier("sequence"), "placed with the brush settings")
	_check(placed.emitter() != brush.emitter() and placed.emitter().attached and placed.emitter().pos == placed.pos, "its own docked relay")
	surface.history.end_group()
	# Handles: move, dock, reach; Ctrl-drag on empty does nothing.
	var dock: Vector2 = placed.emitter().dock_screen_pos(surface, placed)
	_drag(dock, Vector2(1000, 500), true)
	_check(not placed.emitter().attached, "drags a diamond out")
	surface.history.end_group()
	_drag(Vector2(1000, 500), surface.to_screen(placed.pos), true)
	_check(placed.emitter().attached, "and docks it")
	surface.history.end_group()
	_drag(dock, surface.to_screen(placed.pos) + Vector2(300, 0), false, true)
	_check(is_equal_approx(placed.emitter().own_reach, 300.0 / surface.z()), "Ctrl-drag sets reach")
	surface.history.end_group()
	var count := surface.notes.size()
	_press(MOUSE_BUTTON_LEFT, true, Vector2(1100, 700), false, true)
	_press(MOUSE_BUTTON_LEFT, false, Vector2(1100, 700), false, true)
	_check(surface.notes.size() == count, "Ctrl-click on empty space does nothing")
	# Ctrl-click copies exactly; a tab doesn't place.
	placed.emitter().cooldown = 3.0
	placed.emitter().strength = 0.5
	placed.relay().sound = false
	placed.emitter().attached = false
	placed.emitter().pos = Vector2(900, 900)
	surface.save_notes()
	surface.set_binding(placed.id, "kp2")
	surface.history.end_group()
	_press(MOUSE_BUTTON_LEFT, true, surface.to_screen(placed.pos), false, true)
	_press(MOUSE_BUTTON_LEFT, false, surface.to_screen(placed.pos), false, true)
	var be: Emitter = brush.emitter()
	_check(be.cooldown == 3.0 and be.strength == 0.5 and be.own_reach > 0.0 and not brush.relay().sound, "Ctrl-click copies the settings")
	_check(be != placed.emitter() and be.attached and brush.binding == "", "but not the spot or binding")
	_check(Settings.brush.get("channel", -1) == 5 and Settings.brush.mods.size() == 2, "the brush is saved")
	var tab: Vector2 = placed.get_modifier("sequence")._tab_centre(surface, placed)
	count = surface.notes.size()
	_click(tab)
	_check(surface.notes.size() == count, "a tab doesn't place")
	# Turning a modifier off clears its settings.
	tools.pick("modifier")
	_press(MOUSE_BUTTON_RIGHT, true, Vector2(700, 500))
	radial.outer_chosen.emit("relay")
	radial.outer_chosen.emit("relay")
	radial.close()
	_check(brush.emitter().cooldown == 1.0 and brush.relay().sound, "turned off and on, a modifier is back to defaults")
	radial.outer_chosen.emit("")
	tools.pick("pitch")
	# It reloads.
	var reloaded := DrawTool.new(surface)
	_check(reloaded.brush.note == brush.note and reloaded.brush.channel == 5, "reloads from settings")
	# Leaving mid-drag closes the undo step.
	surface.history.end_group()
	steps = surface.history.undo_steps()
	tools.set_tool("draw")
	_press(MOUSE_BUTTON_LEFT, true, Vector2(400, 600))
	tools.set_tool("select")
	_check(not surface.history._stroke_open and not surface.drag.active(), "leaving mid-drag closes the undo step")
	surface.clear_notes()
	Settings.brush = {}
	brush.channel = 0
	brush.modifiers.clear()


func _pitch() -> void:
	surface.history.end_group()
	tools.open_ring_for("pitch", -1, Vector2(500, 400))
	_check(radial.visible and radial.outer_items.size() > 0 and radial.inner_items.size() == 7, "pitch ring opens")
	_check(radial.center_item.is_empty(), "no delete with nothing to delete")
	var ring: PitchTool = tools.get_tool("pitch")
	var pitch: int = radial.outer_items[1].id
	radial.outer_chosen.emit(pitch)
	_check(surface.notes.size() == 1 and surface.notes[0].note == pitch, "first pick places")
	var id: int = surface.notes[0].id
	radial.outer_chosen.emit(radial.outer_items[2].id)
	_check(surface.notes.size() == 1 and surface.notes[0].note == radial.outer_items[2].id, "next pick retunes")
	var was: int = surface.notes[0].note
	radial.inner_chosen.emit(ring._octave + 1)
	_check(surface.notes[0].note == was + 12, "octave keeps the letter")
	radial.center_chosen.emit("delete")
	_check(surface.get_note(id) == null and not radial.visible, "centre deletes and closes")


func _channel() -> void:
	var a := surface.add_note_at(Vector2(200, 200), 60, 0)
	var b := surface.add_note_at(Vector2(300, 200), 62, 0)
	surface.selection.notes = {a: true, b: true}
	tools.open_ring_for("channel", a, Vector2(200, 200))
	_check(radial.outer_items.size() == 16, "16 channels")
	radial.outer_chosen.emit(7)
	_check(surface.get_note(a).channel == 7 and surface.get_note(b).channel == 7, "applies to the group")
	radial.close()
	surface.selection.clear()
	surface.clear_notes()


func _modifiers() -> void:
	var a := surface.add_note_at(Vector2(200, 200), 60, 0)
	tools.open_ring_for("modifier", a, Vector2(200, 200))
	_check(radial.outer_items.size() == 3 and radial.inner_items.is_empty(), "add and remove only")
	radial.outer_chosen.emit("sequence")
	radial.outer_chosen.emit("relay")
	var o := surface.get_note(a)
	_check(o.modifiers.size() == 2 and o.modifiers[0] is SequenceModifier and o.modifiers[1] is RelayModifier, "holds both")
	_check(o.sounds() and o.emitter().attached and o.shows_pitch(), "a new relay keeps sounding")
	# Sounding relay on a toggle: acts on every other hit, playing and pulsing together.
	var sent: Array = []
	var spy := func(b: PackedByteArray) -> void:
		if (b[0] & 0xF0) == 0x90:
			sent.append(b)
	Midi.message_sent.connect(spy)
	surface.trigger_note(a)
	_check(sent.size() == 1 and surface.waves.size() == 1, "plays and pulses")
	surface.waves.clear()
	surface.step(1.0)
	surface.trigger_note(a)
	_check(sent.size() == 1 and surface.waves.is_empty(), "the toggle silences both")
	Midi.message_sent.disconnect(spy)
	surface.stop()
	radial.outer_chosen.emit("sequence")
	_check(surface.get_note(a).modifiers.size() == 1, "removes just that one")
	radial.outer_chosen.emit("")
	_check(surface.get_note(a).modifiers.is_empty(), "None clears them")
	radial.close()
	surface.clear_notes()


func _tabs() -> void:
	var a := surface.add_note_at(Vector2(400, 300), 60, 0)
	var b := surface.add_note_at(Vector2(700, 300), 62, 0)
	surface.add_modifier(a, "relay")
	surface.add_modifier(a, "sequence")
	surface.selection.notes = {a: true, b: true}
	var o := surface.get_note(a)
	var e := o.emitter()
	tools.set_tool("select")
	# The relay's diamond, docked upper right.
	var dock := e.dock_screen_pos(surface, o)
	_check(dock.x > 400 and dock.y < 300, "docked upper right")
	_press(MOUSE_BUTTON_RIGHT, true, dock)
	_check(radial.visible and tools.open_ring.tool_id() == "relay_settings", "right-click the diamond")
	radial.outer_chosen.emit(2.0)
	_check(e.cooldown == 2.0, "cooldown")
	radial.inner_chosen.emit(0.5)
	_check(e.strength == 0.5, "strength")
	radial.center_chosen.emit("sound")
	_check(not o.relay().sound and not o.shows_pitch(), "centre turns Sound off")
	radial.center_chosen.emit("sound")
	_check(o.relay().sound, "and back on")
	radial.close()
	# Remote: the diamond and the dim handle both open it, at the diamond.
	e.attached = false
	e.pos = surface.to_world(Vector2(900, 600))
	_press(MOUSE_BUTTON_RIGHT, true, dock)
	_check(radial.visible and tools.open_ring.tool_id() == "relay_settings", "the dim handle opens it")
	radial.close()
	_press(MOUSE_BUTTON_RIGHT, true, Vector2(900, 600))
	_check(radial.visible and tools.open_ring.tool_id() == "relay_settings", "the remote diamond opens it")
	_check(radial._center.is_equal_approx(Vector2(900, 600)), "at the click")
	radial.close()
	_check(surface.pick_at(dock) == ["emitter", a], "the dim handle can be grabbed")
	surface.drag.begin(a, "emitter", dock)
	surface.drag.moved = true
	surface.drag.move_to(Vector2(500, 500), true)
	surface.drag.end()
	_check(not e.attached and surface.to_screen(e.pos) == Vector2(500, 500), "dragging it places the diamond")
	surface.drag.begin(a, "emitter", dock)
	surface.drag.moved = true
	surface.drag.move_to(Vector2(400, 300), true)
	surface.drag.end()
	_check(e.attached, "dropping on the note recalls it")
	# The toggle's tab.
	var tab: Vector2 = o.get_modifier("sequence")._tab_centre(surface, o)
	_press(MOUSE_BUTTON_RIGHT, true, tab)
	_check(radial.visible and tools.open_ring.tool_id() == "sequence_settings", "right-click the toggle tab")
	radial.inner_chosen.emit(3)
	var t: SequenceModifier = o.get_modifier("sequence")
	_check(t.steps == [true, false, true], "the inner ring sets the step count, and new steps are On")
	_check(radial.outer_items.size() == 3 and radial.inner_items.size() == 16, "the outer ring has a segment per step")
	radial.outer_chosen.emit(1)
	_check(t.steps == [true, true, true] and radial.outer_items[1].selected and radial.visible, "the outer ring toggles a step, and stays open")
	radial.close()
	# Not on a tab, and not in Tap.
	_press(MOUSE_BUTTON_RIGHT, true, Vector2(600, 600))
	_check(not radial.visible, "elsewhere nothing opens")
	tools.set_tool("tap")
	_press(MOUSE_BUTTON_RIGHT, true, dock)
	_check(not radial.visible, "Tap locks tabs too")
	tools.set_tool("select")
	surface.selection.clear()
	surface.clear_notes()


func _radial_press(button: MouseButton, down: bool, at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = down
	e.position = at
	radial._input(e)


func _radial_move(at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	radial._input(e)


func _quick_pick() -> void:
	var a := surface.add_note_at(Vector2(640, 400), 60, 0)
	surface.add_modifier(a, "relay")
	surface.add_modifier(a, "sequence")
	var o := surface.get_note(a)
	var e: Emitter = o.emitter()
	tools.set_tool("select")
	var dock: Vector2 = e.dock_screen_pos(surface, o)
	var open_ring := func() -> Vector2:
		_press(MOUSE_BUTTON_RIGHT, true, dock)
		return radial._center
	# Outer: release picks and closes.
	var c: Vector2 = open_ring.call()
	_check(radial.holding, "opens held")
	var item: Vector2 = c + Vector2(0, -112)         # the top of the outer ring: Retrigger
	_radial_move(item)
	_radial_press(MOUSE_BUTTON_RIGHT, false, item)
	_check(e.cooldown == 0.0 and not radial.visible, "release on the outer ring picks and closes")
	# Inner.
	c = open_ring.call()
	item = c + Vector2(0, -54)                       # the top of the inner ring: 25%
	_radial_move(item)
	_radial_press(MOUSE_BUTTON_RIGHT, false, item)
	_check(e.strength == 0.25 and not radial.visible, "release on the inner ring picks and closes")
	# Centre.
	c = open_ring.call()
	_radial_move(c + Vector2(0, -112))
	_radial_move(c)
	_radial_press(MOUSE_BUTTON_RIGHT, false, c)
	_check(not o.relay().sound and not radial.visible, "release on the centre picks and closes")
	o.relay().sound = true
	# Off the rings: cancels.
	var settings := JSON.stringify(e.to_dict())
	c = open_ring.call()
	_radial_move(c + Vector2(250, 0))
	_radial_press(MOUSE_BUTTON_RIGHT, false, c + Vector2(250, 0))
	_check(not radial.visible and JSON.stringify(e.to_dict()) == settings and o.relay().sound, "release off the rings cancels")
	# No move: stays open, and left clicks pick without closing.
	c = open_ring.call()
	_radial_press(MOUSE_BUTTON_RIGHT, false, c)
	_check(radial.visible and not radial.holding and o.relay().sound, "release without moving stays open")
	var left := InputEventMouseButton.new()
	left.button_index = MOUSE_BUTTON_LEFT
	left.pressed = true
	left.position = c + Vector2(0, -112)
	radial._gui_input(left)
	_check(radial.visible and e.cooldown == 0.0, "left click picks and stays open")
	left.position = c + Vector2(250, 0)
	radial._gui_input(left)
	_check(not radial.visible, "left click off the rings closes")
	# A left click during the hold picks too.
	e.cooldown = 1.0
	c = open_ring.call()
	_radial_press(MOUSE_BUTTON_LEFT, true, c + Vector2(0, -112))
	_check(radial.visible and radial.holding and e.cooldown == 0.0, "left click during the hold keeps it open")
	_radial_press(MOUSE_BUTTON_RIGHT, false, c)
	radial.close()
	# The toggle's ring, and the group.
	var tab: Vector2 = o.get_modifier("sequence")._tab_centre(surface, o)
	_press(MOUSE_BUTTON_RIGHT, true, tab)
	c = radial._center
	item = c + Vector2(0, -100)                      # step 1, at the top
	_radial_move(item)
	_radial_press(MOUSE_BUTTON_RIGHT, false, item)
	_check(o.get_modifier("sequence").steps == [false, false] and not radial.visible, "works on the sequence ring")
	surface.clear_notes()


func _ring_options() -> void:
	var a := surface.add_note_at(Vector2(640, 400), 60, 0)
	var b := surface.add_note_at(Vector2(900, 400), 62, 0)
	tools.set_tool("select")
	_check(tools.ring_option.tool_id() == "pitch", "pitch by default")
	tools.pick("modifier")
	_check(tools.current_id() == "select" and tools.ring_option.tool_id() == "modifier", "an option doesn't change the tool")
	tools.set_tool("channel")
	_check(tools.current_id() == "select", "and can't be made the tool")
	for option in ["pitch", "channel", "modifier"]:
		tools.pick(option)
		_press(MOUSE_BUTTON_RIGHT, true, Vector2(640, 400))
		_check(radial.visible and radial.holding and tools.open_ring.tool_id() == option, "%s opens on a note" % option)
		radial.close()
	tools.pick("modifier")
	_press(MOUSE_BUTTON_RIGHT, true, Vector2(100, 100))
	_check(not radial.visible, "empty space opens nothing")
	# Quick pick adds; the same pick removes; a group follows.
	_press(MOUSE_BUTTON_RIGHT, true, Vector2(640, 400))
	var c: Vector2 = radial._center
	var toggle_at: Vector2 = c + Vector2.from_angle(-PI / 2.0 + TAU / 3.0) * 112.0
	_radial_move(toggle_at)
	_radial_press(MOUSE_BUTTON_RIGHT, false, toggle_at)
	_check(surface.get_note(a).get_modifier("sequence") != null and not radial.visible, "quick pick adds a modifier")
	surface.selection.notes = {a: true, b: true}
	_press(MOUSE_BUTTON_RIGHT, true, Vector2(640, 400))
	_radial_move(toggle_at)
	_radial_press(MOUSE_BUTTON_RIGHT, false, toggle_at)
	_check(surface.get_note(a).modifiers.is_empty(), "picking it again removes it")
	_press(MOUSE_BUTTON_RIGHT, true, Vector2(640, 400))
	_radial_move(toggle_at)
	_radial_press(MOUSE_BUTTON_RIGHT, false, toggle_at)
	_check(surface.get_note(b).get_modifier("sequence") != null, "the group follows")
	surface.selection.clear()
	# A tab still wins, and Tap keeps rings off.
	var o := surface.get_note(a)
	_press(MOUSE_BUTTON_RIGHT, true, o.get_modifier("sequence")._tab_centre(surface, o))
	_check(tools.open_ring.tool_id() == "sequence_settings", "a tab opens its settings")
	radial.close()
	tools.set_tool("tap")
	_press(MOUSE_BUTTON_RIGHT, true, Vector2(640, 400))
	_check(not radial.visible, "Tap opens no rings")
	tools.pick("pitch")
	tools.set_tool("select")
	surface.clear_notes()


func _tab() -> void:
	var cases := ["select", "select", "pan", "zoom"]
	for id in cases:
		tools.set_tool(id)
		_key(KEY_TAB)
		_check(tools.current_id() == "tap" and not tools.is_editing(), "Tab from %s goes to Tap" % id)
		_key(KEY_TAB)
		_check(tools.current_id() == id and tools.is_editing(), "Tab returns to %s" % id)
	tools.set_tool("select")
	tools.pick("tap")
	_key(KEY_TAB)
	_check(tools.current_id() == "select", "Tap picked on the bar returns too")
	# A ring option isn't a tool, so it's left alone.
	tools.pick("channel")
	_key(KEY_TAB)
	_key(KEY_TAB)
	_check(tools.current_id() == "select" and tools.ring_option.tool_id() == "channel", "the ring option stays")
	tools.pick("pitch")
	# Nothing happens during a spring-load.
	_press(MOUSE_BUTTON_MIDDLE, true, Vector2.ZERO)
	_key(KEY_TAB)
	_check(tools.current_id() == "pan", "ignored while spring-loaded")
	_press(MOUSE_BUTTON_MIDDLE, false, Vector2.ZERO)
	_check(tools.current_id() == "select", "spring-load still returns")
	var ctrl := InputEventKey.new()
	ctrl.keycode = KEY_TAB
	ctrl.pressed = true
	ctrl.ctrl_pressed = true
	tools.handle_input(ctrl)
	_check(tools.current_id() == "select", "Ctrl+Tab does nothing")
	tools.set_tool("select")


func _kp(digit: int, down: bool = true) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = (KEY_KP_0 + digit) as Key
	e.pressed = down
	tools.handle_input(e)


func _bindings() -> void:
	var a := surface.add_note_at(Vector2(300, 300), 60, 0)
	var b := surface.add_note_at(Vector2(500, 300), 62, 0)
	var r := surface.add_note_at(Vector2(700, 300), 64, 0)
	surface.add_modifier(r, "relay")
	surface.set_relay_sound(r, false)
	var ao := surface.get_note(a)
	var bind: BindTool = tools.get_tool("bind")
	# Stop.
	tools.set_tool("tap")
	for code in [KEY_SPACE, KEY_KP_ENTER]:
		surface.spawn_wave(Vector2(100, 100))
		_key(code)
		_check(surface.waves.is_empty(), "%s stops" % OS.get_keycode_string(code))
	# Arm and bind.
	tools.set_tool("bind")
	surface.history.end_group()
	var steps := surface.history.undo_steps()
	_click(Vector2(300, 300))
	_check(bind.armed() and ao.binding == "", "a click arms")
	_kp(3)
	_kp(3, false)
	_check(ao.binding == "kp3" and not bind.armed(), "a key binds and disarms")
	_check(surface.history.undo_steps() == steps + 1, "binding can be undone")
	surface.history.end_group()
	_click(Vector2(300, 300))
	tools.binding_pressed("midi36")
	tools.binding_released("midi36")
	_check(ao.binding == "midi36", "a new binding replaces the old")
	_check(ao.binding_label() == MidiMessage.note_name(36) and ao.hover_text().contains("MIDI"), "MIDI label")
	surface.history.end_group()
	_click(Vector2(300, 300))
	_kp(0)
	_kp(0, false)
	_check(ao.binding == "kp0", "KP0 binds")
	surface.history.end_group()
	var count := Settings.notes.size()
	# Shared, and a group; Esc and empty space disarm; Delete clears without removing.
	_click(Vector2(500, 300))
	_kp(0)
	_kp(0, false)
	_check(surface.get_note(b).binding == "kp0", "many notes can share one")
	surface.history.end_group()
	_click(Vector2(300, 300))
	_key(KEY_DELETE)
	_check(ao.binding == "" and not bind.armed() and Settings.notes.size() == count, "Delete clears the binding")
	surface.history.end_group()
	_click(Vector2(300, 300))
	_key(KEY_ESCAPE)
	_check(not bind.armed(), "Esc disarms")
	_click(Vector2(300, 300))
	_click(Vector2(100, 600))
	_check(not bind.armed(), "empty space disarms")
	_click(Vector2(300, 300))
	tools.set_tool("select")
	_check(not bind.armed(), "leaving the tool disarms")
	surface.selection.notes = {a: true, b: true}
	tools.set_tool("bind")
	_click(Vector2(300, 300))
	_kp(7)
	_kp(7, false)
	_check(ao.binding == "kp7" and surface.get_note(b).binding == "kp7", "a selected note binds its group")
	surface.selection.clear()
	surface.history.end_group()
	# Firing: as a tap, in any tool.
	surface.set_binding(r, "kp7")
	surface.get_note(r).emitter().own_reach = 60.0   # its waves stay clear of the notes
	surface.history.end_group()
	var sent: Array = []
	var spy := func(m: PackedByteArray) -> void:
		if (m[0] & 0xF0) == 0x90:
			sent.append(m)
	Midi.message_sent.connect(spy)
	tools.set_tool("tap")
	surface.get_note(a).muted = true
	surface.step(1.0)
	_kp(7)
	_check(sent.size() == 2, "fires as a tap, overriding mute")
	_check(surface.waves.size() == 1 and surface.waves[0].source == r, "only the relay sends a wave")
	# Held: the relay refires, notes don't.
	surface.stop()
	var refired := 0
	for i in 150:
		surface.step(1.0 / 60.0)
		refired = maxi(refired, surface.waves.size())
	_check(refired >= 1 and sent.size() == 2, "held: the relay refires, notes don't")
	_kp(7, false)
	surface.stop()
	for i in 150:
		surface.step(1.0 / 60.0)
	_check(surface.waves.is_empty(), "released: no more")
	surface.get_note(r).emitter().cooldown = 0.0
	surface.step(1.0)
	_kp(7)
	surface.stop()
	for i in 150:
		surface.step(1.0 / 60.0)
	_check(surface.waves.is_empty(), "retrigger doesn't refire")
	_kp(7, false)
	# MIDI fires the same way.
	sent.clear()
	surface.set_binding(b, "midi40")
	tools.binding_pressed("midi40")
	tools.binding_released("midi40")
	_check(sent.size() == 1, "MIDI fires")
	Midi.message_sent.disconnect(spy)
	# Saves.
	Settings.notes = [{"x": 0.0, "y": 0.0, "note": 60, "channel": 0, "slot": 4, "id": 2}]
	surface.load_notes()
	_check(surface.get_note(2).binding == "kp4", "old slots carry over")
	surface.save_notes()
	_check(Settings.notes[0].binding == "kp4" and not Settings.notes[0].has("slot"), "saved as a binding")
	tools.set_tool("select")
	surface.stop()
	surface.clear_notes()


func _grid_tool() -> void:
	var a := surface.add_note_at(Vector2(300, 300), 60, 0)
	var r := surface.add_note_at(Vector2(700, 300), 64, 0)
	surface.add_modifier(r, "relay")
	surface.history.end_group()
	var ao := surface.get_note(a)
	var ro := surface.get_note(r)
	var e: Emitter = ro.emitter()
	tools.set_tool("grid")
	var steps := surface.history.undo_steps()
	_click(Vector2(300, 300))
	_check(ao.grid != null, "click adds an origin")
	_check(surface.history.undo_steps() == steps + 1, "an undo step")
	surface.history.end_group()
	_click(Vector2(300, 300))
	_check(ao.grid == null, "click again removes it")
	surface.history.end_group()
	_click(Vector2(100, 100))
	_check(surface.snapping.active_grids().is_empty(), "empty space does nothing")
	# Automatic reach: a beat past the global Reach, or a relay's own.
	_click(Vector2(300, 300))
	surface.history.end_group()
	_check(ao.grid_limit() == Settings.wave_range + Settings.BEAT_UNIT, "a note: wave reach + 1 beat")
	Settings.wave_range += 100.0
	_check(ao.grid_limit() == Settings.wave_range + Settings.BEAT_UNIT, "and it follows the setting")
	Settings.wave_range -= 100.0
	_click(Vector2(700, 300))
	e.own_reach = 300.0
	_check(ro.grid_limit() == 300.0, "a docked relay: its reach")
	surface.history.end_group()
	_click(Vector2(700, 300))
	e.attached = false
	e.pos = surface.to_world(Vector2(900, 500))
	surface.save_notes()
	surface.history.end_group()
	var dock: Vector2 = e.dock_screen_pos(surface, ro)
	_click(dock)
	_check(ro.grid == null and e.grid == null, "a dim handle does nothing")
	_click(Vector2(900, 500))
	_check(e.grid != null and e.grid_limit() == 300.0, "a remote diamond: its reach")
	surface.history.end_group()
	e.grid = null
	e.attached = true
	e.own_reach = 0.0
	surface.save_notes()
	surface.history.end_group()
	var docked := e.dock_screen_pos(surface, ro)
	_click(docked + Vector2(9, -9))
	_check(e.grid == null, "a docked diamond does nothing")
	# Drag sets reach: snapped, Alt free, back on the origin automatic; press outside the threshold.
	steps = surface.history.undo_steps()
	_drag(Vector2(300, 300), Vector2(300 + 317, 300))
	_check(ao.grid != null and is_equal_approx(ao.grid.reach * surface.z(), 300.0), "drag sets reach, snapped")
	_check(surface.history.undo_steps() == steps + 1, "one undo step")
	surface.history.end_group()
	_drag(Vector2(300, 300), Vector2(300 + 317, 300), true)
	_check(is_equal_approx(ao.grid.reach * surface.z(), 317.0), "Alt leaves it unsnapped")
	surface.history.end_group()
	_drag(Vector2(300, 300), Vector2(303, 300))
	_check(ao.grid == null, "a drag under the threshold is a click")
	surface.history.end_group()
	# Snapping stops at the reach.
	ao.grid = Grid.new()
	ao.grid.reach = 400.0
	surface.save_notes()
	surface.history.end_group()
	var inside: Vector2 = ao.pos + Vector2(303, 3)
	var outside: Vector2 = ao.pos + Vector2(603, 3)
	_check(surface.snapping.grid_snap(inside) != inside, "snaps inside the reach")
	_check(surface.snapping.grid_snap(outside) == outside, "not past it")
	var held := surface.add_note_at(Vector2(100, 700), 62, 0)
	var info := surface.snapping.compute_drag(surface.get_note(held), "note", outside, false)
	_check(not info.snapped and info.limits[1] == 400.0, "nor does a drag")
	# Saved.
	surface.save_notes()
	var saved: Array = Settings.notes.duplicate(true)
	surface.load_notes()
	_check(surface.get_note(a).grid.reach == 400.0, "reach survives a reload")
	surface.save_notes()
	_check(JSON.stringify(saved) == JSON.stringify(Settings.notes), "and round-trips")
	tools.set_tool("select")
	surface.clear_notes()


func _tool_options() -> void:
	var has: Array = []
	for item in tools.tools:
		if item.has_options():
			has.append(item.tool_id())
	has.sort()
	_check(has == ["bind", "channel", "collection", "grid", "pitch", "tap", "zoom"], "these tools have panels")
	for id in has:
		var box := VBoxContainer.new()
		add_child(box)
		tools.get_tool(id).build_options(box)
		_check(box.get_child_count() > 0, "%s builds its panel" % id)
		box.queue_free()
	# Every setting explains itself, in tool panels and Options.
	var holders: Array = []
	for id in has:
		var box := VBoxContainer.new()
		add_child(box)
		tools.get_tool(id).build_options(box)
		holders.append(box)
	var options := OptionsPanel.new()
	options.mappings = MidiMappings.new(surface)
	add_child(options)
	holders.append(options)
	for holder in holders:
		for kind in ["HSlider", "CheckButton", "OptionButton", "Button"]:
			for c in holder.find_children("*", kind, true, false):
				if c.get_parent() is not TabBar and c.get_class() != "PopupMenu":
					_check(c.tooltip_text != "", "%s %s has a tooltip" % [kind, c.text if c is Button else c.name])
	for key in PanelBuilder.TIPS:
		_check(key in Settings, "tip key %s is a setting" % key)
		_check(PanelBuilder.TIPS[key].length() <= 100, "tip %s is short" % key)
	for holder in holders:
		holder.queue_free()
	var a := surface.add_note_at(Vector2(300, 300), 60, 0)
	var b := surface.add_note_at(Vector2(500, 300), 62, 0)
	surface.snapping.toggle_grid(surface.get_note(a), false)
	surface.snapping.toggle_grid(surface.get_note(b), false)
	surface.history.end_group()
	var notices: Array = []
	var spy := func(text: String) -> void: notices.append(text)
	tools.notice.connect(spy)
	var grid: GridTool = tools.get_tool("grid")
	var steps := surface.history.undo_steps()
	grid.clear_all()
	_check(surface.snapping.active_grids().is_empty() and notices == ["Grids cleared"], "Clear All works from any tool")
	_check(surface.history.undo_steps() == steps + 1, "and can be undone")
	surface.history.end_group()
	surface.undo()
	_check(surface.snapping.active_grids().size() == 2, "undo restores them")
	surface.history.end_group()
	surface.snapping.clear_grids()
	surface.history.end_group()
	grid.clear_all()
	_check(notices[-1] == "No grids on", "says when there are none")
	tools.notice.disconnect(spy)
	surface.clear_notes()
	# Scale: existing notes keep their pitch; a nudge lands on the scale.
	var n := surface.add_note_at(Vector2(300, 300), 60, 0)
	var scale_before: String = Settings.scale_name
	var o := surface.get_note(n)
	o.note = 61
	Settings.set_value("scale_name", "Major")
	_check(o.note == 61, "a scale change leaves notes alone")
	surface.selection.notes = {n: true}
	surface.nudge_pitch(1, false)
	_check(Scales.quantize(o.note, Settings.root_note, "Major") == o.note and o.note > 61, "a nudge lands on the scale")
	o.note = 61
	surface.nudge_pitch(-1, false)
	_check(Scales.quantize(o.note, Settings.root_note, "Major") == o.note and o.note < 61, "down too")
	surface.selection.clear()
	tools.open_ring_for("pitch", n, Vector2(600, 400))
	var shown: Array = radial.outer_items.map(func(i: Dictionary) -> int: return i.id)
	_check(shown == Scales.octave_notes(tools.get_tool("pitch")._octave, Settings.root_note, "Major"), "the ring shows the scale")
	radial.close()
	Settings.set_value("scale_name", scale_before)
	surface.clear_notes()


func _knobs(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Knob:
			out.append(c)
		out.append_array(_knobs(c))
	return out


func _knob_input(k: Knob, e: InputEvent) -> void:
	k._gui_input(e)


func _channel_volume() -> void:
	var sent: Array = []
	var spy := func(m: PackedByteArray) -> void:
		if (m[0] & 0xF0) == 0x90:
			sent.append(m)
	Midi.message_sent.connect(spy)
	var a := surface.add_object(Vector2.ZERO, 60, 2)
	var o := surface.get_note(a)
	var box := VBoxContainer.new()
	add_child(box)
	tools.get_tool("channel").build_options(box)
	var volume: Knob = _knobs(box)[4]                # channel 3's volume
	_check(volume.value == 1.0 and volume.fmt.call(volume.value) == "100%", "starts at full")
	# Turning the knob: drag, scroll, double-click.
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	volume._gui_input(press)
	var move := InputEventMouseMotion.new()
	move.button_mask = MOUSE_BUTTON_MASK_LEFT
	move.relative = Vector2(0, 75)
	volume._gui_input(move)
	_check(volume.value == 0.5 and Settings.channel_volumes[2] == 0.5, "dragging down turns it down")
	var free := InputEventMouseMotion.new()
	free.relative = Vector2(0, 60)
	volume._gui_input(free)
	_check(volume.value == 0.5, "only with the button held")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	volume._gui_input(wheel)
	_check(is_equal_approx(volume.value, 0.55), "scrolling steps it")
	var twice := InputEventMouseButton.new()
	twice.button_index = MOUSE_BUTTON_LEFT
	twice.pressed = true
	twice.double_click = true
	volume._gui_input(twice)
	_check(volume.value == 1.0 and Settings.channel_volumes[2] == 1.0, "double-click resets")
	# Velocity scales, on this channel only.
	o.play(surface, 1.0, 0)
	_check(sent[-1][2] == 127, "full volume")
	Settings.set_channel_volume(2, 0.5)
	o.silence()
	o.play(surface, 1.0, 0)
	_check(sent[-1][2] == 64, "half volume halves velocity")
	o.silence()
	o.channel = 3
	o.play(surface, 1.0, 0)
	_check(sent[-1][2] == 127, "other channels are unaffected")
	o.silence()
	o.channel = 2
	Settings.set_channel_volume(2, 0.05)
	o.play(surface, 0.05, 0)
	_check(sent[-1][2] == 1, "low volume still sounds")
	o.silence()
	# Off: no note, but a relay still fires.
	Settings.set_channel_volume(2, 0.0)
	sent.clear()
	surface.add_modifier(a, "relay")
	surface.trigger_note(a)
	_check(sent.is_empty() and surface.waves.size() == 1, "off silences it, and the relay still fires")
	Midi.play_note(60, 90, 0.25, 2)
	_check(sent.is_empty(), "previews follow it")
	Settings.set_channel_volume(2, 1.0)
	Midi.play_note(60, 90, 0.25, 2)
	_check(sent.size() == 1 and sent[0][2] == 90, "at full, previews are unchanged")
	# Reset all, and it persists.
	Settings.set_channel_volume(5, 0.3)
	Settings.set_channel_beats(5, 2.0)
	box.queue_free()
	var box2 := VBoxContainer.new()
	add_child(box2)
	tools.get_tool("channel").build_options(box2)
	var ks := _knobs(box2)
	_check(is_equal_approx(ks[10].value, 0.3) and ks[11].value == 2.0, "the panel shows stored values")
	for b in box2.find_children("*", "Button", true, false):
		if b.text == "Reset all":
			b.pressed.emit()
	_check(Settings.channel_volumes[5] == 1.0 and Settings.channel_beats[5] == 0.0, "Reset all clears both")
	box2.queue_free()
	Midi.message_sent.disconnect(spy)
	surface.stop()
	surface.clear_notes()


func _midi_event(message: int, field: String = "", value: int = 0, value2: int = 0) -> InputEventMIDI:
	var e := InputEventMIDI.new()
	e.message = message as MIDIMessage
	if field == "note":
		e.pitch = value
		e.velocity = value2
	elif field == "cc":
		e.controller_number = value
		e.controller_value = value2
	return e


func _midi_controls() -> void:
	var saved: Dictionary = Settings.midi_mappings
	Settings.midi_mappings = MidiMappings.DEFAULTS.duplicate()
	var map := MidiMappings.new(surface)
	var fired: Array = []
	map.triggered.connect(func(a: String) -> void: fired.append(a))
	var midi_in := MidiInput.new()
	midi_in.message_received.connect(map.receive)
	var pressed: Array = []
	midi_in.note_pressed.connect(func(p: int) -> void: pressed.append(map.listening))
	Settings.midi_in_port = "Keys"
	midi_in._names = ["Keys", "loopMIDI"]
	# The default, and where messages may come from.
	var stop := _midi_event(MIDI_MESSAGE_STOP)
	_check(midi_in.handle(stop) and fired == ["stop"], "MIDI Stop runs Stop by default")
	stop.device = 1
	_check(not midi_in.handle(stop) and fired.size() == 1, "not from another input")
	stop.device = 0
	Settings.midi_in_port = ""
	_check(not midi_in.handle(stop) and fired.size() == 1, "nor with input Off")
	Settings.midi_in_port = "Keys"
	# Learning.
	fired.clear()
	map.listen("panic")
	midi_in.handle(_midi_event(MIDI_MESSAGE_CONTROL_CHANGE, "cc", 20, 127))
	_check(map.listening == "" and map.key_for("panic") == "cc20" and fired.is_empty(), "learning doesn't fire")
	midi_in.handle(_midi_event(MIDI_MESSAGE_CONTROL_CHANGE, "cc", 20, 0))
	midi_in.handle(_midi_event(MIDI_MESSAGE_CONTROL_CHANGE, "cc", 20, 40))
	midi_in.handle(_midi_event(MIDI_MESSAGE_CONTROL_CHANGE, "cc", 20, 90))
	_check(fired == ["panic"], "a CC fires once on rising above 0")
	midi_in.handle(_midi_event(MIDI_MESSAGE_CONTROL_CHANGE, "cc", 20, 0))
	midi_in.handle(_midi_event(MIDI_MESSAGE_CONTROL_CHANGE, "cc", 20, 127))
	_check(fired.size() == 2, "and again after returning to 0")
	# Notes: the binding is told before the note is learned, and can stand aside.
	map.listen("panic")
	midi_in.handle(_midi_event(MIDI_MESSAGE_NOTE_ON, "note", 60, 100))
	_check(pressed == ["panic"] and map.key_for("panic") == "note60", "a note learns")
	midi_in.handle(_midi_event(MIDI_MESSAGE_NOTE_OFF, "note", 60))
	fired.clear()
	midi_in.handle(_midi_event(MIDI_MESSAGE_NOTE_ON, "note", 60, 100))
	_check(fired == ["panic"] and pressed[-1] == "", "a mapped note fires")
	midi_in.handle(_midi_event(MIDI_MESSAGE_NOTE_ON, "note", 60, 0))
	_check(fired.size() == 1, "a Note On at velocity 0 is a release")
	# One message, one action.
	map.listen("stop")
	map.receive("note60")
	_check(map.key_for("stop") == "note60" and map.key_for("panic") == "", "a message moves to the new action")
	# Bound notes.
	var a := surface.add_object(Vector2.ZERO, 60, 0)
	var b := surface.add_object(Vector2(100, 0), 62, 0)
	surface.set_binding(a, "midi60")
	surface.set_binding(b, "midi60")
	_check(map.bound_notes("note60") == 2 and map.bound_notes("cc60") == 0, "bound notes are counted")
	surface.clear_notes()
	# Labels, clearing and cancelling.
	_check(MidiMappings.label("note60") == "Note C4" and MidiMappings.label("cc20") == "CC 20", "labels")
	_check(MidiMappings.label("rt252") == "MIDI Stop" and MidiMappings.label("") == "Not set", "more labels")
	map.clear("stop")
	_check(map.key_for("stop") == "", "Clear removes it")
	map.listen("stop")
	map.cancel()
	map.receive("cc1")
	_check(map.key_for("stop") == "", "cancel stops listening")
	map.reset()
	_check(map.key_for("stop") == "rt252" and map.key_for("panic") == "", "Reset returns to the defaults")
	# The tab. With no controller chosen, since the panel lists the inputs, and there are none here.
	Settings.midi_in_port = ""
	var options := OptionsPanel.new()
	options.mappings = map
	add_child(options)
	options._control_rows["panic"].learn.pressed.emit()
	_check(map.listening == "panic" and options._control_rows["panic"].learn.text == "Cancel", "Learn listens")
	_check(options._control_rows["panic"].value.text == "Listening...", "and says so")
	options.toggle()
	options.toggle()
	_check(map.listening == "", "closing Options cancels")
	options.toggle()
	options._control_rows["panic"].learn.pressed.emit()
	options.tabs.current_tab = 2
	_check(map.listening == "", "changing tab cancels")
	options.tabs.current_tab = 0
	options._control_rows["stop"].clear.pressed.emit()
	_check(options._control_rows["stop"].value.text == "Not set" and options._control_rows["stop"].clear.disabled, "Clear shows")
	options.queue_free()
	midi_in.free()
	Settings.midi_mappings = saved


func _held_during_cooldown() -> void:
	var a := surface.add_object(Vector2.ZERO, 60, 0)
	surface.add_modifier(a, "relay")
	surface.set_binding(a, "kp1")
	var e: Emitter = surface.get_note(a).emitter()
	e.cooldown = 2.0
	var length := float(e.cooldown_usec()) / 1_000_000.0
	var run := func(seconds: float) -> void:
		for i in int(seconds * 120.0):
			surface.step(1.0 / 120.0)
	surface.press_binding("kp1")
	surface.release_binding("kp1")
	var first: int = e.ready_at
	run.call(length * 0.5)
	var sent: Array = []
	var spy := func(m: PackedByteArray) -> void:
		if (m[0] & 0xF0) == 0x90:
			sent.append(m)
	Midi.message_sent.connect(spy)
	surface.add_modifier(a, "sequence")
	var seq: SequenceModifier = surface.get_note(a).get_modifier("sequence")
	seq.steps = [true, false]
	surface.press_binding("kp1")
	_check(e.ready_at == first and sent.is_empty() and seq.pos == 0, "a press during a cooldown does nothing")
	run.call(length * 0.4)
	_check(e.ready_at == first and sent.is_empty(), "nor before it ends")
	run.call(length * 0.15)
	_check(e.ready_at > first and e.ready_at <= first + e.cooldown_usec() + 20000, "held, it fires as the cooldown ends")
	_check(sent.size() == 1 and seq.pos == 1, "once, with its sound, taking one step")
	surface.remove_modifier(a, "sequence")
	Midi.message_sent.disconnect(spy)
	var second: int = e.ready_at
	surface.release_binding("kp1")
	run.call(length * 0.5)
	surface.press_binding("kp1")
	surface.release_binding("kp1")
	run.call(length * 0.7)
	_check(e.ready_at == second, "released in time, it doesn't")
	surface.stop()
	surface.clear_notes()


func _collections() -> void:
	var tool: CollectionTool = tools.get_tool("collection")
	tools.set_tool("select")
	surface.clear_notes()
	surface.selection.clear()
	for n in Collections.list():
		Collections.remove(n)
	var a := surface.add_object(Vector2(100, 100), 60, 2)
	var b := surface.add_object(Vector2(300, 100), 64, 3)
	var c := surface.add_object(Vector2(900, 900), 67, 4)
	surface.add_modifier(a, "relay")
	surface.add_modifier(b, "sequence")
	surface.set_sequence_count(b, 5)
	surface.set_sequence_step(b, 2, false)
	surface.set_binding(b, "kp4")
	surface.snapping.toggle_grid(surface.get_note(b), false)
	var e: Emitter = surface.get_note(a).emitter()
	e.attached = false
	e.pos = Vector2(100, 200)
	surface.get_note(a).snap_note = "n%d" % b
	surface.get_note(b).snap_note = "n%d" % c          # outside the group
	# Saving.
	_check(tool.save_selection("Pair") == "Select some notes first.", "saving needs a selection")
	surface.selection.notes = {a: true, b: true}
	_check(tool.save_selection("  ") == "Give it a name first.", "and a name")
	_check(tool.save_selection(" kits / Bells 1 ") == "", "a name saves")
	_check(Array(Collections.list()) == ["kits/Bells 1"], "trimmed, and listed with its folder")
	_check(FileAccess.file_exists("user://collections/kits/Bells 1.json"), "as a JSON file in the folder")
	_check(tool.save_selection("kits/Bells 1") == "That name is already used.", "a used name is refused")
	_check(tool.save_selection("KITS\\bells 1") == "That name is already used.", "in any case, with either slash")
	_check(Collections.list().size() == 1, "and nothing changes")
	# Placing a copy: everything comes back, around the drop point.
	var before := surface.notes.size()
	Settings.snap_enabled = false
	var added := tool.drop("kits/Bells 1", surface.to_screen(Vector2(500, 500)))
	Settings.snap_enabled = true
	_check(added == 2 and surface.notes.size() == before + 2, "dropping adds the notes")
	_check(surface.selection.notes.size() == 2 and not surface.selection.notes.has(a), "which become the selection")
	var ids: Array = surface.selection.notes.keys()
	ids.sort()
	var pa := surface.get_note(ids[0])
	var pb := surface.get_note(ids[1])
	_check(pa.pos == Vector2(400, 500) and pb.pos == Vector2(600, 500), "around the drop point")
	_check(pa.emitter().pos == Vector2(400, 600) and not pa.emitter().attached, "with its remote emitter")
	_check(pb.note == 64 and pb.channel == 3 and pb.binding == "kp4" and pb.grid != null, "binding and grid kept")
	_check(pb.get_modifier("sequence").steps == [true, false, false, true, true], "modifiers kept")
	_check(pa.snap_note == "n%d" % pb.id, "snap memory follows the group")
	_check(pb.snap_note == "", "and links outside it are dropped")
	surface.undo()
	_check(surface.notes.size() == before, "one undo removes the lot")
	# Stamping.
	surface.selection.clear()
	tools.set_tool("select")
	tool.pick("kits/Bells 1")
	_check(tools.current == tool, "picking a row switches to the tool")
	_press(MOUSE_BUTTON_LEFT, true, Vector2(500, 300))
	_press(MOUSE_BUTTON_LEFT, false, Vector2(500, 300))
	_press(MOUSE_BUTTON_LEFT, true, Vector2(700, 500))
	_press(MOUSE_BUTTON_LEFT, false, Vector2(700, 500))
	_check(surface.notes.size() == before + 4, "each click stamps a copy")
	surface.undo()
	surface.undo()
	# The panel.
	var box := VBoxContainer.new()
	add_child(box)
	tool.build_options(box)
	var row: CollectionRow = box.find_children("*", "CollectionRow", true, false)[0]
	_check(row.handle.button_pressed and row.handle.collection == "kits/Bells 1", "the picked row is lit")
	_check(surface._can_drop_data(Vector2(300, 300), {"collection": "kits/Bells 1"}), "the surface takes it")
	_check(not surface._can_drop_data(Vector2(300, 300), {"other": 1}), "and nothing else")
	surface._notification(Control.NOTIFICATION_DRAG_END)
	_check(not row.confirm_button.visible, "no confirm yet")
	row.delete_button.pressed.emit()
	_check(row.confirm_button.visible and not row.delete_button.visible and Collections.list().size() == 1, "Delete asks")
	row.cancel_button.pressed.emit()
	_check(row.delete_button.visible and not row.confirm_button.visible and Collections.list().size() == 1, "Keep keeps it")
	row.delete_button.pressed.emit()
	row.confirm_button.pressed.emit()
	_check(Collections.list().is_empty() and tool.picked == "", "Confirm deletes it, and unpicks it")
	box.queue_free()
	# Names.
	_check(Collections.cleaned('a:b*c?d"e<f>g|h\\i') == "abcdefgh/i", "typing keeps to file name characters")
	_check(Collections.normalised("  a//b / c ") == "a/b/c", "extra slashes and spaces go")
	_check(Collections.problem("") != "" and Collections.problem("a/") != "", "a name needs a last part")
	_check(Collections.problem("a./b") != "" and Collections.problem("..") != "" and Collections.problem("a/..") != "", "no dots at the end, or climbing out")
	_check(Collections.problem("con") != "" and Collections.problem("a/NUL.x") != "" and Collections.problem("com1/a") != "", "no reserved names")
	_check(Collections.problem("console") == "" and Collections.problem("a.b/c-d_e f") == "", "ordinary names pass")
	_check(Collections.problem("a".repeat(101)) != "", "not too long")
	_check(tool.save_selection("../out") != "" and Collections.list().is_empty(), "nothing saves outside the folder")
	# Folders.
	var sel_note := surface.add_object(Vector2(50, 50), 60, 0)
	surface.selection.notes = {sel_note: true}
	tool.save_selection("a/b/one")
	tool.save_selection("a/two")
	tool.save_selection("three")
	_check(Array(Collections.list()) == ["a/b/one", "a/two", "three"], "folders nest")
	tool._open.clear()
	var tree := VBoxContainer.new()
	add_child(tree)
	tool.build_options(tree)
	_check(tree.find_children("*", "CollectionFolder", true, false).size() == 1, "one folder at the top")
	_check(tree.find_children("*", "CollectionRow", true, false).size() == 1, "closed, with the loose collection")
	tool.toggle_folder("a")
	tool.toggle_folder("a/b")
	var rows := tree.find_children("*", "CollectionRow", true, false)
	_check(rows.size() == 3 and tree.find_children("*", "CollectionFolder", true, false).size() == 2, "opening folders shows them")
	_check(rows[0].handle.text == "one" and rows[0].collection == "a/b/one", "rows show the last part")
	tool.toggle_folder("a")
	_check(tree.find_children("*", "CollectionRow", true, false).size() == 1, "closing hides them")
	tree.queue_free()
	tool.delete("a/b/one")
	_check(not DirAccess.dir_exists_absolute(Collections.DIR + "a/b"), "deleting the last one removes its folder")
	_check(DirAccess.dir_exists_absolute(Collections.DIR + "a"), "but not one still in use")
	tool.delete("a/two")
	_check(not DirAccess.dir_exists_absolute(Collections.DIR + "a"), "and folders above it empty out")
	tool.delete("three")
	_check(DirAccess.dir_exists_absolute(Collections.DIR), "the collections folder stays")
	# The folder button.
	DirAccess.remove_absolute(Collections.DIR)
	var folder_path := Collections.folder()
	_check(DirAccess.dir_exists_absolute(folder_path) and folder_path.is_absolute_path(), "the folder is made, with a real path")
	var opener := VBoxContainer.new()
	add_child(opener)
	tool.build_options(opener)
	_check(opener.find_children("*", "Button", true, false).any(func(b: Button) -> bool:
		return b.text == "Open Collections Folder" and b.tooltip_text != ""), "the panel has the button")
	opener.queue_free()
	# A bad file.
	DirAccess.make_dir_recursive_absolute(Collections.DIR)
	var bad := FileAccess.open(Collections.DIR + "Bad.json", FileAccess.WRITE)
	bad.store_string("{not json")
	bad.close()
	_check(Collections.read("Bad").is_empty(), "a broken file reads as empty")
	_check(tool.drop("Bad", Vector2(100, 100)) == 0, "and places nothing")
	Collections.remove("Bad")
	tools.set_tool("select")
	surface.selection.clear()
	surface.clear_notes()


func _sequence() -> void:
	var a := surface.add_object(Vector2.ZERO, 60, 0)
	surface.add_modifier(a, "sequence")
	var o := surface.get_note(a)
	var s: SequenceModifier = o.get_modifier("sequence")
	_check(s.steps == [true, false] and s.pos == 0 and not s.resting(), "a new sequence is On, Off")
	surface.set_sequence_count(a, 4)
	surface.set_sequence_step(a, 1, true)
	surface.set_sequence_step(a, 2, false)
	var fired: Array = []
	for i in 6:
		fired.append(s.passes_hit())
	_check(fired == [true, true, false, true, true, true], "steps play in order, and repeat")
	_check(s.pos == 2 and s.resting() and s.dims_label(), "the next step is shown")
	_check("step 3 of 4" in o.hover_text(), "and described")
	surface.set_sequence_count(a, 2)
	_check(s.pos == 0 and s.steps == [true, true], "fewer steps keeps the position in range")
	surface.set_sequence_count(a, 0)
	_check(s.steps.size() == 1, "at least one step")
	surface.set_sequence_count(a, 99)
	_check(s.steps.size() == SequenceModifier.MAX_STEPS and s.steps[15], "and at most 16, new ones On")
	surface.set_sequence_step(a, 99, false)
	_check(s.steps.count(true) == 16, "steps out of range are ignored")
	surface.set_sequence_count(a, 3)
	s.passes_hit()
	surface.stop()
	_check(s.pos == 0, "Stop returns to step 1")
	# Silences a relay too, and every hit moves on.
	surface.add_modifier(a, "relay")
	surface.set_sequence_step(a, 0, false)
	surface.trigger_note(a)
	_check(surface.waves.is_empty() and s.pos == 1, "an Off step silences the relay")
	surface.trigger_note(a)
	_check(surface.waves.size() == 1, "an On step fires it")
	surface.stop()
	surface.remove_modifier(a, "relay")
	# Saves.
	var copy := SequenceModifier.new()
	copy.load_dict(s.to_dict(), Vector2.ZERO)
	_check(copy.steps == s.steps and copy.pos == 0, "sequences save")
	var from_json := SequenceModifier.new()
	from_json.load_dict(JSON.parse_string(JSON.stringify(s.to_dict())), Vector2.ZERO)
	_check(from_json.steps == s.steps, "through JSON too")
	# Old saves, keeping their timing.
	var old := Modifier.create("toggle")
	old.load_dict({"kind": "toggle", "start": false}, Vector2.ZERO)
	_check(old is SequenceModifier and old.steps == [false, true], "a toggle starting off")
	old.load_dict({"kind": "toggle", "start": true}, Vector2.ZERO)
	_check(old.steps == [true, false], "a toggle starting on")
	old = Modifier.create("rest")
	old.load_dict({"kind": "rest", "value": 3, "start": 2}, Vector2.ZERO)
	_check(old.steps == [false, false, true, false], "a Rest 3 with 2 left")
	old.load_dict({"kind": "rest", "value": 8, "start": 0}, Vector2.ZERO)
	_check(old.steps.size() == 9 and old.steps.count(true) == 1 and old.steps[0], "a Rest 8")
	surface.clear_notes()


func _note_lengths() -> void:
	_check(Settings.note_beats == 0.5, "the default is an eighth note")
	var bpm: float = Settings.bpm
	_check(is_equal_approx(Settings.note_length_for(0), 0.5 * 60.0 / bpm), "lengths are in beats")
	Settings.bpm = 60.0
	_check(is_equal_approx(Settings.note_length_for(0), 0.5), "and follow the tempo")
	Settings.set_channel_beats(3, 2.5)
	_check(is_equal_approx(Settings.note_length_for(3), 2.5) and is_equal_approx(Settings.note_length_for(4), 0.5), "a channel can differ")
	Settings.set_channel_beats(3, 0.0)
	Settings.bpm = bpm
	for pair in [[0.1, 0.5], [0.74, 0.5], [0.76, 1.0], [1.3, 1.5], [9.0, 4.0]]:
		_check(Settings.snap_length(pair[0]) == pair[1], "%s snaps to %s" % pair)
	for pair in [[0.5, "½ beat"], [1.0, "1 beat"], [1.5, "1½ beats"], [4.0, "4 beats"]]:
		_check(PanelBuilder.beats_text(pair[0]) == pair[1], "reads %s" % pair[1])
	var box := VBoxContainer.new()
	add_child(box)
	tools.get_tool("channel").build_options(box)
	var sliders := box.find_children("*", "HSlider", true, false)
	_check(sliders.size() == 1, "one Default slider")
	_check(sliders[0].step == 0.5 and sliders[0].min_value == 0.5 and sliders[0].max_value == 4.0, "Default runs ½ to 4 in ½ steps")
	var knobs := _knobs(box)
	_check(knobs.size() == 32, "two knobs per channel")
	_check(knobs[1].step == 0.5 and knobs[1].min_value == 0.0 and knobs[1].max_value == 4.0, "a length knob has Default at the bottom")
	for k in knobs:
		_check(k.tooltip_text != "", "knob has a tooltip")
	box.queue_free()
	# Old saves.
	var cfg := ConfigFile.new()
	var old: Array = []
	old.resize(16)
	old.fill(0.0)
	old[1] = 1.3
	cfg.set_value("app", "note_length", 0.35)
	cfg.set_value("app", "channel_lengths", old)
	var was: float = Settings.note_beats
	var was_channels: Array = Settings.channel_beats.duplicate()
	Settings._migrate_note_lengths(cfg)
	_check(Settings.note_beats == 0.5 and Settings.channel_beats[1] == 2.5 and Settings.channel_beats[0] == 0.0, "old seconds convert and snap")
	Settings.note_beats = was
	Settings.channel_beats = was_channels


func _run_frames(seconds: float, fps: float, jitter: float, rng: RandomNumberGenerator) -> void:
	var t := 0.0
	while t < seconds:
		var d: float = (1.0 / fps) * (1.0 + rng.randf_range(-jitter, jitter))
		surface.step(d)
		t += d


func _timing() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var bpm: float = Settings.bpm
	Settings.bpm = 120.0
	surface.waves.clear()
	var fired: Array = []
	var spy := func(m: PackedByteArray) -> void:
		if (m[0] & 0xF0) == 0x90:
			fired.append([surface.clock_usec, m[1]])
	Midi.message_sent.connect(spy)
	# A 2-beat loop keeps its tempo, whatever the frame rate.
	for setup in [[60.0, 0.0], [60.0, 0.25], [144.0, 0.0], [144.0, 0.25]]:
		surface.clear_notes()
		fired.clear()
		var a := surface.add_object(Vector2(0, 0), 60, 0)
		var b := surface.add_object(Vector2(200, 0), 62, 0)
		for id in [a, b]:
			surface.add_modifier(id, "relay")
			surface.get_note(id).emitter().cooldown = 0.5
			surface.get_note(id).emitter().own_reach = 400.0
		surface.trigger_note(a)
		_run_frames(60.0, setup[0], setup[1], rng)
		var times: Array = fired.filter(func(f: Array) -> bool: return f[1] == 60).map(func(f: Array) -> int: return f[0])
		var period: float = float(times[-1] - times[0]) / (times.size() - 1) / 1000.0
		_check(absf(period - 1000.0) < 1.0, "%d fps, jitter %.2f: loop period %.2f ms" % [setup[0], setup[1], period])
		surface.stop()
	# A chain's eighth link is at most about a frame late.
	for fps in [60.0, 144.0]:
		surface.clear_notes()
		fired.clear()
		var first := -1
		for i in 8:
			var id := surface.add_object(Vector2(200.0 * i, 0), 40 + i, 0)
			surface.add_modifier(id, "relay")
			surface.get_note(id).emitter().own_reach = 250.0
			surface.get_note(id).emitter().cooldown = 4.0
			if i == 0:
				first = id
		var start: int = surface.clock_usec
		surface.trigger_note(first)
		_run_frames(3.8, fps, 0.1, rng)
		var last: Array = fired.filter(func(f: Array) -> bool: return f[1] == 47)
		var late: float = (last[0][0] - start) / 1000.0 - 3500.0
		_check(late >= -1.0 and late < 1000.0 / fps + 3.0, "%d fps: eighth link %.1f ms late" % [fps, late])
		surface.stop()
	# A cooldown equal to the time between hits skips nothing.
	for fps in [60.0, 144.0]:
		surface.clear_notes()
		var r := surface.add_object(Vector2(100, 0), 60, 0)
		surface.add_modifier(r, "relay")
		var e: Emitter = surface.get_note(r).emitter()
		e.own_reach = 10.0
		var count := 0
		var ready: int = e.ready_at
		var t := 0.0
		var next := 0.0
		while t < 30.0:
			if t >= next:
				surface.add_wave(Wave.new(Vector2.ZERO, 1.0, -1, 300.0))
				next += 0.5
			var d: float = (1.0 / fps) * (1.0 + rng.randf_range(-0.1, 0.1))
			surface.step(d)
			t += d
			if e.ready_at != ready:
				count += 1
				ready = e.ready_at
		_check(count >= 59, "%d fps: fired %d of 60 hits" % [fps, count])
		surface.stop()
	# A cooldown still holds off hits that are clearly too soon.
	surface.clear_notes()
	var c := surface.add_object(Vector2(0, 0), 60, 0)
	surface.add_modifier(c, "relay")
	var ce: Emitter = surface.get_note(c).emitter()
	surface.trigger_note(c)
	surface.waves.clear()
	surface.step(0.2)
	surface.trigger_note(c)
	_check(surface.waves.is_empty(), "a cooldown still gates")
	surface.step(0.3 - 0.01)
	surface.trigger_note(c)
	_check(surface.waves.size() == 1, "and a hit 10 ms early fires")
	_check(ce.cooldown == 1.0, "defaults untouched")
	Midi.message_sent.disconnect(spy)
	Settings.bpm = bpm
	surface.stop()
	surface.clear_notes()


func _slow_frame() -> void:
	var heard: Array = []
	var spy := func(m: PackedByteArray) -> void:
		if (m[0] & 0xF0) == 0x90:
			heard.append([surface.clock_usec, m[1], m[2]])
	var melody := func() -> Array: return heard.map(func(h: Array) -> int: return h[1])
	# A wave ending in one slow frame still hits what it reached, and nothing past its end.
	var inner := surface.add_object(Vector2(100, 0), 60, 0)
	var outer := surface.add_object(Vector2(400, 0), 62, 0)
	Midi.message_sent.connect(spy)
	heard.clear()
	surface.add_wave(Wave.new(Vector2.ZERO, 1.0, -1, 300.0))
	surface.step(1.0)
	_check(melody.call() == [60] and surface.waves.is_empty(), "a slow frame hits within reach only (%s, %d)" % [str(melody.call()), outer - inner])
	Midi.message_sent.disconnect(spy)
	surface.stop()
	surface.clear_notes()


func _wave_end() -> void:
	var heard: Array = []
	var spy := func(m: PackedByteArray) -> void:
		if (m[0] & 0xF0) == 0x90:
			heard.append([m[1], m[2]])
	Midi.message_sent.connect(spy)
	var four := 4.0 * Settings.BEAT_UNIT
	for fps in [60.0, 144.0, 12.0]:
		for b in [3.5, 3.9, 3.99, 4.0]:
			surface.clear_notes()
			heard.clear()
			surface.add_object(Vector2(b * Settings.BEAT_UNIT, 0), 60, 0)
			surface.add_wave(Wave.new(Vector2.ZERO, 1.0, -1, four))
			_run_frames(3.0, fps, 0.0, RandomNumberGenerator.new())
			_check(heard.size() == 1 and heard[0][1] >= 1, "%d fps: a 4-beat wave hits a note at %s beats" % [fps, b])
			surface.stop()
		surface.clear_notes()
		heard.clear()
		surface.add_object(Vector2(4.05 * Settings.BEAT_UNIT, 0), 60, 0)
		surface.add_wave(Wave.new(Vector2.ZERO, 1.0, -1, four))
		_run_frames(3.0, fps, 0.0, RandomNumberGenerator.new())
		_check(heard.is_empty(), "%d fps: but not past its reach" % fps)
		surface.stop()
	# A relay at the very end of a wave fires too.
	surface.clear_notes()
	var r := surface.add_object(Vector2(four, 0), 60, 0)
	surface.add_modifier(r, "relay")
	surface.get_note(r).emitter().own_reach = 50.0
	surface.add_wave(Wave.new(Vector2.ZERO, 1.0, -1, four))
	var fired := false
	var t := 0.0
	while t < 2.5:
		surface.step(1.0 / 60.0)
		t += 1.0 / 60.0
		fired = fired or surface.get_note(r).emitter().ready_at > 0
	_check(fired, "a relay at the reach fires")
	Midi.message_sent.disconnect(spy)
	surface.stop()
	surface.clear_notes()


func _tweaks() -> void:
	var a := surface.add_note_at(Vector2(300, 300), 60, 0)
	var b := surface.add_note_at(Vector2(500, 300), 63, 0)
	var ao := surface.get_note(a)
	for id in ["tap", "select", "draw", "bind", "grid", "pan"]:
		tools.set_tool(id)
		surface.selection.clear()
		surface.set_pointer(Vector2(300, 300))
		ao.muted = false
		_key(KEY_M)
		_check(ao.muted, "M mutes in %s" % id)
		ao.muted = false
		var was: int = ao.note
		var e := InputEventKey.new()
		e.keycode = KEY_PERIOD
		e.pressed = true
		tools.handle_input(e)
		_check(ao.note > was, "> nudges in %s" % id)
		e.keycode = KEY_COMMA
		tools.handle_input(e)
		_check(ao.note == was, "< nudges back in %s" % id)
		e.shift_pressed = true
		e.keycode = KEY_PERIOD
		tools.handle_input(e)
		_check(ao.note == was + 12, "Shift: an octave in %s" % id)
		e.keycode = KEY_COMMA
		tools.handle_input(e)
	surface.set_pointer(Vector2(1000, 700))
	tools.set_tool("select")
	surface.clear_notes()


func _group_rings() -> void:
	tools.set_tool("select")
	var scale_before: String = Settings.scale_name
	Settings.set_value("scale_name", "Major")
	var c4 := surface.add_note_at(Vector2(200, 300), 60, 0)      # C4
	var e4 := surface.add_note_at(Vector2(350, 300), 64, 0)      # E4
	var g4 := surface.add_note_at(Vector2(500, 300), 67, 0)      # G4
	var lone := surface.add_note_at(Vector2(700, 300), 72, 0)
	surface.history.end_group()
	var sel := surface.selection
	sel.notes = {c4: true, e4: true, g4: true}
	var open_on := func(id: int) -> void:
		_press(MOUSE_BUTTON_RIGHT, true, surface.to_screen(surface.get_note(id).pos))
		_press(MOUSE_BUTTON_RIGHT, false, surface.to_screen(surface.get_note(id).pos))
	tools.pick("pitch")
	# A pick moves the chord by scale steps: C-E-G up two steps is E-G-B.
	var steps := surface.history.undo_steps()
	open_on.call(c4)
	radial.outer_chosen.emit(64)
	_check(surface.get_note(c4).note == 64 and surface.get_note(e4).note == 67 and surface.get_note(g4).note == 71, "the chord moves by scale steps")
	_check(surface.get_note(lone).note == 72, "unselected notes stay")
	_check(surface.history.undo_steps() == steps + 1, "as one undo step")
	surface.history.end_group()
	radial.outer_chosen.emit(60)
	_check(surface.get_note(e4).note == 64 and surface.get_note(g4).note == 67, "and back down")
	surface.history.end_group()
	radial.close()
	# Opened on another note, that note takes the pick.
	open_on.call(g4)
	radial.outer_chosen.emit(69)
	_check(surface.get_note(g4).note == 69 and surface.get_note(c4).note == 62, "any selected note can lead")
	surface.history.end_group()
	radial.outer_chosen.emit(67)
	surface.history.end_group()
	radial.close()
	# Off-scale notes land on the scale; out of range stays put.
	surface.get_note(e4).note = 63
	surface.get_note(g4).note = 126
	open_on.call(c4)
	radial.outer_chosen.emit(62)
	_check(surface.get_note(e4).note == 64, "an off-scale note steps onto the scale")
	surface.history.end_group()
	radial.close()
	# Octave.
	surface.get_note(c4).note = 60
	surface.get_note(e4).note = 64
	surface.get_note(g4).note = 67
	surface.save_notes()
	surface.history.end_group()
	var ring: PitchTool = tools.get_tool("pitch")
	open_on.call(c4)
	radial.inner_chosen.emit(ring._octave + 1)
	_check(surface.get_note(c4).note == 72 and surface.get_note(e4).note == 76 and surface.get_note(g4).note == 79, "octave moves them all")
	surface.history.end_group()
	surface.get_note(g4).note = 120
	radial.inner_chosen.emit(ring._octave + 1)
	_check(surface.get_note(g4).note == 120 and surface.get_note(c4).note == 84, "one past the top stays put")
	surface.history.end_group()
	radial.close()
	# Channel, modifier, settings.
	tools.pick("channel")
	open_on.call(c4)
	radial.outer_chosen.emit(4)
	radial.close()
	_check(surface.get_note(g4).channel == 4 and surface.get_note(lone).channel == 0, "channel spreads")
	tools.pick("modifier")
	open_on.call(c4)
	radial.outer_chosen.emit("relay")
	radial.outer_chosen.emit("sequence")
	radial.close()
	_check(surface.get_note(g4).relay() != null and surface.get_note(e4).get_modifier("sequence") != null, "modifiers spread")
	var o := surface.get_note(c4)
	_press(MOUSE_BUTTON_RIGHT, true, o.emitter().dock_screen_pos(surface, o))
	radial.outer_chosen.emit(2.0)
	radial.center_chosen.emit("sound")
	radial.close()
	_check(surface.get_note(g4).emitter().cooldown == 2.0 and not surface.get_note(e4).relay().sound, "relay settings spread")
	_press(MOUSE_BUTTON_RIGHT, true, o.get_modifier("sequence")._tab_centre(surface, o))
	radial.inner_chosen.emit(4)
	radial.outer_chosen.emit(1)
	radial.close()
	var spread: SequenceModifier = surface.get_note(g4).get_modifier("sequence")
	_check(spread.steps == [true, true, true, true], "sequence settings spread")
	# Selected diamonds count for relay settings.
	sel.clear()
	sel.emitters = {c4: true, g4: true}
	_press(MOUSE_BUTTON_RIGHT, true, o.emitter().dock_screen_pos(surface, o))
	radial.outer_chosen.emit(3.0)
	radial.close()
	_check(surface.get_note(g4).emitter().cooldown == 3.0 and surface.get_note(e4).emitter().cooldown == 2.0, "selected diamonds spread")
	sel.clear()
	# Delete.
	sel.notes = {c4: true, e4: true, g4: true}
	tools.pick("pitch")
	open_on.call(c4)
	radial.center_chosen.emit("delete")
	_check(surface.notes.size() == 1 and not radial.visible and surface.get_note(lone) != null, "the centre deletes the selection")
	surface.history.end_group()
	surface.undo()
	_check(surface.notes.size() == 4, "undo brings them back")
	sel.clear()
	open_on.call(lone)
	radial.center_chosen.emit("delete")
	_check(surface.notes.size() == 3, "a lone note deletes alone")
	Settings.set_value("scale_name", scale_before)
	surface.clear_notes()


func _saves() -> void:
	Settings.notes = [
		{"x": 10.0, "y": 0.0, "note": 60, "channel": 0, "mode": 2, "pulse_strength": 0.5, "cooldown_beats": 2.0, "attached": false, "ex": 30.0, "ey": 40.0, "mod": "sequence", "mod_start": false, "id": 3, "range": 200.0, "grid_emit": true, "snap_emit": "n1"},
		{"x": 20.0, "y": 0.0, "note": 62, "channel": 1, "mode": 1, "id": 4},
		{"x": 30.0, "y": 0.0, "note": 64, "channel": 2, "mode": 0, "attached": false, "ex": 9.0, "ey": 9.0, "id": 5},
	]
	surface.load_notes()
	var r := surface.get_note(3)
	_check(r.relay() and not r.relay().sound and r.get_modifier("sequence") and r.get_modifier("sequence").steps == [false, true], "an old toggle becomes a sequence")
	var e := r.emitter()
	_check(e.strength == 0.5 and e.cooldown == 2.0 and not e.attached and e.pos == Vector2(30, 40) and e.own_reach == 200.0 and e.grid and e.snap == "n1", "keeps its emitter")
	_check(surface.get_note(4).relay() and surface.get_note(4).relay().sound and surface.notes.size() == 3, "an old hybrid is one sounding relay")
	_check(surface.get_note(5).modifiers.is_empty(), "an old plain note has no relay")
	surface.save_notes()
	var saved := JSON.stringify(Settings.notes)
	surface.load_notes()
	surface.save_notes()
	_check(JSON.stringify(Settings.notes) == saved, "the new format round-trips")
	_check(not saved.contains("\"mode\""), "and has no type field")
	surface.clear_notes()


func _default_ring() -> void:
	var n := surface.add_note_at(Vector2(200, 200), 60, 0)
	tools.open_default_ring(n, Vector2(200, 200))
	_check(tools.open_ring.tool_id() == "pitch", "a note's default is pitch")
	tools.open_default_ring(-1, Vector2(600, 200))
	_check(tools.open_ring.tool_id() == "pitch", "empty space is pitch")
	radial.hover_at(Vector2(600, 100))
	radial.close()
	surface.clear_notes()
