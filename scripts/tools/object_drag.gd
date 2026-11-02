class_name ObjectDrag
extends RefCounted
## Holding and moving something on the surface: an object ("note"), an emitter ("emitter"), or an
## emitter's reach ("range"). A selected item carries its group, which keeps its shape. Any tool
## can use it. While moving, it shows the rings and readout from Snapping.
##
## Touch to snap (deprecated, see Snapping) lives here too: touching another object while moving
## toggles it as a snap target, when the overlap begins.

const THRESHOLD := 6.0             ## screen px before a press becomes a move

var surface: WaveSurface
var id := -1
var kind := ""
var moved := false                 ## past the threshold
var info: Dictionary = {}          ## rings + readout for the current move (empty when not moving)
var group: Dictionary = {}         # id -> [pos, emit, moves_note, moves_emit]
var touched: Dictionary = {}       # object keys toggled as snap targets this drag
var _overlapping: Dictionary = {}  # object keys the held item overlaps right now
var _press_pos := Vector2.ZERO


func _init(owner_surface: WaveSurface) -> void:
	surface = owner_surface


func active() -> bool:
	return id != -1


func editing_reach_of(object_id: int) -> bool:
	return kind == "range" and moved and (group.has(object_id) or object_id == id)


func begin(object_id: int, what: String, pos: Vector2) -> void:
	var sel := surface.selection
	id = object_id
	kind = what
	_press_pos = pos
	moved = false
	touched = {}
	group = {}
	if what == "range" and sel.notes.has(id) and sel.notes.size() > 1:
		for gid in sel.group_for(id):
			var g := surface.get_note(gid)
			group[gid] = _start_of(g, true)
	elif ((what == "note" and sel.notes.has(id)) or (what == "emitter" and sel.emitters.has(id))) and sel.count() > 1:
		# Selected objects move with their emitters; selected diamonds move on their own.
		for gid in sel.notes:
			var g := surface.get_note(gid)
			if g:
				group[gid] = _start_of(g, true)
		for gid in sel.emitters:
			var g := surface.get_note(gid)
			if g and not group.has(gid):
				group[gid] = _start_of(g, false)
	var o := surface.get_note(id)
	if o:
		var remembered: String = o.emitter().snap if what == "emitter" else o.snap_note
		if Settings.touch_snap and Settings.snap_memory and remembered != "" and surface.snapping.touch_targets(id).has(remembered):
			touched[remembered] = true
	# Whatever the held item already overlaps at the start doesn't count as a touch.
	_overlapping = _overlaps_at(o, o.pos if what == "note" else o.emitter().world_pos(o)) if o else {}


func _start_of(g: Note, moves_note: bool) -> Array:
	var e: Emitter = g.emitter()
	return [g.pos, e.pos if e else g.pos, moves_note, true]


## The pointer moved: past the threshold, the held item follows. `free` places without snapping.
func pointer_to(screen_pos: Vector2, free: bool) -> void:
	if not moved and screen_pos.distance_to(_press_pos) > THRESHOLD:
		moved = true
	if moved:
		move_to(screen_pos, free)


func move_to(screen_pos: Vector2, free: bool) -> void:
	var n := surface.get_note(id)
	if n == null:
		return
	var p := surface.to_world(screen_pos)
	if kind == "range":
		_move_reach(n, p, free)
		return
	_update_touches(n, p)
	info = surface.snapping.compute_drag(n, kind, p, free, touched)
	var delta := Vector2.ZERO
	var e: Emitter = n.emitter()
	if kind == "emitter":
		e.attached = false
		e.pos = info.pos
		if group.has(n.id):
			delta = e.pos - group[n.id][1]
			if group[n.id][2]:
				n.pos = group[n.id][0] + delta       # its note is selected too
	else:
		n.pos = info.pos
		if group.has(n.id):
			delta = n.pos - group[n.id][0]
			if e and not e.attached:
				e.pos = group[n.id][1] + delta
	if group.has(n.id):
		# The rest of the selection follows the held item, keeping its shape.
		for gid in group:
			if gid == n.id:
				continue
			var g := surface.get_note(gid)
			if g == null:
				continue
			var st: Array = group[gid]
			var ge: Emitter = g.emitter()
			if st[2]:
				g.pos = st[0] + delta
				if ge:
					ge.pos = st[1] + delta if not ge.attached else g.pos
			elif ge and not ge.attached:
				ge.pos = st[1] + delta


## The distance from the emitter to the pointer becomes its reach, snapped to the timing divisions
## unless `free`. Back onto the note resets it to the global Reach. Applies to every selected relay.
func _move_reach(n: Note, p: Vector2, free: bool) -> void:
	if n.relay() == null:
		info = {}
		return
	var at: Vector2 = n.emitter().world_pos(n)
	var r: float = at.distance_to(p)
	var step := Snapping.ring_step()
	if r <= Note.RADIUS / surface.z():
		r = 0.0                                  # back onto the note: use the global Reach
	elif not free and Settings.snap_enabled:
		r = maxf(roundf(r / step) * step, step)
	for gid in surface.selection.group_for(n.id):
		var g := surface.get_note(gid)
		if g and g.relay():
			g.emitter().own_reach = r
	var label := "reach %s" % Snapping.format_beats(n.emitter().reach() / Settings.BEAT_UNIT)
	if r == 0.0:
		label += " (global)"
	info = {"pos": at, "centres": [], "readout": label, "loop": "", "snapped": r > 0.0 and not free,
			"ref_point": null, "snap_key": "", "range_edit": true}


## Ends the press and saves any move. Returns true if the item moved.
func end() -> bool:
	var was_moved := moved
	if id != -1 and kind == "range":
		if moved:
			surface.save_notes()
	elif id != -1:
		var n := surface.get_note(id)
		if n and moved:
			var snapped_to: String = info.get("snap_key", "") if info.get("snapped", false) else ""
			if not (Settings.snap_memory and Settings.touch_snap):
				snapped_to = ""
			if kind == "emitter":
				n.emitter().snap = snapped_to
			else:
				n.snap_note = snapped_to
			if kind == "emitter" and n.emitter().pos.distance_to(n.pos) <= Note.RADIUS / surface.z():
				n.emitter().attached = true  # dropped back on its own note: re-attach
				n.emitter().pos = n.pos
				surface.selection.emitters.erase(n.id)
			surface.save_notes()
	id = -1
	kind = ""
	moved = false
	info = {}
	touched = {}
	_overlapping = {}
	group = {}
	return was_moved


func _update_touches(n: Note, p: Vector2) -> void:
	if not Settings.touch_snap:
		return
	var now_over := _overlaps_at(n, p)
	for key in now_over:
		if not _overlapping.has(key):
			if touched.has(key):
				touched.erase(key)
			else:
				touched[key] = true
			surface.effects.add_touch_flash(now_over[key])
	_overlapping = now_over


func _overlaps_at(n: Note, p: Vector2) -> Dictionary:
	var held_r := Emitter.HANDLE_RADIUS if kind == "emitter" else Note.RADIUS
	var out := {}
	var targets := surface.snapping.touch_targets(n.id)
	for key in targets:
		var other_r := Note.RADIUS if key.begins_with("n") else Emitter.HANDLE_RADIUS
		if p.distance_to(targets[key]) < (held_r + other_r) / surface.z():
			out[key] = targets[key]
	return out


# --- Drawing -------------------------------------------------------------------------------

func draw_rings() -> void:
	# Rings run out to the edges of the window (not just the wave's reach). Rings past the
	# reach are drawn a little dimmer: waves fade out before getting there.
	var dragged := surface.get_note(id)
	var focus: Variant = info.get("ref_point")
	for c in info.centres:
		var centre_w: Vector2 = c
		var is_held: bool = centre_w == info.centres[0]
		var weight := (1.0 if (is_held or (focus != null and centre_w.is_equal_approx(focus))) else 0.6) * Settings.guide_brightness
		Grid.draw_guide(surface, centre_w, weight, Settings.guide_divisions)
	if dragged and info.snapped:
		var at := surface.to_screen(info.pos)
		var sc := Color(Palette.ACCENT.lightened(0.3), 0.6)
		var radius := Note.RADIUS
		surface.draw_arc(at, radius + 14.0, 0.0, TAU, 40, sc, 1.0, true)
		if info.get("centre", false):
			# Centre snap: a crosshair through the shared centre.
			var arm := radius + 22.0
			for dv in [Vector2.RIGHT, Vector2.DOWN]:
				surface.draw_line(at - dv * arm, at - dv * (radius + 8.0), sc, 1.5, true)
				surface.draw_line(at + dv * (radius + 8.0), at + dv * arm, sc, 1.5, true)


## Touched objects get a highlight ring; a touch shows a brief flash.
func draw_touches() -> void:
	var targets := surface.snapping.touch_targets(id)
	for key in touched:
		if targets.has(key):
			var r := (Note.RADIUS if key.begins_with("n") else Emitter.HANDLE_RADIUS) + 8.0
			surface.draw_arc(surface.to_screen(targets[key]), r, 0.0, TAU, 40, Color(Palette.ACCENT.lightened(0.4), 0.85), 2.0, true)
	surface.effects.draw_touch_flashes(surface)


func draw_readout(font: Font) -> void:
	var text: String = info.readout
	if info.loop != "":
		text += "  ·  " + info.loop
	if text == "":
		return
	var radius := Note.RADIUS
	var at := surface.to_screen(info.pos) + Vector2(radius + 14.0, -radius - 10.0)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 16.0
	at.x = minf(at.x, surface.size.x - w - 8.0)
	at.y = maxf(at.y, 24.0)
	surface.draw_rect(Rect2(at + Vector2(0, -15), Vector2(w, 22)), Color(Palette.GLASS, 0.92))
	surface.draw_rect(Rect2(at + Vector2(0, -15), Vector2(w, 22)), Color(1, 1, 1, 0.12), false, 1.0)
	surface.draw_string(font, at + Vector2(8, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Palette.TEXT if info.snapped else Palette.TEXT_DIM)
