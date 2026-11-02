extends Node
## Behavior baseline for the simulation, editing operations and save format. It drives
## WaveSurface directly (no input events), logs every MIDI message and layout, and compares the
## log with tests/baseline_expected.txt.
##   godot --headless --path . res://tests/baseline.tscn             compare
##   godot --headless --path . res://tests/baseline.tscn -- --record rewrite the expected log

const EXPECTED := "res://tests/baseline_expected.txt"
const DT := 1.0 / 60.0

var surface: WaveSurface
var log_lines: PackedStringArray = []


func _ready() -> void:
	Midi.log_when_closed = false
	Midi.message_sent.connect(func(b: PackedByteArray) -> void:
		_log("midi %d %s" % [surface.clock_usec, b.hex_encode()]))
	surface = WaveSurface.new()
	surface.size = Vector2(1280, 800)
	add_child(surface)
	surface.size = Vector2(1280, 800)
	surface.clear_notes()
	_scenarios()
	_finish()


func _log(text: String) -> void:
	log_lines.append(text)


func _layout(label: String) -> void:
	surface.save_notes()
	_log("layout %s %s" % [label, JSON.stringify(Settings.notes)])


func _run(seconds: float) -> void:
	for i in int(seconds / DT):
		surface.step(DT)
		if i % 30 == 0:
			_log("waves %d %s" % [surface.waves.size(), str(surface.shader_waves().slice(0, 3))])


func _note_at(world: Vector2, pitch: int, channel: int = 0) -> int:
	return surface.add_note_at(surface.to_screen(world), pitch, channel)


func _relay_at(world: Vector2, pitch: int, cooldown: float, strength: float = 0.8) -> int:
	var id := _note_at(world, pitch, 1)
	surface.add_modifier(id, "relay")
	surface.set_relay_sound(id, false)
	surface.set_pulse_params(id, strength, cooldown)
	return id


## Press, move and release an object through the surface's drag operation.
func _drag(id: int, kind: String, to_world: Vector2, free: bool = false) -> void:
	var to := surface.to_screen(to_world)
	surface.drag.begin(id, kind, surface.to_screen(surface.get_note(id).pos))
	surface.drag.moved = true
	surface.drag.move_to(to, free)
	_log("drag %s" % JSON.stringify(_clean(surface.drag.info)))
	surface.drag.end()


func _set_hover(id: int, handle: int = -1) -> void:
	surface._hover_id = id
	surface._hover_handle = handle


func _clean(d: Dictionary) -> Dictionary:
	var out := {}
	for key in d:
		out[key] = str(d[key])
	return out


func _reset() -> void:
	surface.stop()
	surface.clear_notes()
	surface.history.end_group()


func _scenarios() -> void:
	# Plain notes: velocity falloff and note length.
	var a := _note_at(Vector2(300, 200), 60)
	var b := _note_at(Vector2(700, 200), 67, 2)
	surface.spawn_wave(surface.to_screen(Vector2(300, 200)))
	_run(2.0)
	surface.get_note(b).tap(surface)
	_run(1.0)
	_log("text %s | %s" % [surface.get_note(a).hover_text(), surface.get_note(b).hover_text()])
	_layout("plain")
	_reset()

	# A relay loop with a detached emitter, cooldowns, retrigger and Stop.
	var r1 := _relay_at(Vector2(200, 300), 60, 1.0)
	var r2 := _relay_at(Vector2(600, 300), 64, 0.5)
	var n1 := _note_at(Vector2(400, 300), 72, 3)
	_drag(r2, "emitter", Vector2(450, 500), true)
	surface.trigger_note(r1)
	_run(4.0)
	surface.set_pulse_params(r1, 0.6, 0.0)
	_log("text %s" % surface.get_note(r1).hover_text())
	_run(2.0)
	_log("skipped %d" % surface.skipped_pulses)
	surface.stop()
	_run(0.5)
	_drag(r2, "emitter", Vector2(600, 300), true)     # dropped back on the note: re-attach
	_layout("relays")
	_reset()

	# A stacked chain fires as one chord.
	var c1 := _relay_at(Vector2(100, 100), 60, 1.0)
	var c2 := _relay_at(Vector2(500, 100), 62, 1.0)
	var c3 := _note_at(Vector2(800, 100), 64)
	_drag(c1, "emitter", Vector2(500, 100), true)
	_drag(c2, "emitter", Vector2(800, 100), true)
	surface.trigger_note(c1)
	_run(1.0)
	_log("chain %s" % surface.get_note(c3).hover_text())
	_reset()

	# Toggle, mute, slots and held refires.
	var t := _note_at(Vector2(300, 300), 60)
	var m := _note_at(Vector2(350, 300), 62)
	var p := _relay_at(Vector2(500, 300), 65, 0.5)
	surface.add_modifier(t, "toggle")
	surface.add_modifier(p, "toggle")
	surface.set_modifier_state(p, false)
	_log("text %s | %s" % [surface.get_note(t).hover_text(), surface.get_note(p).hover_text()])
	surface.set_binding(t, "kp1")
	surface.set_binding(p, "kp1")
	surface.set_binding(m, "kp2")
	_set_hover(m)
	_log("mute %d" % surface.toggle_mute())
	_set_hover(-1)
	surface.press_binding("kp1")
	_run(1.5)
	surface.release_binding("kp1")
	surface.press_binding("kp2")
	surface.release_binding("kp2")
	_run(1.0)
	surface.save_state()
	_log("text %s" % surface.get_note(t).hover_text())
	surface.stop()
	_layout("toggles")
	surface.remove_modifier(t, "toggle")
	_layout("toggle_removed")
	_reset()

	# Cooldowns gate pulses, and a held slot refires a relay each time its cooldown runs out.
	var cool := _relay_at(Vector2(300, 300), 60, 2.0)
	var heard := _note_at(Vector2(420, 300), 64)
	var held := _relay_at(Vector2(900, 900), 66, 0.5)
	var far := _note_at(Vector2(1000, 900), 69)
	surface.set_binding(held, "kp4")
	for i in 6:
		surface.spawn_wave(surface.to_screen(Vector2(200, 300)))
		_run(0.4)
	surface.press_binding("kp4")
	_run(2.0)
	surface.release_binding("kp4")
	_run(1.0)
	_log("cool %s %s" % [surface.get_note(cool).hover_text(), surface.get_note(far).hover_text()])
	_log("heard %s" % surface.get_note(heard).hover_text())
	_reset()

	# Grids, snapping, group drags and range.
	var g := _note_at(Vector2(400, 400), 60)
	var q := _note_at(Vector2(530, 410), 62)
	var e := _relay_at(Vector2(800, 400), 65, 1.0)
	surface.snapping.toggle_grid(surface.get_note(g), false)
	_drag(e, "emitter", Vector2(900, 500), true)
	surface.snapping.toggle_grid(surface.get_note(e), true)
	for pt in [Vector2(610, 395), Vector2(420, 610), Vector2(530, 530), Vector2(400, 402), Vector2(901, 503), Vector2(2000, 2000)]:
		_log("snap %s %s" % [str(surface.snapping.grid_snap(pt)), JSON.stringify(_clean(surface.snapping.compute_drag(surface.get_note(q), "note", pt, false)))])
		_log("free %s" % JSON.stringify(_clean(surface.snapping.compute_drag(surface.get_note(q), "emitter", pt, true))))
	_drag(q, "note", Vector2(612, 402))
	var id_new := _note_at(Vector2(555, 545), 64)
	_log("placed %s" % str(surface.get_note(id_new).pos))
	surface.selection.select_in_rect(Rect2(surface.to_screen(Vector2(350, 350)), surface.to_screen(Vector2(1000, 1000)) - surface.to_screen(Vector2(350, 350))))
	_log("selected %d" % surface.selection.count())
	_drag(q, "note", Vector2(700, 480), true)
	_log("group %s" % str(surface.selection.group_for(q)))
	surface.selection.clear()
	surface.selection.select_in_rect(Rect2(surface.to_screen(Vector2(850, 450)), surface.to_screen(Vector2(100, 100)) * surface.z() ))
	_log("selected %d" % surface.selection.count())
	surface.selection.clear()
	surface.drag.begin(e, "range", surface.to_screen(surface.get_note(e).pos))
	surface.drag.moved = true
	surface.drag.move_to(surface.to_screen(Vector2(1000, 620)), false)
	_log("range %s" % JSON.stringify(_clean(surface.drag.info)))
	surface.drag.end()
	_log("text %s" % surface.get_note(e).hover_text())
	_layout("grids")
	_log("cleared %d" % surface.snapping.clear_grids())
	_reset()

	# Copy, paste, delete, undo and redo.
	var u := _note_at(Vector2(300, 300), 60)
	surface.history.end_group()
	var v := _relay_at(Vector2(500, 300), 67, 2.0, 0.5)
	surface.history.end_group()
	_drag(v, "emitter", Vector2(600, 450), true)
	surface.history.end_group()
	surface.add_modifier(v, "toggle")
	surface.history.end_group()
	surface.selection.select_in_rect(Rect2(Vector2.ZERO, Vector2(1280, 800)))
	_log("copied %d" % surface.selection.copy())
	surface.history.end_group()
	_log("pasted %d" % surface.selection.paste_at(Vector2(640, 500)))
	surface.history.end_group()
	_layout("pasted")
	surface.set_relay_sound(v, true)
	surface.history.end_group()
	_layout("sounding")
	surface.set_relay_sound(v, false)
	surface.history.end_group()
	_layout("silent")
	surface.set_note_pitch(u, 72)
	surface.history.end_group()
	surface.set_note_channel(u, 9)
	surface.history.end_group()
	surface.remove_note(u)
	surface.history.end_group()
	surface.delete_selection()
	surface.history.end_group()
	for i in 4:
		_log("undo %s %d" % [surface.undo(), surface.history.undo_steps()])
		_layout("undo%d" % i)
	for i in 2:
		_log("redo %s %d" % [surface.redo(), surface.history.redo_steps()])
		_layout("redo%d" % i)
	_reset()

	# Scale changes re-snap; nudging moves pitches.
	var s1 := _note_at(Vector2(300, 300), 61)
	var s2 := _note_at(Vector2(400, 300), 66)
	Settings.set_value("scale_name", "Major")
	_layout("rescale")
	surface.selection.notes = {s1: true, s2: true}
	_log("nudge %d" % surface.nudge_pitch(1, false))
	_log("nudge %d" % surface.nudge_pitch(-1, true))
	Settings.set_value("scale_name", "Minor Pentatonic")
	_layout("nudged")
	surface.selection.clear()
	_reset()

	# Old saves: seconds cooldowns and the note + pulse hybrid; an unknown modifier is dropped.
	Settings.notes = [
		{"x": 100.0, "y": 100.0, "note": 60, "channel": 1, "mode": 1, "pulse_strength": 0.5, "cooldown": 1.0, "mod": "toggle", "mod_start": false, "slot": 3, "id": 7},
		{"x": 200.0, "y": 100.0, "note": 62, "channel": 2, "mode": 2, "cooldown_beats": 0.01, "attached": false, "ex": 400.0, "ey": 500.0, "mod": "bogus", "id": 7},
		{"x": 300.0, "y": 100.0, "note": 64, "channel": 3, "mode": 0, "grid": true, "range": 300.0, "muted": true},
	]
	surface.load_notes()
	_layout("legacy")
	surface.frame_notes()
	_log("view %s" % str(surface.view_offset))
	surface.seed_default_layout()
	_layout("seeded")
	_log("beats %s %s %s" % [Snapping.format_beats(1.75), Snapping.format_beats(0.5), Snapping.format_beats(1.37)])


func _finish() -> void:
	var text := "\n".join(log_lines) + "\n"
	if OS.get_cmdline_user_args().has("--record"):
		var f := FileAccess.open(EXPECTED, FileAccess.WRITE)
		f.store_string(text)
		f.close()
		print("BASELINE RECORDED: %d lines" % log_lines.size())
		get_tree().quit(0)
		return
	var want := FileAccess.get_file_as_string(EXPECTED).split("\n")
	var got := text.split("\n")
	for i in mini(want.size(), got.size()):
		if want[i] != got[i]:
			print("BASELINE FAILED at line %d\n  want: %s\n  got:  %s" % [i + 1, want[i], got[i]])
			get_tree().quit(1)
			return
	if want.size() != got.size():
		print("BASELINE FAILED: %d lines, expected %d" % [got.size(), want.size()])
		get_tree().quit(1)
		return
	print("BASELINE OK: %d lines" % log_lines.size())
	get_tree().quit(0)
