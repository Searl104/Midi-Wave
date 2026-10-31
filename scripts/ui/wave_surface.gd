class_name WaveSurface
extends Control
## The liquid surface. Owns waves and notes, does hit detection, sends MIDI, draws both.
##
## Mouse:  click = wave · drag a note = move · shift-click = new note
##         right-click = pitch radial (on empty space it places a note)
##         alt-click = channel radial · middle-click / Delete = remove note

signal pitch_menu_requested(note_id: int, at: Vector2)    # note_id -1 = place a new note at `at`
signal channel_menu_requested(note_id: int, at: Vector2)
signal notes_changed

const MAX_WAVES := 32
const NOTE_RADIUS := 22.0
const DRAG_THRESHOLD := 6.0
const MIN_AMPLITUDE := 0.01
const SPLASH_TIME := 0.6

var waves: Array = []      # {origin: Vector2, t: float, strength: float, hits: Dictionary}
var notes: Array = []      # {id, pos: Vector2 (normalized), note, channel, flash, playing, off_at}
var splashes: Array = []   # {pos: Vector2, t: float, color: Color, strength: float}

var last_pitch := 60
var last_channel := 0

var _next_id := 1
var _hover_id := -1
var _press_id := -1
var _press_pos := Vector2.ZERO
var _dragging := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	load_notes()
	Settings.changed.connect(_on_setting_changed)


# --- Notes ---------------------------------------------------------------------

func load_notes() -> void:
	notes.clear()
	for d in Settings.notes:
		_add(Vector2(d.get("x", 0.5), d.get("y", 0.5)), int(d.get("note", 60)), int(d.get("channel", 0)))
	if notes.is_empty():
		seed_default_layout()


func seed_default_layout() -> void:
	var pitches := Scales.octave_notes(4, Settings.root_note, Settings.scale_name)
	pitches.append_array(Scales.octave_notes(5, Settings.root_note, Settings.scale_name).slice(0, 3))
	var count := pitches.size()
	for i in count:
		var a := -PI / 2.0 + TAU * i / count
		_add(Vector2(0.5, 0.5) + Vector2(cos(a) * 0.26, sin(a) * 0.32), pitches[i], 0)
	save_notes()


func save_notes() -> void:
	var out: Array = []
	for n in notes:
		out.append({"x": n.pos.x, "y": n.pos.y, "note": n.note, "channel": n.channel})
	Settings.notes = out
	Settings.queue_save()
	notes_changed.emit()


func add_note_at(screen_pos: Vector2, pitch: int, channel: int) -> int:
	var id := _add(screen_pos / size, Scales.quantize(pitch, Settings.root_note, Settings.scale_name), channel)
	last_pitch = pitch
	last_channel = channel
	save_notes()
	return id


func set_note_pitch(id: int, pitch: int) -> void:
	var n := get_note(id)
	if n.is_empty():
		return
	_silence(n)
	n.note = pitch
	last_pitch = pitch
	save_notes()


func set_note_channel(id: int, channel: int) -> void:
	var n := get_note(id)
	if n.is_empty():
		return
	_silence(n)
	n.channel = channel
	last_channel = channel
	save_notes()


func remove_note(id: int) -> void:
	for i in notes.size():
		if notes[i].id == id:
			_silence(notes[i])
			notes.remove_at(i)
			break
	if _hover_id == id:
		_hover_id = -1
	save_notes()


func clear_notes() -> void:
	for n in notes:
		_silence(n)
	notes.clear()
	save_notes()


func get_note(id: int) -> Dictionary:
	for n in notes:
		if n.id == id:
			return n
	return {}


func note_screen_pos(n: Dictionary) -> Vector2:
	return n.pos * size


func note_at(screen_pos: Vector2) -> int:
	var best := -1
	var best_d := NOTE_RADIUS + 6.0
	for n in notes:
		var d := screen_pos.distance_to(note_screen_pos(n))
		if d < best_d:
			best_d = d
			best = n.id
	return best


func _add(pos_n: Vector2, pitch: int, channel: int) -> int:
	var id := _next_id
	_next_id += 1
	notes.append({
		"id": id, "pos": pos_n.clamp(Vector2.ZERO, Vector2.ONE),
		"note": clampi(pitch, 0, 127), "channel": clampi(channel, 0, 15),
		"flash": 0.0, "playing": false, "off_at": 0,
	})
	return id


func _on_setting_changed(key: String) -> void:
	if key == "root_note" or key == "scale_name":
		for n in notes:
			var q := Scales.quantize(n.note, Settings.root_note, Settings.scale_name)
			if q != n.note:
				_silence(n)
				n.note = q
		save_notes()


# --- Waves -----------------------------------------------------------------------

func spawn_wave(origin: Vector2, strength: float = -1.0) -> void:
	waves.append({
		"origin": origin, "t": 0.0,
		"strength": Settings.wave_strength if strength < 0.0 else strength,
		"hits": {},
	})
	while waves.size() > MAX_WAVES:
		waves.pop_front()


## Wave amplitude at distance `d` from its source: strength at 0, falling to 0 at range.
func amplitude(strength: float, d: float) -> float:
	var x := clampf(1.0 - d / maxf(Settings.wave_range, 1.0), 0.0, 1.0)
	return strength * pow(x, Settings.falloff_curve)


## Data for water.gdshader: (x, y, radius, amplitude at that radius) per wave.
func shader_waves() -> PackedVector4Array:
	var out := PackedVector4Array()
	out.resize(MAX_WAVES)
	for i in mini(waves.size(), MAX_WAVES):
		var w: Dictionary = waves[i]
		var r: float = w.t * Settings.wave_speed
		out[i] = Vector4(w.origin.x, w.origin.y, r, amplitude(w.strength, r) * _fade_in(r))
	return out


func _fade_in(r: float) -> float:
	return clampf(r / 40.0, 0.0, 1.0)


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var i := 0
	while i < waves.size():
		var w: Dictionary = waves[i]
		w.t += delta
		var r: float = w.t * Settings.wave_speed
		if r >= Settings.wave_range:
			waves.remove_at(i)
			continue
		for n in notes:
			if w.hits.has(n.id):
				continue
			var d := (w.origin as Vector2).distance_to(note_screen_pos(n))
			if r >= d:
				w.hits[n.id] = true
				var amp := amplitude(w.strength, d)
				if amp >= MIN_AMPLITUDE:
					_trigger(n, amp, now)
		i += 1

	for n in notes:
		if n.playing and now >= n.off_at:
			Midi.note_off(n.note, n.channel)
			n.playing = false
		n.flash = maxf(0.0, n.flash - delta * 2.5)

	var s := 0
	while s < splashes.size():
		splashes[s].t += delta
		if splashes[s].t >= SPLASH_TIME:
			splashes.remove_at(s)
		else:
			s += 1
	queue_redraw()


func _trigger(n: Dictionary, amp: float, now: int) -> void:
	var velocity := clampi(roundi(amp * 127.0), 1, 127)
	if n.playing:
		Midi.note_off(n.note, n.channel)
	Midi.note_on(n.note, velocity, n.channel)
	n.playing = true
	n.off_at = now + int(Settings.note_length * 1_000_000.0)
	n.flash = maxf(n.flash, 0.35 + amp * 0.65)
	splashes.append({"pos": note_screen_pos(n), "t": 0.0, "color": Palette.channel_color(n.channel), "strength": amp})


func _silence(n: Dictionary) -> void:
	if n.playing:
		Midi.note_off(n.note, n.channel)
		n.playing = false


# --- Input -------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb:
		_handle_button(mb)
		accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm:
		if _press_id != -1:
			if not _dragging and mm.position.distance_to(_press_pos) > DRAG_THRESHOLD:
				_dragging = true
			if _dragging:
				var n := get_note(_press_id)
				if not n.is_empty():
					n.pos = (mm.position / size).clamp(Vector2.ZERO, Vector2.ONE)
		_hover_id = note_at(mm.position)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _hover_id != -1 else Control.CURSOR_ARROW


func _handle_button(mb: InputEventMouseButton) -> void:
	var pos := mb.position
	var hit := note_at(pos)
	match mb.button_index:
		MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if mb.alt_pressed:
					if hit != -1:
						channel_menu_requested.emit(hit, pos)
				elif mb.shift_pressed:
					add_note_at(pos, last_pitch, last_channel)
				elif hit != -1:
					_press_id = hit
					_press_pos = pos
					_dragging = false
				else:
					spawn_wave(pos)
			else:
				if _press_id != -1:
					if _dragging:
						save_notes()
					else:
						var n := get_note(_press_id)
						if not n.is_empty():
							spawn_wave(note_screen_pos(n))
				_press_id = -1
				_dragging = false
		MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				if mb.alt_pressed:
					if hit != -1:
						channel_menu_requested.emit(hit, pos)
				else:
					pitch_menu_requested.emit(hit, pos)
		MOUSE_BUTTON_MIDDLE:
			if mb.pressed and hit != -1:
				remove_note(hit)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and (key.keycode == KEY_DELETE or key.keycode == KEY_BACKSPACE):
		if _hover_id != -1:
			remove_note(_hover_id)
			get_viewport().set_input_as_handled()


# --- Drawing -------------------------------------------------------------------------

func _draw() -> void:
	var font := get_theme_default_font()

	for w in waves:
		var r: float = w.t * Settings.wave_speed
		var a := amplitude(w.strength, r) * _fade_in(r)
		draw_arc(w.origin, r, 0.0, TAU, 160, Color(Palette.ACCENT, a * 0.7), 2.0, true)
		if r > 14.0:
			draw_arc(w.origin, r - 12.0, 0.0, TAU, 160, Color(1, 1, 1, a * 0.12), 1.0, true)

	for sp in splashes:
		var k: float = sp.t / SPLASH_TIME
		var rr := NOTE_RADIUS + 46.0 * ease(k, 0.4)
		draw_arc(sp.pos, rr, 0.0, TAU, 64, Color(sp.color, (1.0 - k) * 0.6 * sp.strength), 2.0, true)

	for n in notes:
		var p := note_screen_pos(n)
		var col := Palette.channel_color(n.channel)
		var f: float = n.flash
		if f > 0.0:
			draw_circle(p, NOTE_RADIUS + 16.0 * f, Color(col, 0.18 * f))
			draw_circle(p, NOTE_RADIUS + 7.0 * f, Color(col, 0.25 * f))
		draw_circle(p, NOTE_RADIUS + 3.0, Color(0, 0, 0, 0.35))                       # shadow
		draw_circle(p, NOTE_RADIUS, Palette.GLASS.lerp(col, 0.12 + f * 0.35))          # body
		draw_arc(p, NOTE_RADIUS - 6.0, PI * 1.05, PI * 1.6, 18, Color(1, 1, 1, 0.22), 2.0, true)  # highlight
		draw_arc(p, NOTE_RADIUS, 0.0, TAU, 48, col.lerp(Color.WHITE, f * 0.5), 2.5, true)          # rim
		if n.id == _hover_id:
			draw_arc(p, NOTE_RADIUS + 5.0, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 1.0, true)
		draw_string(font, p + Vector2(-NOTE_RADIUS, 5.0), MidiMessage.note_name(n.note),
				HORIZONTAL_ALIGNMENT_CENTER, NOTE_RADIUS * 2.0, 13, Palette.TEXT)
		draw_string(font, p + Vector2(-NOTE_RADIUS, NOTE_RADIUS + 15.0), "ch %d" % (n.channel + 1),
				HORIZONTAL_ALIGNMENT_CENTER, NOTE_RADIUS * 2.0, 10, Color(col, 0.7))
