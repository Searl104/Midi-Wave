extends "res://tests/support/tools_test_base.gd"
## Radial menu rings, tab behaviour, key bindings and group rings.


func run() -> void:
	_quick_pick()
	_ring_options()
	_tab()
	_tool_keys()
	_bindings()
	_group_rings()


func _quick_pick() -> void:
	var a := surface.add_note_at(Vector2(640, 400), 60, 0)
	surface.add_modifier(a, "relay")
	surface.add_modifier(a, "sequence")
	var o := surface.get_note(a)
	tools.set_tool("select")
	# The relay's tab opens a cooldown dial: no rings, no centre.
	var dock: Vector2 = o.emitter().dock_screen_pos(surface, o)
	var open_dial := func() -> Vector2:
		_press(MOUSE_BUTTON_RIGHT, true, dock)
		return radial._center
	var c: Vector2 = open_dial.call()
	_check(radial.visible and radial.holding and radial.dial, "the relay tab opens a dial, held")
	_check(radial.outer_items.is_empty() and radial.inner_items.is_empty() and radial.center_item.is_empty(), "with no rings and no centre")
	_check(is_equal_approx(radial.dial_value, 8.0 / 32.0) and radial.dial_text == "1", "showing the cooldown, 1 beat")
	var at_value := func(v: float) -> Vector2:
		return c + Vector2.from_angle(RadialMenu.DIAL_START + RadialMenu.DIAL_SWEEP * v) * 100.0
	surface.history.end_group()
	var steps := surface.history.undo_steps()
	_radial_move(at_value.call(0.0))
	_check(o.emitter().cooldown == 0.0 and radial.dial_text == "Retrigger", "the start is Retrigger")
	_radial_move(at_value.call(1.0))
	_check(o.emitter().cooldown == 4.0 and radial.dial_text == "4", "the end is 4 beats")
	_radial_move(at_value.call(11.0 / 32.0))
	_check(o.emitter().cooldown == 1.375 and radial.dial_text == "1⅜", "in eighth-beat steps")
	_radial_press(MOUSE_BUTTON_RIGHT, false, at_value.call(11.0 / 32.0))
	_check(not radial.visible and o.emitter().cooldown == 1.375, "release keeps it and closes")
	_check(surface.history.undo_steps() == steps + 1, "one turn of the dial is one undo step")
	surface.undo()
	o = surface.get_note(a)
	_check(o.emitter().cooldown == 1.0, "which undoes to where it started")
	# A still release leaves the dial open; a left drag turns it and a click off it closes it.
	c = open_dial.call()
	_radial_press(MOUSE_BUTTON_RIGHT, false, c)
	_check(radial.visible and not radial.holding, "a still release leaves the dial open")
	var left := InputEventMouseButton.new()
	left.button_index = MOUSE_BUTTON_LEFT
	left.pressed = true
	left.position = at_value.call(0.5)
	radial._gui_input(left)
	_check(radial.visible and surface.get_note(a).emitter().cooldown == 2.0, "a left press turns it")
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = left.position
	radial._gui_input(up)
	left.position = c + Vector2(250, 0)
	radial._gui_input(left)
	_check(not radial.visible, "a click off the dial closes it")
	_check(RelaySettingsRing.label(0.125) == "⅛" and RelaySettingsRing.label(1.5) == "1½" and RelaySettingsRing.label(0.0) == "Retrigger", "labels")
	_check(RelaySettingsRing.stop_for(1.0 / 3.0) == 3 and RelaySettingsRing.label(1.0 / 3.0) == "≈ ⅜", "an older save's ⅓ sits near ⅜")
	# Quick pick on a ring of items: the sequence's.
	o = surface.get_note(a)
	var tab: Vector2 = o.get_modifier("sequence")._tab_centre(surface, o)
	var open_seq := func() -> Vector2:
		_press(MOUSE_BUTTON_RIGHT, true, tab)
		return radial._center
	c = open_seq.call()
	_check(radial.holding and not radial.dial, "the sequence tab opens its rings, held")
	var item: Vector2 = c + Vector2(0, -112)         # the top of the outer ring: step 1
	_radial_move(item)
	_radial_press(MOUSE_BUTTON_RIGHT, false, item)
	_check(o.get_modifier("sequence").steps == [false, false] and not radial.visible, "release on the outer ring picks and closes")
	c = open_seq.call()
	item = c + Vector2(0, -54)                       # the top of the inner ring: 1 step
	_radial_move(item)
	_radial_press(MOUSE_BUTTON_RIGHT, false, item)
	_check(o.get_modifier("sequence").steps.size() == 1 and not radial.visible, "release on the inner ring picks and closes")
	surface.set_sequence_count(a, 2)
	var settings := JSON.stringify(o.to_dict())
	c = open_seq.call()
	_radial_move(c + Vector2(250, 0))
	_radial_press(MOUSE_BUTTON_RIGHT, false, c + Vector2(250, 0))
	_check(not radial.visible and JSON.stringify(o.to_dict()) == settings, "release off the rings cancels")
	c = open_seq.call()
	_radial_press(MOUSE_BUTTON_RIGHT, false, c)
	_check(not radial.visible and JSON.stringify(o.to_dict()) == settings, "a still release, with nothing highlighted, closes it")
	# Painting: a left drag across the steps gives each the first step's new state.
	surface.set_sequence_count(a, 4)
	for i in 4:
		surface.set_sequence_step(a, i, i % 2 == 0)              # On, Off, On, Off
	var seq: SequenceModifier = o.get_modifier("sequence")
	c = open_seq.call()
	var step_at := func(i: int) -> Vector2:
		return c + Vector2.from_angle(-PI / 2.0 + TAU * i / 4.0) * 112.0
	surface.history.end_group()
	var before := surface.history.undo_steps()
	_radial_press(MOUSE_BUTTON_LEFT, true, step_at.call(0))
	_check(seq.steps == [false, false, true, false], "the press turns its step Off")
	_radial_move(step_at.call(1))
	_radial_move(step_at.call(2))
	_radial_move(step_at.call(1))
	_check(seq.steps == [false, false, false, false], "and the drag paints Off, each step once")
	_radial_press(MOUSE_BUTTON_LEFT, false, step_at.call(2))
	_check(radial.visible and surface.history.undo_steps() == before + 1, "one stroke is one undo step, and the ring stays open")
	_radial_press(MOUSE_BUTTON_LEFT, true, step_at.call(3))
	_radial_move(step_at.call(0))
	_radial_press(MOUSE_BUTTON_LEFT, false, step_at.call(0))
	_check(seq.steps == [true, false, false, true], "starting on an Off step paints On")
	_radial_move(step_at.call(1))
	_check(seq.steps == [true, false, false, true], "moving after the release paints nothing")
	_radial_move(c + Vector2(250, 0))
	_radial_press(MOUSE_BUTTON_RIGHT, false, c + Vector2(250, 0))
	_check(not radial.visible and seq.steps == [true, false, false, true], "and a release off the rings closes it, keeping the paint")
	surface.undo()
	o = surface.get_note(a)
	_check(o.get_modifier("sequence").steps == [false, false, false, false], "undo takes back one stroke")
	# On a ring left open, the same.
	seq = o.get_modifier("sequence")
	c = open_seq.call()
	radial.holding = false
	var gui_press := func(at: Vector2, down: bool) -> void:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = at
		radial._gui_input(e)
	var gui_move := func(at: Vector2) -> void:
		var e := InputEventMouseMotion.new()
		e.position = at
		radial._gui_input(e)
	gui_press.call(step_at.call(1), true)
	gui_move.call(step_at.call(2))
	gui_move.call(step_at.call(3))
	gui_press.call(step_at.call(3), false)
	_check(seq.steps == [false, true, true, true] and radial.visible, "an open ring paints too")
	radial.close()
	# The Modifier ring doesn't paint: a drag can't remove a modifier and its settings.
	tools.pick("modifier")
	_press(MOUSE_BUTTON_RIGHT, true, Vector2(640, 400))
	c = radial._center
	radial.holding = false
	var mod_at := func(i: int) -> Vector2:
		return c + Vector2.from_angle(-PI / 2.0 + TAU * i / 4.0) * 112.0
	gui_press.call(mod_at.call(3), true)                         # Silent
	gui_move.call(mod_at.call(2))                                # Relay
	gui_move.call(mod_at.call(1))                                # Sequence
	gui_press.call(mod_at.call(1), false)
	o = surface.get_note(a)
	_check(o.get_modifier("silent") != null and o.relay() != null and o.get_modifier("sequence") != null, "the Modifier ring only takes the press")
	radial.close()
	surface.remove_modifier(a, "silent")
	tools.pick("pitch")
	o = surface.get_note(a)
	tab = o.get_modifier("sequence")._tab_centre(surface, o)
	# A left click during the hold picks and keeps it open.
	c = open_seq.call()
	_radial_press(MOUSE_BUTTON_LEFT, true, c + Vector2(0, -112))
	_check(radial.visible and radial.holding and o.get_modifier("sequence").steps[0], "left click during the hold keeps it open")
	_radial_press(MOUSE_BUTTON_RIGHT, false, c)
	radial.close()
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
	# With nothing highlighted, a release without moving closes it, changing nothing.
	for option in ["pitch", "channel", "modifier"]:
		tools.pick(option)
		var before := JSON.stringify(surface.get_note(a).to_dict())
		_press(MOUSE_BUTTON_RIGHT, true, Vector2(640, 400))
		_check(radial._hover_ring == "", "%s opens with nothing highlighted" % option)
		_radial_press(MOUSE_BUTTON_RIGHT, false, Vector2(640, 400))
		_check(not radial.visible and JSON.stringify(surface.get_note(a).to_dict()) == before, "%s: a release before highlighting anything closes it" % option)
	tools.pick("modifier")
	# Quick pick adds; the same pick removes; a group follows.
	_press(MOUSE_BUTTON_RIGHT, true, Vector2(640, 400))
	var c: Vector2 = radial._center
	var toggle_at: Vector2 = c + Vector2.from_angle(-PI / 2.0 + TAU / 4.0) * 112.0   # Sequence, of four
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
	tools.set_tool("select")
	tools.pick("pitch")
	var seen: Array = []
	for i in 4:
		_key(KEY_TAB)
		seen.append(tools.ring_option.tool_id())
	_check(seen == ["channel", "modifier", "pitch", "channel"], "Tab cycles the ring choice, wrapping")
	_check(tools.current_id() == "select" and tools.is_editing(), "and leaves the tool alone")
	var back: Array = []
	for i in 3:
		_key(KEY_TAB, false, true)
		back.append(tools.ring_option.tool_id())
	_check(back == ["pitch", "modifier", "channel"], "Shift+Tab goes back")
	tools.pick("pitch")
	var changed := [false]
	var on_change := func(_id: String) -> void: changed[0] = true
	tools.tool_changed.connect(on_change)
	_key(KEY_TAB)
	tools.tool_changed.disconnect(on_change)
	_check(changed[0], "and reports it, so the bar redraws and it's saved")
	tools.set_tool("tap")
	_key(KEY_TAB)
	_check(tools.current_id() == "tap" and tools.ring_option.tool_id() == "modifier", "in Tap too, staying in Tap")
	tools.set_tool("select")
	_press(MOUSE_BUTTON_MIDDLE, true, Vector2.ZERO)
	_key(KEY_TAB)
	_check(tools.current_id() == "pan" and tools.ring_option.tool_id() == "pitch", "and during a spring-load")
	_press(MOUSE_BUTTON_MIDDLE, false, Vector2.ZERO)
	_check(tools.current_id() == "select", "which still returns")
	_key(KEY_TAB, true)
	_check(tools.ring_option.tool_id() == "pitch", "Ctrl+Tab does nothing")
	tools.pick("pitch")
	tools.set_tool("select")


func _tool_keys() -> void:
	var saved: Dictionary = Settings.tool_keys
	Settings.tool_keys = ToolKeys.DEFAULTS.duplicate()
	tools.set_tool("select")
	var keys := {"tap": KEY_T, "select": KEY_S, "draw": KEY_D, "bind": KEY_B, "grid": KEY_G,
			"velocity": KEY_V, "collection": KEY_C, "pan": KEY_H, "zoom": KEY_Z}
	for id in ToolKeys.ORDER:
		_key(keys[id])
		_check(tools.current_id() == id, "%s picks %s" % [OS.get_keycode_string(keys[id]), id])
	tools.set_tool("select")
	_key(KEY_T)
	_check(tools.current_id() == "tap" and not tools.is_editing(), "T locks the layout, like Tap on the bar")
	_key(KEY_S)
	_check(tools.current_id() == "select" and tools.is_editing(), "and S unlocks it")
	_key(KEY_D, true)
	_check(tools.current_id() == "select", "Ctrl+D picks nothing")
	_key(KEY_D, false, true)
	_check(tools.current_id() == "select", "nor does Shift+D")
	_press(MOUSE_BUTTON_MIDDLE, true, Vector2.ZERO)
	_key(KEY_D)
	_check(tools.current_id() == "pan", "ignored while spring-loaded")
	_press(MOUSE_BUTTON_MIDDLE, false, Vector2.ZERO)
	_check(tools.current_id() == "select", "and the spring-load returns")
	# Assigning, taking a key from another tool, clearing and resetting.
	ToolKeys.assign("draw", KEY_S)
	_check(ToolKeys.key_for("draw") == "S" and ToolKeys.key_for("select") == "", "a key moves to the new tool")
	_key(KEY_S)
	_check(tools.current_id() == "draw", "and picks it")
	tools.set_tool("select")
	ToolKeys.clear("draw")
	_key(KEY_S)
	_check(tools.current_id() == "select", "a cleared key does nothing")
	ToolKeys.reset()
	_check(Settings.tool_keys == ToolKeys.DEFAULTS, "Reset returns to the defaults")
	# Keys that can't be learned.
	var refused := func(code: Key, shift: bool = false) -> bool:
		var e := InputEventKey.new()
		e.keycode = code
		e.shift_pressed = shift
		return ToolKeys.refusal(e) != ""
	_check(refused.call(KEY_SPACE) and refused.call(KEY_TAB) and refused.call(KEY_M) and refused.call(KEY_COMMA)
			and refused.call(KEY_DELETE) and refused.call(KEY_ESCAPE), "keys the app uses are refused")
	_check(refused.call(KEY_K, true), "as are keys with Shift")
	var kp := InputEventKey.new()
	kp.physical_keycode = KEY_KP_3
	_check(ToolKeys.refusal(kp) != "" and ToolKeys.tool_for(kp) == "", "and the keypad digits")
	_check(not refused.call(KEY_K) and not refused.call(KEY_F1), "other keys are fine")
	# The Controls tab: Learn takes the next key press, refuses used keys, and Esc cancels.
	var options := OptionsPanel.new()
	options.surface = surface
	options.mappings = MidiMappings.new(surface)
	add_child(options)
	options.toggle()
	var row: Dictionary = options._key_rows["grid"]
	_check(row.value.text == "G", "the tab shows each key")
	row.learn.pressed.emit()
	_check(row.value.text == "Press a key..." and row.learn.text == "Cancel", "Learn listens")
	var press := func(code: Key) -> void:
		var e := InputEventKey.new()
		e.keycode = code
		e.pressed = true
		options._input(e)
	press.call(KEY_SHIFT)
	_check(options._key_listening == "grid", "a modifier on its own is skipped")
	press.call(KEY_SPACE)
	_check(options._key_listening == "grid" and row.warning.visible, "a used key is refused, and it keeps listening")
	press.call(KEY_K)
	_check(ToolKeys.key_for("grid") == "K" and row.value.text == "K" and not row.warning.visible, "a free key is learned")
	row.learn.pressed.emit()
	press.call(KEY_D)
	_check(ToolKeys.key_for("grid") == "D" and ToolKeys.key_for("draw") == "", "taking another tool's key")
	_check(row.warning.visible and row.warning.text.contains("Draw"), "says which tool lost it")
	row.learn.pressed.emit()
	press.call(KEY_ESCAPE)
	_check(options._key_listening == "" and ToolKeys.key_for("grid") == "D", "Esc cancels")
	row.learn.pressed.emit()
	options.tabs.current_tab = 0
	_check(options._key_listening == "", "changing tab cancels")
	row.clear.pressed.emit()
	_check(row.value.text == "None" and row.clear.disabled, "Clear shows")
	options.queue_free()
	Settings.tool_keys = saved
	tools.set_tool("select")


func _bindings() -> void:
	var a := surface.add_note_at(Vector2(300, 300), 60, 0)
	var b := surface.add_note_at(Vector2(500, 300), 62, 0)
	var r := surface.add_note_at(Vector2(700, 300), 64, 0)
	surface.add_modifier(r, "relay")
	surface.add_modifier(r, "silent")
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
	radial.outer_chosen.emit("silent")
	radial.close()
	_check(surface.get_note(g4).relay() != null and surface.get_note(e4).get_modifier("sequence") != null, "modifiers spread")
	_check(not surface.get_note(g4).sounds() and surface.get_note(lone).sounds(), "Silent spreads too")
	var o := surface.get_note(c4)
	_press(MOUSE_BUTTON_RIGHT, true, o.emitter().dock_screen_pos(surface, o))
	radial.dial_changed.emit(16.0 / 32.0)
	radial.close()
	_check(surface.get_note(g4).emitter().cooldown == 2.0 and surface.get_note(e4).emitter().cooldown == 2.0, "relay settings spread")
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
	radial.dial_changed.emit(24.0 / 32.0)
	radial.close()
	_check(surface.get_note(g4).emitter().cooldown == 3.0 and surface.get_note(e4).emitter().cooldown == 2.0, "selected diamonds spread")
	sel.clear()
	Settings.set_value("scale_name", scale_before)
	surface.clear_notes()
