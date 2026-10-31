extends Node
## Global MIDI output, autoloaded as `Midi`.
##
## Godot can only *receive* MIDI natively, so output goes through the
## `MidiOutDevice` class from the native extension in addons/midi_out
## (built from native/). If that extension isn't built yet, every message
## is printed to the Output panel instead, so the rest of the app still works.

signal port_changed(port_name: String)
signal message_sent(bytes: PackedByteArray)

const NATIVE_CLASS := "MidiOutDevice"

## Channel used when a call passes channel = -1. 0-15.
var default_channel := 0
## Print messages when no port is open (always true without the native backend).
var log_when_closed := true

var _device: Object = null
var _port_name := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if ClassDB.class_exists(NATIVE_CLASS):
		_device = ClassDB.instantiate(NATIVE_CLASS)
	else:
		push_warning("MIDI: native extension not built; messages will be logged only. See README.md.")


func _exit_tree() -> void:
	panic()
	close_port()


# --- Ports ---------------------------------------------------------------

func has_native_backend() -> bool:
	return _device != null


func backend_name() -> String:
	if _device == null:
		return "log only"
	return _device.get_api_name()


func list_ports() -> PackedStringArray:
	var names := PackedStringArray()
	if _device == null:
		return names
	for i in _device.get_port_count():
		names.append(_device.get_port_name(i))
	return names


func open_port(index: int) -> bool:
	if _device == null:
		return false
	close_port()
	if not _device.open_port(index):
		return false
	_port_name = _device.get_port_name(index)
	port_changed.emit(_port_name)
	return true


## Creates a port other apps can connect to (macOS / Linux only).
func open_virtual_port(port_name: String = "Godot MIDI Driver") -> bool:
	if _device == null:
		return false
	close_port()
	if not _device.open_virtual_port(port_name):
		return false
	_port_name = port_name + " (virtual)"
	port_changed.emit(_port_name)
	return true


func close_port() -> void:
	if _device != null and _device.is_port_open():
		_device.close_port()
	if _port_name != "":
		_port_name = ""
		port_changed.emit("")


func is_open() -> bool:
	return _device != null and _device.is_port_open()


func current_port_name() -> String:
	return _port_name


# --- Sending -------------------------------------------------------------

func send(bytes: PackedByteArray) -> void:
	if is_open():
		_device.send_message(bytes)
	elif log_when_closed:
		print("[MIDI] ", MidiMessage.describe(bytes))
	message_sent.emit(bytes)


func note_on(note: int, velocity: int = 100, channel: int = -1) -> void:
	send(MidiMessage.note_on(_resolve(channel), note, velocity))


func note_off(note: int, channel: int = -1) -> void:
	send(MidiMessage.note_off(_resolve(channel), note))


## Fire-and-forget note with an automatic note-off after `duration` seconds.
func play_note(note: int, velocity: int = 100, duration: float = 0.25, channel: int = -1) -> void:
	var ch := _resolve(channel)
	send(MidiMessage.note_on(ch, note, velocity))
	get_tree().create_timer(duration, true, false, true).timeout.connect(
		func() -> void: send(MidiMessage.note_off(ch, note))
	)


func control_change(controller: int, value: int, channel: int = -1) -> void:
	send(MidiMessage.control_change(_resolve(channel), controller, value))


func program_change(program: int, channel: int = -1) -> void:
	send(MidiMessage.program_change(_resolve(channel), program))


## value is -8192..8191, 0 = centre.
func pitch_bend(value: int, channel: int = -1) -> void:
	send(MidiMessage.pitch_bend(_resolve(channel), value))


func all_notes_off(channel: int = -1) -> void:
	send(MidiMessage.control_change(_resolve(channel), MidiMessage.CC_ALL_NOTES_OFF, 0))


## All notes off + all sound off on every channel. Use when something sticks.
func panic() -> void:
	for ch in 16:
		send(MidiMessage.control_change(ch, MidiMessage.CC_ALL_NOTES_OFF, 0))
		send(MidiMessage.control_change(ch, MidiMessage.CC_ALL_SOUND_OFF, 0))


func _resolve(channel: int) -> int:
	return default_channel if channel < 0 else channel
