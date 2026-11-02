extends Control
## Root of MIDI Wave: builds the water, surface, HUD, radial menu and options,
## and wires the radial menus to note editing.

const DIGIT_WINDOW_MS := 600   ## time allowed for the second digit of a channel number
const PAN_SPEED := 700.0       ## px per second for arrow-key panning

## Beats; 0 = Retrigger (no timer: fires on every wave that reaches it).
const COOLDOWNS := [0.0, 0.125, 1.0 / 6.0, 0.25, 1.0 / 3.0, 0.5, 2.0 / 3.0, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0]
const COOLDOWN_LABELS := ["Retrig", "⅛", "⅙", "¼", "⅓", "½", "⅔", "¾", "1", "1½", "2", "3", "4"]
const PULSE_STRENGTHS := [0.25, 0.5, 0.75, 1.0]
const MODE_LABELS := ["Note", "", "Relay"]   ## by Mode value (1 was the old hybrid)

var water: ColorRect
var caustic_time := 0.0          ## Tidal caustic clock, advanced at the Caustics speed setting
var surface: WaveSurface
var radial: RadialMenu
var options: OptionsPanel
var status_label: Label
var hint_label: Label
var toolbar: Toolbar
var midi_in: MidiInput

var _menu_note := -1          # note being edited, -1 = placing a new one
var _menu_pos := Vector2.ZERO
var _menu_octave := 4
var _menu_channel := 0
var _menu_pitch := -1         # pitch the menu opened with (the note's current pitch)
var _digit_first := -1        # first digit of a possible 10-16, or -1
var _digit_time := 0


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
	surface.mode_changed.connect(_on_mode_changed)
	surface.tool_changed.connect(_on_tool_changed)

	_build_hud()

	toolbar = Toolbar.new()
	toolbar.surface = surface
	add_child(toolbar)
	surface.draw_type = WaveSurface.Mode.RELAY if int(Settings.draw_type) == WaveSurface.Mode.RELAY else WaveSurface.Mode.NOTE
	surface.set_tool(Settings.tool if WaveSurface.TOOLS.has(Settings.tool) else "select")

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
	radial.hover_changed.connect(_on_radial_hover)

	midi_in = MidiInput.new()
	add_child(midi_in)
	midi_in.slot_pressed.connect(surface.press_slot)
	midi_in.slot_released.connect(surface.release_slot)
	midi_in.learned.connect(func(base: int) -> void:
		_toast("Pads: key 1 = %s, keys 2-9 follow" % MidiMessage.note_name(base)))
	options.midi_learn_requested.connect(func() -> void:
		midi_in.learning = true
		_toast("Hit the pad for keypad key 1"))

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


func _on_mode_changed(edit: bool) -> void:
	if radial and radial.visible:
		radial.close()
	_toast(TOOL_NAMES[surface.tool] if edit else "Wave  ·  layout locked")


# --- Toolbar tools ---------------------------------------------------------------------------
# Picking Draw again switches what it places (Note or Relay).

const TOOL_NAMES := {"wave": "Wave", "select": "Select", "draw": "Draw", "pitch": "Pitch",
		"channel": "Channel", "pulse": "Pulse", "modifier": "Modifier"}


func pick_tool(t_name: String) -> void:
	if t_name == "draw" and surface.tool == "draw":
		surface.toggle_draw_type()
		_toast("Draw: %s" % ("Relays" if surface.draw_type == WaveSurface.Mode.RELAY else "Notes"))
		return
	surface.set_tool(t_name)


func _on_tool_changed(_t: String) -> void:
	if radial and radial.visible:
		radial.close()
	if toolbar:
		toolbar.queue_redraw()
	Settings.set_value("tool", surface.tool)
	Settings.set_value("draw_type", surface.draw_type)


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
	save.tooltip_text = "Make every toggle's current state its start state"
	save.focus_mode = Control.FOCUS_NONE
	save.pressed.connect(_save_state)
	top.add_child(save)

	var stop := Button.new()
	stop.text = "Stop"
	stop.tooltip_text = "Clear every wave and return to the save state"
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


# --- Pitch menu (quick place) -------------------------------------------------------------

## Opened on the right-button press: hold, hover a pitch, release. A tap keeps it open.
func _open_pitch_menu(note_id: int, at: Vector2) -> void:
	_menu_note = note_id
	_menu_pos = at
	_digit_first = -1
	_previewed_pitch = -1
	var current := surface.last_pitch
	_menu_channel = surface.last_channel
	_menu_pitch = -1
	if note_id != -1:
		var n := surface.get_note(note_id)
		current = n.note
		_menu_channel = n.channel
		_menu_pitch = n.note
	_menu_octave = clampi(Scales.octave_of(current, Settings.root_note), 1, 7)
	radial.set_meta("mode", "pitch")
	radial.center_item = {"id": "delete", "label": "Del", "color": Palette.RED} if note_id != -1 else {}
	_rebuild_pitch_items()
	radial.open(at)


func _rebuild_pitch_items() -> void:
	var col := Palette.channel_color(_menu_channel)
	radial.outer_items = []
	for n in Scales.octave_notes(_menu_octave, Settings.root_note, Settings.scale_name):
		radial.outer_items.append({"id": n, "label": MidiMessage.note_name(n), "color": col, "selected": n == _menu_pitch})
	radial.inner_items = []
	for o in range(1, 8):
		radial.inner_items.append({"id": o, "label": str(o), "color": Palette.YELLOW, "selected": o == _menu_octave})
	var ch_text := "ch %d" % (_menu_channel + 1)
	if _digit_first != -1 and Time.get_ticks_msec() - _digit_time <= DIGIT_WINDOW_MS:
		ch_text += "…"                  # waiting for a second digit (10-16)
	radial.title = "%s %s · octave %d · %s" % [
		Scales.ROOT_NAMES[Settings.root_note], Settings.scale_name, _menu_octave, ch_text]
	radial.subtitle = ""
	radial.refresh()


func _set_menu_octave(o: int) -> void:
	if radial.get_meta("mode", "") != "pitch":
		return
	var old := _menu_octave
	_menu_octave = clampi(o, 1, 7)
	# The note keeps its letter (A, C#, ...) and moves to the new octave.
	if _menu_pitch != -1 and _menu_octave != old:
		var moved := _menu_pitch + 12 * (_menu_octave - old)
		if moved >= 0 and moved <= 127:
			_menu_pitch = moved
			if _menu_note != -1 and not surface.get_note(_menu_note).is_empty():
				surface.set_note_pitch(_menu_note, moved)
				Midi.play_note(moved, 90, 0.25, _menu_channel)
	_rebuild_pitch_items()


## Two-digit channel typing: 1-9 apply at once; a quick second digit makes 10-16
## (1 then 2 = 12); any other second digit starts over.
func _on_digit(d: int) -> void:
	if radial.get_meta("mode", "") != "pitch":
		return
	var now := Time.get_ticks_msec()
	if _digit_first != -1 and now - _digit_time <= DIGIT_WINDOW_MS:
		var v := _digit_first * 10 + d
		_digit_first = -1
		if v >= 10 and v <= 16:
			_menu_channel = v - 1
			_rebuild_pitch_items()
			return
	if d >= 1 and d <= 9:
		_menu_channel = d - 1
		_digit_first = d if d == 1 else -1     # only "1" can start 10-16
		_digit_time = now
		_rebuild_pitch_items()
		if _digit_first != -1:
			# Show "ch 1…" while a second digit can still follow, then settle on "ch 1".
			get_tree().create_timer(DIGIT_WINDOW_MS / 1000.0 + 0.02).timeout.connect(func() -> void:
				if radial.visible and radial.get_meta("mode", "") == "pitch" and Time.get_ticks_msec() - _digit_time > DIGIT_WINDOW_MS:
					_rebuild_pitch_items())


# --- Channel menu ---------------------------------------------------------------------------

func _open_channel_menu(note_id: int, at: Vector2) -> void:
	_menu_note = note_id
	radial.set_meta("mode", "channel")
	_rebuild_channel_items()
	radial.open(at)


func _rebuild_channel_items() -> void:
	var current: int = surface.get_note(_menu_note).get("channel", 0)
	radial.inner_items = []
	radial.center_item = {}
	radial.outer_items = []
	for ch in 16:
		radial.outer_items.append({"id": ch, "label": str(ch + 1), "color": Palette.channel_color(ch), "selected": ch == current})
	radial.title = "MIDI channel"
	radial.subtitle = ""
	radial.refresh()


# --- Pulse menu -----------------------------------------------------------------------------

## Outer ring = cooldown, inner ring = emit strength, centre = cycle mode.
func _open_pulse_menu(note_id: int, at: Vector2) -> void:
	_menu_note = note_id
	radial.set_meta("mode", "pulse")
	_rebuild_pulse_items()
	radial.open(at)


func _rebuild_pulse_items() -> void:
	var n := surface.get_note(_menu_note)
	if n.is_empty():
		return
	radial.outer_items = []
	for i in COOLDOWNS.size():
		var c: float = COOLDOWNS[i]
		radial.outer_items.append({"id": c, "label": COOLDOWN_LABELS[i], "color": Palette.YELLOW,
				"selected": absf(n.cooldown - c) < 0.001})
	radial.inner_items = []
	for s in PULSE_STRENGTHS:
		radial.inner_items.append({"id": s, "label": "%d%%" % roundi(s * 100), "color": Palette.RED,
				"selected": absf(n.pulse_strength - s) < 0.001})
	radial.center_item = {"id": "mode", "label": MODE_LABELS[n.mode], "color": Palette.channel_color(n.channel)}
	radial.title = "Pulse · cooldown in beats or Retrigger (outer) · strength (inner)"
	radial.subtitle = "Centre: switch Note ↔ Relay"
	radial.refresh()


# --- Modifier menu ----------------------------------------------------------------------------

## Outer ring = modifier (None / Toggle); inner ring = the toggle's state (On / Off),
## which sets both its current and its start state.
func _open_modifier_menu(note_id: int, at: Vector2) -> void:
	_menu_note = note_id
	radial.set_meta("mode", "modifier")
	_rebuild_modifier_items()
	radial.open(at)


func _rebuild_modifier_items() -> void:
	var n := surface.get_note(_menu_note)
	if n.is_empty():
		return
	var col := Palette.channel_color(n.channel)
	radial.outer_items = [
		{"id": "", "label": "None", "color": Palette.TEXT_DIM, "selected": n.mod == ""},
		{"id": "toggle", "label": "Toggle", "color": col, "selected": n.mod == "toggle"},
	]
	radial.inner_items = []
	if n.mod == "toggle":
		radial.inner_items = [
			{"id": true, "label": "On", "color": col, "selected": n.mod_on},
			{"id": false, "label": "Off", "color": Palette.TEXT_DIM, "selected": not n.mod_on},
		]
	radial.center_item = {}
	radial.title = "Modifier"
	radial.subtitle = "Toggle: plays every other hit · inner ring sets its start state" if n.mod == "toggle" else "Toggle: plays every other hit"
	radial.refresh()


## Pitch ring preview: hovering an outer item plays it on the ring's channel.
var _previewed_pitch := -1


func _on_radial_hover(ring: String, id: Variant) -> void:
	_previewed_pitch = -1
	if ring != "outer" or radial.get_meta("mode", "") != "pitch" or not Settings.hover_preview:
		return
	var pitch: int = id
	Midi.play_note(pitch, 80, 0.25, _menu_channel)
	_previewed_pitch = pitch


# --- Radial results ---------------------------------------------------------------------------

func _on_radial_outer(id: Variant) -> void:
	match radial.get_meta("mode", ""):
		"pitch":
			var pitch: int = id
			if _menu_note == -1:
				# Placed. Further picks (left clicks keep the menu open) retune this note.
				_menu_note = surface.add_note_at(_menu_pos, pitch, _menu_channel)
				radial.center_item = {"id": "delete", "label": "Del", "color": Palette.RED}
			else:
				surface.set_note_pitch(_menu_note, pitch)
				if surface.get_note(_menu_note).channel != _menu_channel:
					surface.set_note_channel(_menu_note, _menu_channel)
			if pitch != _previewed_pitch:
				Midi.play_note(pitch, 90, 0.25, _menu_channel)   # already heard on hover otherwise
			_menu_pitch = pitch
			_rebuild_pitch_items()
		"channel":
			var ch: int = id
			for gid in surface.group_for(_menu_note):
				surface.set_note_channel(gid, ch)
			var n := surface.get_note(_menu_note)
			if not n.is_empty():
				Midi.play_note(n.note, 90, 0.25, ch)
			_rebuild_channel_items()
		"modifier":
			for gid in surface.group_for(_menu_note):
				surface.set_modifier(gid, id)
			_rebuild_modifier_items()
		"pulse":
			var n := surface.get_note(_menu_note)
			if n.is_empty():
				return
			for gid in surface.group_for(_menu_note):
				var g := surface.get_note(gid)
				surface.set_pulse_params(gid, g.pulse_strength, id)
				if g.mode == WaveSurface.Mode.NOTE:
					surface.set_note_mode(gid, WaveSurface.Mode.RELAY)   # tuning a pulse turns it on
			_rebuild_pulse_items()


func _on_radial_inner(id: Variant) -> void:
	match radial.get_meta("mode", ""):
		"modifier":
			for gid in surface.group_for(_menu_note):
				surface.set_modifier_state(gid, id)
			_rebuild_modifier_items()
		"pitch":
			_set_menu_octave(id)
		"pulse":
			var n := surface.get_note(_menu_note)
			if n.is_empty():
				return
			for gid in surface.group_for(_menu_note):
				var g := surface.get_note(gid)
				surface.set_pulse_params(gid, id, g.cooldown)
				if g.mode == WaveSurface.Mode.NOTE:
					surface.set_note_mode(gid, WaveSurface.Mode.RELAY)
			_rebuild_pulse_items()


func _on_radial_center(id: Variant) -> void:
	if _menu_note == -1:
		return
	match id:
		"delete":
			surface.remove_note(_menu_note)
			radial.close()                   # nothing left to edit
		"mode":
			surface.cycle_mode(_menu_note)
			_rebuild_pulse_items()
