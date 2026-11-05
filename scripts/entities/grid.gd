class_name Grid
extends RefCounted
## A snap grid: timing rings and spokes centred on a note or a detached emitter. Whatever carries
## it passes its own world position as `origin`. The same guides show around dragged items.
## Nothing draws or snaps past a grid's reach. With no reach set, it follows its carrier.

var reach := 0.0                   ## world units; 0 = automatic


## The nearest ring point and ring / spoke crossing to `p`: [on_ring, crossing].
func nearest(origin: Vector2, p: Vector2, ring: float, spoke_step: float) -> Array:
	var v := p - origin
	var d := v.length()
	var r := maxf(roundf(d / ring), 1.0) * ring
	var ang := v.angle() if d > 0.001 else -PI / 2.0
	return [origin + Vector2.from_angle(ang) * r, origin + Vector2.from_angle(roundf(ang / spoke_step) * spoke_step) * r]


## One object's timing rings and spokes, out to the window edge (or the wave's reach).
static func draw_guide(surface: WaveSurface, centre_w: Vector2, weight: float, divisions: bool, limit: float = INF) -> void:
	var step_s := Snapping.ring_step() * surface.z()    # ring spacing on screen
	var div: int = Settings.divisions
	var reach_s := Settings.wave_range * surface.z()
	var size := surface.size
	var corners := [Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]
	var centre := surface.to_screen(centre_w)
	var far := 0.0
	for corner in corners:
		far = maxf(far, centre.distance_to(corner))
	if not Settings.guides_to_edge:
		far = minf(far, reach_s)
	far = minf(far, limit * surface.z())
	var count := mini(int(floor(far / step_s + 0.001)), 600)
	if limit == INF:
		count = mini(int(ceil(far / step_s)), 600)
	if Settings.spoke_count > 0:
		# Spokes out to the guide limit, on the held item and on every snap target.
		var spokes: int = Settings.spoke_count
		for i in spokes:
			var sd := Vector2.from_angle(i * TAU / spokes)
			surface.draw_line(centre + sd * (Note.RADIUS + 10.0), centre + sd * far,
					Color(Palette.ACCENT.lightened(0.3), minf((0.5 if i % 2 == 0 else 0.32) * weight, 1.0)), 1.0, true)
	for k in range(1, count + 1):
		var r := k * step_s
		var fade := (1.0 - 0.55 * minf(r / maxf(far, 1.0), 1.0)) * weight
		if r > reach_s:
			fade *= 0.6
		var col: Color
		var width := 1.0
		if k % (div * 4) == 0:
			col = Color(Palette.ACCENT.lightened(0.45), 0.85 * fade)    # bar
			width = 2.0
		elif k % div == 0:
			col = Color(Palette.ACCENT.lightened(0.3), 0.62 * fade)     # beat
			width = 1.5
		else:
			if step_s < 6.0 or not divisions:
				continue                                                 # off, or too dense to read
			col = Color(1, 1, 1, 0.16 * fade)                            # division
		surface.draw_arc(centre, r, 0.0, TAU, clampi(int(r / 5.0), 48, 720), col, width, true)
