class_name RelayModifier
extends Modifier
## Fires a new wave from its Emitter when a hit gets through, so waves can chain and loop. Sound
## says whether the note also plays; with it off the note is silent and hollow, its pitch kept.
## Its tab is the diamond, or the dim handle left on the note while the diamond is remote.

var emitter := Emitter.new()
var sound := true


func kind() -> String:
	return "relay"


func ring_id() -> String:
	return "relay_settings"


func order() -> int:
	return 1


func load_dict(d: Dictionary, p: Vector2) -> void:
	sound = bool(d.get("sound", true))
	emitter.load_dict(d, p)


func to_dict() -> Dictionary:
	var d := {"kind": kind(), "sound": sound}
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
