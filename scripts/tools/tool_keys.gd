class_name ToolKeys
extends RefCounted
## Keyboard keys that pick tools, set in Options > Controls. Saved in Settings.tool_keys as
## tool id -> key name ("T"), or "" for no key. A key picks one tool, and only with no Shift,
## Ctrl, Alt or Meta held, so Ctrl+C, Ctrl+V and Ctrl+Z keep their own jobs.

const ORDER := ["tap", "select", "draw", "bind", "grid", "velocity", "collection", "pan", "zoom"]
const DEFAULTS := {
	"tap": "T", "select": "S", "draw": "D", "bind": "B", "grid": "G", "velocity": "V",
	"collection": "C", "pan": "H", "zoom": "Z",
}
## Keys the app already uses, which a tool can't take, with what they do.
const RESERVED := {
	KEY_SPACE: "Stop", KEY_KP_ENTER: "Stop", KEY_TAB: "Tap and back", KEY_ESCAPE: "closing rings and panels",
	KEY_M: "Mute", KEY_COMMA: "Nudge", KEY_PERIOD: "Nudge", KEY_LESS: "Nudge", KEY_GREATER: "Nudge",
	KEY_DELETE: "Delete", KEY_BACKSPACE: "Delete",
}
const MODIFIER_KEYS := [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK, KEY_NUMLOCK]


## The key a press is, as a keycode: the labelled key, else the physical one.
static func keycode_of(key: InputEventKey) -> Key:
	return key.keycode if key.keycode != KEY_NONE else key.physical_keycode


static func has_modifier(key: InputEventKey) -> bool:
	return key.shift_pressed or key.ctrl_pressed or key.alt_pressed or key.meta_pressed


## A Shift, Ctrl, Alt, Meta, Caps Lock or Num Lock press on its own: Learn keeps waiting.
static func is_modifier_only(key: InputEventKey) -> bool:
	return MODIFIER_KEYS.has(keycode_of(key))


static func _is_keypad_digit(key: InputEventKey) -> bool:
	var pad: int = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	return pad >= KEY_KP_0 and pad <= KEY_KP_9


## The tool a key press picks, or "".
static func tool_for(key: InputEventKey) -> String:
	if has_modifier(key) or _is_keypad_digit(key):
		return ""
	var code := keycode_of(key)
	if code == KEY_NONE:
		return ""
	for id in ORDER:
		var name := key_for(id)
		if name != "" and OS.find_keycode_from_string(name) == code:
			return id
	return ""


static func key_for(id: String) -> String:
	return str(Settings.tool_keys.get(id, ""))


## Why a key press can't be learned, or "" if it can.
static func refusal(key: InputEventKey) -> String:
	if has_modifier(key):
		return "Use a key on its own, without Shift, Ctrl, Alt or Meta."
	if _is_keypad_digit(key):
		return "The keypad digits fire bindings."
	var code := keycode_of(key)
	if RESERVED.has(code):
		return "%s is already used for %s." % [OS.get_keycode_string(code), RESERVED[code]]
	return ""


## Gives `code` to tool `id`, taking it from any other tool.
static func assign(id: String, code: Key) -> void:
	var name := OS.get_keycode_string(code)
	var keys: Dictionary = Settings.tool_keys.duplicate()
	for other in keys:
		if keys[other] == name:
			keys[other] = ""
	keys[id] = name
	Settings.set_value("tool_keys", keys)


static func clear(id: String) -> void:
	var keys: Dictionary = Settings.tool_keys.duplicate()
	keys[id] = ""
	Settings.set_value("tool_keys", keys)


static func reset() -> void:
	Settings.set_value("tool_keys", DEFAULTS.duplicate())


## What a tool's key is called on screen.
static func label(id: String) -> String:
	var name := key_for(id)
	return "None" if name == "" else name
