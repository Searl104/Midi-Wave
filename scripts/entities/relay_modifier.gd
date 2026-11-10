class_name RelayModifier
extends Modifier
## Fires a new wave from its Emitter when a hit gets through, so waves can chain and loop. The note
## still plays; a SilentModifier stops that. Its tab is the diamond, or the dim handle left on the
## note while the diamond is remote. Older saves' "sound": false becomes a SilentModifier (Note).

var emitter := Emitter.new()


func kind() -> String:
	return "relay"


func ring_id() -> String:
	return "relay_settings"


func order() -> int:
	return 1


func load_dict(d: Dictionary, p: Vector2) -> void:
	emitter.load_dict(d, p)


func to_dict() -> Dictionary:
	var d := {"kind": kind()}
	d.merge(emitter.to_dict())
	return d


func live_state() -> Array:
	return [emitter.ready_at]


func restore_state(state: Array) -> void:
	emitter.ready_at = state[0]


func tick(delta: float) -> void:
	emitter.tick(delta)


func tab_contains(surface: WaveSurface, note: Note, at: Vector2) -> bool:
	var reach := Emitter.HANDLE_RADIUS + 4.0
	return at.distance_to(emitter.handle_screen_pos(surface, note)) <= reach \
			or at.distance_to(emitter.dock_screen_pos(surface, note)) <= reach
