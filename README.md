# MIDI Wave (Godot 4)

A liquid surface you play with waves. Click anywhere to send a ripple; every note it reaches
fires a MIDI note, with velocity set by how strong the wave still is when it arrives.

## Playing

| Action | What it does |
|---|---|
| Click | Send a wave from that point. Clicking a plain note sends one from the note; clicking a pulser triggers it directly (sound + pulse, no click wave) |
| Drag a note | Move it |
| Hold right-click, hover, release | Quick place: pick a pitch and release to place a note there. On a note, retunes it; releasing on the centre deletes it |
| Right-click tap | Opens the same pitch ring and keeps it open for clicking |
| While the pitch ring is open | A / D or mouse wheel: octave · type 1-16: channel (1 then 2 = 12) · Esc: cancel |
| Alt-click a note | Channel ring (1-16); notes are colored by channel |
| Ctrl-click a note | Cycle Note → Note + Pulse → Pulse only (silent, hollow, no note label) |
| Ctrl + left-drag from a pulser or its emitter | Set that emitter's own wave reach: the drag distance, snapped to the timing divisions (Shift: free). Drag back onto the note to return to the global Reach. Applies to every selected pulser |
| Ctrl-right-click a note | Pulse ring: cooldown in beats, ⅛ to 4, or Retrigger (outer), emit strength (inner), mode (centre). Retrigger has no timer: the pulser fires on every wave that reaches it |
| Drag a pulser's diamond | Place where its wave starts (drop it back on the note to re-attach) |
| Shift-click | Place a note with the last pitch and channel |
| Middle-click / Delete | Remove the hovered note (Delete removes the selection, if any) |
| M | Mute / unmute the selected notes, or the hovered note. A muted note makes no sound but keeps its mode, so a muted pulser still pulses. Hollow notes show a bright centre dot when unmuted, a faint one when muted |
| Ctrl + right-drag on empty space | Box select notes (Shift adds to the selection); Esc or a click on empty space clears it |
| With a selection | Drag a selected note to move the whole group; channel, pulse, mode, modifier and keypad edits on a selected note apply to all of them; Ctrl+C / Ctrl+V copy and paste the group at the cursor |
| Middle-drag or arrow keys | Pan the view (the canvas is unbounded) · Home centres on the notes |
| While dragging a note or emitter | It shows its own timing rings. Touch another note or emitter to snap to its rings (touch again to drop it). Drag onto any note or emitter to snap to its centre. The target you were snapped to when you let go is remembered for the next drag. Shift places freely |
| Shift-right-click a note | Modifier ring: None / Toggle (outer), On / Off start state (inner) |
| Ctrl+S or Save state | Make every toggle's current state its start state |
| Space, KP0 or Stop | Clear all waves, return every toggle to its start state, ready every pulser |
| KP1–KP9 | Trigger every note assigned to that key on key down (a pulser fires directly; a plain note sends a wave from where it sits). Hold the key and its pulsers refire every time their cooldown runs out. Muted notes are skipped |
| Ctrl + KP1–KP9 over a note | Assign it to that key (again to unassign). A key can hold several notes; a badge shows the key |
| Tab or O | Options · Esc closes menus |

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
its own rings (bars brightest, beats bright, divisions faded); touching another note or emitter
toggles that object's rings on, and the dragged item snaps only to touched objects (within 12 screen px). The rings run out to the edges of the window, a little dimmer past the wave's reach, and you can snap to any of them. Each touched target also shows 8 spokes (every 45°); the dragged item snaps to a spoke, or to where a ring and a spoke cross. Centre snapping puts the item exactly on top of any note or emitter (touched or not) whose centre is within the snap distance, for stacking an emitter on a note or two emitters on one spot; it takes priority over rings and spokes.

**Options → Snap** sets: snapping on/off, snap distance, spoke snapping on/off, centre snapping on/off, spokes per target (none, 4, 8, 12, 16), guides to the window edge or only the wave's reach, division rings on/off, guide brightness, and whether the snap target is remembered on drop. Touches reset on drop, except the target the item was snapped to when dropped: it is remembered (separately for a note and its emitter, saved with the layout) and starts toggled on that item's next drag.

Notes off screen keep playing; a marker on the window edge shows them firing.

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
  ui/options_panel.gd     Options panel
  ui/glass_theme.gd       UI theme
shaders/water.gdshader    The liquid surface
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
