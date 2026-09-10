#!/usr/bin/env bash
set -euo pipefail

# Exact-path launch; never quit another copy or start recording automatically.
# --check validates the route without launching anything.
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--check" ) ]]; then
  echo "Usage: bash scripts/launch_knowledge_copilot.sh [--check]" >&2
  exit 2
fi
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
APP_PATH="$ROOT_DIR/dist/OpenOats.app"
APP_EXECUTABLE="$APP_PATH/Contents/MacOS/OpenOats"
if [[ ! -x "$APP_EXECUTABLE" ]]; then
  echo "Development app not built: $APP_PATH" >&2
  exit 1
fi
while read -r process_id executable; do
  case "$executable" in
    */Contents/MacOS/OpenOats)
      if [[ "$executable" != "$APP_EXECUTABLE" ]]; then
        echo "Another OpenOats copy is running (PID $process_id): $executable" >&2
        echo "Finish/save its session and quit it normally, then retry. Nothing was launched or stopped." >&2
        exit 1
      fi
      ;;
  esac
done < <(/bin/ps -ax -o pid=,comm=)
echo "Development app: $APP_PATH"
if [[ "${1:-}" == "--check" ]]; then
  echo "Launch check passed; no app launched."
  exit 0
fi
/usr/bin/open -a "$APP_PATH"
