#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
preview_root="$(mktemp -d -t colony-designer-XXXXXX)"
trap 'rm -rf "$preview_root"' EXIT
python3 - "$project_root" "$preview_root/project" <<'PY'
from pathlib import Path
import shutil,sys
source,target=map(Path,sys.argv[1:])
shutil.copytree(source,target,ignore=shutil.ignore_patterns('.git','.godot','evidence'))
p=target/'project.godot';p.write_text(p.read_text().replace('config/name="archipelago"','config/name="archipelago-designer-validation"'))
PY
if ! godot --headless --path "$preview_root/project" --editor --quit > "$preview_root/import.log" 2>&1; then cat "$preview_root/import.log"; exit 1; fi
if rg -q 'SCRIPT ERROR|Parse Error|Failed to load' "$preview_root/import.log"; then cat "$preview_root/import.log"; exit 1; fi
export COLONY_SOURCE_REVISION="$(git -C "$project_root" rev-parse HEAD)"
export COLONY_EVIDENCE_DIR="$project_root/evidence/designer"
mkdir -p "$COLONY_EVIDENCE_DIR"
if ! godot --path "$preview_root/project" --display-driver x11 --audio-driver Dummy --resolution 1280x720 --fixed-fps 30 --quit-after 1500 --write-movie "$preview_root/designer.avi" res://tests/designer_visual.tscn > "$preview_root/ui.log" 2>&1; then cat "$preview_root/ui.log"; exit 1; fi
cat "$preview_root/ui.log"
if rg -q 'SCRIPT ERROR|UI FAIL|leaked' "$preview_root/ui.log" || ! rg -q '^UI TESTS PASS$' "$preview_root/ui.log"; then exit 1; fi
ffmpeg -hide_banner -loglevel error -y -i "$preview_root/designer.avi" -c:v libx264 -crf 18 -pix_fmt yuv420p -c:a aac "$COLONY_EVIDENCE_DIR/designer.mp4"
