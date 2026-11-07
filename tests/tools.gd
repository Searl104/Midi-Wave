extends Node
## Exercises every tool's operations directly. Run: godot --headless --path . res://tests/tools.tscn
## The checks live in tests/tools/, one file per area, sharing the state set up here.

const AREAS := [
	"res://tests/tools/editing_test.gd",
	"res://tests/tools/rings_test.gd",
	"res://tests/tools/panels_test.gd",
	"res://tests/tools/layouts_test.gd",
	"res://tests/tools/midi_timing_test.gd",
	"res://tests/tools/saves_test.gd",
]

var surface: WaveSurface
var tools: ToolManager
var radial: RadialMenu


func _ready() -> void:
	Midi.log_when_closed = false
	surface = WaveSurface.new()
	add_child(surface)
	surface.size = Vector2(1280, 800)
	radial = RadialMenu.new()
	add_child(radial)
	radial.size = Vector2(1280, 800)
	tools = surface.tools
	tools.attach_radial(radial)
	surface.clear_notes()
	var counts := {"checks": 0, "failures": 0}
	for path in AREAS:
		var area: Node = load(path).new()
		area.surface = surface
		area.tools = tools
		area.radial = radial
		area.counts = counts
		add_child(area)
		area.run()
	var failures: int = counts.failures
	print("TOOLS %s: %d checks, %d failed" % ["OK" if failures == 0 else "FAILED", counts.checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
