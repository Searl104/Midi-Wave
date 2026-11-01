class_name MidiInput
extends Node
## MIDI-input triggering (R7): pads on a controller fire the keypad slots.
##
## Uses Godot's own MIDI input (no native extension). Godot can only open every MIDI input at
## once, so inputs stay closed until a controller is chosen in Options; events from any other
## input (including the loopMIDI port this app sends to) are ignored. Notes base..base+8 fire
## slots 1-9: note-on presses the slot, note-off (or note-on at velocity 0) releases it, so
## holding a pad refires its pulsers like holding the key. "Learn" sets base to the next pad hit.

signal slot_pressed(slot: int)
signal slot_released(slot: int)
signal learned(base: int)

var learning := false
var _names: PackedStringArray = []      ## names of the open inputs; event.device indexes this


func _ready() -> void:
	apply()
	Settings.changed.connect(func(key: String) -> void:
		if key == "midi_in_port":
			apply())


## Lists the MIDI inputs. Opening them is the only way to read their names, so they are closed
## again afterwards unless a controller is in use.
static func list_inputs() -> PackedStringArray:
	OS.open_midi_inputs()
	var names := OS.get_connected_midi_inputs()
	if Settings.midi_in_port == "":
		OS.close_midi_inputs()
	return names


## Opens the inputs when a controller is chosen, closes them when it's Off.
func apply() -> void:
	if Settings.midi_in_port == "":
		OS.close_midi_inputs()
		_names = []
	else:
		OS.open_midi_inputs()
		_names = OS.get_connected_midi_inputs()


func is_listening() -> bool:
	return Settings.midi_in_port != "" and _names.has(Settings.midi_in_port)


## The slot (1-9) a note fires, or 0.
static func slot_for(pitch: int) -> int:
	var s := pitch - Settings.midi_in_base + 1
	return s if s >= 1 and s <= 9 else 0


func _input(event: InputEvent) -> void:
	var ev := event as InputEventMIDI
	if ev and handle(ev):
		get_viewport().set_input_as_handled()


## Returns true if the event came from the chosen controller and was a note.
func handle(ev: InputEventMIDI) -> bool:
	if Settings.midi_in_port == "" or ev.device < 0 or ev.device >= _names.size() \
			or _names[ev.device] != Settings.midi_in_port:
		return false
	var on := ev.message == MIDI_MESSAGE_NOTE_ON and ev.velocity > 0
	var off := ev.message == MIDI_MESSAGE_NOTE_OFF or (ev.message == MIDI_MESSAGE_NOTE_ON and ev.velocity == 0)
	if not on and not off:
		return false
	if learning and on:
		learning = false
		Settings.set_value("midi_in_base", clampi(ev.pitch, 0, 119))
		learned.emit(Settings.midi_in_base)
		return true
	var slot := slot_for(ev.pitch)
	if slot == 0:
		return true
	if on:
		slot_pressed.emit(slot)
	else:
		slot_released.emit(slot)
	return true
