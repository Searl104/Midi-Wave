class_name WaveSurface
extends Control
## The liquid surface: holds the view and the objects and waves on it, runs the simulation and
## draws everything in order. Rules live with what they apply to: see scripts/entities for
## objects and waves, scripts/surface for undo, selection, snapping and effects, and
## scripts/tools for what each tool does.
##
## Everything lives in world units (Settings.BEAT_UNIT per beat); the window shows the part
## starting at `view_offset`, scaled by the zoom (beat spacing / BEAT_UNIT). Icons (notes,
## rings, tabs, handles, labels) are drawn at a fixed screen size whatever the zoom.
## The canvas is unbounded. Waves and notes keep playing off screen, with edge markers.

signal notes_changed

const MAX_WAVES := 64           ## must match MAX_WAVES in water.gdshader
const EDGE_INSET := 16.0
const BRUSH_ID := -2            ## get_note() id of the Draw brush, so rings can edit it

var waves: Array = []           # of Wave
var notes: Array = []           # of Note
var held_bindings: Dictionary = {}   # bindings currently held down
var held_tap := -1                 ## a relay pressed in Tap during its cooldown, while held

var tools: ToolManager
var drag: ObjectDrag
var selection: Selection
var snapping: Snapping
var history: UndoHistory
var effects: SurfaceEffects
var editing: SurfaceEditing
var drawing: SurfaceDrawing

var view_offset := Vector2.ZERO   ## world position of the window's top-left corner
var last_pitch := 60
var last_channel := 0
var skipped_pulses := 0    ## pulses dropped because the surface was full (for testing / HUD)
var clock_usec := 0        ## simulation time; cooldowns and note lengths run on this

var _zoom := 1.0                   # zoom the view was last laid out at (to zoom about the centre)
var _zoom_anchor: Variant = null   # screen point a zoom keeps still
var _hover_id := -1
var _hover_handle := -1
var _pointer := Vector2.ZERO
var _pointer_in := false


func _init() -> void:
	history = UndoHistory.new()
	effects = SurfaceEffects.new()
	editing = SurfaceEditing.new(self)
	drawing = SurfaceDrawing.new(self)
	selection = Selection.new(self)
	snapping = Snapping.new(self)
	drag = ObjectDrag.new(self)
	tools = ToolManager.new(self)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	view_offset = Settings.view_offset
	_zoom = Settings.zoom()
	load_notes()
	Settings.changed.connect(_on_setting_changed)


func _gui_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm:
		set_pointer(mm.position)
	if tools.handle_input(event):
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if tools.handle_input(event):
		get_viewport().set_input_as_handled()


## A collection dragged from its panel.
func _can_drop_data(at: Vector2, data: Variant) -> bool:
	if not data is Dictionary or not data.has("collection"):
		return false
	tools.get_tool("collection").hover_drop(data["collection"], at)
	return true


func _drop_data(at: Vector2, data: Variant) -> void:
	tools.get_tool("collection").drop(data["collection"], at, Input.is_key_pressed(KEY_ALT))


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		tools.get_tool("collection").end_drop()
	if what == NOTIFICATION_MOUSE_EXIT:
		set_pointer(_pointer, false)


# --- Coordinates and view ------------------------------------------------------------------

func z() -> float:
	return Settings.zoom()


func to_world(screen_pos: Vector2) -> Vector2:
	return screen_pos / z() + view_offset


func to_screen(world_pos: Vector2) -> Vector2:
	return (world_pos - view_offset) * z()


func pan_by(screen_delta: Vector2) -> void:
	if screen_delta == Vector2.ZERO:
		return
	view_offset += screen_delta / z()
	Settings.view_offset = view_offset
	Settings.queue_save()


## Zooms (beat spacing) by `factor`, keeping the world point under `at` still.
func zoom_at(at: Vector2, factor: float) -> void:
	var v := clampf(Settings.beat_spacing * factor, Settings.BEAT_SPACING_MIN, Settings.BEAT_SPACING_MAX)
	if is_equal_approx(v, Settings.beat_spacing):
		return
	_zoom_anchor = at
	Settings.set_value("beat_spacing", v)
	_zoom_anchor = null


## Centres the window on the objects (and any detached emitters).
func frame_notes() -> void:
	if notes.is_empty():
		return
	var box := Rect2(notes[0].pos, Vector2.ZERO)
	for o in notes:
		box = box.expand(o.pos)
		var e: Emitter = o.emitter()
		if e and not e.attached:
			box = box.expand(e.pos)
	pan_by((box.get_center() - view_offset) * z() - size / 2.0)


func is_on_screen(world_pos: Vector2, margin: float = 0.0) -> bool:
	return Rect2(Vector2.ZERO, size).grow(margin).has_point(to_screen(world_pos))


## Where the pointer is, for hover and the reach glow; `inside` = false when it has left.
func set_pointer(pos: Vector2, inside: bool = true) -> void:
	_pointer = pos
	_pointer_in = inside
	var hit := pick_at(pos) if inside else []
	_hover_id = hit[1] if not hit.is_empty() and hit[0] == "note" else -1
	_hover_handle = hit[1] if not hit.is_empty() and hit[0] == "emitter" else -1


func pointer() -> Vector2:
	return _pointer


func pointer_inside() -> bool:
	return _pointer_in


func hovered_note() -> int:
	return _hover_id


func hovered_handle() -> int:
	return _hover_handle


## Forgets the hovered note: any, or only `only_id` when given.
func unhover_note(only_id: int = -1) -> void:
	if only_id == -1 or _hover_id == only_id:
		_hover_id = -1


func note_at(screen_pos: Vector2) -> int:
	var best := -1
	var best_d := Note.RADIUS + 6.0
	for o in notes:
		var d := screen_pos.distance_to(to_screen(o.pos))
		if d < best_d:
			best_d = d
			best = o.id
	return best


## What a click at a screen position lands on, top first: a diamond or dim handle on a note, then
## a note, then a remote diamond, which draws under notes. ["note" or "emitter", id], or [] if none.
func pick_at(screen_pos: Vector2) -> Array:
	var reach := Emitter.HANDLE_RADIUS + 4.0
	for o in notes:
		var e: Emitter = o.emitter()
		if e and screen_pos.distance_to(e.dock_screen_pos(self, o)) <= reach:
			return ["emitter", o.id]
	var hit := note_at(screen_pos)
	if hit != -1:
		return ["note", hit]
	for o in notes:
		var e: Emitter = o.emitter()
		if e and screen_pos.distance_to(e.handle_screen_pos(self, o)) <= reach:
			return ["emitter", o.id]
	return []


## The note and modifier whose tab is at a screen position: [note, modifier], or [] if none.
func tab_at(screen_pos: Vector2) -> Array:
	for o in notes:
		var m: Modifier = o.tab_at(self, screen_pos)
		if m:
			return [o, m]
	return []


func get_note(id: int) -> Note:
	if id == BRUSH_ID:
		return _brush()
	for o in notes:
		if o.id == id:
			return o
	return null


# --- Layout --------------------------------------------------------------------------------

func load_notes() -> void:
	history.begin_load()
	_build(Settings.notes)
	if notes.is_empty():
		seed_default_layout()
	history.end_load(Settings.notes)


## Replaces everything with a saved-format layout, as one undoable edit, and frames it.
func load_layout(layout: Array) -> void:
	stop()
	for o in notes:
		o.silence()
	selection.clear()
	_hover_id = -1
	_hover_handle = -1
	history.end_group()
	_build(layout)
	save_notes()
	frame_notes()


## Replaces everything with a saved layout, leaving the view alone and clearing the undo history.
func replace_layout(layout: Array) -> void:
	stop()
	for o in notes:
		o.silence()
	selection.clear()
	_hover_id = -1
	_hover_handle = -1
	history.begin_load()
	_build(layout)
	save_notes()
	history.end_load(Settings.notes)


func _brush() -> Note:
	return tools.get_tool("draw").brush


## Makes the objects in `layout`.
func _build(layout: Array) -> void:
	notes.clear()
	# Objects keep their ids across saves, so snap memories ("n<id>" / "e<id>") stay valid.
	var used := {}
	for d in layout:
		var saved := int(d.get("id", 0))
		if saved > 0 and not used.has(saved):
			used[saved] = true
			editing.reserve_id(saved)
	for d in layout:
		var p := Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0)))
		var id := add_object(p, int(d.get("note", 60)), int(d.get("channel", 0)))
		var o := get_note(id)
		var saved := int(d.get("id", 0))
		if saved > 0 and used.get(saved, false):
			o.id = saved
			used[saved] = false             # each saved id is used once
		o.load_dict(d, p)


func seed_default_layout() -> void:
	var pitches := Scales.octave_notes(4, Settings.root_note, Settings.scale_name)
	pitches.append_array(Scales.octave_notes(5, Settings.root_note, Settings.scale_name).slice(0, 3))
	var view := size if size.x > 64.0 else Vector2(1280, 800)
	var centre := to_world(view / 2.0)
	var count := pitches.size()
	for i in count:
		var a := -PI / 2.0 + TAU * i / count
		add_object(centre + Vector2(cos(a) * view.x * 0.26, sin(a) * view.y * 0.32) / z(), pitches[i], 0)
	save_notes()


func save_notes() -> void:
	var out: Array = []
	for o in notes:
		out.append(o.to_dict())
	Settings.notes = out
	Settings.brush = _brush().to_dict()
	history.record(out)
	Settings.queue_save()
	notes_changed.emit()


func undo() -> bool:
	if not history.can_undo() or drag.active():
		return false
	_apply_snapshot(history.step_back())
	return true


func redo() -> bool:
	if not history.can_redo() or drag.active():
		return false
	_apply_snapshot(history.step_forward())
	return true


## Rebuilds the objects from a layout snapshot, keeping live play state (sequences, cooldowns) and
## the selection for objects that survive.
func _apply_snapshot(snap: Array) -> void:
	var live := {}
	for o in notes:
		o.silence()
		var state := {}
		for m in o.modifiers:
			state[m.kind()] = m.live_state()
		live[o.id] = state
	history.begin_restore()
	Settings.notes = snap.duplicate(true)
	load_notes()
	history.end_restore()
	for o in notes:
		for m in o.modifiers:
			if live.has(o.id) and live[o.id].has(m.kind()):
				m.restore_state(live[o.id][m.kind()])
	selection.prune()
	_hover_id = -1
	Settings.queue_save()
	notes_changed.emit()


# --- Editing -------------------------------------------------------------------------------

## These forward to SurfaceEditing, which holds the code.

func add_object(world_pos: Vector2, pitch: int, channel: int) -> int:
	return editing.add_object(world_pos, pitch, channel)


func add_note_at(screen_pos: Vector2, pitch: int, channel: int) -> int:
	return editing.add_note_at(screen_pos, pitch, channel)


func set_note_pitch(id: int, pitch: int) -> void:
	editing.set_note_pitch(id, pitch)


## Moves the selection (or the hovered object) one scale step down / up, or with `octave` a whole
## octave. One that would leave the MIDI range stays put. Each moved note plays its new pitch
## (up to 8) and flashes. Returns how many moved.
func nudge_pitch(steps: int, octave: bool) -> int:
	return editing.nudge_pitch(steps, octave)


func set_note_channel(id: int, channel: int) -> void:
	editing.set_note_channel(id, channel)


## Pulse strength (0-1) and cooldown in beats (tempo-locked, at least the minimum), on a relay.
func set_pulse_params(id: int, strength: float, cooldown: float) -> void:
	editing.set_pulse_params(id, strength, cooldown)


## Adds a modifier if the object doesn't have it. A new relay sounds and is ready to fire; a new
## sequence is on an On step.
func add_modifier(id: int, kind: String) -> void:
	editing.add_modifier(id, kind)


func remove_modifier(id: int, kind: String) -> void:
	editing.remove_modifier(id, kind)


func clear_modifiers(id: int) -> void:
	editing.clear_modifiers(id)


## A relay's Sound: off makes it Silent and hollow; its pitch is kept.
func set_relay_sound(id: int, on: bool) -> void:
	editing.set_relay_sound(id, on)


## Sets a note's share of a hit's strength, 1-100.
func set_note_velocity(id: int, value: int) -> void:
	editing.set_note_velocity(id, value)


## Sets how many steps a sequence has.
func set_sequence_count(id: int, count: int) -> void:
	editing.set_sequence_count(id, count)


## Turns one step of a sequence On or Off.
func set_sequence_step(id: int, index: int, on: bool) -> void:
	editing.set_sequence_step(id, index, on)


## Sets what fires an object ("" clears it).
func set_binding(id: int, binding: String) -> void:
	editing.set_binding(id, binding)


## Mutes the selection (or the hovered object). If any of them is unmuted they all mute,
## otherwise they all unmute.
func toggle_mute() -> int:
	return editing.toggle_mute()


func delete_selection() -> void:
	editing.delete_selection()


func remove_note(id: int) -> void:
	editing.remove_note(id)


func clear_notes() -> void:
	editing.clear_notes()
func _on_setting_changed(key: String) -> void:
	if key == "beat_spacing":
		# Zoom about the anchor or the centre of the window.
		var anchor_s: Vector2 = _zoom_anchor if _zoom_anchor != null else size / 2.0
		var anchor_w := view_offset + anchor_s / _zoom
		_zoom = z()
		view_offset = anchor_w - anchor_s / _zoom
		Settings.view_offset = view_offset


# --- Playing -------------------------------------------------------------------------------

## A wave from the user at a screen position.
func spawn_wave(screen_origin: Vector2, strength: float = -1.0) -> void:
	add_wave(Wave.new(to_world(screen_origin), Settings.wave_strength if strength < 0.0 else strength, -1))


## Adds a user wave. If the surface is full, the oldest wave makes room.
func add_wave(w: Wave) -> void:
	waves.append(w)
	while waves.size() > MAX_WAVES:
		waves.pop_front()


## Triggers an object as if a wave at click strength had just reached it. Modifiers and cooldown
## apply as for any hit. No click wave is sent.
func trigger_note(id: int) -> void:
	var o := get_note(id)
	if o == null:
		return
	var spawned: Array = []
	o.hit(self, Settings.wave_strength, clock_usec, spawned)
	waves.append_array(spawned)


## A binding went down: every object on it fires as a tap, and while it stays held its relays
## refire each time their cooldown runs out.
func press_binding(binding: String) -> void:
	held_bindings[binding] = true
	for o in notes.duplicate():
		if o.binding != binding:
			continue
		var e: Emitter = o.emitter()
		if e and e.cooling(clock_usec):
			e.hold_next = e.ready_at         # nothing yet: it fires when this ends, if still held
			continue
		o.tap(self)
		if e:
			e.hold_next = clock_usec + e.cooldown_usec()


func release_binding(binding: String) -> void:
	held_bindings.erase(binding)


func release_all_bindings() -> void:
	held_bindings.clear()
	held_tap = -1


## Stop: clears all waves and returns every modifier to its start state. Cooldowns keep running,
## so a relay that just fired can't be re-fired straight away by a reset.
func stop() -> void:
	waves.clear()
	for o in notes:
		o.reset()


func shader_waves() -> PackedVector4Array:
	var out := PackedVector4Array()
	out.resize(MAX_WAVES)
	for i in mini(waves.size(), MAX_WAVES):
		out[i] = waves[i].shader_value(self)
	return out


func _process(delta: float) -> void:
	step(delta)
	queue_redraw()


## Advances the simulation by `delta` seconds. Split out so tests can drive it directly.
## Radius grows by the current speed each step, so a tempo change takes effect smoothly.
func step(delta: float) -> void:
	clock_usec += int(delta * 1_000_000.0)
	var now := clock_usec
	var speed := Settings.wave_speed
	var spawned: Array = []
	var fresh_from := waves.size()   # waves at or past this index were fired this frame
	var i := 0
	while i < waves.size():
		var w: Wave = waves[i]
		if i < fresh_from:
			w.grow(delta * speed)
		# Hits come first: on a slow frame a wave can reach its end and pass objects in one step.
		for o in notes:
			w.try_hit(self, o, now, spawned)
		# Waves fired by relays join the loop now, at radius 0, so a note sitting on the emitter
		# is hit this same frame: a stacked chain plays as one chord instead of one link per
		# frame. Cooldowns and MAX_WAVES keep this from running away.
		waves.append_array(spawned)
		spawned.clear()
		if w.finished():
			waves.remove_at(i)
			if i < fresh_from:
				fresh_from -= 1
			continue
		i += 1

	# A tap held through a cooldown fires once as it ends.
	if held_tap != -1:
		var tapped := get_note(held_tap)
		if tapped == null or tapped.emitter() == null:
			held_tap = -1
		elif not tapped.emitter().cooling(now):
			held_tap = -1
			tapped.tap(self)

	# Held bindings: relays refire each time their cooldown runs out (a refire that a sequence
	# silences still waits a full cooldown before the next). Retrigger relays don't refire.
	if not held_bindings.is_empty():
		for o in notes.duplicate():
			var e: Emitter = o.emitter()
			if e and held_bindings.has(o.binding) and not e.is_retrigger() and now >= e.hold_next:
				e.hold_next = now + e.cooldown_usec()
				o.tap(self)

	for o in notes:
		o.tick(delta, now)
	effects.tick(delta)


# --- Drawing -------------------------------------------------------------------------------

func _draw() -> void:
	drawing.draw()


## Four white corner brackets around `at`. `arm` is each bracket's length as a share of the side.
func draw_brackets(at: Vector2, half: float, width: float, alpha: float, arm: float) -> void:
	drawing.brackets(at, half, width, alpha, arm)
