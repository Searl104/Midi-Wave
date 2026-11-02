class_name Selection
extends RefCounted
## What's selected, by id: objects, and detached emitter diamonds on their own. Ids survive undo,
## which rebuilds the objects. Also holds the clipboard. Dragging a selected object moves the
## whole group; a selected diamond moves with it.

var surface: WaveSurface
var notes: Dictionary = {}         # selected object ids
var emitters: Dictionary = {}      # ids of objects whose detached emitter diamond is selected
var _clipboard: Array = []         # copied objects, positions relative to the group centre


func _init(owner_surface: WaveSurface) -> void:
	surface = owner_surface


func clear() -> void:
	notes.clear()
	emitters.clear()


## Objects plus emitter diamonds selected.
func count() -> int:
	return notes.size() + emitters.size()


func has_any() -> bool:
	return not notes.is_empty() or not emitters.is_empty()


## The objects an edit on `id` applies to: the whole selection if `id` is in it.
func group_for(id: int) -> Array:
	if notes.has(id) and notes.size() > 1:
		var out: Array = []
		for o in surface.notes:
			if notes.has(o.id):
				out.append(o.id)
		return out
	return [id]


func select_in_rect(screen_rect: Rect2, add: bool = false) -> void:
	if not add:
		clear()
	var r := screen_rect.abs()
	for o in surface.notes:
		if r.has_point(surface.to_screen(o.pos)):
			notes[o.id] = true
		# A detached emitter diamond inside the box is selected on its own.
		var e: Emitter = o.emitter()
		if e and not e.attached and r.has_point(e.handle_screen_pos(surface, o)):
			emitters[o.id] = true


## After undo: keeps only what still exists.
func prune() -> void:
	var kept: Array = notes.keys()
	var kept_emit: Array = emitters.keys()
	notes = {}
	for id in kept:
		if surface.get_note(id):
			notes[id] = true
	emitters = {}
	for id in kept_emit:
		var o := surface.get_note(id)
		if o and o.emitter() and not o.emitter().attached:
			emitters[id] = true


func copy() -> int:
	_clipboard.clear()
	if notes.is_empty():
		return 0
	var centre := Vector2.ZERO
	var picked: Array = []
	for o in surface.notes:
		if notes.has(o.id):
			picked.append(o)
			centre += o.pos
	centre /= picked.size()
	for o in picked:
		var d: Dictionary = o.to_dict()
		d["off"] = o.pos - centre
		var e: Emitter = o.emitter()
		d["emit_off"] = (e.pos if e else o.pos) - centre
		_clipboard.append(d)
	return _clipboard.size()


## Pastes the copied group centred at a screen position; the pasted objects become the selection.
## Pasted copies leave out what belongs to the original: its grids and snap memory.
func paste_at(screen_pos: Vector2) -> int:
	if _clipboard.is_empty():
		return 0
	var centre := surface.to_world(screen_pos)
	# The first copied object lands on the nearest grid point; the rest keep their places around it.
	var first: Vector2 = centre + _clipboard[0].off
	centre += surface.snapping.grid_snap(first) - first
	clear()
	for c in _clipboard:
		var id := surface.add_object(centre + c.off, c.note, c.channel)
		var o := surface.get_note(id)
		o.load_dict(c, o.pos)
		o.grid = null
		o.snap_note = ""
		var e: Emitter = o.emitter()
		if e:
			e.pos = o.pos if e.attached else centre + c.emit_off
			e.grid = null
			e.snap = ""
		notes[id] = true
	surface.save_notes()
	return _clipboard.size()
