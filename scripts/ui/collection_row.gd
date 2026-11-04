class_name CollectionRow
extends HBoxContainer
## A collection in Paste Collection's panel: click its name to pick it, drag it onto the surface, or
## delete it, which asks first.

signal picked(collection: String)
signal delete_confirmed(collection: String)


## The name, which can also be dragged.
class Handle:
	extends Button
	var collection := ""

	func _get_drag_data(_at: Vector2) -> Variant:
		var preview := Label.new()
		preview.text = collection
		set_drag_preview(preview)
		return {"collection": collection}


var collection := ""
var handle: Handle
var delete_button: Button
var confirm_button: Button
var cancel_button: Button


func _init(collection_name: String, chosen: bool) -> void:
	collection = collection_name
	handle = Handle.new()
	handle.collection = collection
	handle.text = collection.get_file()
	handle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	handle.clip_text = true
	handle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	handle.focus_mode = Control.FOCUS_NONE
	handle.tooltip_text = "Click to stamp it on the surface, or drag it there."
	handle.toggle_mode = true
	handle.button_pressed = chosen
	handle.pressed.connect(func() -> void: picked.emit(collection))
	add_child(handle)
	delete_button = PanelBuilder.button("Delete", _ask, "Deletes this collection, after asking.")
	add_child(delete_button)
	confirm_button = PanelBuilder.button("Confirm", func() -> void: delete_confirmed.emit(collection),
			"Deletes this collection. This can't be undone.")
	add_child(confirm_button)
	cancel_button = PanelBuilder.button("Keep", _answer, "Keeps this collection.")
	add_child(cancel_button)
	_answer()


func _ask() -> void:
	delete_button.hide()
	confirm_button.show()
	cancel_button.show()


func _answer() -> void:
	delete_button.show()
	confirm_button.hide()
	cancel_button.hide()
