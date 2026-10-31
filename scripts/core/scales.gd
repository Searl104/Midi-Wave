class_name Scales
extends RefCounted
## Musical scales and quantization. Notes are MIDI numbers, root is 0-11 (C = 0).

const ROOT_NAMES := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

const SCALES := {
	"Major": [0, 2, 4, 5, 7, 9, 11],
	"Natural Minor": [0, 2, 3, 5, 7, 8, 10],
	"Harmonic Minor": [0, 2, 3, 5, 7, 8, 11],
	"Dorian": [0, 2, 3, 5, 7, 9, 10],
	"Phrygian": [0, 1, 3, 5, 7, 8, 10],
	"Lydian": [0, 2, 4, 6, 7, 9, 11],
	"Mixolydian": [0, 2, 4, 5, 7, 9, 10],
	"Major Pentatonic": [0, 2, 4, 7, 9],
	"Minor Pentatonic": [0, 3, 5, 7, 10],
	"Blues": [0, 3, 5, 6, 7, 10],
	"Whole Tone": [0, 2, 4, 6, 8, 10],
	"Chromatic": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
}

const MIN_OCTAVE := 0
const MAX_OCTAVE := 8


static func names() -> PackedStringArray:
	return PackedStringArray(SCALES.keys())


static func intervals(scale_name: String) -> Array:
	return SCALES.get(scale_name, SCALES["Chromatic"])


static func in_scale(note: int, root: int, scale_name: String) -> bool:
	return intervals(scale_name).has(posmod(note - root, 12))


## Nearest in-scale note; ties resolve downward.
static func quantize(note: int, root: int, scale_name: String) -> int:
	for dist in 7:
		if note - dist >= 0 and in_scale(note - dist, root, scale_name):
			return note - dist
		if note + dist <= 127 and in_scale(note + dist, root, scale_name):
			return note + dist
	return clampi(note, 0, 127)


## Octave number (C4 = 60 convention) of the root-based octave containing `note`.
static func octave_of(note: int, root: int) -> int:
	return floori(float(note - root) / 12.0) - 1


## All scale notes in one root-based octave, clipped to the MIDI range.
static func octave_notes(octave: int, root: int, scale_name: String) -> Array[int]:
	var base := (octave + 1) * 12 + root
	var out: Array[int] = []
	for step in intervals(scale_name):
		var n: int = base + step
		if n >= 0 and n <= 127:
			out.append(n)
	return out
