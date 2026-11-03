class_name Emitter
extends RefCounted
## Where a relay's wave starts, and how it fires: strength, cooldown in beats and its own reach.
## It starts docked on its note; dragged away, it stays at a fixed spot on the surface, drawn under
## the notes, and a dim handle stays on the note. It is only a point: waves don't trigger it.

const HANDLE_RADIUS := 7.0
const MIN_COOLDOWN := 0.125        ## beats (an eighth of a beat)
const DEFAULT_STRENGTH := 0.8
const DEFAULT_COOLDOWN := 1.0      ## beats
const COOLDOWN_GRACE := 20000      ## microseconds early a hit can land and still fire: about a frame

var attached := true
var pos := Vector2.ZERO            ## world units; used while detached
var strength := DEFAULT_STRENGTH
var cooldown := DEFAULT_COOLDOWN   ## beats; 0 = retrigger
var own_reach := 0.0               ## wave reach in world units (0 = the global Reach)
var grid: Grid = null              ## snap grid centred here, if on and detached
var snap := ""                     ## target last snapped to when dropped
var ready_at := 0                  ## clock time it can fire again
var hold_next := 0                 ## next refire time while its binding is held
var pulse_flash := 0.0


## A cooldown as saved: at least MIN_COOLDOWN, and 0 stays retrigger.
static func clamp_cooldown(beats: float) -> float:
	return 0.0 if beats <= 0.0 else maxf(beats, MIN_COOLDOWN)


func load_dict(d: Dictionary, p: Vector2) -> void:
	grid = Grid.new() if bool(d.get("grid_emit", false)) else null
	if grid:
		grid.reach = maxf(float(d.get("grid_emit_reach", 0.0)), 0.0)
	snap = str(d.get("snap_emit", ""))
	own_reach = maxf(float(d.get("range", 0.0)), 0.0)
	strength = clampf(float(d.get("pulse_strength", DEFAULT_STRENGTH)), 0.05, 1.0)
	# Cooldowns are in beats (tempo-locked). Older saves stored seconds: convert at the saved tempo.
	var cd := DEFAULT_COOLDOWN
	if d.has("cooldown_beats"):
		cd = float(d["cooldown_beats"])
	elif d.has("cooldown"):
		cd = float(d["cooldown"]) * Settings.bpm / 60.0
	cooldown = clamp_cooldown(cd)
	attached = bool(d.get("attached", true))
	pos = Vector2(float(d.get("ex", p.x)), float(d.get("ey", p.y)))


func to_dict() -> Dictionary:
	return {"pulse_strength": strength, "cooldown_beats": cooldown, "attached": attached,
			"ex": pos.x, "ey": pos.y, "range": own_reach, "grid_emit": grid != null,
			"grid_emit_reach": grid.reach if grid else 0.0, "snap_emit": snap}


func is_retrigger() -> bool:
	return cooldown <= 0.0


## The cooldown in microseconds at the current tempo. Retrigger has no timer: it fires on every
## wave, with only the 1/8-beat minimum kept as a safety floor against runaway contact loops.
func cooldown_usec() -> int:
	var beats: float = MIN_COOLDOWN if is_retrigger() else cooldown
	return int(beats * 60.0 / maxf(Settings.bpm, 1.0) * 1_000_000.0)


## Where its waves start, in world units.
func world_pos(owner: Note) -> Vector2:
	return owner.pos if attached else pos


## Its reach: its own if set, else the global Reach.
func reach() -> float:
	return own_reach if own_reach > 0.0 else Settings.wave_range


## How far a grid on this emitter reaches: its own, else as far as the emitter's waves.
func grid_limit() -> float:
	return grid.reach if grid and grid.reach > 0.0 else reach()


## Fires a wave. `overshoot` is how far the hit's wave had passed when this frame noticed it: the new
## wave starts that far out and the cooldown counts from the true hit, so links don't add frames
## and loops keep their tempo. Hits land on frames, so one a little early still fires.
## True if it can't fire yet at `time`.
func cooling(time: int) -> bool:
	return time < ready_at - COOLDOWN_GRACE


func fire(surface: WaveSurface, owner: Note, now: int, spawned: Array, overshoot: float = 0.0) -> void:
	var hit_at := now - int(overshoot / Settings.wave_speed * 1_000_000.0)
	if cooling(hit_at):
		return
	if surface.waves.size() + spawned.size() >= WaveSurface.MAX_WAVES:
		surface.skipped_pulses += 1  # surface full: skip this beat, stay ready
		return
	var w := Wave.new(world_pos(owner), strength, owner.id, own_reach)
	w.r = overshoot
	spawned.append(w)
	ready_at = hit_at + cooldown_usec()
	pulse_flash = 1.0


func tick(delta: float) -> void:
	pulse_flash = maxf(0.0, pulse_flash - delta * 3.0)


# --- Drawing -------------------------------------------------------------------------------

## Where the handle sits on its note: upper right, past any modifier ring.
func dock_screen_pos(surface: WaveSurface, owner: Note) -> Vector2:
	var out := Note.RADIUS + (Modifier.RING + 8.0 if owner.has_ring() else 9.0)
	return surface.to_screen(owner.pos) + Vector2(1, -1).normalized() * out


## Where the diamond is: on its note while docked, else out on the surface.
func handle_screen_pos(surface: WaveSurface, owner: Note) -> Vector2:
	return dock_screen_pos(surface, owner) if attached else surface.to_screen(pos)


## A faint ring at its reach, where its waves fade to 0.
func draw_limit_ring(surface: WaveSurface, owner: Note, editing: bool) -> void:
	var r := reach() * surface.z()
	var c := surface.to_screen(world_pos(owner))
	if Rect2(Vector2.ZERO, surface.size).grow(r).has_point(c):
		var a := 0.55 if editing else (0.16 if own_reach > 0.0 else 0.11)
		surface.draw_arc(c, r, 0.0, TAU, maxi(64, int(r / 6.0)), Color(Palette.YELLOW, a), 2.0 if editing else 1.0, true)


## The dashed line from a detached emitter back to its relay.
func draw_tether(surface: WaveSurface, owner: Note) -> void:
	var a := surface.to_screen(owner.pos)
	var b := surface.to_screen(pos)
	var col := Color(Palette.channel_color(owner.channel), 0.4)
	var length := a.distance_to(b)
	if length < 1.0:
		return
	var dir := (b - a) / length
	var t := Note.RADIUS + 4.0
	while t < length - HANDLE_RADIUS:
		surface.draw_line(a + dir * t, a + dir * minf(t + 6.0, length - HANDLE_RADIUS), col, 1.0, true)
		t += 11.0


## The dim handle left on the note while the diamond is out on the surface.
func draw_dock(surface: WaveSurface, at: Vector2, hovered: bool) -> void:
	var r := HANDLE_RADIUS - 1.0 + (2.0 if hovered else 0.0)
	var pts := PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0), at + Vector2(0, -r)])
	surface.draw_polyline(pts, Color(Palette.YELLOW, 0.55 if hovered else 0.32), 1.0, true)


func draw_handle(surface: WaveSurface, at: Vector2, col: Color, hovered: bool) -> void:
	var r := HANDLE_RADIUS + (2.0 if hovered else 0.0)
	var pts := PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)])
	surface.draw_colored_polygon(pts, Palette.GLASS.lerp(Palette.YELLOW, 0.35 if hovered else 0.15))
	pts.append(pts[0])
	surface.draw_polyline(pts, Color(Palette.YELLOW, 0.95 if hovered else 0.75), 1.5, true)
	surface.draw_circle(at, 1.6, Color(col, 0.9))


## Refills clockwise from the top while cooling down, and flashes on fire.
func draw_pulse_ring(surface: WaveSurface, p: Vector2, now: int) -> void:
	var ring_r := Note.RADIUS + 5.0
	var charged := 1.0
	if now < ready_at:
		charged = 1.0 - float(ready_at - now) / float(maxi(cooldown_usec(), 1))
	var pf := pulse_flash
	surface.draw_arc(p, ring_r, 0.0, TAU, 48, Color(1, 1, 1, 0.08), 2.0, true)
	surface.draw_arc(p, ring_r, -PI / 2.0, -PI / 2.0 + TAU * clampf(charged, 0.0, 1.0), 48,
			Color(Palette.YELLOW, 0.55 + 0.45 * pf), 2.0, true)
	if pf > 0.0:
		surface.draw_arc(p, ring_r + 8.0 * (1.0 - pf), 0.0, TAU, 48, Color(Palette.YELLOW, 0.5 * pf), 2.0, true)
