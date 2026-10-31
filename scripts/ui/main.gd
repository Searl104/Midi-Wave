extends Control
## Root of MIDI Wave: builds the water, surface, HUD, radial menu and options,
## and wires the radial menus to note editing.

var water: ColorRect
var surface: WaveSurface
var radial: RadialMenu
var options: OptionsPanel
var status_label: Label
var hint_label: Label

var _menu_note := -1          # note being edited, -1 = placing a new one
var _menu_pos := Vector2.ZERO
var _menu_octave := 4


func _ready() -> void:
	theme = GlassTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	water = ColorRect.new()
	water.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	water.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var water_mat := ShaderMaterial.new()
	water_mat.shader = load("res://shaders/water.gdshader")
	water_mat.set_shader_parameter("accent", Palette.ACCENT)
	water.material = water_mat
	add_child(water)

	surface = WaveSurface.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(surface)
	surface.pitch_menu_requested.connect(_open_pitch_menu)
	surface.channel_menu_requested.connect(_open_channel_menu)

	_build_hud()

	options = OptionsPanel.new()
	add_child(options)
	options.clear_notes_requested.connect(surface.clear_notes)
	options.reset_layout_requested.connect(func() -> void:
		surface.clear_notes()
		surface.seed_default_layout())

	radial = RadialMenu.new()
	var glass_mat := ShaderMaterial.new()
	glass_mat.shader = load("res://shaders/glass.gdshader")
	glass_mat.set_shader_parameter("opacity", 0.85)
	radial.material = glass_mat
	add_child(radial)
	radial.outer_chosen.connect(_on_radial_outer)
	radial.inner_chosen.connect(_on_radial_inner)
	radial.center_chosen.connect(_on_radial_center)
	radial.wheel.connect(func(dir: int) -> void: _set_menu_octave(_menu_octave + dir))

	Midi.port_changed.connect(func(_n: String) -> void: _update_status())
	_reopen_last_port()
	_update_status()


func _process(_delta: float) -> void:
	var mat := water.material as ShaderMaterial
	mat.set_shader_parameter("surface_size", water.size)
	mat.set_shader_parameter("wave_count", mini(surface.waves.size(), WaveSurface.MAX_WAVES))
	mat.set_shader_parameter("waves", surface.shader_waves())


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not key or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_TAB, KEY_O:
			options.toggle()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if options.visible:
				options.hide()
				get_viewport().set_input_as_handled()


func _reopen_last_port() -> void:
	if Settings.midi_port == "" or not Midi.has_native_backend():
		return
	var idx := Midi.list_ports().find(Settings.midi_port)
	if idx != -1:
		Midi.open_port(idx)


# --- HUD -------------------------------------------------------------------------------

func _build_hud() -> void:
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 20
	top.offset_right = -20
	top.offset_top = 16
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)

	var title := Label.new()
	title.text = "MIDI  WAVE"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Palette.TEXT)
	top.add_child(title)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(status_label)

	var gear := Button.new()
	gear.text = "Options"
	gear.focus_mode = Control.FOCUS_NONE
	gear.pressed.connect(func() -> void: options.toggle())
	top.add_child(gear)

	hint_label = Label.new()
	hint_label.text = "Click to send a wave  ·  Right-click to place / tune a note  ·  Alt-click for channel  ·  Tab for options"
	hint_label.add_theme_font_size_override("font_size", 12)
	hint_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint_label.offset_top = -34
	hint_label.offset_bottom = -14
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint_label)
	var tw := create_tween()
	tw.tween_interval(8.0)
	tw.tween_property(hint_label, "modulate:a", 0.35, 2.0)


func _update_status() -> void:
	var text := "    "
	if Midi.is_open():
		text += "→ " + Midi.current_port_name()
	elif Midi.has_native_backend():
		text += "no MIDI output · open Options to pick a port"
	else:
		text += "log-only mode (MIDI extension not loaded)"
	status_label.text = text


# --- Radial menus ---------------------------------------------------------------------

func _open_pitch_menu(note_id: int, at: Vector2) -> void:
	_menu_note = note_id
	_menu_pos = at
	var current := surface.last_pitch
	if note_id != -1:
		current = surface.get_note(note_id).note
	_menu_octave = clampi(Scales.octave_of(current, Settings.root_note), 1, 7)
	radial.set_meta("mode", "pitch")
	radial.center_item = {"id": "delete", "label": "Del", "color": Palette.RED} if note_id != -1 else {}
	_rebuild_pitch_items(current)
	radial.open(at)


func _rebuild_pitch_items(current: int = -1) -> void:
	if current == -1 and _menu_note != -1:
		current = surface.get_note(_menu_note).get("note", -1)
	var col := Palette.channel_color(surface.get_note(_menu_note).get("channel", surface.last_channel))
	radial.outer_items = []
	for n in Scales.octave_notes(_menu_octave, Settings.root_note, Settings.scale_name):
		radial.outer_items.append({"id": n, "label": MidiMessage.note_name(n), "color": col, "selected": n == current})
	radial.inner_items = []
	for o in range(1, 8):
		radial.inner_items.append({"id": o, "label": str(o), "color": Palette.YELLOW, "selected": o == _menu_octave})
	radial.title = "%s %s · octave %d" % [Scales.ROOT_NAMES[Settings.root_note], Settings.scale_name, _menu_octave]
	radial.refresh()


func _set_menu_octave(o: int) -> void:
	if radial.get_meta("mode", "") != "pitch":
		return
	_menu_octave = clampi(o, 1, 7)
	_rebuild_pitch_items()


func _open_channel_menu(note_id: int, at: Vector2) -> void:
	_menu_note = note_id
	var current: int = surface.get_note(note_id).get("channel", 0)
	radial.set_meta("mode", "channel")
	radial.inner_items = []
	radial.center_item = {}
	radial.outer_items = []
	for ch in 16:
		radial.outer_items.append({"id": ch, "label": str(ch + 1), "color": Palette.channel_color(ch), "selected": ch == current})
	radial.title = "MIDI channel"
	radial.open(at)


func _on_radial_outer(id: Variant) -> void:
	var mode: String = radial.get_meta("mode", "")
	if mode == "pitch":
		var pitch: int = id
		var ch := surface.last_channel
		if _menu_note == -1:
			surface.add_note_at(_menu_pos, pitch, ch)
		else:
			surface.set_note_pitch(_menu_note, pitch)
			ch = surface.get_note(_menu_note).channel
		Midi.play_note(pitch, 90, 0.25, ch)
	elif mode == "channel":
		var ch: int = id
		surface.set_note_channel(_menu_note, ch)
		var n := surface.get_note(_menu_note)
		if not n.is_empty():
			Midi.play_note(n.note, 90, 0.25, ch)


func _on_radial_inner(id: Variant) -> void:
	_set_menu_octave(id)


func _on_radial_center(id: Variant) -> void:
	if id == "delete" and _menu_note != -1:
		surface.remove_note(_menu_note)
