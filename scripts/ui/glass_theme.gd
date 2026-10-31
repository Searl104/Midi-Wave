class_name GlassTheme
extends RefCounted
## Builds the app Theme in code: dark glass panels, grey controls, blue accent.


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 14

	t.set_stylebox("panel", "PanelContainer", _box(Color(Palette.GLASS, 1.0), Color(1, 1, 1, 0.1), 16, 18))
	t.set_stylebox("panel", "PopupMenu", _box(Color(0.06, 0.065, 0.078, 0.98), Color(1, 1, 1, 0.1), 10, 6))
	t.set_stylebox("hover", "PopupMenu", _box(Color(Palette.ACCENT, 0.35), Color(0, 0, 0, 0), 6, 4))

	for type in ["Label"]:
		t.set_color("font_color", type, Palette.TEXT)

	var normal := _box(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.1), 8, 8)
	var hover := _box(Color(1, 1, 1, 0.09), Color(1, 1, 1, 0.18), 8, 8)
	var pressed := _box(Color(Palette.ACCENT, 0.35), Color(Palette.ACCENT, 0.9), 8, 8)
	var disabled := _box(Color(1, 1, 1, 0.02), Color(1, 1, 1, 0.05), 8, 8)
	var focus := _box(Color(0, 0, 0, 0), Color(Palette.ACCENT, 0.8), 8, 8)
	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, pressed)
		t.set_stylebox("disabled", type, disabled)
		t.set_stylebox("focus", type, focus)
		t.set_color("font_color", type, Palette.TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_disabled_color", type, Palette.TEXT_DIM)

	var track := _box(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 3, 0)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	var fill := _box(Color(Palette.ACCENT, 0.85), Color(0, 0, 0, 0), 3, 0)
	fill.content_margin_top = 2
	fill.content_margin_bottom = 2
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var grab := _dot(Color(0.92, 0.94, 1.0))
	t.set_icon("grabber", "HSlider", grab)
	t.set_icon("grabber_highlight", "HSlider", _dot(Color.WHITE))

	t.set_stylebox("separator", "HSeparator", _line())

	# Tabs: glass strip, selected tab lit with the accent.
	t.set_stylebox("panel", "TabContainer", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0))
	t.set_stylebox("tabbar_background", "TabContainer", _box(Color(1, 1, 1, 0.03), Color(0, 0, 0, 0), 8, 0))
	t.set_stylebox("tab_selected", "TabContainer", _box(Color(Palette.ACCENT, 0.3), Color(Palette.ACCENT, 0.8), 8, 8))
	t.set_stylebox("tab_unselected", "TabContainer", _box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.08), 8, 8))
	t.set_stylebox("tab_hovered", "TabContainer", _box(Color(1, 1, 1, 0.09), Color(1, 1, 1, 0.16), 8, 8))
	t.set_stylebox("tab_focus", "TabContainer", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 8, 8))
	t.set_color("font_selected_color", "TabContainer", Color.WHITE)
	t.set_color("font_unselected_color", "TabContainer", Palette.TEXT_DIM)
	t.set_color("font_hovered_color", "TabContainer", Palette.TEXT)
	t.set_color("font_color", "CheckButton", Palette.TEXT)
	t.set_color("font_hover_color", "CheckButton", Color.WHITE)
	t.set_color("font_pressed_color", "CheckButton", Palette.TEXT)
	t.set_color("font_hover_pressed_color", "CheckButton", Color.WHITE)
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		t.set_stylebox(st, "CheckButton", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 6, 4))
	return t


static func _box(bg: Color, border: Color, radius: int, margin: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1 if border.a > 0.0 else 0)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	s.anti_aliasing = true
	return s


static func _line() -> StyleBoxLine:
	var s := StyleBoxLine.new()
	s.color = Color(1, 1, 1, 0.08)
	s.thickness = 1
	return s


static func _dot(col: Color) -> ImageTexture:
	var d := 14
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := Vector2(d, d) / 2.0
	for y in d:
		for x in d:
			var dist := Vector2(x + 0.5, y + 0.5).distance_to(c)
			img.set_pixel(x, y, Color(col, clampf(d / 2.0 - dist, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
