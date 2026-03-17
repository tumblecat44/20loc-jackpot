#!/usr/bin/env node
// usage-gate.js — 사용량 감지 (OAuth API > iteration 폴백)
// 출력: JSON (stdout), 종료코드: 항상 0

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
  } catch { return { threshold: 90, cooldown: 30, buffer: 60 }; }
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
  } catch {}
}

// macOS Keychain에서 credentials 읽기
function getCredentials() {
  try {
    const raw = execSync(
      'security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null',
      { encoding: 'utf8', timeout: 5000 }
    ).trim();
    const parsed = JSON.parse(raw);
    // 중첩 구조 대응: { claudeAiOauth: { accessToken, refreshToken } }
    const oauth = parsed.claudeAiOauth || parsed;
    return { accessToken: oauth.accessToken, refreshToken: oauth.refreshToken };
  } catch {
    // Linux 폴백
    try {
      const credPath = path.join(os.homedir(), '.claude', '.credentials.json');
      const parsed = JSON.parse(fs.readFileSync(credPath, 'utf8'));
      const oauth = parsed.claudeAiOauth || parsed;
      return { accessToken: oauth.accessToken, refreshToken: oauth.refreshToken };
    } catch { return null; }
  }
}

// 토큰 갱신
function refreshToken(creds) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({
      grant_type: 'refresh_token',
      refresh_token: creds.refreshToken,
      client_id: '9d1c250a-e61b-44d9-88ed-5944d1962f5e',
    });
    const req = https.request({
      hostname: 'platform.claude.com',
      path: '/v1/oauth/token',
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': body.length },
    }, (res) => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => {
        try { resolve(JSON.parse(data)); } catch { reject(new Error('token parse error')); }
      });
    });
    req.on('error', reject);
    req.setTimeout(10000, () => { req.destroy(); reject(new Error('timeout')); });
    req.write(body);
    req.end();
  });
}

// Usage API 호출
function fetchUsage(accessToken) {
  return new Promise((resolve, reject) => {
    const req = https.request({
      hostname: 'api.anthropic.com',
      path: '/api/oauth/usage',
      method: 'GET',
      headers: { 'Authorization': `Bearer ${accessToken}` },
    }, (res) => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => {
        try { resolve({ status: res.statusCode, body: JSON.parse(data) }); }
        catch { reject(new Error('usage parse error')); }
      });
    });
    req.on('error', reject);
    req.setTimeout(10000, () => { req.destroy(); reject(new Error('timeout')); });
    req.end();
  });
}

// iteration 폴백 — OAuth API 실패 시 사용
function iterationFallback(projectDir) {
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
    console.log(JSON.stringify(result));
    return;
  }

  // 2순위: OAuth API 직접 호출
  const creds = getCredentials();
  if (creds && creds.accessToken) {
    try {
      let resp = await fetchUsage(creds.accessToken);

      // 401 → 토큰 갱신 후 재시도
      if (resp.status === 401 && creds.refreshToken) {
        const newTokens = await refreshToken(creds);
        if (newTokens.access_token) {
          resp = await fetchUsage(newTokens.access_token);
        }
      }

      if (resp.status === 200) {
        const u = resp.body;
        const fiveHr = u.fiveHourPercent ?? u.five_hour?.utilization * 100 ?? 0;
        const weekly = u.weeklyPercent ?? u.weekly?.utilization * 100 ?? 0;
        const resetsAt = u.fiveHourResetsAt ?? u.five_hour?.resets_at ?? null;

        writeCache({ five_hour_pct: fiveHr, weekly_pct: weekly, resets_at: resetsAt, source: 'oauth' });

        const result = buildResult(fiveHr, weekly, resetsAt, 'oauth', cfg);
        console.log(JSON.stringify(result));
        return;
      }
    } catch {}
  }

  // 3순위: iteration 폴백 (최후 수단)
  console.log(JSON.stringify(iterationFallback(projectDir)));
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

main().catch(() => {
  console.log(JSON.stringify(iterationFallback(projectDir)));
});
