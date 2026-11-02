class_name SurfaceObject
extends RefCounted
## Something placed on the surface that waves can hit. Note and Relay are the two kinds.
##
## Every object has an Emitter, used only by a Relay: a Note keeps its emitter dormant, so
## switching type keeps its pulse settings, and a Relay keeps its pitch for the same reason.
## A pulsing object's sensor is the object; its emitter is where the wave starts.

enum Mode { NOTE = 0, RELAY = 2 }   # 1 was the old note + pulse hybrid
const LEGACY_NOTE_PULSE := 1
const RADIUS := 22.0

var id := 0
var pos := Vector2.ZERO            ## world units
var note := 60                     ## MIDI pitch
var channel := 0
var muted := false                 ## no sound and no pulse; the type is kept
var slot := 0                      ## keypad trigger slot 1-9, 0 = none
var snap_note := ""                ## target last snapped to when dropped
var grid: Grid = null              ## snap grid centred here, if on
var modifier: Modifier = null      ## acts on each hit, at most one
var emitter := Emitter.new()

var flash := 0.0
var dim_flash := 0.0               ## a silenced hit
var playing := false
var off_at := 0

var mode: int:
	get:
		return _mode()


static func create(type: int) -> SurfaceObject:
	return Relay.new() if type == Mode.RELAY else Note.new()


func _mode() -> int:
	return Mode.NOTE


## A new object of type `type` carrying everything this one has.
func converted(type: int) -> SurfaceObject:
	var o := SurfaceObject.create(type)
	for key in ["id", "pos", "note", "channel", "muted", "slot", "snap_note", "grid", "modifier", "emitter",
			"flash", "dim_flash", "playing", "off_at"]:
		o.set(key, get(key))
	return o


func mod_kind() -> String:
	return modifier.kind() if modifier else ""


## Reads a saved layout entry; `p` is its position.
func load_dict(d: Dictionary, p: Vector2) -> void:
	slot = clampi(int(d.get("slot", 0)), 0, 9)
	muted = bool(d.get("muted", false))
	grid = Grid.new() if bool(d.get("grid", false)) else null
	snap_note = str(d.get("snap_note", ""))
	emitter.load_dict(d, p)
	modifier = Modifier.create(str(d.get("mod", "")))
	if modifier:
		modifier.set_start(bool(d.get("mod_start", true)))


func to_dict() -> Dictionary:
	return {
		"x": pos.x, "y": pos.y, "note": note, "channel": channel,
		"mode": mode, "pulse_strength": emitter.strength, "cooldown_beats": emitter.cooldown,
		"attached": emitter.attached, "ex": emitter.pos.x, "ey": emitter.pos.y,
		"mod": mod_kind(), "mod_start": modifier.start if modifier else true,
		"id": id, "snap_note": snap_note, "snap_emit": emitter.snap, "slot": slot, "range": emitter.own_reach, "muted": muted,
		"grid": grid != null, "grid_emit": emitter.grid != null,
	}


# --- Hits ----------------------------------------------------------------------------------

## A wave reached this object. The modifier decides whether it acts on this hit.
func hit(surface: WaveSurface, amp: float, now: int, spawned: Array) -> void:
	if modifier and not modifier.passes_hit():
		dim_flash = 1.0              # silenced: no sound, no pulse
		return
	if muted:
		dim_flash = 1.0              # muted: no sound and no pulse (a toggle still advances)
		return
	_act(surface, amp, now, spawned)


## What this object does when a hit gets through.
func _act(_surface: WaveSurface, _amp: float, _now: int, _spawned: Array) -> void:
	pass


## A click, or a keypad slot firing this object.
func clicked(_surface: WaveSurface) -> void:
	pass


## Tapped with the Tap tool: a hit of its own, at click strength with no wave, that overrides mute.
func tap(surface: WaveSurface) -> void:
	if modifier and not modifier.passes_hit():
		dim_flash = 1.0
		return
	var spawned: Array = []
	_act(surface, Settings.wave_strength, surface.clock_usec, spawned)
	surface.waves.append_array(spawned)


func play(surface: WaveSurface, amp: float, now: int) -> void:
	var velocity := clampi(roundi(amp * 127.0), 1, 127)
	if playing:
		Midi.note_off(note, channel)
	Midi.note_on(note, velocity, channel)
	playing = true
	off_at = now + int(Settings.note_length_for(channel) * 1_000_000.0)
	flash = maxf(flash, 0.35 + amp * 0.65)
	surface.effects.add_splash(pos, Palette.channel_color(channel), amp)


func silence() -> void:
	if playing:
		Midi.note_off(note, channel)
		playing = false


## Stop: back to the modifier's start state.
func reset() -> void:
	if modifier:
		modifier.reset()
	dim_flash = 0.0


func tick(delta: float, now: int) -> void:
	if playing and now >= off_at:
		Midi.note_off(note, channel)
		playing = false
	flash = maxf(0.0, flash - delta * 2.5)
	emitter.tick(delta)
	if modifier:
		modifier.tick(delta)
	dim_flash = maxf(0.0, dim_flash - delta * 3.0)


# --- Description ---------------------------------------------------------------------------

## Whether the pitch shows, on the surface and in the tooltip.
func shows_pitch() -> bool:
	return true


func _title_text() -> String:
	return "%s · ch %d" % [MidiMessage.note_name(note), channel + 1]


func _pulse_text() -> String:
	return ""


func _reach_text() -> String:
	return ""


## Tooltip text: pitch, channel and state.
func hover_text() -> String:
	var text := _title_text() + _pulse_text()
	if muted:
		text += " · muted"
	if modifier:
		text += modifier.describe()
	text += _reach_text()
	if slot > 0:
		text += " · key %d" % slot
	return text


# --- Drawing -------------------------------------------------------------------------------

## Half the side of the bracket box: clear of the pulse and modifier rings and badges.
func bracket_half() -> float:
	if modifier:
		return RADIUS + Modifier.RING + 6.0
	return RADIUS + _bracket_margin()


func _bracket_margin() -> float:
	return 7.0


## Drawn with no fill; a Relay always is, and so is anything muted.
func _hollow() -> bool:
	return muted


func _draw_pulse_ring(_surface: WaveSurface, _p: Vector2, _now: int) -> void:
	pass


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
		surface.draw_arc(p, RADIUS - 6.0, PI * 1.05, PI * 1.6, 18, Color(1, 1, 1, 0.22), 2.0, true)  # highlight
	surface.draw_arc(p, RADIUS, 0.0, TAU, 48, Color(col.lerp(Color.WHITE, f * 0.5), 0.45 if hollow else 1.0), 2.5, true)
	if Palette.channel_marked(channel):
		surface.draw_arc(p, RADIUS - 4.5, 0.0, TAU, 40, Color(col, 0.45 if hollow else 0.9), 1.5, true)
	if muted:
		# Muted: a slash, so it reads differently from a hollow relay.
		var sl := Vector2(1, -1).normalized() * (RADIUS - 3.0)
		surface.draw_line(p - sl, p + sl, Color(col, 0.85), 2.0, true)

	_draw_pulse_ring(surface, p, now)

	var label_col := Palette.TEXT_DIM if (hollow or (modifier and modifier.dims_label())) else Palette.TEXT
	if shows_pitch():
		surface.draw_string(font, p + Vector2(-RADIUS, 5.0), MidiMessage.note_name(note),
				HORIZONTAL_ALIGNMENT_CENTER, RADIUS * 2.0, 13, label_col)
	if dim_flash > 0.0:
		surface.draw_circle(p, RADIUS + 4.0, Color(1, 1, 1, 0.12 * dim_flash))     # a silenced hit
	if modifier:
		modifier.draw(surface, p, col)
	if slot > 0:
		# Keypad slot badge, top left (opposite the emitter handle).
		var out := RADIUS + (Modifier.RING + 8.0 if modifier else 8.0)
		var b := p + Vector2(-1, -1).normalized() * out
		surface.draw_circle(b, 8.0, Color(0.075, 0.08, 0.11, 1.0))
		surface.draw_arc(b, 8.0, 0.0, TAU, 24, Color(1, 1, 1, 0.35), 1.0, true)
		surface.draw_string(font, b + Vector2(-8, 4), str(slot), HORIZONTAL_ALIGNMENT_CENTER, 16, 11, Palette.TEXT)


## Off screen and firing: a marker on the nearest window edge.
func draw_edge_marker(surface: WaveSurface) -> void:
	var f: float = maxf(flash, emitter.pulse_flash)
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
