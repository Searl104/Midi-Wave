class_name ModifierTool
extends RingTool
## Outer ring = modifier (None / Toggle); inner ring = the toggle's state (On / Off), which sets
## both its current and its start state.


func tool_id() -> String:
	return "modifier"


func title() -> String:
	return "Modifier"


func build() -> void:
	var o := surface.get_note(note_id)
	if o == null:
		return
	var col := Palette.channel_color(o.channel)
	var toggle: bool = o.mod_kind() == "toggle"
	radial.outer_items = [
		{"id": "", "label": "None", "color": Palette.TEXT_DIM, "selected": o.modifier == null},
		{"id": "toggle", "label": "Toggle", "color": col, "selected": toggle},
	]
	radial.inner_items = []
	if toggle:
		radial.inner_items = [
			{"id": true, "label": "On", "color": col, "selected": o.modifier.on},
			{"id": false, "label": "Off", "color": Palette.TEXT_DIM, "selected": not o.modifier.on},
		]
	radial.center_item = {}
	radial.title = "Modifier"
	radial.subtitle = "Toggle: plays every other hit · inner ring sets its start state" if toggle else "Toggle: plays every other hit"
	radial.refresh()


func pick_outer(id: Variant) -> void:
	for gid in surface.selection.group_for(note_id):
		surface.set_modifier(gid, id)
	build()


func pick_inner(id: Variant) -> void:
	for gid in surface.selection.group_for(note_id):
		surface.set_modifier_state(gid, id)
	build()


func draw_icon(canvas: CanvasItem, c: Vector2, ink: Color) -> void:
	canvas.draw_circle(c, 2.2, ink)
	canvas.draw_arc(c, 6.0, -0.9, 0.9, 10, ink, 1.5, true)
	canvas.draw_arc(c, 6.0, PI - 0.9, PI + 0.9, 10, ink, 1.5, true)
	canvas.draw_arc(c, 10.0, -0.75, 0.75, 12, Color(ink, 0.6), 1.5, true)
	canvas.draw_arc(c, 10.0, PI - 0.75, PI + 0.75, 12, Color(ink, 0.6), 1.5, true)
