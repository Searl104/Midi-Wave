class_name NavTool
extends Tool
## A tool that moves the view instead of editing, used by dragging with the left or middle button.
## It leaves the layout and selection alone, so it can spring-load over any other tool.

var _button := MOUSE_BUTTON_NONE   # the button holding the drag
var _start := Vector2.ZERO
var _last := Vector2.ZERO


func section() -> int:
	return 3


func navigates() -> bool:
	return true


func deactivate() -> void:
	_button = MOUSE_BUTTON_NONE


func handle_input(event: InputEvent) -> bool:
	var mb := event as InputEventMouseButton
	if mb:
		if mb.button_index != MOUSE_BUTTON_LEFT and mb.button_index != MOUSE_BUTTON_MIDDLE:
			return false
		if mb.pressed and _button == MOUSE_BUTTON_NONE:
			_button = mb.button_index
			_start = mb.position
			_last = mb.position
		elif not mb.pressed and mb.button_index == _button:
			_button = MOUSE_BUTTON_NONE
		return true
	var mm := event as InputEventMouseMotion
	if mm and _button != MOUSE_BUTTON_NONE:
		_dragged(mm.position - _last)
		_last = mm.position
		return true
	return false


## The pointer moved by `delta` during a drag.
func _dragged(_delta: Vector2) -> void:
	pass
