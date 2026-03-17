# Fixed Stack: web-solo (2026.03)

codeloop-init은 단일 스택만 사용한다. 선택지 없음.

**Version policy**: 프로젝트 생성 시 `npm info {pkg} version` / `pip index versions {pkg}`로 최신 stable 확인 후 핀.

## Stack Definition

```yaml
# Frontend
frontend: Next.js 16 (App Router, Turbopack)
ui: React 19, TypeScript 6, Tailwind CSS 4, shadcn/ui

# Backend
backend: Python FastAPI 0.135 (uvicorn, async)
orm: SQLAlchemy 2.0 + Alembic
validation: Pydantic v2

# Infrastructure
database: Railway PostgreSQL 18
cache: Railway Redis 8 (if needed)
storage: Cloudflare R2 (S3-compatible)

# Auth
auth: FastAPI JWT + OAuth (Google, GitHub) / Clerk frontend (optional)

# Payments
payments: Stripe (Checkout, Subscriptions, Webhooks)

# Deploy
deploy_frontend: Vercel (Git Integration — push to main = auto-deploy)
deploy_backend: Railway (Git Integration — push to main = auto-deploy)
ci_cd: GitHub Actions (lint + test on PR, backup deploy on main)

# Monitoring
monitoring: Vercel Analytics + Sentry (free tier)

# Runtime
runtime_frontend: Node.js 24 LTS
runtime_backend: Python 3.13
```

## Directory Structure

```
{project-name}/
├── packages/
│   ├── web/              # Next.js 16 (App Router)
│   │   ├── src/
│   │   │   ├── app/      # App Router pages
│   │   │   ├── components/
│   │   │   └── lib/
│   │   ├── public/
│   │   ├── package.json
│   │   ├── tsconfig.json
│   │   ├── tailwind.config.ts
│   │   └── next.config.ts
│   │
│   ├── api/              # FastAPI backend
│   │   ├── app/
│   │   │   ├── main.py
│   │   │   ├── routers/
│   │   │   ├── models/
│   │   │   ├── schemas/
│   │   │   ├── services/
│   │   │   └── core/     # config, security, db
│   │   ├── alembic/      # DB migrations
│   │   ├── pyproject.toml
│   │   └── Dockerfile
│   │
│   ├── shared/           # Shared types
│   │   ├── types.ts      # TypeScript types
│   │   └── models.py     # Pydantic models
│   │
│   └── scripts/          # Seed, setup, migrations
│       ├── seed.py
│       └── setup.sh
│
├── .github/
│   └── workflows/
│       ├── ci.yml        # Lint + test on PR
│       └── deploy.yml    # Backup deploy on main merge
│
├── codeloop.yaml
├── PROMPT.md
├── CLAUDE.md
├── start.sh
├── validate-env.sh
├── .env.example
├── .env.local            # Secrets (gitignored)
├── vercel.json
├── railway.toml
└── .gitignore
```

## Deploy Configs

### vercel.json
```json
{
  "buildCommand": "cd packages/web && npm run build",
  "outputDirectory": "packages/web/.next",
  "installCommand": "cd packages/web && npm install",
  "framework": "nextjs"
}
```

### railway.toml
```toml
[build]
builder = "dockerfile"
dockerfilePath = "packages/api/Dockerfile"

[deploy]
startCommand = "cd packages/api && alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port $PORT"
healthcheckPath = "/health"
restartPolicyType = "on_failure"
```

### .github/workflows/ci.yml (skeleton)
```yaml
name: CI
on: [pull_request]
jobs:
  lint-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Frontend lint + type check
        run: cd packages/web && npm ci && npm run lint && npm run type-check
      - name: Backend lint + test
        run: cd packages/api && pip install -e ".[dev]" && ruff check . && pytest
```
