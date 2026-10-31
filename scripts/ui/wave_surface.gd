class_name WaveSurface
extends Control
## The liquid surface. Owns waves and notes, does hit detection, sends MIDI, draws both.
##
## A note is one object with three modes:
##   NOTE        plays its note when a wave hits it
##   NOTE_PULSE  plays its note and emits a new wave from its emitter
##   PULSE       silent; only emits
## A pulsing note emits at its own fixed strength, at most once per cooldown, and never
## reacts to waves it emitted itself. Its emitter starts on the note (attached); dragging
## the emitter handle detaches it to a fixed spot on the surface.
##
## Mouse:  click = wave · drag note = move · drag emitter handle = place emitter
##         right-click (hold / tap) = pitch radial · alt-click = channel radial
##         ctrl-click = cycle mode · ctrl-right-click = pulse radial
##         shift-click = new note · middle-click / Delete = remove note

signal pitch_menu_requested(note_id: int, at: Vector2)    # note_id -1 = place a new note at `at`
signal channel_menu_requested(note_id: int, at: Vector2)
signal pulse_menu_requested(note_id: int, at: Vector2)
signal notes_changed

enum Mode { NOTE, NOTE_PULSE, PULSE }

const MAX_WAVES := 64           ## must match MAX_WAVES in water.gdshader
const NOTE_RADIUS := 22.0
const HANDLE_RADIUS := 7.0
const DRAG_THRESHOLD := 6.0
const MIN_AMPLITUDE := 0.01
const SPLASH_TIME := 0.6
const MIN_COOLDOWN := 0.1
const DEFAULT_PULSE_STRENGTH := 0.8
const DEFAULT_COOLDOWN := 0.5

var waves: Array = []      # {origin: Vector2, t: float, strength: float, source: int, hits: Dictionary}
var notes: Array = []      # see _add()
var splashes: Array = []   # {pos: Vector2, t: float, color: Color, strength: float}

var last_pitch := 60
var last_channel := 0
var skipped_pulses := 0    ## pulses dropped because the surface was full (for testing / HUD)

var clock_usec := 0       ## simulation time; cooldowns and note lengths run on this
var _next_id := 1
var _hover_id := -1
var _hover_handle := -1
var _press_id := -1
var _press_kind := ""      # "note" or "emitter"
var _press_pos := Vector2.ZERO
var _dragging := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	load_notes()
	Settings.changed.connect(_on_setting_changed)


# --- Notes -------------------------------------------------------------------------------

func load_notes() -> void:
	notes.clear()
	for d in Settings.notes:
		var id := _add(Vector2(d.get("x", 0.5), d.get("y", 0.5)), int(d.get("note", 60)), int(d.get("channel", 0)))
		var n := get_note(id)
		n.mode = clampi(int(d.get("mode", Mode.NOTE)), Mode.NOTE, Mode.PULSE)
		n.pulse_strength = clampf(float(d.get("pulse_strength", DEFAULT_PULSE_STRENGTH)), 0.05, 1.0)
		n.cooldown = maxf(float(d.get("cooldown", DEFAULT_COOLDOWN)), MIN_COOLDOWN)
		n.attached = bool(d.get("attached", true))
		n.emit = Vector2(d.get("ex", n.pos.x), d.get("ey", n.pos.y))
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
		out.append({
			"x": n.pos.x, "y": n.pos.y, "note": n.note, "channel": n.channel,
			"mode": n.mode, "pulse_strength": n.pulse_strength, "cooldown": n.cooldown,
			"attached": n.attached, "ex": n.emit.x, "ey": n.emit.y,
		})
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


## NOTE -> NOTE_PULSE -> PULSE -> NOTE. A pulse that gets switched on is ready to fire.
func cycle_mode(id: int) -> void:
	var n := get_note(id)
	if n.is_empty():
		return
	set_note_mode(id, (n.mode + 1) % 3)


func set_note_mode(id: int, mode: int) -> void:
	var n := get_note(id)
	if n.is_empty():
		return
	if n.mode == Mode.NOTE and mode != Mode.NOTE:
		n.ready_at = 0
	if mode == Mode.PULSE:
		_silence(n)
	n.mode = mode
	save_notes()


func set_pulse_params(id: int, strength: float, cooldown: float) -> void:
	var n := get_note(id)
	if n.is_empty():
		return
	n.pulse_strength = clampf(strength, 0.05, 1.0)
	n.cooldown = maxf(cooldown, MIN_COOLDOWN)
	n.ready_at = mini(n.ready_at, clock_usec + int(n.cooldown * 1_000_000.0))
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


## Where this note's waves start.
func emitter_screen_pos(n: Dictionary) -> Vector2:
	return note_screen_pos(n) if n.attached else n.emit * size


## Where the draggable emitter handle is drawn: on the rim while attached.
func handle_screen_pos(n: Dictionary) -> Vector2:
	if n.attached:
		return note_screen_pos(n) + Vector2(1, -1).normalized() * (NOTE_RADIUS + 9.0)
	return n.emit * size


func note_at(screen_pos: Vector2) -> int:
	var best := -1
	var best_d := NOTE_RADIUS + 6.0
	for n in notes:
		var d := screen_pos.distance_to(note_screen_pos(n))
		if d < best_d:
			best_d = d
			best = n.id
	return best


func handle_at(screen_pos: Vector2) -> int:
	for n in notes:
		if n.mode != Mode.NOTE and screen_pos.distance_to(handle_screen_pos(n)) <= HANDLE_RADIUS + 4.0:
			return n.id
	return -1


func _add(pos_n: Vector2, pitch: int, channel: int) -> int:
	var id := _next_id
	_next_id += 1
	var p := pos_n.clamp(Vector2.ZERO, Vector2.ONE)
	notes.append({
		"id": id, "pos": p,
		"note": clampi(pitch, 0, 127), "channel": clampi(channel, 0, 15),
		"flash": 0.0, "playing": false, "off_at": 0,
		"mode": Mode.NOTE, "pulse_strength": DEFAULT_PULSE_STRENGTH, "cooldown": DEFAULT_COOLDOWN,
		"ready_at": 0, "pulse_flash": 0.0,
		"attached": true, "emit": p,
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


# --- Waves -------------------------------------------------------------------------------

## A wave from the user. If the surface is full, the oldest wave makes room.
func spawn_wave(origin: Vector2, strength: float = -1.0) -> void:
	waves.append(_make_wave(origin, Settings.wave_strength if strength < 0.0 else strength, -1))
	while waves.size() > MAX_WAVES:
		waves.pop_front()


func stop_all_waves() -> void:
	waves.clear()


func _make_wave(origin: Vector2, strength: float, source: int) -> Dictionary:
	return {"origin": origin, "t": 0.0, "strength": strength, "source": source, "hits": {}}


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
	step(delta)
	queue_redraw()


## Advances the simulation by `delta` seconds. Split out so tests can drive it directly.
func step(delta: float) -> void:
	clock_usec += int(delta * 1_000_000.0)
	var now := clock_usec
	var spawned: Array = []
	var i := 0
	while i < waves.size():
		var w: Dictionary = waves[i]
		w.t += delta
		var r: float = w.t * Settings.wave_speed
		if r >= Settings.wave_range:
			waves.remove_at(i)
			continue
		for n in notes:
			if n.id == w.source or w.hits.has(n.id):
				continue
			var d := (w.origin as Vector2).distance_to(note_screen_pos(n))
			# A wave that starts on a note (d within its radius) hits it straight away.
			if r >= d or d <= NOTE_RADIUS:
				w.hits[n.id] = true
				var amp := amplitude(w.strength, d)
				if amp >= MIN_AMPLITUDE:
					_on_hit(n, amp, now, spawned)
		i += 1
	waves.append_array(spawned)

	for n in notes:
		if n.playing and now >= n.off_at:
			Midi.note_off(n.note, n.channel)
			n.playing = false
		n.flash = maxf(0.0, n.flash - delta * 2.5)
		n.pulse_flash = maxf(0.0, n.pulse_flash - delta * 3.0)

	var s := 0
	while s < splashes.size():
		splashes[s].t += delta
		if splashes[s].t >= SPLASH_TIME:
			splashes.remove_at(s)
		else:
			s += 1


func _on_hit(n: Dictionary, amp: float, now: int, spawned: Array) -> void:
	if n.mode != Mode.PULSE:
		_play(n, amp, now)
	if n.mode == Mode.NOTE or now < n.ready_at:
		return
	if waves.size() + spawned.size() >= MAX_WAVES:
		skipped_pulses += 1          # surface full: skip this beat, stay ready
		return
	spawned.append(_make_wave(emitter_screen_pos(n), n.pulse_strength, n.id))
	n.ready_at = now + int(n.cooldown * 1_000_000.0)
	n.pulse_flash = 1.0


func _play(n: Dictionary, amp: float, now: int) -> void:
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


# --- Input -------------------------------------------------------------------------------

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
					var p := (mm.position / size).clamp(Vector2.ZERO, Vector2.ONE)
					if _press_kind == "emitter":
						n.attached = false
						n.emit = p
					else:
						n.pos = p
		_hover_handle = handle_at(mm.position)
		_hover_id = note_at(mm.position) if _hover_handle == -1 else -1
		var over := _hover_id != -1 or _hover_handle != -1
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if over else Control.CURSOR_ARROW


func _handle_button(mb: InputEventMouseButton) -> void:
	var pos := mb.position
	var handle := handle_at(pos)
	var hit := note_at(pos)
	match mb.button_index:
		MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if mb.ctrl_pressed:
					if hit != -1:
						cycle_mode(hit)
					else:
						spawn_wave(pos)
				elif mb.alt_pressed:
					if hit != -1:
						channel_menu_requested.emit(hit, pos)
				elif mb.shift_pressed:
					add_note_at(pos, last_pitch, last_channel)
				elif handle != -1:
					_begin_press(handle, "emitter", pos)
				elif hit != -1:
					_begin_press(hit, "note", pos)
				else:
					spawn_wave(pos)
			else:
				_end_press()
		MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				if mb.ctrl_pressed:
					if hit != -1:
						pulse_menu_requested.emit(hit, pos)
				elif mb.alt_pressed:
					if hit != -1:
						channel_menu_requested.emit(hit, pos)
				else:
					pitch_menu_requested.emit(hit, pos)
		MOUSE_BUTTON_MIDDLE:
			if mb.pressed and hit != -1:
				remove_note(hit)


func _begin_press(id: int, kind: String, pos: Vector2) -> void:
	_press_id = id
	_press_kind = kind
	_press_pos = pos
	_dragging = false


func _end_press() -> void:
	if _press_id != -1:
		var n := get_note(_press_id)
		if not n.is_empty():
			if _dragging:
				if _press_kind == "emitter" and (n.emit * size).distance_to(note_screen_pos(n)) <= NOTE_RADIUS:
					n.attached = true        # dropped back on its own note: re-attach
					n.emit = n.pos
				save_notes()
			elif _press_kind == "note":
				spawn_wave(note_screen_pos(n))
	_press_id = -1
	_press_kind = ""
	_dragging = false


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and (key.keycode == KEY_DELETE or key.keycode == KEY_BACKSPACE):
		if _hover_id != -1:
			remove_note(_hover_id)
			get_viewport().set_input_as_handled()


# --- Drawing -------------------------------------------------------------------------------

func _draw() -> void:
	var font := get_theme_default_font()
	var now := clock_usec

	for w in waves:
		var r: float = w.t * Settings.wave_speed
		var a := amplitude(w.strength, r) * _fade_in(r)
		var ring_col := Palette.ACCENT if w.source == -1 else Palette.YELLOW
		draw_arc(w.origin, r, 0.0, TAU, 160, Color(ring_col, a * 0.7), 2.0, true)
		if r > 14.0:
			draw_arc(w.origin, r - 12.0, 0.0, TAU, 160, Color(1, 1, 1, a * 0.12), 1.0, true)

	for sp in splashes:
		var k: float = sp.t / SPLASH_TIME
		var rr := NOTE_RADIUS + 46.0 * ease(k, 0.4)
		draw_arc(sp.pos, rr, 0.0, TAU, 64, Color(sp.color, (1.0 - k) * 0.6 * sp.strength), 2.0, true)

	# Emitter tethers sit under the notes.
	for n in notes:
		if n.mode != Mode.NOTE and not n.attached:
			_draw_dashed(note_screen_pos(n), n.emit * size, Color(Palette.channel_color(n.channel), 0.4))

	for n in notes:
		_draw_note(n, font, now)


func _draw_note(n: Dictionary, font: Font, now: int) -> void:
	var p := note_screen_pos(n)
	var col := Palette.channel_color(n.channel)
	var f: float = n.flash
	var muted: bool = n.mode == Mode.PULSE

	if f > 0.0:
		draw_circle(p, NOTE_RADIUS + 16.0 * f, Color(col, 0.18 * f))
		draw_circle(p, NOTE_RADIUS + 7.0 * f, Color(col, 0.25 * f))
	draw_circle(p, NOTE_RADIUS + 3.0, Color(0, 0, 0, 0.35))                                   # shadow
	if muted:
		draw_circle(p, NOTE_RADIUS, Color(Palette.BG, 0.9))                                    # hollow
		draw_circle(p, NOTE_RADIUS * 0.35, Color(col, 0.18))
	else:
		draw_circle(p, NOTE_RADIUS, Palette.GLASS.lerp(col, 0.12 + f * 0.35))                  # body
		draw_arc(p, NOTE_RADIUS - 6.0, PI * 1.05, PI * 1.6, 18, Color(1, 1, 1, 0.22), 2.0, true)  # highlight
	draw_arc(p, NOTE_RADIUS, 0.0, TAU, 48, Color(col.lerp(Color.WHITE, f * 0.5), 0.45 if muted else 1.0), 2.5, true)

	if n.mode != Mode.NOTE:
		# Pulse ring: refills clockwise from the top while cooling down, flashes on fire.
		var ring_r := NOTE_RADIUS + 5.0
		var ready := 1.0
		if now < n.ready_at:
			ready = 1.0 - float(n.ready_at - now) / (n.cooldown * 1_000_000.0)
		var pf: float = n.pulse_flash
		draw_arc(p, ring_r, 0.0, TAU, 48, Color(1, 1, 1, 0.08), 2.0, true)
		draw_arc(p, ring_r, -PI / 2.0, -PI / 2.0 + TAU * clampf(ready, 0.0, 1.0), 48,
				Color(Palette.YELLOW, 0.55 + 0.45 * pf), 2.0, true)
		if pf > 0.0:
			draw_arc(p, ring_r + 8.0 * (1.0 - pf), 0.0, TAU, 48, Color(Palette.YELLOW, 0.5 * pf), 2.0, true)
		_draw_handle(handle_screen_pos(n), col, n.id == _hover_handle)

	if n.id == _hover_id:
		draw_arc(p, NOTE_RADIUS + (12.0 if n.mode != Mode.NOTE else 5.0), 0.0, TAU, 48, Color(1, 1, 1, 0.35), 1.0, true)
	var label_col := Palette.TEXT_DIM if muted else Palette.TEXT
	draw_string(font, p + Vector2(-NOTE_RADIUS, 5.0), MidiMessage.note_name(n.note),
			HORIZONTAL_ALIGNMENT_CENTER, NOTE_RADIUS * 2.0, 13, label_col)
	var sub := "ch %d" % (n.channel + 1)
	if n.mode == Mode.PULSE:
		sub = "muted · ch %d" % (n.channel + 1)
	draw_string(font, p + Vector2(-NOTE_RADIUS * 2.0, NOTE_RADIUS + 17.0), sub,
			HORIZONTAL_ALIGNMENT_CENTER, NOTE_RADIUS * 4.0, 10, Color(col, 0.7))


func _draw_handle(at: Vector2, col: Color, hovered: bool) -> void:
	var r := HANDLE_RADIUS + (2.0 if hovered else 0.0)
	var pts := PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)])
	draw_colored_polygon(pts, Palette.GLASS.lerp(Palette.YELLOW, 0.35 if hovered else 0.15))
	pts.append(pts[0])
	draw_polyline(pts, Color(Palette.YELLOW, 0.95 if hovered else 0.75), 1.5, true)
	draw_circle(at, 1.6, Color(col, 0.9))


func _draw_dashed(a: Vector2, b: Vector2, col: Color) -> void:
	var length := a.distance_to(b)
	if length < 1.0:
		return
	var dir := (b - a) / length
	var t := NOTE_RADIUS + 4.0
	while t < length - HANDLE_RADIUS:
		draw_line(a + dir * t, a + dir * minf(t + 6.0, length - HANDLE_RADIUS), col, 1.0, true)
		t += 11.0
