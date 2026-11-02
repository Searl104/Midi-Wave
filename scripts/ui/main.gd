extends Control
## Root of MIDI Wave: builds the water, surface, HUD, radial menu and options.

var water: ColorRect
var caustic_time := 0.0          ## Tidal caustic clock, advanced at the Caustics speed setting
var surface: WaveSurface
var radial: RadialMenu
var options: OptionsPanel
var status_label: Label
var hint_label: Label
var toolbar: Toolbar
var tool_panel: ToolPanel
var midi_in: MidiInput


func _ready() -> void:
	theme = GlassTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	water = ColorRect.new()
	water.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	water.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var water_mat := ShaderMaterial.new()
	water_mat.set_shader_parameter("accent", Palette.ACCENT)
	water.material = water_mat
	_apply_look()
	add_child(water)
	Settings.changed.connect(func(key: String) -> void:
		if key == "look":
			_apply_look()
		elif Settings.LOOK_PARAMS.has(key):
			_apply_look_params())

	surface = WaveSurface.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(surface)
	surface.tools.mode_changed.connect(_on_mode_changed)
	surface.tools.tool_changed.connect(_on_tool_changed)
	surface.tools.notice.connect(_toast)

	_build_hud()

	toolbar = Toolbar.new()
	toolbar.surface = surface
	add_child(toolbar)
	tool_panel = ToolPanel.new()
	tool_panel.toolbar = toolbar
	toolbar.panel = tool_panel
	add_child(tool_panel)
	surface.tools.set_ring_option(Settings.ring_option)
	surface.tools.set_tool("tap" if Settings.tool == "wave" else Settings.tool)   # "wave" is the old name

	options = OptionsPanel.new()
	add_child(options)
	options.clear_notes_requested.connect(surface.clear_notes)
	options.reset_layout_requested.connect(func() -> void:
		surface.clear_notes()
		surface.seed_default_layout())
	options.test_layout_requested.connect(func() -> void:
		var demo := DemoLayout.new()
		surface.load_layout(demo.layout)
		for id in demo.starters:
			surface.trigger_note(id))

	radial = RadialMenu.new()
	var glass_mat := ShaderMaterial.new()
	glass_mat.shader = load("res://shaders/glass.gdshader")
	glass_mat.set_shader_parameter("opacity", 0.85)
	radial.material = glass_mat
	add_child(radial)
	surface.tools.attach_radial(radial)

	midi_in = MidiInput.new()
	add_child(midi_in)
	midi_in.note_pressed.connect(func(pitch: int) -> void: surface.tools.binding_pressed("midi%d" % pitch))
	midi_in.note_released.connect(func(pitch: int) -> void: surface.tools.binding_released("midi%d" % pitch))

	Midi.port_changed.connect(func(_n: String) -> void: _update_status())
	_reopen_last_port()
	_update_status()


func _process(delta: float) -> void:
	var mat := water.material as ShaderMaterial
	mat.set_shader_parameter("surface_size", water.size)
	mat.set_shader_parameter("wave_count", mini(surface.waves.size(), WaveSurface.MAX_WAVES))
	mat.set_shader_parameter("waves", surface.shader_waves())
	# The backgrounds follow panning only: Beat spacing (the zoom) doesn't scale or shift them.
	# Pan = the world point at the window centre, which zooming about the centre leaves alone.
	mat.set_shader_parameter("view_px", surface.view_offset + water.size * (0.5 / surface.z() - 0.5))
	if Settings.look == "Tidal":
		caustic_time = fmod(caustic_time + delta * Settings.look_uniform_value("tidal_caustic_speed"), 10000.0)
		mat.set_shader_parameter("caustic_time", caustic_time)


## Surface shader for the chosen look: Abyssal (endless depth), Tidal (black glossy sand
## below the water) or Glass (flat dark glass).
func _apply_look() -> void:
	var mat := water.material as ShaderMaterial
	match Settings.look:
		"Glass":
			mat.shader = load("res://shaders/water.gdshader")
		"Tidal":
			mat.shader = load("res://shaders/tidal.gdshader")
			mat.set_shader_parameter("sand_normal", load("res://assets/tidal/sand_normal.jpg"))
			mat.set_shader_parameter("sand_rough", load("res://assets/tidal/sand_rough.jpg"))
			mat.set_shader_parameter("sand_color", load("res://assets/tidal/sand_color.jpg"))
		_:
			mat.shader = load("res://shaders/abyssal.gdshader")
	_apply_look_params()


## Pushes the Options > Look controls into the surface shader.
func _apply_look_params() -> void:
	var mat := water.material as ShaderMaterial
	for key in Settings.LOOK_PARAMS:
		if Settings.LOOK_PARAMS[key][0] == Settings.look:
			mat.set_shader_parameter(Settings.LOOK_PARAMS[key][1], Settings.look_uniform_value(key))


func _on_mode_changed(editing: bool) -> void:
	surface.tools.close_ring()
	_toast(surface.tools.current.title() if editing else "Tap  ·  layout locked")


func _on_tool_changed(_t: String) -> void:
	surface.tools.close_ring()
	if toolbar:
		toolbar.queue_redraw()
	if not surface.tools.springing():
		Settings.set_value("tool", surface.tools.current_id())
	Settings.set_value("ring_option", surface.tools.ring_option.tool_id())


## The Save state button: toggles' current states become their start states.
func _save_state() -> void:
	surface.save_state()
	_toast("Start states saved")


var _toast_label: Label
var _toast_tween: Tween


## A short message above the hint bar that fades out on its own.
func _toast(text: String) -> void:
	if _toast_label == null:
		_toast_label = Label.new()
		_toast_label.add_theme_font_size_override("font_size", 13)
		_toast_label.add_theme_color_override("font_color", Palette.TEXT)
		_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		_toast_label.offset_top = -66
		_toast_label.offset_bottom = -42
		_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_toast_label.modulate.a = 0.0
		add_child(_toast_label)
	_toast_label.text = text
	_toast_label.modulate.a = 1.0
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.2)
	_toast_tween.tween_property(_toast_label, "modulate:a", 0.0, 0.5)


func _notification(what: int) -> void:
	# A button released while the window is unfocused never arrives.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and surface:
		surface.tools.end_spring()
		surface.release_all_bindings()


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
	top.add_theme_constant_override("separation", 8)
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

	var save := Button.new()
	save.text = "Save state"
	save.tooltip_text = "Make every toggle's current state its start state (Ctrl+S)"
	save.focus_mode = Control.FOCUS_NONE
	save.pressed.connect(_save_state)
	top.add_child(save)

	var stop := Button.new()
	stop.text = "Stop"
	stop.tooltip_text = "Clear every wave and return to the save state (Space, KP Enter)"
	stop.focus_mode = Control.FOCUS_NONE
	stop.pressed.connect(func() -> void: surface.stop())
	top.add_child(stop)

	var gear := Button.new()
	gear.text = "Options"
	gear.focus_mode = Control.FOCUS_NONE
	gear.pressed.connect(func() -> void: options.toggle())
	top.add_child(gear)

	hint_label = Label.new()
	hint_label.add_theme_font_size_override("font_size", 12)
	hint_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint_label.offset_top = -34
	hint_label.offset_bottom = -14
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint_label)
	hint_label.modulate.a = 0.85


func _update_status() -> void:
	var text := "    "
	if Midi.is_open():
		text += "→ " + Midi.current_port_name()
	elif Midi.has_native_backend():
		text += "no MIDI output · open Options to pick a port"
	else:
		text += "log-only mode (MIDI extension not loaded)"
	status_label.text = text
