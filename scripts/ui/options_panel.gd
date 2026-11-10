class_name OptionsPanel
extends PanelContainer
## Slide-in options for the whole app, in five tabs: General, MIDI, Controls, Layout and Look. Settings that belong to a
## tool are in its tool panel instead.

signal clear_notes_requested
signal reset_layout_requested
signal test_layout_requested

const WIDTH := 330.0

var mappings: MidiMappings
var surface: WaveSurface
var layouts: LayoutPanel

var _slots: Array = []         ## a port picker per slot
var _port_status: Label


func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/glass.gdshader")
	mat.set_shader_parameter("opacity", 0.78)
	material = mat
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_left = -WIDTH - 16.0
	offset_right = -16.0
	offset_top = 16.0
	offset_bottom = -16.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN   # wide content grows into the window
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	hide()
	visibility_changed.connect(func() -> void:
		if not visible:
			mappings.cancel()
			_cancel_key_learn())
	Midi.port_changed.connect(func(_n: String) -> void: _update_port_status())


func toggle() -> void:
	if visible:
		hide()
	else:
		refresh_ports()
		_refresh_controls()
		layouts.refresh()
		show()


var tabs: TabContainer


func _build() -> void:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	add_child(outer)

	var head := HBoxContainer.new()
	outer.add_child(head)
	var title := Label.new()
	title.text = "Options"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(PanelBuilder.button("Close", hide, "Closes Options."))

	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.focus_mode = Control.FOCUS_NONE
	tabs.use_hidden_tabs_for_min_size = true    # keeps the panel one width across tabs
	outer.add_child(tabs)
	tabs.tab_changed.connect(func(_i: int) -> void:
		mappings.cancel()
		_cancel_key_learn())
	var box := _tab("General")
	_build_midi(_tab("MIDI"))
	_build_controls(_tab("Controls"))
	_build_layout(_tab("Layout"))
	_build_look(_tab("Look"))

	PanelBuilder.section(box, "PREVIEW", Palette.BLUE)
	PanelBuilder.check(box, "Play notes while hovering the pitch ring", "hover_preview")

	PanelBuilder.section(box, "TIMING", Palette.ACCENT)
	var tempo := PanelBuilder.slider(box, "Tempo", "bpm", 40.0, 240.0, 1.0, func(v: float) -> String: return "%d BPM" % v)
	Settings.changed.connect(func(key: String) -> void:
		if key == "bpm":                 # a layout can change it
			tempo.value = Settings.bpm
		elif key == "midi_slots":
			refresh_ports())
	box.add_child(PanelBuilder.hint("Waves cross one beat of space per beat, so the layout stays in time at any tempo."))

	PanelBuilder.section(box, "DISPLAY", Palette.YELLOW)
	PanelBuilder.check(box, "Colour-blind palette", "colorblind")
	box.add_child(PanelBuilder.hint("Eight colour-blind safe sound colours; sounds 9-16 reuse them with a double outline. Hover a note for its sound number."))


## MIDI tab: where notes go, and the controller that plays them.
func _build_midi(box: VBoxContainer) -> void:
	PanelBuilder.section(box, "MIDI OUTPUT", Palette.BLUE)
	box.add_child(PanelBuilder.hint("A sound is one of the 16 note colours, sent to the port picked here, always on channel 1. Sounds can share a port."))
	for slot in Midi.SLOTS:
		_slots.append(_slot_row(box, slot))
	var port_row := HBoxContainer.new()
	box.add_child(port_row)
	_port_status = Label.new()
	_port_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_port_status.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_port_status.add_theme_font_size_override("font_size", 12)
	_port_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	port_row.add_child(_port_status)
	port_row.add_child(PanelBuilder.button("Refresh", refresh_ports, "Looks for MIDI output ports, and opens any that sounds are waiting for."))
	port_row.add_child(PanelBuilder.button("Panic", Midi.panic, "Stops every sounding note on all ports."))

	PanelBuilder.section(box, "MIDI INPUT", Palette.BLUE)
	box.add_child(MidiInputControls.new())


## Layout tab: saved layouts, and what replaces the surface.
func _build_layout(box: VBoxContainer) -> void:
	PanelBuilder.section(box, "SAVED LAYOUTS", Palette.YELLOW)
	box.add_child(PanelBuilder.hint("A layout keeps the notes, tempo, divisions, sound volumes and lengths, ports and view. Loading it replaces all of those, and can't be undone."))
	layouts = LayoutPanel.new()
	layouts.surface = surface
	box.add_child(layouts)
	PanelBuilder.section(box, "NOTES", Palette.TEXT_DIM)
	var notes_row := HBoxContainer.new()
	box.add_child(notes_row)
	notes_row.add_child(PanelBuilder.danger(PanelBuilder.button("Clear all", func() -> void: clear_notes_requested.emit(), "Removes every note from the surface.")))
	notes_row.add_child(PanelBuilder.danger(PanelBuilder.button("Default layout", func() -> void: reset_layout_requested.emit(), "Replaces the notes with the starting ring of notes.")))
	notes_row.add_child(PanelBuilder.danger(PanelBuilder.button("Test layout", func() -> void: test_layout_requested.emit(), "Replaces the notes with a self-playing demo of each feature.")))
	box.add_child(PanelBuilder.hint("Test layout replaces the notes with one group per feature and starts playing. Stop ends it."))


## Controls tab: a row per tool, each learning the next key press, then a row per action, each
## learning the next MIDI message from the controller.
var _control_rows := {}
var _controller_hint: Label
var _key_rows := {}
var _key_listening := ""           ## the tool waiting for a key press, or ""


func _build_controls(box: VBoxContainer) -> void:
	PanelBuilder.section(box, "TOOL KEYS", Palette.YELLOW)
	box.add_child(PanelBuilder.hint("Press Learn, then press a key. Pressing it picks the tool, as clicking it on the toolbar does. A key on its own only: Space, Tab, Esc, M, < >, Delete, Backspace, the keypad digits and KP Enter are already used."))
	for id in ToolKeys.ORDER:
		_key_rows[id] = _key_row(box, id)
	box.add_child(PanelBuilder.button("Reset keys", func() -> void:
		_key_listening = ""
		ToolKeys.reset()
		_refresh_keys(), "Returns to the starting keys: T, S, D, B, G, V, C, H and Z."))
	Settings.changed.connect(func(key: String) -> void:
		if key == "tool_keys":
			_refresh_keys())
	_refresh_keys()

	PanelBuilder.section(box, "MIDI MAPPINGS", Palette.BLUE)
	box.add_child(PanelBuilder.hint("Press Learn, then press a key, pad or button, or move a knob. A control change fires each time it rises above 0."))
	_controller_hint = PanelBuilder.hint("Pick a controller under MIDI input on the MIDI tab first.")
	_controller_hint.add_theme_color_override("font_color", Palette.YELLOW)
	box.add_child(_controller_hint)
	for action in MidiMappings.ACTIONS:
		_control_rows[action] = _control_row(box, action)
	box.add_child(PanelBuilder.button("Reset mappings", mappings.reset, "Returns to the starting mappings: MIDI Stop runs Stop."))
	mappings.changed.connect(_refresh_controls)
	Settings.changed.connect(func(key: String) -> void:
		if key == "midi_in_port":
			_refresh_controls())
	_refresh_controls()


func _control_row(box: VBoxContainer, action: String) -> Dictionary:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	box.add_child(col)
	var row := HBoxContainer.new()
	col.add_child(row)
	var name_l := Label.new()
	name_l.text = MidiMappings.ACTIONS[action]
	name_l.tooltip_text = MidiMappings.TIPS[action]
	name_l.mouse_filter = Control.MOUSE_FILTER_PASS
	name_l.custom_minimum_size.x = 84
	row.add_child(name_l)
	var value := Label.new()
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.clip_text = true
	value.add_theme_color_override("font_color", Palette.TEXT_DIM)
	row.add_child(value)
	var learn := PanelBuilder.button("Learn", func() -> void:
		if mappings.listening == action:
			mappings.cancel()
		else:
			_cancel_key_learn()
			mappings.listen(action), "Waits for the next MIDI message from the controller. Press again to cancel.")
	row.add_child(learn)
	var clear := PanelBuilder.button("Clear", func() -> void: mappings.clear(action), "Removes this mapping.")
	row.add_child(clear)
	var warning := PanelBuilder.hint("")
	warning.add_theme_color_override("font_color", Palette.YELLOW)
	col.add_child(warning)
	return {"value": value, "learn": learn, "clear": clear, "warning": warning}


func _refresh_controls() -> void:
	_controller_hint.visible = Settings.midi_in_port == ""
	for action in _control_rows:
		var row: Dictionary = _control_rows[action]
		var key := mappings.key_for(action)
		var bound := mappings.bound_notes(key)
		var listening: bool = mappings.listening == action
		row.value.text = "Listening..." if listening else MidiMappings.label(key)
		row.learn.text = "Cancel" if listening else "Learn"
		row.clear.disabled = key == ""
		row.warning.visible = bound > 0
		row.warning.text = "Also fires %d bound note%s." % [bound, "" if bound == 1 else "s"]


func _key_row(box: VBoxContainer, id: String) -> Dictionary:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	box.add_child(col)
	var row := HBoxContainer.new()
	col.add_child(row)
	var name_l := Label.new()
	name_l.text = surface.tools.get_tool(id).title()
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.clip_text = true
	row.add_child(name_l)
	var value := Label.new()
	value.custom_minimum_size.x = 70
	value.clip_text = true
	value.add_theme_color_override("font_color", Palette.TEXT_DIM)
	row.add_child(value)
	var learn := PanelBuilder.button("Learn", func() -> void:
		if _key_listening == id:
			_cancel_key_learn()
		else:
			mappings.cancel()
			_key_listening = id
			_key_rows[id].warning.visible = false
			_refresh_keys(), "Waits for the next key press. Press again, or Esc, to cancel.")
	row.add_child(learn)
	var clear := PanelBuilder.button("Clear", func() -> void:
		if _key_listening == id:
			_key_listening = ""
		ToolKeys.clear(id)
		_refresh_keys(), "Removes this tool's key.")
	row.add_child(clear)
	var warning := PanelBuilder.hint("")
	warning.add_theme_color_override("font_color", Palette.YELLOW)
	warning.visible = false
	col.add_child(warning)
	return {"value": value, "learn": learn, "clear": clear, "warning": warning}


func _cancel_key_learn() -> void:
	if _key_listening != "":
		_key_listening = ""
		_refresh_keys()


func _refresh_keys() -> void:
	for id in _key_rows:
		var row: Dictionary = _key_rows[id]
		var listening: bool = _key_listening == id
		row.value.text = "Press a key..." if listening else ToolKeys.label(id)
		row.learn.text = "Cancel" if listening else "Learn"
		row.clear.disabled = ToolKeys.key_for(id) == ""


## While a tool row is learning, the next key press is its key, and goes nowhere else.
func _input(event: InputEvent) -> void:
	if _key_listening == "" or not visible:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or ToolKeys.is_modifier_only(key):
		return
	get_viewport().set_input_as_handled()
	var id := _key_listening
	if ToolKeys.keycode_of(key) == KEY_ESCAPE and not ToolKeys.has_modifier(key):
		_cancel_key_learn()
		return
	var why := ToolKeys.refusal(key)
	var row: Dictionary = _key_rows[id]
	row.warning.text = why
	row.warning.visible = why != ""
	if why != "":
		return                      # keeps listening for another key
	var taken_from := ToolKeys.ORDER.filter(func(other: String) -> bool:
		return other != id and OS.find_keycode_from_string(ToolKeys.key_for(other)) == ToolKeys.keycode_of(key) and ToolKeys.key_for(other) != "")
	_key_listening = ""
	ToolKeys.assign(id, ToolKeys.keycode_of(key))
	if not taken_from.is_empty():
		row.warning.text = "Taken from %s, which now has no key." % surface.tools.get_tool(taken_from[0]).title()
		row.warning.visible = true
	_refresh_keys()


## Look tab: the surface shader and its controls (only the chosen look's are shown).
var _look_boxes := {}
var _look_sliders := {}


func _build_look(box: VBoxContainer) -> void:
	PanelBuilder.section(box, "CURSOR", Palette.RED)
	PanelBuilder.slider(box, "Cursor glow", "cursor_glow", 0.0, 2.0, 0.05, func(v: float) -> String:
		return "Off" if v <= 0.0 else "%d%%" % roundi(v * 100))

	PanelBuilder.section(box, "SURFACE", Palette.BLUE)
	PanelBuilder.pick(box, "Look", "look", Settings.LOOKS, Settings.LOOKS)

	var pct := func(v: float) -> String: return "%d%%" % roundi(v * 100.0)
	var abyss := _look_box(box, "Abyssal")
	PanelBuilder.section(abyss, "ABYSSAL", Palette.ACCENT)
	_look_slider(abyss, "Sinking speed", "abyss_sink", 0.0, 4.0, pct)
	_look_slider(abyss, "Marine snow", "abyss_density", 0.0, 3.0, pct)
	_look_slider(abyss, "Glints", "abyss_glints", 0.0, 4.0, pct)
	_look_slider(abyss, "Light shafts", "abyss_shafts", 0.0, 3.0, pct)
	_look_slider(abyss, "Depth", "abyss_depth", 0.25, 3.0, pct)
	_look_slider(abyss, "Refraction", "abyss_refraction", 0.0, 3.0, pct)
	abyss.add_child(PanelBuilder.hint("Depth sets how fast things shrink as they sink: higher feels deeper. Refraction is how much ripples bend the view below."))

	var tidal := _look_box(box, "Tidal")
	PanelBuilder.section(tidal, "TIDAL", Palette.YELLOW)
	_look_slider(tidal, "Sand colour", "tidal_color", 0.0, 3.0, pct)
	_look_slider(tidal, "Caustics", "tidal_caustics", 0.0, 3.0, pct)
	_look_slider(tidal, "Caustics scale", "tidal_caustic_scale", 0.25, 4.0, pct)
	_look_slider(tidal, "Caustics speed", "tidal_caustic_speed", 0.0, 4.0, pct)
	_look_slider(tidal, "Sand scale", "tidal_scale", 0.25, 3.0, pct)
	_look_slider(tidal, "Floor parallax", "tidal_depth", 0.1, 1.0, pct)
	_look_slider(tidal, "Shine", "tidal_shine", 0.0, 3.0, pct)
	_look_slider(tidal, "Ripple relief", "tidal_relief", 0.0, 3.0, pct)
	_look_slider(tidal, "Refraction", "tidal_refraction", 0.0, 3.0, pct)
	tidal.add_child(PanelBuilder.hint("Sand colour at 0% gives black sand. Floor parallax is how far the sand moves when you pan or zoom, relative to the notes: lower feels deeper."))

	var glass := _look_box(box, "Glass")
	glass.add_child(PanelBuilder.hint("Glass has no extra controls."))

	box.add_child(PanelBuilder.button("Reset look controls", func() -> void:
		for key in Settings.LOOK_PARAMS:
			if Settings.LOOK_PARAMS[key][0] == Settings.look:
				Settings.set_value(key, Settings.look_default(key))
				_look_sliders[key].value = Settings.look_default(key), "Returns this look's controls to 100%."))
	_show_look_box()
	Settings.changed.connect(func(key: String) -> void:
		if key == "look":
			_show_look_box())


func _look_box(box: VBoxContainer, look_name: String) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", 8)
	box.add_child(b)
	_look_boxes[look_name] = b
	return b


func _look_slider(box: VBoxContainer, label: String, key: String, min_v: float, max_v: float, fmt: Callable) -> void:
	_look_sliders[key] = PanelBuilder.slider(box, label, key, min_v, max_v, 0.05, fmt)


func _show_look_box() -> void:
	for look_name in _look_boxes:
		_look_boxes[look_name].visible = look_name == Settings.look


## A slot's colour, number and port picker.
func _slot_row(box: VBoxContainer, slot: int) -> OptionButton:
	var row := HBoxContainer.new()
	box.add_child(row)
	var dot := ColorRect.new()
	dot.color = Palette.channel_color(slot)
	dot.custom_minimum_size = Vector2(6, 22)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var number := Label.new()
	number.text = str(slot + 1)
	number.custom_minimum_size.x = 22
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(number)
	var picker := OptionButton.new()
	picker.clip_text = true
	picker.fit_to_longest_item = false
	picker.focus_mode = Control.FOCUS_NONE
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.tooltip_text = "The port this sound sends to, on channel 1."
	picker.item_selected.connect(func(i: int) -> void: Midi.set_slot(slot, picker.get_item_metadata(i)))
	row.add_child(picker)
	return picker


## Rebuilds the pickers from the ports there are now, and opens what's now available.
func refresh_ports() -> void:
	Midi.apply_slots()
	var names := Midi.list_ports()
	for slot in Midi.SLOTS:
		var picker: OptionButton = _slots[slot]
		var port: String = Settings.midi_slots[slot]
		picker.clear()
		picker.add_item("None")
		picker.set_item_metadata(0, "")
		for n in names:
			picker.add_item(n)
			picker.set_item_metadata(-1 + picker.item_count, n)
		if port != "" and not names.has(port):   # keep it, in case it comes back
			picker.add_item(port + " (not found)")
			picker.set_item_metadata(picker.item_count - 1, port)
		var selected := 0
		for i in picker.item_count:
			if picker.get_item_metadata(i) == port:
				selected = i
		picker.select(selected)
		picker.disabled = not Midi.has_native_backend()
	_update_port_status()


func _update_port_status() -> void:
	if not Midi.has_native_backend():
		_port_status.text = "Log-only mode."
		return
	var missing := Midi.missing_ports()
	if not missing.is_empty():
		_port_status.text = "Not found: " + ", ".join(missing)
	elif Midi.is_open():
		_port_status.text = "Sending to " + ", ".join(Midi.open_ports())
	else:
		_port_status.text = "Pick a port for each sound you use (e.g. your loopMIDI ports)."


# --- Builders -----------------------------------------------------------------------

## A tab page: a scrolling column of controls.
func _tab(name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 4)
	scroll.add_child(pad)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	pad.add_child(box)
	return box
