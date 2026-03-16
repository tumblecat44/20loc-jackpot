#!/bin/bash
# stop-hook.sh — Codeloop Orchestrator
# 원조: nowimslepe/.claude/hooks/stop-hook.sh
# 역할: 매 Claude 세션 종료 시 자동 실행. usage → gates → dashboard
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
CONFIG="$PROJECT_DIR/codeloop.yaml"
STATE="$PROJECT_DIR/.claude/codeloop.state.md"
SCRIPTS="$PLUGIN_ROOT/scripts"

source "$SCRIPTS/parse-yaml.sh"

# 상태 파일 없으면 루프 아님 → 즉시 종료
[ -f "$STATE" ] || exit 0

# iteration 증가
ITER=$(grep '^iteration:' "$STATE" | head -1 | awk '{print $2}')
ITER=${ITER:-0}
ITER=$((ITER + 1))
sed -i.bak "s/^iteration:.*/iteration: $ITER/" "$STATE" && rm -f "$STATE.bak"

# Step 1: Usage Gate (OAuth API → sleep 또는 pass)
USAGE_RESULT=$(node "$SCRIPTS/usage-gate.js" --config "$CONFIG" --project "$PROJECT_DIR" 2>/dev/null || echo '{"action":"cooldown","sleep_seconds":30}')
ACTION=$(echo "$USAGE_RESULT" | grep -o '"action":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ "$ACTION" = "sleep" ]; then
  SLEEP_SEC=$(echo "$USAGE_RESULT" | grep -o '"sleep_seconds":[0-9]*' | head -1 | cut -d: -f2)
  echo "⏸️  codeloop: 사용량 한도 도달 — ${SLEEP_SEC}초 대기"
  sleep "$SLEEP_SEC"
elif [ "$ACTION" = "cooldown" ]; then
  COOL=$(echo "$USAGE_RESULT" | grep -o '"sleep_seconds":[0-9]*' | head -1 | cut -d: -f2)
  COOL=${COOL:-30}
  sleep "$COOL"
fi

# Step 2: Completion Gates — exit 0 = 미도달(계속), exit 1 = 도달(종료 후보)
ALL_MET=true
for GATE_TYPE in $(yaml_get_gates "$CONFIG"); do
  GATE_SCRIPT="$SCRIPTS/gates/${GATE_TYPE}.sh"
  [ -f "$GATE_SCRIPT" ] || continue
  if bash "$GATE_SCRIPT" "$CONFIG" "$PROJECT_DIR" > /dev/null 2>&1; then
    ALL_MET=false  # exit 0 = 목표 미도달 → 루프 계속
  fi
  # exit 1 = 목표 도달 → 이 게이트는 통과
done

# Step 3: Dashboard 갱신
bash "$SCRIPTS/dashboard.sh" "$CONFIG" "$PROJECT_DIR" "$ITER" "$USAGE_RESULT" 2>/dev/null || true

# Step 4: 모든 게이트 목표 도달 → 상태 파일 삭제 → 루프 종료
if [ "$ALL_MET" = true ]; then
  rm -f "$STATE"
  echo "🎉 codeloop: 모든 게이트 통과 — 루프 종료"
fi

exit 0  # 항상 exit 0 — 루프 제어는 상태 파일로
