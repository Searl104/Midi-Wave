class_name RingTool
extends Tool
## A tool that edits an object through the radial menu. A subclass fills the rings in build() and
## applies picks; edits on a selected object apply to the whole selection.

var radial: RadialMenu
var note_id := -1


func open(menu: RadialMenu, id: int, at: Vector2) -> void:
	radial = menu
	note_id = id
	_prepare(at)
	build()
	radial.open(at)


## Before the first build().
func _prepare(_at: Vector2) -> void:
	pass


## Fills the radial menu's rings for the current state.
func build() -> void:
	pass


func pick_outer(_id: Variant) -> void:
	pass


func pick_inner(_id: Variant) -> void:
	pass


func pick_center(_id: Variant) -> void:
	pass


func hovered(_ring: String, _id: Variant) -> void:
	pass
