# MIDI Wave (Godot 4)

A liquid surface you play with waves. Click anywhere to send a ripple; every note it reaches
fires a MIDI note, with velocity set by how strong the wave still is when it arrives.

## Playing

| Action | What it does |
|---|---|
| Click | Send a wave from that point (clicking a note sends one from the note) |
| Drag a note | Move it |
| Right-click a note | Pitch ring: outer ring = scale notes, inner ring / mouse wheel = octave, centre = delete |
| Right-click empty space | Pitch ring that places a new note where you clicked |
| Alt-click a note | Channel ring (1-16); notes are colored by channel |
| Shift-click | Place a note with the last pitch and channel |
| Middle-click / Delete | Remove the hovered note |
| Tab or O | Options · Esc closes menus |

Options: MIDI output port (remembered and reopened on launch), wave strength, speed,
reach (distance where it fades to 0), falloff curve, note length, root and scale.
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

A wave's radius grows at *speed*. Its amplitude at distance *d* is
`strength × (1 − d / reach) ^ curve`, reaching 0 at *reach*. When the ring passes a note, the note plays
once per wave at velocity `amplitude × 127`, and turns off after *note length*.
