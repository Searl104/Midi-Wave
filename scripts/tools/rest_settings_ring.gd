class_name RestSettingsRing
extends RingTool
## A rest's tab opens this. The outer ring sets its Value, and the inner ring how many hits it has
## left at the start.


func tool_id() -> String:
	return "rest_settings"


func title() -> String:
	return "Rest"


func build() -> void:
	var o := surface.get_note(note_id)
	if o == null or o.get_modifier("rest") == null:
		return
	var rest: RestModifier = o.get_modifier("rest")
	var col := Palette.channel_color(o.channel)
	radial.outer_items = []
	for v in range(1, RestModifier.MAX_VALUE + 1):
		radial.outer_items.append({"id": v, "label": str(v), "color": col, "selected": v == rest.value})
	radial.inner_items = []
	for n in rest.value + 1:
		radial.inner_items.append({"id": n, "label": str(n), "color": Palette.YELLOW, "selected": n == rest.start_left})
	radial.center_item = {}
	radial.title = "Rest · hits it sits out after firing"
	radial.subtitle = "Inner ring: hits left at the start"
	radial.refresh()


func pick_outer(id: Variant) -> void:
	for gid in surface.selection.group_for(note_id):
		surface.set_rest_value(gid, id)
	build()


func pick_inner(id: Variant) -> void:
	for gid in surface.selection.group_for(note_id):
		surface.set_rest_start(gid, id)
	build()
