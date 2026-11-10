class_name SequenceSettingsRing
extends RingTool
## A sequence's tab opens this. The inner ring sets how many steps it has, and the outer ring turns
## each step On or Off, clockwise from the top. A left drag across the outer ring paints: every step
## it crosses takes the state the first step was turned to, as one undo step.

var _painting := false             # a stroke that began with pick_outer is open
var _paint_on := true              ## the state a paint stroke sets


func tool_id() -> String:
	return "sequence_settings"


func title() -> String:
	return "Sequence"


func _sequence() -> SequenceModifier:
	var o := surface.get_note(note_id)
	return o.get_modifier("sequence") if o else null


func build() -> void:
	var seq := _sequence()
	if seq == null:
		return
	radial.outer_items = []
	for i in seq.steps.size():
		var on: bool = seq.steps[i]
		radial.outer_items.append({"id": i, "label": str(i + 1), "color": Palette.BLUE if on else Palette.TEXT_DIM, "selected": on})
	radial.inner_items = []
	for n in range(1, SequenceModifier.MAX_STEPS + 1):
		radial.inner_items.append({"id": n, "label": str(n), "color": Palette.YELLOW, "selected": n == seq.steps.size()})
	radial.center_item = {}
	radial.paint_outer = true
	radial.title = "Sequence · which activations sound"
	radial.subtitle = "Inner ring: steps. Outer ring: On or Off, clockwise"
	radial.refresh()


func pick_outer(id: Variant) -> void:
	var seq := _sequence()
	if seq == null or id >= seq.steps.size():
		return
	_end_stroke()
	_painting = true
	surface.history.end_group()
	surface.history.set_stroke(true)
	_paint_on = not seq.steps[id]
	for gid in surface.selection.group_for(note_id):
		surface.set_sequence_step(gid, id, _paint_on)
	build()


func paint_outer(id: Variant) -> void:
	var seq := _sequence()
	if not _painting or seq == null or id >= seq.steps.size():
		return
	for gid in surface.selection.group_for(note_id):
		surface.set_sequence_step(gid, id, _paint_on)
	build()


func paint_ended() -> void:
	_end_stroke()


func ring_closed() -> void:
	_end_stroke()


func _end_stroke() -> void:
	if _painting:
		_painting = false
		surface.history.set_stroke(false)
		surface.history.end_group()


func pick_inner(id: Variant) -> void:
	for gid in surface.selection.group_for(note_id):
		surface.set_sequence_count(gid, id)
	build()
