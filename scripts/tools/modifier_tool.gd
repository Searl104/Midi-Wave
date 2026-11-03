class_name ModifierTool
extends RingTool
## Adds and removes modifiers: None, Rest and Relay. Each modifier's settings are on its tab.


func tool_id() -> String:
	return "modifier"


func title() -> String:
	return "Modifier"


func build() -> void:
	var o := surface.get_note(note_id)
	if o == null:
		return
	var col := Palette.channel_color(o.channel)
	radial.outer_items = [
		{"id": "", "label": "None", "color": Palette.TEXT_DIM, "selected": o.modifiers.is_empty()},
		{"id": "rest", "label": "Rest", "color": col, "selected": o.get_modifier("rest") != null},
		{"id": "relay", "label": "Relay", "color": Palette.YELLOW, "selected": o.relay() != null},
	]
	radial.inner_items = []
	radial.center_item = {}
	radial.title = "Modifiers"
	radial.subtitle = "Right-click a modifier's tab for its settings"
	radial.refresh()


## Adds or removes the picked modifier, or clears them all. The group follows the picked note.
func pick_outer(id: Variant) -> void:
	var o := surface.get_note(note_id)
	if o == null:
		return
	var adding: bool = id != "" and o.get_modifier(id) == null
	for gid in surface.selection.group_for(note_id):
		if id == "":
			surface.clear_modifiers(gid)
		elif adding:
			surface.add_modifier(gid, id)
		else:
			surface.remove_modifier(gid, id)
	build()


func draw_icon(canvas: CanvasItem, c: Vector2, ink: Color) -> void:
	canvas.draw_circle(c, 2.2, ink)
	canvas.draw_arc(c, 6.0, -0.9, 0.9, 10, ink, 1.5, true)
	canvas.draw_arc(c, 6.0, PI - 0.9, PI + 0.9, 10, ink, 1.5, true)
	canvas.draw_arc(c, 10.0, -0.75, 0.75, 12, Color(ink, 0.6), 1.5, true)
	canvas.draw_arc(c, 10.0, PI - 0.75, PI + 0.75, 12, Color(ink, 0.6), 1.5, true)
