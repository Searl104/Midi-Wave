extends Node
## Plays the Test layout for a while and checks each group does what it demonstrates.
## Run: godot --headless --path . res://tests/demo.tscn

const DT := 1.0 / 60.0
const SECONDS := 16.0

var surface: WaveSurface
var failures := 0
var checks := 0
var on_times: Dictionary = {}   # object id -> [clock times it played]
var _last_off: Dictionary = {}
var demo: DemoLayout


func _ready() -> void:
	Midi.log_when_closed = false
	surface = WaveSurface.new()
	add_child(surface)
	surface.size = Vector2(1280, 800)
	var before: Array = Settings.notes.duplicate(true)
	surface.history.end_group()
	demo = DemoLayout.new()
	var layout := demo.layout
	surface.load_layout(layout)
	_check(surface.notes.size() == layout.size(), "every object loaded")
	_check(demo.starters.size() == 6, "one starter per group")
	for id in demo.starters:
		var o := surface.get_note(id)
		_check(o is Relay and o.emitter.own_reach > 0.0, "starter %d is a pair relay" % id)
		surface.trigger_note(id)
	for o in surface.notes:
		on_times[o.id] = []
	var peak := 0
	for i in int(SECONDS / DT):
		surface.step(DT)
		_record()
		peak = maxi(peak, surface.waves.size())
	print("peak waves %d, skipped %d" % [peak, surface.skipped_pulses])
	_check(surface.skipped_pulses == 0, "no pulses skipped")
	_check(peak < WaveSurface.MAX_WAVES, "stays under the wave cap")
	_groups()
	surface.stop()
	_check(surface.waves.is_empty(), "Stop ends it")
	var count := _played()
	for i in 120:
		surface.step(DT)
		_record()
	_check(_played() == count, "nothing plays after Stop")
	_check(surface.undo(), "loading can be undone")
	_check(JSON.stringify(Settings.notes) == JSON.stringify(before), "undo restores the old layout")
	_check(surface.redo() and surface.notes.size() == layout.size(), "and redone")
	surface.save_notes()
	var saved: Array = Settings.notes.duplicate(true)
	surface.load_notes()
	surface.save_notes()
	_check(JSON.stringify(Settings.notes) == JSON.stringify(saved), "survives save and reload")
	print("DEMO %s: %d checks, %d failed" % ["OK" if failures == 0 else "FAILED", checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _record() -> void:
	for o in surface.notes:
		if o.off_at != _last_off.get(o.id, 0):
			_last_off[o.id] = o.off_at
			on_times[o.id].append(surface.clock_usec)


func _played() -> int:
	var n := 0
	for id in on_times:
		n += on_times[id].size()
	return n


func _hits(mark: String) -> int:
	return on_times[demo.marks[mark]].size()


func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("  failed: ", what)


func _groups() -> void:
	var counts := {}
	for mark in demo.marks:
		counts[mark] = _hits(mark)
	print(counts)
	var channels := {}
	for i in 16:
		_check(_hits("channel%d" % i) > 8, "channel note %d plays" % i)
		channels[surface.get_note(demo.marks["channel%d" % i]).channel] = true
	_check(channels.size() == 16, "16 channels")
	_check(_hits("plain") > 8, "plain note plays")
	_check(absi(_hits("toggle_on") * 2 - _hits("plain")) <= 2, "toggle plays every other hit")
	_check(absi(_hits("toggle_off") * 2 - _hits("plain")) <= 2, "toggle starting off too")
	_check(_hits("toggled_target") > 2 and _hits("toggled_target") < _hits("plain"), "toggled relay passes on fewer")
	_check(_hits("muted") == 0, "muted note is silent")
	_check(_hits("unmuted") > 8, "note beside it plays")
	_check(_hits("muted_target") == 0, "muted relay sends nothing")
	_check(_hits("cooldown0") >= 2 and _hits("cooldown0") < _hits("cooldown1"), "4 beats is slower than 1")
	_check(_hits("cooldown1") < _hits("cooldown2"), "1 beat is slower than a quarter")
	_check(_hits("cooldown3") >= _hits("cooldown2"), "retrigger keeps up")
	var ch: Array = on_times[demo.marks["chord0"]]
	_check(ch.size() > 2, "chain plays")
	_check(ch == on_times[demo.marks["chord1"]] and ch == on_times[demo.marks["chord2"]], "chain plays as one chord")
	for mark in ["grid", "on_ring", "on_spoke", "emitter_grid"]:
		_check(_hits(mark) > 2, "%s plays" % mark)
	var g := surface.get_note(demo.marks["grid"])
	_check(g.grid != null, "note grid on")
	var target := surface.get_note(demo.marks["on_ring"])
	var snapped := surface.snapping.grid_snap(target.pos + Vector2(4, 4))
	_check(snapped.is_equal_approx(target.pos), "the ring object sits on a grid point")
	var has_emitter_grid := false
	var slots := {}
	for o in surface.notes:
		has_emitter_grid = has_emitter_grid or (o.emitter.grid != null and not o.emitter.attached)
		if o.slot > 0:
			slots[o.slot] = true
	_check(has_emitter_grid, "emitter grid on")
	_check(slots.size() == 5, "five slots in use")
