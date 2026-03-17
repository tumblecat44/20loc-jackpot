#!/usr/bin/env bash
# gates/loc.sh — LOC Gate (원조 count-loc.sh 기반, 하드코딩 제거)
# exit 0 = 목표 미도달(계속), exit 1 = 목표 도달(종료)
set -euo pipefail

CONFIG="$1"
PROJECT_DIR="$2"
SCRIPTS="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPTS/parse-yaml.sh"

TARGET=$(yaml_get "gates" "$CONFIG" 2>/dev/null || echo "")
# gates 배열에서 loc target 추출
TARGET=$(grep -A2 'type: loc' "$CONFIG" | grep 'target:' | head -1 | awk '{print $2}')
TARGET=${TARGET:-200000}

# ─── 임시 find 스크립트 생성 (eval/subshell 쿼팅 지옥 회피) ───
FIND_SCRIPT=$(mktemp)
cat > "$FIND_SCRIPT" <<'FINDEOF'
#!/usr/bin/env bash
PROJECT_DIR="$1"
find "$PROJECT_DIR" \
  -type d \( \
    -name node_modules \
    -o -name .next \
    -o -name dist \
    -o -name build \
    -o -name out \
    -o -name .output \
    -o -name coverage \
    -o -name __pycache__ \
    -o -name .pytest_cache \
    -o -name venv \
    -o -name .venv \
    -o -name env \
    -o -name .env \
    -o -name vendor \
    -o -name .git \
    -o -name .bkit \
    -o -name .omc \
    -o -name .claude \
    -o -name .turbo \
    -o -name .cache \
    -o -name .nuxt \
    -o -name .svelte-kit \
    -o -name target \
    -o -name .gradle \
    -o -name .idea \
    -o -name .vscode \
    -o -name storybook-static \
    -o -name .parcel-cache \
    -o -name .expo \
    -o -name .terraform \
    -o -name .serverless \
    -o -name cdk.out \
    -o -name .aws-sam \
    -o -name .vercel \
    -o -name .netlify \
    -o -name migrations \
    -o -name .mypy_cache \
    -o -name .ruff_cache \
    -o -name .tox \
    -o -name eggs \
    -o -name site-packages \
  \) -prune -o -type f \( \
    -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \
    -o -name "*.mjs" -o -name "*.cjs" -o -name "*.py" -o -name "*.pyw" \
    -o -name "*.go" -o -name "*.rs" -o -name "*.java" -o -name "*.kt" \
    -o -name "*.kts" -o -name "*.scala" -o -name "*.c" -o -name "*.h" \
    -o -name "*.cpp" -o -name "*.hpp" -o -name "*.cc" -o -name "*.cxx" \
    -o -name "*.cs" -o -name "*.rb" -o -name "*.php" -o -name "*.swift" \
    -o -name "*.dart" -o -name "*.lua" -o -name "*.r" -o -name "*.R" \
    -o -name "*.jl" -o -name "*.ex" -o -name "*.exs" -o -name "*.erl" \
    -o -name "*.hrl" -o -name "*.hs" -o -name "*.ml" -o -name "*.mli" \
    -o -name "*.clj" -o -name "*.cljs" -o -name "*.cljc" -o -name "*.elm" \
    -o -name "*.vue" -o -name "*.svelte" -o -name "*.html" -o -name "*.htm" \
    -o -name "*.css" -o -name "*.scss" -o -name "*.sass" -o -name "*.less" \
    -o -name "*.styl" -o -name "*.sql" -o -name "*.graphql" -o -name "*.gql" \
    -o -name "*.proto" -o -name "*.yaml" -o -name "*.yml" -o -name "*.toml" \
    -o -name "*.json" -o -name "*.jsonc" -o -name "*.xml" -o -name "*.tf" \
    -o -name "*.hcl" -o -name "*.sh" -o -name "*.bash" -o -name "*.zsh" \
    -o -name "*.fish" -o -name "*.ps1" -o -name "*.md" -o -name "*.mdx" \
    -o -name "*.prisma" -o -name "*.sol" -o -name "*.zig" -o -name "*.nim" \
    -o -name "*.v" -o -name "*.cr" \
    -o -name Dockerfile -o -name Makefile \
  \) \
  ! -name "package-lock.json" \
  ! -name "yarn.lock" \
  ! -name "pnpm-lock.yaml" \
  ! -name "*.min.js" \
  ! -name "*.min.css" \
  ! -name "*.map" \
  ! -name "*.d.ts" \
  ! -name "*.snap" \
  ! -name "*.pyc" \
  ! -name "*.class" \
  ! -name "go.sum" \
  ! -name "Cargo.lock" \
  ! -name "poetry.lock" \
  -not -path "*.egg-info/*" \
  -print 2>/dev/null
FINDEOF
chmod +x "$FIND_SCRIPT"

# LOC 카운트
TOTAL=0
FILE_COUNT=0
while IFS= read -r file; do
  lines=$(grep -cve '^\s*$' "$file" 2>/dev/null || echo 0)
  TOTAL=$((TOTAL + lines))
  FILE_COUNT=$((FILE_COUNT + 1))
done < <(bash "$FIND_SCRIPT" "$PROJECT_DIR")

rm -f "$FIND_SCRIPT"

REMAINING=$((TARGET - TOTAL))
[ $REMAINING -lt 0 ] && REMAINING=0
PROGRESS=$(echo "scale=1; $TOTAL * 100 / $TARGET" | bc 2>/dev/null || echo "0")

# JSON 출력
cat <<EOF
{"gate":"loc","current":$TOTAL,"target":$TARGET,"remaining":$REMAINING,"progress_pct":$PROGRESS,"file_count":$FILE_COUNT,"passed":$([ $TOTAL -ge $TARGET ] && echo true || echo false)}
EOF

# exit 1 = 목표 도달, exit 0 = 미도달
[ $TOTAL -ge $TARGET ] && exit 1 || exit 0
