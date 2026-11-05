class_name PanelBuilder
extends RefCounted
## The controls the Options panel and tool panels are made of. Most edit one Settings key, and take
## their tooltip from TIPS, so a setting reads the same wherever it appears.

const TIPS := {
	"wave_strength": "How strong a wave starts, which sets velocity. Also the strength of taps and bindings.",
	"wave_range": "How far a wave travels before fading to nothing. Relays can set their own.",
	"falloff_curve": "How a wave fades with distance. 1 is even; higher drops faster near its source.",
	"velocity_stamp": "The velocity a click gives a note, as a share of the wave that hits it.",
	"note_beats": "How long notes are held, in eighth notes up to a 4-beat measure. Follows the tempo.",
	"bpm": "Beats per minute. Wave speed follows it, so the layout stays in time.",
	"divisions": "How many timing rings fall within each beat, and so how fine snapping is.",
	"beat_spacing": "Screen pixels per beat. Scales distances, not icons or timing.",
	"root_note": "The scale's starting note, for the pitch ring. Existing notes keep their pitch.",
	"scale_name": "The notes the pitch ring offers and nudges land on. Existing notes keep their pitch.",
	"hover_preview": "Plays each pitch as the pointer moves onto it in the pitch ring.",
	"colorblind": "Uses eight colour-blind safe sound colours; sounds 9-16 add a double outline.",
	"cursor_glow": "How bright the glow is that shows a wave's reach under the pointer. 0 hides it.",
	"look": "The surface drawn under the notes.",
	"snap_enabled": "Dragged items and new notes land on grid points. Hold Alt to place freely.",
	"snap_distance": "How close, in screen pixels, an item must be to snap.",
	"snap_spokes": "Snap to a grid's spokes as well as its rings.",
	"snap_centres": "Snap exactly onto a note or emitter when dragged over it.",
	"spoke_count": "How many straight lines radiate from each grid.",
	"guides_to_edge": "How far the rings around a dragged item run. A grid's own reach still applies.",
	"guide_divisions": "Show the faint rings between beats.",
	"guide_brightness": "How bright grid and drag guides are.",
	"abyss_sink": "How fast marine snow sinks.",
	"abyss_density": "How much marine snow there is.",
	"abyss_glints": "How many bright specks glint in the water.",
	"abyss_shafts": "How strong the light shafts are.",
	"abyss_depth": "How fast things shrink as they sink. Higher feels deeper.",
	"abyss_refraction": "How much ripples bend the view below.",
	"tidal_color": "How much of the sand's colour shows. 0% gives black sand.",
	"tidal_caustics": "How bright the caustic light is.",
	"tidal_caustic_scale": "How large the caustic pattern is.",
	"tidal_caustic_speed": "How fast the caustic light moves.",
	"tidal_scale": "How large the sand ripples are.",
	"tidal_depth": "How far the sand moves when you pan. Lower feels deeper.",
	"tidal_shine": "How glossy the sand is.",
	"tidal_relief": "How deep the sand ripples look.",
	"tidal_refraction": "How much ripples bend the view of the sand.",
}


## "½ beat", "1 beat", "2½ beats".
static func beats_text(beats: float) -> String:
	var whole := floori(beats)
	var half := beats - whole >= 0.25
	var number := ("%d" % whole if whole > 0 else "") + ("½" if half else "")
	return number + (" beat" if beats <= 1.0 else " beats")


static func check(box: VBoxContainer, label: String, key: String) -> CheckButton:
	var c := CheckButton.new()
	c.text = label
	c.focus_mode = Control.FOCUS_NONE
	c.tooltip_text = TIPS.get(key, "")
	c.button_pressed = bool(Settings.get(key))
	c.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
	box.add_child(c)
	return c


static func pick(box: VBoxContainer, label: String, key: String, values: Array, labels: Array) -> OptionButton:
	var row := HBoxContainer.new()
	row.tooltip_text = TIPS.get(key, "")
	box.add_child(row)
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var o := OptionButton.new()
	o.tooltip_text = row.tooltip_text
	o.focus_mode = Control.FOCUS_NONE
	for t in labels:
		o.add_item(str(t))
	o.select(maxi(0, values.find(Settings.get(key))))
	o.item_selected.connect(func(i: int) -> void: Settings.set_value(key, values[i]))
	row.add_child(o)
	return o


static func section(box: VBoxContainer, text: String, col: Color) -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	box.add_child(gap)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var dot := ColorRect.new()
	dot.color = col
	dot.custom_minimum_size = Vector2(3, 14)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Palette.TEXT_DIM)
	row.add_child(l)


static func slider(box: VBoxContainer, label: String, key: String, min_v: float, max_v: float,
		step: float, fmt: Callable) -> HSlider:
	var row := HBoxContainer.new()
	row.tooltip_text = TIPS.get(key, "")
	box.add_child(row)
	var name_l := Label.new()
	name_l.text = label
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_l)
	var val_l := Label.new()
	val_l.add_theme_color_override("font_color", Palette.TEXT_DIM)
	row.add_child(val_l)
	var s := HSlider.new()
	s.tooltip_text = row.tooltip_text
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = Settings.get(key)
	s.focus_mode = Control.FOCUS_NONE
	val_l.text = fmt.call(s.value)
	s.value_changed.connect(func(v: float) -> void:
		val_l.text = fmt.call(v)
		Settings.set_value(key, v))
	box.add_child(s)
	return s


static func button(text: String, on_press: Callable, tip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	return b


static func hint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Palette.TEXT_DIM)
	l.add_theme_font_size_override("font_size", 12)
	return l
