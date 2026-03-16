# Codeloop — 범용 AI 자율 개발 루프 엔진

## Executive Summary

| 관점 | 내용 |
|------|------|
| **Problem** | Claude Code는 세션 종료 후 자동 재개가 안 되고, 사용량 제한에 걸리면 멈춘다. 대규모 프로젝트를 AI가 자율적으로 계속 짤 방법이 없다 |
| **Solution** | nowimslepe에서 311K LOC 달성으로 검증된 Ralph Loop를 범용 OSS로 추출. Stop Hook 기반 자동 루프 + OAuth API 실시간 사용량 감지 + 플러거블 게이트 시스템 |
| **Function UX Effect** | `codeloop start` 한 번이면 목표 도달까지 Claude가 알아서 개발·sleep·재개를 반복 |
| **Core Value** | 소프트웨어 공장 — PROMPT.md 하나로 프로덕션 코드를 찍어낸다 |

---

## 0. 현재 프로젝트 구조

```
20loc-jackpot/
├── CLAUDE.md                              # 프로젝트 컨텍스트 (codeloop 철학·루프 구조·규칙)
├── docs/
│   └── 01-plan/
│       └── features/
│           └── ralph-loop-200k-loc-plugin.plan.md  # ← 이 문서
├── skills/
│   └── codeloop-init/                     # 셋업 위자드 스킬
│       ├── SKILL.md                       # 위자드 로직 (3문답 → 자동생성)
│       └── references/
│           ├── stacks.md                  # 6개 프리셋 (스택 + 디렉토리 구조)
│           └── prompt-template.md         # PROMPT.md 생성 템플릿
├── .claude/
│   └── rules/                             # 프로젝트 규칙 파일들
│       ├── 20loc-philosophy.md
│       ├── claude-code-internals.md
│       ├── codeloop-source-reference.md
│       ├── gate-plugin-pattern.md
│       ├── language.md
│       ├── pdca-workflow.md
│       ├── pre-dev-setup-skill.md
│       └── research-before-planning.md
└── .bkit/
    └── state/
        └── pdca-status.json               # PDCA 워크플로우 상태 추적
```

### 구현 후 목표 구조 (Claude Code Plugin)

배포 방식: **Claude Code Plugin** (npm CLI가 아님)
- 설치: `/plugin marketplace add user/codeloop` → `/plugin install codeloop`
- Stop Hook이 플러그인 설치 시 자동 등록됨 (사용자가 settings.local.json 안 만져도 됨)
- `${CLAUDE_PLUGIN_ROOT}` 환경변수로 스크립트 경로 참조

```
codeloop/                                  # ← GitHub 리포 = 플러그인 + 마켓플레이스
├── .claude-plugin/
│   ├── plugin.json                        # 플러그인 메타데이터 (name, version, hooks, skills)
│   └── marketplace.json                   # 마켓플레이스 등록 정보
├── hooks/
│   ├── hooks.json                         # Stop Hook 자동 등록 정의
│   └── stop-hook.sh                       # 오케스트레이터 (usage-gate → gates → dashboard)
├── scripts/
│   ├── usage-gate.js                      # OAuth API 사용량 감지 (핵심 개선)
│   ├── dashboard.sh                       # 마크다운 대시보드 생성
│   └── gates/
│       ├── loc.sh                         # LOC 게이트
│       ├── iterations.sh                  # 반복 횟수 게이트
│       ├── budget.sh                      # API 비용 게이트
│       └── custom.sh                      # 사용자 정의 게이트 템플릿
├── skills/
│   └── codeloop-init/
│       ├── SKILL.md                       # /codeloop-init 위자드 (3문답 → 자동생성)
│       └── references/
│           ├── stacks.md                  # 6개 프리셋
│           └── prompt-template.md         # PROMPT.md 생성 템플릿
├── commands/
│   └── codeloop.md                        # /codeloop start|stop|status 명령어
└── README.md
```

### codeloop를 사용하는 프로젝트 쪽 구조 (`/codeloop-init` 실행 후)

```
my-project/                                # ← 사용자의 프로젝트
├── PROMPT.md                              # 매 반복마다 claude -p에 주입되는 프롬프트
├── CLAUDE.md                              # 프로젝트 컨텍스트 (Claude가 참조)
├── codeloop.yaml                          # 루프 설정 (게이트·모델·프롬프트 경로)
├── .claude/
│   └── codeloop.state.md                  # 루프 ON/OFF 상태 파일 (실행 중 자동 생성)
└── packages/                              # 스캐폴딩 (프리셋에 따라 구조 다름)
```

> **변경점**: `.claude/settings.local.json`에 Stop Hook 수동 등록 불필요 — 플러그인이 `hooks/hooks.json`으로 자동 등록

---

## 1. 피처 개요

**피처명**: Codeloop (범용 AI 자율 개발 루프 엔진)
**원조**: nowimslepe/Photo AI 프로젝트에서 311K LOC 달성한 Ralph Loop
**목표**: 프로젝트 무관하게 `codeloop start`만으로 AI 자율 개발 루프를 돌리는 CLI 도구

### 원조 → 범용화 변환표

| 원조 (nowimslepe 하드코딩) | 범용화 (codeloop) |
|---|---|
| `Photo AI` 문구 전부 | `codeloop.yaml` → `project.name` |
| `TARGET_LOC=200000` | `codeloop.yaml` → `gates.loc.target` |
| `RESET_HOUR=3` (KST) | OAuth API `resets_at` 실측값 (타임존 불필요) |
| `MAX_ITERATIONS_PER_WINDOW=40` (추정) | OAuth API `five_hour.utilization` 실측값 |
| `/tmp/photo-ai-*` 경로 | `~/.codeloop/{project}/` |
| `PROMPT.md` 직접 읽기 | `codeloop.yaml` → `prompt` 경로 |
| PHASE 이름 하드코딩 | 사용자 정의 or LOC 기반 자동 |
| `usage-gate.py` (Python 272줄, iteration 추정) | `usage-gate.js` (Node.js, OAuth API 실측) |

---

## 2. 프로젝트 셋업 위자드 (`codeloop init`)

루프를 돌리기 전에 3가지만 물어보고 전부 자동 생성:

### 셋업 플로우

```
codeloop init
  │
  ├─ Q1: 뭘 만들지?
  │   ├─ 1. Web App (SaaS, 대시보드, 마켓플레이스)
  │   ├─ 2. Mobile App (iOS/Android)
  │   └─ 3. Full Stack (웹 + 모바일 + API + Worker + 인프라, 싹다)
  │
  ├─ Q2: 배포 환경?
  │   ├─ 1. Solo Vibe Coder (무료/저렴)
  │   │     → Vercel + Railway + Stripe
  │   └─ 2. Funded / Serious (스케일 대비)
  │         → AWS (EKS/RDS/S3) + Stripe + CloudFront
  │
  ├─ Q3: 한 줄로 설명해봐
  │   └─ "AI 사진 생성기 — 셀카 올리면 프로 사진 만들어줌"
  │
  ▼
자동 생성:
  ├─ codeloop.yaml          (루프 설정)
  ├─ PROMPT.md              (AI 창업가 프롬프트)
  ├─ CLAUDE.md              (프로젝트 컨텍스트)
  ├─ packages/ 디렉토리     (스캐폴딩)
  ├─ package.json, tsconfig (기본 설정)
  └─ .claude/settings.local.json (Stop Hook)
```

### 프리셋 매트릭스

| 타입 | Solo Vibe Coder | Funded |
|------|-----------------|--------|
| **Web** | Vercel + Railway + Stripe | AWS + Stripe |
| | Next.js API Routes, Prisma, R2 | Express 분리, RDS, S3, CloudFront |
| **Mobile** | Expo + Supabase + RevenueCat | Expo + Express + AWS + Stripe |
| **Full** | Vercel + Railway, 8개 패키지 | AWS EKS, 13+ 패키지 (Photo AI급) |

### 스킬 파일 위치

```
skills/codeloop-init/
├── SKILL.md                      # 위자드 로직
└── references/
    ├── stacks.md                 # 6개 프리셋 (스택 + 디렉토리 구조)
    └── prompt-template.md        # PROMPT.md 생성 템플릿 (311K LOC 검증)
```

핵심: **3개 질문 → 전부 자동 생성 → 바로 `codeloop start`**

---

## 3. 검증된 아키텍처 (원조에서 추출)

### 2.1 엔드-투-엔드 루프 플로우

```
codeloop start
  │
  ├─ codeloop.yaml 읽기
  ├─ 상태 파일 생성: .claude/codeloop.state.md (active: true)
  ├─ PROMPT 파일 읽기
  │
  ▼
claude --dangerously-skip-permissions --model {model} -p "$PROMPT"
  │
  │  [Claude가 자율 개발 수행]
  │
  ▼ (세션 종료 시 자동 발동)
Stop Hook (.claude/settings.local.json)
  │
  ├─ Step 1: Usage Gate (OAuth API)
  │   ├─ Keychain에서 accessToken 추출
  │   ├─ api.anthropic.com/api/oauth/usage 호출
  │   ├─ five_hour.utilization >= 0.90 → sleep(resets_at까지)
  │   └─ 아니면 → 30초 쿨다운
  │
  ├─ Step 2: Completion Gates (플러거블)
  │   ├─ LOC Gate: count-loc → 목표 도달?
  │   ├─ Budget Gate: API 비용 한도?
  │   ├─ Iteration Gate: 최대 반복?
  │   └─ Custom Gate: 사용자 스크립트
  │
  ├─ Step 3: Dashboard 업데이트
  │   └─ loc-status.md 갱신 (progress, phase, usage)
  │
  └─ Step 4: 게이트 통과?
      ├─ YES (목표 도달) → rm codeloop.state.md → 루프 종료
      └─ NO → exit 0 → 다음 반복 자동 시작
```

**핵심 메커니즘**: Stop Hook이 exit 0을 반환하면 Claude의 ralph-loop가 자동으로 다음 `claude -p` 호출을 트리거. 상태 파일 존재 = 루프 ON, 삭제 = 루프 OFF.

### 2.2 핵심 컴포넌트 (5개)

#### Component 1: Loop Engine (`engine.sh`)

원조 `start.sh`에서 추출. 역할:
- `codeloop.yaml` 파싱
- `.claude/codeloop.state.md` 생성 (frontmatter + 프롬프트 합침)
- `claude -p` 파이프 모드 호출
- CLI 인터페이스: `start`, `stop`, `status`

```bash
# 사용법
codeloop start                          # codeloop.yaml 기반 시작
codeloop start --prompt PROMPT.md       # 프롬프트 직접 지정
codeloop stop                           # 상태 파일 삭제 → 루프 종료
codeloop status                         # 현재 LOC, 사용량, 반복 횟수
```

#### Component 2: Stop Hook Orchestrator (`orchestrator.sh`)

원조 `stop-hook.sh`에서 추출. 역할:
- Usage Gate → Completion Gates → Dashboard 순서로 파이프라인 실행
- 모든 게이트의 exit code 해석 & 루프 제어
- 항상 exit 0 (루프 제어권은 상태 파일에)

#### Component 3: Usage Gate (`usage-gate.js`) — **원조 대비 핵심 개선점**

| 원조 | 범용화 |
|------|--------|
| Python, iteration/40 추정 | Node.js, OAuth API 실측 |
| 3am KST 하드코딩 | `resets_at` 필드에서 정확한 리셋 시각 |
| Claude Max 전용 | Claude Max / Pro / API 키 자동 감지 |

**OAuth API 사용량 체크 로직**:
```
1. macOS: security find-generic-password -s "Claude Code-credentials" -w
   Linux: ~/.claude/.credentials.json 읽기
2. accessToken 만료 시 → refreshToken으로 자동 갱신
   POST platform.claude.com/v1/oauth/token
   client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e
3. GET api.anthropic.com/api/oauth/usage
   Authorization: Bearer {accessToken}
   anthropic-beta: oauth-2025-04-20
4. Response:
   { "five_hour": { "utilization": 0.87, "resets_at": "2026-03-16T14:00:00Z" } }
5. utilization >= 0.90 → sleep(resets_at - now + 60초 버퍼)
6. utilization < 0.90 → 30초 쿨다운 후 다음 반복
```

**폴백**: OAuth 사용 불가 시 (API 키 사용자) → iteration 기반 추정 모드

#### Component 4: Completion Gates (플러거블)

원조 `count-loc.sh`에서 추출 + 확장:

```yaml
# codeloop.yaml 게이트 설정
gates:
  - type: loc
    target: 200000
  - type: iterations
    max: 100
  - type: budget
    max_usd: 50
  - type: custom
    command: "./my-gate.sh"
```

| 게이트 | 원조 파일 | 동작 |
|--------|-----------|------|
| `loc` | `count-loc.sh` (234줄, 63개 확장자, 58개 제외) | SLOC 카운트 → 목표 비교 |
| `iterations` | 새로 추가 | 반복 횟수 제한 |
| `budget` | 새로 추가 | API 비용 추적 (OAuth API 비용 정보) |
| `custom` | 새로 추가 | 사용자 스크립트 exit code로 판단 |

#### Component 5: Dashboard (`dashboard.sh`)

원조 `loc-status.md` 생성 로직에서 추출:
- 프로젝트명, 게이트 종류에 따라 동적 렌더링
- progress bar, phase 표시, 사용량 표시
- `~/.codeloop/{project}/status.md`에 저장

### 2.3 파일 구조 (Claude Code Plugin)

```
codeloop/                                  # GitHub 리포 = 플러그인
├── .claude-plugin/
│   ├── plugin.json                        # 플러그인 메타 (name, version, hooks, skills)
│   └── marketplace.json                   # 마켓플레이스 등록 정보
├── hooks/
│   ├── hooks.json                         # Stop Hook 자동 등록 {"hooks":{"Stop":[...]}}
│   └── stop-hook.sh                       # 오케스트레이터 (${CLAUDE_PLUGIN_ROOT} 참조)
├── scripts/
│   ├── usage-gate.js                      # OAuth API 사용량 감지
│   ├── dashboard.sh                       # 마크다운 대시보드 생성
│   └── gates/
│       ├── loc.sh                         # LOC 게이트 (원조 count-loc.sh 기반)
│       ├── iterations.sh                  # 반복 횟수 게이트
│       ├── budget.sh                      # API 비용 게이트
│       └── custom.sh                      # 사용자 정의 게이트 템플릿
├── skills/
│   └── codeloop-init/
│       ├── SKILL.md                       # /codeloop-init 위자드
│       └── references/
│           ├── stacks.md                  # 6개 프리셋
│           └── prompt-template.md         # PROMPT.md 생성 템플릿
├── commands/
│   └── codeloop.md                        # /codeloop start|stop|status
└── README.md
```

**배포**: GitHub → `/plugin marketplace add user/codeloop` → `/plugin install codeloop`
**Hook 등록**: 플러그인 설치 시 `hooks.json`으로 Stop Hook 자동 등록 (수동 설정 불필요)

### 2.4 설정 파일 (`codeloop.yaml`)

```yaml
project:
  name: "My SaaS"

prompt: ./PROMPT.md
model: opus

gates:
  - type: loc
    target: 200000
  - type: iterations
    max: 500

usage:
  threshold: 0.90           # 90%에서 sleep
  cooldown_seconds: 30      # 기본 쿨다운
  sleep_buffer_seconds: 60  # 리셋 후 추가 대기

dashboard:
  path: .claude/loc-status.md
  log: ~/.codeloop/{project}/loop.log
```

---

## 4. 제약사항 & 리스크

| 리스크 | 영향 | 대응 |
|--------|------|------|
| OAuth credentials 없음 (API 키 사용자) | 사용량 실측 불가 | iteration 기반 추정 폴백 |
| Token 갱신 실패 | API 호출 불가 | 보수적 sleep(30분) + 재시도 |
| Stop Hook에서 sleep 블로킹 | 프로세스 점유 | sleep은 정상 동작 (원조에서 검증됨) |
| LOC 품질 저하 (양만 채우기) | 코드 쓰레기 | 프롬프트에 품질 규칙 강제 (사용자 책임) |
| 같은 작업 반복 | 리소스 낭비 | loc-status.md를 Claude가 매번 읽어 상태 인지 |

---

## 5. 구현 우선순위

| 순서 | 컴포넌트 | 원조 대응 | 작업량 |
|------|----------|-----------|--------|
| 0 | **Plugin 뼈대** (`.claude-plugin/`, `hooks/hooks.json`) | 없음 (신규) | plugin.json + marketplace.json + hooks.json |
| 1 | **Stop Hook Orchestrator** (`hooks/stop-hook.sh`) | `stop-hook.sh` | `${CLAUDE_PLUGIN_ROOT}` 경로 적용 |
| 2 | LOC Gate (`scripts/gates/loc.sh`) | `count-loc.sh` 거의 그대로 | 하드코딩 제거만 |
| 3 | Usage Gate (`scripts/usage-gate.js`) | `usage-gate.py` → Node.js + OAuth API | **핵심 신규** |
| 4 | Dashboard (`scripts/dashboard.sh`) | `loc-status.md` 생성 로직 | 프로젝트명 변수화 |
| 5 | **Command** (`commands/codeloop.md`) | 없음 (신규) | `/codeloop start\|stop\|status` 슬래시 커맨드 |
| 6 | **Init Wizard** (`skills/codeloop-init/SKILL.md`) | 없음 (신규) | 스킬 + 프리셋 6개 |

---

## 6. 성공 기준

- [ ] `codeloop init` → 3개 질문 후 codeloop.yaml + PROMPT.md + 스캐폴딩 자동 생성
- [ ] `codeloop start` → 루프 시작, 목표 LOC 도달 시 자동 정지
- [ ] `codeloop stop` → 즉시 루프 종료
- [ ] `codeloop status` → 현재 LOC, 사용량, 반복 횟수 표시
- [ ] OAuth API 기반 사용량 90% 이상에서 자동 sleep, `resets_at`까지 대기 후 재개
- [ ] `codeloop.yaml` 하나로 프로젝트·게이트·프롬프트 설정 가능
- [ ] 다른 프로젝트에서 `codeloop.yaml` + `PROMPT.md`만 작성하면 즉시 사용 가능

---

## 7. 20 LOC Jackpot 철학

> "codeloop.yaml 20줄 + PROMPT.md 한 장 = 20만 줄의 프로덕션 코드"

nowimslepe에서 311K LOC로 검증됨.
이제 공장을 범용화한다.
