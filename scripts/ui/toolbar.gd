class_name Toolbar
extends Control
## The tool strip on the left edge, one slot per tool in ToolManager. Each tool draws its own icon;
## the active tool is lit.

const SLOT := 44.0
const PAD := 6.0

var surface: WaveSurface


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := surface.tools.tools.size()
	custom_minimum_size = Vector2(SLOT + PAD * 2.0, n * SLOT + (n - 1) * 2.0 + PAD * 2.0)
	size = custom_minimum_size
	set_anchors_preset(Control.PRESET_CENTER_LEFT)
	offset_left = 12.0
	offset_right = 12.0 + size.x
	offset_top = -size.y / 2.0
	offset_bottom = size.y / 2.0


func _slot_rect(i: int) -> Rect2:
	return Rect2(Vector2(PAD, PAD + i * (SLOT + 2.0)), Vector2(SLOT, SLOT))


func _draw() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.065, 0.085, 0.82)
	bg.border_color = Color(1, 1, 1, 0.1)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(10)
	draw_style_box(bg, Rect2(Vector2.ZERO, size))
	var manager := surface.tools
	for i in manager.tools.size():
		var t: Tool = manager.tools[i]
		var r := _slot_rect(i)
		var on := t == manager.current
		if on:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(Palette.ACCENT, 0.32)
			sb.border_color = Color(Palette.ACCENT.lightened(0.3), 0.9)
			sb.set_border_width_all(1)
			sb.set_corner_radius_all(7)
			draw_style_box(sb, r)
		if i == 1:
			draw_line(Vector2(PAD + 6, r.position.y - 1), Vector2(PAD + SLOT - 6, r.position.y - 1), Color(1, 1, 1, 0.08), 1.0)
		if i == 3:
			draw_line(Vector2(PAD + 6, r.position.y - 1), Vector2(PAD + SLOT - 6, r.position.y - 1), Color(1, 1, 1, 0.14), 1.0)
		var ink := Palette.TEXT if on else Palette.TEXT_DIM
		t.draw_icon(self, r.get_center(), ink)
