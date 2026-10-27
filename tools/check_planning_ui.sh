#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
planning_root="$(mktemp -d -t colony-planning-ui-XXXXXX)"
trap 'rm -rf "$planning_root"' EXIT
python3 - "$project_root" "$planning_root/project" <<'PY'
import shutil, sys
from pathlib import Path
source, destination = map(Path, sys.argv[1:])
shutil.copytree(source, destination, ignore=shutil.ignore_patterns('.git', '.godot', 'evidence'))
project = destination / 'project.godot'
project.write_text(project.read_text().replace('config/name="archipelago"', 'config/name="archipelago-planning-validation"'))
PY
godot_binary="${GODOT_BIN:-godot}"
"$godot_binary" --headless --path "$planning_root/project" --editor --quit > "$planning_root/import.log" 2>&1
if rg -q 'SCRIPT ERROR|Failed to load|Parse Error' "$planning_root/import.log"; then cat "$planning_root/import.log"; exit 1; fi
export COLONY_EVIDENCE_DIR="$project_root/evidence/assignment"
export COLONY_SOURCE_REVISION="$(git -C "$project_root" rev-parse HEAD)"
mkdir -p "$COLONY_EVIDENCE_DIR"
if ! "$godot_binary" --path "$planning_root/project" --display-driver x11 --audio-driver Dummy --resolution 1280x720 --fixed-fps 30 --quit-after 1800 --write-movie "$planning_root/planning.avi" res://tests/planning_visual.tscn > "$planning_root/ui.log" 2>&1; then cat "$planning_root/ui.log"; exit 1; fi
cat "$planning_root/ui.log"
if rg -q 'SCRIPT ERROR|leaked|UI TESTS FAIL' "$planning_root/ui.log" || ! rg -q '^UI TESTS PASS$' "$planning_root/ui.log"; then exit 1; fi
ffmpeg -hide_banner -loglevel error -y -i "$planning_root/planning.avi" -vf 'scale=1280:720:flags=neighbor' -c:v libx264 -crf 20 -pix_fmt yuv420p -c:a aac -b:a 96k "$COLONY_EVIDENCE_DIR/planning.mp4"
