class_name ToggleSettingsRing
extends RingTool
## A toggle's tab opens this: On / Off, which sets both its current and its start state.


func tool_id() -> String:
	return "toggle_settings"


func title() -> String:
	return "Toggle"


func build() -> void:
	var o := surface.get_note(note_id)
	if o == null or o.get_modifier("toggle") == null:
		return
	var on: bool = o.get_modifier("toggle").on
	radial.outer_items = [
		{"id": true, "label": "On", "color": Palette.channel_color(o.channel), "selected": on},
		{"id": false, "label": "Off", "color": Palette.TEXT_DIM, "selected": not on},
	]
	radial.inner_items = []
	radial.center_item = {}
	radial.title = "Toggle · start state"
	radial.subtitle = "Toggle: plays every other hit"
	radial.refresh()


func pick_outer(id: Variant) -> void:
	for gid in surface.selection.group_for(note_id):
		surface.set_modifier_state(gid, id)
	build()
