class_name ChannelTool
extends RingTool
## Outer ring = the 16 MIDI channels.


func tool_id() -> String:
	return "channel"


func title() -> String:
	return "Channel"


func build() -> void:
	var o := surface.get_note(note_id)
	var current: int = o.channel if o else 0
	radial.inner_items = []
	radial.center_item = {}
	radial.outer_items = []
	for ch in 16:
		radial.outer_items.append({"id": ch, "label": str(ch + 1), "color": Palette.channel_color(ch), "selected": ch == current})
	radial.title = "MIDI channel"
	radial.subtitle = ""
	radial.refresh()


func pick_outer(id: Variant) -> void:
	var ch: int = id
	for gid in surface.selection.group_for(note_id):
		surface.set_note_channel(gid, ch)
	var o := surface.get_note(note_id)
	if o:
		Midi.play_note(o.note, 90, 0.25, ch)
	build()


func draw_icon(canvas: CanvasItem, c: Vector2, ink: Color) -> void:
	for k in 4:
		var o := Vector2(-5 if k % 2 == 0 else 5, -5 if k < 2 else 5)
		canvas.draw_circle(c + o, 3.6, Color(Palette.channel_color(k), 0.95 if ink == Palette.TEXT else 0.7))
