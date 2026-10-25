#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
ui_root="$(mktemp -d -t colony-ui-XXXXXX)"
trap 'rm -rf "$ui_root"' EXIT
python3 - "$project_root" "$ui_root/project" <<'PY'
import shutil, sys
from pathlib import Path
source, destination = map(Path, sys.argv[1:])
shutil.copytree(source, destination, ignore=shutil.ignore_patterns('.git', '.godot', 'evidence'))
project = destination / 'project.godot'
project.write_text(project.read_text().replace('config/name="archipelago"', 'config/name="archipelago-ui-validation"'))
PY
godot_binary="${GODOT_BIN:-godot}"
"$godot_binary" --headless --path "$ui_root/project" --editor --quit > "$ui_root/import.log" 2>&1
mkdir -p "$project_root/evidence/after"
export COLONY_EVIDENCE_DIR="$project_root/evidence/after"
if ! "$godot_binary" --path "$ui_root/project" --display-driver x11 --audio-driver Dummy --resolution 1280x720 --fixed-fps 30 --quit-after 3600 --write-movie "$ui_root/interface.avi" res://tests/ui_runner.tscn > "$ui_root/ui.log" 2>&1; then cat "$ui_root/ui.log"; exit 1; fi
cat "$ui_root/ui.log"
if rg -q 'SCRIPT ERROR|leaked|UI TESTS FAIL' "$ui_root/ui.log" || ! rg -q '^UI TESTS PASS$' "$ui_root/ui.log"; then exit 1; fi
ffmpeg -hide_banner -loglevel error -y -i "$ui_root/interface.avi" -c:v libx264 -crf 20 -pix_fmt yuv420p -c:a aac -b:a 96k "$project_root/evidence/after/interface-walkthrough.mp4"
cp "$project_root/evidence/after/ui-report.json" "$project_root/evidence/after/ui-report-1280.json"
for resolution in 960x600 1920x1080; do
  layout_args=(--resolution "$resolution")
  virtual_args=()
  if [ "$resolution" = "1920x1080" ]; then layout_args=(--resolution 1280x720); virtual_args=(--virtual-resolution=1920x1080); fi
  if ! "$godot_binary" --path "$ui_root/project" --display-driver x11 --audio-driver Dummy "${layout_args[@]}" --fixed-fps 30 --quit-after 1200 res://tests/ui_runner.tscn -- --layout-only "${virtual_args[@]}" > "$ui_root/layout.log" 2>&1; then cat "$ui_root/layout.log"; exit 1; fi
  cat "$ui_root/layout.log"
  if rg -q 'SCRIPT ERROR|UI TESTS FAIL|leaked' "$ui_root/layout.log"; then exit 1; fi
  cp "$project_root/evidence/after/ui-report.json" "$project_root/evidence/after/ui-report-$resolution.json"
done

export COLONY_DISPLAY_FRAMES="$ui_root/display-frames"
if ! "$godot_binary" --path "$ui_root/project" --display-driver x11 --audio-driver Dummy --resolution 1280x720 --fixed-fps 30 res://tests/display_runner.tscn > "$ui_root/display.log" 2>&1; then cat "$ui_root/display.log"; exit 1; fi
cat "$ui_root/display.log"
if rg -q 'SCRIPT ERROR' "$ui_root/display.log"; then exit 1; fi
ffmpeg -hide_banner -loglevel error -y -framerate 30 -i "$ui_root/display-frames/frame-%04d.png" -vf "scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2" -c:v libx264 -crf 20 -pix_fmt yuv420p "$project_root/evidence/after/display-settings.mp4"
