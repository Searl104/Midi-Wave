extends "res://tests/support/tools_test_base.gd"
## Radial menu rings, tab behaviour, key bindings and group rings.


func run() -> void:
	_quick_pick()
	_ring_options()
	_tab()
	_bindings()
	_group_rings()


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
	Settings.set_value("scale_name", scale_before)
	surface.clear_notes()
