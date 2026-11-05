class_name LayoutRow
extends HBoxContainer
## A saved layout: Load and Delete each ask first, with Confirm and Keep.

signal load_confirmed(layout: String)
signal delete_confirmed(layout: String)

var layout := ""
var load_button: Button
var delete_button: Button
var confirm_button: Button
var keep_button: Button
var _asking := ""                  # "load" or "delete"


func _init(layout_name: String) -> void:
	layout = layout_name
	var title := Label.new()
	title.text = layout.get_file()
	title.clip_text = true
	title.tooltip_text = layout
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(title)
	load_button = PanelBuilder.button("Load", _ask.bind("load"), "Replaces the surface with this layout, after asking.")
	add_child(load_button)
	delete_button = PanelBuilder.button("Delete", _ask.bind("delete"), "Deletes this layout, after asking.")
	add_child(delete_button)
	confirm_button = PanelBuilder.button("Confirm", _confirm, "Goes ahead. This can't be undone.")
	add_child(confirm_button)
	keep_button = PanelBuilder.button("Keep", _answer, "Changes nothing.")
	add_child(keep_button)
	_answer()


func _ask(action: String) -> void:
	_asking = action
	confirm_button.text = "Clear all and load?" if action == "load" else "Confirm"
	keep_button.text = "Cancel" if action == "load" else "Keep"
	load_button.hide()
	delete_button.hide()
	confirm_button.show()
	keep_button.show()


func _confirm() -> void:
	var action := _asking
	_answer()
	if action == "load":
		load_confirmed.emit(layout)
	else:
		delete_confirmed.emit(layout)


func _answer() -> void:
	_asking = ""
	load_button.show()
	delete_button.show()
	confirm_button.hide()
	keep_button.hide()
