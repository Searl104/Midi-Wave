class_name MidiInputControls
extends VBoxContainer
## Picks the MIDI controller. It's in Options and the Bind tool panel; copies stay in step through
## Settings.

var _ports: OptionButton
var _status: Label


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_ports = OptionButton.new()
	_ports.clip_text = true
	_ports.fit_to_longest_item = false
	_ports.focus_mode = Control.FOCUS_NONE
	_ports.tooltip_text = "The controller whose Note On events can fire bindings."
	_ports.item_selected.connect(func(i: int) -> void:
		Settings.set_value("midi_in_port", "" if i == 0 else _ports.get_item_text(i)))
	add_child(_ports)
	var row := HBoxContainer.new()
	add_child(row)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_status.add_theme_font_size_override("font_size", 12)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_status)
	row.add_child(PanelBuilder.button("Refresh", refresh, "Looks for connected MIDI controllers."))
	add_child(PanelBuilder.hint("The Bind tool links a note to any Note On from this controller. Windows lets only one app open a controller, so turn it off in your DAW's MIDI inputs first."))
	refresh(Settings.midi_in_port != "")          # listing opens every input, so only on request
	Settings.changed.connect(_on_setting)


func _on_setting(key: String) -> void:
	if key == "midi_in_port":
		refresh(Settings.midi_in_port != "" or _ports.item_count > 1)


func refresh(listing: bool = true) -> void:
	_ports.clear()
	_ports.add_item("Off")
	var names: PackedStringArray = MidiInput.list_inputs() if listing else PackedStringArray()
	for n in names:
		_ports.add_item(n)
	var at := names.find(Settings.midi_in_port)
	_ports.select(at + 1 if at != -1 else 0)
	if Settings.midi_in_port == "":
		_status.text = "Off · Refresh lists your controllers" if _ports.item_count <= 1 else "Off"
	else:
		_status.text = "Listening to %s" % Settings.midi_in_port
