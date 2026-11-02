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
	_wave()
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
	_check(tools.tools.size() == 7, "seven tools")
	_check(tools.current_id() == "select", "starts on select")
	tools.set_tool("nothing")
	_check(tools.current_id() == "select", "unknown tool ignored")
	tools.set_tool("draw")
	tools.toggle_wave()
	_check(tools.current_id() == "wave" and not tools.is_editing(), "wave locks the layout")
	tools.toggle_wave()
	_check(tools.current_id() == "draw", "back to the last editing tool")
	_check(modes == [false, true], "mode changes reported")
	tools.pick("draw")
	_check(tools.get_tool("draw").place_type == SurfaceObject.Mode.RELAY, "picking Draw again switches type")
	tools.pick("draw")
	_check(seen.size() >= 4, "tool changes reported")
	for t in tools.tools:
		_check(t.handle_input(InputEventMouseButton.new()) == false, "%s takes no input yet" % t.tool_id())
	tools.set_tool("select")


func _wave() -> void:
	var id := surface.add_note_at(Vector2(300, 300), 60, 0)
	var wave: WaveTool = tools.get_tool("wave")
	wave.play_at(Vector2(800, 600))
	_check(surface.waves.size() == 1, "empty space sends a wave")
	surface.waves.clear()
	wave.play_at(Vector2(302, 302))
	_check(surface.waves.size() == 1 and surface.waves[0].origin == surface.get_note(id).pos, "a note sends a wave from itself")
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
