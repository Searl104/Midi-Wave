class_name DrawTool
extends Tool
## A brush: a ghost note follows the pointer, and a left press places a copy (dragging it into
## position before release, as one undo step). It snaps like a moved note; Alt places freely.
## Existing notes and diamonds can still be dragged, and the ghost hides over them. Rings on empty
## space set the brush, and Ctrl-click copies a note into it. Ctrl-drag from a diamond sets reach.
## Shift-click deletes a note, and places nothing on empty space.
## The brush is a real Note kept off the surface, so rings edit it like any other.

var brush := Note.new()
var _placing := false              # a press placed a note, and the drag may still position it


func _init(owner_surface: WaveSurface) -> void:
	super(owner_surface)
	brush.id = WaveSurface.BRUSH_ID
	brush.note = Scales.quantize(60, Settings.root_note, Settings.scale_name)
	if not Settings.brush.is_empty():
		_copy_from_dict(Settings.brush)


func tool_id() -> String:
	return "draw"


func title() -> String:
	return "Draw"


func section() -> int:
	return 1


func activate() -> void:
	surface.selection.clear()


func deactivate() -> void:
	_end_placing()


func ring_target() -> int:
	return WaveSurface.BRUSH_ID


func handle_input(event: InputEvent) -> bool:
	var mb := event as InputEventMouseButton
	if mb:
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return false
		if mb.pressed:
			_press(mb)
		else:
			surface.drag.end()
			_end_placing()
		return true
	var mm := event as InputEventMouseMotion
	if mm and surface.drag.active():
		surface.drag.pointer_to(mm.position, mm.alt_pressed)
		return true
	return false


func _press(mb: InputEventMouseButton) -> void:
	var hit := surface.pick_at(mb.position)
	if mb.shift_pressed:
		if not hit.is_empty() and hit[0] == "note":
			surface.history.end_group()
			surface.remove_note(hit[1])
			surface.history.end_group()
	elif mb.ctrl_pressed:
		if not hit.is_empty() and hit[0] == "note":
			pick_up(hit[1])
		elif not hit.is_empty():
			surface.drag.begin(hit[1], "range", mb.position)
	elif not hit.is_empty():
		surface.drag.begin(hit[1], hit[0], mb.position)
	elif surface.tab_at(mb.position).is_empty():
		place_at(mb.position, mb.alt_pressed)


## Where a note placed at a screen position lands.
func landing(screen_pos: Vector2, free: bool) -> Vector2:
	var world := surface.to_world(screen_pos)
	return world if free else surface.snapping.grid_snap(world)


## Places the brush and holds the new note, so a drag can position it.
func place_at(screen_pos: Vector2, free: bool = false) -> int:
	_placing = true
	surface.history.set_stroke(true)
	var id := surface.add_object(landing(screen_pos, free), brush.note, brush.channel)
	var o := surface.get_note(id)
	o.load_dict(brush.to_dict(), o.pos)
	var e: Emitter = o.emitter()
	if e:
		e.pos = o.pos
	surface.save_notes()
	if o.sounds() and not o.muted:
		Midi.play_note(o.note, 90, 0.25, o.channel)
	surface.drag.begin(id, "note", screen_pos)
	return id


func _end_placing() -> void:
	if _placing:
		_placing = false
		surface.history.set_stroke(false)


## Copies a note into the brush: pitch, channel, mute and modifiers with their settings.
func pick_up(id: int) -> void:
	var o := surface.get_note(id)
	if o:
		_copy_from_dict(o.to_dict())
		surface.effects.flash_brackets(o)
		surface.save_notes()


## What belongs to one spot isn't copied: the binding, grids, snap memory and a remote emitter.
func _copy_from_dict(d: Dictionary) -> void:
	brush.note = int(d.get("note", brush.note))
	brush.channel = int(d.get("channel", brush.channel))
	brush.load_dict(d, Vector2.ZERO)
	brush.binding = ""
	brush.grid = null
	brush.snap_note = ""
	var e: Emitter = brush.emitter()
	if e:
		e.attached = true
		e.pos = Vector2.ZERO
		e.grid = null
		e.snap = ""


func draw_overlay(canvas: WaveSurface) -> void:
	var at := canvas.pointer()
	if not canvas.pointer_inside() or canvas.drag.active() or not canvas.pick_at(at).is_empty() \
			or not canvas.tab_at(at).is_empty() or (surface.tools.radial and surface.tools.radial.visible):
		return
	brush.draw_ghost(canvas, canvas.to_screen(landing(at, Input.is_key_pressed(KEY_ALT))))


func draw_icon(canvas: CanvasItem, c: Vector2, ink: Color) -> void:
	var d := Vector2(1, -1).normalized()
	var nrm := Vector2(d.y, -d.x)
	var tip := c + Vector2(-8, 8)
	var back := tip + d * 18.0
	canvas.draw_colored_polygon(PackedVector2Array([tip, tip + d * 5.0 + nrm * 3.0, back + nrm * 3.0,
			back - nrm * 3.0, tip + d * 5.0 - nrm * 3.0]), ink)
