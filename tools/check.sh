#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
check_root="$(mktemp -d -t colony-check-XXXXXX)"
trap 'rm -rf "$check_root"' EXIT
python3 - "$project_root" "$check_root/project" <<'PY'
import shutil, sys
from pathlib import Path
source, destination = map(Path, sys.argv[1:])
shutil.copytree(source, destination, ignore=shutil.ignore_patterns('.git', '.godot', 'evidence'))
project = destination / 'project.godot'
project.write_text(project.read_text().replace('config/name="archipelago"', 'config/name="archipelago-tests"'))
PY
godot_binary="${GODOT_BIN:-godot}"
"$godot_binary" --headless --path "$check_root/project" --editor --quit > "$check_root/import.log" 2>&1
if rg -q 'SCRIPT ERROR|Failed to load|Parse Error' "$check_root/import.log"; then
  cat "$check_root/import.log"
  exit 1
fi
"$godot_binary" --headless --path "$check_root/project" --fixed-fps 60 res://tests/test_runner.tscn > "$check_root/tests.log" 2>&1
cat "$check_root/tests.log"
if rg -q 'SCRIPT ERROR|Leaked|leaked|TESTS FAIL' "$check_root/tests.log" || ! rg -q '^TESTS PASS$' "$check_root/tests.log"; then exit 1; fi
"$godot_binary" --headless --path "$check_root/project" res://game/test/house_test.tscn > "$check_root/house.log" 2>&1
cat "$check_root/house.log"
rg -q '^HOUSE TEST PASS$' "$check_root/house.log"
