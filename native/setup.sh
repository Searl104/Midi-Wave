#!/usr/bin/env bash
# Fetches the native dependencies. Run from the native/ folder.
set -euo pipefail
cd "$(dirname "$0")"

GODOT_CPP_BRANCH="${GODOT_CPP_BRANCH:-4.4}"   # match (or stay below) your Godot editor version
RTMIDI_TAG="${RTMIDI_TAG:-6.0.0}"

[ -d godot-cpp ] || git clone --depth 1 --branch "$GODOT_CPP_BRANCH" https://github.com/godotengine/godot-cpp.git
[ -d rtmidi ]    || git clone --depth 1 --branch "$RTMIDI_TAG" https://github.com/thestk/rtmidi.git

echo "Done. Now build with:  scons target=template_debug"
