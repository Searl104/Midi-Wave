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
const MIN_AMPLITUDE := 0.01
const EDGE_INSET := 16.0

var waves: Array = []           # of Wave
var notes: Array = []           # of SurfaceObject
var held_slots: Dictionary = {} # keypad slots currently held down

var tools: ToolManager
var drag: ObjectDrag
var selection: Selection
var snapping: Snapping
var history: UndoHistory
var effects: SurfaceEffects

var view_offset := Vector2.ZERO   ## world position of the window's top-left corner
var last_pitch := 60
var last_channel := 0
var skipped_pulses := 0    ## pulses dropped because the surface was full (for testing / HUD)
var clock_usec := 0        ## simulation time; cooldowns and note lengths run on this

var _zoom := 1.0                   # zoom the view was last laid out at (to zoom about the centre)
var _zoom_anchor: Variant = null   # screen point a zoom keeps still
var _next_id := 1
var _hover_id := -1
var _hover_handle := -1
var _pointer := Vector2.ZERO
var _pointer_in := false
var _glow_tex: GradientTexture2D
var _glow_curve := -1.0            # falloff curve the glow texture was built for


func _init() -> void:
	history = UndoHistory.new()
	effects = SurfaceEffects.new()
	selection = Selection.new(self)
	snapping = Snapping.new(self)
	drag = ObjectDrag.new(self)
	tools = ToolManager.new(self)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	view_offset = Settings.view_offset
	_zoom = Settings.zoom()
	load_notes()
	Settings.changed.connect(_on_setting_changed)


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
		if not o.emitter.attached:
			box = box.expand(o.emitter.pos)
	pan_by((box.get_center() - view_offset) * z() - size / 2.0)


func is_on_screen(world_pos: Vector2, margin: float = 0.0) -> bool:
	return Rect2(Vector2.ZERO, size).grow(margin).has_point(to_screen(world_pos))


## Where the pointer is, for hover and the reach glow; `inside` = false when it has left.
func set_pointer(pos: Vector2, inside: bool = true) -> void:
	_pointer = pos
	_pointer_in = inside
	_hover_handle = handle_at(pos) if inside else -1
	_hover_id = (note_at(pos) if _hover_handle == -1 else -1) if inside else -1


func hovered_note() -> int:
	return _hover_id


func hovered_handle() -> int:
	return _hover_handle


func note_at(screen_pos: Vector2) -> int:
	var best := -1
	var best_d := SurfaceObject.RADIUS + 6.0
	for o in notes:
		var d := screen_pos.distance_to(to_screen(o.pos))
		if d < best_d:
			best_d = d
			best = o.id
	return best


func handle_at(screen_pos: Vector2) -> int:
	for o in notes:
		if o.mode != SurfaceObject.Mode.NOTE and screen_pos.distance_to(o.emitter.handle_screen_pos(self, o)) <= Emitter.HANDLE_RADIUS + 4.0:
			return o.id
	return -1


func get_note(id: int) -> SurfaceObject:
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


## Makes the objects in `layout`.
func _build(layout: Array) -> void:
	notes.clear()
	# Objects keep their ids across saves, so snap memories ("n<id>" / "e<id>") stay valid.
	var used := {}
	var hybrids: Array = []             # ids saved as the old note + pulse hybrid
	for d in layout:
		var saved := int(d.get("id", 0))
		if saved > 0 and not used.has(saved):
			used[saved] = true
			_next_id = maxi(_next_id, saved + 1)
	for d in layout:
		var p := Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0)))
		var saved_mode := int(d.get("mode", SurfaceObject.Mode.NOTE))
		var relay := saved_mode == SurfaceObject.Mode.RELAY or saved_mode == SurfaceObject.LEGACY_NOTE_PULSE
		var id := add_object(p, int(d.get("note", 60)), int(d.get("channel", 0)),
				SurfaceObject.Mode.RELAY if relay else SurfaceObject.Mode.NOTE)
		var o := get_note(id)
		var saved := int(d.get("id", 0))
		if saved > 0 and used.get(saved, false):
			o.id = saved
			used[saved] = false             # each saved id is used once
		o.load_dict(d, p)
		if saved_mode == SurfaceObject.LEGACY_NOTE_PULSE:
			hybrids.append(o.id)
	# An old note + pulse hybrid becomes a Relay plus a plain Note on the same spot, so it still
	# sounds and still pulses.
	for hid in hybrids:
		var h := get_note(hid)
		var nn := get_note(add_object(h.pos, h.note, h.channel))
		nn.slot = h.slot
		nn.muted = h.muted
		nn.modifier = Modifier.create(h.mod_kind())
		if nn.modifier:
			nn.modifier.set_start(h.modifier.start)
	if not hybrids.is_empty():
		save_notes()


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


## Rebuilds the objects from a layout snapshot, keeping live play state (toggles, cooldowns) and
## the selection for objects that survive.
func _apply_snapshot(snap: Array) -> void:
	var live := {}
	for o in notes:
		o.silence()
		live[o.id] = [o.mod_kind(), o.modifier.on if o.modifier else true, o.emitter.ready_at]
	history.begin_restore()
	Settings.notes = snap.duplicate(true)
	load_notes()
	history.end_restore()
	for o in notes:
		if live.has(o.id) and live[o.id][0] == o.mod_kind():
			if o.modifier:
				o.modifier.on = live[o.id][1]
			o.emitter.ready_at = live[o.id][2]
	selection.prune()
	_hover_id = -1
	Settings.queue_save()
	notes_changed.emit()


# --- Editing -------------------------------------------------------------------------------

func add_object(world_pos: Vector2, pitch: int, channel: int, type: int = SurfaceObject.Mode.NOTE) -> int:
	var id := _next_id
	while get_note(id):
		id += 1
	_next_id = id + 1
	var o := SurfaceObject.create(type)
	o.id = id
	o.pos = world_pos
	o.note = clampi(pitch, 0, 127)
	o.channel = clampi(channel, 0, 15)
	o.emitter.pos = world_pos
	notes.append(o)
	return id


func add_note_at(screen_pos: Vector2, pitch: int, channel: int) -> int:
	var id := add_object(snapping.grid_snap(to_world(screen_pos)), Scales.quantize(pitch, Settings.root_note, Settings.scale_name), channel)
	last_pitch = pitch
	last_channel = channel
	save_notes()
	return id


func set_note_pitch(id: int, pitch: int) -> void:
	var o := get_note(id)
	if o == null:
		return
	o.silence()
	o.note = pitch
	last_pitch = pitch
	save_notes()


## Moves the selection (or the hovered object) one scale step down / up, or with `octave` a whole
## octave. One that would leave the MIDI range stays put. Each moved note plays its new pitch
## (up to 8) and flashes. Returns how many moved.
func nudge_pitch(steps: int, octave: bool) -> int:
	var ids: Array = selection.notes.keys() if not selection.notes.is_empty() else ([_hover_id] if _hover_id != -1 else [])
	var moved := 0
	var heard := {}
	for id in ids:
		var o := get_note(id)
		if o == null:
			continue
		var p: int = o.note + 12 * steps if octave else Scales.step(o.note, steps, Settings.root_note, Settings.scale_name)
		if p < 0 or p > 127 or p == o.note:
			continue
		o.silence()
		o.note = p
		last_pitch = p
		moved += 1
		effects.flash_brackets(o)
		if o.mode != SurfaceObject.Mode.RELAY and not o.muted and heard.size() < 8 and not heard.has([p, o.channel]):
			heard[[p, o.channel]] = true
			Midi.play_note(p, 90, 0.25, o.channel)
	if moved > 0:
		save_notes()
	return moved


func set_note_channel(id: int, channel: int) -> void:
	var o := get_note(id)
	if o == null:
		return
	o.silence()
	o.channel = channel
	last_channel = channel
	save_notes()


## Note <-> Relay, for the whole group.
func cycle_mode(id: int) -> void:
	var o := get_note(id)
	if o == null:
		return
	var type: int = SurfaceObject.Mode.RELAY if o.mode == SurfaceObject.Mode.NOTE else SurfaceObject.Mode.NOTE
	for gid in selection.group_for(id):
		set_note_mode(gid, type)


## Swaps the object for one of the new type, keeping everything it has. A relay that gets switched
## on is ready to fire.
func set_note_mode(id: int, type: int) -> void:
	var o := get_note(id)
	if o == null:
		return
	if type != SurfaceObject.Mode.RELAY and type != SurfaceObject.LEGACY_NOTE_PULSE:
		type = SurfaceObject.Mode.NOTE
	else:
		type = SurfaceObject.Mode.RELAY  # the hybrid is gone: a pulsing note is a relay
	if o.mode == SurfaceObject.Mode.NOTE and type != SurfaceObject.Mode.NOTE:
		o.emitter.ready_at = 0
	if type == SurfaceObject.Mode.RELAY:
		o.silence()
	notes[notes.find(o)] = o.converted(type)
	save_notes()


## Pulse strength (0-1) and cooldown in beats (tempo-locked, at least the minimum).
func set_pulse_params(id: int, strength: float, cooldown: float) -> void:
	var o := get_note(id)
	if o == null:
		return
	o.emitter.strength = clampf(strength, 0.05, 1.0)
	o.emitter.cooldown = Emitter.clamp_cooldown(cooldown)
	o.emitter.ready_at = mini(o.emitter.ready_at, clock_usec + o.emitter.cooldown_usec())
	save_notes()


## Attaches a modifier ("" removes it). A new toggle starts on.
func set_modifier(id: int, kind: String) -> void:
	var o := get_note(id)
	if o == null or (kind != "" and not Modifier.KINDS.has(kind)):
		return
	o.modifier = Modifier.create(kind)
	save_notes()


## A state the user sets is the modifier's intended start state: sets current and start.
func set_modifier_state(id: int, on: bool) -> void:
	var o := get_note(id)
	if o == null or o.modifier == null:
		return
	o.modifier.set_state(on)
	save_notes()


## Save state: every modifier's current state becomes its start state.
func save_state() -> void:
	for o in notes:
		if o.modifier:
			o.modifier.save_start()
	save_notes()


## Puts an object (and its group) in a keypad slot; again takes it out.
func toggle_slot(id: int, slot: int) -> void:
	var o := get_note(id)
	if o == null or slot < 1 or slot > 9:
		return
	var target: int = 0 if o.slot == slot else slot
	for gid in selection.group_for(id):
		get_note(gid).slot = target
		effects.flash_brackets(get_note(gid))
	save_notes()


## Mutes the selection (or the hovered object). If any of them is unmuted they all mute,
## otherwise they all unmute.
func toggle_mute() -> int:
	var ids: Array = []
	if not selection.notes.is_empty():
		ids = selection.notes.keys()
	elif _hover_id != -1:
		ids = [_hover_id]
	if ids.is_empty():
		return 0
	var mute := false
	for id in ids:
		var o := get_note(id)
		if o and not o.muted:
			mute = true
	for id in ids:
		var o := get_note(id)
		if o == null:
			continue
		o.muted = mute
		if mute:
			o.silence()
		effects.flash_brackets(o)
	save_notes()
	return ids.size()


func delete_selection() -> void:
	for id in selection.notes.keys():
		var o := get_note(id)
		if o:
			o.silence()
			effects.flash_brackets(o)
			notes.erase(o)
	selection.clear()
	_hover_id = -1
	save_notes()


func remove_note(id: int) -> void:
	var o := get_note(id)
	if o:
		o.silence()
		effects.flash_brackets(o)
		notes.erase(o)
	if _hover_id == id:
		_hover_id = -1
	selection.notes.erase(id)
	save_notes()


func clear_notes() -> void:
	for o in notes:
		o.silence()
	notes.clear()
	selection.clear()
	save_notes()


func _on_setting_changed(key: String) -> void:
	if key == "beat_spacing":
		# Zoom about the anchor or the centre of the window.
		var anchor_s: Vector2 = _zoom_anchor if _zoom_anchor != null else size / 2.0
		var anchor_w := view_offset + anchor_s / _zoom
		_zoom = z()
		view_offset = anchor_w - anchor_s / _zoom
		Settings.view_offset = view_offset
	if key == "root_note" or key == "scale_name":
		for o in notes:
			var q := Scales.quantize(o.note, Settings.root_note, Settings.scale_name)
			if q != o.note:
				o.silence()
				o.note = q
		save_notes()


# --- Playing -------------------------------------------------------------------------------

## A wave from the user at a screen position.
func spawn_wave(screen_origin: Vector2, strength: float = -1.0) -> void:
	add_wave(Wave.new(to_world(screen_origin), Settings.wave_strength if strength < 0.0 else strength, -1))


## Adds a user wave. If the surface is full, the oldest wave makes room.
func add_wave(w: Wave) -> void:
	waves.append(w)
	while waves.size() > MAX_WAVES:
		waves.pop_front()


func click_note(id: int) -> void:
	var o := get_note(id)
	if o:
		o.clicked(self)


## Triggers an object as if a wave at click strength had just reached it. Modifiers and cooldown
## apply as for any hit. No click wave is sent.
func trigger_note(id: int) -> void:
	var o := get_note(id)
	if o == null:
		return
	var spawned: Array = []
	o.hit(self, Settings.wave_strength, clock_usec, spawned)
	waves.append_array(spawned)


## Slot press: fires the slot once, then while it stays held its relays refire each time their
## cooldown runs out. Plain notes fire only on the press.
func press_slot(slot: int) -> void:
	held_slots[slot] = true
	trigger_slot(slot)
	for o in notes:
		if o.slot == slot and o is Relay:
			o.emitter.hold_next = clock_usec + o.emitter.cooldown_usec()


func release_slot(slot: int) -> void:
	held_slots.erase(slot)


func release_all_slots() -> void:
	held_slots.clear()


## Every object in the slot is clicked once. Muted ones are skipped.
func trigger_slot(slot: int) -> int:
	var count := 0
	for o in notes.duplicate():
		if o.slot == slot and not o.muted:
			click_note(o.id)
			count += 1
	return count


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
		if w.finished():
			waves.remove_at(i)
			if i < fresh_from:
				fresh_from -= 1
			continue
		for o in notes:
			w.try_hit(self, o, now, spawned)
		# Waves fired by relays join the loop now, at radius 0, so a note sitting on the emitter
		# is hit this same frame: a stacked chain plays as one chord instead of one link per
		# frame. Cooldowns and MAX_WAVES keep this from running away.
		waves.append_array(spawned)
		spawned.clear()
		i += 1

	# Held slots: relays refire each time their cooldown runs out (a refire that a toggle
	# silences still waits a full cooldown before the next).
	if not held_slots.is_empty():
		for o in notes.duplicate():
			if held_slots.has(o.slot) and o is Relay and not o.muted and not o.emitter.is_retrigger() \
					and now >= o.emitter.hold_next:
				o.emitter.hold_next = now + o.emitter.cooldown_usec()
				trigger_note(o.id)

	for o in notes:
		o.tick(delta, now)
	effects.tick(delta)


# --- Drawing -------------------------------------------------------------------------------

func _draw() -> void:
	var font := get_theme_default_font()
	var now := clock_usec
	var margin := SurfaceObject.RADIUS + 40.0
	var dragging_item: bool = not drag.info.is_empty() and not drag.info.get("range_edit", false)

	if _pointer_in:
		_draw_reach_glow(_pointer)
	for o in notes:
		if o is Relay:
			o.emitter.draw_limit_ring(self, o, drag.editing_reach_of(o.id))

	if dragging_item:
		drag.draw_rings()
	else:
		# Grids that are on stay faintly visible when nothing is being dragged.
		var grids := snapping.active_grids()
		for key in grids:
			Grid.draw_guide(self, grids[key][1], 0.32 * Settings.guide_brightness, Settings.guide_divisions)

	for w in waves:
		w.draw(self)
	effects.draw_splashes(self)

	# Emitter tethers sit under the notes.
	for o in notes:
		if o is Relay and not o.emitter.attached:
			o.emitter.draw_tether(self, o)

	for o in notes:
		if is_on_screen(o.pos, margin):
			o.draw(self, font, now)
		else:
			o.draw_edge_marker(self)

	# Emitter diamonds go over every note, so a note can never hide one.
	for o in notes:
		if o is Relay:
			var hp: Vector2 = o.emitter.handle_screen_pos(self, o)
			if hp.x > -40.0 and hp.y > -40.0 and hp.x < size.x + 40.0 and hp.y < size.y + 40.0:
				o.emitter.draw_handle(self, hp, Palette.channel_color(o.channel), o.id == _hover_handle)

	# Hover and selection are boxes (white corner brackets), so rings only ever mean state.
	for o in notes:
		if not is_on_screen(o.pos, margin):
			continue
		if selection.notes.has(o.id):
			draw_brackets(to_screen(o.pos), o.bracket_half() + 2.0, 2.0, 0.95, 0.42)
		elif o.id == _hover_id and not drag.active():
			draw_brackets(to_screen(o.pos), o.bracket_half(), 1.0, 0.55, 0.28)
	for eid in selection.emitters:
		var en := get_note(eid)
		if en and en is Relay and not en.emitter.attached:
			draw_brackets(en.emitter.handle_screen_pos(self, en), Emitter.HANDLE_RADIUS + 6.0, 2.0, 0.95, 0.42)
	effects.draw_bracket_flashes(self)
	tools.draw_overlay(self)

	if not drag.info.is_empty():
		if dragging_item:
			drag.draw_touches()
		drag.draw_readout(font)
	elif _hover_id != -1 and not drag.active():
		var hovered := get_note(_hover_id)
		if hovered:
			hovered.draw_tooltip(self, font)


## Faint glow under the pointer showing how far a wave from here reaches and how it fades:
## brightness follows the wave's amplitude (strength x falloff curve) out to its reach.
func _draw_reach_glow(at: Vector2) -> void:
	var g: float = Settings.cursor_glow        # Options -> Wave -> Cursor glow (0 = off)
	if g <= 0.0:
		return
	var reach := Settings.wave_range * z()
	draw_texture_rect(_reach_texture(), Rect2(at - Vector2(reach, reach), Vector2(reach, reach) * 2.0),
			false, Color(1, 1, 1, minf(0.2 * Settings.wave_strength * g, 1.0)))
	draw_arc(at, reach, 0.0, TAU, maxi(64, int(reach / 6.0)), Color(Palette.ACCENT, minf(0.10 * g, 1.0)), 1.0, true)


func _reach_texture() -> GradientTexture2D:
	if _glow_tex == null or not is_equal_approx(_glow_curve, Settings.falloff_curve):
		_glow_curve = Settings.falloff_curve
		var g := Gradient.new()
		var offsets := PackedFloat32Array()
		var colors := PackedColorArray()
		for i in 17:
			var t := i / 16.0
			offsets.append(t)
			colors.append(Color(Palette.ACCENT.lightened(0.15), pow(1.0 - t, _glow_curve)))
		g.offsets = offsets
		g.colors = colors
		_glow_tex = GradientTexture2D.new()
		_glow_tex.gradient = g
		_glow_tex.width = 256
		_glow_tex.height = 256
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1.0, 0.5)
	return _glow_tex


## Four white corner brackets around `at`. `arm` is each bracket's length as a share of the side.
func draw_brackets(at: Vector2, half: float, width: float, alpha: float, arm: float) -> void:
	var col := Color(1, 1, 1, alpha)
	var l := half * 2.0 * arm
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var c := at + Vector2(sx, sy) * half
			draw_polyline(PackedVector2Array([c - Vector2(sx * l, 0), c, c - Vector2(0, sy * l)]), col, width, true)
