# MIDI Wave: notes for Claude

Godot 4.4 app: a liquid surface where waves trigger MIDI notes. The user runs it on Windows with loopMIDI.
The spec lives in the claude.ai project doc `claude/midi-wave-spec.md`.

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
