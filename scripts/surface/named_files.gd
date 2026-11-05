class_name NamedFiles
extends RefCounted
## JSON files saved under a name the user types. The name is the path without the extension, so
## "patterns/shaker01" is shaker01.json in a patterns folder. Names follow the Windows rules, so
## files can move between systems.

const NAME_MAX := 100
const FORBIDDEN := ":*?\"<>|"
const RESERVED := ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7",
		"COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]


static func path(dir: String, file_name: String) -> String:
	return dir + file_name + ".json"


## `dir` as a path on this computer, made if needed.
static func folder(dir: String) -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	return ProjectSettings.globalize_path(dir)


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
	var joined := "/".join(parts)
	return joined + "/" if joined != "" and cleaned(text).strip_edges().ends_with("/") else joined


## What's wrong with a normalised name, or "".
static func problem(file_name: String) -> String:
	if file_name == "":
		return "Give it a name first."
	if file_name.ends_with("/"):
		return "Add a name after the folder."
	if file_name.length() > NAME_MAX:
		return "That name is too long."
	for part in file_name.split("/"):
		if part.ends_with("."):
			return "A name or folder can't end in a dot."
		if part.get_slice(".", 0).to_upper() in RESERVED:
			return "Windows reserves the name %s." % part.get_slice(".", 0)
	return ""


## The saved names, sorted, with their folders.
static func list(dir: String) -> PackedStringArray:
	var names: Array = []
	_collect(dir, "", names)
	names.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	return PackedStringArray(names)


static func _collect(dir: String, sub: String, names: Array) -> void:
	if not DirAccess.dir_exists_absolute(dir + sub):
		return
	for file in DirAccess.get_files_at(dir + sub):
		if file.ends_with(".json"):
			names.append(sub + file.trim_suffix(".json"))
	for inner in DirAccess.get_directories_at(dir + sub):
		_collect(dir, sub + inner + "/", names)


## The saved name matching `file_name`, ignoring case as Windows does, or "".
static func existing(dir: String, file_name: String) -> String:
	var lower := file_name.to_lower()
	for n in list(dir):
		if n.to_lower() == lower:
			return n
	return ""


## Deletes a file, and any folders that leaves empty.
static func remove(dir: String, file_name: String) -> void:
	DirAccess.remove_absolute(path(dir, file_name))
	var sub := file_name.get_base_dir()
	while sub != "":
		var there := dir + sub
		if not DirAccess.get_files_at(there).is_empty() or not DirAccess.get_directories_at(there).is_empty():
			return
		DirAccess.remove_absolute(there)
		sub = sub.get_base_dir()
