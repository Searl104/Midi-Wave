extends Node
## Persistent app settings and note layout, autoloaded as `Settings`.
## Saved to user://settings.cfg (on Windows: %APPDATA%\Godot\app_userdata\MIDI Wave\).

signal changed(key: String)

const PATH := "user://settings.cfg"
const LAYOUT_VERSION := 3       ## 1 = fractions of the window, 2 = screen px, 3 = world units
const BEAT_UNIT := 200.0        ## world units per beat; beat spacing / BEAT_UNIT = zoom
const LEGACY_SIZE := Vector2(1280, 800)   ## window size used to convert version-1 layouts
const DIVISION_OPTIONS := [1, 2, 3, 4, 6, 8]
const KEYS := [
	"wave_strength", "bpm", "beat_spacing", "divisions", "wave_range", "falloff_curve", "note_length",
	"root_note", "scale_name", "midi_port", "notes", "view_offset", "layout_version",
	"snap_enabled", "snap_distance", "snap_spokes", "spoke_count", "guides_to_edge",
	"guide_divisions", "guide_brightness", "snap_memory", "touch_snap", "colorblind", "channel_lengths", "snap_centres", "look",
	"abyss_sink", "abyss_density", "abyss_glints", "abyss_shafts", "abyss_depth", "abyss_refraction",
	"tidal_scale", "tidal_depth", "tidal_shine", "tidal_relief", "tidal_refraction", "tidal_color", "tidal_caustics", "tidal_caustic_scale", "tidal_caustic_speed",
]
const SPOKE_OPTIONS := [0, 4, 6, 8, 12, 16]
const LOOKS := ["Abyssal", "Tidal", "Glass"]   ## surface shaders: shaders/<lowercase>.gdshader ("Glass" = water)

var wave_strength := 1.0        ## 0.1-1.0, peak velocity of a fresh wave
var bpm := 120.0                ## tempo; wave speed follows it
var beat_spacing := 200.0       ## on-screen px per beat: the canvas zoom (timing is unchanged)
var divisions := 4              ## faded division rings per beat
var wave_range := 900.0         ## world units at which the wave reaches 0 (BEAT_UNIT per beat)
var falloff_curve := 1.6        ## 1 = linear, higher = drops faster near the source
var note_length := 0.35         ## seconds a triggered note is held
var root_note := 0              ## 0-11, C = 0
var scale_name := "Minor Pentatonic"
var midi_port := ""             ## last opened output port, reopened on launch
var notes: Array = []           ## [{x, y, note, channel, mode, ...}] in world units
var view_offset := Vector2.ZERO ## world position of the window's top-left corner
var layout_version := LAYOUT_VERSION
var look := "Abyssal"           ## surface look, one of LOOKS

## Look controls (Options > Look). Each is a multiplier on the shader's base value (1 = as
## designed), except tidal_depth, the sand plane's pan/zoom rate. key -> [look, uniform, base].
const LOOK_PARAMS := {
	"abyss_sink": ["Abyssal", "sink_speed", 0.018],
	"abyss_density": ["Abyssal", "snow_density", 1.0],
	"abyss_glints": ["Abyssal", "glint_amount", 1.0],
	"abyss_shafts": ["Abyssal", "shaft_strength", 1.0],
	"abyss_depth": ["Abyssal", "depth_scale", 7.0],
	"abyss_refraction": ["Abyssal", "refraction", 16.0],
	"tidal_scale": ["Tidal", "tile_px", 1800.0],
	"tidal_depth": ["Tidal", "plane_depth", 1.0],
	"tidal_shine": ["Tidal", "shine", 1.0],
	"tidal_relief": ["Tidal", "bump", 1.15],
	"tidal_refraction": ["Tidal", "refraction", 22.0],
	"tidal_color": ["Tidal", "color_amount", 1.0],
	"tidal_caustics": ["Tidal", "caustics", 1.0],
	"tidal_caustic_scale": ["Tidal", "caustic_px", 330.0],
	"tidal_caustic_speed": ["Tidal", "caustic_speed", 0.35],
}
const LOOK_DEFAULTS := {"tidal_depth": 0.65}   ## anything not listed defaults to 1.0
var abyss_sink := 1.0
var abyss_density := 1.0
var abyss_glints := 1.0
var abyss_shafts := 1.0
var abyss_depth := 1.0
var abyss_refraction := 1.0
var tidal_scale := 1.0
var tidal_depth := 0.65
var tidal_shine := 1.0
var tidal_relief := 1.0
var tidal_refraction := 1.0
var tidal_color := 1.0
var tidal_caustics := 1.0
var tidal_caustic_scale := 1.0
var tidal_caustic_speed := 1.0


func look_default(key: String) -> float:
	return LOOK_DEFAULTS.get(key, 1.0)


## Shader uniform value for a look control.
func look_uniform_value(key: String) -> float:
	return float(get(key)) * float(LOOK_PARAMS[key][2])

# Snap settings (Options > Snap)
var snap_enabled := true        ## snap dragged items to touched targets' rings and spokes
var snap_distance := 12.0       ## screen px within which a dragged item snaps
var snap_spokes := true         ## snap to spokes as well as rings
var spoke_count := 8            ## spokes drawn from each snap target (0 = none)
var guides_to_edge := true      ## guides run to the window edge (false: stop at the wave's reach)
var guide_divisions := true     ## draw the faded division rings
var guide_brightness := 1.0     ## 0.3-1.5
## Colour-blind safe channel colours (channels 9-16 get a double outline).
var colorblind := false:
	set(v):
		colorblind = v
		Palette.colorblind = v
## Deprecated: touch to snap (touch an object while dragging to snap to it). Off by default and
## not in the Options panel; set touch_snap=true in the settings file to bring it back.
var touch_snap := false
var snap_memory := true         ## remember the target snapped to on drop for the next drag
var snap_centres := true        ## snap onto the centre of a note or emitter the item is dropped on

## Per-channel note length in seconds (index 0 = channel 1); 0 = use the global note_length.
var channel_lengths: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]


## How long a note on `channel` (0-15) is held.
func note_length_for(channel: int) -> float:
	if channel >= 0 and channel < channel_lengths.size() and float(channel_lengths[channel]) > 0.0:
		return float(channel_lengths[channel])
	return note_length


func set_channel_length(channel: int, seconds: float) -> void:
	if channel < 0 or channel > 15:
		return
	channel_lengths[channel] = maxf(seconds, 0.0)
	changed.emit("channel_lengths")
	queue_save()

## Wave speed in world units per second, locked to tempo: one beat of space per beat.
## Setting it sets the tempo.
var wave_speed: float:
	get:
		return BEAT_UNIT * bpm / 60.0
	set(value):
		bpm = value * 60.0 / BEAT_UNIT


## Canvas zoom: on-screen px per world unit. Icons are drawn at a fixed size regardless.
func zoom() -> float:
	return beat_spacing / BEAT_UNIT

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
	if layout_version < 3:
		_migrate_v2()
	if not Scales.SCALES.has(scale_name):
		scale_name = "Minor Pentatonic"
	if not DIVISION_OPTIONS.has(divisions):
		divisions = 4
	if not SPOKE_OPTIONS.has(spoke_count):
		spoke_count = 8
	if not LOOKS.has(look):
		look = "Abyssal"
	if channel_lengths.size() != 16:
		var fixed: Array = []
		for i in 16:
			fixed.append(float(channel_lengths[i]) if i < channel_lengths.size() else 0.0)
		channel_lengths = fixed


## Version 1 stored positions as fractions of the window and wave speed in px/s.
func _migrate_v1(cfg: ConfigFile) -> void:
	# Version 1 had no tempo: one beat was its wave speed (default 420 px/s) x 60 / 120 BPM.
	beat_spacing = float(cfg.get_value("app", "wave_speed", 420.0)) * 60.0 / maxf(bpm, 1.0)
	for d in notes:
		d["x"] = float(d.get("x", 0.5)) * LEGACY_SIZE.x
		d["y"] = float(d.get("y", 0.5)) * LEGACY_SIZE.y
		if d.has("ex"):
			d["ex"] = float(d["ex"]) * LEGACY_SIZE.x
			d["ey"] = float(d["ey"]) * LEGACY_SIZE.y
	layout_version = 2
	queue_save()


## Version 2 stored positions in screen px, with one beat = beat_spacing px. Version 3 stores
## world units (one beat = BEAT_UNIT); beat spacing is now only the zoom, so the layout looks
## the same and keeps its timing.
func _migrate_v2() -> void:
	var k := BEAT_UNIT / maxf(beat_spacing, 1.0)
	for d in notes:
		for key in ["x", "y", "ex", "ey"]:
			if d.has(key):
				d[key] = float(d[key]) * k
	view_offset *= k
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
