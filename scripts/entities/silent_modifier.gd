class_name SilentModifier
extends Modifier
## The note makes no sound, but still takes hits: sequences step on, a relay fires, bindings and
## taps count. Drawn hollow with its pitch hidden. It has no settings, so no ring or tab.


func kind() -> String:
	return "silent"


func order() -> int:
	return 2
