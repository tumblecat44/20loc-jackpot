#!/bin/bash
# gates/iterations.sh — 반복 횟수 게이트
# exit 0 = 미도달(계속), exit 1 = 도달(종료)
set -euo pipefail
CONFIG="$1"; PROJECT_DIR="$2"
MAX=$(grep -A2 'type: iterations' "$CONFIG" | grep 'max:' | head -1 | awk '{print $2}')
MAX=${MAX:-500}
STATE="$PROJECT_DIR/.claude/codeloop.state.md"
CURRENT=$(grep '^iteration:' "$STATE" 2>/dev/null | head -1 | awk '{print $2}')
CURRENT=${CURRENT:-0}
echo "{\"gate\":\"iterations\",\"current\":$CURRENT,\"max\":$MAX,\"passed\":$([ $CURRENT -ge $MAX ] && echo true || echo false)}"
[ $CURRENT -ge $MAX ] && exit 1 || exit 0
