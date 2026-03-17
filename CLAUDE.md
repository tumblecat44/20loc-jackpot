User communicates in Korean — always respond in Korean unless explicitly asked otherwise.
This project's core philosophy is achieving maximum real-world impact with ~20 lines of code ("20 LOC jackpot"), so every solution should be ruthlessly minimal yet complete.
`bkit` is the project's development pipeline tool; the PDCA workflow (`/pdca plan {feature}`) is the standard planning cycle used here.
PDCA plan docs are saved to `docs/01-plan/features/{feature-name}.plan.md`; workflow state is tracked in `.bkit/state/pdca-status.json` (fields: activeFeatures[], primaryFeature, features{phase/startedAt/planPath}).
Always end assistant responses with the recommended next step in the format: `/pdca {next-phase} {feature-name}`.
Usage 모니터링 훅은 `Stop` 훅을 사용할 것 — `PostToolUse`는 호출 빈도가 너무 높아 부적합.
이 프로젝트의 핵심 산출물은 `codeloop` CLI — 범용 자율 코드 생성 루프; 인터페이스: `codeloop start --prompt --target --model --gate`; 게이트는 loc/tests/budget/iterations 등 플러그블 조건.
`/Users/dgsw67/nowimslepe`는 패턴 일반화의 소스 프로젝트("20만 LOC 커스텀")로, codeloop 설계 시 이 프로젝트의 구현 패턴을 참조한다; nowimslepe의 자율 코딩 루프 구현체 이름은 **ralph-loop**이며, codeloop는 ralph-loop를 베이스로 범용화한 직계 후속 프로젝트다.
codeloop = ralph-loop 엔진 위에 범용 껍질을 씌운 것 — 엔진(Stop Hook + state-file ON/OFF + claude -p pipe mode + LOC counter) 자체는 원조 그대로 유지; 변경점은 단 2가지: 하드코딩→yaml config, iteration 추정→OAuth API.
codeloop 루프 구조: `start.sh → claude --dangerously-skip-permissions -p → (Stop Hook) → usage-gate(OAuth API 실측값 기반: fiveHourPercent/fiveHourResetsAt) → count-loc → LOC≥target? stop : exit 0 → repeat`; Stop Hook은 반드시 `exit 0`으로 종료해야 루프가 계속된다(루프 제어권은 Hook에 있음).
nowimslepe 레퍼런스 소스는 `.claude/hooks/` 디렉터리에 있으며, 일반화 시 제거 대상: KST 3am 하드코딩·200K LOC 하드코딩·`ralph-loop.local.md` 이름·Photo AI 전용 경로·iteration 기반 usage 추정(OAuth API 불가 시 폴백으로만 허용); 유지 대상: exit-0 패턴·state-file ON/OFF·LOC 카운터·markdown 대시보드.
usage-gate 구현 원칙: OAuth API(`GET api.anthropic.com/api/oauth/usage`)가 정확한 방식 — iteration 추정은 OAuth API를 모를 때 쓴 임시 방편이므로 codeloop에서는 OAuth API 우선, iteration은 폴백으로만 사용.
배포 프로파일 2종: "1인 바이버"(저자본 인디) = Vercel + Railway + Stripe; "자본 있음"(펀딩/엔터프라이즈) = AWS + Stripe.
개발 시작 전 필수 절차: `/skill-creator` 실행 → 프로젝트 유형(app/web/풀스택) 선택 → 배포 프로파일 선택 → 환경 세팅 완료 후 개발 착수.
스킬 파일 구조: `skills/{skill-name}/SKILL.md` + `skills/{skill-name}/references/` (stacks.md, prompt-template.md 등); `.claude/skills/`가 아닌 프로젝트 루트 `skills/` 디렉터리에 저장.
`codeloop init` 위저드 3문답(필수 선행): Q1 빌드 유형(Web/Mobile/FullStack) → Q2 배포 프로파일(solo-vibe/funded) → Q3 한줄 설명 → 자동 생성: `codeloop.yaml` + `PROMPT.md` + scaffolding + hooks; `codeloop start` 전 반드시 실행.
스택 버전은 항상 WebSearch로 최신 stable 버전을 확인 후 작성 — 기억이나 이전 파일 복사로 버전을 적지 않는다; 검증된 현재 버전(2026-03): Next.js 16, Node.js 24 LTS, React 19.2, TypeScript 5, Tailwind v4, Prisma 7, Express 5, React Native 0.84, Expo SDK 55, PostgreSQL 17, Redis 8.6.
백엔드 프레임워크는 FastAPI 고정(Express 사용 금지), DB는 PostgreSQL 고정 — 선택지가 아닌 고정값이며 스킬/스캐폴딩 생성 시 이 기준을 따른다.
`skills/*/references/stacks.md` 등 모든 스킬 참조 파일에도 FastAPI/PostgreSQL 기본값이 반드시 반영되어야 한다 — 규칙 파일과 실제 프리셋 파일의 동기화는 별도로 검증할 것.
외부 라이브러리/API 사용 시 반드시 `chub get <id>`로 최신 문서를 확인한 후 코딩 — 훈련 데이터의 기억에 의존하지 않는다; context-hub(`@aisuite/chub`)는 플러그인 설치 시 SessionStart 훅이 자동 설치하며, `skills/get-api-docs/SKILL.md` 스킬이 사용법을 안내한다.
