class_name VelocityTool
extends RingTool
## Sets how loudly notes play, as a share of the wave that hits them. Both a tool and a ring option:
## a click stamps the value in its panel on a note, and a drag up or down adjusts it, along with the
## rest of the selection. Its ring is a dial, which right-click opens in any tool when it's chosen.

const DRAG_PIXELS := 2.0           ## px of drag per 1%

var _dragging: Array = []          # [id, velocity at the press]
var _press_y := 0.0
var _shown := -1                   # the note showing its value during a drag


func tool_id() -> String:
	return "velocity"


func title() -> String:
	return "Velocity"


func acts_as_tool() -> bool:
	return true


func has_options() -> bool:
	return true


func build_options(box: VBoxContainer) -> void:
	PanelBuilder.slider(box, "Click sets", "velocity_stamp", 1.0, 100.0, 1.0, func(v: float) -> String: return "%d%%" % v)
	box.add_child(PanelBuilder.hint("Click a note to apply this, then drag up or down to adjust it."))


# --- The tool -------------------------------------------------------------------------------

func handle_input(event: InputEvent) -> bool:
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_press(mb)
		else:
			_end_drag()
		return true
	var mm := event as InputEventMouseMotion
	if mm and not _dragging.is_empty():
		var change := roundi((_press_y - mm.position.y) / DRAG_PIXELS)
		for entry in _dragging:
			surface.set_note_velocity(entry[0], entry[1] + change)
		return true
	return false


func _press(mb: InputEventMouseButton) -> void:
	var hit := surface.note_at(mb.position)
	if hit == -1:
		return
	surface.history.end_group()
	surface.history.set_stroke(true)
	_shown = hit
	_press_y = mb.position.y
	_dragging = []
	for id in surface.selection.group_for(hit):
		surface.set_note_velocity(id, roundi(Settings.velocity_stamp))
		_dragging.append([id, roundi(Settings.velocity_stamp)])


func _end_drag() -> void:
	if _dragging.is_empty():
		return
	_dragging = []
	_shown = -1
	surface.history.set_stroke(false)
	surface.history.end_group()


func deactivate() -> void:
	_end_drag()


func draw_overlay(canvas: WaveSurface) -> void:
	var o := canvas.get_note(_shown)
	if o:
		canvas.draw_string(canvas.get_theme_default_font(), canvas.to_screen(o.pos) + Vector2(-40, -Note.RADIUS - 22.0),
				"%d%%" % o.velocity, HORIZONTAL_ALIGNMENT_CENTER, 80, 13, Palette.TEXT)


# --- The ring -------------------------------------------------------------------------------

func _prepare(_at: Vector2) -> void:
	surface.history.end_group()
	surface.history.set_stroke(true)


func build() -> void:
	var o := surface.get_note(note_id)
	radial.outer_items = []
	radial.inner_items = []
	radial.center_item = {}
	radial.title = "Velocity"
	radial.subtitle = ""
	radial.dial = true
	if o:
		radial.dial_value = o.velocity / 100.0
		radial.dial_text = "%d%%" % o.velocity
		radial.dial_color = Palette.channel_color(o.channel)
	radial.refresh()


func pick_dial(value: float) -> void:
	for id in surface.selection.group_for(note_id):
		surface.set_note_velocity(id, roundi(value * 100.0))
	build()


func ring_closed() -> void:
	surface.history.set_stroke(false)
	surface.history.end_group()


func draw_icon(canvas: CanvasItem, c: Vector2, ink: Color) -> void:
	canvas.draw_arc(c, 9.0, 0.0, TAU, 28, ink, 1.8, true)
	var fill := PackedVector2Array()
	for i in 13:
		fill.append(c + Vector2.from_angle(PI / 12.0 * i) * 6.2)
	canvas.draw_colored_polygon(fill, ink)
