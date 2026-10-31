class_name RadialMenu
extends Control
## Ring-shaped picker (marking menu). Outer ring choices close the menu; inner ring
## choices (e.g. octaves) and the mouse wheel just emit so the caller can rebuild.
##
## Two ways to use it:
## - Click mode: it stays open; click an item.
## - Hold mode (quick place): opened on a right-button press; hover an item and release.
##   Releasing without moving drops into click mode. Releasing in the dead zone cancels.
## While open: A / D emit `wheel(-1 / +1)`, number keys emit `digit(n)`, Esc closes.
##
## Items: {id: Variant, label: String, color: Color, selected: bool}

signal outer_chosen(id: Variant)
signal inner_chosen(id: Variant)
signal center_chosen(id: Variant)
signal wheel(direction: int)
signal digit(value: int)
signal closed

const CENTER_R := 30.0
const INNER_R0 := 36.0
const INNER_R1 := 72.0
const OUTER_R0 := 78.0
const OUTER_R1 := 148.0
const SOLO_R0 := 44.0
const TAP_SLOP := 6.0

var title := ""
var subtitle := ""
var outer_items: Array = []
var inner_items: Array = []
var center_item: Dictionary = {}

var holding := false        ## true while the opening right-button press is still held

var _center := Vector2.ZERO
var _press_pos := Vector2.ZERO
var _moved := false
var _hover_ring := ""       # "outer", "inner", "center" or ""
var _hover_index := -1
var _open_t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	hide()


func open(at: Vector2, hold: bool = false) -> void:
	var m := OUTER_R1 + 12.0
	var top := OUTER_R1 + 34.0   # room for the title
	_center = Vector2(clampf(at.x, m, maxf(m, size.x - m)), clampf(at.y, top, maxf(top, size.y - m)))
	_press_pos = at
	_moved = false
	holding = hold
	_open_t = 0.0
	_set_hover(_ring_at(at))
	show()
	var tw := create_tween()
	tw.tween_property(self, "_open_t", 1.0, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	queue_redraw()


func close() -> void:
	holding = false
	if visible:
		hide()
		closed.emit()


func refresh() -> void:
	queue_redraw()


func _process(_d: float) -> void:
	if visible and _open_t < 1.0:
		queue_redraw()


# --- Hit testing -----------------------------------------------------------------------

func _outer_r0() -> float:
	return OUTER_R0 if not inner_items.is_empty() else SOLO_R0


func _ring_at(pos: Vector2) -> Array:
	var d := pos.distance_to(_center)
	if not center_item.is_empty() and d <= CENTER_R:
		return ["center", 0]
	if not inner_items.is_empty() and d >= INNER_R0 and d <= INNER_R1:
		return ["inner", _segment(pos, inner_items.size())]
	if not outer_items.is_empty() and d >= _outer_r0() and d <= OUTER_R1 + 6.0:
		return ["outer", _segment(pos, outer_items.size())]
	return ["", -1]


func _segment(pos: Vector2, count: int) -> int:
	var seg := TAU / count
	var a := (pos - _center).angle() + PI / 2.0 + seg / 2.0   # item 0 centred at the top
	return int(fposmod(a, TAU) / seg) % count


func _set_hover(r: Array) -> void:
	if r[0] != _hover_ring or r[1] != _hover_index:
		_hover_ring = r[0]
		_hover_index = r[1]
		queue_redraw()


## Activates whatever is at `pos`. Returns false if nothing was there.
func _activate(pos: Vector2) -> bool:
	var r := _ring_at(pos)
	match r[0]:
		"outer":
			var id: Variant = outer_items[r[1]].id
			close()
			outer_chosen.emit(id)
		"inner":
			inner_chosen.emit(inner_items[r[1]].id)
		"center":
			var cid: Variant = center_item.id
			close()
			center_chosen.emit(cid)
		_:
			return false
	return true


# --- Input -------------------------------------------------------------------------------

## Hold mode: the press started on another control, so motion and the release are
## routed there. Watch them here first. They are deliberately not consumed: the
## control that took the press must also see its release, or the GUI keeps sending
## it the mouse afterwards.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		if _handle_key(key):
			get_viewport().set_input_as_handled()
		return
	if not holding:
		return
	var mm := event as InputEventMouseMotion
	if mm:
		if mm.position.distance_to(_press_pos) > TAP_SLOP:
			_moved = true
		_set_hover(_ring_at(mm.position))
		return
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_RIGHT and not mb.pressed:
		holding = false
		if not _moved:
			return                      # a tap: stay open in click mode
		var r := _ring_at(mb.position)
		if r[0] == "inner":
			_activate(mb.position)      # change octave, stay open in click mode
		elif not _activate(mb.position):
			close()                     # released in the dead zone: cancel


func _handle_key(key: InputEventKey) -> bool:
	match key.keycode:
		KEY_ESCAPE:
			close()
			return true
		KEY_A, KEY_LEFT:
			wheel.emit(-1)
			return true
		KEY_D, KEY_RIGHT:
			wheel.emit(1)
			return true
	if key.keycode >= KEY_0 and key.keycode <= KEY_9:
		digit.emit(key.keycode - KEY_0)
		return true
	if key.keycode >= KEY_KP_0 and key.keycode <= KEY_KP_9:
		digit.emit(key.keycode - KEY_KP_0)
		return true
	return false


func _gui_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm:
		_set_hover(_ring_at(mm.position))
		accept_event()
		return
	var mb := event as InputEventMouseButton
	if mb and mb.pressed:
		accept_event()
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			wheel.emit(1)
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			wheel.emit(-1)
			return
		if not _activate(mb.position):
			close()


# --- Drawing -------------------------------------------------------------------------------

func _draw() -> void:
	var k := ease(_open_t, 0.5)
	var font := get_theme_default_font()
	draw_circle(_center, OUTER_R1 * k + 10.0, Color(0, 0, 0, 0.25 * k))   # soft shadow

	_draw_ring(outer_items, _outer_r0() * k, OUTER_R1 * k, "outer", 15, font)
	if not inner_items.is_empty():
		_draw_ring(inner_items, INNER_R0 * k, INNER_R1 * k, "inner", 12, font)

	if not center_item.is_empty():
		var hov := _hover_ring == "center"
		var c: Color = center_item.get("color", Palette.RED)
		draw_circle(_center, CENTER_R * k, Palette.GLASS.lerp(c, 0.45 if hov else 0.15))
		draw_arc(_center, CENTER_R * k, 0.0, TAU, 40, Color(c, 0.8), 1.5, true)
		draw_string(font, _center + Vector2(-CENTER_R, 5), center_item.label,
				HORIZONTAL_ALIGNMENT_CENTER, CENTER_R * 2.0, 12, Palette.TEXT)

	if title != "":
		draw_string(font, _center + Vector2(-OUTER_R1 - 40.0, -OUTER_R1 * k - 12.0), title,
				HORIZONTAL_ALIGNMENT_CENTER, OUTER_R1 * 2.0 + 80.0, 13, Palette.TEXT_DIM)
	if subtitle != "":
		draw_string(font, _center + Vector2(-OUTER_R1 - 40.0, OUTER_R1 * k + 24.0), subtitle,
				HORIZONTAL_ALIGNMENT_CENTER, OUTER_R1 * 2.0 + 80.0, 12, Palette.TEXT_DIM)


func _draw_ring(items: Array, r0: float, r1: float, ring: String, font_size: int, font: Font) -> void:
	var count := items.size()
	if count == 0:
		return
	var seg := TAU / count
	var gap := 0.025 if count > 1 else 0.0
	for i in count:
		var item: Dictionary = items[i]
		var a0 := -PI / 2.0 - seg / 2.0 + seg * i + gap
		var a1 := a0 + seg - gap * 2.0
		var col: Color = item.get("color", Palette.ACCENT)
		var hovered := _hover_ring == ring and _hover_index == i
		var fill := Palette.GLASS
		if item.get("selected", false):
			fill = fill.lerp(col, 0.32)
		if hovered:
			fill = fill.lerp(col, 0.55)
		draw_colored_polygon(_sector(r0, r1, a0, a1), Color(fill, 0.94))
		draw_arc(_center, r1, a0, a1, 12, Color(col, 0.9 if hovered else 0.5), 2.0, true)
		draw_arc(_center, r0, a0, a1, 12, Palette.LINE, 1.0, true)
		var mid := _center + Vector2.from_angle((a0 + a1) * 0.5) * (r0 + r1) * 0.5
		draw_string(font, mid + Vector2(-30, font_size * 0.35), item.label,
				HORIZONTAL_ALIGNMENT_CENTER, 60, font_size, Palette.TEXT if not hovered else Color.WHITE)


func _sector(r0: float, r1: float, a0: float, a1: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := maxi(4, int((a1 - a0) * 16.0))
	for s in steps + 1:
		pts.append(_center + Vector2.from_angle(lerpf(a0, a1, float(s) / steps)) * r1)
	for s in range(steps, -1, -1):
		pts.append(_center + Vector2.from_angle(lerpf(a0, a1, float(s) / steps)) * r0)
	return pts
