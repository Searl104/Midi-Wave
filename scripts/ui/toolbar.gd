class_name Toolbar
extends Control
## The tool strip on the left edge, one slot per tool in ToolManager. Each tool draws its own icon;
## the active tool is lit, and a yellow bar marks the ring option. Right-click opens an item's
## ToolPanel, if it has options.

const SLOT := 44.0
const PAD := 6.0

var surface: WaveSurface
var panel: ToolPanel
var _hover := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
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


func _slot_at(p: Vector2) -> int:
	for i in surface.tools.tools.size():
		if _slot_rect(i).has_point(p):
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm:
		_set_hover(_slot_at(mm.position))
		accept_event()
		return
	var mb := event as InputEventMouseButton
	if mb:
		accept_event()
		var i := _slot_at(mb.position)
		if mb.pressed and i != -1:
			_slot_pressed(surface.tools.tools[i], mb.button_index, i)


## Clicking the panel's own item closes it. A left click picks; a right click opens that tool's
## panel, if it has one.
func _slot_pressed(item: Tool, button: int, i: int) -> void:
	if button != MOUSE_BUTTON_LEFT and button != MOUSE_BUTTON_RIGHT:
		return
	if panel.is_open_for(item):
		panel.close()
	elif button == MOUSE_BUTTON_LEFT:
		panel.close()
		surface.tools.pick(item.tool_id())
	elif item.has_options():
		panel.open(item, global_position.y + _slot_rect(i).get_center().y)
	else:
		panel.close()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_set_hover(-1)


func _set_hover(i: int) -> void:
	if i != _hover:
		_hover = i
		queue_redraw()


func _get_tooltip(at_position: Vector2) -> String:
	var i := _slot_at(at_position)
	return surface.tools.tools[i].title() if i != -1 else ""


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
		if on or i == _hover:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(Palette.ACCENT, 0.32) if on else Color(1, 1, 1, 0.06)
			if on:
				sb.border_color = Color(Palette.ACCENT.lightened(0.3), 0.9)
				sb.set_border_width_all(1)
			sb.set_corner_radius_all(7)
			draw_style_box(sb, r)
		if i > 0 and t.section() != manager.tools[i - 1].section():
			# Sections: a faint line after Wave, then stronger ones.
			var line := Color(1, 1, 1, 0.08 if t.section() == 1 else 0.14)
			draw_line(Vector2(PAD + 6, r.position.y - 1), Vector2(PAD + SLOT - 6, r.position.y - 1), line, 1.0)
		var option := t == manager.ring_option
		if option:
			draw_rect(Rect2(r.position + Vector2(1, 9), Vector2(3, SLOT - 18)), Palette.YELLOW)
		var ink := Palette.TEXT if on or option else Palette.TEXT_DIM
		t.draw_icon(self, r.get_center(), ink)
