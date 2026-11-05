class_name SequenceSettingsRing
extends RingTool
## A sequence's tab opens this. The inner ring sets how many steps it has, and the outer ring turns
## each step On or Off, clockwise from the top.


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
	radial.title = "Sequence · which activations sound"
	radial.subtitle = "Inner ring: steps. Outer ring: On or Off, clockwise"
	radial.refresh()


func pick_outer(id: Variant) -> void:
	var seq := _sequence()
	if seq == null or id >= seq.steps.size():
		return
	var on: bool = not seq.steps[id]
	for gid in surface.selection.group_for(note_id):
		surface.set_sequence_step(gid, id, on)
	build()


func pick_inner(id: Variant) -> void:
	for gid in surface.selection.group_for(note_id):
		surface.set_sequence_count(gid, id)
	build()
