class_name Modifier
extends RefCounted
## Something on a note that changes what a hit does. A note can hold several. Each has a tab that
## opens its settings ring. Subclasses set the rules, ring and tab; Stop resets any state.

const RING := 10.0                 ## ring radius beyond the object's
const KINDS := ["sequence", "relay", "silent"]

var flip := 0.0                    ## flash when the state changes


## A modifier of `kind`, or null for "" or a kind that doesn't exist.
static func create(kind_name: String) -> Modifier:
	match kind_name:
		"sequence", "rest", "toggle":    # older saves use the other names
			return SequenceModifier.new()
		"relay":
			return RelayModifier.new()
		"silent":
			return SilentModifier.new()
	return null


func kind() -> String:
	return ""


## Its settings ring, as named in ToolManager.
func ring_id() -> String:
	return ""


## The order hits reach modifiers: anything that can silence a hit comes first.
func order() -> int:
	return 0


## True if it draws a ring and hanging tab.
func has_ring() -> bool:
	return false


func load_dict(_d: Dictionary, _p: Vector2) -> void:
	pass


func to_dict() -> Dictionary:
	return {"kind": kind()}


## Play state undo keeps.
func live_state() -> Array:
	return []


func restore_state(_state: Array) -> void:
	pass


## True if `at` (screen) is on its tab.
func tab_contains(_surface: WaveSurface, _note: Note, _at: Vector2) -> bool:
	return false


## A hit arrived. Returns false if it's silenced.
func passes_hit() -> bool:
	return true


## Back to its start state.
func reset() -> void:
	pass


## True if hits are being silenced for now.
func resting() -> bool:
	return false


func tick(delta: float) -> void:
	flip = maxf(0.0, flip - delta * 4.0)


## Added to the object's tooltip.
func describe() -> String:
	return ""


func dims_label() -> bool:
	return false


## The ring and tab, for modifiers that have them.
func draw(surface: WaveSurface, p: Vector2, col: Color) -> void:
	if has_ring():
		_draw_ring_and_tab(surface, p, col)


func _tab_centre(surface: WaveSurface, note: Note) -> Vector2:
	return surface.to_screen(note.pos) + Vector2(0, Note.RADIUS + RING + 4.0)


## The ring and its tab, which hangs off the bottom of the ring and holds the icon.
func _draw_ring_and_tab(surface: WaveSurface, p: Vector2, col: Color) -> void:
	var ring_r := Note.RADIUS + RING + 2.0 * flip
	surface.draw_arc(p, ring_r, 0.0, TAU, 56, Color(col, (0.35 if resting() else 1.0) * (1.0 - 0.3 * flip) + 0.3 * flip), 1.0 + flip, true)

	var c := p + Vector2(0, Note.RADIUS + RING + 4.0)   # tab centre
	var tab := Rect2(c - Vector2(12, 7), Vector2(24, 14))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.075, 0.08, 0.11, 1.0)
	sb.border_color = Color(col, 0.55 if resting() else 1.0)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.anti_aliasing = true
	surface.draw_style_box(sb, tab)
	_draw_icon(surface, c, Palette.TEXT_DIM if resting() else col)


func _draw_icon(_surface: WaveSurface, _c: Vector2, _ink: Color) -> void:
	pass
