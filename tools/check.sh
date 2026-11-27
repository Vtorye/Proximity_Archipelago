#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
check_root="$(mktemp -d -t colony-check-XXXXXX)"
trap 'rm -rf "$check_root"' EXIT
source "$project_root/tools/test_project.sh"
prepare_test_project "$project_root" "$check_root"
godot_binary="${GODOT_BIN:-godot}"
"$godot_binary" --headless --path "$check_root/project" --script res://tools/check_dialogue_assets.gd
if ! "$godot_binary" --headless --path "$check_root/project" --fixed-fps 60 res://tests/test_runner.tscn > "$check_root/tests.log" 2>&1; then cat "$check_root/tests.log"; exit 1; fi
cat "$check_root/tests.log"
if rg -qi '(script error|error):|leaked|tests fail' "$check_root/tests.log" || ! rg -q '^TESTS PASS$' "$check_root/tests.log"; then exit 1; fi
if ! "$godot_binary" --headless --path "$check_root/project" res://game/test/nest_test.tscn > "$check_root/nest.log" 2>&1; then cat "$check_root/nest.log"; exit 1; fi
cat "$check_root/nest.log"
if rg -qi '(script error|error):|leaked|nest test fail' "$check_root/nest.log" || ! rg -q '^NEST TEST PASS$' "$check_root/nest.log"; then exit 1; fi
