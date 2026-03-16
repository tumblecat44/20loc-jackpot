#!/bin/bash
# parse-yaml.sh — 경량 YAML 파서 (외부 의존성 없음)
# 사용법: source parse-yaml.sh; yaml_get "key.subkey" file.yaml

yaml_get() {
  local key="$1" file="$2"
  local IFS='.' parts=($key) current="" depth=0 target_depth=${#parts[@]}
  local match_idx=0 indent=0

  while IFS= read -r line; do
    # 빈 줄/주석 건너뛰기
    [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]] && continue
    # 현재 들여쓰기 레벨
    indent=$(echo "$line" | sed 's/[^ ].*//' | wc -c)
    indent=$((indent - 1))
    local expected_indent=$((match_idx * 2))

    if [ $match_idx -lt $target_depth ]; then
      if [ $indent -eq $expected_indent ] && echo "$line" | grep -q "^[[:space:]]*${parts[$match_idx]}:"; then
        match_idx=$((match_idx + 1))
        if [ $match_idx -eq $target_depth ]; then
          echo "$line" | sed "s/^[[:space:]]*${parts[$((match_idx-1))]}:[[:space:]]*//" | sed 's/^["'\'']\(.*\)["'\'']$/\1/'
          return 0
        fi
      fi
    fi
  done < "$file"
  return 1
}

# gates 배열 파싱 — type 목록 반환
yaml_get_gates() {
  local file="$1"
  grep -A1 '^\s*- type:' "$file" | grep 'type:' | sed 's/.*type:[[:space:]]*//' | tr -d '"'\'''
}
