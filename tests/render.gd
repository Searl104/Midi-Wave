extends Node
## Renders a fixed surface (notes, relays, toggles, grids, waves, selection, a drag) to the file
## given after `--`, so drawing can be compared before and after a change. Needs a display.

const DT := 1.0 / 60.0


func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	Midi.log_when_closed = false
	get_window().size = Vector2i(1280, 800)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.size = Vector2(1280, 800)
	add_child(bg)
	var s := WaveSurface.new()
	add_child(s)
	s.size = Vector2(1280, 800)
	s.clear_notes()
	var a := s.add_note_at(Vector2(200, 200), 60, 0)
	var b := s.add_note_at(Vector2(400, 200), 64, 2)
	var c := s.add_note_at(Vector2(600, 200), 67, 12)
	var r := s.add_note_at(Vector2(300, 400), 72, 1)
	s.add_modifier(r, "relay")
	s.add_modifier(r, "silent")
	s.set_cooldown(r, 4.0)
	var r2 := s.add_note_at(Vector2(700, 400), 72, 5)
	s.add_modifier(r2, "relay")
	s.add_modifier(r2, "silent")
	var sounding := s.add_note_at(Vector2(520, 500), 69, 4)
	s.add_modifier(sounding, "relay")
	s.add_modifier(sounding, "sequence")
	s.add_modifier(b, "sequence")
	s.add_modifier(c, "sequence")
	s.set_sequence_count(c, 7)
	s.set_sequence_step(c, 0, false)
	s.set_sequence_step(c, 3, false)
	s.set_binding(a, "kp3")
	s.set_binding(c, "midi36")
	s.set_cooldown(r2, 1.0)
	s.get_note(r2).muted = true
	_detach(s, r2, Vector2(900, 550))
	_grid(s, a, -1)
	_grid(s, -1, r2)
	var off := s.add_note_at(Vector2(640, 100), 69, 3)
	s.spawn_wave(Vector2(500, 300))
	s.trigger_note(r)
	for i in 40:
		s.step(DT)
	s.pan_by(Vector2(-60, -30))
	s.get_note(off).pos = Vector2(5000, 300)
	s.trigger_note(off)
	s.selection.select_in_rect(Rect2(150, 150, 120, 120))
	s.selection.emitters[r2] = true
	s.effects.flash_brackets(s.get_note(b))
	s.set_pointer(Vector2(700, 350))
	s.drag.begin(b, "note", Vector2(400, 200))
	s.drag.moved = true
	s.drag.move_to(Vector2(520, 330), false)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit(0)


func _detach(s: WaveSurface, id: int, world: Vector2) -> void:
	s.drag.begin(id, "emitter", Vector2.ZERO)
	s.drag.moved = true
	s.drag.move_to(s.to_screen(world), true)
	s.drag.end()


func _grid(s: WaveSurface, note: int, handle: int) -> void:
	s.snapping.toggle_grid(s.get_note(handle if note == -1 else note), note == -1)
