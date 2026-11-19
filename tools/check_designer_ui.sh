#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
preview_root="$(mktemp -d -t colony-designer-XXXXXX)"
trap 'rm -rf "$preview_root"' EXIT
source "$project_root/tools/test_project.sh"
prepare_test_project "$project_root" "$preview_root"
export COLONY_SOURCE_REVISION="$(git -C "$project_root" rev-parse HEAD)"
export COLONY_CAPTURE_DIR="${COLONY_OUTPUT_ROOT:-/tmp/colony-validation}/designer"
mkdir -p "$COLONY_CAPTURE_DIR"
if ! godot --path "$preview_root/project" --display-driver x11 --audio-driver Dummy --resolution 1280x720 --fixed-fps 30 --quit-after 3600 --write-movie "$preview_root/designer.avi" res://tests/designer_visual.tscn > "$preview_root/ui.log" 2>&1; then cat "$preview_root/ui.log"; exit 1; fi
cat "$preview_root/ui.log"
if rg -q 'SCRIPT ERROR|UI FAIL|leaked' "$preview_root/ui.log" || ! rg -q '^UI TESTS PASS$' "$preview_root/ui.log"; then exit 1; fi
ffmpeg -hide_banner -loglevel error -y -i "$preview_root/designer.avi" -c:v libx264 -crf 18 -pix_fmt yuv420p -c:a aac "$COLONY_CAPTURE_DIR/designer.mp4"
