class_name Note
extends SurfaceObject
## Plays its pitch when a wave hits it.


func _act(surface: WaveSurface, amp: float, now: int, _spawned: Array) -> void:
	play(surface, amp, now)


## A click sends a wave from where the note sits.
func clicked(surface: WaveSurface) -> void:
	surface.add_wave(Wave.new(pos, Settings.wave_strength, -1))
