class_name BindTool
extends Tool
## Sets what fires a note. Click a note to arm it (a selected note arms its group), then press
## KP0-9 or hit a MIDI note. Delete or Backspace clears the binding; Esc or a click on empty space
## cancels. A note holds one binding, and many notes can share one.

var _armed: Array = []             # ids waiting for an input


func tool_id() -> String:
	return "bind"


func title() -> String:
	return "Bind"


func section() -> int:
	return 1


func has_options() -> bool:
	return true


func build_options(box: VBoxContainer) -> void:
	PanelBuilder.section(box, "MIDI INPUT", Palette.BLUE)
	box.add_child(MidiInputControls.new())


func deactivate() -> void:
	_armed = []


func armed() -> bool:
	_armed = _armed.filter(func(id: int) -> bool: return surface.get_note(id) != null)
	return not _armed.is_empty()


func bind(binding: String) -> void:
	for id in _armed:
		surface.set_binding(id, binding)
	_armed = []


func handle_input(event: InputEvent) -> bool:
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		var hit := surface.note_at(mb.position)
		_armed = surface.selection.group_for(hit) if hit != -1 else []
		return true
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and armed():
		match key.keycode:
			KEY_ESCAPE:
				_armed = []
				return true
			KEY_DELETE, KEY_BACKSPACE:
				bind("")
				return true
	return false


func draw_overlay(canvas: WaveSurface) -> void:
	if not armed():
		return
	var font := canvas.get_theme_default_font()
	var at := Vector2.ZERO
	for id in _armed:
		var o := surface.get_note(id)
		at = canvas.to_screen(o.pos)
		canvas.draw_brackets(at, o.bracket_half() + 4.0, 2.0, 0.95, 0.5)
	canvas.draw_string(font, at + Vector2(-90, Note.RADIUS + 34.0), "Press KP0-9 or a MIDI note",
			HORIZONTAL_ALIGNMENT_CENTER, 180.0, 12, Palette.YELLOW)


## Two linked rings.
func draw_icon(canvas: CanvasItem, c: Vector2, ink: Color) -> void:
	canvas.draw_arc(c + Vector2(-4, 4), 5.5, 0.0, TAU, 20, ink, 2.0, true)
	canvas.draw_arc(c + Vector2(4, -4), 5.5, 0.0, TAU, 20, ink, 2.0, true)
