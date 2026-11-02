class_name PitchTool
extends RingTool
## Outer ring = the scale's notes, inner ring = octave, centre = delete. With no object it places
## a new one, and later picks retune it. Hovering a pitch can preview it.

const DIGIT_WINDOW_MS := 600       ## time allowed for the second digit of a channel number

var _pos := Vector2.ZERO
var _octave := 4
var _channel := 0
var _pitch := -1                   # the current pitch, -1 = none yet
var _digit_first := -1             # first digit of a possible 10-16, or -1
var _digit_time := 0
var _previewed := -1


func tool_id() -> String:
	return "pitch"


func title() -> String:
	return "Pitch"


func _prepare(at: Vector2) -> void:
	_pos = at
	_digit_first = -1
	_previewed = -1
	var current := surface.last_pitch
	_channel = surface.last_channel
	_pitch = -1
	var o := surface.get_note(note_id)
	if o:
		current = o.note
		_channel = o.channel
		_pitch = o.note
	_octave = clampi(Scales.octave_of(current, Settings.root_note), 1, 7)
	radial.center_item = {"id": "delete", "label": "Del", "color": Palette.RED} if note_id >= 0 else {}


func build() -> void:
	var col := Palette.channel_color(_channel)
	radial.outer_items = []
	for n in Scales.octave_notes(_octave, Settings.root_note, Settings.scale_name):
		radial.outer_items.append({"id": n, "label": MidiMessage.note_name(n), "color": col, "selected": n == _pitch})
	radial.inner_items = []
	for o in range(1, 8):
		radial.inner_items.append({"id": o, "label": str(o), "color": Palette.YELLOW, "selected": o == _octave})
	var ch_text := "ch %d" % (_channel + 1)
	if _digit_first != -1 and Time.get_ticks_msec() - _digit_time <= DIGIT_WINDOW_MS:
		ch_text += "…"                  # waiting for a second digit (10-16)
	radial.title = "%s %s · octave %d · %s" % [
		Scales.ROOT_NAMES[Settings.root_note], Settings.scale_name, _octave, ch_text]
	radial.subtitle = ""
	radial.refresh()


func hovered(ring: String, id: Variant) -> void:
	_previewed = -1
	if ring != "outer" or not Settings.hover_preview:
		return
	var pitch: int = id
	Midi.play_note(pitch, 80, 0.25, _channel)
	_previewed = pitch


func pick_outer(id: Variant) -> void:
	var pitch: int = id
	if note_id == -1:
		# Placed. Further picks retune this object.
		note_id = surface.add_note_at(_pos, pitch, _channel)
		radial.center_item = {"id": "delete", "label": "Del", "color": Palette.RED}
	else:
		surface.set_note_pitch(note_id, pitch)
		if surface.get_note(note_id).channel != _channel:
			surface.set_note_channel(note_id, _channel)
	if pitch != _previewed:
		Midi.play_note(pitch, 90, 0.25, _channel)   # already heard on hover otherwise
	_pitch = pitch
	build()


func pick_inner(id: Variant) -> void:
	set_octave(id)


func pick_center(id: Variant) -> void:
	if note_id != -1 and id == "delete":
		surface.remove_note(note_id)
		radial.close()                   # nothing left to edit


## Moves up or down an octave.
func step_octave(direction: int) -> void:
	set_octave(_octave + direction)


## The note keeps its letter (A, C#, ...) and moves to the new octave.
func set_octave(octave: int) -> void:
	var old := _octave
	_octave = clampi(octave, 1, 7)
	if _pitch != -1 and _octave != old:
		var moved := _pitch + 12 * (_octave - old)
		if moved >= 0 and moved <= 127:
			_pitch = moved
			if note_id != -1 and surface.get_note(note_id):
				surface.set_note_pitch(note_id, moved)
				Midi.play_note(moved, 90, 0.25, _channel)
	build()


## Two-digit channel typing: 1-9 apply at once; a quick second digit makes 10-16
## (1 then 2 = 12); any other second digit starts over.
func type_digit(d: int) -> void:
	var now := Time.get_ticks_msec()
	if _digit_first != -1 and now - _digit_time <= DIGIT_WINDOW_MS:
		var v := _digit_first * 10 + d
		_digit_first = -1
		if v >= 10 and v <= 16:
			_channel = v - 1
			build()
			return
	if d >= 1 and d <= 9:
		_channel = d - 1
		_digit_first = d if d == 1 else -1     # only "1" can start 10-16
		_digit_time = now
		build()
		if _digit_first != -1:
			# Show "ch 1…" while a second digit can still follow, then settle on "ch 1".
			surface.get_tree().create_timer(DIGIT_WINDOW_MS / 1000.0 + 0.02).timeout.connect(func() -> void:
				if radial.visible and surface.tools.open_ring == self and Time.get_ticks_msec() - _digit_time > DIGIT_WINDOW_MS:
					build())


## A quaver.
func draw_icon(canvas: CanvasItem, c: Vector2, ink: Color) -> void:
	canvas.draw_circle(c + Vector2(-3, 6), 4.0, ink)
	canvas.draw_line(c + Vector2(0.5, 6), c + Vector2(0.5, -9), ink, 2.0, true)
	canvas.draw_line(c + Vector2(0.5, -9), c + Vector2(6, -4), ink, 2.0, true)
