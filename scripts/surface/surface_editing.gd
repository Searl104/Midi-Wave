class_name SurfaceEditing
extends RefCounted
## Every change to the objects on the surface: adding, moving pitch and Sound, modifiers,
## velocity, sequences, bindings, mute and delete. Each one saves, which records an undo step.
## WaveSurface forwards these, so callers use `surface.set_note_pitch(...)` and so on.

var surface: WaveSurface
var _next_id := 1


func _init(owner_surface: WaveSurface) -> void:
	surface = owner_surface


## Keeps ids handed out from now on above `saved`, so a loaded layout's ids stay unique.
func reserve_id(saved: int) -> void:
	_next_id = maxi(_next_id, saved + 1)


func add_object(world_pos: Vector2, pitch: int, channel: int) -> int:
	var id := _next_id
	while surface.get_note(id):
		id += 1
	_next_id = id + 1
	var o := Note.new()
	o.id = id
	o.pos = world_pos
	o.note = clampi(pitch, 0, 127)
	o.channel = clampi(channel, 0, 15)
	surface.notes.append(o)
	return id


func add_note_at(screen_pos: Vector2, pitch: int, channel: int) -> int:
	var id := add_object(surface.snapping.grid_snap(surface.to_world(screen_pos)), Scales.quantize(pitch, Settings.root_note, Settings.scale_name), channel)
	surface.last_pitch = pitch
	surface.last_channel = channel
	surface.save_notes()
	return id


func set_note_pitch(id: int, pitch: int) -> void:
	var o := surface.get_note(id)
	if o == null:
		return
	o.silence()
	o.note = pitch
	surface.last_pitch = pitch
	surface.save_notes()


## Moves the surface.selection (or the hovered object) one scale step down / up, or with `octave` a whole
## octave. One that would leave the MIDI range stays put. Each moved note plays its new pitch
## (up to 8) and flashes. Returns how many moved.
func nudge_pitch(steps: int, octave: bool) -> int:
	var ids: Array = surface.selection.notes.keys() if not surface.selection.notes.is_empty() else ([surface.hovered_note()] if surface.hovered_note() != -1 else [])
	var moved := 0
	var heard := {}
	for id in ids:
		var o := surface.get_note(id)
		if o == null:
			continue
		var p: int = o.note + 12 * steps if octave else Scales.step(o.note, steps, Settings.root_note, Settings.scale_name)
		if p < 0 or p > 127 or p == o.note:
			continue
		o.silence()
		o.note = p
		surface.last_pitch = p
		moved += 1
		surface.effects.flash_brackets(o)
		if o.sounds() and not o.muted and heard.size() < 8 and not heard.has([p, o.channel]):
			heard[[p, o.channel]] = true
			Midi.play_note(p, 90, 0.25, o.channel)
	if moved > 0:
		surface.save_notes()
	return moved


func set_note_channel(id: int, channel: int) -> void:
	var o := surface.get_note(id)
	if o == null:
		return
	o.silence()
	o.channel = channel
	surface.last_channel = channel
	surface.save_notes()


## A relay's cooldown in beats (tempo-locked, at least the minimum; 0 = Retrigger).
func set_cooldown(id: int, cooldown: float) -> void:
	var o := surface.get_note(id)
	if o == null or o.relay() == null:
		return
	var e: Emitter = o.emitter()
	e.cooldown = Emitter.clamp_cooldown(cooldown)
	e.ready_at = mini(e.ready_at, surface.clock_usec + e.cooldown_usec())
	surface.save_notes()


## Adds a modifier if the object doesn't have it. A new relay is ready to fire; a new sequence is
## on an On step; Silent stops a note that's sounding.
func add_modifier(id: int, kind: String) -> void:
	var o := surface.get_note(id)
	if o == null or o.get_modifier(kind):
		return
	var m := Modifier.create(kind)
	if m == null:
		return
	if m is RelayModifier:
		m.emitter.pos = o.pos
	o.add_modifier(m)
	if m is SilentModifier:
		o.silence()
	surface.save_notes()


func remove_modifier(id: int, kind: String) -> void:
	var o := surface.get_note(id)
	if o == null or o.get_modifier(kind) == null:
		return
	o.modifiers.erase(o.get_modifier(kind))
	if kind == "relay":
		surface.selection.emitters.erase(id)
	surface.save_notes()


func clear_modifiers(id: int) -> void:
	var o := surface.get_note(id)
	if o == null or o.modifiers.is_empty():
		return
	o.modifiers.clear()
	surface.selection.emitters.erase(id)
	surface.save_notes()



## Sets a note's share of a hit's strength, 1-100.
func set_note_velocity(id: int, value: int) -> void:
	var o := surface.get_note(id)
	if o == null:
		return
	o.velocity = clampi(value, 1, 100)
	surface.save_notes()


## Sets how many steps a sequence has.
func set_sequence_count(id: int, count: int) -> void:
	var o := surface.get_note(id)
	if o == null or o.get_modifier("sequence") == null:
		return
	o.get_modifier("sequence").set_count(count)
	surface.save_notes()


## Turns one step of a sequence On or Off.
func set_sequence_step(id: int, index: int, on: bool) -> void:
	var o := surface.get_note(id)
	if o == null or o.get_modifier("sequence") == null:
		return
	o.get_modifier("sequence").set_step(index, on)
	surface.save_notes()


## Sets what fires an object ("" clears it).
func set_binding(id: int, binding: String) -> void:
	var o := surface.get_note(id)
	if o == null:
		return
	o.binding = binding
	surface.effects.flash_brackets(o)
	surface.save_notes()


## Mutes the surface.selection (or the hovered object). If any of them is unmuted they all mute,
## otherwise they all unmute.
func toggle_mute() -> int:
	var ids: Array = []
	if not surface.selection.notes.is_empty():
		ids = surface.selection.notes.keys()
	elif surface.hovered_note() != -1:
		ids = [surface.hovered_note()]
	if ids.is_empty():
		return 0
	var mute := false
	for id in ids:
		var o := surface.get_note(id)
		if o and not o.muted:
			mute = true
	for id in ids:
		var o := surface.get_note(id)
		if o == null:
			continue
		o.muted = mute
		if mute:
			o.silence()
		surface.effects.flash_brackets(o)
	surface.save_notes()
	return ids.size()


func delete_selection() -> void:
	for id in surface.selection.notes.keys():
		var o := surface.get_note(id)
		if o:
			o.silence()
			surface.effects.flash_brackets(o)
			surface.notes.erase(o)
	surface.selection.clear()
	surface.unhover_note()
	surface.save_notes()


func remove_note(id: int) -> void:
	var o := surface.get_note(id)
	if o:
		o.silence()
		surface.effects.flash_brackets(o)
		surface.notes.erase(o)
	surface.unhover_note(id)
	surface.selection.notes.erase(id)
	surface.save_notes()


func clear_notes() -> void:
	for o in surface.notes:
		o.silence()
	surface.notes.clear()
	surface.selection.clear()
	surface.save_notes()
