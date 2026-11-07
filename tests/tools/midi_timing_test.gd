extends "res://tests/support/tools_test_base.gd"
## Cooldowns, MIDI input, note lengths, Sound volume, timing and wave ends.


func run() -> void:
	_held_during_cooldown()
	_midi_controls()
	_note_lengths()
	_channel_volume()
	_timing()
	_slow_frame()
	_wave_end()


func _midi_event(message: int, field: String = "", value: int = 0, value2: int = 0) -> InputEventMIDI:
	var e := InputEventMIDI.new()
	e.message = message as MIDIMessage
	if field == "note":
		e.pitch = value
		e.velocity = value2
	elif field == "cc":
		e.controller_number = value
		e.controller_value = value2
	return e


func _run_frames(seconds: float, fps: float, jitter: float, rng: RandomNumberGenerator) -> void:
	var t := 0.0
	while t < seconds:
		var d: float = (1.0 / fps) * (1.0 + rng.randf_range(-jitter, jitter))
		surface.step(d)
		t += d


func _held_during_cooldown() -> void:
	var a := surface.add_object(Vector2.ZERO, 60, 0)
	surface.add_modifier(a, "relay")
	surface.set_binding(a, "kp1")
	var e: Emitter = surface.get_note(a).emitter()
	e.cooldown = 2.0
	var length := float(e.cooldown_usec()) / 1_000_000.0
	var run := func(seconds: float) -> void:
		for i in int(seconds * 120.0):
			surface.step(1.0 / 120.0)
	surface.press_binding("kp1")
	surface.release_binding("kp1")
	var first: int = e.ready_at
	run.call(length * 0.5)
	var sent: Array = []
	var spy := func(m: PackedByteArray) -> void:
		if (m[0] & 0xF0) == 0x90:
			sent.append(m)
	Midi.message_sent.connect(spy)
	surface.add_modifier(a, "sequence")
	var seq: SequenceModifier = surface.get_note(a).get_modifier("sequence")
	seq.steps = [true, false]
	surface.press_binding("kp1")
	_check(e.ready_at == first and sent.is_empty() and seq.pos == 0, "a press during a cooldown does nothing")
	run.call(length * 0.4)
	_check(e.ready_at == first and sent.is_empty(), "nor before it ends")
	run.call(length * 0.15)
	_check(e.ready_at > first and e.ready_at <= first + e.cooldown_usec() + 20000, "held, it fires as the cooldown ends")
	_check(sent.size() == 1 and seq.pos == 1, "once, with its sound, taking one step")
	surface.remove_modifier(a, "sequence")
	Midi.message_sent.disconnect(spy)
	var second: int = e.ready_at
	surface.release_binding("kp1")
	run.call(length * 0.5)
	surface.press_binding("kp1")
	surface.release_binding("kp1")
	run.call(length * 0.7)
	_check(e.ready_at == second, "released in time, it doesn't")
	surface.stop()
	surface.clear_notes()


func _midi_controls() -> void:
	var saved: Dictionary = Settings.midi_mappings
	Settings.midi_mappings = MidiMappings.DEFAULTS.duplicate()
	var map := MidiMappings.new(surface)
	var fired: Array = []
	map.triggered.connect(func(a: String) -> void: fired.append(a))
	var midi_in := MidiInput.new()
	midi_in.message_received.connect(map.receive)
	var pressed: Array = []
	midi_in.note_pressed.connect(func(p: int) -> void: pressed.append(map.listening))
	Settings.midi_in_port = "Keys"
	midi_in._names = ["Keys", "loopMIDI"]
	# The default, and where messages may come from.
	var stop := _midi_event(MIDI_MESSAGE_STOP)
	_check(midi_in.handle(stop) and fired == ["stop"], "MIDI Stop runs Stop by default")
	stop.device = 1
	_check(not midi_in.handle(stop) and fired.size() == 1, "not from another input")
	stop.device = 0
	Settings.midi_in_port = ""
	_check(not midi_in.handle(stop) and fired.size() == 1, "nor with input Off")
	Settings.midi_in_port = "Keys"
	# Learning.
	fired.clear()
	map.listen("panic")
	midi_in.handle(_midi_event(MIDI_MESSAGE_CONTROL_CHANGE, "cc", 20, 127))
	_check(map.listening == "" and map.key_for("panic") == "cc20" and fired.is_empty(), "learning doesn't fire")
	midi_in.handle(_midi_event(MIDI_MESSAGE_CONTROL_CHANGE, "cc", 20, 0))
	midi_in.handle(_midi_event(MIDI_MESSAGE_CONTROL_CHANGE, "cc", 20, 40))
	midi_in.handle(_midi_event(MIDI_MESSAGE_CONTROL_CHANGE, "cc", 20, 90))
	_check(fired == ["panic"], "a CC fires once on rising above 0")
	midi_in.handle(_midi_event(MIDI_MESSAGE_CONTROL_CHANGE, "cc", 20, 0))
	midi_in.handle(_midi_event(MIDI_MESSAGE_CONTROL_CHANGE, "cc", 20, 127))
	_check(fired.size() == 2, "and again after returning to 0")
	# Notes: the binding is told before the note is learned, and can stand aside.
	map.listen("panic")
	midi_in.handle(_midi_event(MIDI_MESSAGE_NOTE_ON, "note", 60, 100))
	_check(pressed == ["panic"] and map.key_for("panic") == "note60", "a note learns")
	midi_in.handle(_midi_event(MIDI_MESSAGE_NOTE_OFF, "note", 60))
	fired.clear()
	midi_in.handle(_midi_event(MIDI_MESSAGE_NOTE_ON, "note", 60, 100))
	_check(fired == ["panic"] and pressed[-1] == "", "a mapped note fires")
	midi_in.handle(_midi_event(MIDI_MESSAGE_NOTE_ON, "note", 60, 0))
	_check(fired.size() == 1, "a Note On at velocity 0 is a release")
	# One message, one action.
	map.listen("stop")
	map.receive("note60")
	_check(map.key_for("stop") == "note60" and map.key_for("panic") == "", "a message moves to the new action")
	# Bound notes.
	var a := surface.add_object(Vector2.ZERO, 60, 0)
	var b := surface.add_object(Vector2(100, 0), 62, 0)
	surface.set_binding(a, "midi60")
	surface.set_binding(b, "midi60")
	_check(map.bound_notes("note60") == 2 and map.bound_notes("cc60") == 0, "bound notes are counted")
	surface.clear_notes()
	# Labels, clearing and cancelling.
	_check(MidiMappings.label("note60") == "Note C4" and MidiMappings.label("cc20") == "CC 20", "labels")
	_check(MidiMappings.label("rt252") == "MIDI Stop" and MidiMappings.label("") == "Not set", "more labels")
	map.clear("stop")
	_check(map.key_for("stop") == "", "Clear removes it")
	map.listen("stop")
	map.cancel()
	map.receive("cc1")
	_check(map.key_for("stop") == "", "cancel stops listening")
	map.reset()
	_check(map.key_for("stop") == "rt252" and map.key_for("panic") == "", "Reset returns to the defaults")
	# The tab. With no controller chosen, since the panel lists the inputs, and there are none here.
	Settings.midi_in_port = ""
	var options := OptionsPanel.new()
	options.surface = surface
	options.mappings = map
	add_child(options)
	options._control_rows["panic"].learn.pressed.emit()
	_check(map.listening == "panic" and options._control_rows["panic"].learn.text == "Cancel", "Learn listens")
	_check(options._control_rows["panic"].value.text == "Listening...", "and says so")
	options.toggle()
	options.toggle()
	_check(map.listening == "", "closing Options cancels")
	options.toggle()
	options._control_rows["panic"].learn.pressed.emit()
	options.tabs.current_tab = 2
	_check(map.listening == "", "changing tab cancels")
	options.tabs.current_tab = 0
	options._control_rows["stop"].clear.pressed.emit()
	_check(options._control_rows["stop"].value.text == "Not set" and options._control_rows["stop"].clear.disabled, "Clear shows")
	options.queue_free()
	midi_in.free()
	Settings.midi_mappings = saved


func _note_lengths() -> void:
	_check(Settings.note_beats == 0.5, "the default is an eighth note")
	var bpm: float = Settings.bpm
	_check(is_equal_approx(Settings.note_length_for(0), 0.5 * 60.0 / bpm), "lengths are in beats")
	Settings.bpm = 60.0
	_check(is_equal_approx(Settings.note_length_for(0), 0.5), "and follow the tempo")
	Settings.set_channel_beats(3, 2.5)
	_check(is_equal_approx(Settings.note_length_for(3), 2.5) and is_equal_approx(Settings.note_length_for(4), 0.5), "a channel can differ")
	Settings.set_channel_beats(3, 0.0)
	Settings.bpm = bpm
	for pair in [[0.1, 0.5], [0.74, 0.5], [0.76, 1.0], [1.3, 1.5], [9.0, 4.0]]:
		_check(Settings.snap_length(pair[0]) == pair[1], "%s snaps to %s" % pair)
	for pair in [[0.5, "½ beat"], [1.0, "1 beat"], [1.5, "1½ beats"], [4.0, "4 beats"]]:
		_check(PanelBuilder.beats_text(pair[0]) == pair[1], "reads %s" % pair[1])
	var box := VBoxContainer.new()
	add_child(box)
	tools.get_tool("channel").build_options(box)
	var sliders := box.find_children("*", "HSlider", true, false)
	_check(sliders.size() == 1, "one Default slider")
	_check(sliders[0].step == 0.5 and sliders[0].min_value == 0.5 and sliders[0].max_value == 4.0, "Default runs ½ to 4 in ½ steps")
	var knobs := _knobs(box)
	_check(knobs.size() == 32, "two knobs per channel")
	_check(knobs[1].step == 0.5 and knobs[1].min_value == 0.0 and knobs[1].max_value == 4.0, "a length knob has Default at the bottom")
	for k in knobs:
		_check(k.tooltip_text != "", "knob has a tooltip")
	box.queue_free()
	# Old saves.
	var cfg := ConfigFile.new()
	var old: Array = []
	old.resize(16)
	old.fill(0.0)
	old[1] = 1.3
	cfg.set_value("app", "note_length", 0.35)
	cfg.set_value("app", "channel_lengths", old)
	var was: float = Settings.note_beats
	var was_channels: Array = Settings.channel_beats.duplicate()
	Settings._migrate_note_lengths(cfg)
	_check(Settings.note_beats == 0.5 and Settings.channel_beats[1] == 2.5 and Settings.channel_beats[0] == 0.0, "old seconds convert and snap")
	Settings.note_beats = was
	Settings.channel_beats = was_channels


func _channel_volume() -> void:
	var sent: Array = []
	var spy := func(m: PackedByteArray) -> void:
		if (m[0] & 0xF0) == 0x90:
			sent.append(m)
	Midi.message_sent.connect(spy)
	var a := surface.add_object(Vector2.ZERO, 60, 2)
	var o := surface.get_note(a)
	var box := VBoxContainer.new()
	add_child(box)
	tools.get_tool("channel").build_options(box)
	var volume: Knob = _knobs(box)[4]                # channel 3's volume
	_check(volume.value == 1.0 and volume.fmt.call(volume.value) == "100%", "starts at full")
	# Turning the knob: drag, scroll, double-click.
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	volume._gui_input(press)
	var move := InputEventMouseMotion.new()
	move.button_mask = MOUSE_BUTTON_MASK_LEFT
	move.relative = Vector2(0, 75)
	volume._gui_input(move)
	_check(volume.value == 0.5 and Settings.channel_volumes[2] == 0.5, "dragging down turns it down")
	var free := InputEventMouseMotion.new()
	free.relative = Vector2(0, 60)
	volume._gui_input(free)
	_check(volume.value == 0.5, "only with the button held")
	move.relative = Vector2(0, 3)
	volume._gui_input(move)
	_check(is_equal_approx(volume.value, 0.48), "volume is continuous")
	move.relative = Vector2(0, -3)
	volume._gui_input(move)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	volume._gui_input(wheel)
	_check(is_equal_approx(volume.value, 0.55), "scrolling steps it")
	var twice := InputEventMouseButton.new()
	twice.button_index = MOUSE_BUTTON_LEFT
	twice.pressed = true
	twice.double_click = true
	volume._gui_input(twice)
	_check(volume.value == 1.0 and Settings.channel_volumes[2] == 1.0, "double-click resets")
	# Velocity scales, on this channel only.
	o.play(surface, 1.0, 0)
	_check(sent[-1][2] == 127, "full volume")
	Settings.set_channel_volume(2, 0.5)
	o.silence()
	o.play(surface, 1.0, 0)
	_check(sent[-1][2] == 64, "half volume halves velocity")
	o.silence()
	o.channel = 3
	o.play(surface, 1.0, 0)
	_check(sent[-1][2] == 127, "other channels are unaffected")
	o.silence()
	o.channel = 2
	Settings.set_channel_volume(2, 0.05)
	o.play(surface, 0.05, 0)
	_check(sent[-1][2] == 1, "low volume still sounds")
	o.silence()
	# Off: no note, but a relay still fires.
	Settings.set_channel_volume(2, 0.0)
	sent.clear()
	surface.add_modifier(a, "relay")
	surface.trigger_note(a)
	_check(sent.is_empty() and surface.waves.size() == 1, "off silences it, and the relay still fires")
	Midi.play_note(60, 90, 0.25, 2)
	_check(sent.is_empty(), "previews follow it")
	Settings.set_channel_volume(2, 1.0)
	Midi.play_note(60, 90, 0.25, 2)
	_check(sent.size() == 1 and sent[0][2] == 90, "at full, previews are unchanged")
	# Reset all, and it persists.
	Settings.set_channel_volume(5, 0.3)
	Settings.set_channel_beats(5, 2.0)
	box.queue_free()
	var box2 := VBoxContainer.new()
	add_child(box2)
	tools.get_tool("channel").build_options(box2)
	var ks := _knobs(box2)
	_check(is_equal_approx(ks[10].value, 0.3) and ks[11].value == 2.0, "the panel shows stored values")
	for b in box2.find_children("*", "Button", true, false):
		if b.text == "Reset all":
			b.pressed.emit()
	_check(Settings.channel_volumes[5] == 1.0 and Settings.channel_beats[5] == 0.0, "Reset all clears both")
	box2.queue_free()
	Midi.message_sent.disconnect(spy)
	surface.stop()
	surface.clear_notes()


func _timing() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var bpm: float = Settings.bpm
	Settings.bpm = 120.0
	surface.waves.clear()
	var fired: Array = []
	var spy := func(m: PackedByteArray) -> void:
		if (m[0] & 0xF0) == 0x90:
			fired.append([surface.clock_usec, m[1]])
	Midi.message_sent.connect(spy)
	# A 2-beat loop keeps its tempo, whatever the frame rate.
	for setup in [[60.0, 0.0], [60.0, 0.25], [144.0, 0.0], [144.0, 0.25]]:
		surface.clear_notes()
		fired.clear()
		var a := surface.add_object(Vector2(0, 0), 60, 0)
		var b := surface.add_object(Vector2(200, 0), 62, 0)
		for id in [a, b]:
			surface.add_modifier(id, "relay")
			surface.get_note(id).emitter().cooldown = 0.5
			surface.get_note(id).emitter().own_reach = 400.0
		surface.trigger_note(a)
		_run_frames(60.0, setup[0], setup[1], rng)
		var times: Array = fired.filter(func(f: Array) -> bool: return f[1] == 60).map(func(f: Array) -> int: return f[0])
		var period: float = float(times[-1] - times[0]) / (times.size() - 1) / 1000.0
		_check(absf(period - 1000.0) < 1.0, "%d fps, jitter %.2f: loop period %.2f ms" % [setup[0], setup[1], period])
		surface.stop()
	# A chain's eighth link is at most about a frame late.
	for fps in [60.0, 144.0]:
		surface.clear_notes()
		fired.clear()
		var first := -1
		for i in 8:
			var id := surface.add_object(Vector2(200.0 * i, 0), 40 + i, 0)
			surface.add_modifier(id, "relay")
			surface.get_note(id).emitter().own_reach = 250.0
			surface.get_note(id).emitter().cooldown = 4.0
			if i == 0:
				first = id
		var start: int = surface.clock_usec
		surface.trigger_note(first)
		_run_frames(3.8, fps, 0.1, rng)
		var last: Array = fired.filter(func(f: Array) -> bool: return f[1] == 47)
		var late: float = (last[0][0] - start) / 1000.0 - 3500.0
		_check(late >= -1.0 and late < 1000.0 / fps + 3.0, "%d fps: eighth link %.1f ms late" % [fps, late])
		surface.stop()
	# A cooldown equal to the time between hits skips nothing.
	for fps in [60.0, 144.0]:
		surface.clear_notes()
		var r := surface.add_object(Vector2(100, 0), 60, 0)
		surface.add_modifier(r, "relay")
		var e: Emitter = surface.get_note(r).emitter()
		e.own_reach = 10.0
		var count := 0
		var ready: int = e.ready_at
		var t := 0.0
		var next := 0.0
		while t < 30.0:
			if t >= next:
				surface.add_wave(Wave.new(Vector2.ZERO, 1.0, -1, 300.0))
				next += 0.5
			var d: float = (1.0 / fps) * (1.0 + rng.randf_range(-0.1, 0.1))
			surface.step(d)
			t += d
			if e.ready_at != ready:
				count += 1
				ready = e.ready_at
		_check(count >= 59, "%d fps: fired %d of 60 hits" % [fps, count])
		surface.stop()
	# A cooldown still holds off hits that are clearly too soon.
	surface.clear_notes()
	var c := surface.add_object(Vector2(0, 0), 60, 0)
	surface.add_modifier(c, "relay")
	var ce: Emitter = surface.get_note(c).emitter()
	surface.trigger_note(c)
	surface.waves.clear()
	surface.step(0.2)
	surface.trigger_note(c)
	_check(surface.waves.is_empty(), "a cooldown still gates")
	surface.step(0.3 - 0.01)
	surface.trigger_note(c)
	_check(surface.waves.size() == 1, "and a hit 10 ms early fires")
	_check(ce.cooldown == 1.0, "defaults untouched")
	Midi.message_sent.disconnect(spy)
	Settings.bpm = bpm
	surface.stop()
	surface.clear_notes()


func _slow_frame() -> void:
	var heard: Array = []
	var spy := func(m: PackedByteArray) -> void:
		if (m[0] & 0xF0) == 0x90:
			heard.append([surface.clock_usec, m[1], m[2]])
	var melody := func() -> Array: return heard.map(func(h: Array) -> int: return h[1])
	# A wave ending in one slow frame still hits what it reached, and nothing past its end.
	var inner := surface.add_object(Vector2(100, 0), 60, 0)
	var outer := surface.add_object(Vector2(400, 0), 62, 0)
	Midi.message_sent.connect(spy)
	heard.clear()
	surface.add_wave(Wave.new(Vector2.ZERO, 1.0, -1, 300.0))
	surface.step(1.0)
	_check(melody.call() == [60] and surface.waves.is_empty(), "a slow frame hits within reach only (%s, %d)" % [str(melody.call()), outer - inner])
	Midi.message_sent.disconnect(spy)
	surface.stop()
	surface.clear_notes()


func _wave_end() -> void:
	var heard: Array = []
	var spy := func(m: PackedByteArray) -> void:
		if (m[0] & 0xF0) == 0x90:
			heard.append([m[1], m[2]])
	Midi.message_sent.connect(spy)
	var four := 4.0 * Settings.BEAT_UNIT
	for fps in [60.0, 144.0, 12.0]:
		for b in [3.5, 3.9, 3.99, 4.0]:
			surface.clear_notes()
			heard.clear()
			surface.add_object(Vector2(b * Settings.BEAT_UNIT, 0), 60, 0)
			surface.add_wave(Wave.new(Vector2.ZERO, 1.0, -1, four))
			_run_frames(3.0, fps, 0.0, RandomNumberGenerator.new())
			_check(heard.size() == 1 and heard[0][1] >= 1, "%d fps: a 4-beat wave hits a note at %s beats" % [fps, b])
			surface.stop()
		surface.clear_notes()
		heard.clear()
		surface.add_object(Vector2(4.05 * Settings.BEAT_UNIT, 0), 60, 0)
		surface.add_wave(Wave.new(Vector2.ZERO, 1.0, -1, four))
		_run_frames(3.0, fps, 0.0, RandomNumberGenerator.new())
		_check(heard.is_empty(), "%d fps: but not past its reach" % fps)
		surface.stop()
	# A relay at the very end of a wave fires too.
	surface.clear_notes()
	var r := surface.add_object(Vector2(four, 0), 60, 0)
	surface.add_modifier(r, "relay")
	surface.get_note(r).emitter().own_reach = 50.0
	surface.add_wave(Wave.new(Vector2.ZERO, 1.0, -1, four))
	var fired := false
	var t := 0.0
	while t < 2.5:
		surface.step(1.0 / 60.0)
		t += 1.0 / 60.0
		fired = fired or surface.get_note(r).emitter().ready_at > 0
	_check(fired, "a relay at the reach fires")
	Midi.message_sent.disconnect(spy)
	surface.stop()
	surface.clear_notes()
