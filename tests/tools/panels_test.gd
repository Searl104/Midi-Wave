extends "res://tests/support/tools_test_base.gd"
## Grid tool, tool options, sequences and draw-tool deletion.


func run() -> void:
	_grid_tool()
	_tool_options()
	_sequence()
	_draw_delete()


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
	_check(has == ["bind", "channel", "collection", "grid", "pitch", "tap", "velocity", "zoom"], "these tools have panels")
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
	options.surface = surface
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
	# The dots slide without jumps, however fast the hits come.
	s.passes_hit()
	_check(s.slide == 1.0, "a hit starts a slide of one step")
	var last := s.slide
	var eased := true
	for i in 8:
		s.tick(1.0 / 120.0)
		eased = eased and s.slide < last and s.slide > 0.0
		last = s.slide
	_check(eased and s.slide < 1.0, "it eases down")
	s.passes_hit()
	_check(is_equal_approx(s.slide, last + 1.0), "a hit during a slide adds to it, so nothing jumps")
	for i in 240:
		s.tick(1.0 / 60.0)
	_check(absf(s.slide) < 0.001, "it settles")
	surface.stop()
	_check(s.slide == 0.0, "Stop ends it")
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


func _draw_delete() -> void:
	tools.set_tool("draw")
	var a := surface.add_object(Vector2(300, 300), 60, 0)
	var b := surface.add_object(Vector2(500, 300), 62, 0)
	surface.save_notes()
	surface.history.end_group()
	var click := func(at: Vector2, shift: bool) -> void:
		for down in [true, false]:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.pressed = down
			e.shift_pressed = shift
			e.position = at
			tools.handle_input(e)
	click.call(surface.to_screen(Vector2(300, 300)), true)
	_check(surface.get_note(a) == null and surface.get_note(b) != null and surface.notes.size() == 1, "Shift-click deletes that note")
	surface.undo()
	_check(surface.get_note(a) != null, "and undoes")
	click.call(surface.to_screen(Vector2(700, 600)), true)
	_check(surface.notes.size() == 2, "on empty space it places nothing")
	click.call(surface.to_screen(Vector2(700, 600)), false)
	_check(surface.notes.size() == 3, "without Shift it places")
	tools.set_tool("select")
	surface.clear_notes()
