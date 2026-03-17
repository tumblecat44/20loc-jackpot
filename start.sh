#!/usr/bin/env bash
# ============================================================================
# codeloop start.sh — AI 자율 개발 루프 런처
#
# 사용법: ./start.sh
# 멈추기: 다른 터미널에서 rm .claude/codeloop.state.md
# 모니터: cat .claude/loc-status.md
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")"

# ─── 설정 로드 ───
CONFIG="codeloop.yaml"
if [ ! -f "$CONFIG" ]; then
  echo "❌ codeloop.yaml not found — run 'codeloop init' first."
  exit 1
fi

# 경량 yaml 파싱 (parse-yaml.sh 없이 동작)
yaml_val() { grep "^[[:space:]]*$1:" "$CONFIG" | head -1 | sed "s/.*$1:[[:space:]]*//" | tr -d '"'"'"; }

PROMPT_PATH=$(yaml_val prompt)
PROMPT_PATH=${PROMPT_PATH:-./PROMPT.md}
MODEL=$(yaml_val model)
MODEL=${MODEL:-opus}
PROJECT_NAME=$(yaml_val name)
PROJECT_NAME=${PROJECT_NAME:-codeloop}

if [ ! -f "$PROMPT_PATH" ]; then
  echo "❌ $PROMPT_PATH not found."
  exit 1
fi

PROMPT=$(cat "$PROMPT_PATH")

# ─── git 초기화 (없으면) ───
if [ ! -d .git ]; then
  git init
  printf "node_modules/\ndist/\nbuild/\n.next/\n__pycache__/\n*.pyc\n.env\n.env.local\n.venv/\n" > .gitignore
  git add .gitignore
  git commit -m "Initial commit"
fi

# ─── 상태 파일 생성 ───
mkdir -p .claude
cat > .claude/codeloop.state.md <<STATE
---
active: true
iteration: 0
started_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
config: "$CONFIG"
---

$PROMPT
STATE

# ─── 이전 대시보드 초기화 ───
rm -f .claude/loc-status.md

# ─── 배너 ───
GATES=$(grep 'type:' "$CONFIG" 2>/dev/null | grep -v 'project\|stack' | sed 's/.*type:[[:space:]]*//' | tr '\n' ', ' | sed 's/,$//')
cat <<BANNER
============================================================
  🚀 codeloop — AI 자율 개발 루프
============================================================
  프로젝트: $PROJECT_NAME
  모델:     $MODEL
  게이트:   $GATES
  프롬프트: $PROMPT_PATH

  모니터링:
    cat .claude/loc-status.md
    cat .claude/codeloop.state.md | head -5

  긴급 중지:
    rm .claude/codeloop.state.md
============================================================

BANNER

echo "Starting Claude Code with codeloop..."
echo ""

# ─── 루프 실행 ───
# Stop Hook의 block 메커니즘이 기본 루프 드라이버이지만,
# 긴 sleep(rate limit 대기) 후 block이 실패할 수 있으므로
# start.sh 자체가 while 루프로 안전망 역할을 한다.
# 종료 조건: .claude/codeloop.state.md 삭제 (stop-hook이 게이트 통과 시 삭제)
export CODELOOP_ACTIVE=1

while [ -f .claude/codeloop.state.md ]; do
  claude --dangerously-skip-permissions \
    --model "$MODEL" \
    --verbose \
    -p "$PROMPT" || true
  # claude -p 종료 후 state 파일 확인 — 없으면 게이트 통과로 정상 종료
  if [ ! -f .claude/codeloop.state.md ]; then
    echo ""
    echo "🎉 codeloop 완료 — 모든 게이트 통과"
    break
  fi
  # 짧은 대기 후 재시작 (tight loop 방지)
  sleep 3
done
