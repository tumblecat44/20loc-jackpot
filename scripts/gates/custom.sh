#!/bin/bash
# gates/custom.sh — 사용자 정의 게이트
# exit 0 = 미도달(계속), exit 1 = 도달(종료)
set -euo pipefail
CONFIG="$1"; PROJECT_DIR="$2"
CMD=$(grep -A2 'type: custom' "$CONFIG" | grep 'command:' | head -1 | sed 's/.*command:[[:space:]]*//' | tr -d '"'\''')
[ -z "$CMD" ] && { echo '{"gate":"custom","passed":false}'; exit 0; }
cd "$PROJECT_DIR"
if bash -c "$CMD" > /dev/null 2>&1; then
  echo '{"gate":"custom","exit_code":0,"passed":false}'; exit 0
else
  echo '{"gate":"custom","exit_code":1,"passed":true}'; exit 1
fi
