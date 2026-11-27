# Sourced by the test launchers. Each process gets a clean game profile and import cache.
prepare_test_project() {
  local source_root="$1" test_root="$2"
  export XDG_DATA_HOME="$test_root/data" XDG_CONFIG_HOME="$test_root/config" XDG_CACHE_HOME="$test_root/cache"
  mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
  python3 - "$source_root" "$test_root/project" <<'PY'
from pathlib import Path
import shutil
import sys

source, destination = map(Path, sys.argv[1:])
shutil.copytree(source, destination, ignore=shutil.ignore_patterns('.git', '.godot', '.godot_test_roaming'))
PY
  # The custom theme references imported textures before the first scan.
  # Validate the next clean editor start once those textures exist.
  local pass
  for pass in bootstrap import; do
    if ! "${GODOT_BIN:-godot}" --headless --path "$test_root/project" --editor --import > "$test_root/$pass.log" 2>&1; then
      cat "$test_root/$pass.log"
      return 1
    fi
  done
  if rg -q '(^|[[:space:]])(SCRIPT ERROR|ERROR):' "$test_root/import.log"; then
    cat "$test_root/import.log"
    return 1
  fi
}
