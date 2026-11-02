class_name PulseTool
extends RingTool
## Outer ring = cooldown, inner ring = emit strength, centre = switch Note <-> Relay. Tuning a
## pulse makes a Note a Relay.

## Beats; 0 = Retrigger (no timer: fires on every wave that reaches it).
const COOLDOWNS := [0.0, 0.125, 1.0 / 6.0, 0.25, 1.0 / 3.0, 0.5, 2.0 / 3.0, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0]
const COOLDOWN_LABELS := ["Retrig", "⅛", "⅙", "¼", "⅓", "½", "⅔", "¾", "1", "1½", "2", "3", "4"]
const STRENGTHS := [0.25, 0.5, 0.75, 1.0]


func tool_id() -> String:
	return "pulse"


func title() -> String:
	return "Pulse"


func build() -> void:
	var o := surface.get_note(note_id)
	if o == null:
		return
	radial.outer_items = []
	for i in COOLDOWNS.size():
		var c: float = COOLDOWNS[i]
		radial.outer_items.append({"id": c, "label": COOLDOWN_LABELS[i], "color": Palette.YELLOW,
				"selected": absf(o.emitter.cooldown - c) < 0.001})
	radial.inner_items = []
	for s in STRENGTHS:
		radial.inner_items.append({"id": s, "label": "%d%%" % roundi(s * 100), "color": Palette.RED,
				"selected": absf(o.emitter.strength - s) < 0.001})
	radial.center_item = {"id": "mode", "label": "Relay" if o is Relay else "Note", "color": Palette.channel_color(o.channel)}
	radial.title = "Pulse · cooldown in beats or Retrigger (outer) · strength (inner)"
	radial.subtitle = "Centre: switch Note ↔ Relay"
	radial.refresh()


func pick_outer(id: Variant) -> void:
	if surface.get_note(note_id) == null:
		return
	for gid in surface.selection.group_for(note_id):
		surface.set_pulse_params(gid, surface.get_note(gid).emitter.strength, id)
		_make_relay(gid)
	build()


func pick_inner(id: Variant) -> void:
	if surface.get_note(note_id) == null:
		return
	for gid in surface.selection.group_for(note_id):
		surface.set_pulse_params(gid, id, surface.get_note(gid).emitter.cooldown)
		_make_relay(gid)
	build()


func pick_center(id: Variant) -> void:
	if note_id != -1 and id == "mode":
		surface.cycle_mode(note_id)
		build()


func _make_relay(id: int) -> void:
	if surface.get_note(id).mode == SurfaceObject.Mode.NOTE:
		surface.set_note_mode(id, SurfaceObject.Mode.RELAY)


func draw_icon(canvas: CanvasItem, c: Vector2, ink: Color) -> void:
	canvas.draw_circle(c, 3.0, ink)
	canvas.draw_arc(c, 9.0, 0.0, TAU, 32, Color(1, 1, 1, 0.12), 2.0, true)
	canvas.draw_arc(c, 9.0, -PI / 2.0, PI, 32, Color(Palette.YELLOW, 0.95 if ink == Palette.TEXT else 0.7), 2.0, true)
