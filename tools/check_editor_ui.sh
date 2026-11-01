#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
editor_root="$(mktemp -d -t colony-editor-XXXXXX)"
trap 'rm -rf "$editor_root"' EXIT
python3 - "$project_root" "$editor_root/project" <<'PY'
from pathlib import Path
import shutil,sys
source,target=map(Path,sys.argv[1:])
shutil.copytree(source,target,ignore=shutil.ignore_patterns('.git','.godot'))
p=target/'project.godot';p.write_text(p.read_text().replace('config/name="archipelago"','config/name="archipelago-editor-validation"'))
p=target/'addons/level_validation/plugin.gd'
s=p.read_text().replace('\t_scene_changed(EditorInterface.get_edited_scene_root())','\t_scene_changed(EditorInterface.get_edited_scene_root())\n\tvar test = load("res://tests/editor_visual.gd").new()\n\tset_meta(&"editor_test", test)\n\ttest.run.call_deferred(self)')
p.write_text(s)
PY
export COLONY_CAPTURE_DIR="${COLONY_OUTPUT_ROOT:-/tmp/colony-validation}/editor"
mkdir -p "$COLONY_CAPTURE_DIR"
if ! godot --editor --path "$editor_root/project" --display-driver x11 --audio-driver Dummy --resolution 1440x900 --quit-after 2400 > "$editor_root/editor.log" 2>&1; then cat "$editor_root/editor.log"; exit 1; fi
cat "$editor_root/editor.log"
if rg -q 'SCRIPT ERROR|EDITOR FAIL|Parse Error' "$editor_root/editor.log" || ! rg -q '^EDITOR TESTS PASS$' "$editor_root/editor.log"; then exit 1; fi
