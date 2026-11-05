class_name Note
extends RefCounted
## An object on the surface: it plays its pitch when a wave hits it. Modifiers change what a hit
## does; a RelayModifier makes it fire a new wave, and can silence its sound.

const RADIUS := 22.0

var id := 0
var pos := Vector2.ZERO            ## world units
var note := 60                     ## MIDI pitch
var channel := 0
var velocity := 100                ## 1-100: the share of a hit's strength it plays at
var muted := false                 ## no sound and no pulse from waves
var binding := ""                  ## what fires it: "kp0"-"kp9", "midi<note>", or "" for none
var snap_note := ""                ## target last snapped to when dropped
var grid: Grid = null              ## snap grid centred here, if on
var modifiers: Array[Modifier] = []

var flash := 0.0
var dim_flash := 0.0               ## a silenced hit
var playing := false
var off_at := 0


func get_modifier(kind: String) -> Modifier:
	for m in modifiers:
		if m.kind() == kind:
			return m
	return null


func relay() -> RelayModifier:
	return get_modifier("relay") as RelayModifier


## The relay's emitter, or null without a relay.
func emitter() -> Emitter:
	var r := relay()
	return r.emitter if r else null


## False when a relay's Sound is off.
func sounds() -> bool:
	var r := relay()
	return r == null or r.sound


## How far this note's grid reaches: its own, else a docked relay's wave, else a beat past the
## global Reach.
func grid_limit() -> float:
	if grid and grid.reach > 0.0:
		return grid.reach
	var e := emitter()
	if e and e.attached:
		return e.reach()
	return Settings.wave_range + Settings.BEAT_UNIT


## True if a modifier draws a ring around the note.
func has_ring() -> bool:
	for m in modifiers:
		if m.has_ring():
			return true
	return false


## Adds a modifier, keeping sequences ahead of the relay they gate.
func add_modifier(m: Modifier) -> void:
	modifiers.append(m)
	modifiers.sort_custom(func(a: Modifier, b: Modifier) -> bool: return a.order() < b.order())


## Reads a saved layout entry; `p` is its position. Saves before modifier lists used "mode"
## (2 = relay, 1 = the old note + pulse hybrid) and a single "mod".
func load_dict(d: Dictionary, p: Vector2) -> void:
	binding = str(d.get("binding", ""))
	var old_slot := clampi(int(d.get("slot", 0)), 0, 9)     # saves before bindings had slots 1-9
	if old_slot > 0:
		binding = "kp%d" % old_slot
	muted = bool(d.get("muted", false))
	velocity = clampi(int(d.get("velocity", 100)), 1, 100)
	grid = Grid.new() if bool(d.get("grid", false)) else null
	if grid:
		grid.reach = maxf(float(d.get("grid_reach", 0.0)), 0.0)
	snap_note = str(d.get("snap_note", ""))
	modifiers.clear()
	if d.has("mods"):
		for md in d["mods"]:
			var m := Modifier.create(str(md.get("kind", "")))
			if m:
				m.load_dict(md, p)
				add_modifier(m)
		return
	var sequence := Modifier.create(str(d.get("mod", "")))
	if sequence:
		sequence.load_dict({"steps": d.get("mod_steps"), "start": d.get("mod_start", true)}, p)
		add_modifier(sequence)
	var mode := int(d.get("mode", 0))
	if mode == 1 or mode == 2:
		var r := RelayModifier.new()
		var legacy := d.duplicate()
		legacy["sound"] = mode == 1
		r.load_dict(legacy, p)
		add_modifier(r)


func to_dict() -> Dictionary:
	var mods: Array = []
	for m in modifiers:
		mods.append(m.to_dict())
	return {
		"x": pos.x, "y": pos.y, "note": note, "channel": channel, "mods": mods,
		"id": id, "snap_note": snap_note, "binding": binding, "muted": muted, "velocity": velocity, "grid": grid != null, "grid_reach": grid.reach if grid else 0.0,
	}


# --- Hits ----------------------------------------------------------------------------------

## Every modifier gets the hit (a sequence steps on), and any can silence it.
func _passes_modifiers() -> bool:
	var passes := true
	for m in modifiers:
		passes = m.passes_hit() and passes
	return passes


## A wave reached this object, and has since travelled `overshoot` further.
func hit(surface: WaveSurface, amp: float, now: int, spawned: Array, overshoot: float = 0.0) -> void:
	if not _passes_modifiers():
		dim_flash = 1.0              # silenced: no sound, no pulse
		return
	if muted:
		dim_flash = 1.0              # muted: no sound and no pulse (a sequence still steps on)
		return
	_act(surface, amp, now, spawned, overshoot)


func _act(surface: WaveSurface, amp: float, now: int, spawned: Array, overshoot: float = 0.0) -> void:
	if sounds():
		play(surface, amp, now)
	var r := relay()
	if r:
		r.emitter.fire(surface, self, now, spawned, overshoot)


## Tapped, or fired by its binding: a hit of its own, at click strength with no wave, that overrides mute.
func tap(surface: WaveSurface) -> void:
	if not _passes_modifiers():
		dim_flash = 1.0
		return
	var spawned: Array = []
	_act(surface, Settings.wave_strength, surface.clock_usec, spawned)
	surface.waves.append_array(spawned)


func play(surface: WaveSurface, amp: float, now: int) -> void:
	var midi_velocity := clampi(roundi(amp * velocity / 100.0 * 127.0), 1, 127)
	if playing:
		Midi.note_off(note, channel)
	Midi.note_on(note, midi_velocity, channel)
	playing = true
	off_at = now + int(Settings.note_length_for(channel) * 1_000_000.0)
	flash = maxf(flash, 0.35 + amp * 0.65)
	surface.effects.add_splash(pos, Palette.channel_color(channel), amp)


func silence() -> void:
	if playing:
		Midi.note_off(note, channel)
		playing = false


## Stop: back to each modifier's start state.
func reset() -> void:
	for m in modifiers:
		m.reset()
	dim_flash = 0.0


func tick(delta: float, now: int) -> void:
	if playing and now >= off_at:
		Midi.note_off(note, channel)
		playing = false
	flash = maxf(0.0, flash - delta * 2.5)
	for m in modifiers:
		m.tick(delta)
	dim_flash = maxf(0.0, dim_flash - delta * 3.0)


# --- Description ---------------------------------------------------------------------------

## Whether the pitch shows, on the surface and in the tooltip.
func shows_pitch() -> bool:
	return sounds()


## Tooltip text: pitch, channel and state.
func hover_text() -> String:
	var text := "%s · sound %d" % [MidiMessage.note_name(note), channel + 1] if sounds() else "relay · sound %d" % (channel + 1)
	var r := relay()
	if r and r.emitter.is_retrigger():
		text += " · retrigger"
	if muted:
		text += " · muted"
	if velocity < 100:
		text += " · velocity %d%%" % velocity
	for m in modifiers:
		text += m.describe()
	if r and r.emitter.own_reach > 0.0:
		text += " · reach " + Snapping.format_beats(r.emitter.own_reach / Settings.BEAT_UNIT)
	if binding != "":
		text += " · " + ("MIDI " if binding.begins_with("midi") else "KP") + binding_label()
	return text


# --- Drawing -------------------------------------------------------------------------------

## Half the side of the bracket box: clear of the pulse and modifier rings and badges.
func bracket_half() -> float:
	if has_ring():
		return RADIUS + Modifier.RING + 6.0
	return RADIUS + (11.0 if relay() else 7.0)


## Drawn with no fill: anything muted, or silent because of its relay.
func _hollow() -> bool:
	return muted or not sounds()


## A subtle tint rising from the bottom of the note, as high as its velocity.
func _draw_velocity_fill(surface: WaveSurface, p: Vector2, col: Color) -> void:
	var r := RADIUS - 1.0
	var top := asin(clampf(1.0 - 2.0 * velocity / 100.0, -1.0, 1.0))
	var points := PackedVector2Array()
	for i in 25:
		points.append(p + Vector2.from_angle(lerpf(top, PI - top, i / 24.0)) * r)
	surface.draw_colored_polygon(points, Color(col, 0.2))


func draw(surface: WaveSurface, font: Font, now: int) -> void:
	var p := surface.to_screen(pos)
	var col := Palette.channel_color(channel)
	var f := flash
	var hollow := _hollow()

	if f > 0.0:
		surface.draw_circle(p, RADIUS + 16.0 * f, Color(col, 0.18 * f))
		surface.draw_circle(p, RADIUS + 7.0 * f, Color(col, 0.25 * f))
	surface.draw_circle(p, RADIUS + 3.0, Color(0, 0, 0, 0.35))                                   # shadow
	if hollow:
		surface.draw_circle(p, RADIUS, Color(Palette.BG, 0.9))                                    # hollow
		# Centre dot doubles as the mute indicator: bright on an unmuted relay.
		surface.draw_circle(p, RADIUS * 0.35, Color(col, 0.18 if muted else 0.9))
	else:
		surface.draw_circle(p, RADIUS, Palette.GLASS.lerp(col, 0.12 + f * 0.35))                  # body
		_draw_velocity_fill(surface, p, col)
		surface.draw_arc(p, RADIUS - 6.0, PI * 1.05, PI * 1.6, 18, Color(1, 1, 1, 0.22), 2.0, true)  # highlight
	surface.draw_arc(p, RADIUS, 0.0, TAU, 48, Color(col.lerp(Color.WHITE, f * 0.5), 0.45 if hollow else 1.0), 2.5, true)
	if Palette.channel_marked(channel):
		surface.draw_arc(p, RADIUS - 4.5, 0.0, TAU, 40, Color(col, 0.45 if hollow else 0.9), 1.5, true)
	if muted:
		# Muted: a slash, so it reads differently from a hollow relay.
		var sl := Vector2(1, -1).normalized() * (RADIUS - 3.0)
		surface.draw_line(p - sl, p + sl, Color(col, 0.85), 2.0, true)

	var r := relay()
	if r:
		r.emitter.draw_pulse_ring(surface, p, now)

	var dimmed := hollow
	for m in modifiers:
		dimmed = dimmed or m.dims_label()
	var label_col := Palette.TEXT_DIM if dimmed else Palette.TEXT
	if shows_pitch():
		surface.draw_string(font, p + Vector2(-RADIUS, 5.0), MidiMessage.note_name(note),
				HORIZONTAL_ALIGNMENT_CENTER, RADIUS * 2.0, 13, label_col)
	if dim_flash > 0.0:
		surface.draw_circle(p, RADIUS + 4.0, Color(1, 1, 1, 0.12 * dim_flash))     # a silenced hit
	for m in modifiers:
		m.draw(surface, p, col)
	if binding != "":
		# Binding badge, top left (opposite the emitter handle). Wider for a MIDI note name.
		var out := RADIUS + (Modifier.RING + 8.0 if has_ring() else 8.0)
		var b := p + Vector2(-1, -1).normalized() * out
		var label := binding_label()
		var half := 8.0 if label.length() == 1 else 12.0
		var box := Rect2(b - Vector2(half, 8), Vector2(half * 2.0, 16))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.075, 0.08, 0.11, 1.0)
		sb.border_color = Color(1, 1, 1, 0.35)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(8)
		sb.anti_aliasing = true
		surface.draw_style_box(sb, box)
		surface.draw_string(font, b + Vector2(-half, 4), label, HORIZONTAL_ALIGNMENT_CENTER, half * 2.0, 11, Palette.TEXT)


## What the badge shows: the keypad digit, or the MIDI note's name.
func binding_label() -> String:
	if binding.begins_with("kp"):
		return binding.substr(2)
	return MidiMessage.note_name(int(binding.substr(4)))


## The modifier whose tab is at a screen position, or null.
func tab_at(surface: WaveSurface, at: Vector2) -> Modifier:
	for m in modifiers:
		if m.tab_contains(surface, self, at):
			return m
	return null


## The faint preview of a note about to be placed: pitch, channel colour, and marks for modifiers.
func draw_ghost(surface: WaveSurface, p: Vector2) -> void:
	var col := Palette.channel_color(channel)
	if sounds() and not muted:
		surface.draw_circle(p, RADIUS, Color(Palette.GLASS.lerp(col, 0.12), 0.4))
	surface.draw_arc(p, RADIUS, 0.0, TAU, 48, Color(col, 0.5), 2.0, true)
	if relay():
		surface.draw_arc(p, RADIUS + 5.0, 0.0, TAU, 48, Color(Palette.YELLOW, 0.4), 1.5, true)
		var d := p + Vector2(1, -1).normalized() * (RADIUS + (Modifier.RING + 8.0 if has_ring() else 9.0))
		var r := Emitter.HANDLE_RADIUS
		surface.draw_polyline(PackedVector2Array([d + Vector2(0, -r), d + Vector2(r, 0), d + Vector2(0, r), d + Vector2(-r, 0), d + Vector2(0, -r)]),
				Color(Palette.YELLOW, 0.5), 1.5, true)
	if has_ring():
		surface.draw_arc(p, RADIUS + Modifier.RING, 0.0, TAU, 56, Color(col, 0.4), 1.0, true)
	if shows_pitch():
		surface.draw_string(surface.get_theme_default_font(), p + Vector2(-RADIUS, 5.0), MidiMessage.note_name(note),
				HORIZONTAL_ALIGNMENT_CENTER, RADIUS * 2.0, 13, Color(Palette.TEXT, 0.6))


## Off screen and firing: a marker on the nearest window edge.
func draw_edge_marker(surface: WaveSurface) -> void:
	var e := emitter()
	var f: float = maxf(flash, e.pulse_flash if e else 0.0)
	if f <= 0.01:
		return
	var p := surface.to_screen(pos)
	var inner := Rect2(Vector2.ZERO, surface.size).grow(-WaveSurface.EDGE_INSET)
	var at := p.clamp(inner.position, inner.end)
	var dir := (p - at).normalized()
	var col := Palette.channel_color(channel)
	surface.draw_circle(at, 6.0 + 6.0 * f, Color(col, 0.18 * f))
	surface.draw_circle(at, 4.0, Color(col, 0.5 + 0.5 * f))
	var tip := at + dir * 11.0
	var side := dir.orthogonal() * 4.0
	surface.draw_colored_polygon(PackedVector2Array([tip, at + dir * 5.0 + side, at + dir * 5.0 - side]), Color(col, 0.8 * f + 0.2))


func draw_tooltip(surface: WaveSurface, font: Font) -> void:
	var text := hover_text()
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 30.0
	var at := surface.to_screen(pos) + Vector2(RADIUS + 18.0, -RADIUS - 26.0)
	at.x = clampf(at.x, 8.0, surface.size.x - w - 8.0)
	at.y = clampf(at.y, 8.0, surface.size.y - 30.0)
	var box := Rect2(at, Vector2(w, 24))
	surface.draw_rect(box, Color(Palette.GLASS, 0.94))
	surface.draw_rect(box, Color(1, 1, 1, 0.12), false, 1.0)
	surface.draw_circle(at + Vector2(12, 12), 4.0, Palette.channel_color(channel))
	surface.draw_string(font, at + Vector2(22, 16), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.TEXT)
