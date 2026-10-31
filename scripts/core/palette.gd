class_name Palette
extends RefCounted
## Glassy black/grey surfaces with primary-color accents.

const BG := Color(0.035, 0.038, 0.047)
const GLASS := Color(0.075, 0.08, 0.095)
const GLASS_LIGHT := Color(0.14, 0.15, 0.17)
const LINE := Color(1, 1, 1, 0.09)
const TEXT := Color(0.86, 0.88, 0.92)
const TEXT_DIM := Color(0.55, 0.58, 0.64)

const BLUE := Color(0.18, 0.48, 1.0)
const RED := Color(1.0, 0.25, 0.27)
const YELLOW := Color(1.0, 0.82, 0.2)

const ACCENT := BLUE   # waves, focus, sliders

## One color per MIDI channel: the three primaries first, then their blends, then lighter repeats.
const CHANNELS := [
	Color(0.18, 0.48, 1.0),   # 1  blue
	Color(1.0, 0.25, 0.27),   # 2  red
	Color(1.0, 0.82, 0.2),    # 3  yellow
	Color(0.2, 0.85, 0.95),   # 4  cyan
	Color(1.0, 0.45, 0.85),   # 5  magenta
	Color(1.0, 0.55, 0.15),   # 6  orange
	Color(0.35, 0.9, 0.45),   # 7  green
	Color(0.62, 0.45, 1.0),   # 8  violet
	Color(0.55, 0.75, 1.0),   # 9  light blue
	Color(1.0, 0.6, 0.6),     # 10 light red
	Color(1.0, 0.92, 0.6),    # 11 light yellow
	Color(0.6, 0.95, 1.0),    # 12 light cyan
	Color(1.0, 0.7, 0.92),    # 13 light magenta
	Color(1.0, 0.75, 0.5),    # 14 light orange
	Color(0.65, 1.0, 0.7),    # 15 light green
	Color(0.8, 0.7, 1.0),     # 16 light violet
]


static func channel_color(channel: int) -> Color:
	return CHANNELS[clampi(channel, 0, 15)]
