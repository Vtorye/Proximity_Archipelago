#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/../.." && pwd)"
construction_root="$(mktemp -d -t colony-construction-ui-XXXXXX)"
trap 'rm -rf "$construction_root"' EXIT
source "$project_root/dev/tools/test_project.sh"
prepare_test_project "$project_root" "$construction_root"
godot_binary="${GODOT_BIN:-godot}"
export COLONY_CAPTURE_DIR="${COLONY_OUTPUT_ROOT:-/tmp/colony-validation}/construction"
export COLONY_SOURCE_REVISION="$(git -C "$project_root" rev-parse HEAD)"
mkdir -p "$COLONY_CAPTURE_DIR"
if ! "$godot_binary" --path "$construction_root/project" --display-driver x11 --audio-driver Dummy --resolution 1280x720 --fixed-fps 30 --quit-after 7200 --write-movie "$construction_root/construction.avi" res://dev/tests/construction_visual.tscn > "$construction_root/ui.log" 2>&1; then cat "$construction_root/ui.log"; exit 1; fi
cat "$construction_root/ui.log"
if rg -q 'SCRIPT ERROR|leaked|UI TESTS FAIL' "$construction_root/ui.log" || ! rg -q '^UI TESTS PASS$' "$construction_root/ui.log"; then exit 1; fi
ffmpeg -hide_banner -loglevel error -y -i "$construction_root/construction.avi" -vf 'scale=1280:720:flags=neighbor' -c:v libx264 -crf 20 -pix_fmt yuv420p -c:a aac -b:a 96k "$COLONY_CAPTURE_DIR/construction.mp4"

export COLONY_CAPTURE_DIR="${COLONY_OUTPUT_ROOT:-/tmp/colony-validation}/construction/compact"
mkdir -p "$COLONY_CAPTURE_DIR"
if ! "$godot_binary" --path "$construction_root/project" --display-driver x11 --audio-driver Dummy --resolution 960x600 --fixed-fps 30 --quit-after 7200 res://dev/tests/construction_visual.tscn > "$construction_root/compact.log" 2>&1; then cat "$construction_root/compact.log"; exit 1; fi
cat "$construction_root/compact.log"
if rg -q 'SCRIPT ERROR|leaked|UI TESTS FAIL' "$construction_root/compact.log" || ! rg -q '^UI TESTS PASS$' "$construction_root/compact.log"; then exit 1; fi

export COLONY_CAPTURE_DIR="${COLONY_OUTPUT_ROOT:-/tmp/colony-validation}/construction/regression"
mkdir -p "$COLONY_CAPTURE_DIR"
if ! "$godot_binary" --path "$construction_root/project" --display-driver x11 --audio-driver Dummy --resolution 1280x720 --fixed-fps 30 --quit-after 7200 --write-movie "$construction_root/interface.avi" res://dev/tests/ui_runner.tscn > "$construction_root/regression.log" 2>&1; then cat "$construction_root/regression.log"; exit 1; fi
cat "$construction_root/regression.log"
if rg -q 'SCRIPT ERROR|leaked|UI TESTS FAIL' "$construction_root/regression.log" || ! rg -q '^UI TESTS PASS$' "$construction_root/regression.log"; then exit 1; fi
ffmpeg -hide_banner -loglevel error -y -i "$construction_root/interface.avi" -vf 'scale=1280:720:flags=neighbor' -c:v libx264 -crf 20 -pix_fmt yuv420p -c:a aac -b:a 96k "$COLONY_CAPTURE_DIR/interface.mp4"
