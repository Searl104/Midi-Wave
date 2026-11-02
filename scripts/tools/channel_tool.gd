class_name ChannelTool
extends RingTool
## Outer ring = the 16 MIDI channels.


func tool_id() -> String:
	return "channel"


func title() -> String:
	return "Channel"


func has_options() -> bool:
	return true


func build_options(box: VBoxContainer) -> void:
	PanelBuilder.section(box, "NOTE LENGTH", Palette.RED)
	PanelBuilder.slider(box, "Default", "note_length", 0.05, 2.0, 0.01, func(v: float) -> String: return "%.2f s" % v)
	var sliders: Array = []
	for ch in 16:
		sliders.append(_channel_row(box, ch))
	box.add_child(PanelBuilder.button("Reset all to Default", func() -> void:
		for s in sliders:
			s.value = 0.0, "Returns every channel to the Default note length."))


## A channel's own note length; 0 follows Default.
func _channel_row(box: VBoxContainer, ch: int) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.tooltip_text = "How long notes on channel %d are held. All the way left uses Default." % (ch + 1)
	box.add_child(row)
	var dot := ColorRect.new()
	dot.color = Palette.channel_color(ch)
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var name_l := Label.new()
	name_l.text = "Ch %d" % (ch + 1)
	name_l.custom_minimum_size.x = 44
	row.add_child(name_l)
	var s := HSlider.new()
	s.tooltip_text = row.tooltip_text
	s.min_value = 0.0
	s.max_value = 4.0
	s.step = 0.01
	s.value = float(Settings.channel_lengths[ch])
	s.focus_mode = Control.FOCUS_NONE
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var val_l := Label.new()
	val_l.custom_minimum_size.x = 56
	val_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_l.add_theme_color_override("font_color", Palette.TEXT_DIM)
	row.add_child(val_l)
	var show_value := func(v: float) -> void:
		val_l.text = "Default" if v <= 0.0 else "%.2f s" % v
	show_value.call(s.value)
	s.value_changed.connect(func(v: float) -> void:
		show_value.call(v)
		Settings.set_channel_length(ch, v))
	return s


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
