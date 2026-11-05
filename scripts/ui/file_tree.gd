class_name FileTree
extends VBoxContainer
## A list of NamedFiles names with collapsible folders. `make_row` makes the row for a name.

var make_row: Callable
var open := {}                     ## folders showing their contents
var empty_text := "Nothing saved yet."
var _names: Array = []


func _init() -> void:
	add_theme_constant_override("separation", 4)


func show_names(names: PackedStringArray) -> void:
	_names = Array(names)
	_rebuild()


## Opens the folders above a name.
func reveal(file_name: String) -> void:
	var folder := file_name.get_base_dir()
	while folder != "":
		open[folder] = true
		folder = folder.get_base_dir()


func toggle(folder: String) -> void:
	open[folder] = not open.get(folder, false)
	_rebuild()


func _rebuild() -> void:
	for old in get_children():
		remove_child(old)
		old.queue_free()
	if _names.is_empty():
		add_child(PanelBuilder.hint(empty_text))
	_add_level(self, "", _names)


## Adds what's directly in `folder`: its folders, then its files.
func _add_level(box: VBoxContainer, folder: String, names: Array) -> void:
	var inside := {}
	var here: Array = []
	for n in names:
		var rest: String = n.trim_prefix(folder)
		if "/" in rest:
			inside[rest.get_slice("/", 0)] = true
		else:
			here.append(n)
	for sub in inside:
		var path: String = folder + sub + "/"
		var shown: bool = open.get(path.trim_suffix("/"), false)
		var row := FolderRow.new(sub, shown)
		row.pressed.connect(toggle.bind(path.trim_suffix("/")))
		box.add_child(row)
		if shown:
			var indent := MarginContainer.new()
			indent.add_theme_constant_override("margin_left", 14)
			box.add_child(indent)
			var level := VBoxContainer.new()
			level.add_theme_constant_override("separation", 4)
			indent.add_child(level)
			_add_level(level, path, names.filter(func(n: String) -> bool: return n.begins_with(path)))
	for n in here:
		box.add_child(make_row.call(n))
