extends "res://tests/support/tools_test_base.gd"
## Layouts, velocity, per-Sound ports and collections.


func run() -> void:
	_layouts()
	_velocity()
	_port_slots()
	_collections()


func _device(port: String) -> FakeDevice:
	for d in FakeDevice.opened:
		if d.port == port:
			return d
	return null


func _layouts() -> void:
	for n in Layouts.list():
		Layouts.remove(n)
	surface.clear_notes()
	var saved_bpm: float = Settings.bpm
	var saved_slots: Array = Settings.midi_slots
	var saved_volumes: Array = Settings.channel_volumes
	Settings.midi_slots = saved_slots.duplicate()
	Settings.channel_volumes = saved_volumes.duplicate()
	var a := surface.add_object(Vector2(100, 100), 60, 2)
	surface.add_modifier(a, "sequence")
	surface.set_note_velocity(a, 40)
	surface.set_binding(a, "kp2")
	Settings.set_value("bpm", 90.0)
	Settings.set_value("divisions", 3)
	Settings.set_channel_volume(2, 0.25)
	Settings.set_channel_beats(2, 1.5)
	Settings.midi_slots[2] = "Bass"
	Settings.set_value("beat_spacing", 120.0)
	surface.view_offset = Vector2(33, 44)
	var options := OptionsPanel.new()
	options.surface = surface
	options.mappings = MidiMappings.new(surface)
	add_child(options)
	var panel: LayoutPanel = options.layouts
	# Saving.
	panel.name_field.text = "sets/opener"
	panel.save_pressed()
	_check(Array(Layouts.list()) == ["sets/opener"] and FileAccess.file_exists("user://layouts/sets/opener.json"), "saves into a folder")
	panel.name_field.text = "bad/"
	panel.save_pressed()
	_check(panel.status.visible and Layouts.list().size() == 1, "names follow the same rules")
	# Overwriting asks.
	Settings.set_value("bpm", 100.0)
	panel.name_field.text = "SETS/opener"
	panel.save_pressed()
	_check(panel.overwrite_row.visible and "sets/opener" in panel.status.text, "a used name asks, in any case")
	_check(int(Layouts.read("sets/opener").bpm) == 90, "and hasn't saved yet")
	panel._cancel_overwrite()
	_check(not panel.overwrite_row.visible and int(Layouts.read("sets/opener").bpm) == 90, "Keep keeps it")
	panel.save_pressed()
	panel._overwrite()
	_check(int(Layouts.read("sets/opener").bpm) == 100 and Layouts.list().size() == 1, "Overwrite replaces it, under its own name")
	# Changes, then load through the row.
	surface.clear_notes()
	surface.add_object(Vector2(500, 500), 70, 0)
	surface.add_object(Vector2(600, 500), 71, 0)
	surface.save_notes()
	Settings.set_value("bpm", 150.0)
	Settings.set_value("divisions", 4)
	Settings.set_channel_volume(2, 1.0)
	Settings.set_channel_beats(2, 0.0)
	Settings.midi_slots[2] = ""
	Settings.set_value("beat_spacing", 200.0)
	surface.view_offset = Vector2.ZERO
	surface.spawn_wave(Vector2(200, 200))
	panel.tree.reveal("sets/opener")
	panel.refresh()
	var row: LayoutRow = panel.tree.find_children("*", "LayoutRow", true, false)[0]
	row.load_button.pressed.emit()
	_check(row.confirm_button.visible and not row.load_button.visible and surface.notes.size() == 2, "Load asks first")
	_check(row.confirm_button.text == "Clear all and load?" and row.keep_button.text == "Cancel", "in plain words")
	row.keep_button.pressed.emit()
	_check(row.load_button.visible and surface.notes.size() == 2, "Keep leaves it alone")
	row.load_button.pressed.emit()
	row.confirm_button.pressed.emit()
	_check(surface.notes.size() == 1 and surface.waves.is_empty(), "confirming replaces the notes and stops")
	var o := surface.get_note(a)
	_check(o != null and o.velocity == 40 and o.binding == "kp2" and o.get_modifier("sequence") != null, "notes come back whole")
	_check(int(Settings.bpm) == 100 and Settings.divisions == 3, "tempo and divisions")
	_check(Settings.channel_volumes[2] == 0.25 and Settings.channel_beats[2] == 1.5, "sound settings")
	_check(Settings.midi_slots[2] == "Bass", "ports")
	_check(Settings.beat_spacing == 120.0 and surface.view_offset == Vector2(33, 44), "and the view")
	_check(not surface.history.can_undo(), "loading clears the undo history")
	_check(panel.name_field.text == "sets/opener", "the name is ready for saving over")
	# Delete asks, and folders tidy up.
	row = panel.tree.find_children("*", "LayoutRow", true, false)[0]
	row.delete_button.pressed.emit()
	_check(Layouts.list().size() == 1 and row.delete_button.text == "X" and row.confirm_button.text == "Delete" and row.keep_button.text == "Cancel", "X asks first")
	_check(row.delete_button.has_theme_stylebox_override("normal") and row.confirm_button.has_theme_stylebox_override("normal"), "deleting is tinted")
	_check(not row.load_button.has_theme_stylebox_override("normal") and not row.keep_button.has_theme_stylebox_override("normal"), "and nothing else is")
	row.confirm_button.pressed.emit()
	_check(Layouts.list().is_empty() and not DirAccess.dir_exists_absolute(Layouts.DIR + "sets"), "and removes it and its folder")
	# Bad and partial files.
	DirAccess.make_dir_recursive_absolute(Layouts.DIR)
	var bad := FileAccess.open(Layouts.DIR + "bad.json", FileAccess.WRITE)
	bad.store_string("{nope")
	bad.close()
	var notes_before := surface.notes.size()
	panel.load_layout("bad")
	_check(panel.status.visible and surface.notes.size() == notes_before, "a broken file loads nothing")
	Layouts.remove("bad")
	Layouts.apply({"notes": []}, surface)
	_check(surface.notes.is_empty() and int(Settings.bpm) == 100, "a partial file keeps what it lacks")
	options.queue_free()
	Settings.set_value("bpm", saved_bpm)
	Settings.set_value("divisions", 4)
	Settings.set_value("beat_spacing", 100.0)
	Settings.midi_slots = saved_slots
	Settings.channel_volumes = saved_volumes
	Settings.channel_beats.fill(0.0)
	surface.view_offset = Vector2.ZERO


func _velocity() -> void:
	var sent: Array = []
	var spy := func(m: PackedByteArray) -> void:
		if (m[0] & 0xF0) == 0x90:
			sent.append(m)
	Midi.message_sent.connect(spy)
	var tool: VelocityTool = tools.get_tool("velocity")
	var a := surface.add_object(Vector2(300, 300), 60, 0)
	var b := surface.add_object(Vector2(500, 300), 62, 0)
	surface.save_notes()
	surface.history.end_group()
	var oa := surface.get_note(a)
	_check(oa.velocity == 100, "notes start at 100%")
	# Scaling.
	surface.set_note_velocity(a, 50)
	oa.play(surface, 1.0, 0)
	_check(sent[-1][2] == 64, "velocity scales a full hit")
	oa.silence()
	oa.play(surface, 0.5, 0)
	_check(sent[-1][2] == 32, "and follows the wave")
	oa.silence()
	surface.set_note_velocity(a, 1)
	oa.play(surface, 0.1, 0)
	_check(sent[-1][2] == 1, "a low note still sounds")
	oa.silence()
	Settings.set_channel_volume(0, 0.5)
	surface.set_note_velocity(a, 50)
	oa.play(surface, 1.0, 0)
	_check(sent[-1][2] == 32, "sound volume applies on top")
	oa.silence()
	Settings.set_channel_volume(0, 1.0)
	surface.set_note_velocity(a, 0)
	_check(oa.velocity == 1, "stops at 1")
	surface.set_note_velocity(a, 300)
	_check(oa.velocity == 100, "and 100")
	# Saved, and shown.
	surface.set_note_velocity(a, 40)
	_check(oa.to_dict().velocity == 40 and "40%" in oa.hover_text(), "saved, and in the tooltip")
	var copy := Note.new()
	copy.load_dict(oa.to_dict(), Vector2.ZERO)
	_check(copy.velocity == 40, "loads")
	copy.load_dict({}, Vector2.ZERO)
	_check(copy.velocity == 100, "older saves are 100%")
	_check("%" not in surface.get_note(b).hover_text(), "100% isn't mentioned")
	# It's a plain tool.
	tools.set_tool("select")
	tools.pick("velocity")
	_check(tools.current == tool and tools.ring_option.tool_id() != "velocity", "it's a tool, not a ring option")
	# Stamp and drag.
	Settings.velocity_stamp = 70.0
	var at := surface.to_screen(oa.pos)
	surface.history.end_group()
	_press(MOUSE_BUTTON_LEFT, true, at)
	_check(oa.velocity == 70, "a click stamps the panel's value")
	var move := InputEventMouseMotion.new()
	move.position = at + Vector2(0, -20)
	tools.handle_input(move)
	_check(oa.velocity == 80, "dragging up raises it")
	move.position = at + Vector2(0, 40)
	tools.handle_input(move)
	_check(oa.velocity == 50, "dragging down lowers it")
	_press(MOUSE_BUTTON_LEFT, false, at)
	surface.undo()
	_check(oa != null and surface.get_note(a).velocity == 40, "one undo")
	oa = surface.get_note(a)
	_press(MOUSE_BUTTON_LEFT, true, Vector2(900, 700))
	_press(MOUSE_BUTTON_LEFT, false, Vector2(900, 700))
	_check(surface.notes.size() == 2, "empty space does nothing")
	# A group.
	surface.selection.notes = {a: true, b: true}
	surface.set_note_velocity(a, 30)
	surface.set_note_velocity(b, 60)
	Settings.velocity_stamp = 50.0
	_press(MOUSE_BUTTON_LEFT, true, at)
	move.position = at + Vector2(0, -20)
	tools.handle_input(move)
	_press(MOUSE_BUTTON_LEFT, false, at)
	_check(surface.get_note(a).velocity == 60 and surface.get_note(b).velocity == 60, "the selection follows")
	surface.selection.clear()
	Settings.velocity_stamp = 100.0
	tools.set_tool("select")
	surface.selection.clear()
	# The dial stays available to rings.
	var turns: Array = []
	var on_turn := func(v: float) -> void: turns.append(roundi(v * 100.0))
	radial.dial_changed.connect(on_turn)
	radial.outer_items = []
	radial.inner_items = []
	radial.center_item = {}
	radial.open(Vector2(600, 400), true)
	radial.dial = true
	var c: Vector2 = radial._center
	_radial_move(c + Vector2(0, -100))
	_radial_move(c + Vector2(100, 0))
	_radial_move(c + Vector2(-5, 5))
	_radial_move(c + Vector2(-2, 100))
	_check(turns == [50, 83, 0], "moving around the dial turns it, the centre doesn't, and the gap takes the nearer end")
	_radial_press(MOUSE_BUTTON_RIGHT, false, c + Vector2(-2, 100))
	_check(not radial.visible, "releasing a hold closes it")
	radial.open(c, false)
	radial.dial = true
	var gui := InputEventMouseButton.new()
	gui.button_index = MOUSE_BUTTON_LEFT
	gui.pressed = true
	gui.position = c + Vector2(0, -100)
	radial._gui_input(gui)
	_check(turns[-1] == 50, "a left click sets it")
	gui.pressed = false
	radial._gui_input(gui)
	gui.pressed = true
	gui.position = c + Vector2(400, 0)
	radial._gui_input(gui)
	_check(not radial.visible, "clicking off it closes")
	radial.dial_changed.disconnect(on_turn)
	radial.dial = false
	tools.pick("pitch")
	_press(MOUSE_BUTTON_RIGHT, true, surface.to_screen(Vector2(300, 300)))
	_check(not radial.dial and not radial.outer_items.is_empty(), "rings stay rings")
	radial.close()
	Midi.message_sent.disconnect(spy)
	tools.set_tool("select")
	surface.clear_notes()


func _port_slots() -> void:
	var saved: Array = Settings.midi_slots
	Settings.midi_slots = saved.duplicate()
	Settings.midi_slots.fill("")
	FakeDevice.opened.clear()
	Midi.use_backend(func() -> Object: return FakeDevice.new())
	_check(not Midi.is_open() and Midi.has_native_backend(), "no ports open at first")
	Midi.set_slot(0, "Bass")
	Midi.set_slot(5, "Keys")
	Midi.set_slot(6, "Keys")
	Midi.set_slot(7, "Gone")
	_check(Array(Midi.open_ports()) == ["Bass", "Keys"], "ports open as slots want them")
	_check(FakeDevice.opened.size() == 2, "two slots share one device")
	_check(Array(Midi.missing_ports()) == ["Gone"], "a port that isn't there is reported")
	var bass := _device("Bass")
	var keys := _device("Keys")
	bass.sent.clear()
	keys.sent.clear()
	Midi.note_on(60, 100, 0)
	Midi.note_on(62, 100, 5)
	Midi.note_off(62, 6)
	_check(bass.sent.size() == 1 and bass.sent[0] == PackedByteArray([0x90, 60, 100]), "slot 1 reaches its port on channel 1")
	_check(keys.sent[0] == PackedByteArray([0x90, 62, 100]), "slot 6 too, on channel 1")
	_check(keys.sent[1][0] == 0x80, "slot 7 shares it, also on channel 1")
	bass.sent.clear()
	keys.sent.clear()
	Midi.note_on(60, 100, 7)
	Midi.note_on(60, 100, 9)
	_check(bass.sent.is_empty() and keys.sent.is_empty(), "missing and empty slots send nothing")
	Settings.set_channel_volume(5, 0.5)
	Midi.note_on(62, 100, 5)
	_check(keys.sent[0][2] == 50, "volume still follows the colour")
	Settings.set_channel_volume(5, 1.0)
	# Panic reaches every port, and every channel.
	bass.sent.clear()
	keys.sent.clear()
	Midi.panic()
	_check(bass.sent.size() == 32 and keys.sent.size() == 32 and bass.sent[31][0] == 0xBF, "Panic covers each port")
	# Changing a slot silences first, and closes what's unused.
	Midi.set_slot(5, "")
	_check(_device("Keys") != null, "a port stays open while a slot uses it")
	keys = _device("Keys")
	keys.sent.clear()
	Midi.set_slot(6, "")
	_check(keys.sent.size() == 32 and not keys.is_port_open() and Array(Midi.open_ports()) == ["Bass"], "the last slot closes it, after a Panic")
	# The panel.
	var options := OptionsPanel.new()
	options.surface = surface
	options.mappings = MidiMappings.new(surface)
	add_child(options)
	options.refresh_ports()
	var picker: OptionButton = options._slots[0]
	_check(options._slots.size() == 16 and picker.item_count == 4 and picker.get_item_text(picker.selected) == "Bass", "a picker per slot")
	_check(options._slots[7].get_item_text(options._slots[7].selected) == "Gone (not found)", "a missing port stays picked")
	_check(options._slots[3].get_item_text(options._slots[3].selected) == "None", "and an empty slot says None")
	_check("Gone" in options._port_status.text, "the status names it")
	options._slots[3].select(3)
	options._slots[3].item_selected.emit(3)
	_check(Settings.midi_slots[3] == "Drums" and Array(Midi.open_ports()).has("Drums"), "picking opens the port")
	options.queue_free()
	Midi.use_backend(Callable())
	Settings.midi_slots = saved


func _collections() -> void:
	var tool: CollectionTool = tools.get_tool("collection")
	tools.set_tool("select")
	surface.clear_notes()
	surface.selection.clear()
	for n in Collections.list():
		Collections.remove(n)
	var a := surface.add_object(Vector2(100, 100), 60, 2)
	var b := surface.add_object(Vector2(300, 100), 64, 3)
	surface.add_modifier(a, "relay")
	surface.add_modifier(b, "sequence")
	surface.set_sequence_count(b, 5)
	surface.set_sequence_step(b, 2, false)
	surface.set_binding(b, "kp4")
	surface.snapping.toggle_grid(surface.get_note(b), false)
	var e: Emitter = surface.get_note(a).emitter()
	e.attached = false
	e.pos = Vector2(100, 200)
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
	surface.undo()
	_check(surface.notes.size() == before, "one undo removes the lot")
	# Stamping.
	surface.selection.clear()
	tools.set_tool("select")
	tool.pick("kits/Bells 1")
	_check(tools.current == tool, "picking a row switches to the tool")
	var shift_click := InputEventMouseButton.new()
	shift_click.button_index = MOUSE_BUTTON_LEFT
	shift_click.pressed = true
	shift_click.shift_pressed = true
	shift_click.position = Vector2(500, 300)
	tool.handle_input(shift_click)
	_check(surface.notes.size() == before + 2 and tool.picked == "kits/Bells 1", "Shift-click places it and keeps it loaded")
	_press(MOUSE_BUTTON_LEFT, true, Vector2(700, 500))
	_press(MOUSE_BUTTON_LEFT, false, Vector2(700, 500))
	_check(surface.notes.size() == before + 4 and tool.picked == "", "a plain click places it and clears it")
	_check(tool._ghosts.is_empty(), "and the ghost goes")
	_press(MOUSE_BUTTON_LEFT, true, Vector2(300, 700))
	_press(MOUSE_BUTTON_LEFT, false, Vector2(300, 700))
	_check(surface.notes.size() == before + 4 and tools.current == tool, "the next click places nothing, in the same tool")
	surface.undo()
	surface.undo()
	tool.pick("kits/Bells 1")
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
	_check(row.delete_button.text == "X" and row.confirm_button.text == "Delete" and row.cancel_button.text == "Cancel", "in plain words")
	row.cancel_button.pressed.emit()
	_check(row.delete_button.visible and not row.confirm_button.visible and Collections.list().size() == 1, "Keep keeps it")
	row.delete_button.pressed.emit()
	row.confirm_button.pressed.emit()
	_check(Collections.list().is_empty() and tool.picked == "", "Confirm deletes it, and unpicks it")
	box.queue_free()
	# Names.
	_check(NamedFiles.cleaned('a:b*c?d"e<f>g|h\\i') == "abcdefgh/i", "typing keeps to file name characters")
	_check(NamedFiles.normalised("  a//b / c ") == "a/b/c", "extra slashes and spaces go")
	_check(NamedFiles.problem("") != "" and NamedFiles.problem("a/") != "", "a name needs a last part")
	_check(NamedFiles.problem("a./b") != "" and NamedFiles.problem("..") != "" and NamedFiles.problem("a/..") != "", "no dots at the end, or climbing out")
	_check(NamedFiles.problem("con") != "" and NamedFiles.problem("a/NUL.x") != "" and NamedFiles.problem("com1/a") != "", "no reserved names")
	_check(NamedFiles.problem("console") == "" and NamedFiles.problem("a.b/c-d_e f") == "", "ordinary names pass")
	_check(NamedFiles.problem("a".repeat(101)) != "", "not too long")
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
	_check(tree.find_children("*", "FolderRow", true, false).size() == 1, "one folder at the top")
	_check(tree.find_children("*", "CollectionRow", true, false).size() == 1, "closed, with the loose collection")
	tool.toggle_folder("a")
	tool.toggle_folder("a/b")
	var rows := tree.find_children("*", "CollectionRow", true, false)
	_check(rows.size() == 3 and tree.find_children("*", "FolderRow", true, false).size() == 2, "opening folders shows them")
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
