extends "res://tests/support/tools_test_base.gd"
## Tweaks, saved state and the default ring.


func run() -> void:
	_tweaks()
	_saves()
	_default_ring()


func _tweaks() -> void:
	var a := surface.add_note_at(Vector2(300, 300), 60, 0)
	var b := surface.add_note_at(Vector2(500, 300), 63, 0)
	var ao := surface.get_note(a)
	for id in ["tap", "select", "draw", "bind", "grid", "pan"]:
		tools.set_tool(id)
		surface.selection.clear()
		surface.set_pointer(Vector2(300, 300))
		ao.muted = false
		_key(KEY_M)
		_check(ao.muted, "M mutes in %s" % id)
		ao.muted = false
		var was: int = ao.note
		var e := InputEventKey.new()
		e.keycode = KEY_PERIOD
		e.pressed = true
		tools.handle_input(e)
		_check(ao.note > was, "> nudges in %s" % id)
		e.keycode = KEY_COMMA
		tools.handle_input(e)
		_check(ao.note == was, "< nudges back in %s" % id)
		e.shift_pressed = true
		e.keycode = KEY_PERIOD
		tools.handle_input(e)
		_check(ao.note == was + 12, "Shift: an octave in %s" % id)
		e.keycode = KEY_COMMA
		tools.handle_input(e)
	surface.set_pointer(Vector2(1000, 700))
	tools.set_tool("select")
	surface.clear_notes()


func _saves() -> void:
	Settings.notes = [
		{"x": 10.0, "y": 0.0, "note": 60, "channel": 0, "mode": 2, "pulse_strength": 0.5, "cooldown_beats": 2.0, "attached": false, "ex": 30.0, "ey": 40.0, "mod": "sequence", "mod_start": false, "id": 3, "range": 200.0, "grid_emit": true},
		{"x": 20.0, "y": 0.0, "note": 62, "channel": 1, "mode": 1, "id": 4},
		{"x": 30.0, "y": 0.0, "note": 64, "channel": 2, "mode": 0, "attached": false, "ex": 9.0, "ey": 9.0, "id": 5},
	]
	surface.load_notes()
	var r := surface.get_note(3)
	_check(r.relay() and r.get_modifier("sequence") and r.get_modifier("sequence").steps == [false, true], "an old toggle becomes a sequence")
	_check(r.get_modifier("silent") != null and not r.sounds(), "an old relay (mode 2) gets Silent")
	var e := r.emitter()
	_check(e.cooldown == 2.0 and not e.attached and e.pos == Vector2(30, 40) and e.own_reach == 200.0 and e.grid, "keeps its emitter")
	_check(not e.to_dict().has("pulse_strength"), "and strength is no longer saved")
	_check(surface.get_note(4).relay() and surface.get_note(4).sounds() and surface.notes.size() == 3, "an old hybrid is one sounding relay")
	_check(surface.get_note(5).modifiers.is_empty(), "an old plain note has no relay")
	surface.save_notes()
	var saved := JSON.stringify(Settings.notes)
	surface.load_notes()
	surface.save_notes()
	_check(JSON.stringify(Settings.notes) == saved, "the new format round-trips")
	_check(not saved.contains("\"mode\""), "and has no type field")
	Settings.notes = [{"x": 0.0, "y": 0.0, "note": 60, "channel": 0, "id": 9,
			"mods": [{"kind": "relay", "sound": false, "pulse_strength": 0.3, "cooldown_beats": 1.0}]}]
	surface.load_notes()
	var quiet := surface.get_note(9)
	_check(quiet.relay() != null and quiet.get_modifier("silent") != null and quiet.modifiers.size() == 2, "a relay saved with Sound off gets Silent")
	surface.clear_notes()


func _default_ring() -> void:
	var n := surface.add_note_at(Vector2(200, 200), 60, 0)
	tools.open_default_ring(n, Vector2(200, 200))
	_check(tools.open_ring.tool_id() == "pitch", "a note's default is pitch")
	tools.open_default_ring(-1, Vector2(600, 200))
	_check(tools.open_ring.tool_id() == "pitch", "empty space is pitch")
	radial.hover_at(Vector2(600, 100))
	radial.close()
	surface.clear_notes()
