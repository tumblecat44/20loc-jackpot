# 상황 진단: usage-gate OAuth API 완전 차단 — 사용량 감지 체계 재설계 필요

## 상황

codeloop의 `usage-gate.js`가 의존하는 Anthropic OAuth API 2개 엔드포인트가 모두 차단됨:
- `GET api.anthropic.com/api/oauth/usage` → 401 "OAuth authentication is currently not supported."
- `POST platform.claude.com/v1/oauth/token` → 400 "invalid_grant"

catch {} 빈 에러 핸들링 때문에 45 iterations 동안 아무도 몰랐고, iteration_fallback(허수)만 동작함.

## 문제 분해

### 근본 문제 (Atomic Unit)
**codeloop에 실제 API 사용량 데이터를 공급하는 경로가 없다.**

### Subproblems

1. **사용량 데이터 소스 확보** — OAuth API 대체할 실측 데이터 경로 확보. 완료 조건: usage-gate가 실제 수치를 리턴
2. **rate limit 감지 및 대응** — API 한도 도달 시 자동 sleep/재개. 완료 조건: 429/overloaded 시 자동 대기 후 루프 재개
3. **start.sh 토큰 만료 대응** — pipe 모드에서 토큰 만료 시 자동 복구. 완료 조건: 401 시 자동 재인증 또는 사용자 안내
4. **에러 가시화** — catch {} 제거, 실패 원인 로깅. 완료 조건: 모든 에러가 codeloop.log에 기록됨

### 의존 관계
```
4 (에러 가시화) → 독립, 먼저 가능
1 (데이터 소스) → 2 (rate limit 대응)에 영향
3 (토큰 만료) → 독립
```

## 진단
- **유형**: D (에러 미궁) + F (압도) — 다층 401이 원인을 가렸고, OAuth 차단 확인 후 "대안이 뭔데?"가 막막
- **핵심 원인**: Anthropic이 OAuth 기반 usage API를 차단함 + 빈 catch가 실패를 은닉
- **놓치고 있던 것**: `claude -p --output-format json`이 세션별 `total_cost_usd`, `usage` (토큰), `stop_reason`, `is_error`를 이미 리턴함. OAuth API 없어도 사용량 추적 가능.

## 실증 데이터 (2026-03-17 조사)

### 발견 1: OAuth API 완전 차단
```
GET api.anthropic.com/api/oauth/usage (유효한 accessToken)
→ 401: "OAuth authentication is currently not supported."
```

### 발견 2: Refresh Token 무효화
```
POST platform.claude.com/v1/oauth/token
→ 400: {"error": "invalid_grant", "error_description": "Refresh token not found or invalid"}
```

### 발견 3: Keychain 접근은 정상
```
직접 호출, bash -c, pipe stdin, Node.js execSync → 전부 성공
```

### 발견 4: claude -p JSON output에 사용량 포함
```json
{
  "total_cost_usd": 0.2622225,
  "usage": {
    "input_tokens": 2,
    "cache_creation_input_tokens": 41486,
    "output_tokens": 117
  },
  "stop_reason": "end_turn",
  "is_error": false
}
```

## 접근법

### 접근 1: Reactive — claude -p 종료 코드/출력 기반 감지
`claude -p --output-format json`의 출력에서 `is_error`, `stop_reason`, `total_cost_usd`를 파싱.
rate limit 에러면 sleep, 정상이면 계속. 사전 예측 대신 사후 반응.

- 장점: OAuth API 의존성 완전 제거. 구현 단순. Claude CLI가 보장하는 공식 출력.
- 단점: rate limit에 "걸린 후" 감지 (사전 방지 불가). 5-hour window 전체 사용률은 모름.

### 접근 2: Cumulative Tracking — 세션별 cost 누적으로 예산 게이트
`total_cost_usd`를 파일에 누적 기록. 5시간 rolling window로 합산.
임계값(예: $50/5hr) 초과 시 proactive sleep.

- 장점: 사전 예방 가능. OAuth API 불필요. 실측 기반.
- 단점: 실제 계정 한도와의 매핑이 부정확 (Max plan 한도가 공개값 아님). 임계값 튜닝 필요.

### 접근 3: Hybrid — Reactive + `--max-budget-usd` CLI 옵션 활용
claude CLI의 `--max-budget-usd` 옵션으로 세션당 예산 제한 + 종료 시 에러 감지.
iteration별 예산 캡을 걸어서 한 iteration이 과도하게 소모하는 것 방지.

- 장점: CLI 네이티브 기능. 세션당 안전장치. Reactive와 결합하면 이중 보호.
- 단점: `--max-budget-usd`의 정확한 동작(초과 시 exit code 등) 검증 필요.

## 선택한 접근: {사용자 선택 대기}

## 체크리스트

> 다음 한 걸음: catch {} 제거하고 에러 로깅부터 추가 (5분 작업)

- [ ] **usage-gate.js catch {} → 에러 로깅으로 교체** ← START HERE
- [ ] `--output-format json` 출력 파싱 로직 설계
- [ ] `--max-budget-usd` 옵션 동작 검증 (exit code, 초과 시 행동)
- [ ] start.sh에서 `claude -p` 출력을 JSON으로 변경하고 결과 파싱
- [ ] stop-hook.sh에 이전 세션 결과(cost, error) 전달 로직 추가
- [ ] usage-gate.js를 새 데이터 소스 기반으로 재작성
- [ ] iteration_fallback 로직 정리 (필요 시 유지 또는 제거)
- [ ] 401 시 자동 안내 메시지 추가 (`claude /login` 실행 안내)
- [ ] onepersonbranding에서 5+ iterations 실제 루프 테스트
- [ ] 완료 확인: OAuth API 의존성 0, 실제 사용량 기반 sleep/continue 동작
