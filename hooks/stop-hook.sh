#!/bin/bash
# stop-hook.sh — Codeloop Orchestrator
# 원조: nowimslepe/.claude/hooks/stop-hook.sh + ralph-wiggum block 패턴
# 역할: 매 Claude 세션 종료 시 usage → gates → dashboard → block(루프 지속)
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
  echo "⏸️  codeloop: 사용량 한도 도달 — ${SLEEP_SEC}초 대기" >&2
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

# Step 4: 루프 제어 — ralph-wiggum block 패턴
if [ "$ALL_MET" = true ]; then
  # 모든 게이트 통과 → 상태 파일 삭제 → 루프 종료
  rm -f "$STATE"
  echo "🎉 codeloop: 모든 게이트 통과 — 루프 종료" >&2
  exit 0
fi

# 게이트 미충족 → block 시그널로 루프 지속
# 상태 파일에서 프롬프트 추출 (--- 프론트매터 이후 전체)
PROMPT_TEXT=$(awk 'BEGIN{n=0} /^---$/{n++; next} n>=2' "$STATE")

if [ -z "$PROMPT_TEXT" ]; then
  echo "⚠️  codeloop: 프롬프트 추출 실패 — 루프 중단" >&2
  exit 0
fi

# block JSON 출력 → Claude Code가 이 프롬프트로 새 세션 시작
# jq로 안전한 JSON escape (macOS/Linux 호환)
jq -n --arg prompt "$PROMPT_TEXT" '{"decision":"block","reason":$prompt}'
exit 0
