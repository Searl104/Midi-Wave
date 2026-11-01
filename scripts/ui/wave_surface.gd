class_name WaveSurface
extends Control
## The liquid surface. Owns waves and notes, does hit detection, sends MIDI, draws both.
##
## Everything lives in world units (Settings.BEAT_UNIT per beat); the window shows the part
## starting at `view_offset`, scaled by the zoom (beat spacing / BEAT_UNIT). Icons (notes,
## rings, tabs, handles, labels) are drawn at a fixed screen size whatever the zoom.
## A faint glow under the cursor shows a wave's reach and fade; pulser emitters show a faint
## ring at their reach.
## The canvas is unbounded and pans (middle-drag, arrow keys); there is no zoom.
## Waves and notes keep playing off screen; edge markers show off-screen notes firing.
##
## A note is one object with three modes:
##   NOTE        plays its note when a wave hits it
##   NOTE_PULSE  plays its note and emits a new wave from its emitter
##   PULSE       silent; only emits
## A pulsing note emits at its own fixed strength, at most once per cooldown (in beats, so
## it follows the tempo; at least an eighth of a beat), and never
## reacts to waves it emitted itself. Its emitter starts on the note (attached); dragging
## the emitter handle detaches it to a fixed spot on the surface.
##
## Timing rings: while a note or emitter is dragged, rings show around every other note and
## emitter within reach: beats bright, bars brighter, divisions faded. The dragged item snaps
## to the nearest ring; Shift places freely. A readout shows the delay in beats and any pulser loop.
##
## Mouse:  click = wave (on a plain note: a wave from the note; on a pulser: trigger it,
##         no click wave) · drag note = move · drag emitter handle = place emitter
##         right-click (hold / tap) = pitch radial · alt-click = channel radial
##         ctrl-click = cycle mode · ctrl-drag from a pulser = set its own reach
##         ctrl-right-click = pulse radial
##         shift-click = new note · shift-right-click = modifier radial
##         Delete = remove note (or the selection) · middle-drag = pan
##         M = mute / unmute the selection or hovered note (no sound, no pulse; the mode is kept)
##         ctrl + right-drag on empty space = box select; Esc clears it
##
## Selection: dragging a selected note moves the whole group (snapping applies to the note
## held; the group's own notes are never snap targets). Delete removes it; channel, pulse,
## mode, modifier and keypad-slot edits on a selected note apply to every selected note;
## Ctrl+C / Ctrl+V copy and paste it at the cursor.
##
## Modifier ring (one per note). "toggle": on each trigger the note acts on its current
## state, then flips; off silences both its sound and its pulse. Each toggle has a start
## state (set by the user, or by Save state); Stop returns every toggle to it.
##
## Grids: G over a note or emitter turns on a grid centred on it (its timing rings and spokes);
## Ctrl+G turns every grid off. Any number can be on; they are saved with the layout and drawn
## faintly. A dragged item snaps to the nearest grid point (a ring, a spoke, or where they cross),
## and new notes (quick place, Shift-click, paste) land on the nearest grid point under the mouse.
##
## Touch to snap (deprecated, off unless touch_snap=true in the settings file): touching another
## object while dragging toggles it as a snap target too. Touches reset on drop, except the target
## snapped to when dropped, which is remembered for that item's next drag.

signal pitch_menu_requested(note_id: int, at: Vector2)    # note_id -1 = place a new note at `at`
signal channel_menu_requested(note_id: int, at: Vector2)
signal pulse_menu_requested(note_id: int, at: Vector2)
signal modifier_menu_requested(note_id: int, at: Vector2)
signal notes_changed
signal mode_changed(edit: bool)

## Edit mode (default) lets you change the layout. Play mode only plays it: clicks send waves
## or trigger notes, the keypad plays slots, Space stops, the view pans and zooms, and nothing
## can be moved, placed, retuned, muted, deleted or undone.
var edit_mode := true

enum Mode { NOTE, NOTE_PULSE, PULSE }

const MAX_WAVES := 64           ## must match MAX_WAVES in water.gdshader
const NOTE_RADIUS := 22.0
const HANDLE_RADIUS := 7.0
const DRAG_THRESHOLD := 6.0
const MIN_AMPLITUDE := 0.01
const SPLASH_TIME := 0.6
const MIN_COOLDOWN := 0.125       ## beats (an eighth of a beat)
const DEFAULT_PULSE_STRENGTH := 0.8
const DEFAULT_COOLDOWN := 1.0      ## beats
const EDGE_INSET := 16.0
const MOD_RING := 10.0          ## modifier ring radius beyond NOTE_RADIUS
const MODIFIERS := ["toggle"]

const FRACTIONS := {
	"1/2": "½", "1/3": "⅓", "2/3": "⅔", "1/4": "¼", "3/4": "¾", "1/6": "⅙", "5/6": "⅚",
	"1/8": "⅛", "3/8": "⅜", "5/8": "⅝", "7/8": "⅞",
}

var waves: Array = []      # {origin: Vector2 (world), r: float, strength: float, source: int, hits: Dictionary}
var notes: Array = []      # see _add(); pos / emit in world px
var bracket_flashes: Array = []   # {pos: Vector2 (world), half: float, t: float}: a keyboard action landed here
const BRACKET_FLASH_TIME := 0.4
var splashes: Array = []   # {pos: Vector2 (world), t: float, color: Color, strength: float}

var view_offset := Vector2.ZERO   ## world position of the window's top-left corner
var _zoom := 1.0                  ## zoom the view was last laid out at (to zoom about the centre)

var last_pitch := 60
var last_channel := 0
var skipped_pulses := 0    ## pulses dropped because the surface was full (for testing / HUD)

var clock_usec := 0        ## simulation time; cooldowns and note lengths run on this
var drag_info: Dictionary = {}   ## rings + readout for the current drag (empty when not dragging)

var _next_id := 1
var _hover_id := -1
var _hover_handle := -1
var _press_id := -1
var _press_kind := ""      # "note" or "emitter"
var _press_pos := Vector2.ZERO
var _dragging := false
var _pan_active := false
var _pan_moved := false
var _pan_start := Vector2.ZERO
var _pan_last := Vector2.ZERO
var _mouse_pos := Vector2.ZERO
var _mouse_in := false
var _glow_tex: GradientTexture2D
var _glow_curve := -1.0          # falloff curve the glow texture was built for
var _touched: Dictionary = {}     # object keys ("n<id>" / "e<id>") toggled as snap targets this drag
var _overlapping: Dictionary = {} # object keys the held item overlaps right now
var touch_flashes: Array = []     # {pos: Vector2 (world), t: float}
var held_slots: Dictionary = {}   # keypad slots currently held down

# Undo / redo: every edit goes through save_notes(), which records the layout it replaced.
# Edits made in the same frame (a group edit touches several notes) form one step.
const UNDO_LIMIT := 50
var _undo: Array = []             # layout snapshots (copies of Settings.notes), newest last
var _redo: Array = []
var _snapshot: Array = []         # the layout as of the last recorded edit
var _snapshot_ready := false
var _last_edit_frame := -1
var _restoring := false
var selection: Dictionary = {}    # selected note ids (box select: Ctrl + right-drag)
var _group_start: Dictionary = {} # id -> [pos, emit] for the group being dragged
var _box_active := false
var _box_start := Vector2.ZERO
var _box_end := Vector2.ZERO
var _clipboard: Array = []        # copied notes, positions relative to the group centre


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
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


## Centres the window on the notes (and any detached emitters).
func frame_notes() -> void:
	if notes.is_empty():
		return
	var box := Rect2(notes[0].pos, Vector2.ZERO)
	for n in notes:
		box = box.expand(n.pos)
		if not n.attached:
			box = box.expand(n.emit)
	pan_by((box.get_center() - view_offset) * z() - size / 2.0)


func is_on_screen(world_pos: Vector2, margin: float = 0.0) -> bool:
	return Rect2(Vector2.ZERO, size).grow(margin).has_point(to_screen(world_pos))


# --- Notes -------------------------------------------------------------------------------

func load_notes() -> void:
	_snapshot_ready = false
	notes.clear()
	# Notes keep their ids across saves, so snap memories ("n<id>" / "e<id>") stay valid.
	var used := {}
	for d in Settings.notes:
		var saved := int(d.get("id", 0))
		if saved > 0 and not used.has(saved):
			used[saved] = true
			_next_id = maxi(_next_id, saved + 1)
	for d in Settings.notes:
		var p := Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0)))
		var id := _add(p, int(d.get("note", 60)), int(d.get("channel", 0)))
		var n := get_note(id)
		var saved := int(d.get("id", 0))
		if saved > 0 and used.get(saved, false):
			n.id = saved
			used[saved] = false             # each saved id is used once
		n.slot = clampi(int(d.get("slot", 0)), 0, 9)
		n.range = maxf(float(d.get("range", 0.0)), 0.0)
		n.muted = bool(d.get("muted", false))
		n.grid = bool(d.get("grid", false))
		n.grid_emit = bool(d.get("grid_emit", false))
		n.snap_note = str(d.get("snap_note", ""))
		n.snap_emit = str(d.get("snap_emit", ""))
		n.mode = clampi(int(d.get("mode", Mode.NOTE)), Mode.NOTE, Mode.PULSE)
		n.pulse_strength = clampf(float(d.get("pulse_strength", DEFAULT_PULSE_STRENGTH)), 0.05, 1.0)
		# Cooldowns are in beats (tempo-locked). Older saves stored seconds: convert at the saved tempo.
		var cd := DEFAULT_COOLDOWN
		if d.has("cooldown_beats"):
			cd = float(d["cooldown_beats"])
		elif d.has("cooldown"):
			cd = float(d["cooldown"]) * Settings.bpm / 60.0
		n.cooldown = 0.0 if cd <= 0.0 else maxf(cd, MIN_COOLDOWN)   # 0 = retrigger
		n.attached = bool(d.get("attached", true))
		n.emit = Vector2(float(d.get("ex", p.x)), float(d.get("ey", p.y)))
		n.mod = str(d.get("mod", ""))
		if not MODIFIERS.has(n.mod):
			n.mod = ""
		n.mod_start = bool(d.get("mod_start", true))
		n.mod_on = n.mod_start
	if notes.is_empty():
		seed_default_layout()
	if not _restoring:
		_undo.clear()
		_redo.clear()
	_snapshot = Settings.notes.duplicate(true)
	_snapshot_ready = true
	_last_edit_frame = -1


func seed_default_layout() -> void:
	var pitches := Scales.octave_notes(4, Settings.root_note, Settings.scale_name)
	pitches.append_array(Scales.octave_notes(5, Settings.root_note, Settings.scale_name).slice(0, 3))
	var view := size if size.x > 64.0 else Vector2(1280, 800)
	var centre := to_world(view / 2.0)
	var count := pitches.size()
	for i in count:
		var a := -PI / 2.0 + TAU * i / count
		_add(centre + Vector2(cos(a) * view.x * 0.26, sin(a) * view.y * 0.32) / z(), pitches[i], 0)
	save_notes()


func save_notes() -> void:
	var out: Array = []
	for n in notes:
		out.append({
			"x": n.pos.x, "y": n.pos.y, "note": n.note, "channel": n.channel,
			"mode": n.mode, "pulse_strength": n.pulse_strength, "cooldown_beats": n.cooldown,
			"attached": n.attached, "ex": n.emit.x, "ey": n.emit.y,
			"mod": n.mod, "mod_start": n.mod_start,
			"id": n.id, "snap_note": n.snap_note, "snap_emit": n.snap_emit, "slot": n.slot, "range": n.range, "muted": n.muted,
			"grid": n.grid, "grid_emit": n.grid_emit,
		})
	Settings.notes = out
	_record_edit(out)
	Settings.queue_save()
	notes_changed.emit()


## Remembers the layout an edit replaced so it can be undone. Edits in one frame share a step.
func _record_edit(layout: Array) -> void:
	if _restoring or not _snapshot_ready:
		return
	if JSON.stringify(layout) == JSON.stringify(_snapshot):
		return
	var frame := Engine.get_process_frames()
	if frame != _last_edit_frame or _undo.is_empty():
		_undo.append(_snapshot)
		if _undo.size() > UNDO_LIMIT:
			_undo.pop_front()
	_last_edit_frame = frame
	_redo.clear()
	_snapshot = layout.duplicate(true)


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo_steps() -> int:
	return _undo.size()


func redo_steps() -> int:
	return _redo.size()


## The next edit starts a new undo step even if it lands in the same frame.
func end_undo_group() -> void:
	_last_edit_frame = -1


func undo() -> bool:
	if _undo.is_empty() or _press_id != -1:
		return false
	_redo.append(_snapshot)
	_apply_snapshot(_undo.pop_back())
	return true


func redo() -> bool:
	if _redo.is_empty() or _press_id != -1:
		return false
	_undo.append(_snapshot)
	_apply_snapshot(_redo.pop_back())
	return true


## Rebuilds the notes from a layout snapshot, keeping live play state (toggles, cooldowns) and
## the selection for notes that survive.
func _apply_snapshot(snap: Array) -> void:
	var live := {}
	for n in notes:
		_silence(n)
		live[n.id] = [n.mod, n.mod_on, n.ready_at]
	var kept: Array = selection.keys()
	_restoring = true
	Settings.notes = snap.duplicate(true)
	load_notes()
	_restoring = false
	for n in notes:
		if live.has(n.id) and live[n.id][0] == n.mod:
			n.mod_on = live[n.id][1]
			n.ready_at = live[n.id][2]
	selection = {}
	for id in kept:
		if not get_note(id).is_empty():
			selection[id] = true
	_hover_id = -1
	_last_edit_frame = -1
	Settings.queue_save()
	notes_changed.emit()


func add_note_at(screen_pos: Vector2, pitch: int, channel: int) -> int:
	var id := _add(grid_snap(to_world(screen_pos)), Scales.quantize(pitch, Settings.root_note, Settings.scale_name), channel)
	last_pitch = pitch
	last_channel = channel
	save_notes()
	return id


func set_note_pitch(id: int, pitch: int) -> void:
	var n := get_note(id)
	if n.is_empty():
		return
	_silence(n)
	n.note = pitch
	last_pitch = pitch
	save_notes()


## < / >: moves the selection (or the hovered note) one scale step down / up, or with
## `octave` a whole octave. A note that would leave the MIDI range stays put. Each moved
## note plays its new pitch (up to 8) and flashes. Returns how many notes moved.
func nudge_pitch(steps: int, octave: bool) -> int:
	var ids: Array = selection.keys() if not selection.is_empty() else ([_hover_id] if _hover_id != -1 else [])
	var moved := 0
	var heard := {}
	for id in ids:
		var n := get_note(id)
		if n.is_empty():
			continue
		var p: int = n.note + 12 * steps if octave else Scales.step(n.note, steps, Settings.root_note, Settings.scale_name)
		if p < 0 or p > 127 or p == n.note:
			continue
		_silence(n)
		n.note = p
		last_pitch = p
		moved += 1
		flash_brackets(n)
		if n.mode != Mode.PULSE and not n.muted and heard.size() < 8 and not heard.has([p, n.channel]):
			heard[[p, n.channel]] = true
			Midi.play_note(p, 90, 0.25, n.channel)
	if moved > 0:
		save_notes()
	return moved


func set_note_channel(id: int, channel: int) -> void:
	var n := get_note(id)
	if n.is_empty():
		return
	_silence(n)
	n.channel = channel
	last_channel = channel
	save_notes()


## NOTE -> NOTE_PULSE -> PULSE -> NOTE. A pulse that gets switched on is ready to fire.
func cycle_mode(id: int) -> void:
	var n := get_note(id)
	if n.is_empty():
		return
	var mode: int = (n.mode + 1) % 3
	for gid in group_for(id):
		set_note_mode(gid, mode)


func set_note_mode(id: int, mode: int) -> void:
	var n := get_note(id)
	if n.is_empty():
		return
	if n.mode == Mode.NOTE and mode != Mode.NOTE:
		n.ready_at = 0
	if mode == Mode.PULSE:
		_silence(n)
	n.mode = mode
	save_notes()


## Pulse strength (0-1) and cooldown in beats (tempo-locked, at least MIN_COOLDOWN).
func set_pulse_params(id: int, strength: float, cooldown: float) -> void:
	var n := get_note(id)
	if n.is_empty():
		return
	n.pulse_strength = clampf(strength, 0.05, 1.0)
	n.cooldown = 0.0 if cooldown <= 0.0 else maxf(cooldown, MIN_COOLDOWN)   # 0 = retrigger
	n.ready_at = mini(n.ready_at, clock_usec + cooldown_usec(n))
	save_notes()


## Attaches a modifier ("" removes it). A new toggle starts on.
func set_modifier(id: int, kind: String) -> void:
	var n := get_note(id)
	if n.is_empty() or (kind != "" and not MODIFIERS.has(kind)):
		return
	n.mod = kind
	n.mod_on = true
	n.mod_start = true
	save_notes()


## A state the user sets is the note's intended start state: sets current and start.
func set_modifier_state(id: int, on: bool) -> void:
	var n := get_note(id)
	if n.is_empty() or n.mod == "":
		return
	n.mod_on = on
	n.mod_start = on
	n.mod_flip = 1.0
	save_notes()


## Save state: every modifier's current state becomes its start state.
func save_state() -> void:
	for n in notes:
		if n.mod != "":
			n.mod_start = n.mod_on
	save_notes()


## Keypad slots: Ctrl + KP1-9 over a note puts it in that slot (again takes it out).
func toggle_slot(id: int, slot: int) -> void:
	var n := get_note(id)
	if n.is_empty() or slot < 1 or slot > 9:
		return
	var target: int = 0 if n.slot == slot else slot
	for gid in group_for(id):
		get_note(gid).slot = target
		flash_brackets(get_note(gid))
	save_notes()


## Keypad key down: trigger the slot once, then while it stays held its pulsers refire
## each time their cooldown runs out. Plain notes fire only on key down.
func press_slot(slot: int) -> void:
	held_slots[slot] = true
	trigger_slot(slot)
	for n in notes:
		if n.slot == slot and n.mode != Mode.NOTE:
			n.hold_next = clock_usec + cooldown_usec(n)


## A note's cooldown in microseconds at the current tempo.
## Retrigger (cooldown 0) has no timer: the pulser fires on every wave that reaches it,
## with only the 1/8-beat minimum kept as a safety floor against runaway contact loops.
func cooldown_usec(n: Dictionary) -> int:
	var beats: float = MIN_COOLDOWN if is_retrigger(n) else n.cooldown
	return int(beats * 60.0 / maxf(Settings.bpm, 1.0) * 1_000_000.0)


func is_retrigger(n: Dictionary) -> bool:
	return n.cooldown <= 0.0


func release_slot(slot: int) -> void:
	held_slots.erase(slot)


func release_all_slots() -> void:
	held_slots.clear()


## KP1-9: every note in the slot is clicked once (a pulser fires directly, a plain note
## sends a wave from where it sits). Muted notes are skipped: the keypad doesn't fire them,
## and a wave reaching a muted note does nothing either (no sound, no pulse).
func trigger_slot(slot: int) -> int:
	var count := 0
	for n in notes.duplicate():
		if n.slot == slot and not n.muted:
			click_note(n.id)
			count += 1
	return count


func hovered_note() -> int:
	return _hover_id


## What a click on a note does: a plain note sends a click wave from the note; a pulser
## is triggered directly with no click wave.
func click_note(id: int) -> void:
	var n := get_note(id)
	if n.is_empty():
		return
	if n.mode == Mode.NOTE:
		waves.append(_make_wave(n.pos, Settings.wave_strength, -1))
		while waves.size() > MAX_WAVES:
			waves.pop_front()
	else:
		trigger_note(id)


## Triggers a note as if a wave at full click strength had just reached it: it plays
## (unless muted) and a pulser fires from its emitter. Modifiers and cooldown apply as for
## any hit. No click wave is sent.
func trigger_note(id: int) -> void:
	var n := get_note(id)
	if n.is_empty():
		return
	var spawned: Array = []
	_trigger(n, Settings.wave_strength, clock_usec, spawned)
	waves.append_array(spawned)


## Stop: clear all waves and return every modifier to its start state. Pulser cooldowns keep
## running, so a pulser that just fired can't be re-fired straight away by a reset.
func stop() -> void:
	waves.clear()
	for n in notes:
		n.mod_on = n.mod_start
		n.dim_flash = 0.0       # cooldowns keep running: a pulser that just fired stays cooling down


## Alpha of a hollow note's centre dot: bright unless muted (pulse-only pulsers are always
## hollow, so the dot is what shows their mute state).
func center_dot_alpha(n: Dictionary) -> float:
	return 0.18 if n.muted else 0.9


## Pulse-only pulsers play no note, so they hide their pitch (it is kept for switching back).
func shows_pitch(n: Dictionary) -> bool:
	return n.mode != Mode.PULSE


## Tooltip text for a note: pitch, channel and modifier state.
func hover_text(n: Dictionary) -> String:
	var text: String
	if shows_pitch(n):
		text = "%s · ch %d" % [MidiMessage.note_name(n.note), n.channel + 1]
	else:
		text = "pulse only · ch %d" % (n.channel + 1)
	if n.mode == Mode.NOTE_PULSE:
		text += " · pulse"
	if n.mode != Mode.NOTE and is_retrigger(n):
		text += " · retrigger"
	if n.muted:
		text += " · muted"
	if n.mod == "toggle":
		text += " · toggle %s" % ("on" if n.mod_on else "off")
		if n.mod_on != n.mod_start:
			text += ", starts %s" % ("on" if n.mod_start else "off")
	if n.mode != Mode.NOTE and n.range > 0.0:
		text += " · reach " + format_beats(n.range / Settings.BEAT_UNIT)
	if n.slot > 0:
		text += " · key %d" % n.slot
	return text


# --- Selection --------------------------------------------------------------------------

## The notes an edit on `id` applies to: the whole selection if `id` is in it.
func group_for(id: int) -> Array:
	if selection.has(id) and selection.size() > 1:
		var out: Array = []
		for n in notes:
			if selection.has(n.id):
				out.append(n.id)
		return out
	return [id]


func select_in_rect(screen_rect: Rect2, add: bool = false) -> void:
	if not add:
		selection.clear()
	var r := screen_rect.abs()
	for n in notes:
		if r.has_point(note_screen_pos(n)):
			selection[n.id] = true


## M: mute the selection (or the hovered note). If any of them is unmuted they all mute,
## otherwise they all unmute. A muted note makes no sound and sends no pulse; its mode is kept
## for when it's unmuted.
func toggle_mute() -> int:
	var ids: Array = []
	if not selection.is_empty():
		ids = selection.keys()
	elif _hover_id != -1:
		ids = [_hover_id]
	if ids.is_empty():
		return 0
	var mute := false
	for id in ids:
		if not get_note(id).get("muted", true):
			mute = true
	for id in ids:
		var n := get_note(id)
		if n.is_empty():
			continue
		n.muted = mute
		if mute:
			_silence(n)
		flash_brackets(n)
	save_notes()
	return ids.size()


func clear_selection() -> void:
	selection.clear()


func delete_selection() -> void:
	for id in selection.keys():
		for i in notes.size():
			if notes[i].id == id:
				_silence(notes[i])
				flash_brackets(notes[i])
				notes.remove_at(i)
				break
	selection.clear()
	_hover_id = -1
	save_notes()


func copy_selection() -> int:
	_clipboard.clear()
	if selection.is_empty():
		return 0
	var centre := Vector2.ZERO
	var picked: Array = []
	for n in notes:
		if selection.has(n.id):
			picked.append(n)
			centre += n.pos
	centre /= picked.size()
	for n in picked:
		_clipboard.append({
			"off": n.pos - centre, "emit_off": n.emit - centre, "attached": n.attached,
			"note": n.note, "channel": n.channel, "mode": n.mode,
			"pulse_strength": n.pulse_strength, "cooldown": n.cooldown,
			"mod": n.mod, "mod_start": n.mod_start, "slot": n.slot, "range": n.range, "muted": n.muted,
		})
	return _clipboard.size()


## Pastes the copied group centred at a screen position; the pasted notes become the selection.
func paste_at(screen_pos: Vector2) -> int:
	if _clipboard.is_empty():
		return 0
	var centre := to_world(screen_pos)
	# The first copied note lands on the nearest grid point; the rest keep their places around it.
	var first: Vector2 = centre + _clipboard[0].off
	centre += grid_snap(first) - first
	selection.clear()
	for c in _clipboard:
		var id := _add(centre + c.off, c.note, c.channel)
		var n := get_note(id)
		n.mode = c.mode
		n.pulse_strength = c.pulse_strength
		n.cooldown = c.cooldown
		n.attached = c.attached
		n.emit = n.pos if c.attached else centre + c.emit_off
		n.mod = c.mod
		n.mod_start = c.mod_start
		n.mod_on = c.mod_start
		n.slot = c.slot
		n.range = c.range
		n.muted = c.muted
		selection[id] = true
	save_notes()
	return _clipboard.size()


func remove_note(id: int) -> void:
	for i in notes.size():
		if notes[i].id == id:
			_silence(notes[i])
			flash_brackets(notes[i])
			notes.remove_at(i)
			break
	if _hover_id == id:
		_hover_id = -1
	selection.erase(id)
	save_notes()


func clear_notes() -> void:
	for n in notes:
		_silence(n)
	notes.clear()
	selection.clear()
	save_notes()


## What the pointer is over or doing, for the hint bar: "box", "drag_note", "drag_emitter",
## "range", "emitter", "selected", "note", "pulser", "selection" (something selected, pointer on
## empty space) or "empty".
func hint_context() -> String:
	if _box_active:
		return "box"
	if _press_id != -1 and (_dragging or _press_kind == "range"):
		if _press_kind == "range":
			return "range"
		return "drag_emitter" if _press_kind == "emitter" else "drag_note"
	if _hover_handle != -1:
		return "emitter"
	if _hover_id != -1:
		if selection.has(_hover_id):
			return "selected"
		return "note" if get_note(_hover_id).get("mode", Mode.NOTE) == Mode.NOTE else "pulser"
	if not selection.is_empty():
		return "selection"
	return "empty"


func set_edit_mode(on: bool) -> void:
	if on == edit_mode:
		return
	edit_mode = on
	_end_press()
	_box_active = false
	if not on:
		selection.clear()
	mode_changed.emit(on)


func get_note(id: int) -> Dictionary:
	for n in notes:
		if n.id == id:
			return n
	return {}


func note_screen_pos(n: Dictionary) -> Vector2:
	return to_screen(n.pos)


## Where this note's waves start, in world px.
func emitter_world_pos(n: Dictionary) -> Vector2:
	return n.pos if n.attached else n.emit


func emitter_screen_pos(n: Dictionary) -> Vector2:
	return to_screen(emitter_world_pos(n))


## Where the draggable emitter handle is drawn: on the rim while attached.
func handle_screen_pos(n: Dictionary) -> Vector2:
	if n.attached:
		var out := NOTE_RADIUS + (MOD_RING + 8.0 if n.mod != "" else 9.0)
		return note_screen_pos(n) + Vector2(1, -1).normalized() * out
	return to_screen(n.emit)


func note_at(screen_pos: Vector2) -> int:
	var best := -1
	var best_d := NOTE_RADIUS + 6.0
	for n in notes:
		var d := screen_pos.distance_to(note_screen_pos(n))
		if d < best_d:
			best_d = d
			best = n.id
	return best


func handle_at(screen_pos: Vector2) -> int:
	for n in notes:
		if n.mode != Mode.NOTE and screen_pos.distance_to(handle_screen_pos(n)) <= HANDLE_RADIUS + 4.0:
			return n.id
	return -1


func _add(world_pos: Vector2, pitch: int, channel: int) -> int:
	var id := _next_id
	while not get_note(id).is_empty():
		id += 1
	_next_id = id + 1
	notes.append({
		"id": id, "pos": world_pos,
		"note": clampi(pitch, 0, 127), "channel": clampi(channel, 0, 15),
		"flash": 0.0, "playing": false, "off_at": 0,
		"mode": Mode.NOTE, "pulse_strength": DEFAULT_PULSE_STRENGTH, "cooldown": DEFAULT_COOLDOWN,
		"ready_at": 0, "pulse_flash": 0.0,
		"attached": true, "emit": world_pos,
		"mod": "", "mod_on": true, "mod_start": true, "mod_flip": 0.0, "dim_flash": 0.0,
		"snap_note": "", "snap_emit": "",   # target last snapped to when the note / its emitter was dropped
		"slot": 0,                          # keypad trigger slot 1-9, 0 = none
		"hold_next": 0,                     # next refire time while its slot key is held
		"range": 0.0,                       # own wave reach in world units (0 = global Reach)
		"muted": false,                     # M: no sound and no pulse; the mode is kept
		"grid": false,                      # G: a snap grid (rings + spokes) centred on the note
		"grid_emit": false,                 # G on a detached emitter: a grid centred on it
	})
	return id


func _on_setting_changed(key: String) -> void:
	if key == "beat_spacing":
		# Zoom about the centre of the window.
		var centre := view_offset + size / (2.0 * _zoom)
		_zoom = z()
		view_offset = centre - size / (2.0 * _zoom)
		Settings.view_offset = view_offset
	if key == "root_note" or key == "scale_name":
		for n in notes:
			var q := Scales.quantize(n.note, Settings.root_note, Settings.scale_name)
			if q != n.note:
				_silence(n)
				n.note = q
		save_notes()


# --- Waves -------------------------------------------------------------------------------

## A wave from the user at a screen position. If the surface is full, the oldest wave makes room.
func spawn_wave(screen_origin: Vector2, strength: float = -1.0) -> void:
	waves.append(_make_wave(to_world(screen_origin), Settings.wave_strength if strength < 0.0 else strength, -1))
	while waves.size() > MAX_WAVES:
		waves.pop_front()


func stop_all_waves() -> void:
	waves.clear()


## `range` 0 = the global Reach (Options); pulsers can set their own.
func _make_wave(world_origin: Vector2, strength: float, source: int, range: float = 0.0) -> Dictionary:
	return {"origin": world_origin, "r": 0.0, "strength": strength, "source": source, "hits": {}, "range": range}


func wave_range_of(w: Dictionary) -> float:
	var r: float = w.get("range", 0.0)
	return r if r > 0.0 else Settings.wave_range


## A pulser's reach: its own if set (Ctrl + left-drag), else the global Reach.
func emitter_range(n: Dictionary) -> float:
	return n.range if n.range > 0.0 else Settings.wave_range


## Wave amplitude at distance `d` from its source: strength at 0, falling to 0 at `range`
## (the global Reach when not given).
func amplitude(strength: float, d: float, range: float = -1.0) -> float:
	var reach := Settings.wave_range if range <= 0.0 else range
	var x := clampf(1.0 - d / maxf(reach, 1.0), 0.0, 1.0)
	return strength * pow(x, Settings.falloff_curve)


## Data for water.gdshader: (x, y, radius, amplitude at that radius) per wave, in screen px.
func shader_waves() -> PackedVector4Array:
	var out := PackedVector4Array()
	out.resize(MAX_WAVES)
	for i in mini(waves.size(), MAX_WAVES):
		var w: Dictionary = waves[i]
		var o := to_screen(w.origin)
		out[i] = Vector4(o.x, o.y, w.r * z(), amplitude(w.strength, w.r, wave_range_of(w)) * _fade_in(w.r))
	return out


func _fade_in(r: float) -> float:
	return clampf(r / 40.0, 0.0, 1.0)


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
		var w: Dictionary = waves[i]
		if i < fresh_from:
			w.r += delta * speed
		var wr := wave_range_of(w)
		if w.r >= wr:
			waves.remove_at(i)
			if i < fresh_from:
				fresh_from -= 1
			continue
		for n in notes:
			if n.id == w.source or w.hits.has(n.id):
				continue
			var d := (w.origin as Vector2).distance_to(n.pos)
			# A wave that starts on a note (d within its radius) hits it straight away.
			if w.r >= d or d <= NOTE_RADIUS:
				w.hits[n.id] = true
				var amp := amplitude(w.strength, d, wr)
				if amp >= MIN_AMPLITUDE:
					_trigger(n, amp, now, spawned)
		# Waves fired by pulsers join the loop now, at radius 0, so a note sitting on the
		# emitter is hit this same frame: a stacked chain plays as one chord instead of one
		# link per frame. Cooldowns and MAX_WAVES keep this from running away.
		waves.append_array(spawned)
		spawned.clear()
		i += 1

	# Held keypad slots: pulsers refire each time their cooldown runs out (a refire that a
	# toggle silences still waits a full cooldown before the next).
	if not held_slots.is_empty():
		for n in notes.duplicate():
			if held_slots.has(n.slot) and n.mode != Mode.NOTE and not n.muted and not is_retrigger(n) \
					and now >= n.hold_next:
				n.hold_next = now + cooldown_usec(n)
				trigger_note(n.id)

	for n in notes:
		if n.playing and now >= n.off_at:
			Midi.note_off(n.note, n.channel)
			n.playing = false
		n.flash = maxf(0.0, n.flash - delta * 2.5)
		n.pulse_flash = maxf(0.0, n.pulse_flash - delta * 3.0)
		n.mod_flip = maxf(0.0, n.mod_flip - delta * 4.0)
		n.dim_flash = maxf(0.0, n.dim_flash - delta * 3.0)

	var f := 0
	while f < touch_flashes.size():
		touch_flashes[f].t += delta
		if touch_flashes[f].t >= 0.35:
			touch_flashes.remove_at(f)
		else:
			f += 1

	var s := 0
	var bf := 0
	while bf < bracket_flashes.size():
		bracket_flashes[bf].t += delta
		if bracket_flashes[bf].t >= BRACKET_FLASH_TIME:
			bracket_flashes.remove_at(bf)
		else:
			bf += 1
	while s < splashes.size():
		splashes[s].t += delta
		if splashes[s].t >= SPLASH_TIME:
			splashes.remove_at(s)
		else:
			s += 1


## A wave reached note `n`. The modifier decides whether it acts on this hit.
func _trigger(n: Dictionary, amp: float, now: int, spawned: Array) -> void:
	if n.mod == "toggle":
		var active: bool = n.mod_on
		n.mod_on = not n.mod_on
		n.mod_flip = 1.0
		if not active:
			n.dim_flash = 1.0       # silenced: no sound, no pulse
			return
	_on_hit(n, amp, now, spawned)


func _on_hit(n: Dictionary, amp: float, now: int, spawned: Array) -> void:
	if n.muted:
		n.dim_flash = 1.0            # muted: no sound and no pulse (a toggle still advances)
		return
	if n.mode != Mode.PULSE:
		_play(n, amp, now)
	if n.mode == Mode.NOTE or now < n.ready_at:
		return
	if waves.size() + spawned.size() >= MAX_WAVES:
		skipped_pulses += 1          # surface full: skip this beat, stay ready
		return
	spawned.append(_make_wave(emitter_world_pos(n), n.pulse_strength, n.id, n.range))
	n.ready_at = now + cooldown_usec(n)
	n.pulse_flash = 1.0


func _play(n: Dictionary, amp: float, now: int) -> void:
	var velocity := clampi(roundi(amp * 127.0), 1, 127)
	if n.playing:
		Midi.note_off(n.note, n.channel)
	Midi.note_on(n.note, velocity, n.channel)
	n.playing = true
	n.off_at = now + int(Settings.note_length_for(n.channel) * 1_000_000.0)
	n.flash = maxf(n.flash, 0.35 + amp * 0.65)
	splashes.append({"pos": n.pos, "t": 0.0, "color": Palette.channel_color(n.channel), "strength": amp})


func _silence(n: Dictionary) -> void:
	if n.playing:
		Midi.note_off(n.note, n.channel)
		n.playing = false


# --- Timing rings and snapping -----------------------------------------------------------

func ring_step() -> float:
	return Settings.BEAT_UNIT / maxf(float(Settings.divisions), 1.0)


## Every object a held item can touch, keyed "n<id>" (a note) or "e<id>" (a detached
## emitter), with its world position. The held note and its own emitter are left out.
func touch_targets(exclude_id: int) -> Dictionary:
	var out := {}
	for m in notes:
		if m.id == exclude_id or _group_start.has(m.id):
			continue
		out["n%d" % m.id] = m.pos
		if m.mode != Mode.NOTE and not m.attached:
			out["e%d" % m.id] = m.emit
	return out


## Grid origins that are on, keyed like touch targets ("n<id>" / "e<id>") with world positions.
## The held note (and its emitter) and the rest of a dragged group are left out.
func grid_targets(exclude_id: int = -1) -> Dictionary:
	var out := {}
	for m in notes:
		if m.id == exclude_id or _group_start.has(m.id):
			continue
		if m.grid:
			out["n%d" % m.id] = m.pos
		if m.grid_emit and m.mode != Mode.NOTE and not m.attached:
			out["e%d" % m.id] = m.emit
	return out


func has_grids() -> bool:
	return not grid_targets().is_empty()


## G: turns the grid under the hovered note or emitter on or off. Returns "on", "off" or ""
## (nothing under the mouse). An attached emitter shares its note's grid.
func toggle_grid_at_hover() -> String:
	var id := _hover_handle if _hover_handle != -1 else _hover_id
	var n := get_note(id)
	if n.is_empty():
		return ""
	var on: bool
	if _hover_handle != -1 and not n.attached:
		n.grid_emit = not n.grid_emit
		on = n.grid_emit
	else:
		n.grid = not n.grid
		on = n.grid
	flash_brackets(n)
	save_notes()
	return "on" if on else "off"


## Ctrl+G: turns every grid off. Returns how many were on.
func clear_grids() -> int:
	var count := 0
	for n in notes:
		if n.grid or n.grid_emit:
			count += int(n.grid) + int(n.grid_emit)
			n.grid = false
			n.grid_emit = false
	if count > 0:
		save_notes()
	return count


## The nearest grid point to world point `p`, for placing new notes: the nearest place where a
## ring crosses a spoke when one is close (within the snap distance, or half a ring step), else
## the nearest ring along the line from a grid's origin. Returns `p` when snapping is off or no
## grid is on (or in reach).
func grid_snap(p: Vector2) -> Vector2:
	if not Settings.snap_enabled:
		return p
	var grids := grid_targets()
	var step := ring_step()
	var use_spokes: bool = Settings.snap_spokes and Settings.spoke_count > 0
	var ss := TAU / maxf(float(Settings.spoke_count), 1.0)
	var near := maxf(Settings.snap_distance / z(), step * 0.5)
	var best_cross := p
	var cross_d := INF
	var best_ring := p
	var ring_d := INF
	for key in grids:
		var a: Vector2 = grids[key]
		var v := p - a
		var d := v.length()
		if not Settings.guides_to_edge and d >= Settings.wave_range:
			continue
		var r := maxf(roundf(d / step), 1.0) * step
		var ang := v.angle() if d > 0.001 else -PI / 2.0
		var on_ring := a + Vector2.from_angle(ang) * r
		if on_ring.distance_to(p) < ring_d:
			ring_d = on_ring.distance_to(p)
			best_ring = on_ring
		if use_spokes:
			var cross := a + Vector2.from_angle(roundf(ang / ss) * ss) * r
			if cross.distance_to(p) < cross_d:
				cross_d = cross.distance_to(p)
				best_cross = cross
	if cross_d <= near:
		return best_cross
	return best_ring


## Works out rings, snapping and the readout for dragging note `n` (`kind` "note" or
## "emitter") to world point `p`, snapping only to the touched objects in `touched`.
## Returns {pos, centres, readout, loop, snapped, centre, ref_point}; centres[0] is the held item.
## Centre snapping (onto any note or emitter within the snap distance) beats rings and spokes.
func compute_drag(n: Dictionary, kind: String, p: Vector2, free: bool, touched: Dictionary = {}) -> Dictionary:
	var reach := Settings.wave_range
	free = free or not Settings.snap_enabled
	var targets := touch_targets(n.id)
	var pairs: Array = []      # [world point, owning note id, key]
	for key in touched:
		if targets.has(key):
			pairs.append([targets[key], int(key.substr(1)), key])
	var grids := grid_targets(n.id)
	for key in grids:
		if not touched.has(key):
			pairs.append([grids[key], int(key.substr(1)), key])

	var step_px := ring_step()
	var best: Array = []
	var best_fix := INF
	for pr in pairs:
		var d := p.distance_to(pr[0])
		if not Settings.guides_to_edge and d >= reach:
			continue                                   # guides stop at the reach
		var target := roundf(d / step_px) * step_px
		if target < step_px * 0.5:
			continue
		var fix := absf(target - d)
		if fix < best_fix:
			best_fix = fix
			best = pr

	# Spokes: 8 lines every 45 degrees from each snap target. Nearest spoke within tolerance.
	var tol := Settings.snap_distance / z()
	var spoke: Array = []
	var spoke_ang := 0.0
	var spoke_off := INF
	var spoke_step := TAU / maxf(float(Settings.spoke_count), 1.0)
	for pr in (pairs if Settings.snap_spokes and Settings.spoke_count > 0 else []):
		var v := p - (pr[0] as Vector2)
		var d := v.length()
		if d < 1.0:
			continue
		var ang := v.angle()
		var snapped_ang := roundf(ang / spoke_step) * spoke_step
		var off := d * absf(sin(ang - snapped_ang))
		if off <= tol and off < spoke_off:
			spoke_off = off
			spoke = pr
			spoke_ang = snapped_ang

	# Centre: any note or emitter (touched or not) whose centre is within the snap distance.
	var centre: Array = []
	var centre_d := tol
	if not free and Settings.snap_centres:
		for key in targets:
			var dc := p.distance_to(targets[key])
			if dc <= centre_d:
				centre_d = dc
				centre = [targets[key], int(key.substr(1)), key]

	# Grid points: where any target's ring crosses one of its own spokes, nearest within tolerance.
	var cross: Array = []
	var cross_pos := p
	var cross_d := tol
	for pr in (pairs if Settings.snap_spokes and Settings.spoke_count > 0 else []):
		var v2 := p - (pr[0] as Vector2)
		var d2 := v2.length()
		if d2 < 1.0 or (not Settings.guides_to_edge and d2 >= reach):
			continue
		var r2 := roundf(d2 / step_px) * step_px
		if r2 < step_px * 0.5:
			continue
		var pt: Vector2 = pr[0] + Vector2.from_angle(roundf(v2.angle() / spoke_step) * spoke_step) * r2
		if pt.distance_to(p) <= cross_d:
			cross_d = pt.distance_to(p)
			cross_pos = pt
			cross = pr

	var out_pos := p
	var snapped := false
	var ref: Array = []
	if not centre.is_empty():
		out_pos = centre[0]
		snapped = true
		ref = centre
	elif not free and not cross.is_empty():
		out_pos = cross_pos
		snapped = true
		ref = cross
	elif not free and not best.is_empty() and best_fix <= tol:
		# On a ring; if also near one of the same target's spokes, land on the crossing.
		var a: Vector2 = best[0]
		var radius := roundf(p.distance_to(a) / step_px) * step_px
		var dir := (p - a).normalized() if p.distance_to(a) > 0.001 else Vector2.RIGHT
		if not spoke.is_empty() and spoke[2] == best[2]:
			dir = Vector2.from_angle(spoke_ang)
		out_pos = a + dir * radius
		snapped = true
		ref = best
	elif not free and not spoke.is_empty():
		# Only on a spoke: keep the distance, line up on the spoke.
		var a2: Vector2 = spoke[0]
		out_pos = a2 + Vector2.from_angle(spoke_ang) * p.distance_to(a2)
		snapped = true
		ref = spoke
	else:
		# Not snapped: measure to the nearest touched object, else the nearest object in reach.
		var pool: Array = pairs.duplicate()
		if pool.is_empty():
			for key in targets:
				pool.append([targets[key], int(key.substr(1)), key])
		var nearest_d := reach
		for pr in pool:
			var d := p.distance_to(pr[0])
			if d < nearest_d:
				nearest_d = d
				ref = pr

	var centres: Array = [out_pos]
	for pr in pairs:
		centres.append(pr[0])
	var info := {"pos": out_pos, "centres": centres, "readout": "", "loop": "", "snapped": snapped,
			"ref_point": ref[0] if not ref.is_empty() else null,
			"snap_key": ref[2] if snapped else ""}
	info["centre"] = not centre.is_empty()
	if not centre.is_empty():
		info.readout = "centre"
		info.loop = _loop_text(n, kind, out_pos, get_note(ref[1]))
	elif not ref.is_empty():
		var d := out_pos.distance_to(ref[0])
		info.readout = "%s · %d ms" % [format_beats(d / Settings.BEAT_UNIT), roundi(d / Settings.wave_speed * 1000.0)]
		info.loop = _loop_text(n, kind, out_pos, get_note(ref[1]))
	elif free:
		info.readout = "free"
	return info


## Loop period when the dragged note and `m` both pulse and each reaches the other.
func _loop_text(n: Dictionary, kind: String, p: Vector2, m: Dictionary) -> String:
	if m.is_empty() or n.mode == Mode.NOTE or m.mode == Mode.NOTE:
		return ""
	var n_pos: Vector2 = p if kind == "note" else n.pos
	var n_emit: Vector2 = p if (kind == "emitter" or n.attached) else n.emit
	var there := n_emit.distance_to(m.pos)
	var back := emitter_world_pos(m).distance_to(n_pos)
	if there >= Settings.wave_range or back >= Settings.wave_range:
		return ""
	return "loop " + format_beats((there + back) / Settings.BEAT_UNIT)


## "1 ¾ beats", "½ beat", "2 beats"; off-grid values read "≈ 1.37 beats".
static func format_beats(b: float) -> String:
	var div: int = Settings.divisions
	var whole := floori(b + 0.0001)
	var num := roundi((b - whole) * div)
	if num == div:
		whole += 1
		num = 0
	if absf(b - (whole + float(num) / div)) > 0.01:
		return "≈ %.2f beats" % b
	var frac := ""
	if num > 0:
		var g := _gcd(num, div)
		var key := "%d/%d" % [num / g, div / g]
		frac = FRACTIONS.get(key, key)
	var text := ""
	if whole > 0 and frac != "":
		text = "%d %s" % [whole, frac]
	elif whole > 0:
		text = str(whole)
	elif frac != "":
		text = frac
	else:
		text = "0"
	return text + (" beat" if b <= 1.0001 else " beats")


static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t := b
		b = a % b
		a = t
	return a


# --- Input -------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb:
		_handle_button(mb)
		accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm:
		_mouse_pos = mm.position
		_mouse_in = true
		if _box_active:
			_box_end = mm.position
			return
		if _pan_active:
			if not _pan_moved and mm.position.distance_to(_pan_start) > DRAG_THRESHOLD:
				_pan_moved = true
			if _pan_moved:
				pan_by(_pan_last - mm.position)
			_pan_last = mm.position
			return
		if _press_id != -1:
			if edit_mode and not _dragging and mm.position.distance_to(_press_pos) > DRAG_THRESHOLD:
				_dragging = true
			if _dragging:
				_drag_to(mm.position, mm.shift_pressed)
		_hover_handle = handle_at(mm.position)
		_hover_id = note_at(mm.position) if _hover_handle == -1 else -1
		var over := _hover_id != -1 or _hover_handle != -1
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if over else Control.CURSOR_ARROW


func _drag_to(screen_pos: Vector2, free: bool) -> void:
	var n := get_note(_press_id)
	if n.is_empty():
		return
	if _press_kind == "range":
		_drag_range(n, to_world(screen_pos), free)
		return
	var p := to_world(screen_pos)
	_update_touches(n, p)
	drag_info = compute_drag(n, _press_kind, p, free, _touched)
	if _press_kind == "emitter":
		n.attached = false
		n.emit = drag_info.pos
	else:
		n.pos = drag_info.pos
		if not _group_start.is_empty():
			# The rest of the selection follows the held note, keeping its shape.
			var delta: Vector2 = n.pos - _group_start[n.id][0]
			for gid in _group_start:
				if gid == n.id:
					continue
				var g := get_note(gid)
				if g.is_empty():
					continue
				g.pos = _group_start[gid][0] + delta
				if not g.attached:
					g.emit = _group_start[gid][1] + delta
				else:
					g.emit = g.pos
			if not n.attached:
				n.emit = _group_start[n.id][1] + delta


## Ctrl + left-drag: the distance from the emitter to the cursor becomes its reach, snapped to
## the timing divisions (Shift: free). Back onto the note resets it to the global Reach.
## Applies to every selected pulser when the note is in the selection.
func _drag_range(n: Dictionary, p: Vector2, free: bool) -> void:
	if n.mode == Mode.NOTE:
		drag_info = {}
		return
	var r := emitter_world_pos(n).distance_to(p)
	var step := ring_step()
	if r <= NOTE_RADIUS / z():
		r = 0.0                                  # back onto the note: use the global Reach
	elif not free and Settings.snap_enabled:
		r = maxf(roundf(r / step) * step, step)
	for gid in group_for(n.id):
		var g := get_note(gid)
		if not g.is_empty() and g.mode != Mode.NOTE:
			g.range = r
	var shown := emitter_range(n)
	var label := "reach %s" % format_beats(shown / Settings.BEAT_UNIT)
	if r == 0.0:
		label += " (global)"
	drag_info = {"pos": emitter_world_pos(n), "centres": [], "readout": label, "loop": "", "snapped": r > 0.0 and not free,
			"ref_point": null, "snap_key": "", "range_edit": true}


## The held item touching another object toggles that object's snap rings. A toggle
## happens when an overlap begins, so touch and move off; touching again toggles back.
func _update_touches(n: Dictionary, p: Vector2) -> void:
	if not Settings.touch_snap:
		return
	var now_over := _overlaps_at(n, p)
	for key in now_over:
		if not _overlapping.has(key):
			if _touched.has(key):
				_touched.erase(key)
			else:
				_touched[key] = true
			touch_flashes.append({"pos": now_over[key], "t": 0.0})
	_overlapping = now_over


func _overlaps_at(n: Dictionary, p: Vector2) -> Dictionary:
	var held_r := HANDLE_RADIUS if _press_kind == "emitter" else NOTE_RADIUS
	var out := {}
	var targets := touch_targets(n.id)
	for key in targets:
		var other_r := NOTE_RADIUS if key.begins_with("n") else HANDLE_RADIUS
		if p.distance_to(targets[key]) < (held_r + other_r) / z():
			out[key] = targets[key]
	return out


func _handle_button(mb: InputEventMouseButton) -> void:
	var pos := mb.position
	var handle := handle_at(pos)
	var hit := note_at(pos)
	if not edit_mode and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		# Play mode: a click plays whatever is under it; nothing is edited.
		if mb.alt_pressed or mb.shift_pressed or handle != -1 or (mb.ctrl_pressed and hit != -1):
			return
		if hit != -1:
			_begin_press(hit, "note", pos)
		else:
			spawn_wave(pos)
		return
	if not edit_mode and mb.button_index == MOUSE_BUTTON_RIGHT:
		return
	match mb.button_index:
		MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if mb.ctrl_pressed:
					# Ctrl-click a note: cycle its mode. Ctrl-drag from a pulser or its emitter:
					# set that emitter's own wave reach.
					var rid := handle if handle != -1 else hit
					if rid != -1:
						_begin_press(rid, "range", pos)
					else:
						spawn_wave(pos)
				elif mb.alt_pressed:
					if hit != -1:
						channel_menu_requested.emit(hit, pos)
				elif mb.shift_pressed:
					add_note_at(pos, last_pitch, last_channel)
				elif handle != -1:
					_begin_press(handle, "emitter", pos)
				elif hit != -1:
					if not selection.has(hit):
						selection.clear()
					_begin_press(hit, "note", pos)
				else:
					selection.clear()
					spawn_wave(pos)
			else:
				_end_press()
		MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				if mb.ctrl_pressed:
					if hit != -1:
						pulse_menu_requested.emit(hit, pos)
					else:
						_box_active = true          # box select from empty space
						_box_start = pos
						_box_end = pos
				elif mb.shift_pressed:
					if hit != -1:
						modifier_menu_requested.emit(hit, pos)
				elif mb.alt_pressed:
					if hit != -1:
						channel_menu_requested.emit(hit, pos)
				else:
					pitch_menu_requested.emit(hit, pos)
			elif _box_active:
				_box_active = false
				_box_end = pos
				if _box_start.distance_to(_box_end) > DRAG_THRESHOLD:
					select_in_rect(Rect2(_box_start, _box_end - _box_start), mb.shift_pressed)
				else:
					selection.clear()
		MOUSE_BUTTON_MIDDLE:
			# Middle only pans. (It used to delete on a click, which a short pan could trigger.)
			if mb.pressed:
				_pan_active = true
				_pan_moved = false
				_pan_start = pos
				_pan_last = pos
			elif _pan_active:
				_pan_active = false


func _begin_press(id: int, kind: String, pos: Vector2) -> void:
	_press_id = id
	_press_kind = kind
	_press_pos = pos
	_dragging = false
	_touched = {}
	_group_start = {}
	if (kind == "note" or kind == "range") and selection.has(id) and selection.size() > 1:
		for gid in group_for(id):
			var g := get_note(gid)
			_group_start[gid] = [g.pos, g.emit]
	var n := get_note(id)
	if not n.is_empty():
		var remembered: String = n.snap_emit if kind == "emitter" else n.snap_note
		if Settings.touch_snap and Settings.snap_memory and remembered != "" and touch_targets(id).has(remembered):
			_touched[remembered] = true
	# Whatever the held item already overlaps at the start doesn't count as a touch.
	_overlapping = _overlaps_at(n, n.pos if kind == "note" else emitter_world_pos(n)) if not n.is_empty() else {}


func _end_press() -> void:
	if _press_id != -1 and _press_kind == "range":
		if _dragging:
			save_notes()
		else:
			cycle_mode(_press_id)                # a plain Ctrl-click
		_press_id = -1
		_press_kind = ""
		_dragging = false
		drag_info = {}
		_group_start = {}
		return
	if _press_id != -1:
		var n := get_note(_press_id)
		if not n.is_empty():
			if _dragging:
				var snapped_to: String = drag_info.get("snap_key", "") if drag_info.get("snapped", false) else ""
				if not (Settings.snap_memory and Settings.touch_snap):
					snapped_to = ""
				if _press_kind == "emitter":
					n.snap_emit = snapped_to
				else:
					n.snap_note = snapped_to
				if _press_kind == "emitter" and n.emit.distance_to(n.pos) <= NOTE_RADIUS / z():
					n.attached = true        # dropped back on its own note: re-attach
					n.emit = n.pos
				save_notes()
			elif _press_kind == "note":
				click_note(n.id)
	_press_id = -1
	_press_kind = ""
	_dragging = false
	drag_info = {}
	_touched = {}
	_overlapping = {}
	_group_start = {}


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and edit_mode and (key.keycode == KEY_DELETE or key.keycode == KEY_BACKSPACE):
		if not selection.is_empty():
			delete_selection()
			get_viewport().set_input_as_handled()
		elif _hover_id != -1:
			remove_note(_hover_id)
			get_viewport().set_input_as_handled()


# --- Drawing -------------------------------------------------------------------------------

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_mouse_in = false
	elif what == NOTIFICATION_MOUSE_ENTER:
		_mouse_in = true


func _draw() -> void:
	var font := get_theme_default_font()
	var now := clock_usec

	if _mouse_in and not _pan_active:
		_draw_reach_glow(_mouse_pos)
	_draw_limit_rings()

	if not drag_info.is_empty() and not drag_info.get("range_edit", false):
		_draw_rings()
	else:
		# Grids that are on stay faintly visible (beats and bars) when nothing is being dragged.
		var grids := grid_targets()
		for key in grids:
			_draw_guide(grids[key], 0.32 * Settings.guide_brightness, false)

	for w in waves:
		var o := to_screen(w.origin)
		var a := amplitude(w.strength, w.r, wave_range_of(w)) * _fade_in(w.r)
		var ring_col := Palette.ACCENT if w.source == -1 else Palette.YELLOW
		var sr: float = w.r * z()
		draw_arc(o, sr, 0.0, TAU, 160, Color(ring_col, a * 0.7), 2.0, true)
		if sr > 14.0:
			draw_arc(o, sr - 12.0, 0.0, TAU, 160, Color(1, 1, 1, a * 0.12), 1.0, true)

	for sp in splashes:
		var k: float = sp.t / SPLASH_TIME
		var rr := NOTE_RADIUS + 46.0 * ease(k, 0.4)
		draw_arc(to_screen(sp.pos), rr, 0.0, TAU, 64, Color(sp.color, (1.0 - k) * 0.6 * sp.strength), 2.0, true)

	# Emitter tethers sit under the notes.
	for n in notes:
		if n.mode != Mode.NOTE and not n.attached:
			_draw_dashed(note_screen_pos(n), to_screen(n.emit), Color(Palette.channel_color(n.channel), 0.4))

	for n in notes:
		if is_on_screen(n.pos, NOTE_RADIUS + 40.0):
			_draw_note(n, font, now)
		else:
			_draw_edge_marker(n)

	# Emitter diamonds go over every note, so a note can never hide one.
	for n in notes:
		if n.mode != Mode.NOTE:
			var hp := handle_screen_pos(n)
			if hp.x > -40.0 and hp.y > -40.0 and hp.x < size.x + 40.0 and hp.y < size.y + 40.0:
				_draw_handle(hp, Palette.channel_color(n.channel), n.id == _hover_handle)

	# Hover and selection are boxes (white corner brackets), so rings only ever mean state.
	for n in notes:
		if not is_on_screen(n.pos, NOTE_RADIUS + 40.0):
			continue
		if selection.has(n.id):
			_draw_brackets(note_screen_pos(n), bracket_half(n) + 2.0, 2.0, 0.95, 0.42)
		elif n.id == _hover_id and _press_id == -1:
			_draw_brackets(note_screen_pos(n), bracket_half(n), 1.0, 0.55, 0.28)
	for bfl in bracket_flashes:
		var k: float = bfl.t / BRACKET_FLASH_TIME
		_draw_brackets(to_screen(bfl.pos), bfl.half + 2.0 + 10.0 * ease(k, 0.4), 2.0, 0.9 * (1.0 - k), 0.42)
	if _box_active:
		var box := Rect2(_box_start, _box_end - _box_start).abs()
		draw_rect(box, Color(Palette.ACCENT, 0.08))
		draw_rect(box, Color(Palette.ACCENT.lightened(0.3), 0.8), false, 1.0)

	if not drag_info.is_empty():
		if not drag_info.get("range_edit", false):
			_draw_touches()
		_draw_readout(font)
	elif _hover_id != -1 and _press_id == -1 and not _pan_active:
		var hn := get_note(_hover_id)
		if not hn.is_empty():
			_draw_tooltip(hn, font)


## Faint glow under the cursor showing how far a wave from here reaches and how it fades:
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


## Every pulser's emitter shows a faint ring at its reach, where its waves fade to 0.
func _draw_limit_rings() -> void:
	for n in notes:
		if n.mode == Mode.NOTE:
			continue
		var reach := emitter_range(n) * z()
		var c := emitter_screen_pos(n)
		if Rect2(Vector2.ZERO, size).grow(reach).has_point(c):
			var editing: bool = _press_kind == "range" and _dragging and _group_start.has(n.id) or (_press_kind == "range" and _dragging and n.id == _press_id)
			var a := 0.55 if editing else (0.16 if n.range > 0.0 else 0.11)
			draw_arc(c, reach, 0.0, TAU, maxi(64, int(reach / 6.0)), Color(Palette.YELLOW, a), 2.0 if editing else 1.0, true)


func _draw_rings() -> void:
	# Rings run out to the edges of the window (not just the wave's reach). Rings past the
	# reach are drawn a little dimmer: waves fade out before getting there.
	var dragged := get_note(_press_id)
	var focus: Variant = drag_info.get("ref_point")
	for c in drag_info.centres:
		var centre_w: Vector2 = c
		var is_held: bool = centre_w == drag_info.centres[0]
		var weight := (1.0 if (is_held or (focus != null and centre_w.is_equal_approx(focus))) else 0.6) * Settings.guide_brightness
		_draw_guide(centre_w, weight, Settings.guide_divisions)
	if not dragged.is_empty() and drag_info.snapped:
		var at := to_screen(drag_info.pos)
		var sc := Color(Palette.ACCENT.lightened(0.3), 0.6)
		draw_arc(at, NOTE_RADIUS + 14.0, 0.0, TAU, 40, sc, 1.0, true)
		if drag_info.get("centre", false):
			# Centre snap: a crosshair through the shared centre.
			var arm := NOTE_RADIUS + 22.0
			for dv in [Vector2.RIGHT, Vector2.DOWN]:
				draw_line(at - dv * arm, at - dv * (NOTE_RADIUS + 8.0), sc, 1.5, true)
				draw_line(at + dv * (NOTE_RADIUS + 8.0), at + dv * arm, sc, 1.5, true)


## One object's timing rings and spokes, out to the window edge (or the wave's reach).
func _draw_guide(centre_w: Vector2, weight: float, divisions: bool) -> void:
	var step_s := ring_step() * z()                   # ring spacing on screen
	var div: int = Settings.divisions
	var reach_s := Settings.wave_range * z()
	var corners := [Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]
	var centre := to_screen(centre_w)
	var far := 0.0
	for corner in corners:
		far = maxf(far, centre.distance_to(corner))
	if not Settings.guides_to_edge:
		far = minf(far, reach_s)
	var count := mini(int(ceil(far / step_s)), 600)
	if Settings.spoke_count > 0:
		# Spokes (default 8, every 45 degrees) out to the guide limit, on the held item
		# and on every snap target.
		var spokes: int = Settings.spoke_count
		for i in spokes:
			var sd := Vector2.from_angle(i * TAU / spokes)
			draw_line(centre + sd * (NOTE_RADIUS + 10.0), centre + sd * far,
					Color(Palette.ACCENT.lightened(0.3), minf((0.5 if i % 2 == 0 else 0.32) * weight, 1.0)), 1.0, true)
	for k in range(1, count + 1):
		var r := k * step_s
		var fade := (1.0 - 0.55 * minf(r / maxf(far, 1.0), 1.0)) * weight
		if r > reach_s:
			fade *= 0.6
		var col: Color
		var width := 1.0
		if k % (div * 4) == 0:
			col = Color(Palette.ACCENT.lightened(0.45), 0.85 * fade)    # bar
			width = 2.0
		elif k % div == 0:
			col = Color(Palette.ACCENT.lightened(0.3), 0.62 * fade)     # beat
			width = 1.5
		else:
			if step_s < 6.0 or not divisions:
				continue                                                 # off, or too dense to read
			col = Color(1, 1, 1, 0.16 * fade)                            # division
		draw_arc(centre, r, 0.0, TAU, clampi(int(r / 5.0), 48, 720), col, width, true)


## Touched objects get a highlight ring; a touch shows a brief flash.
func _draw_touches() -> void:
	var targets := touch_targets(_press_id)
	for key in _touched:
		if targets.has(key):
			var r := (NOTE_RADIUS if key.begins_with("n") else HANDLE_RADIUS) + 8.0
			draw_arc(to_screen(targets[key]), r, 0.0, TAU, 40, Color(Palette.ACCENT.lightened(0.4), 0.85), 2.0, true)
	for tf in touch_flashes:
		var k: float = tf.t / 0.35
		draw_arc(to_screen(tf.pos), NOTE_RADIUS + 6.0 + 22.0 * k, 0.0, TAU, 40, Color(1, 1, 1, 0.5 * (1.0 - k)), 2.0, true)


func _draw_tooltip(n: Dictionary, font: Font) -> void:
	var text := hover_text(n)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 30.0
	var at := note_screen_pos(n) + Vector2(NOTE_RADIUS + 18.0, -NOTE_RADIUS - 26.0)
	at.x = clampf(at.x, 8.0, size.x - w - 8.0)
	at.y = clampf(at.y, 8.0, size.y - 30.0)
	var box := Rect2(at, Vector2(w, 24))
	draw_rect(box, Color(Palette.GLASS, 0.94))
	draw_rect(box, Color(1, 1, 1, 0.12), false, 1.0)
	draw_circle(at + Vector2(12, 12), 4.0, Palette.channel_color(n.channel))
	draw_string(font, at + Vector2(22, 16), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.TEXT)


func _draw_readout(font: Font) -> void:
	var text: String = drag_info.readout
	if drag_info.loop != "":
		text += "  ·  " + drag_info.loop
	if text == "":
		return
	var at := to_screen(drag_info.pos) + Vector2(NOTE_RADIUS + 14.0, -NOTE_RADIUS - 10.0)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 16.0
	at.x = minf(at.x, size.x - w - 8.0)
	at.y = maxf(at.y, 24.0)
	draw_rect(Rect2(at + Vector2(0, -15), Vector2(w, 22)), Color(Palette.GLASS, 0.92))
	draw_rect(Rect2(at + Vector2(0, -15), Vector2(w, 22)), Color(1, 1, 1, 0.12), false, 1.0)
	draw_string(font, at + Vector2(8, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Palette.TEXT if drag_info.snapped else Palette.TEXT_DIM)


## A note off screen that is firing shows as a marker on the nearest window edge.
func _draw_edge_marker(n: Dictionary) -> void:
	var f: float = maxf(n.flash, n.pulse_flash)
	if f <= 0.01:
		return
	var p := note_screen_pos(n)
	var inner := Rect2(Vector2.ZERO, size).grow(-EDGE_INSET)
	var at := p.clamp(inner.position, inner.end)
	var dir := (p - at).normalized()
	var col := Palette.channel_color(n.channel)
	draw_circle(at, 6.0 + 6.0 * f, Color(col, 0.18 * f))
	draw_circle(at, 4.0, Color(col, 0.5 + 0.5 * f))
	var tip := at + dir * 11.0
	var side := dir.orthogonal() * 4.0
	draw_colored_polygon(PackedVector2Array([tip, at + dir * 5.0 + side, at + dir * 5.0 - side]), Color(col, 0.8 * f + 0.2))


func _draw_note(n: Dictionary, font: Font, now: int) -> void:
	var p := note_screen_pos(n)
	var col := Palette.channel_color(n.channel)
	var f: float = n.flash
	var muted: bool = n.mode == Mode.PULSE or n.muted

	if f > 0.0:
		draw_circle(p, NOTE_RADIUS + 16.0 * f, Color(col, 0.18 * f))
		draw_circle(p, NOTE_RADIUS + 7.0 * f, Color(col, 0.25 * f))
	draw_circle(p, NOTE_RADIUS + 3.0, Color(0, 0, 0, 0.35))                                   # shadow
	if muted:
		draw_circle(p, NOTE_RADIUS, Color(Palette.BG, 0.9))                                    # hollow
		# Centre dot doubles as the mute indicator: bright on an unmuted pulse-only pulser.
		draw_circle(p, NOTE_RADIUS * 0.35, Color(col, center_dot_alpha(n)))
	else:
		draw_circle(p, NOTE_RADIUS, Palette.GLASS.lerp(col, 0.12 + f * 0.35))                  # body
		draw_arc(p, NOTE_RADIUS - 6.0, PI * 1.05, PI * 1.6, 18, Color(1, 1, 1, 0.22), 2.0, true)  # highlight
	draw_arc(p, NOTE_RADIUS, 0.0, TAU, 48, Color(col.lerp(Color.WHITE, f * 0.5), 0.45 if muted else 1.0), 2.5, true)
	if Palette.channel_marked(n.channel):
		draw_arc(p, NOTE_RADIUS - 4.5, 0.0, TAU, 40, Color(col, 0.45 if muted else 0.9), 1.5, true)
	if n.muted:
		# Muted: a slash, so it reads differently from a hollow pulse-only pulser.
		var sl := Vector2(1, -1).normalized() * (NOTE_RADIUS - 3.0)
		draw_line(p - sl, p + sl, Color(col, 0.85), 2.0, true)

	if n.mode != Mode.NOTE:
		# Pulse ring: refills clockwise from the top while cooling down, flashes on fire.
		var ring_r := NOTE_RADIUS + 5.0
		var ready := 1.0
		if now < n.ready_at:
			ready = 1.0 - float(n.ready_at - now) / float(maxi(cooldown_usec(n), 1))
		var pf: float = n.pulse_flash
		draw_arc(p, ring_r, 0.0, TAU, 48, Color(1, 1, 1, 0.08), 2.0, true)
		draw_arc(p, ring_r, -PI / 2.0, -PI / 2.0 + TAU * clampf(ready, 0.0, 1.0), 48,
				Color(Palette.YELLOW, 0.55 + 0.45 * pf), 2.0, true)
		if pf > 0.0:
			draw_arc(p, ring_r + 8.0 * (1.0 - pf), 0.0, TAU, 48, Color(Palette.YELLOW, 0.5 * pf), 2.0, true)

	var toggled_off: bool = n.mod == "toggle" and not n.mod_on
	var label_col := Palette.TEXT_DIM if (muted or toggled_off) else Palette.TEXT
	if shows_pitch(n):
		draw_string(font, p + Vector2(-NOTE_RADIUS, 5.0), MidiMessage.note_name(n.note),
				HORIZONTAL_ALIGNMENT_CENTER, NOTE_RADIUS * 2.0, 13, label_col)
	if n.dim_flash > 0.0:
		draw_circle(p, NOTE_RADIUS + 4.0, Color(1, 1, 1, 0.12 * n.dim_flash))     # a silenced hit
	if n.mod != "":
		_draw_modifier(n, p, col)
	if n.slot > 0:
		# Keypad slot badge, top left (opposite the emitter handle).
		var out := NOTE_RADIUS + (MOD_RING + 8.0 if n.mod != "" else 8.0)
		var b := p + Vector2(-1, -1).normalized() * out
		draw_circle(b, 8.0, Color(0.075, 0.08, 0.11, 1.0))
		draw_arc(b, 8.0, 0.0, TAU, 24, Color(1, 1, 1, 0.35), 1.0, true)
		draw_string(font, b + Vector2(-8, 4), str(n.slot), HORIZONTAL_ALIGNMENT_CENTER, 16, 11, Palette.TEXT)


## Modifier ring and its tab (the tab hangs off the bottom of the ring, with the icon).
## Toggle icon = ripple: a dot with ripples spreading out when on, still water when off.
func _draw_modifier(n: Dictionary, p: Vector2, col: Color) -> void:
	var on: bool = n.mod_on
	var flip: float = n.mod_flip
	var ring_r := NOTE_RADIUS + MOD_RING + 2.0 * flip
	draw_arc(p, ring_r, 0.0, TAU, 56, Color(col, (1.0 if on else 0.35) * (1.0 - 0.3 * flip) + 0.3 * flip), 1.0 + flip, true)

	var c := p + Vector2(0, NOTE_RADIUS + MOD_RING + 4.0)        # tab centre
	var tab := Rect2(c - Vector2(12, 7), Vector2(24, 14))
	_draw_round_rect(tab, 4.5, Color(0.075, 0.08, 0.11, 1.0), Color(col, 1.0 if on else 0.55))
	var ink := col if on else Palette.TEXT_DIM
	draw_circle(c, 1.6, ink)
	if on:
		var grow := 1.0 + 0.6 * flip
		draw_arc(c, 3.5 * grow, -0.9, 0.9, 10, Color(ink, 1.0), 1.0, true)
		draw_arc(c, 3.5 * grow, PI - 0.9, PI + 0.9, 10, Color(ink, 1.0), 1.0, true)
		draw_arc(c, 6.0 * grow, -0.75, 0.75, 12, Color(ink, 0.6), 1.0, true)
		draw_arc(c, 6.0 * grow, PI - 0.75, PI + 0.75, 12, Color(ink, 0.6), 1.0, true)
	else:
		draw_line(c + Vector2(3.5, 0), c + Vector2(7.5, 0), ink, 1.0, true)
		draw_line(c - Vector2(3.5, 0), c - Vector2(7.5, 0), ink, 1.0, true)
	if n.mod_on != n.mod_start:
		# Start-state dot: filled = starts on, hollow = starts off.
		var dot := tab.position + Vector2(tab.size.x - 1.0, 1.0)
		draw_circle(dot, 3.2, Palette.BG)
		if n.mod_start:
			draw_circle(dot, 2.3, col)
		else:
			draw_arc(dot, 2.0, 0.0, TAU, 12, Palette.TEXT_DIM, 1.0, true)


var _tab_box: StyleBoxFlat

func _draw_round_rect(r: Rect2, radius: float, fill: Color, border: Color) -> void:
	if _tab_box == null:
		_tab_box = StyleBoxFlat.new()
	var sb := _tab_box
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = true
	draw_style_box(sb, r)


## Half the side of a note's bracket box: clear of its pulse and modifier rings and badges.
func bracket_half(n: Dictionary) -> float:
	if n.mod != "":
		return NOTE_RADIUS + MOD_RING + 6.0
	return NOTE_RADIUS + (11.0 if n.mode != Mode.NOTE else 7.0)


## Briefly flashes a note's brackets: shows where a keyboard action (M, Delete, Ctrl+KP) landed.
func flash_brackets(n: Dictionary) -> void:
	if not n.is_empty():
		bracket_flashes.append({"pos": n.pos, "half": bracket_half(n), "t": 0.0})


## Four white corner brackets around `at`. `arm` is each bracket's length as a share of the side.
func _draw_brackets(at: Vector2, half: float, width: float, alpha: float, arm: float) -> void:
	var col := Color(1, 1, 1, alpha)
	var l := half * 2.0 * arm
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var c := at + Vector2(sx, sy) * half
			draw_polyline(PackedVector2Array([c - Vector2(sx * l, 0), c, c - Vector2(0, sy * l)]), col, width, true)


func _draw_handle(at: Vector2, col: Color, hovered: bool) -> void:
	var r := HANDLE_RADIUS + (2.0 if hovered else 0.0)
	var pts := PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)])
	draw_colored_polygon(pts, Palette.GLASS.lerp(Palette.YELLOW, 0.35 if hovered else 0.15))
	pts.append(pts[0])
	draw_polyline(pts, Color(Palette.YELLOW, 0.95 if hovered else 0.75), 1.5, true)
	draw_circle(at, 1.6, Color(col, 0.9))


func _draw_dashed(a: Vector2, b: Vector2, col: Color) -> void:
	var length := a.distance_to(b)
	if length < 1.0:
		return
	var dir := (b - a) / length
	var t := NOTE_RADIUS + 4.0
	while t < length - HANDLE_RADIUS:
		draw_line(a + dir * t, a + dir * minf(t + 6.0, length - HANDLE_RADIUS), col, 1.0, true)
		t += 11.0
