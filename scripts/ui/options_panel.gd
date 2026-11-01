class_name OptionsPanel
extends PanelContainer
## Slide-in options in two tabs. General: MIDI output, timing, wave, scale, notes, controls.
## Snap: snapping and guide settings.

signal clear_notes_requested
signal reset_layout_requested

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
	head.add_child(_button("Close", hide))

	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.focus_mode = Control.FOCUS_NONE
	outer.add_child(tabs)
	var box := _tab("General")
	_build_snap(_tab("Snap"))
	_build_channels(_tab("Channels"))
	_build_look(_tab("Look"))

	_section(box, "MIDI OUTPUT", Palette.BLUE)
	_ports = OptionButton.new()
	_ports.clip_text = true
	_ports.fit_to_longest_item = false
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
	port_row.add_child(_button("Refresh", refresh_ports))
	port_row.add_child(_button("Panic", Midi.panic))

	_section(box, "TIMING", Palette.ACCENT)
	_slider(box, "Tempo", "bpm", 40.0, 240.0, 1.0, func(v: float) -> String: return "%d BPM" % v)
	_slider(box, "Beat spacing (zoom)", "beat_spacing", 60.0, 600.0, 5.0, func(v: float) -> String:
		return "%d px · %d%%" % [v, roundi(v / Settings.BEAT_UNIT * 100.0)])
	var div_row := HBoxContainer.new()
	box.add_child(div_row)
	var div_label := Label.new()
	div_label.text = "Divisions per beat"
	div_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	div_row.add_child(div_label)
	var div_pick := OptionButton.new()
	div_pick.focus_mode = Control.FOCUS_NONE
	for d in Settings.DIVISION_OPTIONS:
		div_pick.add_item(str(d))
	div_pick.select(maxi(0, Settings.DIVISION_OPTIONS.find(Settings.divisions)))
	div_pick.item_selected.connect(func(i: int) -> void: Settings.set_value("divisions", Settings.DIVISION_OPTIONS[i]))
	div_row.add_child(div_pick)
	box.add_child(_hint("Beat spacing zooms the canvas: distances scale, icons stay the same size, and timing doesn't change. Waves cross one beat of space per beat, so the layout stays in time at any tempo."))

	_section(box, "WAVE", Palette.RED)
	_slider(box, "Strength", "wave_strength", 0.1, 1.0, 0.01, func(v: float) -> String: return "%d%%" % roundi(v * 100))
	_slider(box, "Reach", "wave_range", 150.0, 2500.0, 10.0, func(v: float) -> String:
		return "%.1f beats" % (v / Settings.BEAT_UNIT))
	_slider(box, "Falloff curve", "falloff_curve", 0.4, 4.0, 0.05, func(v: float) -> String:
		return "%.2f %s" % [v, "(linear)" if absf(v - 1.0) < 0.03 else ""])
	_slider(box, "Note length", "note_length", 0.05, 2.0, 0.01, func(v: float) -> String: return "%.2f s" % v)

	_section(box, "SCALE", Palette.YELLOW)
	var scale_row := HBoxContainer.new()
	box.add_child(scale_row)
	var root := OptionButton.new()
	for n in Scales.ROOT_NAMES:
		root.add_item(n)
	root.select(Settings.root_note)
	root.item_selected.connect(func(i: int) -> void: Settings.set_value("root_note", i))
	scale_row.add_child(root)
	var scale := OptionButton.new()
	scale.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var names := Scales.names()
	for n in names:
		scale.add_item(n)
	scale.select(maxi(0, names.find(Settings.scale_name)))
	scale.item_selected.connect(func(i: int) -> void: Settings.set_value("scale_name", names[i]))
	scale_row.add_child(scale)
	box.add_child(_hint("Changing the scale snaps every note to it."))

	_section(box, "NOTES", Palette.TEXT_DIM)
	var notes_row := HBoxContainer.new()
	box.add_child(notes_row)
	notes_row.add_child(_button("Clear all", func() -> void: clear_notes_requested.emit()))
	notes_row.add_child(_button("Default layout", func() -> void: reset_layout_requested.emit()))

	_section(box, "CONTROLS", Palette.TEXT_DIM)
	box.add_child(_hint(
		"Click: send a wave (click a pulser to trigger it without a wave)\n" +
		"Drag a note: move it\n" +
		"Hold right-click, hover a pitch, release: place a note (on a note: retune it). A tap keeps the menu open.\n" +
		"   While the menu is open: A / D or wheel = octave, type 1-16 = channel, Esc = cancel\n" +
		"Alt-click: set MIDI channel\n" +
		"Ctrl-click: Note → Note + Pulse → Pulse only · Ctrl-drag from a pulser: set its own wave reach (back onto the note resets it)\n" +
		"Ctrl-right-click: pulse cooldown (in beats, or Retrigger: every wave) and strength\n" +
		"Drag the diamond on a pulser: place where its wave starts\n" +
		"Shift-click: place a note with the last pitch\n" +
		"Delete: remove the hovered note or the selection\n" +
		"M: mute / unmute the selected notes (or the hovered one); pulsers keep pulsing\n" +
		"Middle-drag or arrow keys: pan · Home: centre on the notes\n" +
		"While dragging: touch another note or emitter to snap to its rings and spokes (touch again to drop it) · Shift places freely · see the Snap tab\n" +
		"Shift-right-click: modifier (Toggle: plays every other hit; set its start state)\n" +
		"Ctrl+S: save state · Space or KP0: stop and return to the save state\n" +
		"Ctrl+Z: undo · Ctrl+Shift+Z or Ctrl+Y: redo\n" +
		"KP1-9: trigger that key's notes (hold: pulsers refire on their cooldown) · Ctrl+KP1-9 over a note: assign / unassign\n" +
		"Ctrl + right-drag on empty space: box select (Shift adds) · Esc clears\n" +
		"   Selected: drag one to move all · Delete removes · menu edits apply to all · Ctrl+C / Ctrl+V copy and paste\n" +
		"Tab: options"))


## Channels tab: per-channel settings. Note length: "Default" follows the global Note length.
func _build_channels(box: VBoxContainer) -> void:
	_section(box, "NOTE LENGTH", Palette.RED)
	box.add_child(_hint("How long notes on each channel are held. Default follows Note length on the General tab."))
	for ch in 16:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		var dot := ColorRect.new()
		dot.color = Palette.channel_color(ch)
		dot.custom_minimum_size = Vector2(10, 10)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)
		var name_l := Label.new()
		name_l.text = "Ch %d" % (ch + 1)
		name_l.custom_minimum_size.x = 44
		row.add_child(name_l)
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 4.0
		s.step = 0.01
		s.value = float(Settings.channel_lengths[ch])
		s.focus_mode = Control.FOCUS_NONE
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(s)
		var val_l := Label.new()
		val_l.custom_minimum_size.x = 64
		val_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val_l.add_theme_color_override("font_color", Palette.TEXT_DIM)
		row.add_child(val_l)
		var show := func(v: float) -> void:
			val_l.text = "Default" if v <= 0.0 else "%.2f s" % v
		show.call(s.value)
		s.value_changed.connect(func(v: float) -> void:
			show.call(v)
			Settings.set_channel_length(ch, v))
	box.add_child(_button("Reset all to Default", func() -> void:
		for ch in 16:
			Settings.set_channel_length(ch, 0.0)
		for child in box.get_children():
			if child is HBoxContainer:
				for c in child.get_children():
					if c is HSlider:
						c.value = 0.0))


## Look tab: the surface shader and its controls (only the chosen look's are shown).
var _look_boxes := {}
var _look_sliders := {}


func _build_look(box: VBoxContainer) -> void:
	_section(box, "SURFACE", Palette.BLUE)
	_pick(box, "Look", "look", Settings.LOOKS, Settings.LOOKS)

	var pct := func(v: float) -> String: return "%d%%" % roundi(v * 100.0)
	var abyss := _look_box(box, "Abyssal")
	_section(abyss, "ABYSSAL", Palette.ACCENT)
	_look_slider(abyss, "Sinking speed", "abyss_sink", 0.0, 4.0, pct)
	_look_slider(abyss, "Marine snow", "abyss_density", 0.0, 3.0, pct)
	_look_slider(abyss, "Glints", "abyss_glints", 0.0, 4.0, pct)
	_look_slider(abyss, "Light shafts", "abyss_shafts", 0.0, 3.0, pct)
	_look_slider(abyss, "Depth", "abyss_depth", 0.25, 3.0, pct)
	_look_slider(abyss, "Refraction", "abyss_refraction", 0.0, 3.0, pct)
	abyss.add_child(_hint("Depth sets how fast things shrink as they sink: higher feels deeper. Refraction is how much ripples bend the view below."))

	var tidal := _look_box(box, "Tidal")
	_section(tidal, "TIDAL", Palette.YELLOW)
	_look_slider(tidal, "Sand colour", "tidal_color", 0.0, 3.0, pct)
	_look_slider(tidal, "Caustics", "tidal_caustics", 0.0, 3.0, pct)
	_look_slider(tidal, "Caustics scale", "tidal_caustic_scale", 0.25, 4.0, pct)
	_look_slider(tidal, "Caustics speed", "tidal_caustic_speed", 0.0, 4.0, pct)
	_look_slider(tidal, "Sand scale", "tidal_scale", 0.25, 3.0, pct)
	_look_slider(tidal, "Floor parallax", "tidal_depth", 0.1, 1.0, pct)
	_look_slider(tidal, "Shine", "tidal_shine", 0.0, 3.0, pct)
	_look_slider(tidal, "Ripple relief", "tidal_relief", 0.0, 3.0, pct)
	_look_slider(tidal, "Refraction", "tidal_refraction", 0.0, 3.0, pct)
	tidal.add_child(_hint("Sand colour at 0% gives black sand. Floor parallax is how far the sand moves when you pan or zoom, relative to the notes: lower feels deeper."))

	var glass := _look_box(box, "Glass")
	glass.add_child(_hint("Glass has no extra controls."))

	box.add_child(_button("Reset look controls", func() -> void:
		for key in Settings.LOOK_PARAMS:
			if Settings.LOOK_PARAMS[key][0] == Settings.look:
				Settings.set_value(key, Settings.look_default(key))
				_look_sliders[key].value = Settings.look_default(key)))
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
	_look_sliders[key] = _slider(box, label, key, min_v, max_v, 0.05, fmt)


func _show_look_box() -> void:
	for look_name in _look_boxes:
		_look_boxes[look_name].visible = look_name == Settings.look


## Snap tab: snapping and guide settings (used while dragging a note or emitter).
func _build_snap(box: VBoxContainer) -> void:
	_section(box, "SNAPPING", Palette.ACCENT)
	_check(box, "Snap to touched targets", "snap_enabled")
	_slider(box, "Snap distance", "snap_distance", 4.0, 30.0, 1.0, func(v: float) -> String: return "%d px" % v)
	_check(box, "Snap to spokes", "snap_spokes")
	_check(box, "Snap to centres", "snap_centres")
	_check(box, "Remember snap target on drop", "snap_memory")
	box.add_child(_hint("While dragging, touch a note or emitter to snap to its rings and spokes; touch it again to drop it. Drag onto any note or emitter to snap to its centre. Hold Shift to place freely."))

	_section(box, "GUIDES", Palette.YELLOW)
	_pick(box, "Spokes per target", "spoke_count", Settings.SPOKE_OPTIONS,
			Settings.SPOKE_OPTIONS.map(func(c: int) -> String: return "None" if c == 0 else str(c)))
	_pick(box, "Guides extend to", "guides_to_edge", [true, false], ["Window edge", "Wave reach"])
	_check(box, "Division rings", "guide_divisions")
	_slider(box, "Guide brightness", "guide_brightness", 0.3, 1.5, 0.05, func(v: float) -> String: return "%d%%" % roundi(v * 100))


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


func _check(box: VBoxContainer, label: String, key: String) -> CheckButton:
	var c := CheckButton.new()
	c.text = label
	c.focus_mode = Control.FOCUS_NONE
	c.button_pressed = bool(Settings.get(key))
	c.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
	box.add_child(c)
	return c


func _pick(box: VBoxContainer, label: String, key: String, values: Array, labels: Array) -> OptionButton:
	var row := HBoxContainer.new()
	box.add_child(row)
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	for t in labels:
		o.add_item(str(t))
	o.select(maxi(0, values.find(Settings.get(key))))
	o.item_selected.connect(func(i: int) -> void: Settings.set_value(key, values[i]))
	row.add_child(o)
	return o

func _section(box: VBoxContainer, text: String, col: Color) -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	box.add_child(gap)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var dot := ColorRect.new()
	dot.color = col
	dot.custom_minimum_size = Vector2(3, 14)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Palette.TEXT_DIM)
	row.add_child(l)


func _slider(box: VBoxContainer, label: String, key: String, min_v: float, max_v: float,
		step: float, fmt: Callable) -> HSlider:
	var row := HBoxContainer.new()
	box.add_child(row)
	var name_l := Label.new()
	name_l.text = label
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_l)
	var val_l := Label.new()
	val_l.add_theme_color_override("font_color", Palette.TEXT_DIM)
	row.add_child(val_l)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = Settings.get(key)
	s.focus_mode = Control.FOCUS_NONE
	val_l.text = fmt.call(s.value)
	s.value_changed.connect(func(v: float) -> void:
		val_l.text = fmt.call(v)
		Settings.set_value(key, v))
	box.add_child(s)
	return s


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	return b


func _hint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Palette.TEXT_DIM)
	l.add_theme_font_size_override("font_size", 12)
	return l
