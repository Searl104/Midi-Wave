extends Node
## Shared state and input helpers for the checks in tests/tools/. Run them with res://tests/tools.tscn.

var surface: WaveSurface
var tools: ToolManager
var radial: RadialMenu
## Shared by every area: {"checks": int, "failures": int}.
var counts: Dictionary


func _check(ok: bool, what: String) -> void:
	counts.checks += 1
	if not ok:
		counts.failures += 1
		print("  failed: ", what)


func _press(button: MouseButton, down: bool, at: Vector2, shift: bool = false, ctrl: bool = false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = down
	e.position = at
	e.shift_pressed = shift
	e.ctrl_pressed = ctrl
	surface._gui_input(e)


func _move(at: Vector2, alt: bool = false) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.alt_pressed = alt
	surface._gui_input(e)


func _click(at: Vector2, shift: bool = false) -> void:
	_press(MOUSE_BUTTON_LEFT, true, at, shift)
	_press(MOUSE_BUTTON_LEFT, false, at, shift)


func _drag(from: Vector2, to: Vector2, alt: bool = false, ctrl: bool = false) -> void:
	_press(MOUSE_BUTTON_LEFT, true, from, false, ctrl)
	_move(to, alt)
	_press(MOUSE_BUTTON_LEFT, false, to, false, ctrl)


func _key(code: Key, ctrl: bool = false, shift: bool = false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.ctrl_pressed = ctrl
	e.shift_pressed = shift
	tools.handle_input(e)


func _ids(d: Dictionary) -> Array:
	var out: Array = d.keys()
	out.sort()
	return out


func _radial_press(button: MouseButton, down: bool, at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = down
	e.position = at
	radial._input(e)


func _radial_move(at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	radial._input(e)


func _kp(digit: int, down: bool = true) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = (KEY_KP_0 + digit) as Key
	e.pressed = down
	tools.handle_input(e)


func _knobs(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Knob:
			out.append(c)
		out.append_array(_knobs(c))
	return out


func _knob_input(k: Knob, e: InputEvent) -> void:
	k._gui_input(e)


## Stands in for the native device.
class FakeDevice:
	extends RefCounted
	static var opened: Array = []
	var port := ""
	var sent: Array = []
	var names := ["Bass", "Keys", "Drums"]

	func get_port_count() -> int:
		return names.size()

	func get_port_name(i: int) -> String:
		return names[i]

	func get_api_name() -> String:
		return "fake"

	func open_port(i: int) -> bool:
		port = names[i]
		opened.append(self)
		return true

	func is_port_open() -> bool:
		return port != ""

	func close_port() -> void:
		port = ""

	func send_message(bytes: PackedByteArray) -> bool:
		sent.append(bytes)
		return true
