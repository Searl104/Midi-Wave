class_name RadialMenu
extends Control
## Ring-shaped picker. It draws the rings and reports what is under a point. Left clicks pick and
## keep it open, and any click off the rings closes it.
##
## Quick pick: opened with `hold` on a right-button press, it follows the pointer while the button
## stays down. Releasing over any item picks it and closes; releasing off the rings cancels. A
## release without moving leaves it open for clicking only if something is highlighted (the centre
## button, which sits under the pointer as the ring opens); with nothing highlighted it closes.
##
## Dial mode replaces the rings with one large knob, for fine control over a single value. Moving
## around it sets the value, by dragging or during a hold, and releasing a hold keeps it.
##
## Items: {id: Variant, label: String, color: Color, selected: bool}

signal outer_chosen(id: Variant)
signal inner_chosen(id: Variant)
signal center_chosen(id: Variant)
signal closed
signal dial_changed(value: float)   ## 0-1
signal hover_changed(ring: String, id: Variant)   ## pointer moved onto an item while open

const CENTER_R := 30.0
const INNER_R0 := 36.0
const INNER_R1 := 72.0
const OUTER_R0 := 78.0
const OUTER_R1 := 148.0
const SOLO_R0 := 44.0
const MOVE_SLOP := 6.0             ## px the pointer must move for a release to pick
const DIAL_START := 0.75 * PI      ## the dial runs clockwise from lower left to lower right
const DIAL_SWEEP := 1.5 * PI

var title := ""
var subtitle := ""
var outer_items: Array = []
var inner_items: Array = []
var center_item: Dictionary = {}
var holding := false               ## the opening right-button press is still down
var dial := false                  ## shows a dial instead of rings
var dial_value := 0.0              ## 0-1
var dial_text := ""
var dial_color := Palette.BLUE


var _center := Vector2.ZERO
var _press_pos := Vector2.ZERO
var _moved := false
var _hover_ring := ""       # "outer", "inner", "center" or ""
var _hover_index := -1
var _open_t := 0.0
var _dial_held := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	hide()


func open(at: Vector2, hold: bool = false) -> void:
	holding = hold
	_press_pos = at
	_moved = false
	var m := OUTER_R1 + 12.0
	var top := OUTER_R1 + 34.0   # room for the title
	_center = Vector2(clampf(at.x, m, maxf(m, size.x - m)), clampf(at.y, top, maxf(top, size.y - m)))
	_open_t = 0.0
	_set_hover(_ring_at(at))
	show()
	var tw := create_tween()
	tw.tween_property(self, "_open_t", 1.0, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.finished.connect(queue_redraw)
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


## Turns the dial to the pointer. The centre does nothing, and the gap at the bottom counts as the
## nearer end, so it can't jump across.
func _turn_dial(pos: Vector2) -> void:
	if pos.distance_to(_center) < CENTER_R:
		return
	var a := fposmod((pos - _center).angle() - DIAL_START, TAU)
	if a > DIAL_SWEEP:
		a = DIAL_SWEEP if a - DIAL_SWEEP < (TAU - DIAL_SWEEP) / 2.0 else 0.0
	dial_changed.emit(a / DIAL_SWEEP)


## Moves the highlight to whatever is at `pos`.
func hover_at(pos: Vector2) -> void:
	_set_hover(_ring_at(pos))


func _set_hover(r: Array) -> void:
	if r[0] != _hover_ring or r[1] != _hover_index:
		_hover_ring = r[0]
		_hover_index = r[1]
		queue_redraw()
		if visible and _hover_ring != "":
			var items: Array = outer_items if _hover_ring == "outer" else (inner_items if _hover_ring == "inner" else [center_item])
			if _hover_index >= 0 and _hover_index < items.size():
				hover_changed.emit(_hover_ring, items[_hover_index].get("id"))


## Activates whatever is at `pos`. Returns false if nothing was there. With `keep_open` the menu
## stays open so several items can be picked; the caller refreshes the items.
func activate(pos: Vector2, keep_open: bool = false) -> bool:
	var r := _ring_at(pos)
	match r[0]:
		"outer":
			var id: Variant = outer_items[r[1]].id
			if not keep_open:
				close()
			outer_chosen.emit(id)
		"inner":
			inner_chosen.emit(inner_items[r[1]].id)
		"center":
			var cid: Variant = center_item.id
			if not keep_open:
				close()
			center_chosen.emit(cid)
		_:
			return false
	return true


## While held, the press belongs to the control under it, so motion and the release go there.
## Watch them here. They aren't consumed: that control must also see its release.
func _input(event: InputEvent) -> void:
	if not visible or not holding:
		return
	var mm := event as InputEventMouseMotion
	if mm:
		_moved = _moved or mm.position.distance_to(_press_pos) > MOVE_SLOP
		if dial and _moved:
			_turn_dial(mm.position)
		elif not dial:
			hover_at(mm.position)
		return
	var mb := event as InputEventMouseButton
	if mb == null:
		return
	if mb.button_index == MOUSE_BUTTON_RIGHT and not mb.pressed:
		holding = false
		if _moved:
			if not dial:
				activate(mb.position)
			close()
		elif not dial and _hover_ring == "":
			close()                    # released before anything was highlighted
	elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		get_viewport().set_input_as_handled()
		if dial:
			_turn_dial(mb.position)
		elif not activate(mb.position, true):
			close()


func _gui_input(event: InputEvent) -> void:
	accept_event()
	if dial:
		_dial_input(event)
		return
	var mm := event as InputEventMouseMotion
	if mm:
		hover_at(mm.position)
		return
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and not activate(mb.position, true):
		close()


func _dial_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm and _dial_held:
		_turn_dial(mm.position)
		return
	var mb := event as InputEventMouseButton
	if mb == null:
		return
	if not mb.pressed:
		_dial_held = false
	elif mb.button_index == MOUSE_BUTTON_LEFT and mb.position.distance_to(_center) <= OUTER_R1 + 6.0:
		_dial_held = true
		_turn_dial(mb.position)
	else:
		close()


# --- Drawing -------------------------------------------------------------------------------

func _draw() -> void:
	var k := ease(_open_t, 0.5)
	var font := get_theme_default_font()
	draw_circle(_center, OUTER_R1 * k + 10.0, Color(0, 0, 0, 0.25 * k))   # soft shadow

	if dial:
		_draw_dial(k, font)
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


func _draw_dial(k: float, font: Font) -> void:
	var r := (OUTER_R1 - 22.0) * k
	draw_circle(_center, OUTER_R1 * k, Color(Palette.GLASS, 0.94))
	draw_arc(_center, r, DIAL_START, DIAL_START + DIAL_SWEEP, 80, Color(1, 1, 1, 0.14), 20.0, true)
	var end := DIAL_START + DIAL_SWEEP * dial_value
	draw_arc(_center, r, DIAL_START, end, 80, dial_color, 20.0, true)
	var tick := Vector2.from_angle(end)
	draw_line(_center + tick * (r - 16.0), _center + tick * (r + 13.0), Palette.TEXT, 3.0, true)
	draw_string(font, _center + Vector2(-OUTER_R1, 11), dial_text, HORIZONTAL_ALIGNMENT_CENTER, OUTER_R1 * 2.0, 32, Palette.TEXT)


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
