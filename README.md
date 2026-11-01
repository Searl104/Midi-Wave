# MIDI Wave (Godot 4)

A liquid surface you play with waves. Click anywhere to send a ripple; every note it reaches
fires a MIDI note, with velocity set by how strong the wave still is when it arrives.

## Playing

| Action | What it does |
|---|---|
| Click | Send a wave from that point. Clicking a plain note sends one from the note; clicking a pulser triggers it directly (sound + pulse, no click wave) |
| Drag a note | Move it |
| Hold right-click, hover, release | Quick place: pick a pitch and release to place a note there. On a note, retunes it; releasing on the centre deletes it. On any ring, releasing over an inner-ring item or the centre picks it and closes |
| Right-click tap | Opens the same pitch ring and keeps it open for clicking |
| Hovering the pitch ring | Plays each note as the pointer moves onto it, on the ring's channel (Options → General → Play notes while hovering the pitch ring turns it off) |
| C / E / F, then right-click a note | Summon the channel, pulse or modifier ring instead of pitch. Right-click always opens the active ring; pitch is the default, and a ring picked with a key is used once, then pitch returns. While the key is held it stays active for every right-click on a note, and letting go returns to pitch. Pressing the key again or Esc cancels |
| Left-click while a ring is open | Pick an item and keep the ring open for more picks (a new note is placed on the first pitch, then retuned by the next). A left click off the ring closes it. Left clicks never reach the surface while a ring is open |
| While the pitch ring is open | A / D, mouse wheel or the inner ring: octave (an edited note keeps its letter, e.g. C#, and moves to that octave) · type 1-16: channel (1 then 2 = 12; the title shows "ch 1…" while a second digit can follow) · Esc: cancel |
| Alt-click a note (alias for C) | Channel ring (1-16); notes are colored by channel |
| Ctrl-click a note | Cycle Note → Note + Pulse → Pulse only (silent, hollow, no note label) |
| Ctrl + left-drag from a pulser or its emitter | Set that emitter's own wave reach: the drag distance, snapped to the timing divisions (Shift: free). Drag back onto the note to return to the global Reach. Applies to every selected pulser |
| Ctrl-right-click a note (alias for E) | Pulse ring: cooldown in beats, ⅛ to 4, or Retrigger (outer), emit strength (inner), mode (centre). Retrigger has no timer: the pulser fires on every wave that reaches it |
| Drag a pulser's diamond | Place where its wave starts (drop it back on the note to re-attach) |
| Shift-click | Place a note with the last pitch and channel |
| Delete | Remove the hovered note (or the selection, if any) |
| M | Mute / unmute the selected notes, or the hovered note. A muted note makes no sound but keeps its mode, so a muted pulser still pulses. A muted note shows a slash; hollow (pulse-only) notes also show a bright centre dot when unmuted, a faint one when muted |
| Ctrl + right-drag on empty space | Box select notes (Shift adds to the selection); Esc or a click on empty space clears it |
| With a selection | Drag a selected note to move the whole group; channel, pulse, mode, modifier and keypad edits on a selected note apply to all of them; Ctrl+C / Ctrl+V copy and paste the group at the cursor |
| Middle-drag or arrow keys | Pan the view (the canvas is unbounded) · Home centres on the notes |
| G over a note or emitter | Turn a grid on or off under it: its timing rings and spokes, drawn faintly and saved with the layout. Any number can be on · Ctrl+G clears every grid |
| While dragging a note or emitter | It shows its own timing rings and snaps to the nearest grid point (a ring, a spoke, or where they cross). Drag onto any note or emitter to snap to its centre. Shift places freely |
| Placing new notes | Quick place, Shift-click and paste put the new note on the nearest grid point under the mouse (when any grid is on) |
| Shift-right-click a note (alias for F) | Modifier ring: None / Toggle (outer), On / Off start state (inner) |
| Ctrl+S or Save state | Make every toggle's current state its start state (a toast confirms it) |
| Ctrl+Z / Ctrl+Shift+Z (or Ctrl+Y) | Undo / redo layout edits (50 steps); edits made in one frame, like a group edit, are one step |
| Space, KP0 or Stop | Clear all waves, return every toggle to its start state. Cooldowns keep running, so a pulser that just fired still waits out its cooldown |
| KP1–KP9 | Trigger every note assigned to that key on key down (a pulser fires directly; a plain note sends a wave from where it sits). Hold the key and its pulsers refire every time their cooldown runs out. Muted notes are skipped |
| Pads on a MIDI controller | Fire keypad keys 1–9 like the numpad, including hold-to-refire (see MIDI input below) |
| Ctrl + KP1–KP9 over a note | Assign it to that key (again to unassign). A key can hold several notes; a badge shows the key |
| Tab | Switch Edit / Play mode. Play mode locks the layout: clicks send waves or trigger notes, the keypad, Space and panning work, but nothing can be moved, placed, retuned, muted, deleted or undone |
| O | Options · Esc closes menus |
| ? or F1 | All controls, grouped by task. The bar at the bottom of the window always shows the actions for whatever is under the mouse (empty space, a note, a pulser, a ◆, the selection, a drag) |

### Pulsers

A pulsing note sends out its own wave when a wave hits it, at its own fixed strength,
at most once per cooldown. Cooldowns are in beats (⅛ beat to 4 beats), so they follow the tempo, or Retrigger: no timer, fire on every wave that reaches it (an ⅛-beat floor still guards against runaway loops). It is never triggered by its own wave, so two
pulsers can keep a loop going until you stop it (Space). A pulser starts ready to fire.
Its emitter starts on the note; drag the diamond to start its waves somewhere else, and it
stays put when you move the note. An emitter on top of another note fires that note instantly.
The surface holds 64 waves; when it is full, pulsers skip a beat instead of removing waves.

### Modifier ring: toggle

A note can carry one modifier. The toggle switches the note off and on each time it is
triggered, so it plays every other hit; off silences both its sound and its pulse. A thin ring
in the channel colour shows it, with a tab underneath: ripples spreading out = on, still water
= off. A dot on the tab shows the start state when it differs. Any state you set by hand is the
note's start state; Save state copies all current states to their start states, and Stop returns
everything to them. Hover a note for its pitch, channel and toggle state.

### Timing rings, tempo and zoom

Positions live in world units where one beat of space is 200 units, and waves cross one beat
of space per beat, so the layout stays in time at any tempo. **Beat spacing** is the zoom: it
sets how many screen pixels one beat takes up. Distances, waves, reach, rings and the reach glow
scale around the centre of the window, while notes, rings, tabs, handles and labels stay the same
size, and timing doesn't change. Reach is shown in beats. While you drag a note or emitter it shows
its own rings (bars brightest, beats bright, divisions faded).

**Grids.** Press G over a note or emitter to put a grid under it: its timing rings plus 8 spokes
(every 45°, or 4, 6, 12 or 16). Grids that are on are drawn faintly and saved with the layout, any
number can be on at once, and Ctrl+G clears them all. While dragging, every grid lights up and the
dragged item snaps (within 12 screen px) to the nearest grid point: where a ring crosses a spoke,
else a spoke, else a ring. New notes from quick place, Shift-click or paste land on the nearest grid
point under the mouse. The rings run out to the edges of the window, a little dimmer past the
wave's reach. Centre snapping puts the item exactly on top of any note or emitter whose centre is
within the snap distance, for stacking an emitter on a note or two emitters on one spot; it takes
priority over grid points. Shift places freely. Grid toggles are undoable like any edit.

**Options → Snap** sets: snapping on/off, snap distance, spoke snapping on/off, centre snapping on/off, spokes per grid (none, 4, 6, 8, 12, 16; 6 gives 60° lines), guides to the window edge or only the wave's reach, division rings on/off and guide brightness.

Touch to snap, the older way of picking snap targets (touch an object while dragging to snap to it), is deprecated and off by default. It has no Options control: set `touch_snap=true` in `settings.cfg` to bring it back, along with `snap_memory`.

Notes off screen keep playing; a marker on the window edge shows them firing.

### MIDI input: pads fire the keypad

**Options → General → MIDI input (pads)** picks a controller (Refresh lists them). Its notes
C1–G#1 (36–44) fire keypad keys 1–9 the same way the numpad does: note-on presses the key and
note-off releases it, so holding a pad refires that key's pulsers. **Learn** sets key 1 to the next
pad you hit; the next eight notes are keys 2–9. Events from any other input, including the loopMIDI
port MIDI Wave sends to, are ignored. It uses Godot's own MIDI input, which opens every input at
once, so inputs stay closed while this is Off. Windows lets only one app open a controller, so
turn it off in FL Studio's MIDI inputs first.

Hover a note to see its pitch and channel number. **Options → General → Colour-blind palette** swaps the 16 channel colours for eight colour-blind safe ones (Okabe-Ito); channels 9-16 reuse them with a second, inner outline.

Hover and selection are drawn as white corner brackets (thin for hover, bright for selected), so rings only ever mean state: pulse cooldown, modifier, snap guides. M, Delete and Ctrl+KP act on the bracketed note, and its brackets flash when the key lands.

**Surface looks** (Options → Look). The Look tab picks the look and shows its controls, each a percentage of the designed look (100%), with a reset button:
- Abyssal: sinking speed, marine snow, glints, light shafts, depth, refraction.
- Tidal: sand colour (0% = black sand), caustics, caustics scale, caustics speed, sand scale, floor parallax (how far the sand moves when you pan or zoom; lower feels deeper), shine, ripple relief, refraction.

- **Abyssal** (default): a thin glassy surface over endless dark water. Marine snow sinks away forever in parallax layers (deep layers move less when you pan), faint light shafts converge on a dark vanishing point, and rare glints pulse far below in the primary colours. Ripples refract the depths, and a passing wave lights the snow under it.
- **Tidal**: dark, glossy sand ripples on a plane below the water, in the scan's own (darkened) colour, with caustic light dancing across them. The sand pans and zooms at 65% of the surface's rate, like a sea floor. Ripples refract it and passing waves make its highlights flare. Texture maps from Poly Haven's *Aerial Beach 01* (CC0).
- **Glass**: the original flat dark glass.

**Options → Channels** sets a note length per MIDI channel (Default follows the global Note length).

Options (General tab): MIDI output port (remembered and reopened on launch), tempo, beat spacing (zoom), divisions per beat,
wave strength, reach (distance where it fades to 0), falloff curve, note length, root and scale.
Changing the scale snaps every note to it. Settings and the note layout save automatically to
`%APPDATA%\Godot\app_userdata\MIDI Wave\settings.cfg`.

## Routing on Windows

Run loopMIDI, create a port, pick it in Options → MIDI Output, and enable the same port as an
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
  ui/main.gd              Builds the scene, wires radial menus to note edits
  ui/wave_surface.gd      Waves, hit detection, MIDI triggering, drawing
  ui/radial_menu.gd       Ring picker used for pitch and channel
  ui/cheat_sheet.gd       The ? / F1 overlay listing every control
  midi/midi_in.gd         Controller pads -> keypad slots (Godot's built-in MIDI input)
  ui/options_panel.gd     Options panel
  ui/glass_theme.gd       UI theme
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

A wave's radius grows at *speed* = 200 world units × BPM / 60 (one beat of space per beat; pulser waves too). Distances below are in world units. Its amplitude at distance *d* is
`strength × (1 − d / reach) ^ curve`, reaching 0 at *reach*. When the ring passes a note, the note plays
once per wave at velocity `amplitude × 127`, and turns off after *note length*.
