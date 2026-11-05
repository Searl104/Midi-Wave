extends Node
## Global MIDI output, autoloaded as `Midi`.
##
## Godot can only *receive* MIDI natively, so output goes through the
## `MidiOutDevice` class from the native extension in addons/midi_out
## (built from native/). If that extension isn't built yet, every message
## is printed to the Output panel instead, so the rest of the app still works.

##
## A note's `channel` value is its Sound: one of 16 numbered colours, called a slot here. Each picks
## a port in Options, and every message goes out on channel 1 of that port. Sounds can share a port.

signal port_changed(port_name: String)
signal message_sent(bytes: PackedByteArray)     ## as addressed to a slot, before routing

const NATIVE_CLASS := "MidiOutDevice"
const SLOTS := 16

## Slot used when a call passes channel = -1. 0-15.
var default_channel := 0
## Print messages when no port is open (always true without the native backend).
var log_when_closed := true

var device_factory: Callable           ## makes a device; tests swap this for a fake
var _probe: Object = null              # lists ports, and is never opened
var _open := {}                        # port name -> open device


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if ClassDB.class_exists(NATIVE_CLASS):
		device_factory = func() -> Object: return ClassDB.instantiate(NATIVE_CLASS)
		_probe = device_factory.call()
	else:
		push_warning("MIDI: native extension not built; messages will be logged only. See README.md.")


func _exit_tree() -> void:
	panic()
	for port in _open.keys():
		_close(port)


## Replaces the backend, for tests.
func use_backend(factory: Callable) -> void:
	for port in _open.keys():
		_close(port)
	device_factory = factory
	_probe = factory.call() if factory.is_valid() else null


# --- Ports ---------------------------------------------------------------

func has_native_backend() -> bool:
	return _probe != null


func backend_name() -> String:
	if _probe == null:
		return "log only"
	return _probe.get_api_name()


func list_ports() -> PackedStringArray:
	var names := PackedStringArray()
	if _probe == null:
		return names
	for i in _probe.get_port_count():
		names.append(_probe.get_port_name(i))
	return names


## Opens every port a slot wants, and closes the rest.
func apply_slots() -> void:
	var wanted := {}
	for port in Settings.midi_slots:
		if port != "":
			wanted[port] = true
	for port in _open.keys():
		if not wanted.has(port):
			_close(port)
	var names := list_ports()
	for port in wanted:
		var index := names.find(port)
		if _open.has(port) or index == -1 or _probe == null:
			continue
		var device: Object = device_factory.call()
		if device.open_port(index):
			_open[port] = device
	port_changed.emit("")


## Points a slot at a port, or at nothing with "". Silences first, as a note held through the change
## would never get its Note Off.
func set_slot(slot: int, port: String) -> void:
	panic()
	Settings.midi_slots[slot] = port
	Settings.set_value("midi_slots", Settings.midi_slots)
	apply_slots()


func _close(port: String) -> void:
	if _open[port].is_port_open():
		_open[port].close_port()
	_open.erase(port)


func is_open() -> bool:
	return not _open.is_empty()


func open_ports() -> PackedStringArray:
	return PackedStringArray(_open.keys())


## Ports a slot wants that aren't open.
func missing_ports() -> PackedStringArray:
	var out := PackedStringArray()
	for port in Settings.midi_slots:
		if port != "" and not _open.has(port) and not out.has(port):
			out.append(port)
	return out


# --- Sending -------------------------------------------------------------

## Sends a channel message to the port of the slot in its channel bits, on channel 1.
func send(bytes: PackedByteArray) -> void:
	var slot := bytes[0] & 0x0F
	var device: Object = _open.get(Settings.midi_slots[slot])
	if device:
		var routed := bytes.duplicate()
		routed[0] = bytes[0] & 0xF0
		device.send_message(routed)
	elif log_when_closed and not is_open():
		print("[MIDI] ", MidiMessage.describe(bytes))
	message_sent.emit(bytes)


## The channel's volume scales the velocity; at 0 the note doesn't sound.
func note_on(note: int, velocity: int = 100, channel: int = -1) -> void:
	var scaled := Settings.channel_velocity(_resolve(channel), velocity)
	if scaled > 0:
		send(MidiMessage.note_on(_resolve(channel), note, scaled))


func note_off(note: int, channel: int = -1) -> void:
	send(MidiMessage.note_off(_resolve(channel), note))


## Fire-and-forget note with an automatic note-off after `duration` seconds.
func play_note(note: int, velocity: int = 100, duration: float = 0.25, channel: int = -1) -> void:
	var ch := _resolve(channel)
	note_on(note, velocity, ch)
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


## All notes off + all sound off on every channel of every open port. Use when something sticks.
func panic() -> void:
	for ch in 16:
		for cc in [MidiMessage.CC_ALL_NOTES_OFF, MidiMessage.CC_ALL_SOUND_OFF]:
			var bytes := MidiMessage.control_change(ch, cc, 0)
			for port in _open:
				_open[port].send_message(bytes)
			if not is_open() and log_when_closed:
				print("[MIDI] ", MidiMessage.describe(bytes))
			message_sent.emit(bytes)


func _resolve(channel: int) -> int:
	return default_channel if channel < 0 else channel
