class_name Layouts
extends RefCounted
## Saved layouts, one JSON file each in user://layouts, named as for all NamedFiles. A layout holds
## the notes, and the tempo, sound settings, ports and view they were left with.

const DIR := "user://layouts/"
const VERSION := 1


static func list() -> PackedStringArray:
	return NamedFiles.list(DIR)


## The file a name would use, or "" if it's new.
static func existing(layout: String) -> String:
	return NamedFiles.existing(DIR, layout)


static func remove(layout: String) -> void:
	NamedFiles.remove(DIR, layout)


## Writes what's on `surface` now, replacing any file of that name. Returns false if it can't.
static func save(layout: String, surface: WaveSurface) -> bool:
	DirAccess.make_dir_recursive_absolute(NamedFiles.path(DIR, layout).get_base_dir())
	var file := FileAccess.open(NamedFiles.path(DIR, layout), FileAccess.WRITE)
	if file == null:
		return false
	surface.save_notes()
	file.store_string(JSON.stringify({
		"version": VERSION,
		"notes": Settings.notes,
		"bpm": Settings.bpm,
		"divisions": Settings.divisions,
		"note_beats": Settings.note_beats,
		"channel_volumes": Settings.channel_volumes,
		"channel_beats": Settings.channel_beats,
		"ports": Settings.midi_slots,
		"beat_spacing": Settings.beat_spacing,
		"view_x": surface.view_offset.x,
		"view_y": surface.view_offset.y,
	}, "\t"))
	return true


## A saved layout, or an empty dictionary if it's missing or unreadable.
static func read(layout: String) -> Dictionary:
	var file := FileAccess.open(NamedFiles.path(DIR, layout), FileAccess.READ)
	if file == null:
		return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	return data if data is Dictionary and data.get("notes") is Array else {}


## Replaces the surface and settings with `data`. Anything it's missing stays as it is.
static func apply(data: Dictionary, surface: WaveSurface) -> void:
	Midi.panic()
	surface.replace_layout(data["notes"])
	if data.has("bpm"):
		Settings.set_value("bpm", clampf(float(data["bpm"]), 40.0, 240.0))
	if int(data.get("divisions", 0)) in Settings.DIVISION_OPTIONS:
		Settings.set_value("divisions", int(data["divisions"]))
	if data.has("note_beats"):
		Settings.set_value("note_beats", Settings.snap_length(float(data["note_beats"])))
	for key in ["channel_volumes", "channel_beats"]:
		if data.get(key) is Array and data[key].size() == 16:
			Settings.set(key, data[key].map(func(v: Variant) -> float: return float(v)))
			Settings.changed.emit(key)
	if data.get("ports") is Array and data["ports"].size() == 16:
		Settings.midi_slots = data["ports"].map(func(p: Variant) -> String: return str(p))
		Settings.changed.emit("midi_slots")
	Midi.apply_slots()
	if data.has("beat_spacing"):
		Settings.set_value("beat_spacing", clampf(float(data["beat_spacing"]), Settings.BEAT_SPACING_MIN, Settings.BEAT_SPACING_MAX))
	if data.has("view_x") and data.has("view_y"):
		surface.view_offset = Vector2(float(data["view_x"]), float(data["view_y"]))
		Settings.view_offset = surface.view_offset
	Settings.queue_save()
