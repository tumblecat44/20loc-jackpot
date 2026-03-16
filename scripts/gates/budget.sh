#!/bin/bash
# gates/budget.sh — API 비용 게이트
# exit 0 = 미도달(계속), exit 1 = 도달(종료)
set -euo pipefail
CONFIG="$1"; PROJECT_DIR="$2"
MAX_USD=$(grep -A2 'type: budget' "$CONFIG" | grep 'max_usd:' | head -1 | awk '{print $2}')
MAX_USD=${MAX_USD:-50}
# 비용 추적 파일 (사용 가능 시)
COST_FILE="$PROJECT_DIR/.claude/codeloop-cost.json"
CURRENT=0
if [ -f "$COST_FILE" ]; then
  CURRENT=$(grep -o '"total_usd":[0-9.]*' "$COST_FILE" | head -1 | cut -d: -f2)
  CURRENT=${CURRENT:-0}
fi
PASSED=$(echo "$CURRENT >= $MAX_USD" | bc -l 2>/dev/null || echo 0)
echo "{\"gate\":\"budget\",\"current_usd\":$CURRENT,\"max_usd\":$MAX_USD,\"passed\":$([ "$PASSED" = "1" ] && echo true || echo false)}"
[ "$PASSED" = "1" ] && exit 1 || exit 0
