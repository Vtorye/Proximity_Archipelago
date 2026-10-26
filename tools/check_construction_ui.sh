#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
construction_root="$(mktemp -d -t colony-construction-ui-XXXXXX)"
trap 'rm -rf "$construction_root"' EXIT
python3 - "$project_root" "$construction_root/project" <<'PY'
import shutil, sys
from pathlib import Path
source, destination = map(Path, sys.argv[1:])
shutil.copytree(source, destination, ignore=shutil.ignore_patterns('.git', '.godot', 'evidence'))
project = destination / 'project.godot'
project.write_text(project.read_text().replace('config/name="archipelago"', 'config/name="archipelago-construction-validation"'))
PY
godot_binary="${GODOT_BIN:-godot}"
if ! "$godot_binary" --headless --path "$construction_root/project" --editor --quit > "$construction_root/import.log" 2>&1; then cat "$construction_root/import.log"; exit 1; fi
if rg -q 'SCRIPT ERROR|Failed to load|Parse Error' "$construction_root/import.log"; then cat "$construction_root/import.log"; exit 1; fi
export COLONY_EVIDENCE_DIR="$project_root/evidence/construction"
export COLONY_SOURCE_REVISION="$(git -C "$project_root" rev-parse HEAD)"
mkdir -p "$COLONY_EVIDENCE_DIR"
if ! "$godot_binary" --path "$construction_root/project" --display-driver x11 --audio-driver Dummy --resolution 1280x720 --fixed-fps 30 --quit-after 1800 --write-movie "$construction_root/construction.avi" res://tests/construction_visual.tscn > "$construction_root/ui.log" 2>&1; then cat "$construction_root/ui.log"; exit 1; fi
cat "$construction_root/ui.log"
if rg -q 'SCRIPT ERROR|leaked|UI TESTS FAIL' "$construction_root/ui.log" || ! rg -q '^UI TESTS PASS$' "$construction_root/ui.log"; then exit 1; fi
ffmpeg -hide_banner -loglevel error -y -i "$construction_root/construction.avi" -vf 'scale=1280:720:flags=neighbor' -c:v libx264 -crf 20 -pix_fmt yuv420p -c:a aac -b:a 96k "$COLONY_EVIDENCE_DIR/construction.mp4"

export COLONY_EVIDENCE_DIR="$project_root/evidence/construction/compact"
mkdir -p "$COLONY_EVIDENCE_DIR"
if ! "$godot_binary" --path "$construction_root/project" --display-driver x11 --audio-driver Dummy --resolution 960x600 --fixed-fps 30 --quit-after 1800 res://tests/construction_visual.tscn > "$construction_root/compact.log" 2>&1; then cat "$construction_root/compact.log"; exit 1; fi
cat "$construction_root/compact.log"
if rg -q 'SCRIPT ERROR|leaked|UI TESTS FAIL' "$construction_root/compact.log" || ! rg -q '^UI TESTS PASS$' "$construction_root/compact.log"; then exit 1; fi

export COLONY_EVIDENCE_DIR="$project_root/evidence/construction/regression"
mkdir -p "$COLONY_EVIDENCE_DIR"
if ! "$godot_binary" --path "$construction_root/project" --display-driver x11 --audio-driver Dummy --resolution 1280x720 --fixed-fps 30 --quit-after 3600 --write-movie "$construction_root/interface.avi" res://tests/ui_runner.tscn > "$construction_root/regression.log" 2>&1; then cat "$construction_root/regression.log"; exit 1; fi
cat "$construction_root/regression.log"
if rg -q 'SCRIPT ERROR|leaked|UI TESTS FAIL' "$construction_root/regression.log" || ! rg -q '^UI TESTS PASS$' "$construction_root/regression.log"; then exit 1; fi
ffmpeg -hide_banner -loglevel error -y -i "$construction_root/interface.avi" -vf 'scale=1280:720:flags=neighbor' -c:v libx264 -crf 20 -pix_fmt yuv420p -c:a aac -b:a 96k "$COLONY_EVIDENCE_DIR/interface.mp4"
