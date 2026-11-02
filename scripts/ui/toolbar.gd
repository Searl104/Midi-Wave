class_name Toolbar
extends Control
## The tool strip on the left edge: Wave, Select, Draw, then the ring tools Pitch, Channel,
## Pulse and Modifier (number keys 1-7). Icons are drawn here; the active tool is lit, and Draw
## shows what it places (a solid dot for Notes, a hollow ring and diamond for Relays).

signal tool_picked(tool: String)

const SLOT := 44.0
const PAD := 6.0
const LABELS := {
	"wave": "Wave (1): click for waves and to play notes; the layout is locked",
	"select": "Select (2): click to select, drag on empty space to box select, drag to move",
	"draw": "Draw (3): click or drag to place on grid points; press 3 again to switch Notes / Relays",
	"pitch": "Pitch (4): click a note for its pitch ring, or empty space to place a note",
	"channel": "Channel (5): click a note for its channel ring",
	"pulse": "Pulse (6): click a note for its pulse ring",
	"modifier": "Modifier (7): click a note for its modifier ring",
}

var surface: WaveSurface
var _hover := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var n := WaveSurface.TOOLS.size()
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
	for i in WaveSurface.TOOLS.size():
		if _slot_rect(i).has_point(p):
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm:
		var h := _slot_at(mm.position)
		if h != _hover:
			_hover = h
			queue_redraw()
		accept_event()
		return
	var mb := event as InputEventMouseButton
	if mb:
		accept_event()
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var i := _slot_at(mb.position)
			if i != -1:
				tool_picked.emit(WaveSurface.TOOLS[i])


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover != -1:
		_hover = -1
		queue_redraw()


func _get_tooltip(at_position: Vector2) -> String:
	var i := _slot_at(at_position)
	return LABELS[WaveSurface.TOOLS[i]] if i != -1 else ""


func _draw() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.065, 0.085, 0.82)
	bg.border_color = Color(1, 1, 1, 0.1)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(10)
	draw_style_box(bg, Rect2(Vector2.ZERO, size))
	var font := get_theme_default_font()
	var active: String = surface.tool if surface else "select"
	for i in WaveSurface.TOOLS.size():
		var t_name: String = WaveSurface.TOOLS[i]
		var r := _slot_rect(i)
		var on := t_name == active
		if on or i == _hover:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(Palette.ACCENT, 0.32) if on else Color(1, 1, 1, 0.06)
			if on:
				sb.border_color = Color(Palette.ACCENT.lightened(0.3), 0.9)
				sb.set_border_width_all(1)
			sb.set_corner_radius_all(7)
			draw_style_box(sb, r)
		if i == 1:
			draw_line(Vector2(PAD + 6, r.position.y - 1), Vector2(PAD + SLOT - 6, r.position.y - 1), Color(1, 1, 1, 0.08), 1.0)
		if i == 3:
			draw_line(Vector2(PAD + 6, r.position.y - 1), Vector2(PAD + SLOT - 6, r.position.y - 1), Color(1, 1, 1, 0.14), 1.0)
		var ink := Palette.TEXT if on else Palette.TEXT_DIM
		_draw_icon(t_name, r.get_center(), ink)
		draw_string(font, r.position + Vector2(3, 11), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(ink, 0.7))


func _draw_icon(t_name: String, c: Vector2, ink: Color) -> void:
	match t_name:
		"wave":
			# A teardrop: a circle with a point, the sides tangent to it.
			var ctr := c + Vector2(0, 3)
			var r := 6.5
			var tip := ctr + Vector2(0, -13.0)
			var pts := PackedVector2Array([tip])
			var a0 := -PI / 2.0 + acos(r / 13.0)
			var a1 := -PI / 2.0 - acos(r / 13.0) + TAU
			for k in 25:
				var a := lerpf(a0, a1, k / 24.0)
				pts.append(ctr + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(pts, ink)
		"select":
			var a := c + Vector2(-5, -9)
			draw_colored_polygon(PackedVector2Array([a, a + Vector2(0, 16), a + Vector2(4, 12), a + Vector2(7, 18),
					a + Vector2(9.5, 17), a + Vector2(6.5, 11), a + Vector2(11.5, 11)]), ink)
		"draw":
			var d := Vector2(1, -1).normalized()
			var nrm := Vector2(d.y, -d.x)
			var tip := c + Vector2(-8, 8)
			var back := tip + d * 18.0
			draw_colored_polygon(PackedVector2Array([tip, tip + d * 5.0 + nrm * 3.0, back + nrm * 3.0,
					back - nrm * 3.0, tip + d * 5.0 - nrm * 3.0]), ink)
			# What it places: Note = solid dot, Relay = hollow ring with a diamond.
			var b := c + Vector2(9, 9)
			if surface and surface.draw_type == WaveSurface.Mode.RELAY:
				draw_arc(b, 4.0, 0.0, TAU, 16, Palette.YELLOW, 1.5, true)
				draw_colored_polygon(PackedVector2Array([b + Vector2(0, -2), b + Vector2(2, 0), b + Vector2(0, 2), b + Vector2(-2, 0)]), Palette.YELLOW)
			else:
				draw_circle(b, 4.0, Palette.ACCENT.lightened(0.2))
		"pitch":
			# A quaver.
			draw_circle(c + Vector2(-3, 6), 4.0, ink)
			draw_line(c + Vector2(0.5, 6), c + Vector2(0.5, -9), ink, 2.0, true)
			draw_line(c + Vector2(0.5, -9), c + Vector2(6, -4), ink, 2.0, true)
		"channel":
			for k in 4:
				var o := Vector2(-5 if k % 2 == 0 else 5, -5 if k < 2 else 5)
				draw_circle(c + o, 3.6, Color(Palette.channel_color(k), 0.95 if ink == Palette.TEXT else 0.7))
		"pulse":
			draw_circle(c, 3.0, ink)
			draw_arc(c, 9.0, 0.0, TAU, 32, Color(1, 1, 1, 0.12), 2.0, true)
			draw_arc(c, 9.0, -PI / 2.0, PI, 32, Color(Palette.YELLOW, 0.95 if ink == Palette.TEXT else 0.7), 2.0, true)
		"modifier":
			draw_circle(c, 2.2, ink)
			draw_arc(c, 6.0, -0.9, 0.9, 10, ink, 1.5, true)
			draw_arc(c, 6.0, PI - 0.9, PI + 0.9, 10, ink, 1.5, true)
			draw_arc(c, 10.0, -0.75, 0.75, 12, Color(ink, 0.6), 1.5, true)
			draw_arc(c, 10.0, PI - 0.75, PI + 0.75, 12, Color(ink, 0.6), 1.5, true)
