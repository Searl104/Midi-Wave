class_name Relay
extends SurfaceObject
## Silent: a hit fires a new wave from its emitter, so waves can chain and loop. Its pitch is
## hidden and kept for switching back to a Note.


func _mode() -> int:
	return Mode.RELAY


func _act(surface: WaveSurface, _amp: float, now: int, spawned: Array) -> void:
	emitter.fire(surface, self, now, spawned)


## A click fires it directly, with no click wave.
func clicked(surface: WaveSurface) -> void:
	surface.trigger_note(id)


## It has no sound of its own, so a tap fires it, as a click does.
func tap(surface: WaveSurface) -> void:
	surface.trigger_note(id)


func shows_pitch() -> bool:
	return false


func _title_text() -> String:
	return "relay · ch %d" % (channel + 1)


func _pulse_text() -> String:
	return " · retrigger" if emitter.is_retrigger() else ""


func _reach_text() -> String:
	if emitter.own_reach > 0.0:
		return " · reach " + Snapping.format_beats(emitter.own_reach / Settings.BEAT_UNIT)
	return ""


func _bracket_margin() -> float:
	return 11.0


func _hollow() -> bool:
	return true


func _draw_pulse_ring(surface: WaveSurface, p: Vector2, now: int) -> void:
	emitter.draw_pulse_ring(surface, p, now)
