class_name MidiMessage
extends RefCounted
## Static helpers for building and describing raw MIDI 1.0 messages.
## Channels are 0-15 here (shown to users as 1-16).

const NOTE_OFF := 0x80
const NOTE_ON := 0x90
const POLY_AFTERTOUCH := 0xA0
const CONTROL_CHANGE := 0xB0
const PROGRAM_CHANGE := 0xC0
const CHANNEL_AFTERTOUCH := 0xD0
const PITCH_BEND := 0xE0

const CC_MOD_WHEEL := 1
const CC_VOLUME := 7
const CC_PAN := 10
const CC_EXPRESSION := 11
const CC_SUSTAIN := 64
const CC_ALL_SOUND_OFF := 120
const CC_ALL_NOTES_OFF := 123

const NOTE_NAMES := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


static func note_on(channel: int, note: int, velocity: int) -> PackedByteArray:
	return _three(NOTE_ON, channel, note, velocity)


static func note_off(channel: int, note: int, velocity: int = 0) -> PackedByteArray:
	return _three(NOTE_OFF, channel, note, velocity)


static func control_change(channel: int, controller: int, value: int) -> PackedByteArray:
	return _three(CONTROL_CHANGE, channel, controller, value)


static func program_change(channel: int, program: int) -> PackedByteArray:
	return PackedByteArray([PROGRAM_CHANGE | _ch(channel), clampi(program, 0, 127)])


## value is -8192..8191, 0 = centre.
static func pitch_bend(channel: int, value: int) -> PackedByteArray:
	var v := clampi(value + 8192, 0, 16383)
	return PackedByteArray([PITCH_BEND | _ch(channel), v & 0x7F, (v >> 7) & 0x7F])


static func channel_aftertouch(channel: int, pressure: int) -> PackedByteArray:
	return PackedByteArray([CHANNEL_AFTERTOUCH | _ch(channel), clampi(pressure, 0, 127)])


## "C4" = 60 (the common DAW convention; some apps call 60 "C3").
static func note_name(note: int) -> String:
	return "%s%d" % [NOTE_NAMES[note % 12], (note / 12) - 1]


## Human-readable description, used by the log-only backend and the UI.
static func describe(bytes: PackedByteArray) -> String:
	if bytes.is_empty():
		return "(empty)"
	var status := bytes[0] & 0xF0
	var ch := (bytes[0] & 0x0F) + 1
	var d1 := bytes[1] if bytes.size() > 1 else 0
	var d2 := bytes[2] if bytes.size() > 2 else 0
	match status:
		NOTE_ON:
			if d2 == 0:
				return "ch%d  Note Off  %s" % [ch, note_name(d1)]
			return "ch%d  Note On   %s  vel %d" % [ch, note_name(d1), d2]
		NOTE_OFF:
			return "ch%d  Note Off  %s" % [ch, note_name(d1)]
		CONTROL_CHANGE:
			return "ch%d  CC %d = %d" % [ch, d1, d2]
		PROGRAM_CHANGE:
			return "ch%d  Program %d" % [ch, d1]
		PITCH_BEND:
			return "ch%d  Pitch Bend %d" % [ch, ((d2 << 7) | d1) - 8192]
		CHANNEL_AFTERTOUCH:
			return "ch%d  Aftertouch %d" % [ch, d1]
	return "raw " + bytes.hex_encode()


static func _three(status: int, channel: int, d1: int, d2: int) -> PackedByteArray:
	return PackedByteArray([status | _ch(channel), clampi(d1, 0, 127), clampi(d2, 0, 127)])


static func _ch(channel: int) -> int:
	return clampi(channel, 0, 15)
