# Codeloop — AI Autonomous Dev Loop

`codeloop start` 한 번이면 목표 LOC까지 AI가 알아서 개발 · sleep · 재개를 반복한다.

nowimslepe 프로젝트에서 **311K LOC** 달성으로 검증된 Ralph Loop 엔진을 범용 Claude Code Plugin으로 추출.

> "codeloop.yaml 20줄 + PROMPT.md 한 장 = 20만 줄의 프로덕션 코드"

## Install

```bash
# 1. Marketplace 등록
/plugin marketplace add https://github.com/tumblecat44/20loc-jackpot.git

# 2. 플러그인 설치
/plugin install codeloop@tumblecat44-20loc-jackpot
```

또는 대화형 UI에서:

```bash
/plugin
# → Discover 탭 → codeloop 선택 → 설치 범위(user/project/local) 선택
```

설치하면 Stop Hook이 자동 등록된다. `settings.local.json`을 직접 편집할 필요 없음.

## Quick Start

```bash
# 1. 프로젝트 셋업 (3문답 위저드)
/codeloop-init

# 2. 루프 시작
/codeloop start

# 3. 상태 확인
/codeloop status

# 4. 루프 중지
/codeloop stop
```

## How It Works

```
codeloop start
  → claude -p (PROMPT.md 주입)
    → Claude 자율 개발
      → Stop Hook 자동 발동
        ├─ Usage Gate (OAuth API → sleep or pass)
        ├─ Completion Gates (loc/iterations/budget/custom)
        ├─ Dashboard 갱신 (loc-status.md)
        └─ 게이트 통과? → 루프 종료 : exit 0 → 반복
```

- **상태 파일 ON/OFF**: `.claude/codeloop.state.md` 존재 = 루프 ON, 삭제 = OFF
- **exit 0 패턴**: Stop Hook은 항상 exit 0 — 루프 제어권은 상태 파일에
- **OAuth API 1순위**: `fiveHourPercent` 실측값으로 정확한 rate limit 관리

## codeloop.yaml

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
  threshold: 90
  cooldown_seconds: 30
  sleep_buffer_seconds: 60

dashboard:
  path: .claude/loc-status.md
```

## Gates

| Gate | Example | Description |
|------|---------|-------------|
| `loc` | `target: 200000` | 누적 LOC 목표 도달 시 종료 |
| `iterations` | `max: 500` | 반복 횟수 제한 |
| `budget` | `max_usd: 50` | API 비용 한도 |
| `custom` | `command: "./my-gate.sh"` | 사용자 스크립트 |

## Project Structure

```
codeloop/
├── .claude-plugin/
│   ├── plugin.json          # Plugin meta + Stop Hook 자동 등록
│   └── marketplace.json     # Marketplace 등록 정보
├── hooks/
│   └── stop-hook.sh         # Orchestrator
├── scripts/
│   ├── usage-gate.js        # OAuth API 사용량 감지
│   ├── dashboard.sh         # Markdown 대시보드
│   ├── parse-yaml.sh        # YAML 파서
│   └── gates/
│       ├── loc.sh           # LOC gate
│       ├── iterations.sh    # Iterations gate
│       ├── budget.sh        # Budget gate
│       └── custom.sh        # Custom gate
└── skills/
    ├── codeloop/
    │   └── SKILL.md          # /codeloop start|stop|status
    └── codeloop-init/
        ├── SKILL.md          # /codeloop-init 위저드
        └── references/
            ├── stacks.md
            └── prompt-template.md
```

## License

MIT
