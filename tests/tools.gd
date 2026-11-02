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
	_navigation()
	_tap()
	_select()
	_draw_strokes()
	_pitch()
	_channel()
	_pulse()
	_modifier()
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
	_check(tools.get_tool("draw").place_type == SurfaceObject.Mode.RELAY, "picking Draw again switches type")
	tools.pick("draw")
	_check(seen.size() >= 4, "tool changes reported")
	for t in tools.tools:
		if not t.navigates() and t.tool_id() != "tap":
			_check(t.handle_input(InputEventMouseButton.new()) == false, "%s takes no input yet" % t.tool_id())
	tools.set_tool("select")


func _press(button: MouseButton, down: bool, at: Vector2, shift: bool = false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = down
	e.position = at
	e.shift_pressed = shift
	tools.handle_input(e)


func _move(at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	tools.handle_input(e)


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
	surface.set_note_mode(relay, SurfaceObject.Mode.RELAY)
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
	sent.clear()
	surface.set_modifier(note, "toggle")
	_press(MOUSE_BUTTON_LEFT, true, Vector2(300, 300))
	_check(sent.size() == 1 and surface.get_note(note).modifier.on, "a toggle isn't advanced")
	surface.step(1.0)
	sent.clear()
	surface.get_note(note).muted = true
	_press(MOUSE_BUTTON_LEFT, true, Vector2(300, 300))
	_check(sent.is_empty() and surface.waves.is_empty(), "muted stays silent")
	_press(MOUSE_BUTTON_LEFT, true, Vector2(500, 300))
	_check(surface.waves.size() == 1 and surface.waves[0].source == relay and sent.is_empty(), "a relay fires its pulse")
	_press(MOUSE_BUTTON_RIGHT, true, Vector2(800, 600))
	_check(surface.waves.size() == 1, "other buttons do nothing")
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
	draw.place_type = SurfaceObject.Mode.RELAY
	var before := surface.history.undo_steps()
	draw.extend_stroke(Vector2(100, 100))
	_check(surface.notes.is_empty(), "no stroke, no object")
	draw.begin_stroke(Vector2(100, 100))
	draw.extend_stroke(Vector2(120, 100))
	_check(surface.notes.size() == 1, "at most one per division")
	draw.extend_stroke(Vector2(400, 100))
	draw.extend_stroke(Vector2(700, 100))
	draw.end_stroke()
	_check(surface.notes.size() == 3 and surface.notes[0] is Relay, "places the current type")
	_check(surface.history.undo_steps() == before + 1, "one undo step")
	draw.place_type = SurfaceObject.Mode.NOTE
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


func _pulse() -> void:
	var a := surface.add_note_at(Vector2(200, 200), 60, 0)
	tools.open_ring_for("pulse", a, Vector2(200, 200))
	_check(radial.center_item.label == "Note", "shows the type")
	radial.outer_chosen.emit(2.0)
	var o := surface.get_note(a)
	_check(o is Relay and o.emitter.cooldown == 2.0, "tuning a pulse makes a relay")
	_check(radial.center_item.label == "Relay", "the ring rebuilt")
	radial.inner_chosen.emit(0.5)
	_check(surface.get_note(a).emitter.strength == 0.5, "strength")
	radial.center_chosen.emit("mode")
	o = surface.get_note(a)
	_check(o is Note and o.emitter.cooldown == 2.0, "switching back keeps the settings")
	radial.close()
	surface.clear_notes()


func _modifier() -> void:
	var a := surface.add_note_at(Vector2(200, 200), 60, 0)
	tools.open_ring_for("modifier", a, Vector2(200, 200))
	_check(radial.inner_items.is_empty(), "no state ring yet")
	radial.outer_chosen.emit("toggle")
	_check(surface.get_note(a).modifier is ToggleModifier and radial.inner_items.size() == 2, "adds a toggle")
	radial.inner_chosen.emit(false)
	var m: Modifier = surface.get_note(a).modifier
	_check(not m.on and not m.start, "state sets current and start")
	radial.outer_chosen.emit("")
	_check(surface.get_note(a).modifier == null, "removes it")
	radial.close()
	surface.clear_notes()


func _default_ring() -> void:
	var n := surface.add_note_at(Vector2(200, 200), 60, 0)
	var r := surface.add_note_at(Vector2(400, 200), 62, 0)
	surface.set_note_mode(r, SurfaceObject.Mode.RELAY)
	tools.open_default_ring(n, Vector2(200, 200))
	_check(tools.open_ring.tool_id() == "pitch", "a note's default is pitch")
	tools.open_default_ring(r, Vector2(400, 200))
	_check(tools.open_ring.tool_id() == "pulse", "a relay's default is pulse")
	tools.open_default_ring(-1, Vector2(600, 200))
	_check(tools.open_ring.tool_id() == "pitch", "empty space is pitch")
	radial.hover_at(Vector2(600, 100))
	radial.close()
	surface.clear_notes()
