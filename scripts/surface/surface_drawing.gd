class_name SurfaceDrawing
extends RefCounted
## Draws the surface in order: reach glow, guides, waves, tethers, notes, handles, brackets and
## overlays. It paints onto the WaveSurface, which calls `draw()` from its own `_draw`.

var surface: WaveSurface
var _glow_tex: GradientTexture2D
var _glow_curve := -1.0            # falloff curve the glow texture was built for


func _init(owner_surface: WaveSurface) -> void:
	surface = owner_surface


func draw() -> void:
	var font := surface.get_theme_default_font()
	var now := surface.clock_usec
	var margin := Note.RADIUS + 40.0
	var dragging_item: bool = not surface.drag.info.is_empty() and not surface.drag.info.get("range_edit", false)

	if surface.pointer_inside() and not surface.tools.current.navigates():
		_reach_glow(surface.pointer())
	for o in surface.notes:
		if o.relay():
			o.emitter().draw_limit_ring(surface, o, surface.drag.editing_reach_of(o.id))

	if dragging_item:
		surface.drag.draw_rings()
	else:
		# Grids that are on stay faintly visible when nothing is being dragged.
		var grids := surface.snapping.active_grids()
		for key in grids:
			Grid.draw_guide(surface, grids[key][1], 0.32 * Settings.guide_brightness, Settings.guide_divisions, grids[key][2])

	for w in surface.waves:
		w.draw(surface)
	surface.effects.draw_splashes(surface)

	# Tethers and diamonds out on the surface sit under the notes.
	for o in surface.notes:
		var e: Emitter = o.emitter()
		if e and not e.attached:
			e.draw_tether(surface, o)
			e.draw_handle(surface, surface.to_screen(e.pos), Palette.channel_color(o.channel), o.id == surface.hovered_handle())

	for o in surface.notes:
		if surface.is_on_screen(o.pos, margin):
			o.draw(surface, font, now)
		else:
			o.draw_edge_marker(surface)

	# Docked diamonds, or the dim handle left on the note, go over every note.
	for o in surface.notes:
		var e: Emitter = o.emitter()
		if e == null:
			continue
		var hp: Vector2 = e.dock_screen_pos(surface, o)
		if hp.x > -40.0 and hp.y > -40.0 and hp.x < surface.size.x + 40.0 and hp.y < surface.size.y + 40.0:
			if e.attached:
				e.draw_handle(surface, hp, Palette.channel_color(o.channel), o.id == surface.hovered_handle())
			else:
				e.draw_dock(surface, hp, o.id == surface.hovered_handle())

	# Hover and selection are boxes (white corner brackets), so rings only ever mean state.
	for o in surface.notes:
		if not surface.is_on_screen(o.pos, margin):
			continue
		if surface.selection.notes.has(o.id):
			brackets(surface.to_screen(o.pos), o.bracket_half() + 2.0, 2.0, 0.95, 0.42)
		elif o.id == surface.hovered_note() and not surface.drag.active():
			brackets(surface.to_screen(o.pos), o.bracket_half(), 1.0, 0.55, 0.28)
	for eid in surface.selection.emitters:
		var en := surface.get_note(eid)
		if en and en.emitter():
			brackets(en.emitter().handle_screen_pos(surface, en), Emitter.HANDLE_RADIUS + 6.0, 2.0, 0.95, 0.42)
	surface.effects.draw_bracket_flashes(surface)
	surface.tools.draw_overlay(surface)

	if not surface.drag.info.is_empty():
		surface.drag.draw_readout(font)
	elif surface.hovered_note() != -1 and not surface.drag.active():
		var hovered := surface.get_note(surface.hovered_note())
		if hovered:
			hovered.draw_tooltip(surface, font)


## Faint glow under the pointer showing how far a wave from here reaches and how it fades:
## brightness follows the wave's amplitude (strength x falloff curve) out to its reach.
func _reach_glow(at: Vector2) -> void:
	var g: float = Settings.cursor_glow        # Options -> Wave -> Cursor glow (0 = off)
	if g <= 0.0:
		return
	var reach := Settings.wave_range * surface.z()
	surface.draw_texture_rect(_reach_texture(), Rect2(at - Vector2(reach, reach), Vector2(reach, reach) * 2.0),
			false, Color(1, 1, 1, minf(0.2 * Settings.wave_strength * g, 1.0)))
	surface.draw_arc(at, reach, 0.0, TAU, maxi(64, int(reach / 6.0)), Color(Palette.ACCENT, minf(0.10 * g, 1.0)), 1.0, true)


func _reach_texture() -> GradientTexture2D:
	if _glow_tex == null or not is_equal_approx(_glow_curve, Settings.falloff_curve):
		_glow_curve = Settings.falloff_curve
		var g := Gradient.new()
		var offsets := PackedFloat32Array()
		var colors := PackedColorArray()
		for i in 17:
			var t := i / 16.0
			offsets.append(t)
			colors.append(Color(Palette.ACCENT.lightened(0.15), pow(1.0 - t, _glow_curve)))
		g.offsets = offsets
		g.colors = colors
		_glow_tex = GradientTexture2D.new()
		_glow_tex.gradient = g
		_glow_tex.width = 256
		_glow_tex.height = 256
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1.0, 0.5)
	return _glow_tex


## Four white corner brackets around `at`. `arm` is each bracket's length as a share of the side.
func brackets(at: Vector2, half: float, width: float, alpha: float, arm: float) -> void:
	var col := Color(1, 1, 1, alpha)
	var l := half * 2.0 * arm
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var c := at + Vector2(sx, sy) * half
			surface.draw_polyline(PackedVector2Array([c - Vector2(sx * l, 0), c, c - Vector2(0, sy * l)]), col, width, true)
