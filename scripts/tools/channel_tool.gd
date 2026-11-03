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
	PanelBuilder.slider(box, "Default length", "note_beats", Settings.LENGTH_STEP, Settings.LENGTH_MAX, Settings.LENGTH_STEP, PanelBuilder.beats_text)
	PanelBuilder.section(box, "CHANNELS", Palette.RED)
	box.add_child(PanelBuilder.hint("Left knob: volume. Right knob: note length. Drag or scroll to turn; double-click resets."))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 1)
	box.add_child(grid)
	var knobs: Array = []
	for ch in 16:
		knobs.append_array(_channel_cell(grid, ch))
	box.add_child(PanelBuilder.button("Reset all", func() -> void:
		for k in knobs:
			k.value = k.reset_value, "Returns every channel to full volume and the Default length."))


## A channel's name, volume knob and note length knob.
func _channel_cell(grid: GridContainer, ch: int) -> Array:
	var cell := HBoxContainer.new()
	cell.add_theme_constant_override("separation", 0)
	grid.add_child(cell)
	var dot := ColorRect.new()
	dot.color = Palette.channel_color(ch)
	dot.custom_minimum_size = Vector2(6, 22)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cell.add_child(dot)
	var name_l := Label.new()
	name_l.text = str(ch + 1)
	name_l.custom_minimum_size.x = 24
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell.add_child(name_l)
	var volume := Knob.new()
	volume.min_value = 0.0
	volume.max_value = 1.0
	volume.step = 0.05
	volume.reset_value = 1.0
	volume.color = Palette.channel_color(ch)
	volume.fmt = func(v: float) -> String: return "Off" if v <= 0.0 else "%d%%" % roundi(v * 100.0)
	volume.tooltip_text = "Volume of channel %d: scales the velocity of its notes. Off silences them; relays still fire." % (ch + 1)
	volume.set_quietly(float(Settings.channel_volumes[ch]))
	volume.value_changed.connect(func(v: float) -> void: Settings.set_channel_volume(ch, v))
	cell.add_child(volume)
	var length := Knob.new()
	length.min_value = 0.0
	length.max_value = Settings.LENGTH_MAX
	length.step = Settings.LENGTH_STEP
	length.reset_value = 0.0
	length.color = Palette.channel_color(ch)
	length.fmt = func(v: float) -> String: return "Def" if v <= 0.0 else PanelBuilder.beats_text(v).get_slice(" ", 0) + "b"
	length.tooltip_text = "How long notes on channel %d are held, in eighth notes. Fully left uses the Default length." % (ch + 1)
	length.set_quietly(float(Settings.channel_beats[ch]))
	length.value_changed.connect(func(v: float) -> void: Settings.set_channel_beats(ch, v))
	cell.add_child(length)
	return [volume, length]


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
