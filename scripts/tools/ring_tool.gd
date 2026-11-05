class_name RingTool
extends Tool
## Edits an object through the radial menu. Those on the toolbar are options, not tools: see
## ToolManager.ring_option. A subclass fills the rings in build() and
## applies picks; edits on a selected object apply to the whole selection.

var radial: RadialMenu
var note_id := -1


func section() -> int:
	return 2


func open(menu: RadialMenu, id: int, at: Vector2, hold: bool = false) -> void:
	radial = menu
	menu.dial = false
	note_id = id
	_prepare(at)
	build()
	radial.open(at, hold)


## Before the first build().
func _prepare(_at: Vector2) -> void:
	pass


## Fills the radial menu's rings for the current state.
func build() -> void:
	pass


## True if it's also a tool, picked like one as well as being the ring option.
func acts_as_tool() -> bool:
	return false


## The ring's dial turned, 0-1.
func pick_dial(_value: float) -> void:
	pass


func ring_closed() -> void:
	pass


func pick_outer(_id: Variant) -> void:
	pass


func pick_inner(_id: Variant) -> void:
	pass


func pick_center(_id: Variant) -> void:
	pass


func hovered(_ring: String, _id: Variant) -> void:
	pass
