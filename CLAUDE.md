# MIDI Wave: notes for Claude

Godot 4.7.2 app: a liquid surface where waves trigger MIDI notes. The user runs it on Windows with loopMIDI.
The spec lives in the editable doc **MIDI Wave Spec**: https://claude.ai/artifact/9KPPqbxemAgocHncR9TQVA
(the claude.ai project file `claude/midi-wave-spec.md` only points there). Read it before changing behavior.

A **Sound** is one of 16 numbered colours with a MIDI output, which notes are assigned to. Code and saves call
this `channel`, and every note is sent on real MIDI channel 1 of its Sound's port.

## Dev environment setup

**Editor.** Godot 4.7.2 stable, GL Compatibility renderer. `project.godot` carries the `4.7` feature tag.
godot-cpp is still pinned to `4.4` (see below), because it has no 4.6 or 4.7 branch yet. Open the repo folder
as a project and run `scenes/main.tscn` (the main scene). The two autoloads are `Settings`
(`scripts/core/settings.gd`) and `Midi` (`scripts/midi/midi_out.gd`).

**Native extension (only when touching `native/`).** The app runs without it, but then it only logs MIDI
messages instead of sending them. To build it:

```sh
cd native
./setup.sh        # Windows: .\setup.ps1. Clones godot-cpp and RtMidi into native/ (both gitignored)
scons target=template_debug
scons target=template_release
```

- `setup.sh` pins godot-cpp to branch `4.4` and RtMidi to tag `6.0.0`. Override with `GODOT_CPP_BRANCH` and
  `RTMIDI_TAG`; keep godot-cpp at or below the editor version.
- Tools: `scons` and a C++ toolchain. A native Linux build also needs the ALSA headers (`libasound2-dev`).
  Cross-compiling the Windows DLLs needs `g++-mingw-w64-x86-64-posix` (see the next section).
- Output goes to `addons/midi_out/bin/libmidiout.<platform>.<target>.<arch>`. Only the Windows DLLs are tracked.

**Local files that stay out of git:** `.godot/`, `*.uid`, `/icon.svg.import`, `native/godot-cpp/`, `native/rtmidi/`,
build objects and Linux/macOS libraries.

**Running with real MIDI (the user's setup, Windows).** Create a loopMIDI port, pick it for a Sound in
Options → MIDI, and enable the same port as an input on an armed instrument track in the DAW.
Settings and the note layout save to `%APPDATA%\Godot\app_userdata\MIDI Wave\settings.cfg`. This cloud
environment has no MIDI hardware, so MIDI behavior can't be heard here; check it by reading the code and
the logged messages, and say so when something couldn't be tested.

## Required reading

Before starting work, read the claude.ai project doc **Working with Direction**
(`claude/working-with-direction.md`), which covers how decisions, requests and testing work here.
Open issues are in `claude/open-issues.md`.

## Keep the Windows DLLs built and committed

The MIDI output extension's Windows DLLs are committed in `addons/midi_out/bin/`, so a fresh clone works
in the Godot editor and exports on Windows without building anything. **Whenever anything in `native/` changes,
or godot-cpp / RtMidi are bumped, rebuild both DLLs and commit them in the same change:**

```sh
cd native
./setup.sh
scons platform=windows use_mingw=yes target=template_debug     # used by the editor
scons platform=windows use_mingw=yes target=template_release   # used by exports
```

Needs `g++-mingw-w64-x86-64-posix` and `scons`. Linux `.so` files stay gitignored.

## Branches

Work on `claude_dev` only: commit and push there, and open pull requests from `claude_dev` into `main`.
**Never commit or push to `main`**; the user merges pull requests.
