class_name Collections
extends RefCounted
## Saved groups of notes, one JSON file each in user://collections. A collection's name is its path
## there, as for all NamedFiles. Positions are relative to the group's centre, so a collection can go anywhere.

const DIR := "user://collections/"
const VERSION := 1
static func _path(collection: String) -> String:
	return DIR + collection + ".json"


## The collections folder as a path on this computer, made if needed.
static func folder() -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	return ProjectSettings.globalize_path(DIR)


## The saved names, sorted, with their folders.
static func list() -> PackedStringArray:
	return NamedFiles.list(DIR)


static func exists(collection: String) -> bool:
	return NamedFiles.existing(DIR, collection) != ""


## Writes `notes` as a new collection, making its folders. Returns false if it can't be written.
static func save(collection: String, notes: Array) -> bool:
	DirAccess.make_dir_recursive_absolute(_path(collection).get_base_dir())
	var file := FileAccess.open(_path(collection), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": VERSION, "items": pack(notes)}, "\t"))
	return true


## The items of a collection, or an empty array if it's missing or unreadable.
static func read(collection: String) -> Array:
	var file := FileAccess.open(_path(collection), FileAccess.READ)
	if file == null:
		return []
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary or not data.get("items") is Array:
		return []
	return data["items"].filter(func(d: Variant) -> bool:
		return d is Dictionary and d.has("x") and d.has("y") and d.has("note") and d.has("channel"))


## Deletes a collection, and any folders that leaves empty.
static func remove(collection: String) -> void:
	NamedFiles.remove(DIR, collection)


## Saved-format entries around the notes' centre.
static func pack(notes: Array) -> Array:
	var centre := Vector2.ZERO
	for o in notes:
		centre += o.pos
	centre /= maxi(notes.size(), 1)
	var items: Array = []
	for o in notes:
		var d: Dictionary = o.to_dict()
		_shift(d, -centre)
		items.append(d)
	return items


## Moves a saved entry and its remote emitter.
static func _shift(d: Dictionary, by: Vector2) -> void:
	d["x"] = float(d["x"]) + by.x
	d["y"] = float(d["y"]) + by.y
	for m in d.get("mods", []):
		if m.has("ex"):
			m["ex"] = float(m["ex"]) + by.x
			m["ey"] = float(m["ey"]) + by.y


## A copy of `items` around `centre`, ready for Note.load_dict.
static func placed(items: Array, centre: Vector2) -> Array:
	var out: Array = items.duplicate(true)
	for d in out:
		_shift(d, centre)
	return out
