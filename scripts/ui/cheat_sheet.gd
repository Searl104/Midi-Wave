class_name CheatSheet
extends Control
## The ? / F1 overlay: every control, grouped by task. Esc, ?, F1 or a click closes it.

const SECTIONS := [
	["TOOLS (TAP A KEY; HOLD IT FOR NOW ONLY)", [
		["1  Wave", "Click: wave, or play a note · layout locked"],
		["2  Select", "Click: select (Shift adds) · drag empty: box · drag: move"],
		["3  Draw", "Click / drag: place on grid points · 3 again: Notes / Relays"],
		["4  Pitch", "Click a note (or empty space): pitch ring"],
		["5  Channel", "Click a note: channel ring"],
		["6  Pulse", "Click a note: pulse ring"],
		["7  Modifier", "Click a note: modifier ring"],
		["Tab", "Wave ↔ the last editing tool"],
	]],
	["PLAY", [
		["KP1–KP9, pads", "Fire that key's notes (hold: pulsers refire)"],
		["Space, KP0", "Stop: clear waves, reset toggles"],
		["Ctrl+S", "Save state: toggles' current state becomes their start"],
	]],
	["RINGS", [
		["Right-click", "Pitch ring (a relay: pulse ring)"],
		["Hold, aim, release", "Pick and close (outer, inner or centre)"],
		["Left-click in a ring", "Pick and keep it open"],
		["In the pitch ring", "A / D or wheel: octave · type 1–16: channel"],
		["Pitch ring centre", "Delete the note"],
	]],
	["EDIT", [
		["Ctrl-click", "Switch Note ↔ Relay"],
		["Drag the ◆", "Place where a relay's wave starts"],
		["Ctrl-drag a relay", "Its own wave reach (back onto it: global)"],
		["< / >", "Nudge a scale step (Shift: an octave)"],
		["M", "Mute / unmute (no sound, no pulse)"],
		["Ctrl+KP1–KP9", "Assign / unassign a keypad key"],
		["Delete", "Remove the selection or hovered note"],
		["Ctrl+C / Ctrl+V", "Copy / paste the selection"],
	]],
	["SNAP", [
		["G over a note or ◆", "Grid on / off under it"],
		["Ctrl+G", "Clear every grid"],
		["While dragging", "Snaps to the nearest grid point or centre"],
		["Shift while dragging", "Place freely"],
	]],
	["VIEW AND APP", [
		["Middle-drag, arrows", "Pan"],
		["Ctrl + wheel", "Zoom about the pointer"],
		["Home", "Centre on the notes"],
		["Ctrl+Z", "Undo (Ctrl+Shift+Z or Ctrl+Y: redo)"],
		["O", "Options"],
		["? or F1", "This sheet"],
	]],
]

var _panel: PanelContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.065, 0.085, 0.97)
	sb.border_color = Color(1, 1, 1, 0.12)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(22)
	_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	_panel.add_child(outer)
	var title := Label.new()
	title.text = "All controls"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Palette.TEXT)
	outer.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 34)
	grid.add_theme_constant_override("v_separation", 18)
	outer.add_child(grid)
	var colors := [Palette.ACCENT, Palette.YELLOW, Palette.RED, Palette.TEXT, Palette.ACCENT, Palette.TEXT_DIM]
	for i in SECTIONS.size():
		grid.add_child(_section(SECTIONS[i], colors[i % colors.size()]))

	var foot := Label.new()
	foot.text = "The bar at the bottom shows what you can do with whatever is under the mouse.   Esc or ? closes."
	foot.add_theme_font_size_override("font_size", 12)
	foot.add_theme_color_override("font_color", Palette.TEXT_DIM)
	outer.add_child(foot)
	hide()


func _section(sec: Array, col: Color) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	box.add_theme_constant_override("separation", 4)
	var head := Label.new()
	head.text = sec[0]
	head.add_theme_font_size_override("font_size", 12)
	head.add_theme_color_override("font_color", col)
	box.add_child(head)
	var rows := GridContainer.new()
	rows.columns = 2
	rows.add_theme_constant_override("h_separation", 12)
	rows.add_theme_constant_override("v_separation", 3)
	box.add_child(rows)
	for r in sec[1]:
		var k := Label.new()
		k.text = r[0]
		k.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		k.add_theme_font_size_override("font_size", 12)
		k.add_theme_color_override("font_color", Palette.TEXT)
		rows.add_child(k)
		var a := Label.new()
		a.text = r[1]
		a.add_theme_font_size_override("font_size", 12)
		a.add_theme_color_override("font_color", Palette.TEXT_DIM)
		a.custom_minimum_size.x = 200
		a.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(a)
	return box


func toggle() -> void:
	visible = not visible


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed:
		hide()
		accept_event()
