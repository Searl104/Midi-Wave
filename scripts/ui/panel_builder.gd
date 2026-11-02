class_name PanelBuilder
extends RefCounted
## The controls the Options panel and tool panels are made of. Most edit one Settings key.


static func check(box: VBoxContainer, label: String, key: String) -> CheckButton:
	var c := CheckButton.new()
	c.text = label
	c.focus_mode = Control.FOCUS_NONE
	c.button_pressed = bool(Settings.get(key))
	c.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
	box.add_child(c)
	return c


static func pick(box: VBoxContainer, label: String, key: String, values: Array, labels: Array) -> OptionButton:
	var row := HBoxContainer.new()
	box.add_child(row)
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	for t in labels:
		o.add_item(str(t))
	o.select(maxi(0, values.find(Settings.get(key))))
	o.item_selected.connect(func(i: int) -> void: Settings.set_value(key, values[i]))
	row.add_child(o)
	return o


static func section(box: VBoxContainer, text: String, col: Color) -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	box.add_child(gap)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var dot := ColorRect.new()
	dot.color = col
	dot.custom_minimum_size = Vector2(3, 14)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Palette.TEXT_DIM)
	row.add_child(l)


static func slider(box: VBoxContainer, label: String, key: String, min_v: float, max_v: float,
		step: float, fmt: Callable) -> HSlider:
	var row := HBoxContainer.new()
	box.add_child(row)
	var name_l := Label.new()
	name_l.text = label
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_l)
	var val_l := Label.new()
	val_l.add_theme_color_override("font_color", Palette.TEXT_DIM)
	row.add_child(val_l)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = Settings.get(key)
	s.focus_mode = Control.FOCUS_NONE
	val_l.text = fmt.call(s.value)
	s.value_changed.connect(func(v: float) -> void:
		val_l.text = fmt.call(v)
		Settings.set_value(key, v))
	box.add_child(s)
	return s


static func button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	return b


static func hint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Palette.TEXT_DIM)
	l.add_theme_font_size_override("font_size", 12)
	return l
