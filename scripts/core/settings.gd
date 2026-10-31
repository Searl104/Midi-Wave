extends Node
## Persistent app settings and note layout, autoloaded as `Settings`.
## Saved to user://settings.cfg (on Windows: %APPDATA%\Godot\app_userdata\MIDI Wave\).

signal changed(key: String)

const PATH := "user://settings.cfg"
const LAYOUT_VERSION := 2       ## 1 = positions normalized to the window, 2 = world pixels
const LEGACY_SIZE := Vector2(1280, 800)   ## window size used to convert version-1 layouts
const DIVISION_OPTIONS := [1, 2, 3, 4, 6, 8]
const KEYS := [
	"wave_strength", "bpm", "beat_spacing", "divisions", "wave_range", "falloff_curve", "note_length",
	"root_note", "scale_name", "midi_port", "notes", "view_offset", "layout_version",
]

var wave_strength := 1.0        ## 0.1-1.0, peak velocity of a fresh wave
var bpm := 120.0                ## tempo; wave speed follows it
var beat_spacing := 210.0       ## px a wave travels in one beat (timing ring spacing)
var divisions := 4              ## faded division rings per beat
var wave_range := 900.0         ## px at which the wave reaches 0
var falloff_curve := 1.6        ## 1 = linear, higher = drops faster near the source
var note_length := 0.35         ## seconds a triggered note is held
var root_note := 0              ## 0-11, C = 0
var scale_name := "Minor Pentatonic"
var midi_port := ""             ## last opened output port, reopened on launch
var notes: Array = []           ## [{x, y, note, channel, mode, ...}] in world px
var view_offset := Vector2.ZERO ## world position of the window's top-left corner
var layout_version := LAYOUT_VERSION

## Wave speed in px/s, locked to tempo. Setting it changes beat spacing at the current BPM.
var wave_speed: float:
	get:
		return beat_spacing * bpm / 60.0
	set(value):
		beat_spacing = value * 60.0 / maxf(bpm, 1.0)

var _save_timer: Timer


func _ready() -> void:
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.4
	_save_timer.timeout.connect(save_now)
	add_child(_save_timer)
	load_settings()


func set_value(key: String, value: Variant) -> void:
	if get(key) == value:
		return
	set(key, value)
	changed.emit(key)
	queue_save()


func queue_save() -> void:
	if _save_timer.is_inside_tree():
		_save_timer.start()


func beat_seconds() -> float:
	return 60.0 / maxf(bpm, 1.0)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for key in KEYS:
		if cfg.has_section_key("app", key):
			set(key, cfg.get_value("app", key))
	if not cfg.has_section_key("app", "layout_version"):
		_migrate_v1(cfg)
	if not Scales.SCALES.has(scale_name):
		scale_name = "Minor Pentatonic"
	if not DIVISION_OPTIONS.has(divisions):
		divisions = 4


## Version 1 stored positions as fractions of the window and wave speed in px/s.
func _migrate_v1(cfg: ConfigFile) -> void:
	if cfg.has_section_key("app", "wave_speed"):
		wave_speed = float(cfg.get_value("app", "wave_speed"))   # -> beat_spacing at the default BPM
	for d in notes:
		d["x"] = float(d.get("x", 0.5)) * LEGACY_SIZE.x
		d["y"] = float(d.get("y", 0.5)) * LEGACY_SIZE.y
		if d.has("ex"):
			d["ex"] = float(d["ex"]) * LEGACY_SIZE.x
			d["ey"] = float(d["ey"]) * LEGACY_SIZE.y
	layout_version = LAYOUT_VERSION
	queue_save()


func save_now() -> void:
	var cfg := ConfigFile.new()
	for key in KEYS:
		cfg.set_value("app", key, get(key))
	cfg.save(PATH)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _save_timer and not _save_timer.is_stopped():
			save_now()
