class_name LayoutPanel
extends VBoxContainer
## Saves and loads whole layouts: a name field, then the saved list. A used name asks to overwrite.

var surface: WaveSurface
var name_field: LineEdit
var status: Label
var overwrite_row: HBoxContainer
var tree: FileTree
var _pending := ""                 # the name waiting for an answer about overwriting


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var row := HBoxContainer.new()
	add_child(row)
	name_field = LineEdit.new()
	name_field.placeholder_text = "folder/name"
	name_field.max_length = NamedFiles.NAME_MAX
	name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_field.tooltip_text = "A name for this layout. A slash puts it in a folder."
	name_field.text_changed.connect(_name_typed)
	name_field.text_submitted.connect(func(_t: String) -> void: save_pressed())
	row.add_child(name_field)
	row.add_child(PanelBuilder.button("Save", save_pressed, "Saves the notes, tempo, sound settings, ports and view."))
	status = PanelBuilder.hint("")
	status.add_theme_color_override("font_color", Palette.YELLOW)
	status.hide()
	add_child(status)
	overwrite_row = HBoxContainer.new()
	overwrite_row.hide()
	add_child(overwrite_row)
	overwrite_row.add_child(PanelBuilder.button("Overwrite", _overwrite, "Replaces the saved layout. This can't be undone."))
	overwrite_row.add_child(PanelBuilder.button("Keep", _cancel_overwrite, "Keeps the saved layout, and saves nothing."))
	add_child(PanelBuilder.button("Open Layouts Folder", func() -> void: OS.shell_open(NamedFiles.folder(Layouts.DIR)),
			"Shows the layout files in your file manager."))
	tree = FileTree.new()
	tree.make_row = _make_row
	add_child(tree)
	refresh()


func refresh() -> void:
	tree.show_names(Layouts.list())


func _make_row(layout: String) -> Control:
	var row := LayoutRow.new(layout)
	row.load_confirmed.connect(load_layout)
	row.delete_confirmed.connect(delete)
	return row


func _name_typed(text: String) -> void:
	_show("")
	var clean := NamedFiles.cleaned(text)
	if clean != text:
		var caret := name_field.caret_column - (text.length() - clean.length())
		name_field.text = clean
		name_field.caret_column = caret


func _show(message: String) -> void:
	status.text = message
	status.visible = message != ""
	overwrite_row.hide()
	_pending = ""


func save_pressed() -> void:
	var layout := NamedFiles.normalised(name_field.text)
	var problem := NamedFiles.problem(layout)
	if problem != "":
		_show(problem)
		return
	var used := Layouts.existing(layout)
	if used == "":
		_write(layout)
		return
	_show("%s already exists." % used)
	_pending = used
	overwrite_row.show()


func _overwrite() -> void:
	_write(_pending)


func _cancel_overwrite() -> void:
	_show("")


func _write(layout: String) -> void:
	if not Layouts.save(layout, surface):
		_show("Couldn't save the file.")
		return
	_show("")
	name_field.text = layout
	tree.reveal(layout)
	refresh()
	surface.tools.notice.emit("Saved %s" % layout)


func load_layout(layout: String) -> void:
	var data := Layouts.read(layout)
	if data.is_empty():
		_show("Couldn't read that file.")
		return
	_show("")
	Layouts.apply(data, surface)
	name_field.text = layout           # ready to save over
	surface.tools.notice.emit("Loaded %s" % layout)


func delete(layout: String) -> void:
	Layouts.remove(layout)
	_show("")
	refresh()
	surface.tools.notice.emit("Deleted %s" % layout)
