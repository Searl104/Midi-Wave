# MIDI Wave (Godot 4)

A liquid surface you play with waves. With the Tap tool, click empty space to send a ripple; every
note it reaches fires a MIDI note, with velocity set by how strong the wave still is when it
arrives. Click a note to play it alone.

## Toolbar

A strip on the left edge holds the tools. Left-click picks one. The layout is locked in Tap.

| Tool | Left click / drag |
|---|---|
| Tap | Empty space: start a wave. A note: play it alone, with no wave. Tapping counts as a hit, so sequences apply, and it overrides mute. A relay fires its pulse. Diamonds don't react: the click goes through to what's under them |
| Select and Move | Click a note or diamond to select it (Shift adds or removes); clicking one of a group narrows to it. Drag to move (Alt: free). Drag on empty space for a box (Shift adds). Ctrl-drag from a diamond sets its relay's reach |
| Draw | A ghost note shows the brush. Press to place a note, then drag to position it (Alt: free). Notes and diamonds can still be dragged. Ctrl-click a note copies it into the brush. Shift-click a note deletes it. Ctrl-drag from a diamond sets reach |
| Bind | Click a note to arm it, then press KP0-9 or hit a MIDI note. Delete clears its binding; Esc or empty space cancels |
| Grid | Click a note or remote diamond to add or remove a grid origin. Drag from it to set the grid's reach (Alt: unsnapped); back onto it returns to automatic |
| Paste Collection | Click to place the collection loaded from its panel, which clears it. Shift-click keeps it loaded (Alt: free) |
| Pan, Zoom | Drag to move the view, or to zoom about the pressed point (right or up zooms in) |

Pitch, Channel and Modifier sit on the bar too, but they aren't tools. Clicking one chooses which
ring a right-click on a note opens; a yellow bar marks the choice.

Middle-drag holds Pan and Shift + middle-drag holds Zoom, returning to the previous tool on release.
Tab flips between Tap and the previous tool. The tool and ring choice are remembered.

**Tool panels:** hovering a toolbar item that has options shows a faint right-click icon beside it.
Right-click to open its panel, just right of the toolbar and centred on the item. Hover any setting
for a tooltip on what it does. Click the item again, or anywhere outside, to close it; a click outside does nothing
else. Esc closes it too.

| Item | Panel |
|---|---|
| Tap | Wave strength, reach and falloff curve |
| Bind | MIDI input (also in Options) |
| Grid | Clear All, snapping, divisions per beat and guides |
| Paste Collection | Save the selection under a name, and the list of collections |
| Pitch | Root and scale. These set what the ring shows; existing notes keep their pitch |
| Channel | Default note length, and a Volume and a Length knob per channel. Volume scales velocity; Off silences notes, though relays still fire |
| Zoom | Beat spacing |

## Rings

| Right-click, in any tool but Tap | Opens |
|---|---|
| A modifier's tab | That modifier's settings |
| A note | The ring chosen on the bar |
| Empty space, in Draw | The chosen ring, set on the brush |

**Quick pick:** hold right-click, aim, and release to pick and close. Releasing off the rings cancels.
Right-click without moving to leave the ring open. Left-click picks and keeps it open; a click off
the rings closes it. Esc closes a ring.

- **Pitch:** scale notes (outer), octave (inner). An octave change keeps the note's letter. Hovering plays each pitch if **Options → General → Play notes while hovering** is on.
- **Channel:** 1-16.
- **Modifier:** None, Sequence and Relay. Picking one adds or removes it, and None clears them all.

Edits on a selected note apply to the whole selection. A pitch pick moves the others by the same
scale steps, so a chord keeps its shape; an octave moves them all. A note that would leave the MIDI range stays put. Relay settings also reach
selected diamonds.

## Collections

Select some notes, right-click Paste Collection, type a name and press Save. Each name can be used
once, ignoring case. A slash puts it in a folder, so `patterns/shaker01` saves `shaker01.json` in
`patterns`. Folders are made as needed, and go when their last collection is deleted. The name field
only takes characters a Windows file name can use. Drag a row onto the surface in any tool, or click it, then click the surface to place
it. Shift-click keeps it loaded to place more. Pasted notes keep their modifiers, bindings and grids, and become the selection, as one
undo step. Delete is in each row and asks first; it can't be undone.

Each collection is a JSON file in `user://collections`, which is
`%APPDATA%\Godot\app_userdata\MIDI Wave\collections` on Windows. Anything you move or rename there
shows in the list, as its path is its name. **Open Collections Folder** in the panel goes straight there.

## MIDI output

**Options → MIDI → MIDI Output** has 16 slots, one per note colour. Each has a dropdown of the
system's ports, and every note goes out on channel 1 of its slot's port, so one port carries one
voice. Slots can share a port, and None silences a slot. Picks are saved by port name. A port that
isn't there stays picked and is listed as not found, and Refresh opens it once it exists. Changing a
slot sends a Panic first, so nothing is left held. Volume and note length still go by colour.

## Keys

| Key | Action |
|---|---|
| Space, KP Enter | Stop: clear all waves and return sequences to step 1. Cooldowns keep running |
| KP0-9 | Fire that binding |
| Tab | Tap and the previous tool |
| M | Mute or unmute the selection, or the hovered note. Every tool |
| < / > (comma / period) | Nudge the selection, or the hovered note, a scale step; with Shift, an octave. Every tool |
| Ctrl+Z, Ctrl+Shift+Z or Ctrl+Y | Undo / redo (50 steps), in editing tools |
| Esc | Close a ring, cancel Bind, or clear the selection |
| Delete, Backspace | Remove the selection (Select and Move); clear the armed binding (Bind) |
| Ctrl+C, Ctrl+V | Copy and paste the selection at the pointer (Select and Move) |

## Modifiers

A note can hold several modifiers. Each has a tab, and right-clicking a tab opens its settings.
Removing a modifier discards its settings.

**Relay** makes a note send out its own wave when a wave hits it, at a fixed strength and at most
once per cooldown, so waves can chain and loop. Its tab is the emitter diamond.
- Settings: cooldown in beats (⅛ to 4, or Retrigger: no timer) on the outer ring, strength on the inner, and Sound or Silent in the centre. A new relay has Sound on, so the note still plays; Silent makes it hollow and keeps its pitch.
- The diamond docks upper right of the note. Dragged out, it stays at that spot and draws under the notes, with a dashed line and a dim handle left on the note. Dropped back on the note, it docks.
- An emitter on top of another note fires that note instantly.
- A new wave starts from where the hit really landed, so loops and chains hold their tempo at any frame rate.
- A hit up to 20 ms early still fires, so a cooldown equal to the time between hits doesn't skip any.
- The surface holds 64 waves; when it's full, relays skip a beat instead of removing waves.

**Sequence** is a list of up to 16 On and Off steps. Each hit takes the next step, and an Off step
silences its sound and pulse. It only decides whether the next activation sounds, as timing still
comes from the surface. A thin ring shows it, with a tab underneath. The tab's icon shows the
next step, with a carousel of dots through it: steps just played on the left and steps to come on the
right, blue for On and grey for Off, fading out so three show each side. Its settings ring
sets the number of steps on the inner ring and turns steps On or Off on the outer ring, clockwise
from the top. New steps start On. Stop returns it to step 1. Rests and Toggles in old saves load as
the same pattern, turned to start where they started.

**Mute** isn't a modifier: a muted note ignores waves, though a sequence on it still steps on. Tapping
it, or firing its binding, plays it anyway.

## Bindings

A note holds one binding: a keypad key (KP0-9) or a MIDI note, and many notes can share one. A badge
at the note's upper left shows it. A binding fires like a tap, in any tool. A press during a cooldown does nothing until it ends, and fires then if still held. A press on a relay in Tap waits the same way, and fires once. While it's held, relays
refire on their cooldown, except Retrigger ones. Older saves' keypad slots become KP1-9 bindings.

**Options → Controls** maps MIDI messages to Stop and Panic. Press Learn, then press a key,
pad or button, or move a knob, on the chosen controller. Notes, control changes and Start, Stop and
Continue can all be learned, on any channel, and a control change fires each time it rises above 0.
One message drives one action, so learning it again moves it. If notes are bound to the same MIDI
note, both fire, and the row says so. MIDI Stop runs Stop until you change it.

The Bind panel, or **Options → MIDI → MIDI input**, picks the controller. Any Note On from it can be bound, on any
channel; other inputs, including the loopMIDI port MIDI Wave sends to, are ignored. It uses Godot's
own MIDI input, which opens every input at once, so inputs stay closed while this is Off. Windows
lets only one app open a controller, so turn it off in your DAW's MIDI inputs first.

### Timing rings, tempo and zoom

Positions live in world units where one beat of space is 200 units, and waves cross one beat
of space per beat, so the layout stays in time at any tempo. **Beat spacing** is the zoom: it
sets how many screen pixels one beat takes up. Distances, waves, reach, rings and the reach glow
scale around the centre of the window, while notes, rings, tabs, handles and labels stay the same
size, and timing doesn't change. The look's background (Abyssal's depths, Tidal's sand) doesn't zoom;
only panning moves it. Reach is shown in beats. While you drag a note or emitter it shows
its own rings (bars brightest, beats bright, divisions faded).

**Grids.** The Grid tool puts a grid on a note or remote diamond: its timing rings plus 8 spokes
(every 45°, or 4, 6, 12 or 16). Grids are drawn faintly, with their division rings if Division rings
is on, and saved with the layout. Any number can be on, and Clear All in the Grid panel removes them.
A grid's reach is automatic until you drag it: a beat past the wave Reach, or a relay's own reach
for a remote diamond or a note with a docked relay. Nothing draws or snaps past it.

While dragging, the dragged item shows its own rings and snaps (within 12 screen px) to the nearest
grid point: where a ring crosses a spoke, else a spoke, else a ring. The Draw ghost and pasted notes
land on the nearest grid point. Centre snapping puts the item exactly on top of any note or emitter
whose centre is within the snap distance, ahead of grid points. Alt places freely.

The **Grid panel** sets: snapping on/off, snap distance, spoke snapping on/off, centre snapping on/off, spokes per grid (none, 4, 6, 8, 12, 16; 6 gives 60° lines), guides to the window edge or only the wave's reach, division rings on/off and guide brightness.

Touch to snap, the older way of picking snap targets (touch an object while dragging to snap to it), is deprecated and off by default. It has no Options control: set `touch_snap=true` in `settings.cfg` to bring it back, along with `snap_memory`.

Notes off screen keep playing; a marker on the window edge shows them firing.

A faint glow under the cursor shows how far a wave from there reaches and how it fades. **Options → Look → Cursor glow** sets its strength (0% hides it, up to 200%).

Hover a note to see its pitch and channel number. **Options → General → Colour-blind palette** swaps the 16 channel colours for eight colour-blind safe ones (Okabe-Ito); channels 9-16 reuse them with a second, inner outline.

Hover and selection are drawn as white corner brackets (thin for hover, bright for selected), so rings only ever mean state: pulse cooldown, modifier, snap guides. M, Delete and Ctrl+KP act on the bracketed note, and its brackets flash when the key lands.

**Surface looks** (Options → Look). The Look tab picks the look and shows its controls, each a percentage of the designed look (100%), with a reset button:
- Abyssal: sinking speed, marine snow, glints, light shafts, depth, refraction.
- Tidal: sand colour (0% = black sand), caustics, caustics scale, caustics speed, sand scale, floor parallax (how far the sand moves when you pan; lower feels deeper), shine, ripple relief, refraction.

- **Abyssal** (default): a thin glassy surface over endless dark water. Marine snow sinks away forever in parallax layers (deep layers move less when you pan), soft light shafts in three depth layers fall toward a dark vanishing point (each beam fades in and out on its own clock, sways and carries drifting specks; deeper layers are dimmer, bluer and pan less), and rare glints pulse far below in the primary colours. Ripples refract the depths, and a passing wave lights the snow under it.
- **Tidal**: dark, glossy sand ripples on a plane below the water, in the scan's own (darkened) colour, with caustic light dancing across them. The sand pans at 65% of the surface's rate, like a sea floor. Ripples refract it and passing waves make its highlights flare. Texture maps from Poly Haven's *Aerial Beach 01* (CC0).
- **Glass**: the original flat dark glass.

The **Channel panel** sets a volume and a note length per MIDI channel: drag or scroll a knob, and double-click to reset. Lengths run in eighth notes up to 4 beats.

Options, MIDI tab: output slots and MIDI input. General tab: hover preview,
tempo, colour-blind palette, and layouts. Settings that belong to a tool
are in its panel. The scale sets what the pitch ring shows, and a nudge lands on the current scale,
but changing it doesn't touch existing notes. Settings and the note layout save automatically to
`%APPDATA%\Godot\app_userdata\MIDI Wave\settings.cfg`.

## Routing on Windows

Run loopMIDI, create a port, pick it for a slot in Options → MIDI, and enable the same port as an
input on an armed instrument track in your DAW.

## Project layout

```
scenes/main.tscn
scripts/
  core/settings.gd        Autoload `Settings`: persisted options + note layout
  core/scales.gd          Scales and quantization
  core/palette.gd         Glassy greys + primary accents, per-channel colors
  midi/midi_out.gd        Autoload `Midi`: ports, note on/off, CC, panic
  midi/midi_message.gd    Raw MIDI byte helpers
  midi/midi_mappings.gd   MIDI messages that run app actions
  midi/midi_in.gd         Controller notes, control changes and transport (Godot's built-in MIDI input)
  entities/               note, emitter, wave, grid, modifier, relay_modifier, sequence_modifier
  surface/                undo_history, selection, snapping, surface_effects, demo_layout, collections
  tools/                  One script per tool and ring, plus tool_manager and object_drag
  ui/main.gd              Builds the scene and HUD
  ui/wave_surface.gd      Holds the view and entities, runs the simulation, draws in order
  ui/radial_menu.gd       The ring picker, with quick pick
  ui/toolbar.gd           The strip of tools and ring choices
  ui/tool_panel.gd        The popup that holds a tool's options
  ui/panel_builder.gd     Sliders, buttons and other controls for the panels
  ui/collection_row.gd    A row in Paste Collection's list
  ui/collection_folder.gd A folder in that list
  ui/knob.gd              A compact dial
  ui/options_panel.gd     Options panel
  ui/glass_theme.gd       UI theme
tests/                    Headless checks: baseline (MIDI and layouts), tools, demo; render
shaders/waves.gdshaderinc Ripple maths shared by the surface shaders
shaders/abyssal.gdshader  Abyssal surface: endless depth under the water
shaders/tidal.gdshader    Tidal surface: black glossy sand below the water
shaders/water.gdshader    Glass surface
assets/tidal/             Sand colour, normal + roughness maps (Poly Haven, CC0)
shaders/glass.gdshader    Frosted-glass panels
addons/midi_out/          GDExtension manifest + built libraries
native/                   C++ source of the MIDI output extension (RtMidi)
export_presets.cfg        Windows Desktop export
```

## Building

Extension (needed for real MIDI output; without it the app logs messages only):

```sh
cd native
./setup.sh                       # Windows: .\setup.ps1
scons target=template_debug
scons target=template_release
# Cross-compile for Windows from Linux:
scons platform=windows use_mingw=yes target=template_release
```

Export: open in Godot 4.4+, Project → Export → Windows Desktop. The extension DLL is copied next to the exe.

## How the wave works

A wave's radius grows at *speed* = 200 world units × BPM / 60 (one beat of space per beat; relay waves too). Distances below are in world units. Its amplitude at distance *d* is
`strength × (1 − d / reach) ^ curve`, reaching 0 at *reach*. When the ring passes a note, the note plays
once per wave at velocity `amplitude × 127` (at least 1), right out to the reach, and turns off after its note length, set in beats so it follows the tempo.
