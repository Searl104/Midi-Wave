class_name MidiMappings
extends RefCounted
## MIDI messages that run app actions, learned in Options > Controls. Mappings are saved in Settings
## as action -> key, where a key is "note60", "cc20", or "rt252" for a transport message. One
## message drives one action, and any channel matches.

signal triggered(action: String)
signal changed                     ## a mapping or `listening` changed

const ACTIONS := {"stop": "Stop", "save_state": "Save state", "panic": "Panic"}
const TIPS := {
	"stop": "Clears every wave and returns rests to their start count.",
	"save_state": "Makes every rest's current count its start count.",
	"panic": "Stops every sounding note on all channels.",
}
const DEFAULTS := {"stop": "rt252"}
const TRANSPORT := {250: "MIDI Start", 251: "MIDI Continue", 252: "MIDI Stop"}

var listening := ""                ## the action waiting for a message, or ""
var _surface: WaveSurface


func _init(surface: WaveSurface) -> void:
	_surface = surface


func key_for(action: String) -> String:
	return str(Settings.midi_mappings.get(action, ""))


## A message arrived: it's learned if an action is listening, otherwise it runs its action.
func receive(key: String) -> void:
	if listening != "":
		var action := listening
		listening = ""
		assign(action, key)
		return
	for action in ACTIONS:
		if key_for(action) == key:
			triggered.emit(action)
			return


func listen(action: String) -> void:
	listening = action
	changed.emit()


func cancel() -> void:
	if listening != "":
		listening = ""
		changed.emit()


## Maps `key` to `action`, taking it from any other action.
func assign(action: String, key: String) -> void:
	var mappings: Dictionary = Settings.midi_mappings.duplicate()
	for other in mappings:
		if mappings[other] == key:
			mappings[other] = ""
	mappings[action] = key
	Settings.set_value("midi_mappings", mappings)
	changed.emit()


func clear(action: String) -> void:
	var mappings: Dictionary = Settings.midi_mappings.duplicate()
	mappings[action] = ""
	Settings.set_value("midi_mappings", mappings)
	changed.emit()


func reset() -> void:
	listening = ""
	Settings.set_value("midi_mappings", DEFAULTS.duplicate())
	changed.emit()


## How many notes are bound to the same message, and so fire along with the mapping.
func bound_notes(key: String) -> int:
	if not key.begins_with("note"):
		return 0
	var binding := "midi" + key.trim_prefix("note")
	return _surface.notes.filter(func(o: Note) -> bool: return o.binding == binding).size()


## What a key is called on screen.
static func label(key: String) -> String:
	if key.begins_with("note"):
		return "Note " + MidiMessage.note_name(key.trim_prefix("note").to_int())
	if key.begins_with("cc"):
		return "CC " + key.trim_prefix("cc")
	if key.begins_with("rt"):
		return TRANSPORT.get(key.trim_prefix("rt").to_int(), "")
	return "Not set"
