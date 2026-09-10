#!/usr/bin/env bash
# Local automated gates only. No installation, recording, signing or model calls.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -d tools/sidecast-debug/node_modules ]]; then
  echo "Install bench dependencies first: cd tools/sidecast-debug && npm ci" >&2
  exit 1
fi

(
  cd OpenOats
  swift test
  swift run knowledge-pack audit-correctness ../fixtures/correctness-gate-v1.json
)
bash scripts/lint_swift.sh
(
  cd tools/sidecast-debug
  npm run verify
)

if [[ "${RUN_UI_SMOKE:-0}" == "1" ]]; then
  bash scripts/run_ui_smoke.sh
else
  echo "Automated checks passed. UI smoke was not run; opt in with RUN_UI_SMOKE=1 on an interactive desktop."
fi
