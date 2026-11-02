class_name PitchTool
extends RingTool
## Outer ring = the scale's notes, inner ring = octave, centre = delete. With no object it places
## a new one, and later picks retune it. Hovering a pitch can preview it.

var _pos := Vector2.ZERO
var _octave := 4
var _channel := 0
var _pitch := -1                   # the current pitch, -1 = none yet
var _previewed := -1


func tool_id() -> String:
	return "pitch"


func title() -> String:
	return "Pitch"


func has_options() -> bool:
	return true


func build_options(box: VBoxContainer) -> void:
	PanelBuilder.section(box, "SCALE", Palette.YELLOW)
	PanelBuilder.pick(box, "Root", "root_note", range(Scales.ROOT_NAMES.size()), Scales.ROOT_NAMES)
	var names: Array = Array(Scales.names())
	PanelBuilder.pick(box, "Scale", "scale_name", names, names)
	box.add_child(PanelBuilder.hint("Sets the notes the ring shows. Existing notes keep their pitch."))


func _prepare(at: Vector2) -> void:
	_pos = at
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
	radial.title = "%s %s · octave %d · ch %d" % [
		Scales.ROOT_NAMES[Settings.root_note], Settings.scale_name, _octave, _channel + 1]
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


## A quaver.
func draw_icon(canvas: CanvasItem, c: Vector2, ink: Color) -> void:
	canvas.draw_circle(c + Vector2(-3, 6), 4.0, ink)
	canvas.draw_line(c + Vector2(0.5, 6), c + Vector2(0.5, -9), ink, 2.0, true)
	canvas.draw_line(c + Vector2(0.5, -9), c + Vector2(6, -4), ink, 2.0, true)
