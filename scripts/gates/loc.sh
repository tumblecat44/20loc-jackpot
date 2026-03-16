#!/usr/bin/env bash
# gates/loc.sh — LOC Gate (원조 count-loc.sh 기반, 하드코딩 제거)
# exit 0 = 목표 미도달(계속), exit 1 = 목표 도달(종료)
set -euo pipefail

CONFIG="$1"
PROJECT_DIR="$2"
SCRIPTS="$(dirname "$(dirname "$0")")/scripts"
source "$SCRIPTS/parse-yaml.sh" 2>/dev/null || source "$(dirname "$0")/../parse-yaml.sh"

TARGET=$(yaml_get "gates" "$CONFIG" 2>/dev/null || echo "")
# gates 배열에서 loc target 추출
TARGET=$(grep -A2 'type: loc' "$CONFIG" | grep 'target:' | head -1 | awk '{print $2}')
TARGET=${TARGET:-200000}

# 제외 디렉토리 (원조 58개 그대로)
EXCLUDES="node_modules .next dist build out .output coverage __pycache__ .pytest_cache venv .venv env .env vendor .git .bkit .omc .claude .turbo .cache .nuxt .svelte-kit target .gradle .idea .vscode storybook-static .parcel-cache .expo .terraform .serverless cdk.out .aws-sam .vercel .netlify migrations"

# find 제외 옵션 생성
FIND_EXCLUDES=""
for d in $EXCLUDES; do
  FIND_EXCLUDES="$FIND_EXCLUDES -not -path '*/$d/*'"
done

# 소스 확장자 (원조 63개 그대로)
EXTS="ts tsx js jsx mjs cjs py pyw go rs java kt kts scala c h cpp hpp cc cxx cs rb php swift dart lua r R jl ex exs erl hrl hs ml mli clj cljs cljc elm vue svelte html htm css scss sass less styl sql graphql gql proto yaml yml toml json jsonc xml tf hcl sh bash zsh fish ps1 md mdx prisma sol zig nim v cr"

# find 포함 옵션 생성
FIND_INCLUDES=""
first=true
for ext in $EXTS; do
  if $first; then
    FIND_INCLUDES="-name '*.$ext'"
    first=false
  else
    FIND_INCLUDES="$FIND_INCLUDES -o -name '*.$ext'"
  fi
done
FIND_INCLUDES="$FIND_INCLUDES -o -name 'Dockerfile' -o -name 'Makefile'"

# 제외 파일 패턴
FIND_FILE_EXCLUDES="-not -name 'package-lock.json' -not -name 'yarn.lock' -not -name 'pnpm-lock.yaml' -not -name '*.min.js' -not -name '*.min.css' -not -name '*.map' -not -name '*.d.ts' -not -name '*.snap' -not -name '*.svg' -not -name '*.png' -not -name '*.jpg' -not -name '*.gif' -not -name '*.woff*' -not -name '*.ttf' -not -name '*.pdf' -not -name '*.zip' -not -name '*.pyc' -not -name '*.class' -not -name 'go.sum' -not -name 'Cargo.lock' -not -name 'poetry.lock'"

# LOC 카운트
TOTAL=0
FILE_COUNT=0
while IFS= read -r file; do
  if [ -f "$file" ]; then
    lines=$(grep -cve '^\s*$' "$file" 2>/dev/null || echo 0)
    TOTAL=$((TOTAL + lines))
    FILE_COUNT=$((FILE_COUNT + 1))
  fi
done < <(eval "find \"$PROJECT_DIR\" -type f $FIND_EXCLUDES $FIND_FILE_EXCLUDES \\( $FIND_INCLUDES \\)" 2>/dev/null)

REMAINING=$((TARGET - TOTAL))
[ $REMAINING -lt 0 ] && REMAINING=0
PROGRESS=$(echo "scale=1; $TOTAL * 100 / $TARGET" | bc 2>/dev/null || echo "0")

# JSON 출력
cat <<EOF
{"gate":"loc","current":$TOTAL,"target":$TARGET,"remaining":$REMAINING,"progress_pct":$PROGRESS,"file_count":$FILE_COUNT,"passed":$([ $TOTAL -ge $TARGET ] && echo true || echo false)}
EOF

# exit 1 = 목표 도달, exit 0 = 미도달
[ $TOTAL -ge $TARGET ] && exit 1 || exit 0
