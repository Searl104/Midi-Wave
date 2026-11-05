class_name Snapping
extends RefCounted
## Timing rings, spokes and grids: where a dragged or newly placed object lands, and the readout.
##
## Rings show around each grid while dragging. The dragged item snaps to the nearest ring, spoke
## or crossing; Shift places freely; onto a note or emitter it lands on the centre. Touch to snap
## (deprecated, off unless touch_snap=true in the settings file) adds touched objects as targets.

const FRACTIONS := {
	"1/2": "½", "1/3": "⅓", "2/3": "⅔", "1/4": "¼", "3/4": "¾", "1/6": "⅙", "5/6": "⅚",
	"1/8": "⅛", "3/8": "⅜", "5/8": "⅝", "7/8": "⅞",
}

var surface: WaveSurface


func _init(owner_surface: WaveSurface) -> void:
	surface = owner_surface


static func ring_step() -> float:
	return Settings.BEAT_UNIT / maxf(float(Settings.divisions), 1.0)


## Every object a held item can touch, keyed "n<id>" (a note) or "e<id>" (a detached
## emitter), with its world position. The held note and its own emitter are left out.
func touch_targets(exclude_id: int) -> Dictionary:
	var out := {}
	for m in surface.notes:
		if m.id == exclude_id or surface.drag.group.has(m.id):
			continue
		out["n%d" % m.id] = m.pos
		var e: Emitter = m.emitter()
		if e and not e.attached:
			out["e%d" % m.id] = e.pos
	return out


## Grids that are on, keyed like touch targets, as {key: [Grid, world position, reach]}.
## The held note (and its emitter) and the rest of a dragged group are left out.
func active_grids(exclude_id: int = -1) -> Dictionary:
	var out := {}
	for m in surface.notes:
		if m.id == exclude_id or surface.drag.group.has(m.id):
			continue
		if m.grid:
			out["n%d" % m.id] = [m.grid, m.pos, m.grid_limit()]
		var e: Emitter = m.emitter()
		if e and e.grid and not e.attached:
			out["e%d" % m.id] = [e.grid, e.pos, e.grid_limit()]
	return out


## Adds or removes the grid on an object, or with `on_emitter` on its emitter.
func toggle_grid(o: Note, on_emitter: bool) -> void:
	var e: Emitter = o.emitter()
	if on_emitter:
		e.grid = null if e.grid else Grid.new()
	else:
		o.grid = null if o.grid else Grid.new()
	surface.effects.flash_brackets(o)
	surface.save_notes()


## Turns every grid off. Returns how many were on.
func clear_grids() -> int:
	var count := 0
	for o in surface.notes:
		var e: Emitter = o.emitter()
		count += int(o.grid != null) + int(e != null and e.grid != null)
		o.grid = null
		if e:
			e.grid = null
	if count > 0:
		surface.save_notes()
	return count


## The nearest grid point to world point `p`, for placing new objects: the nearest place where a
## ring crosses a spoke when one is close (within the snap distance, or half a ring step), else
## the nearest ring along the line from a grid's origin. Returns `p` when snapping is off or no
## grid is on (or in reach).
func grid_snap(p: Vector2) -> Vector2:
	if not Settings.snap_enabled:
		return p
	var grids := active_grids()
	var step := ring_step()
	var use_spokes: bool = Settings.snap_spokes and Settings.spoke_count > 0
	var ss := TAU / maxf(float(Settings.spoke_count), 1.0)
	var near := maxf(Settings.snap_distance / surface.z(), step * 0.5)
	var best_cross := p
	var cross_d := INF
	var best_ring := p
	var ring_d := INF
	for key in grids:
		var origin: Vector2 = grids[key][1]
		var to_p := (p - origin).length()
		if to_p >= grids[key][2] or (not Settings.guides_to_edge and to_p >= Settings.wave_range):
			continue
		var points: Array = grids[key][0].nearest(origin, p, step, ss)
		if points[0].distance_to(p) < ring_d:
			ring_d = points[0].distance_to(p)
			best_ring = points[0]
		if use_spokes and points[1].distance_to(p) < cross_d:
			cross_d = points[1].distance_to(p)
			best_cross = points[1]
	if cross_d <= near:
		return best_cross
	return best_ring


## Works out rings, snapping and the readout for dragging object `n` (`kind` "note" or
## "emitter") to world point `p`, snapping only to the touched objects in `touched`.
## Returns {pos, centres, readout, loop, snapped, centre, ref_point}; centres[0] is the held item.
## Centre snapping (onto any note or emitter within the snap distance) beats rings and spokes.
func compute_drag(n: Note, kind: String, p: Vector2, free: bool, touched: Dictionary = {}) -> Dictionary:
	var reach := Settings.wave_range
	free = free or not Settings.snap_enabled
	var targets := touch_targets(n.id)
	var pairs: Array = []      # [world point, owning object id, key]
	for key in touched:
		if targets.has(key):
			pairs.append([targets[key], int(key.substr(1)), key, INF])
	var grids := active_grids(n.id)
	for key in grids:
		if not touched.has(key):
			pairs.append([grids[key][1], int(key.substr(1)), key, grids[key][2]])

	var step_px := ring_step()
	var best: Array = []
	var best_fix := INF
	for pr in pairs:
		var d := p.distance_to(pr[0])
		if d >= pr[3] or (not Settings.guides_to_edge and d >= reach):
			continue                                   # guides stop at the reach
		var target := roundf(d / step_px) * step_px
		if target < step_px * 0.5:
			continue
		var fix := absf(target - d)
		if fix < best_fix:
			best_fix = fix
			best = pr

	# Spokes: lines from each snap target. Nearest spoke within tolerance.
	var tol := Settings.snap_distance / surface.z()
	var spoke: Array = []
	var spoke_ang := 0.0
	var spoke_off := INF
	var spoke_step := TAU / maxf(float(Settings.spoke_count), 1.0)
	for pr in (pairs if Settings.snap_spokes and Settings.spoke_count > 0 else []):
		var v := p - (pr[0] as Vector2)
		var d := v.length()
		if d < 1.0 or d >= pr[3]:
			continue
		var ang := v.angle()
		var snapped_ang := roundf(ang / spoke_step) * spoke_step
		var off := d * absf(sin(ang - snapped_ang))
		if off <= tol and off < spoke_off:
			spoke_off = off
			spoke = pr
			spoke_ang = snapped_ang

	# Centre: any note or emitter (touched or not) whose centre is within the snap distance.
	var centre: Array = []
	var centre_d := tol
	if not free and Settings.snap_centres:
		for key in targets:
			var dc := p.distance_to(targets[key])
			if dc <= centre_d:
				centre_d = dc
				centre = [targets[key], int(key.substr(1)), key]

	# Grid points: where any target's ring crosses one of its own spokes, nearest within tolerance.
	var cross: Array = []
	var cross_pos := p
	var cross_d := tol
	for pr in (pairs if Settings.snap_spokes and Settings.spoke_count > 0 else []):
		var v2 := p - (pr[0] as Vector2)
		var d2 := v2.length()
		if d2 < 1.0 or d2 >= pr[3] or (not Settings.guides_to_edge and d2 >= reach):
			continue
		var r2 := roundf(d2 / step_px) * step_px
		if r2 < step_px * 0.5:
			continue
		var pt: Vector2 = pr[0] + Vector2.from_angle(roundf(v2.angle() / spoke_step) * spoke_step) * r2
		if pt.distance_to(p) <= cross_d:
			cross_d = pt.distance_to(p)
			cross_pos = pt
			cross = pr

	var out_pos := p
	var snapped := false
	var ref: Array = []
	if not centre.is_empty():
		out_pos = centre[0]
		snapped = true
		ref = centre
	elif not free and not cross.is_empty():
		out_pos = cross_pos
		snapped = true
		ref = cross
	elif not free and not best.is_empty() and best_fix <= tol:
		# On a ring; if also near one of the same target's spokes, land on the crossing.
		var a: Vector2 = best[0]
		var radius := roundf(p.distance_to(a) / step_px) * step_px
		var dir := (p - a).normalized() if p.distance_to(a) > 0.001 else Vector2.RIGHT
		if not spoke.is_empty() and spoke[2] == best[2]:
			dir = Vector2.from_angle(spoke_ang)
		out_pos = a + dir * radius
		snapped = true
		ref = best
	elif not free and not spoke.is_empty():
		# Only on a spoke: keep the distance, line up on the spoke.
		var a2: Vector2 = spoke[0]
		out_pos = a2 + Vector2.from_angle(spoke_ang) * p.distance_to(a2)
		snapped = true
		ref = spoke
	else:
		# Not snapped: measure to the nearest touched object, else the nearest object in reach.
		var pool: Array = pairs.duplicate()
		if pool.is_empty():
			for key in targets:
				pool.append([targets[key], int(key.substr(1)), key])
		var nearest_d := reach
		for pr in pool:
			var d := p.distance_to(pr[0])
			if d < nearest_d:
				nearest_d = d
				ref = pr

	var centres: Array = [out_pos]
	var limits: Array = [INF]
	for pr in pairs:
		centres.append(pr[0])
		limits.append(pr[3])
	var info := {"pos": out_pos, "centres": centres, "limits": limits, "readout": "", "loop": "", "snapped": snapped,
			"ref_point": ref[0] if not ref.is_empty() else null,
			"snap_key": ref[2] if snapped else ""}
	info["centre"] = not centre.is_empty()
	if not centre.is_empty():
		info.readout = "centre"
		info.loop = _loop_text(n, kind, out_pos, surface.get_note(ref[1]))
	elif not ref.is_empty():
		var d := out_pos.distance_to(ref[0])
		info.readout = "%s · %d ms" % [format_beats(d / Settings.BEAT_UNIT), roundi(d / Settings.wave_speed * 1000.0)]
		info.loop = _loop_text(n, kind, out_pos, surface.get_note(ref[1]))
	elif free:
		info.readout = "free"
	return info


## Loop period when the dragged object and `m` both pulse and each reaches the other.
func _loop_text(n: Note, kind: String, p: Vector2, m: Note) -> String:
	if m == null or n.relay() == null or m.relay() == null:
		return ""
	var n_pos: Vector2 = p if kind == "note" else n.pos
	var n_emit: Vector2 = p if (kind == "emitter" or n.emitter().attached) else n.emitter().pos
	var there := n_emit.distance_to(m.pos)
	var back := m.emitter().world_pos(m).distance_to(n_pos)
	if there >= Settings.wave_range or back >= Settings.wave_range:
		return ""
	return "loop " + format_beats((there + back) / Settings.BEAT_UNIT)


## "1 ¾ beats", "½ beat", "2 beats"; off-grid values read "≈ 1.37 beats".
static func format_beats(b: float) -> String:
	var div: int = Settings.divisions
	var whole := floori(b + 0.0001)
	var num := roundi((b - whole) * div)
	if num == div:
		whole += 1
		num = 0
	if absf(b - (whole + float(num) / div)) > 0.01:
		return "≈ %.2f beats" % b
	var frac := ""
	if num > 0:
		var g := _gcd(num, div)
		var key := "%d/%d" % [num / g, div / g]
		frac = FRACTIONS.get(key, key)
	var text := ""
	if whole > 0 and frac != "":
		text = "%d %s" % [whole, frac]
	elif whole > 0:
		text = str(whole)
	elif frac != "":
		text = frac
	else:
		text = "0"
	return text + (" beat" if b <= 1.0001 else " beats")


static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t := b
		b = a % b
		a = t
	return a
