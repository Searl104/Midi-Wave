class_name DemoLayout
extends RefCounted
## The Options > Test layout: six groups, one per feature, three across and two down.
##
##   Channels and falloff | Toggles       | Mute
##   Cooldowns            | Stacked chain | Grids and slots
##
## Each group is driven by its own pair of relays, which fire at each other. Their reach stops
## short of the next group, so groups don't set each other off. Firing one of each pair
## (`starters`) sets them all going; Stop ends it. Pitches come from the current scale.

const NOTE := 0
const RELAY := 2                   ## a silent relay, in the older saved format this writes

var layout: Array = []             ## in a saved format
var starters: Array = []           ## ids to fire once loaded
var marks: Dictionary = {}         ## name -> id, for tests


func _init() -> void:
	_channels(Vector2(-420, -200))
	_toggles(Vector2(0, -200))
	_mute(Vector2(420, -200))
	_cooldowns(Vector2(-420, 200))
	_chain(Vector2(0, 200))
	_grids(Vector2(420, 200))


func _add(pos: Vector2, degree: int, channel: int, mode: int = NOTE, extra: Dictionary = {}) -> int:
	var d := {"id": layout.size() + 1, "x": pos.x, "y": pos.y, "note": _pitch(degree), "channel": channel, "mode": mode}
	d.merge(extra)
	layout.append(d)
	return d.id


func _pitch(degree: int) -> int:
	var scale: Array = Scales.octave_notes(4, Settings.root_note, Settings.scale_name)
	return scale[degree % scale.size()] + 12 * (degree / scale.size())


## A relay firing `strength` waves from a detached emitter at `emit`, out to `reach`.
func _sender(pos: Vector2, emit: Vector2, channel: int, reach: float, cooldown: float = 1.0, strength: float = 1.0, extra: Dictionary = {}) -> int:
	var d := {"attached": false, "ex": emit.x, "ey": emit.y, "range": reach, "cooldown_beats": cooldown, "pulse_strength": strength}
	d.merge(extra)
	return _add(pos, 0, channel, RELAY, d)


## The two relays that keep a group going: each one's wave sets off the other.
func _pair(a: Vector2, b: Vector2, reach: float) -> void:
	for p in [a, b]:
		var id := _add(p, 0, 1, RELAY, {"range": reach, "pulse_strength": 1.0, "cooldown_beats": 1.0})
		if p == a:
			starters.append(id)


## All 16 channel colours, and velocity falling off with distance.
func _channels(c: Vector2) -> void:
	_pair(c + Vector2(-55, 0), c + Vector2(55, 0), 200.0)
	for i in 16:
		marks["channel%d" % i] = _add(c + Vector2.from_angle(TAU * i / 16.0) * 115.0, i, i)


## The usual driver: a pair on the group's left edge. Anything right of about x = 5 is out of its reach,
## so it only hears what a relay sends it.
func _driver(c: Vector2) -> void:
	_pair(c + Vector2(-150, -60), c + Vector2(-150, 60), 155.0)


## A toggle starting on, one starting off, a plain note to compare, and a toggle on a relay, which
## passes on every other wave to its note.
func _toggles(c: Vector2) -> void:
	_driver(c)
	marks["toggle_on"] = _add(c + Vector2(-80, -44), 0, 0, NOTE, {"mod": "toggle", "mod_start": true})
	marks["toggle_off"] = _add(c + Vector2(-80, 0), 2, 2, NOTE, {"mod": "toggle", "mod_start": false})
	marks["plain"] = _add(c + Vector2(-80, 44), 4, 3)
	var target := c + Vector2(100, 90)
	_sender(c + Vector2(-70, 90), target, 4, 60.0, 0.25, 1.0, {"mod": "toggle", "mod_start": true})
	marks["toggled_target"] = _add(target, 6, 5)


## A muted note beside a plain one, and a muted relay that passes nothing to its note.
func _mute(c: Vector2) -> void:
	_driver(c)
	marks["muted"] = _add(c + Vector2(-70, -60), 1, 6, NOTE, {"muted": true})
	marks["unmuted"] = _add(c + Vector2(-70, 10), 3, 7)
	var target := c + Vector2(100, 90)
	_sender(c + Vector2(-70, 90), target, 8, 60.0, 0.25, 1.0, {"muted": true})
	marks["muted_target"] = _add(target, 5, 8)


## Relays with cooldowns of 4, 1 and a quarter beat and retrigger, at rising strength, each aimed at
## its own note with a short reach. They're all hit equally often; only the cooldown differs.
func _cooldowns(c: Vector2) -> void:
	_driver(c)
	var rows := [[-66.0, 4.0, 0.25], [-22.0, 1.0, 0.5], [22.0, 0.25, 0.75], [66.0, 0.0, 1.0]]
	for i in rows.size():
		var y: float = rows[i][0]
		var target := c + Vector2(100, y)
		_sender(c + Vector2(-80, y), target, 9, 40.0, rows[i][1], rows[i][2])
		marks["cooldown%d" % i] = _add(target, i * 2, 9)


## Each relay's emitter sits on the next relay and a note, so all three notes play in one frame.
## The tethers show the separate emitters; short reaches keep each wave on its own stack.
func _chain(c: Vector2) -> void:
	_driver(c)
	var stops := [c + Vector2(40, -80), c + Vector2(100, 0), c + Vector2(40, 80)]
	_sender(c + Vector2(-60, 0), stops[0], 10, 30.0)
	marks["chord0"] = _add(stops[0], 0, 10)
	_sender(stops[0], stops[1], 10, 30.0)
	marks["chord1"] = _add(stops[1], 2, 10)
	_sender(stops[1], stops[2], 10, 30.0)
	marks["chord2"] = _add(stops[2], 4, 10)


## A grid on a note and one on a detached emitter, with objects on their rings and spokes. Every
## object here has a binding, so KP1-5 fire them.
func _grids(c: Vector2) -> void:
	_driver(c)
	_sender(c + Vector2(-70, -30), c + Vector2(50, -20), 11, 160.0)
	var g := c + Vector2(0, -80)
	marks["grid"] = _add(g, 0, 11, NOTE, {"grid": true, "binding": "kp1"})
	marks["on_ring"] = _add(g + Vector2(100, 0), 1, 12, NOTE, {"binding": "kp2"})
	marks["on_spoke"] = _add(g + Vector2.from_angle(PI / 4.0) * 100.0, 2, 13, NOTE, {"binding": "kp3"})
	var emit := c + Vector2(100, 90)
	_sender(c + Vector2(-70, 90), emit, 14, 60.0, 1.0, 1.0, {"grid_emit": true, "binding": "kp4"})
	marks["emitter_grid"] = _add(emit + Vector2(0, -50), 4, 15, NOTE, {"binding": "kp5"})
