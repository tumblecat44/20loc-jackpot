#!/usr/bin/env node
// usage-gate.js — 사용량 감지 (OAuth API > iteration 폴백)
// 출력: JSON (stdout), 종료코드: 항상 0
//
// ⚠️ 절대 refreshToken()을 호출하지 않는다.
// OAuth2 토큰 로테이션: refresh 호출 시 기존 access_token이 즉시 폐기되어
// 동시에 실행 중인 Claude Code 세션이 401로 죽는다.
// 토큰 갱신은 Claude Code 자체(/login)만 해야 한다.

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const https = require('https');
const os = require('os');

// CLI 인자 파싱
const args = process.argv.slice(2);
const configIdx = args.indexOf('--config');
const projectIdx = args.indexOf('--project');
const configPath = configIdx >= 0 ? args[configIdx + 1] : 'codeloop.yaml';
const projectDir = projectIdx >= 0 ? args[projectIdx + 1] : process.cwd();

// 설정 읽기 (경량 yaml 파싱)
function readConfig(file) {
  try {
    const text = fs.readFileSync(file, 'utf8');
    const get = (key) => {
      const m = text.match(new RegExp(`^\\s*${key}:\\s*(.+)`, 'm'));
      return m ? m[1].trim().replace(/^['"]|['"]$/g, '') : null;
    };
    let threshold = parseFloat(get('threshold')) || 90;
    // 0.90 같은 소수 표기(=90%) → 퍼센트로 변환
    if (threshold > 0 && threshold <= 1) threshold = threshold * 100;
    return {
      threshold,
      cooldown: parseInt(get('cooldown_seconds')) || 30,
      buffer: parseInt(get('sleep_buffer_seconds')) || 60,
    };
  } catch (e) {
    log(`readConfig error: ${e.message}`);
    return { threshold: 90, cooldown: 30, buffer: 60 };
  }
}

// 로깅 — 에러를 삼키지 않고 기록
const LOG_DIR = path.join(projectDir, '.claude', 'logs');
function log(msg) {
  try {
    fs.mkdirSync(LOG_DIR, { recursive: true });
    fs.appendFileSync(
      path.join(LOG_DIR, 'usage-gate.log'),
      `[${new Date().toISOString()}] ${msg}\n`
    );
  } catch {}
}

// 캐시 경로
const CACHE_DIR = path.join(os.homedir(), '.codeloop');
const CACHE_FILE = path.join(CACHE_DIR, '.usage-cache.json');
const CACHE_TTL = 30_000; // 30초

function readCache() {
  try {
    const data = JSON.parse(fs.readFileSync(CACHE_FILE, 'utf8'));
    if (Date.now() - new Date(data.cached_at).getTime() < CACHE_TTL) return data;
  } catch {}
  return null;
}

function writeCache(data) {
  try {
    fs.mkdirSync(CACHE_DIR, { recursive: true });
    fs.writeFileSync(CACHE_FILE, JSON.stringify({ ...data, cached_at: new Date().toISOString() }));
  } catch (e) { log(`writeCache error: ${e.message}`); }
}

// macOS Keychain에서 credentials 읽기 (읽기 전용 — 갱신 금지)
function getCredentials() {
  try {
    const raw = execSync(
      'security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null',
      { encoding: 'utf8', timeout: 5000 }
    ).trim();
    const parsed = JSON.parse(raw);
    // 중첩 구조 대응: { claudeAiOauth: { accessToken, refreshToken } }
    const oauth = parsed.claudeAiOauth || parsed;
    return { accessToken: oauth.accessToken };
  } catch (e) {
    // Linux 폴백
    try {
      const credPath = path.join(os.homedir(), '.claude', '.credentials.json');
      const parsed = JSON.parse(fs.readFileSync(credPath, 'utf8'));
      const oauth = parsed.claudeAiOauth || parsed;
      return { accessToken: oauth.accessToken };
    } catch (e2) {
      log(`getCredentials error: macOS=${e.message}, linux=${e2.message}`);
      return null;
    }
  }
}

// Usage API 호출
function fetchUsage(accessToken) {
  return new Promise((resolve, reject) => {
    const req = https.request({
      hostname: 'api.anthropic.com',
      path: '/api/oauth/usage',
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'anthropic-beta': 'oauth-2025-04-20',
      },
    }, (res) => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => {
        try {
          const retryAfter = parseInt(res.headers['retry-after']) || 0;
          resolve({ status: res.statusCode, body: JSON.parse(data), retryAfter });
        }
        catch { reject(new Error(`usage parse error: ${data.substring(0, 100)}`)); }
      });
    });
    req.on('error', reject);
    req.setTimeout(10000, () => { req.destroy(); reject(new Error('timeout')); });
    req.end();
  });
}

// iteration 폴백 — OAuth API 실패 시 사용
function iterationFallback(projectDir, reason) {
  log(`fallback: ${reason}`);
  const stateFile = path.join(projectDir, '.claude', 'codeloop.state.md');
  try {
    const text = fs.readFileSync(stateFile, 'utf8');
    const m = text.match(/^iteration:\s*(\d+)/m);
    const iter = m ? parseInt(m[1]) : 0;
    const MAX_PER_WINDOW = 40;
    const pct = Math.min((iter / MAX_PER_WINDOW) * 100, 100);
    return {
      source: 'iteration_fallback',
      five_hour_pct: pct,
      weekly_pct: 0,
      resets_at: null,
      iteration: iter,
      action: 'cooldown',
      sleep_seconds: 30,
    };
  } catch {
    return { source: 'iteration_fallback', five_hour_pct: 0, weekly_pct: 0, action: 'cooldown', sleep_seconds: 30 };
  }
}

async function main() {
  const cfg = readConfig(configPath);

  // 1순위: 자체 캐시 (이전 실행에서 저장한 값)
  const cached = readCache();
  if (cached && cached.five_hour_pct !== undefined) {
    const result = buildResult(cached.five_hour_pct, cached.weekly_pct, cached.resets_at, cached.source || 'cache', cfg);
    log(`cache hit: ${JSON.stringify(result)}`);
    console.log(JSON.stringify(result));
    return;
  }

  // 2순위: OAuth API 직접 호출 (읽기 전용 — refresh 절대 금지)
  const creds = getCredentials();
  if (creds && creds.accessToken) {
    try {
      const resp = await fetchUsage(creds.accessToken);
      log(`oauth response: status=${resp.status}`);

      if (resp.status === 200) {
        const u = resp.body;
        const fiveHr = u.fiveHourPercent ?? u.five_hour?.utilization * 100 ?? 0;
        const weekly = u.weeklyPercent ?? u.weekly?.utilization * 100 ?? 0;
        const resetsAt = u.fiveHourResetsAt ?? u.five_hour?.resets_at ?? null;

        writeCache({ five_hour_pct: fiveHr, weekly_pct: weekly, resets_at: resetsAt, source: 'oauth' });

        const result = buildResult(fiveHr, weekly, resetsAt, 'oauth', cfg);
        log(`oauth success: ${JSON.stringify(result)}`);
        console.log(JSON.stringify(result));
        return;
      }

      // 429 = 인증 성공이지만 rate limited → retry-after로 정확한 sleep 시간 파악
      if (resp.status === 429 && resp.retryAfter > 0) {
        const resetsAt = new Date(Date.now() + resp.retryAfter * 1000).toISOString();
        // 429 = 사용량 한도 도달 (100%) — retry-after가 리셋까지 남은 시간
        writeCache({ five_hour_pct: 100, weekly_pct: 0, resets_at: resetsAt, source: 'oauth_429' });
        const result = buildResult(100, 0, resetsAt, 'oauth_429', cfg);
        log(`oauth 429: retry-after=${resp.retryAfter}s, sleep=${result.sleep_seconds}s`);
        console.log(JSON.stringify(result));
        return;
      }

      // 401/기타 → refresh 시도 없이 바로 폴백
      // ⚠️ refresh하면 OAuth2 로테이션으로 Claude Code 세션 토큰이 죽음
      const errMsg = resp.body?.error?.message || `status ${resp.status}`;
      console.log(JSON.stringify(iterationFallback(projectDir, `oauth ${resp.status}: ${errMsg}`)));
      return;
    } catch (e) {
      console.log(JSON.stringify(iterationFallback(projectDir, `oauth error: ${e.message}`)));
      return;
    }
  }

  // 3순위: credential 없음 → iteration 폴백
  console.log(JSON.stringify(iterationFallback(projectDir, 'no credentials')));
}

function buildResult(fiveHrPct, weeklyPct, resetsAt, source, cfg) {
  let action = 'cooldown';
  let sleepSeconds = cfg.cooldown;

  if (fiveHrPct >= cfg.threshold) {
    action = 'sleep';
    if (resetsAt) {
      sleepSeconds = Math.max(0, Math.floor((new Date(resetsAt) - Date.now()) / 1000) + cfg.buffer);
    } else {
      sleepSeconds = 1800; // 30분 보수적 대기
    }
  } else if (weeklyPct >= 95) {
    action = 'warn';
    sleepSeconds = 300; // 5분 보수적 대기
  }

  return { source, five_hour_pct: fiveHrPct, weekly_pct: weeklyPct, resets_at: resetsAt, action, sleep_seconds: sleepSeconds };
}

main().catch((e) => {
  log(`fatal: ${e.message}`);
  console.log(JSON.stringify(iterationFallback(projectDir, `fatal: ${e.message}`)));
});
