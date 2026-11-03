class_name OptionsPanel
extends PanelContainer
## Slide-in options for the whole app, in two tabs: General and Look. Settings that belong to a
## tool are in its tool panel instead.

signal clear_notes_requested
signal reset_layout_requested
signal test_layout_requested
signal song_layout_requested

const WIDTH := 330.0

var _ports: OptionButton
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
	Midi.port_changed.connect(func(_n: String) -> void: _update_port_status())


func toggle() -> void:
	if visible:
		hide()
	else:
		refresh_ports()
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
	outer.add_child(tabs)
	var box := _tab("General")
	_build_look(_tab("Look"))

	PanelBuilder.section(box, "MIDI OUTPUT", Palette.BLUE)
	_ports = OptionButton.new()
	_ports.clip_text = true
	_ports.fit_to_longest_item = false
	_ports.tooltip_text = "The port MIDI Wave sends notes to, such as your loopMIDI port."
	_ports.item_selected.connect(_on_port_selected)
	box.add_child(_ports)
	var port_row := HBoxContainer.new()
	box.add_child(port_row)
	_port_status = Label.new()
	_port_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_port_status.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_port_status.add_theme_font_size_override("font_size", 12)
	_port_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	port_row.add_child(_port_status)
	port_row.add_child(PanelBuilder.button("Refresh", refresh_ports, "Looks for MIDI output ports."))
	port_row.add_child(PanelBuilder.button("Panic", Midi.panic, "Stops every sounding note on all channels."))
	PanelBuilder.check(box, "Play notes while hovering the pitch ring", "hover_preview")

	PanelBuilder.section(box, "MIDI INPUT", Palette.BLUE)
	box.add_child(MidiInputControls.new())

	PanelBuilder.section(box, "TIMING", Palette.ACCENT)
	PanelBuilder.slider(box, "Tempo", "bpm", 40.0, 240.0, 1.0, func(v: float) -> String: return "%d BPM" % v)
	PanelBuilder.pick(box, "Divisions per beat", "divisions", Settings.DIVISION_OPTIONS,
			Settings.DIVISION_OPTIONS.map(func(d: int) -> String: return str(d)))
	box.add_child(PanelBuilder.hint("Waves cross one beat of space per beat, so the layout stays in time at any tempo."))

	PanelBuilder.section(box, "DISPLAY", Palette.YELLOW)
	PanelBuilder.check(box, "Colour-blind palette", "colorblind")
	box.add_child(PanelBuilder.hint("Eight colour-blind safe channel colours; channels 9-16 reuse them with a double outline. Hover a note for its channel number."))

	PanelBuilder.section(box, "NOTES", Palette.TEXT_DIM)
	var notes_row := HBoxContainer.new()
	box.add_child(notes_row)
	notes_row.add_child(PanelBuilder.button("Clear all", func() -> void: clear_notes_requested.emit(), "Removes every note from the surface."))
	notes_row.add_child(PanelBuilder.button("Default layout", func() -> void: reset_layout_requested.emit(), "Replaces the notes with the starting ring of notes."))
	notes_row.add_child(PanelBuilder.button("Test layout", func() -> void: test_layout_requested.emit(), "Replaces the notes with a self-playing demo of each feature."))
	box.add_child(PanelBuilder.button("Three Blind Mice", func() -> void: song_layout_requested.emit(), "Replaces the notes with the song in four parts, played on KP1-4."))
	box.add_child(PanelBuilder.hint("Test layout replaces the notes with one group per feature and starts playing. Stop ends it."))


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


func refresh_ports() -> void:
	_ports.clear()
	if not Midi.has_native_backend():
		_ports.add_item("MIDI extension not loaded")
		_ports.disabled = true
	else:
		var names := Midi.list_ports()
		if names.is_empty():
			_ports.add_item("No MIDI outputs found")
			_ports.disabled = true
		else:
			_ports.disabled = false
			for n in names:
				_ports.add_item(n)
			_ports.select(names.find(Settings.midi_port) if Midi.is_open() else -1)
	_update_port_status()


func _on_port_selected(index: int) -> void:
	if Midi.open_port(index):
		Settings.set_value("midi_port", Midi.current_port_name())


func _update_port_status() -> void:
	if Midi.is_open():
		_port_status.text = "Sending to " + Midi.current_port_name()
	elif Midi.has_native_backend():
		_port_status.text = "No port open. Pick one above (e.g. your loopMIDI port)."
	else:
		_port_status.text = "Log-only mode."


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
