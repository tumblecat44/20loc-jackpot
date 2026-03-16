# Codeloop Design Document

> **Summary**: nowimslepe ralph-loop를 범용 Claude Code Plugin으로 추출 — Stop Hook 기반 자율 개발 루프 엔진
>
> **Project**: 20loc-jackpot (codeloop)
> **Date**: 2026-03-16
> **Status**: Draft
> **Planning Doc**: [ralph-loop-200k-loc-plugin.plan.md](../../01-plan/features/ralph-loop-200k-loc-plugin.plan.md)

---

## 1. 설계 목표

### 1.1 Design Goals

- nowimslepe의 검증된 루프 엔진을 **하드코딩 제거 + 파라미터화**만으로 범용화
- Claude Code Plugin 배포 구조로 **설치 즉시 사용** (Hook 수동 설정 불필요)
- OAuth API 기반 사용량 감지로 **정확한 rate limit 관리** (iteration 추정은 폴백)
- 플러거블 게이트로 **완료 조건 교체 가능**

### 1.2 Design Principles

- **엔진은 그대로, 껍질만 바꾼다** — Stop Hook + 상태 파일 ON/OFF + `claude -p` 파이프 + LOC 카운터는 원조 유지
- **20 LOC per gate** — 각 게이트는 독립 파일, 20줄 이내
- **설정으로 확장** — `codeloop.yaml` 하나로 프로젝트·게이트·프롬프트 제어

---

## 2. 아키텍처

### 2.1 전체 흐름도

```
┌─────────────────────────────────────────────────────────────────┐
│                     codeloop Plugin                              │
│                                                                  │
│  [/codeloop-init]          [/codeloop start]                    │
│       │                         │                                │
│   3문답 위저드             codeloop.yaml 파싱                    │
│       │                         │                                │
│   codeloop.yaml            상태 파일 생성                        │
│   PROMPT.md           .claude/codeloop.state.md                  │
│   scaffolding               │                                    │
│                    claude -p "$PROMPT"                            │
│                         │                                        │
│                    [Claude 자율 개발]                             │
│                         │                                        │
│                    Stop Hook 발화                                 │
│                    ┌────┴────┐                                   │
│                    │ orchestrator.sh                              │
│                    │    │                                         │
│                    │    ├─ usage-gate.js (OAuth API → sleep/pass) │
│                    │    ├─ gates/*.sh (loc/iterations/budget)     │
│                    │    ├─ dashboard.sh (status.md 갱신)          │
│                    │    └─ 게이트 통과? → exit 0 (반복)           │
│                    │         목표 도달? → 상태 파일 삭제 (종료)   │
│                    └─────────┘                                   │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 컴포넌트 의존 관계

```
                 ┌──────────────┐
                 │ codeloop.yaml │  ← 모든 컴포넌트의 설정 소스
                 └──────┬───────┘
                        │
         ┌──────────────┼──────────────┐
         ▼              ▼              ▼
┌──────────────┐ ┌────────────┐ ┌──────────────┐
│ commands/    │ │ hooks/     │ │ skills/      │
│ codeloop.md  │ │ stop-hook  │ │ codeloop-init│
│ (start/stop/ │ │ .sh        │ │ /SKILL.md    │
│  status)     │ └─────┬──────┘ └──────────────┘
└──────────────┘       │
                ┌──────┼──────────┐
                ▼      ▼          ▼
         ┌──────────┐ ┌────┐ ┌───────────┐
         │usage-gate│ │gate│ │ dashboard │
         │.js       │ │s/* │ │ .sh       │
         └──────────┘ └────┘ └───────────┘
```

### 2.3 데이터 흐름

```
codeloop.yaml → orchestrator → usage-gate → [sleep 또는 pass]
                     │                           │
                     ├─→ gates (loc/iter/budget) ─┤
                     │                           │
                     ├─→ dashboard.sh ─→ status.md
                     │
                     └─→ gate 결과: 목표 도달? → 상태 파일 삭제
                                    미도달?   → exit 0 (반복)
```

---

## 3. Plugin 구조

### 3.1 `.claude-plugin/plugin.json`

```json
{
  "name": "codeloop",
  "version": "1.0.0",
  "description": "AI 자율 개발 루프 엔진 — Stop Hook 기반 무한 반복 + 자동 사용량 관리",
  "author": "dgsw67",
  "hooks": {
    "Stop": [
      {
        "type": "command",
        "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/stop-hook.sh\"",
        "timeout": 600
      }
    ]
  },
  "skills": ["codeloop-init"],
  "commands": ["codeloop"]
}
```

**핵심**: `hooks` 필드로 Stop Hook 자동 등록 — 사용자가 `settings.local.json`을 편집할 필요 없음.

### 3.2 전체 파일 트리

```
codeloop/                              # GitHub 리포 = Plugin
├── .claude-plugin/
│   ├── plugin.json                    # 플러그인 메타 + 훅 자동 등록
│   └── marketplace.json               # 마켓플레이스 메타
├── hooks/
│   └── stop-hook.sh                   # 오케스트레이터 (~30줄)
├── scripts/
│   ├── usage-gate.js                  # OAuth API 사용량 감지 (~80줄)
│   ├── dashboard.sh                   # 마크다운 대시보드 생성 (~40줄)
│   ├── parse-yaml.sh                  # codeloop.yaml 파서 (~15줄)
│   └── gates/
│       ├── loc.sh                     # LOC 게이트 (~20줄, 원조 count-loc.sh 경량화)
│       ├── iterations.sh              # 반복 횟수 게이트 (~10줄)
│       ├── budget.sh                  # API 비용 게이트 (~15줄)
│       └── custom.sh                  # 사용자 정의 게이트 (~5줄)
├── skills/
│   └── codeloop-init/
│       ├── SKILL.md                   # /codeloop-init 위자드
│       └── references/
│           ├── stacks.md              # 6개 프리셋
│           └── prompt-template.md     # PROMPT.md 생성 템플릿
├── commands/
│   └── codeloop.md                    # /codeloop start|stop|status
└── README.md
```

---

## 4. 컴포넌트 상세 설계

### 4.1 Stop Hook Orchestrator (`hooks/stop-hook.sh`)

원조: `nowimslepe/.claude/hooks/stop-hook.sh`

**역할**: 매 Claude 세션 종료 시 자동 실행. usage → gates → dashboard 순서로 파이프라인 처리.

```bash
#!/bin/bash
# hooks/stop-hook.sh — Orchestrator
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
CONFIG="$PROJECT_DIR/codeloop.yaml"
STATE="$PROJECT_DIR/.claude/codeloop.state.md"
SCRIPTS="$PLUGIN_ROOT/scripts"

# 상태 파일 없으면 루프 아님 → 즉시 종료
[ -f "$STATE" ] || exit 0

# Step 1: Usage Gate (sleep 또는 pass)
node "$SCRIPTS/usage-gate.js" --config "$CONFIG" --project "$PROJECT_DIR"

# Step 2: Completion Gates
ALL_PASSED=true
for gate_config in $(parse_gates "$CONFIG"); do
  gate_type=$(echo "$gate_config" | jq -r '.type')
  if ! bash "$SCRIPTS/gates/${gate_type}.sh" "$CONFIG" "$PROJECT_DIR"; then
    ALL_PASSED=false
    break
  fi
done

# Step 3: Dashboard 갱신
bash "$SCRIPTS/dashboard.sh" "$CONFIG" "$PROJECT_DIR"

# Step 4: 목표 도달 시 상태 파일 삭제 → 루프 종료
if [ "$ALL_PASSED" = true ]; then
  rm -f "$STATE"
  echo "🎉 codeloop: 모든 게이트 통과 — 루프 종료"
fi

exit 0  # 항상 exit 0 — 루프 제어는 상태 파일로
```

**설계 결정**:
- `exit 0` 무조건 — 원조 패턴 유지. 루프 제어권은 상태 파일에 있음
- `${CLAUDE_PLUGIN_ROOT}` — 플러그인 루트 경로 환경변수 참조
- 게이트 순회: `codeloop.yaml`의 `gates` 배열을 순서대로 평가

### 4.2 Usage Gate (`scripts/usage-gate.js`)

원조: `nowimslepe/.claude/hooks/usage-gate.py` (Python, iteration 기반 추정)
**핵심 변경**: OAuth API 실측값 기반으로 전면 교체

**동작 흐름**:

```
1. 인증 정보 획득
   ├─ macOS: security find-generic-password -s "Claude Code-credentials" -w
   └─ Linux: ~/.claude/.credentials.json

2. accessToken 유효성 검증
   └─ 만료 시: POST platform.claude.com/v1/oauth/token (refreshToken)

3. 사용량 조회
   GET api.anthropic.com/api/oauth/usage
   Authorization: Bearer {accessToken}
   → { fiveHourPercent, weeklyPercent, fiveHourResetsAt }

4. 판단
   ├─ fiveHourPercent >= threshold (기본 90) → sleep(fiveHourResetsAt까지 + buffer)
   ├─ weeklyPercent >= 95 → 경고 출력 + 보수적 sleep
   └─ 그 외 → cooldown_seconds(기본 30초) 대기

5. 폴백 (OAuth 불가 시)
   └─ iteration 기반 추정 (원조 방식, MAX_ITER=40/window)
```

**인터페이스**:

```
입력: --config codeloop.yaml --project /path/to/project
출력: JSON (stdout)
{
  "source": "oauth",           // "oauth" | "iteration_fallback"
  "five_hour_pct": 87.5,
  "weekly_pct": 45.2,
  "resets_at": "2026-03-16T14:00:00Z",
  "action": "cooldown",       // "cooldown" | "sleep" | "warn"
  "sleep_seconds": 30
}
종료코드: 항상 0
```

**설정 (`codeloop.yaml` → `usage`)**:

```yaml
usage:
  threshold: 90            # fiveHourPercent 이 값 이상이면 sleep (기본 90)
  cooldown_seconds: 30     # 정상 시 대기 시간
  sleep_buffer_seconds: 60 # resets_at 이후 추가 버퍼
```

**보안 고려사항**:
- accessToken은 메모리에서만 사용, 파일에 기록하지 않음
- refreshToken 갱신 시 platform.claude.com HTTPS만 사용
- 캐시: `~/.codeloop/.usage-cache.json` (TTL 30초, oh-my-claudecode 패턴 참조)

### 4.3 Completion Gates (`scripts/gates/`)

각 게이트는 독립 실행 가능한 셸 스크립트. 20 LOC 이내.

**공통 인터페이스**:

```
입력: $1 = codeloop.yaml 경로, $2 = 프로젝트 디렉토리
출력: JSON (stdout) — 현재 값, 목표, 통과 여부
종료코드: 0 = 목표 미도달 (계속), 1 = 목표 도달 (종료 조건 충족)
```

> **주의**: 게이트의 exit code는 orchestrator의 exit code와 반대 의미.
> 게이트 exit 1 = "이 게이트의 종료 조건 충족" → orchestrator가 `ALL_PASSED=true` 확인 후 상태 파일 삭제.

#### 4.3.1 LOC Gate (`gates/loc.sh`)

원조: `nowimslepe/.claude/hooks/count-loc.sh` (234줄, 63개 확장자)

**경량화 전략**:
- 원조의 제외 목록/확장자 목록은 거의 그대로 유지 (검증됨)
- JSON 출력만 추가, 하드코딩(200K, Photo AI) 제거

```
입력: codeloop.yaml (gates.loc.target 읽기), 프로젝트 디렉토리
처리: find + grep -c (빈 줄 제외) — 원조 방식 그대로
출력:
{
  "gate": "loc",
  "current": 156789,
  "target": 200000,
  "remaining": 43211,
  "progress_pct": 78.4,
  "file_count": 523,
  "passed": false
}
```

#### 4.3.2 Iterations Gate (`gates/iterations.sh`)

```
입력: codeloop.yaml (gates.iterations.max), 상태 파일에서 iteration 읽기
출력:
{
  "gate": "iterations",
  "current": 42,
  "max": 500,
  "passed": false
}
```

#### 4.3.3 Budget Gate (`gates/budget.sh`)

```
입력: codeloop.yaml (gates.budget.max_usd), OAuth API 비용 정보 (가용 시)
출력:
{
  "gate": "budget",
  "current_usd": 12.50,
  "max_usd": 50.00,
  "passed": false
}
```

#### 4.3.4 Custom Gate (`gates/custom.sh`)

```
입력: codeloop.yaml (gates.custom.command)
처리: 사용자 지정 스크립트 실행, exit code로 판단
출력:
{
  "gate": "custom",
  "command": "./my-gate.sh",
  "exit_code": 0,
  "passed": false
}
```

### 4.4 Dashboard (`scripts/dashboard.sh`)

원조: `nowimslepe/.claude/hooks/stop-hook.sh` 내 loc-status.md 생성 로직

**출력 파일**: `{project}/.claude/loc-status.md` (기본값, `codeloop.yaml → dashboard.path`로 변경 가능)

**형식** (원조 대시보드 구조 유지):

```markdown
---
updated_at: "2026-03-16 16:36:10"
iteration: 42
phase: "BUILDING"
---

# 📊 {project.name} — Codeloop Dashboard

| Metric | Value |
|--------|-------|
| **LOC** | 156,789 / 200,000 |
| **Remaining** | 43,211 lines |
| **Files** | 523 |
| **Iteration** | #42 |
| **Phase** | BUILDING |
| **LOC Progress** | [████████████████████░░░░░░░░░░] 78.4% |
| **API Usage** | 5hr: 45% · Weekly: 22% |
| **Gates** | loc: ❌ · iterations: ❌ |

> Last updated: 2026-03-16 16:36:10
```

**Phase 결정 로직** (원조 패턴):

| 진행률 | Phase | 설명 |
|--------|-------|------|
| 0-25% | FOUNDATION | 기반 구축 |
| 25-50% | BUILDING | 핵심 기능 구현 |
| 50-75% | SCALING | 확장 및 최적화 |
| 75-90% | MOAT | 차별화 |
| 90-100% | POLISH | 마무리 |

### 4.5 Command (`commands/codeloop.md`)

`/codeloop` 슬래시 커맨드로 루프 제어.

#### `/codeloop start`

```
1. codeloop.yaml 존재 확인 (없으면 에러: "run codeloop init first")
2. PROMPT.md 읽기 (경로: codeloop.yaml → prompt)
3. 상태 파일 생성: .claude/codeloop.state.md
   ---
   active: true
   iteration: 0
   started_at: "{ISO 8601}"
   config: "codeloop.yaml"
   ---
   {PROMPT.md 내용}
4. claude --dangerously-skip-permissions --model {model} -p "$PROMPT"
5. Stop Hook이 자동으로 루프 제어
```

#### `/codeloop stop`

```
1. .claude/codeloop.state.md 삭제
2. "codeloop 루프 종료" 메시지 출력
```

#### `/codeloop status`

```
1. .claude/loc-status.md 읽기
2. 현재 LOC, 반복 횟수, 사용량, 게이트 상태 요약 출력
3. 상태 파일 없으면 "루프 미실행" 표시
```

---

## 5. 상태 파일 설계

### 5.1 `codeloop.state.md` (루프 ON/OFF 제어)

```yaml
---
active: true
iteration: 42
started_at: "2026-03-16T06:00:00Z"
config: "codeloop.yaml"
---

# 아래는 PROMPT.md 내용 (claude -p에 주입됨)
{PROMPT.md 전문}
```

- **존재 = 루프 ON**, 삭제 = 루프 OFF (원조 패턴 그대로)
- `iteration`은 orchestrator가 매 실행마다 +1 증가
- frontmatter의 `active: true`는 Ralph 플러그인 호환용

### 5.2 `loc-status.md` (대시보드)

- 매 Stop Hook 실행 시 `dashboard.sh`가 덮어쓰기
- Claude가 다음 반복에서 이 파일을 읽어 현재 상태 파악
- 경로: `codeloop.yaml → dashboard.path` (기본값: `.claude/loc-status.md`)

### 5.3 `.usage-cache.json` (사용량 캐시)

```json
{
  "cached_at": "2026-03-16T10:30:00Z",
  "ttl_seconds": 30,
  "five_hour_pct": 45.2,
  "weekly_pct": 22.1,
  "resets_at": "2026-03-16T14:00:00Z"
}
```

- 경로: `~/.codeloop/.usage-cache.json`
- TTL: 30초 (oh-my-claudecode 패턴)
- OAuth API 호출 횟수 최소화 목적

### 5.4 `loop.log` (이벤트 로그)

```
2026-03-16 10:30:00 | Iter #42 | LOC: 156789/200000 | 78.4% | Usage: 45% | Action: cooldown 30s
2026-03-16 10:31:30 | Iter #43 | LOC: 157102/200000 | 78.6% | Usage: 47% | Action: cooldown 30s
```

- 경로: `codeloop.yaml → dashboard.log` (기본값: `~/.codeloop/{project}/loop.log`)
- 한 줄 = 한 반복

---

## 6. 설정 파일 스키마 (`codeloop.yaml`)

```yaml
# === 필수 ===
project:
  name: "My SaaS"                    # 프로젝트 이름 (대시보드 표시용)

prompt: ./PROMPT.md                   # 매 반복마다 주입할 프롬프트 파일 경로
model: opus                           # Claude 모델 (opus | sonnet | haiku)

# === 게이트 (1개 이상 필수) ===
gates:
  - type: loc                         # LOC 게이트
    target: 200000                    # 목표 LOC
  - type: iterations                  # 반복 횟수 게이트
    max: 500
  # - type: budget
  #   max_usd: 50
  # - type: custom
  #   command: "./my-gate.sh"

# === 선택 ===
usage:
  threshold: 90                       # fiveHourPercent 이 값 이상이면 sleep (기본 90)
  cooldown_seconds: 30                # 정상 시 대기 시간 (기본 30)
  sleep_buffer_seconds: 60            # resets_at 이후 추가 대기 (기본 60)

dashboard:
  path: .claude/loc-status.md         # 대시보드 파일 경로
  log: ~/.codeloop/{project}/loop.log # 이벤트 로그 경로
```

**yaml 파싱**: `parse-yaml.sh` — `grep`/`sed` 기반 경량 파서 (외부 의존성 없음). 복잡한 중첩은 jq + yq 폴백.

---

## 7. 에러 처리

### 7.1 에러 시나리오별 대응

| 시나리오 | 감지 방법 | 대응 | 종료코드 |
|----------|----------|------|----------|
| codeloop.yaml 없음 | `[ ! -f "$CONFIG" ]` | "run codeloop init first" 에러 출력, 루프 시작 거부 | exit 1 (start 시) |
| 상태 파일 없음 (Stop Hook) | `[ ! -f "$STATE" ]` | 루프 아님 → 조용히 종료 | exit 0 |
| OAuth token 만료 | HTTP 401 응답 | refreshToken으로 자동 갱신 | — |
| OAuth 갱신 실패 | refreshToken도 만료 | iteration 폴백 모드 전환 + 경고 | exit 0 |
| OAuth API 불가 (API 키 사용자) | Keychain 없음 | iteration 폴백 모드 | exit 0 |
| 게이트 스크립트 실행 실패 | bash exit code != 0/1 | 해당 게이트 건너뛰기 + 경고 로그 | exit 0 |
| 네트워크 오류 | curl timeout | 보수적 sleep (30분) + 재시도 | exit 0 |

### 7.2 핵심 원칙

- **Stop Hook은 절대 exit 1하지 않는다** — 어떤 에러든 exit 0으로 종료하여 Claude 세션을 정상 종료시킨다
- 루프 중단이 필요하면 상태 파일을 삭제하는 것이 유일한 방법

---

## 8. 보안 고려사항

- [x] accessToken은 Keychain/credentials 파일에서 읽고 메모리에서만 사용 — 디스크에 평문 저장 안 함
- [x] refreshToken 갱신은 HTTPS(platform.claude.com) 전용
- [x] `.usage-cache.json`에 토큰 저장 안 함 (사용량 수치만 캐시)
- [x] `--dangerously-skip-permissions`는 사용자가 명시적으로 동의한 경우에만 (`codeloop start` 시 안내)
- [x] custom gate 스크립트는 프로젝트 로컬 경로만 허용 (절대 경로 원격 URL 금지)

---

## 9. 구현 순서

Plan 문서의 우선순위를 구체적 태스크로 분해:

### Phase 0: Plugin 뼈대

| # | 태스크 | 파일 | LOC |
|---|--------|------|-----|
| 0-1 | plugin.json 작성 | `.claude-plugin/plugin.json` | ~15 |
| 0-2 | marketplace.json 작성 | `.claude-plugin/marketplace.json` | ~10 |

### Phase 1: Stop Hook Orchestrator

| # | 태스크 | 파일 | LOC |
|---|--------|------|-----|
| 1-1 | orchestrator 본체 | `hooks/stop-hook.sh` | ~30 |
| 1-2 | yaml 파서 유틸 | `scripts/parse-yaml.sh` | ~15 |

### Phase 2: LOC Gate

| # | 태스크 | 파일 | LOC |
|---|--------|------|-----|
| 2-1 | LOC 카운터 (원조 count-loc.sh 경량화) | `scripts/gates/loc.sh` | ~60 (제외 목록 포함) |

### Phase 3: Usage Gate

| # | 태스크 | 파일 | LOC |
|---|--------|------|-----|
| 3-1 | OAuth 인증 + 사용량 조회 | `scripts/usage-gate.js` | ~80 |
| 3-2 | iteration 폴백 로직 | (usage-gate.js 내) | ~20 |

### Phase 4: Dashboard

| # | 태스크 | 파일 | LOC |
|---|--------|------|-----|
| 4-1 | 마크다운 대시보드 생성기 | `scripts/dashboard.sh` | ~40 |

### Phase 5: Command

| # | 태스크 | 파일 | LOC |
|---|--------|------|-----|
| 5-1 | /codeloop start\|stop\|status | `commands/codeloop.md` | ~50 |

### Phase 6: Init Wizard

| # | 태스크 | 파일 | LOC |
|---|--------|------|-----|
| 6-1 | SKILL.md (이미 존재, 검증) | `skills/codeloop-init/SKILL.md` | 기존 |
| 6-2 | stacks.md (이미 존재, 검증) | `skills/codeloop-init/references/stacks.md` | 기존 |
| 6-3 | prompt-template.md | `skills/codeloop-init/references/prompt-template.md` | ~100 |

### Phase 7: 추가 게이트

| # | 태스크 | 파일 | LOC |
|---|--------|------|-----|
| 7-1 | iterations gate | `scripts/gates/iterations.sh` | ~10 |
| 7-2 | budget gate | `scripts/gates/budget.sh` | ~15 |
| 7-3 | custom gate | `scripts/gates/custom.sh` | ~5 |

---

## 10. 원조 대비 변경 추적표

| 항목 | nowimslepe (원조) | codeloop (설계) | 변경 사유 |
|------|-------------------|-----------------|-----------|
| 배포 형태 | 로컬 .claude/hooks/ | Claude Code Plugin | 설치 즉시 사용 |
| Hook 등록 | settings.local.json 수동 | plugin.json 자동 | UX 개선 |
| 사용량 추적 | Python, iteration/40 추정 | Node.js, OAuth API 실측 | 정확도 |
| 리셋 시각 | KST 3am 하드코딩 | OAuth `fiveHourResetsAt` 실측 | 타임존 독립 |
| LOC 타겟 | 200K 하드코딩 | codeloop.yaml `gates.loc.target` | 파라미터화 |
| 상태 파일명 | ralph-loop.local.md | codeloop.state.md | 범용화 |
| 임시 파일 경로 | /tmp/photo-ai-* | ~/.codeloop/{project}/ | 프로젝트 격리 |
| exit 0 패턴 | ✅ 유지 | ✅ 유지 | — |
| 상태 파일 ON/OFF | ✅ 유지 | ✅ 유지 | — |
| 마크다운 대시보드 | ✅ 유지 | ✅ 유지 | — |
| LOC 제외 목록 | ✅ 유지 (63개 확장자) | ✅ 유지 | — |

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 0.1 | 2026-03-16 | Initial design — nowimslepe 레퍼런스 기반 | dgsw67 |
