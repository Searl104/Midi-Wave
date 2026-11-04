class_name Collections
extends RefCounted
## Saved groups of notes, one JSON file each in user://collections. A collection's name is its path
## there, without the extension, so "patterns/shaker01" is shaker01.json in a patterns folder.
## Names follow the Windows rules, so a collection can move between systems. Positions are relative
## to the group's centre, so a collection can go anywhere. Snap memory is kept only within the group.

const DIR := "user://collections/"
const VERSION := 1
const NAME_MAX := 100
const FORBIDDEN := ":*?\"<>|"
const RESERVED := ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7",
		"COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]


static func _path(collection: String) -> String:
	return DIR + collection + ".json"


## The collections folder as a path on this computer, made if needed.
static func folder() -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	return ProjectSettings.globalize_path(DIR)


## `text` with what can't be typed in a name taken out, and backslashes as folder separators.
static func cleaned(text: String) -> String:
	var out := ""
	for ch in text.replace("\\", "/"):
		if ch not in FORBIDDEN and ch.unicode_at(0) >= 32:
			out += ch
	return out


## `text` as a name: spaces at the ends of each part go, and so do repeated slashes. A trailing
## slash stays, since it means the name is unfinished.
static func normalised(text: String) -> String:
	var parts: Array = []
	for part in cleaned(text).split("/", false):
		if part.strip_edges() != "":
			parts.append(part.strip_edges())
	var name := "/".join(parts)
	return name + "/" if name != "" and cleaned(text).strip_edges().ends_with("/") else name


## What's wrong with a normalised name, or "".
static func problem(collection: String) -> String:
	if collection == "":
		return "Give it a name first."
	if collection.ends_with("/"):
		return "Add a name after the folder."
	if collection.length() > NAME_MAX:
		return "That name is too long."
	for part in collection.split("/"):
		if part.ends_with("."):
			return "A name or folder can't end in a dot."
		if part.get_slice(".", 0).to_upper() in RESERVED:
			return "Windows reserves the name %s." % part.get_slice(".", 0)
	return ""


## The saved names, sorted, with their folders.
static func list() -> PackedStringArray:
	var names: Array = []
	_collect("", names)
	names.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	return PackedStringArray(names)


static func _collect(folder: String, names: Array) -> void:
	if not DirAccess.dir_exists_absolute(DIR + folder):
		return
	for file in DirAccess.get_files_at(DIR + folder):
		if file.ends_with(".json"):
			names.append(folder + file.trim_suffix(".json"))
	for sub in DirAccess.get_directories_at(DIR + folder):
		_collect(folder + sub + "/", names)


## Ignores case, since Windows file names do.
static func exists(collection: String) -> bool:
	var lower := collection.to_lower()
	return Array(list()).any(func(n: String) -> bool: return n.to_lower() == lower)


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
	DirAccess.remove_absolute(_path(collection))
	var folder := collection.get_base_dir()
	while folder != "":
		var path := DIR + folder
		if not DirAccess.get_files_at(path).is_empty() or not DirAccess.get_directories_at(path).is_empty():
			return
		DirAccess.remove_absolute(path)
		folder = folder.get_base_dir()


## Saved-format entries around the notes' centre.
static func pack(notes: Array) -> Array:
	var centre := Vector2.ZERO
	var ids := {}
	for o in notes:
		centre += o.pos
		ids[o.id] = true
	centre /= maxi(notes.size(), 1)
	var items: Array = []
	for o in notes:
		var d: Dictionary = o.to_dict()
		_shift(d, -centre)
		d["snap_note"] = _inside(d["snap_note"], ids)
		for m in d["mods"]:
			if m.has("snap_emit"):
				m["snap_emit"] = _inside(m["snap_emit"], ids)
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


static func _inside(key: String, ids: Dictionary) -> String:
	return key if key != "" and ids.has(key.substr(1).to_int()) else ""


## `key` with its object's id swapped for the new one.
static func _renamed(key: String, new_ids: Dictionary) -> String:
	if key == "" or not new_ids.has(key.substr(1).to_int()):
		return ""
	return "%s%d" % [key.left(1), new_ids[key.substr(1).to_int()]]


## A copy of `items` around `centre`, ready for Note.load_dict.
static func placed(items: Array, centre: Vector2) -> Array:
	var out: Array = items.duplicate(true)
	for d in out:
		_shift(d, centre)
	return out


## Fixes snap memory after new ids are given: `new_ids` maps saved ids to new ones.
static func relink(note: Note, new_ids: Dictionary) -> void:
	note.snap_note = _renamed(note.snap_note, new_ids)
	var e: Emitter = note.emitter()
	if e:
		e.snap = _renamed(e.snap, new_ids)
