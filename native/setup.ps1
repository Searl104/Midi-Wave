# Fetches the native dependencies. Run from the native\ folder.
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$GodotCppBranch = if ($env:GODOT_CPP_BRANCH) { $env:GODOT_CPP_BRANCH } else { "4.4" }
$RtMidiTag      = if ($env:RTMIDI_TAG) { $env:RTMIDI_TAG } else { "6.0.0" }

if (-not (Test-Path godot-cpp)) { git clone --depth 1 --branch $GodotCppBranch https://github.com/godotengine/godot-cpp.git }
if (-not (Test-Path rtmidi))    { git clone --depth 1 --branch $RtMidiTag https://github.com/thestk/rtmidi.git }

Write-Host "Done. Now build with:  scons target=template_debug"
