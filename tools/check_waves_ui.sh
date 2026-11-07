#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
task_root="$(mktemp -d -t colony-waves-ui-XXXXXX)"
trap 'rm -rf "$task_root"' EXIT
python3 - "$project_root" "$task_root/project" <<'PY'
from pathlib import Path
import shutil,sys
source,target=map(Path,sys.argv[1:])
shutil.copytree(source,target,ignore=shutil.ignore_patterns('.git','.godot'))
p=target/'project.godot';p.write_text(p.read_text().replace('config/name="archipelago"','config/name="archipelago-waves-validation"'))
PY
if ! godot --headless --path "$task_root/project" --editor --quit > "$task_root/import.log" 2>&1; then cat "$task_root/import.log"; exit 1; fi
if rg -q 'SCRIPT ERROR|Parse Error|Failed to load' "$task_root/import.log"; then cat "$task_root/import.log"; exit 1; fi
export COLONY_SOURCE_REVISION="$(git -C "$project_root" rev-parse HEAD)"
for size in 1280x720 960x600; do
  export COLONY_CAPTURE_DIR="${COLONY_OUTPUT_ROOT:-/tmp/colony-validation}/waves/$size"
  mkdir -p "$COLONY_CAPTURE_DIR"
  movie=()
  if [ "$size" = 1280x720 ]; then movie=(--write-movie "$task_root/waves.avi"); fi
  if ! godot --path "$task_root/project" --display-driver x11 --audio-driver Dummy --resolution "$size" --fixed-fps 30 --quit-after 6000 "${movie[@]}" res://tests/waves_visual.tscn > "$task_root/ui.log" 2>&1; then cat "$task_root/ui.log"; exit 1; fi
  cat "$task_root/ui.log"
  if rg -q 'SCRIPT ERROR|ERROR:|UI FAIL|leaked' "$task_root/ui.log" || ! rg -q '^UI TESTS PASS$' "$task_root/ui.log"; then exit 1; fi
done
ffmpeg -hide_banner -loglevel error -y -i "$task_root/waves.avi" -c:v libx264 -crf 18 -pix_fmt yuv420p -an "${COLONY_OUTPUT_ROOT:-/tmp/colony-validation}/waves/waves.mp4"
