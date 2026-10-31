extends Node
## Persistent app settings and note layout, autoloaded as `Settings`.
## Saved to user://settings.cfg (on Windows: %APPDATA%\Godot\app_userdata\MIDI Wave\).

signal changed(key: String)

const PATH := "user://settings.cfg"
const KEYS := [
	"wave_strength", "wave_speed", "wave_range", "falloff_curve", "note_length",
	"root_note", "scale_name", "midi_port", "notes",
]

var wave_strength := 1.0        ## 0.1-1.0, peak velocity of a fresh wave
var wave_speed := 420.0         ## px per second
var wave_range := 900.0         ## px at which the wave reaches 0
var falloff_curve := 1.6        ## 1 = linear, higher = drops faster near the source
var note_length := 0.35         ## seconds a triggered note is held
var root_note := 0              ## 0-11, C = 0
var scale_name := "Minor Pentatonic"
var midi_port := ""             ## last opened output port, reopened on launch
var notes: Array = []           ## [{x, y, note, channel}] with x/y normalized 0-1

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


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for key in KEYS:
		if cfg.has_section_key("app", key):
			set(key, cfg.get_value("app", key))
	if not Scales.SCALES.has(scale_name):
		scale_name = "Minor Pentatonic"


func save_now() -> void:
	var cfg := ConfigFile.new()
	for key in KEYS:
		cfg.set_value("app", key, get(key))
	cfg.save(PATH)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _save_timer and not _save_timer.is_stopped():
			save_now()
