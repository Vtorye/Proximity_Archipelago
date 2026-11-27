#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
task_root="$(mktemp -d -t colony-build-delivery-ui-XXXXXX)"
trap 'rm -rf "$task_root"' EXIT
source "$project_root/tools/test_project.sh"
prepare_test_project "$project_root" "$task_root"
export COLONY_SOURCE_REVISION="$(git -C "$project_root" rev-parse HEAD)"
for size in 1280x720 960x600; do
  export COLONY_CAPTURE_DIR="${COLONY_OUTPUT_ROOT:-/tmp/colony-validation}/build-delivery/$size"
  mkdir -p "$COLONY_CAPTURE_DIR"
  movie=()
  if [ "$size" = 1280x720 ]; then movie=(--write-movie "$task_root/build-delivery.avi"); fi
  if ! "${GODOT_BIN:-godot}" --path "$task_root/project" --display-driver x11 --audio-driver Dummy --resolution "$size" --fixed-fps 30 --quit-after 3000 "${movie[@]}" res://tests/build_delivery_visual.tscn > "$task_root/ui.log" 2>&1; then cat "$task_root/ui.log"; exit 1; fi
  cat "$task_root/ui.log"
  if rg -q 'SCRIPT ERROR|ERROR:|UI FAIL|leaked' "$task_root/ui.log" || ! rg -q '^UI TESTS PASS$' "$task_root/ui.log"; then exit 1; fi
done
ffmpeg -hide_banner -loglevel error -y -i "$task_root/build-delivery.avi" -c:v libx264 -crf 18 -pix_fmt yuv420p -an "${COLONY_OUTPUT_ROOT:-/tmp/colony-validation}/build-delivery/build-delivery.mp4"
