class_name SongLayout
extends RefCounted
## The Options > Three Blind Mice layout: the song in C, one playable sequence per part, each fired
## by its own keypad key. Play it as KP1 KP1, KP2 KP2, KP3 KP3 KP3, KP4.
##
## A note's height shows its pitch and its row runs in time order. Each note is a relay whose
## diamond sits out past the row: the distance from there to the next note's silent relay is the
## time between them. That relay then fires a short wave on its note, so every note plays at the same
## strength however far the timing wave came. Reaches stop just past the target, so a wave touches
## nothing else. Waves spread every way, so the top row works upward and the bottom row downward,
## keeping each row's waves clear of the other.

const STEP := 180.0                ## space between notes
const PITCH_HEIGHT := 6.0          ## space per semitone
const RELAY_GAP := 50.0            ## silent relays sit this far past the row
const REACH_MARGIN := 1.15         ## enough to arrive under a raised Falloff curve (to about 2.1)
const STRENGTH := 0.8
const SHORTEST := 0.125            ## cooldown in beats, for every relay but a part's first

## [key, row, column, [[pitch, beats until the next note], ...]]
const PARTS := [
	["kp1", 0, 0, [[64, 1.5], [62, 1.5], [60, 0.0]]],                   # Three blind mice
	["kp2", 0, 4, [[67, 1.5], [65, 1.0], [65, 0.5], [64, 0.0]]],        # See how they run
	["kp3", 1, 0, [[67, 0.5], [72, 1.0], [72, 0.5], [71, 0.5], [69, 0.5], [71, 0.5],
			[72, 1.0], [67, 0.5], [67, 0.0]]],                          # They all ran after the farmer's wife
	["kp4", 1, 10, [[65, 0.5], [64, 1.5], [62, 1.5], [60, 0.0]]],       # As three blind mice
]
const ROW_HEIGHT := 300.0

var layout: Array = []             ## in the saved format


func _init() -> void:
	for part in PARTS:
		_part(part[0], Vector2(part[2] * STEP, part[1] * ROW_HEIGHT), part[3])


func _add(pos: Vector2, pitch: int, binding: String, mods: Array) -> int:
	layout.append({"id": layout.size() + 1, "x": pos.x, "y": pos.y, "note": pitch, "channel": 0,
			"binding": binding, "mods": mods})
	return layout.size()


func _relay(sound: bool, emit: Vector2, reach: float, cooldown: float = SHORTEST) -> Dictionary:
	return {"kind": "relay", "sound": sound, "pulse_strength": STRENGTH, "cooldown_beats": cooldown,
			"attached": false, "ex": emit.x, "ey": emit.y, "range": reach}


func _part(key: String, origin: Vector2, notes: Array) -> void:
	var up: bool = origin.y == 0.0
	var away := -1.0 if up else 1.0            # the side the timing waves work on
	var top_note := -(72 - 60) * PITCH_HEIGHT  # the song's highest pitch sits here
	var length := 0.0
	for n in notes:
		length += n[1]
	var row: float = origin.y + (top_note - RELAY_GAP if up else RELAY_GAP)
	for i in notes.size():
		var x: float = origin.x + i * STEP
		var pitch: int = notes[i][0]
		var at := Vector2(x, origin.y - (pitch - 60) * PITCH_HEIGHT)
		var distance: float = notes[i][1] * Settings.BEAT_UNIT
		var mods: Array = []
		if distance > 0.0:
			# The timing wave: from past the next note's relay, straight back to it.
			mods = [_relay(true, Vector2(x + STEP, row + away * distance), distance * REACH_MARGIN, length + 1.5 if i == 0 else SHORTEST)]
		_add(at, pitch, key if i == 0 else "", mods)
		if i > 0:
			_add(Vector2(x, row), pitch, "", [_relay(false, at, 30.0)])
