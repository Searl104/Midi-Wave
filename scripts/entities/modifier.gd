class_name Modifier
extends RefCounted
## A ring on an object that decides what each hit does. One per object. Subclasses set the rules
## and the tab's icon; Stop returns any state to its start.

const RING := 10.0                 ## ring radius beyond the object's
const KINDS := ["toggle"]

var on := true                     ## current state
var start := true                  ## what Stop returns to
var flip := 0.0                    ## flash when the state changes


## A modifier of `kind`, or null for "" or a kind that doesn't exist.
static func create(kind_name: String) -> Modifier:
	match kind_name:
		"toggle":
			return ToggleModifier.new()
	return null


func kind() -> String:
	return ""


func set_start(state: bool) -> void:
	start = state
	on = state


## A state the user sets is its intended start state: sets both.
func set_state(state: bool) -> void:
	on = state
	start = state
	flip = 1.0


## A hit arrived. Returns false if it's silenced.
func passes_hit() -> bool:
	return true


func reset() -> void:
	on = start


func save_start() -> void:
	start = on


func tick(delta: float) -> void:
	flip = maxf(0.0, flip - delta * 4.0)


## Added to the object's tooltip.
func describe() -> String:
	return ""


func dims_label() -> bool:
	return false


## The ring and its tab, which hangs off the bottom of the ring and holds the icon.
func draw(surface: WaveSurface, p: Vector2, col: Color) -> void:
	var ring_r := SurfaceObject.RADIUS + RING + 2.0 * flip
	surface.draw_arc(p, ring_r, 0.0, TAU, 56, Color(col, (1.0 if on else 0.35) * (1.0 - 0.3 * flip) + 0.3 * flip), 1.0 + flip, true)

	var c := p + Vector2(0, SurfaceObject.RADIUS + RING + 4.0)   # tab centre
	var tab := Rect2(c - Vector2(12, 7), Vector2(24, 14))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.075, 0.08, 0.11, 1.0)
	sb.border_color = Color(col, 1.0 if on else 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.anti_aliasing = true
	surface.draw_style_box(sb, tab)
	_draw_icon(surface, c, col if on else Palette.TEXT_DIM)
	if on != start:
		# Start-state dot: filled = starts on, hollow = starts off.
		var dot := tab.position + Vector2(tab.size.x - 1.0, 1.0)
		surface.draw_circle(dot, 3.2, Palette.BG)
		if start:
			surface.draw_circle(dot, 2.3, col)
		else:
			surface.draw_arc(dot, 2.0, 0.0, TAU, 12, Palette.TEXT_DIM, 1.0, true)


func _draw_icon(_surface: WaveSurface, _c: Vector2, _ink: Color) -> void:
	pass
