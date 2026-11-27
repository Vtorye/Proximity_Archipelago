#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
planning_root="$(mktemp -d -t colony-planning-ui-XXXXXX)"
trap 'rm -rf "$planning_root"' EXIT
source "$project_root/tools/test_project.sh"
prepare_test_project "$project_root" "$planning_root"
godot_binary="${GODOT_BIN:-godot}"
export COLONY_CAPTURE_DIR="${COLONY_OUTPUT_ROOT:-/tmp/colony-validation}/assignment"
export COLONY_SOURCE_REVISION="$(git -C "$project_root" rev-parse HEAD)"
mkdir -p "$COLONY_CAPTURE_DIR"
if ! "$godot_binary" --path "$planning_root/project" --display-driver x11 --audio-driver Dummy --resolution 1280x720 --fixed-fps 30 --quit-after 1800 --write-movie "$planning_root/planning.avi" res://tests/planning_visual.tscn > "$planning_root/ui.log" 2>&1; then cat "$planning_root/ui.log"; exit 1; fi
cat "$planning_root/ui.log"
if rg -q 'SCRIPT ERROR|leaked|UI TESTS FAIL' "$planning_root/ui.log" || ! rg -q '^UI TESTS PASS$' "$planning_root/ui.log"; then exit 1; fi
ffmpeg -hide_banner -loglevel error -y -i "$planning_root/planning.avi" -vf 'scale=1280:720:flags=neighbor' -c:v libx264 -crf 20 -pix_fmt yuv420p -c:a aac -b:a 96k "$COLONY_CAPTURE_DIR/planning.mp4"
