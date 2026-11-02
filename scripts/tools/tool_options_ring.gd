class_name ToolOptionsRing
extends RingTool
## A toolbar item's options: right-click the item to open this, filled from the tool's options().


var target: Tool = null


func tool_id() -> String:
	return "tool_options"


func title() -> String:
	return "Tool options"


func build() -> void:
	radial.outer_items = target.options()
	radial.inner_items = []
	radial.center_item = {}
	radial.title = target.title()
	radial.subtitle = ""
	radial.refresh()


func pick_outer(id: Variant) -> void:
	target.option_chosen(id)
	build()
