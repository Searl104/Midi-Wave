class_name MidiInput
extends Node
## MIDI input: Note On and Note Off from the chosen controller.
##
## Uses Godot's own MIDI input (no native extension). Godot can only open every MIDI input at
## once, so inputs stay closed until a controller is chosen in Options; events from any other
## input (including the loopMIDI port this app sends to) are ignored. A Note On at velocity 0
## counts as a Note Off. Any channel matches.

signal note_pressed(pitch: int)
signal note_released(pitch: int)

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
	if on:
		note_pressed.emit(ev.pitch)
	else:
		note_released.emit(ev.pitch)
	return true
