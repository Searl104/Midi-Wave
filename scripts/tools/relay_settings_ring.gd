class_name RelaySettingsRing
extends RingTool
## A relay's tab opens this: a dial for its cooldown. Retrigger is at the start of the sweep, then
## ⅛ to 4 beats in eighth-beat steps. Turning it sets every selected relay, and one opening of
## the dial is one undo step.

const STEP := 0.125                ## beats between stops
const STOPS := 33                  ## Retrigger, then 1-32 eighths (⅛ to 4 beats)

var _turning := false              # an undo stroke is open for this opening of the dial


func tool_id() -> String:
	return "relay_settings"


func title() -> String:
	return "Relay"


## The cooldown in beats at stop `i`; stop 0 is Retrigger.
static func cooldown_at(i: int) -> float:
	return clampi(i, 0, STOPS - 1) * STEP


## The nearest stop to a cooldown. Older saves can hold values between stops, such as ⅓.
static func stop_for(cooldown: float) -> int:
	return clampi(roundi(cooldown / STEP), 0, STOPS - 1)


static func label(cooldown: float) -> String:
	if cooldown <= 0.0:
		return "Retrigger"
	var whole := floori(cooldown + 0.0001)
	var eighths := roundi((cooldown - whole) * 8.0)
	var frac := ""
	if eighths > 0:
		var g := 8
		while eighths % g != 0 or 8 % g != 0:
			g -= 1
		var key := "%d/%d" % [eighths / g, 8 / g]
		frac = Snapping.FRACTIONS.get(key, key)
	var text: String = (str(whole) + frac) if whole > 0 else frac
	if absf(cooldown - (whole + eighths / 8.0)) > 0.001:
		text = "≈ " + text                     # an older save's value between stops
	return text


func build() -> void:
	var o := surface.get_note(note_id)
	if o == null or o.relay() == null:
		return
	var e: Emitter = o.emitter()
	radial.outer_items = []
	radial.inner_items = []
	radial.center_item = {}
	radial.dial = true
	radial.dial_value = float(stop_for(e.cooldown)) / (STOPS - 1)
	radial.dial_text = label(e.cooldown)
	radial.dial_color = Palette.YELLOW
	radial.title = "Relay cooldown · beats, or Retrigger at the start"
	radial.subtitle = ""
	radial.refresh()


## Every selected relay, whether its note or its diamond is selected.
func _group() -> Array:
	var sel := surface.selection
	var ids: Array = sel.group_for(note_id)
	if sel.notes.has(note_id) or sel.emitters.has(note_id):
		for id in sel.emitters:
			if not ids.has(id):
				ids.append(id)
	return ids.filter(func(id: int) -> bool: return surface.get_note(id) != null and surface.get_note(id).relay() != null)


func pick_dial(value: float) -> void:
	if not _turning:
		_turning = true
		surface.history.end_group()
		surface.history.set_stroke(true)
	var c := cooldown_at(roundi(clampf(value, 0.0, 1.0) * (STOPS - 1)))
	for gid in _group():
		surface.set_cooldown(gid, c)
	build()


func ring_closed() -> void:
	if _turning:
		_turning = false
		surface.history.set_stroke(false)
		surface.history.end_group()
