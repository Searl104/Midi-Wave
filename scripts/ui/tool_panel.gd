class_name ToolPanel
extends PanelContainer
## A tool's options: a popup just right of the toolbar, centred on the tool's slot as far as the
## window allows. Right-click a toolbar item to open it. Clicking the item again, or anywhere
## outside the panel, closes it; a click outside does nothing else, except on the toolbar, which
## handles its own clicks. Controls are built fresh from Settings each time it opens.

const WIDTH := 320.0
const GAP := 8.0
const EDGE := 12.0
const MAX_HEIGHT := 640.0

var tool: Tool = null              ## the tool it's showing
var toolbar: Control

var _scroll: ScrollContainer
var _box: VBoxContainer
var _anchor_y := 0.0


func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/glass.gdshader")
	mat.set_shader_parameter("opacity", 0.86)
	material = mat
	mouse_filter = Control.MOUSE_FILTER_STOP
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	hide()


func is_open_for(t: Tool) -> bool:
	return visible and tool == t


## Opens `t`'s options beside a toolbar slot at height `anchor_y`.
func open(t: Tool, anchor_y: float) -> void:
	tool = t
	_anchor_y = anchor_y
	for old in _scroll.get_children():
		_scroll.remove_child(old)
		old.queue_free()
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_right", 10)
	_box = VBoxContainer.new()
	_box.custom_minimum_size.x = WIDTH - 44.0
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = t.title()
	title.add_theme_font_size_override("font_size", 16)
	_box.add_child(title)
	t.build_options(_box)
	pad.add_child(_box)
	_scroll.add_child(pad)
	show()
	_fit.call_deferred(pad)


## Sizes to the contents, up to the window's height, then scrolls.
func _fit(content: Control) -> void:
	var room := minf(MAX_HEIGHT, get_viewport_rect().size.y - EDGE * 2.0)
	var style := get_theme_stylebox("panel")
	var chrome := style.get_minimum_size().y if style else 0.0
	var high := minf(content.get_combined_minimum_size().y, room - chrome)
	_scroll.custom_minimum_size = Vector2(WIDTH, high)
	reset_size()
	var window := get_viewport_rect().size
	var top := clampf(_anchor_y - size.y / 2.0, EDGE, maxf(EDGE, window.y - size.y - EDGE))
	position = Vector2(toolbar.global_position.x + toolbar.size.x + GAP, top)


func close() -> void:
	hide()
	tool = null


func _a_dropdown_is_open() -> bool:
	for o in find_children("*", "OptionButton", true, false):
		if (o as OptionButton).get_popup().visible:
			return true
	return false


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key and key.pressed and key.keycode == KEY_ESCAPE and not _a_dropdown_is_open():
		close()
		get_viewport().set_input_as_handled()
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or _a_dropdown_is_open():
		return
	if get_global_rect().has_point(mb.position) or toolbar.get_global_rect().has_point(mb.position):
		return
	close()
	get_viewport().set_input_as_handled()
