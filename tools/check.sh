#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
check_root="$(mktemp -d -t colony-check-XXXXXX)"
trap 'rm -rf "$check_root"' EXIT
python3 - "$project_root" "$check_root/project" <<'PY'
import shutil, sys
from pathlib import Path
source, destination = map(Path, sys.argv[1:])
shutil.copytree(source, destination, ignore=shutil.ignore_patterns('.git', '.godot', '.godot_test_roaming'))
PY
export XDG_DATA_HOME="$check_root/data"
export XDG_CONFIG_HOME="$check_root/config"
export XDG_CACHE_HOME="$check_root/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
godot_binary="${GODOT_BIN:-godot}"
# The custom theme can reference imported textures before the first scan.
# Run the import to completion, then verify a fresh editor start.
if ! "$godot_binary" --headless --path "$check_root/project" --editor --import > "$check_root/bootstrap-import.log" 2>&1; then cat "$check_root/bootstrap-import.log"; exit 1; fi
if ! "$godot_binary" --headless --path "$check_root/project" --editor --import > "$check_root/import.log" 2>&1; then cat "$check_root/import.log"; exit 1; fi
if rg -q '(^|[[:space:]])(SCRIPT ERROR|ERROR):' "$check_root/import.log"; then
  cat "$check_root/import.log"
  exit 1
fi
"$godot_binary" --headless --path "$check_root/project" --script res://tools/check_dialogue_assets.gd
if ! "$godot_binary" --headless --path "$check_root/project" --fixed-fps 60 res://tests/test_runner.tscn > "$check_root/tests.log" 2>&1; then cat "$check_root/tests.log"; exit 1; fi
cat "$check_root/tests.log"
if rg -qi '(script error|error):|leaked|tests fail' "$check_root/tests.log" || ! rg -q '^TESTS PASS$' "$check_root/tests.log"; then exit 1; fi
if ! "$godot_binary" --headless --path "$check_root/project" res://game/test/nest_test.tscn > "$check_root/nest.log" 2>&1; then cat "$check_root/nest.log"; exit 1; fi
cat "$check_root/nest.log"
if rg -qi '(script error|error):|leaked|nest test fail' "$check_root/nest.log" || ! rg -q '^NEST TEST PASS$' "$check_root/nest.log"; then exit 1; fi
