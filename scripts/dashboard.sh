#!/bin/bash
# dashboard.sh — 마크다운 대시보드 생성 (원조 loc-status.md 패턴)
set -euo pipefail

CONFIG="$1"
PROJECT_DIR="$2"
ITER="${3:-0}"
USAGE_JSON="${4:-{}}"
SCRIPTS="$(dirname "$0")"

source "$SCRIPTS/parse-yaml.sh"

# 설정 읽기
PROJ_NAME=$(yaml_get "project.name" "$CONFIG" 2>/dev/null || basename "$PROJECT_DIR")
DASH_PATH=$(yaml_get "dashboard.path" "$CONFIG" 2>/dev/null || echo ".claude/loc-status.md")
LOG_PATH=$(yaml_get "dashboard.log" "$CONFIG" 2>/dev/null || echo "")

# LOC Gate 결과 가져오기
LOC_JSON=$(bash "$SCRIPTS/gates/loc.sh" "$CONFIG" "$PROJECT_DIR" 2>/dev/null || echo '{"current":0,"target":200000,"remaining":200000,"progress_pct":0,"file_count":0}')
CURRENT=$(echo "$LOC_JSON" | grep -o '"current":[0-9]*' | cut -d: -f2)
TARGET=$(echo "$LOC_JSON" | grep -o '"target":[0-9]*' | cut -d: -f2)
REMAINING=$(echo "$LOC_JSON" | grep -o '"remaining":[0-9]*' | cut -d: -f2)
PROGRESS=$(echo "$LOC_JSON" | grep -o '"progress_pct":[0-9.]*' | cut -d: -f2)
FILES=$(echo "$LOC_JSON" | grep -o '"file_count":[0-9]*' | cut -d: -f2)

# Usage 파싱
FIVE_HR=$(echo "$USAGE_JSON" | grep -o '"five_hour_pct":[0-9.]*' | head -1 | cut -d: -f2)
WEEKLY=$(echo "$USAGE_JSON" | grep -o '"weekly_pct":[0-9.]*' | head -1 | cut -d: -f2)
FIVE_HR=${FIVE_HR:-0}
WEEKLY=${WEEKLY:-0}

# Phase 결정 (원조 패턴)
PROGRESS_INT=${PROGRESS%.*}
PROGRESS_INT=${PROGRESS_INT:-0}
if [ "$PROGRESS_INT" -lt 25 ]; then PHASE="FOUNDATION"
elif [ "$PROGRESS_INT" -lt 50 ]; then PHASE="BUILDING"
elif [ "$PROGRESS_INT" -lt 75 ]; then PHASE="SCALING"
elif [ "$PROGRESS_INT" -lt 90 ]; then PHASE="MOAT"
else PHASE="POLISH"
fi

# Progress Bar 생성
BAR_LEN=30
FILLED=$((PROGRESS_INT * BAR_LEN / 100))
EMPTY=$((BAR_LEN - FILLED))
BAR=$(printf '%0.s█' $(seq 1 $FILLED 2>/dev/null) 2>/dev/null || echo "")
BAR="$BAR$(printf '%0.s░' $(seq 1 $EMPTY 2>/dev/null) 2>/dev/null || echo "")"

# 게이트 상태
GATE_STATUS=""
for gt in $(grep -A1 'type:' "$CONFIG" 2>/dev/null | grep 'type:' | awk '{print $2}'); do
  if bash "$SCRIPTS/gates/${gt}.sh" "$CONFIG" "$PROJECT_DIR" > /dev/null 2>&1; then
    GATE_STATUS="$GATE_STATUS ${gt}: ❌"
  else
    GATE_STATUS="$GATE_STATUS ${gt}: ✅"
  fi
done

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
DASH_FULL="$PROJECT_DIR/$DASH_PATH"

mkdir -p "$(dirname "$DASH_FULL")"
cat > "$DASH_FULL" <<EOF
---
updated_at: "$TIMESTAMP"
iteration: $ITER
phase: "$PHASE"
---

# 📊 $PROJ_NAME — Codeloop Dashboard

| Metric | Value |
|--------|-------|
| **LOC** | $(printf "%'d" $CURRENT) / $(printf "%'d" $TARGET) |
| **Remaining** | $(printf "%'d" $REMAINING) lines |
| **Files** | $FILES |
| **Iteration** | #$ITER |
| **Phase** | $PHASE |
| **LOC Progress** | [$BAR] ${PROGRESS}% |
| **API Usage** | 5hr: ${FIVE_HR}% · Weekly: ${WEEKLY}% |
| **Gates** |$GATE_STATUS |

> Last updated: $TIMESTAMP
EOF

# 이벤트 로그
if [ -n "$LOG_PATH" ]; then
  LOG_FULL=$(echo "$LOG_PATH" | sed "s|{project}|$(basename "$PROJECT_DIR")|g" | sed "s|~|$HOME|g")
  mkdir -p "$(dirname "$LOG_FULL")"
  echo "$TIMESTAMP | Iter #$ITER | LOC: $CURRENT/$TARGET | ${PROGRESS}% | Usage: ${FIVE_HR}% | Phase: $PHASE" >> "$LOG_FULL"
fi
