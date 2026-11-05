class_name Knob
extends Control
## A compact dial for tight panels. Drag up or down to turn it, scroll to step it, and double-click
## to reset it. It shows its value underneath, in `fmt`.

signal value_changed(value: float)

const SIZE := Vector2(46, 46)
const RADIUS := 15.0
const SWEEP := 1.5 * PI            ## the dial's arc, with its gap at the bottom
const START := 0.75 * PI
const DRAG_PIXELS := 150.0         ## drag this far for the full range

var min_value := 0.0
var max_value := 1.0
var step := 0.05                   ## what values snap to; 0 is continuous
var wheel_step := 0.0              ## a scroll notch, if not `step`
var reset_value := 0.0
var color := Color.WHITE
var fmt: Callable
var value := 0.0:
	set(v):
		var snapped_v := clampf(snappedf(v, step) if step > 0.0 else v, min_value, max_value)
		if not is_equal_approx(snapped_v, value):
			value = snapped_v
			value_changed.emit(value)
			queue_redraw()

var _dragged := 0.0                # where the drag has got to, before snapping
var _hovered := false


func _init() -> void:
	custom_minimum_size = SIZE
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_VSIZE


## Sets the value without signalling.
func set_quietly(v: float) -> void:
	set_block_signals(true)
	value = v
	set_block_signals(false)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed:
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				_dragged = value
				if mb.double_click:
					value = reset_value
			MOUSE_BUTTON_WHEEL_UP:
				value += _notch()
			MOUSE_BUTTON_WHEEL_DOWN:
				value -= _notch()
		accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm and mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_dragged = clampf(_dragged - mm.relative.y / DRAG_PIXELS * (max_value - min_value), min_value, max_value)
		value = _dragged
		accept_event()


func _notch() -> float:
	return wheel_step if wheel_step > 0.0 else step


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER or what == NOTIFICATION_MOUSE_EXIT:
		_hovered = what == NOTIFICATION_MOUSE_ENTER
		queue_redraw()


func _draw() -> void:
	var c := Vector2(size.x / 2.0, RADIUS + 2.0)
	var share := (value - min_value) / maxf(max_value - min_value, 0.001)
	var end := START + SWEEP * share
	draw_arc(c, RADIUS, START, START + SWEEP, 32, Color(1, 1, 1, 0.14), 3.0, true)
	if share > 0.0:
		draw_arc(c, RADIUS, START, end, 32, Color(color, 1.0 if _hovered else 0.85), 3.0, true)
	draw_circle(c, RADIUS - 5.0, Color(1, 1, 1, 0.1 if _hovered else 0.06))
	var tick := Vector2.from_angle(end)
	draw_line(c + tick * 3.0, c + tick * (RADIUS - 5.0), Palette.TEXT, 2.0, true)
	var font := get_theme_default_font()
	draw_string(font, Vector2(0, size.y - 2.0), fmt.call(value), HORIZONTAL_ALIGNMENT_CENTER, size.x, 10, Palette.TEXT_DIM)
