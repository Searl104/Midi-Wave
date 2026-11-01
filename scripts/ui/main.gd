extends Control
## Root of MIDI Wave: builds the water, surface, HUD, radial menu and options,
## and wires the radial menus to note editing.

const DIGIT_WINDOW_MS := 600   ## time allowed for the second digit of a channel number
const PAN_SPEED := 700.0       ## px per second for arrow-key panning

## Beats; 0 = Retrigger (no timer: fires on every wave that reaches it).
const COOLDOWNS := [0.0, 0.125, 1.0 / 6.0, 0.25, 1.0 / 3.0, 0.5, 2.0 / 3.0, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0]
const COOLDOWN_LABELS := ["Retrig", "⅛", "⅙", "¼", "⅓", "½", "⅔", "¾", "1", "1½", "2", "3", "4"]
const PULSE_STRENGTHS := [0.25, 0.5, 0.75, 1.0]
const MODE_LABELS := ["Note", "N+Pulse", "Pulse"]

var water: ColorRect
var caustic_time := 0.0          ## Tidal caustic clock, advanced at the Caustics speed setting
var surface: WaveSurface
var radial: RadialMenu
var options: OptionsPanel
var status_label: Label
var hint_label: Label
var cheat_sheet: CheatSheet
var midi_in: MidiInput
var _hint_key := ""

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
	surface.pitch_menu_requested.connect(_on_right_click)
	surface.channel_menu_requested.connect(_open_channel_menu)
	surface.pulse_menu_requested.connect(_open_pulse_menu)
	surface.modifier_menu_requested.connect(_open_modifier_menu)

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
	radial.digit.connect(_on_digit)
	radial.hover_changed.connect(_on_radial_hover)

	cheat_sheet = CheatSheet.new()
	add_child(cheat_sheet)

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
	_pan_with_keys(delta)
	var mat := water.material as ShaderMaterial
	mat.set_shader_parameter("surface_size", water.size)
	mat.set_shader_parameter("wave_count", mini(surface.waves.size(), WaveSurface.MAX_WAVES))
	mat.set_shader_parameter("waves", surface.shader_waves())
	mat.set_shader_parameter("view_px", surface.view_offset * surface.z())
	mat.set_shader_parameter("zoom", surface.z())
	_refresh_hint()
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


## Arrow keys pan the view (not while a radial menu is open: it uses Left / Right for octave).
func _pan_with_keys(delta: float) -> void:
	if radial.visible or get_viewport().gui_get_focus_owner() != null:
		return
	var dir := Vector2(
		float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_UP)))
	if dir != Vector2.ZERO:
		surface.pan_by(dir.normalized() * PAN_SPEED * delta)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not key:
		return
	# Keypad: KP1-9 trigger that slot's notes (held: pulsers refire on their cooldown);
	# Ctrl + KP1-9 over a note assigns it. Match the physical key so it works with
	# Num Lock on or off.
	var pad: int = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	if not key.pressed:
		if pad >= KEY_KP_1 and pad <= KEY_KP_9:
			surface.release_slot(pad - KEY_KP_0)
		elif RING_KEYS.has(key.keycode):
			_release_ring_key(RING_KEYS[key.keycode])
		return
	if key.echo:
		return
	if key.keycode == KEY_F1 or key.unicode == 63:      # F1 or "?"
		cheat_sheet.toggle()
		get_viewport().set_input_as_handled()
		return
	if cheat_sheet.visible and key.keycode == KEY_ESCAPE:
		cheat_sheet.hide()
		get_viewport().set_input_as_handled()
		return
	if pad == KEY_KP_0:
		surface.stop()
		get_viewport().set_input_as_handled()
		return
	if pad >= KEY_KP_1 and pad <= KEY_KP_9:
		var slot: int = pad - KEY_KP_0
		if key.ctrl_pressed:
			if surface.edit_mode and surface.hovered_note() != -1:
				surface.toggle_slot(surface.hovered_note(), slot)
		else:
			surface.press_slot(slot)
		get_viewport().set_input_as_handled()
		return
	match key.keycode:
		KEY_TAB:
			surface.set_edit_mode(not surface.edit_mode)
			get_viewport().set_input_as_handled()
		KEY_O:
			options.toggle()
			get_viewport().set_input_as_handled()
		KEY_SPACE:
			surface.stop()
			get_viewport().set_input_as_handled()
		KEY_S:
			if key.ctrl_pressed:
				_save_state()
				get_viewport().set_input_as_handled()
		KEY_M:
			if not key.ctrl_pressed and surface.edit_mode:
				surface.toggle_mute()
				get_viewport().set_input_as_handled()
		KEY_V:
			if key.ctrl_pressed and surface.edit_mode:
				surface.paste_at(surface.get_local_mouse_position())
				get_viewport().set_input_as_handled()
		KEY_Z:
			if key.ctrl_pressed and surface.edit_mode:
				_undo_redo(key.shift_pressed)
				get_viewport().set_input_as_handled()
		KEY_Y:
			if key.ctrl_pressed and surface.edit_mode:
				_undo_redo(true)
				get_viewport().set_input_as_handled()
		KEY_C, KEY_E, KEY_F:
			if key.keycode == KEY_C and key.ctrl_pressed:
				if surface.edit_mode:
					surface.copy_selection()
					get_viewport().set_input_as_handled()
			elif not key.ctrl_pressed and not key.alt_pressed and surface.edit_mode and not radial.visible:
				arm_ring(RING_KEYS[key.keycode])
				get_viewport().set_input_as_handled()
		KEY_G:
			if surface.edit_mode and not key.alt_pressed:
				if key.ctrl_pressed:
					var cleared: int = surface.clear_grids()
					_toast("Grids cleared" if cleared > 0 else "No grids on")
				else:
					match surface.toggle_grid_at_hover():
						"on": _toast("Grid on")
						"off": _toast("Grid off")
						_: _toast("Hover a note or emitter, then G for its grid")
				get_viewport().set_input_as_handled()
		KEY_HOME:
			surface.frame_notes()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if armed_ring != "":
				arm_ring("")
				get_viewport().set_input_as_handled()
			elif options.visible:
				options.hide()
				get_viewport().set_input_as_handled()
			elif not surface.selection.is_empty():
				surface.clear_selection()
				get_viewport().set_input_as_handled()


## Hint bar (R3): the actions for whatever is under the mouse, from WaveSurface.hint_context().
const HINTS_EDIT := {
	"empty": "Click: wave  ·  Right-click: pitch ring (hold, aim, release: place)  ·  Shift-click: note with last pitch  ·  Ctrl + right-drag: box select  ·  Middle-drag: pan  ·  Tab: play mode  ·  ?: all controls",
	"note": "Click: wave from it  ·  Drag: move  ·  Right-click: pitch (C / E / F first: channel / pulse / modifier)  ·  Ctrl-click: make a pulser  ·  M: mute  ·  G: grid  ·  Delete: remove  ·  Ctrl+KP: keypad key",
	"pulser": "Click: trigger  ·  Drag: move  ·  Ctrl-click: next mode  ·  Ctrl-drag: its reach  ·  E, right-click: pulse ring  ·  M: mute  ·  G: grid  ·  Delete: remove  ·  Ctrl+KP: keypad key",
	"emitter": "Drag: place where its wave starts (drop on the note to re-attach)  ·  Ctrl-drag: its reach  ·  G: grid under the emitter",
	"selected": "Drag: move the group  ·  Ring edits, M, Delete and Ctrl+KP apply to all  ·  Ctrl+C: copy  ·  Esc: clear",
	"selection": "%d selected  ·  M: mute all  ·  Delete: remove all  ·  Ctrl+C: copy  ·  Ctrl+V: paste at the mouse  ·  Esc or click empty space: clear",
	"drag_note": "Snapping to grid points (G over a note or emitter adds a grid)  ·  Drop on a note or emitter: snap to its centre  ·  Shift: free",
	"drag_emitter": "Place where the wave starts  ·  Snaps to grid points and centres  ·  Drop on its note: re-attach  ·  Shift: free",
	"range": "Set this emitter's reach (snaps to beat divisions)  ·  Back onto the note: global reach  ·  Shift: free",
	"box": "Release to select  ·  Hold Shift to add to the selection",
}
const HINT_PLAY := "Play mode  ·  Click: wave or trigger  ·  KP1-9: slots  ·  Middle-drag: pan  ·  Space: stop  ·  Tab: edit mode  ·  ?: all controls"


func _on_mode_changed(edit: bool) -> void:
	if radial and radial.visible:
		radial.close()
	armed_ring = ""
	_held_ring = ""
	_refresh_hint()
	_toast("Edit mode" if edit else "Play mode  ·  layout locked")


# --- Ring choice (R8) --------------------------------------------------------------------------
# Right-click always summons the active ring. Pitch is the default; C, E and F pick the channel,
# pulse or modifier ring for the next right-click on a note, then it goes back to pitch. Holding
# the key while right-dragging is a quick ring: flick to an item and release.

const RING_KEYS := {KEY_C: "channel", KEY_E: "pulse", KEY_F: "modifier"}
const RING_NAMES := {"channel": "Channel", "pulse": "Pulse", "modifier": "Modifier"}
const RING_KEY_LABELS := {"channel": "C", "pulse": "E", "modifier": "F"}

var armed_ring := ""        ## "" = pitch (the default), else "channel", "pulse" or "modifier"
var _held_ring := ""        ## the ring whose key is held down: it stays active until the key is let go
var _held_used := false     ## the held ring was opened at least once while its key was down


## Picks the ring the next right-click opens. Picking the armed ring again cancels it.
func arm_ring(ring: String) -> void:
	armed_ring = "" if ring == armed_ring else ring
	_held_ring = armed_ring
	_held_used = false
	_refresh_hint()


## Letting go of C / E / F. A ring used while its key was held ends with the key; a quick tap
## (not used yet) stays armed for one right-click.
func _release_ring_key(ring: String) -> void:
	if _held_ring != ring:
		return
	_held_ring = ""
	if _held_used and armed_ring == ring:
		armed_ring = ""
	_held_used = false
	_refresh_hint()


func _on_right_click(note_id: int, at: Vector2) -> void:
	var ring := armed_ring
	if ring == "":
		_open_pitch_menu(note_id, at)
		return
	if note_id == -1:
		_toast("Right-click a note for the %s ring" % RING_NAMES[ring])
		return
	if _held_ring == ring:
		_held_used = true            # key still held: the ring stays active until it's let go
	else:
		armed_ring = ""              # tapped: used once, then back to pitch
	_refresh_hint()
	# Opened as a held ring: flick and release to choose (the quick ring); a tap keeps it open.
	match ring:
		"channel":
			_open_channel_menu(note_id, at, true)
		"pulse":
			_open_pulse_menu(note_id, at, true)
		"modifier":
			_open_modifier_menu(note_id, at, true)


func _refresh_hint() -> void:
	var text: String
	if armed_ring != "" and _held_ring == armed_ring and _held_used:
		text = "%s ring while %s is held  ·  Right-click notes  ·  let go of %s for pitch" % [
				RING_NAMES[armed_ring], RING_KEY_LABELS[armed_ring], RING_KEY_LABELS[armed_ring]]
	elif armed_ring != "":
		var k: String = RING_KEY_LABELS[armed_ring]
		text = "%s ring armed  ·  Right-click a note (or hold %s and right-drag, release to choose)  ·  %s or Esc cancels" % [
				RING_NAMES[armed_ring], k, k]
	elif not surface.edit_mode:
		text = HINT_PLAY
	else:
		var ctx: String = surface.hint_context()
		text = HINTS_EDIT[ctx]
		if ctx == "selection":
			text = text % surface.selection.size()
		elif ctx == "empty" and surface.has_grids():
			text = text.replace("Shift-click: note with last pitch", "New notes land on grid points  ·  Ctrl+G: clear grids")
	if text != _hint_key:
		_hint_key = text
		hint_label.text = text


## Ctrl+S or the Save state button: toggles' current states become their start states.
func _save_state() -> void:
	surface.save_state()
	_toast("Start states saved")


## Ctrl+Z / Ctrl+Shift+Z (Ctrl+Y): undo or redo the last edit, with a brief toast.
func _undo_redo(redo: bool) -> void:
	var done: bool = surface.redo() if redo else surface.undo()
	if done:
		var left: int = surface.redo_steps() if redo else surface.undo_steps()
		_toast("%s  ·  %d more" % ["Redo" if redo else "Undo", left])
	else:
		_toast("Nothing to redo" if redo else "Nothing to undo")


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
	# A key released while the window is unfocused never arrives: don't leave slots held.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and surface:
		surface.release_all_slots()


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
	stop.tooltip_text = "Clear every wave and return to the save state (Space)"
	stop.focus_mode = Control.FOCUS_NONE
	stop.pressed.connect(func() -> void: surface.stop())
	top.add_child(stop)

	var gear := Button.new()
	gear.text = "Options"
	gear.focus_mode = Control.FOCUS_NONE
	gear.pressed.connect(func() -> void: options.toggle())
	top.add_child(gear)

	hint_label = Label.new()
	hint_label.text = HINTS_EDIT["empty"]
	hint_label.add_theme_font_size_override("font_size", 12)
	hint_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint_label.offset_top = -34
	hint_label.offset_bottom = -14
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint_label)
	hint_label.modulate.a = 0.85                 # stays up: it follows what is under the mouse


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
	radial.open(at, true)


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
	radial.subtitle = "A / D octave · type 1-16 for channel · Esc cancels"
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

func _open_channel_menu(note_id: int, at: Vector2, hold: bool = false) -> void:
	_menu_note = note_id
	radial.set_meta("mode", "channel")
	_rebuild_channel_items()
	radial.open(at, hold)


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
func _open_pulse_menu(note_id: int, at: Vector2, hold: bool = false) -> void:
	_menu_note = note_id
	radial.set_meta("mode", "pulse")
	_rebuild_pulse_items()
	radial.open(at, hold)


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
	radial.subtitle = "Centre: Note → Note + Pulse → Pulse only"
	radial.refresh()


# --- Modifier menu ----------------------------------------------------------------------------

## Outer ring = modifier (None / Toggle); inner ring = the toggle's state (On / Off),
## which sets both its current and its start state.
func _open_modifier_menu(note_id: int, at: Vector2, hold: bool = false) -> void:
	_menu_note = note_id
	radial.set_meta("mode", "modifier")
	_rebuild_modifier_items()
	radial.open(at, hold)


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
					surface.set_note_mode(gid, WaveSurface.Mode.NOTE_PULSE)   # tuning a pulse turns it on
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
					surface.set_note_mode(gid, WaveSurface.Mode.NOTE_PULSE)
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
