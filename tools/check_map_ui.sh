#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
map_root="$(mktemp -d -t colony-map-ui-XXXXXX)"
trap 'rm -rf "$map_root"' EXIT
python3 - "$project_root" "$map_root/project" <<'PY'
from pathlib import Path
import shutil, sys
source, target = map(Path, sys.argv[1:])
shutil.copytree(source, target, ignore=shutil.ignore_patterns('.git', '.godot'))
project = target / 'project.godot'
project.write_text(project.read_text().replace('config/name="archipelago"', 'config/name="archipelago-map-validation"'))
PY
if ! godot --headless --path "$map_root/project" --editor --quit > "$map_root/import.log" 2>&1; then cat "$map_root/import.log"; exit 1; fi
if rg -q 'SCRIPT ERROR|Parse Error|Failed to load' "$map_root/import.log"; then cat "$map_root/import.log"; exit 1; fi
export COLONY_SOURCE_REVISION="$(git -C "$project_root" rev-parse HEAD)"
export COLONY_CAPTURE_DIR="${COLONY_OUTPUT_ROOT:-/tmp/colony-validation}/archipelago"
mkdir -p "$COLONY_CAPTURE_DIR"
if ! godot --path "$map_root/project" --display-driver x11 --audio-driver Dummy --resolution 1280x720 --fixed-fps 30 --quit-after 6000 --write-movie "$map_root/archipelago.avi" res://tests/authored_map_visual.tscn > "$map_root/ui.log" 2>&1; then cat "$map_root/ui.log"; exit 1; fi
cat "$map_root/ui.log"
if rg -q 'SCRIPT ERROR|ERROR:|UI FAIL|leaked' "$map_root/ui.log" || ! rg -q '^UI TESTS PASS$' "$map_root/ui.log"; then exit 1; fi
ffmpeg -hide_banner -loglevel error -y -i "$map_root/archipelago.avi" -c:v libx264 -crf 18 -pix_fmt yuv420p -an "$COLONY_CAPTURE_DIR/archipelago.mp4"
