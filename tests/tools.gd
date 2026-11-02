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
	_draw_strokes()
	_pitch()
	_channel()
	_modifiers()
	_tabs()
	_quick_pick()
	_ring_options()
	_tab()
	_bindings()
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
	_check(tools.tools.size() == 9, "nine tools")
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
	surface.set_pointer(surface.to_screen(ao.pos))
	surface.snapping.toggle_at_hover()
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
	tools.set_tool("draw")
	_press(MOUSE_BUTTON_MIDDLE, true, Vector2(100, 100))
	_check(tools.current_id() == "pan" and tools.springing(), "middle spring-loads pan")
	_move(Vector2(160, 130))
	_check(surface.to_screen(saved_view) == Vector2(60, 30), "pan follows the pointer")
	_press(MOUSE_BUTTON_MIDDLE, false, Vector2(160, 130))
	_check(tools.current_id() == "draw" and not tools.springing(), "release returns to the tool")
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
	_check(tools.current_id() == "draw", "zoom returns too")
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
	surface.add_modifier(note, "toggle")
	_press(MOUSE_BUTTON_LEFT, true, Vector2(300, 300))
	_check(sent.size() == 1 and not surface.get_note(note).get_modifier("toggle").on, "a toggle on plays and flips")
	surface.step(1.0)
	sent.clear()
	_press(MOUSE_BUTTON_LEFT, true, Vector2(300, 300))
	_check(sent.is_empty() and surface.get_note(note).get_modifier("toggle").on, "a toggle off is silent and flips")
	surface.remove_modifier(note, "toggle")
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
	_check(surface.waves.is_empty(), "cooldown applies")
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


func _draw_strokes() -> void:
	var draw: DrawTool = tools.get_tool("draw")
	surface.history.end_group()
	var before := surface.history.undo_steps()
	draw.extend_stroke(Vector2(100, 100))
	_check(surface.notes.is_empty(), "no stroke, no object")
	draw.begin_stroke(Vector2(100, 100))
	draw.extend_stroke(Vector2(120, 100))
	_check(surface.notes.size() == 1, "at most one per division")
	draw.extend_stroke(Vector2(400, 100))
	draw.extend_stroke(Vector2(700, 100))
	draw.end_stroke()
	_check(surface.notes.size() == 3 and surface.notes[0].modifiers.is_empty(), "places plain notes")
	_check(surface.history.undo_steps() == before + 1, "one undo step")
	surface.clear_notes()


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
	ring.step_octave(1)
	_check(surface.notes[0].note == was + 12, "octave keeps the letter")
	radial.inner_chosen.emit(2)
	_check(ring._octave == 2, "inner ring sets octave")
	ring.type_digit(1)
	ring.type_digit(2)
	_check(ring._channel == 11, "1 then 2 is channel 12")
	ring.type_digit(5)
	_check(ring._channel == 4, "a single digit")
	radial.outer_chosen.emit(radial.outer_items[0].id)
	_check(surface.notes[0].channel == 4, "pick applies the channel")
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
	radial.outer_chosen.emit("toggle")
	radial.outer_chosen.emit("relay")
	var o := surface.get_note(a)
	_check(o.modifiers.size() == 2 and o.modifiers[0] is ToggleModifier and o.modifiers[1] is RelayModifier, "holds both")
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
	radial.outer_chosen.emit("toggle")
	_check(surface.get_note(a).modifiers.size() == 1, "removes just that one")
	radial.outer_chosen.emit("")
	_check(surface.get_note(a).modifiers.is_empty(), "None clears them")
	radial.close()
	surface.clear_notes()


func _tabs() -> void:
	var a := surface.add_note_at(Vector2(400, 300), 60, 0)
	var b := surface.add_note_at(Vector2(700, 300), 62, 0)
	surface.add_modifier(a, "relay")
	surface.add_modifier(a, "toggle")
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
	var tab: Vector2 = o.get_modifier("toggle")._tab_centre(surface, o)
	_press(MOUSE_BUTTON_RIGHT, true, tab)
	_check(radial.visible and tools.open_ring.tool_id() == "toggle_settings", "right-click the toggle tab")
	radial.outer_chosen.emit(false)
	var t: Modifier = o.get_modifier("toggle")
	_check(not t.on and not t.start, "state sets current and start")
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
	surface.add_modifier(a, "toggle")
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
	var tab: Vector2 = o.get_modifier("toggle")._tab_centre(surface, o)
	_press(MOUSE_BUTTON_RIGHT, true, tab)
	c = radial._center
	item = c + Vector2(0, 100)                       # Off, the lower half
	_radial_move(item)
	_radial_press(MOUSE_BUTTON_RIGHT, false, item)
	_check(not o.get_modifier("toggle").on and not radial.visible, "works on the toggle ring")
	surface.clear_notes()


func _ring_options() -> void:
	var a := surface.add_note_at(Vector2(640, 400), 60, 0)
	var b := surface.add_note_at(Vector2(900, 400), 62, 0)
	tools.set_tool("draw")
	_check(tools.ring_option.tool_id() == "pitch", "pitch by default")
	tools.pick("modifier")
	_check(tools.current_id() == "draw" and tools.ring_option.tool_id() == "modifier", "an option doesn't change the tool")
	tools.set_tool("channel")
	_check(tools.current_id() == "draw", "and can't be made the tool")
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
	_check(surface.get_note(a).get_modifier("toggle") != null and not radial.visible, "quick pick adds a modifier")
	surface.selection.notes = {a: true, b: true}
	_press(MOUSE_BUTTON_RIGHT, true, Vector2(640, 400))
	_radial_move(toggle_at)
	_radial_press(MOUSE_BUTTON_RIGHT, false, toggle_at)
	_check(surface.get_note(a).modifiers.is_empty(), "picking it again removes it")
	_press(MOUSE_BUTTON_RIGHT, true, Vector2(640, 400))
	_radial_move(toggle_at)
	_radial_press(MOUSE_BUTTON_RIGHT, false, toggle_at)
	_check(surface.get_note(b).get_modifier("toggle") != null, "the group follows")
	surface.selection.clear()
	# A tab still wins, and Tap keeps rings off.
	var o := surface.get_note(a)
	_press(MOUSE_BUTTON_RIGHT, true, o.get_modifier("toggle")._tab_centre(surface, o))
	_check(tools.open_ring.tool_id() == "toggle_settings", "a tab opens its settings")
	radial.close()
	tools.set_tool("tap")
	_press(MOUSE_BUTTON_RIGHT, true, Vector2(640, 400))
	_check(not radial.visible, "Tap opens no rings")
	tools.pick("pitch")
	tools.set_tool("select")
	surface.clear_notes()


func _tab() -> void:
	var cases := ["select", "draw", "pan", "zoom"]
	for id in cases:
		tools.set_tool(id)
		_key(KEY_TAB)
		_check(tools.current_id() == "tap" and not tools.is_editing(), "Tab from %s goes to Tap" % id)
		_key(KEY_TAB)
		_check(tools.current_id() == id and tools.is_editing(), "Tab returns to %s" % id)
	tools.set_tool("draw")
	tools.pick("tap")
	_key(KEY_TAB)
	_check(tools.current_id() == "draw", "Tap picked on the bar returns too")
	# A ring option isn't a tool, so it's left alone.
	tools.pick("channel")
	_key(KEY_TAB)
	_key(KEY_TAB)
	_check(tools.current_id() == "draw" and tools.ring_option.tool_id() == "channel", "the ring option stays")
	tools.pick("pitch")
	# Nothing happens during a spring-load.
	_press(MOUSE_BUTTON_MIDDLE, true, Vector2.ZERO)
	_key(KEY_TAB)
	_check(tools.current_id() == "pan", "ignored while spring-loaded")
	_press(MOUSE_BUTTON_MIDDLE, false, Vector2.ZERO)
	_check(tools.current_id() == "draw", "spring-load still returns")
	var ctrl := InputEventKey.new()
	ctrl.keycode = KEY_TAB
	ctrl.pressed = true
	ctrl.ctrl_pressed = true
	tools.handle_input(ctrl)
	_check(tools.current_id() == "draw", "Ctrl+Tab does nothing")
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


func _saves() -> void:
	Settings.notes = [
		{"x": 10.0, "y": 0.0, "note": 60, "channel": 0, "mode": 2, "pulse_strength": 0.5, "cooldown_beats": 2.0, "attached": false, "ex": 30.0, "ey": 40.0, "mod": "toggle", "mod_start": false, "id": 3, "range": 200.0, "grid_emit": true, "snap_emit": "n1"},
		{"x": 20.0, "y": 0.0, "note": 62, "channel": 1, "mode": 1, "id": 4},
		{"x": 30.0, "y": 0.0, "note": 64, "channel": 2, "mode": 0, "attached": false, "ex": 9.0, "ey": 9.0, "id": 5},
	]
	surface.load_notes()
	var r := surface.get_note(3)
	_check(r.relay() and not r.relay().sound and r.get_modifier("toggle") and not r.get_modifier("toggle").start, "old relay with a toggle")
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
