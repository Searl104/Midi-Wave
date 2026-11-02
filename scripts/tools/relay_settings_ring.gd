class_name RelaySettingsRing
extends RingTool
## A relay's tab opens this. Outer ring = cooldown, inner ring = emit strength, centre = Sound.

## Beats; 0 = Retrigger (no timer: fires on every wave that reaches it).
const COOLDOWNS := [0.0, 0.125, 1.0 / 6.0, 0.25, 1.0 / 3.0, 0.5, 2.0 / 3.0, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0]
const COOLDOWN_LABELS := ["Retrig", "⅛", "⅙", "¼", "⅓", "½", "⅔", "¾", "1", "1½", "2", "3", "4"]
const STRENGTHS := [0.25, 0.5, 0.75, 1.0]


func tool_id() -> String:
	return "relay_settings"


func title() -> String:
	return "Relay"


func build() -> void:
	var o := surface.get_note(note_id)
	if o == null or o.relay() == null:
		return
	var e: Emitter = o.emitter()
	radial.outer_items = []
	for i in COOLDOWNS.size():
		var c: float = COOLDOWNS[i]
		radial.outer_items.append({"id": c, "label": COOLDOWN_LABELS[i], "color": Palette.YELLOW,
				"selected": absf(e.cooldown - c) < 0.001})
	radial.inner_items = []
	for s in STRENGTHS:
		radial.inner_items.append({"id": s, "label": "%d%%" % roundi(s * 100), "color": Palette.RED,
				"selected": absf(e.strength - s) < 0.001})
	radial.center_item = {"id": "sound", "label": "Sound" if o.relay().sound else "Mute", "color": Palette.channel_color(o.channel)}
	radial.title = "Relay · cooldown in beats or Retrigger (outer) · strength (inner)"
	radial.subtitle = "Centre: note sound on / off"
	radial.refresh()


func _group() -> Array:
	var out: Array = []
	for gid in surface.selection.group_for(note_id):
		if surface.get_note(gid) and surface.get_note(gid).relay():
			out.append(gid)
	return out


func pick_outer(id: Variant) -> void:
	for gid in _group():
		surface.set_pulse_params(gid, surface.get_note(gid).emitter().strength, id)
	build()


func pick_inner(id: Variant) -> void:
	for gid in _group():
		surface.set_pulse_params(gid, id, surface.get_note(gid).emitter().cooldown)
	build()


func pick_center(_id: Variant) -> void:
	var o := surface.get_note(note_id)
	if o == null or o.relay() == null:
		return
	var on: bool = not o.relay().sound
	for gid in _group():
		surface.set_relay_sound(gid, on)
	build()
