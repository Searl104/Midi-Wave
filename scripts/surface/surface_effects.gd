class_name SurfaceEffects
extends RefCounted
## Short-lived visuals that aren't entities: splashes when notes play, and bracket flashes.

const SPLASH_TIME := 0.6
const BRACKET_FLASH_TIME := 0.4

var splashes: Array = []           # {pos: Vector2 (world), t: float, color: Color, strength: float}
var bracket_flashes: Array = []    # {pos: Vector2 (world), half: float, t: float}


func add_splash(pos: Vector2, color: Color, strength: float) -> void:
	splashes.append({"pos": pos, "t": 0.0, "color": color, "strength": strength})


## Briefly flashes an object's brackets, to show where an action landed.
func flash_brackets(o: Note) -> void:
	if o:
		bracket_flashes.append({"pos": o.pos, "half": o.bracket_half(), "t": 0.0})


func tick(delta: float) -> void:
	_age(bracket_flashes, delta, BRACKET_FLASH_TIME)
	_age(splashes, delta, SPLASH_TIME)


func _age(items: Array, delta: float, life: float) -> void:
	var i := 0
	while i < items.size():
		items[i].t += delta
		if items[i].t >= life:
			items.remove_at(i)
		else:
			i += 1


func draw_splashes(surface: WaveSurface) -> void:
	for sp in splashes:
		var k: float = sp.t / SPLASH_TIME
		var rr := Note.RADIUS + 46.0 * ease(k, 0.4)
		surface.draw_arc(surface.to_screen(sp.pos), rr, 0.0, TAU, 64, Color(sp.color, (1.0 - k) * 0.6 * sp.strength), 2.0, true)


func draw_bracket_flashes(surface: WaveSurface) -> void:
	for bfl in bracket_flashes:
		var k: float = bfl.t / BRACKET_FLASH_TIME
		surface.draw_brackets(surface.to_screen(bfl.pos), bfl.half + 2.0 + 10.0 * ease(k, 0.4), 2.0, 0.9 * (1.0 - k), 0.42)

