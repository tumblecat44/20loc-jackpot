# Stack Presets (2026.03 Latest)

Selection matrix: `Q1 (type)` x `Q2 (budget)` = preset.

**Version policy**: Always use the latest stable version at project creation time.
Check `npm info {pkg} version` / `pip index versions {pkg}` before pinning.

**Fixed choices**:
- Backend: **FastAPI** (Python) — 모든 프리셋 공통
- Database: **PostgreSQL** — 모든 프리셋 공통
- ORM: **SQLAlchemy 2 + Alembic** (Python 생태계 통일)

## Web App Presets

### web-solo — Web + Solo Vibe Coder

```yaml
frontend: Next.js 16 (App Router, Turbopack), React 19, TypeScript 6, Tailwind CSS 4, shadcn/ui
backend: Python FastAPI 0.135 (uvicorn, async)
database: Railway PostgreSQL 18 (SQLAlchemy 2 + Alembic)
cache: Railway Redis 8 (if needed)
auth: FastAPI JWT + OAuth (Google, GitHub) / Clerk frontend
payments: Stripe
storage: Cloudflare R2 (S3-compatible, free tier generous)
deploy_frontend: Vercel
deploy_backend: Railway
monitoring: Vercel Analytics + Sentry (free tier)
runtime: Node.js 24 LTS (frontend), Python 3.13 (backend)
```

**Directory structure:**
```
packages/
├── web/              # Next.js 16 app
├── api/              # FastAPI backend
├── shared/           # Shared types (Pydantic models + TS types)
└── scripts/          # Seed, setup, migrations
```

### web-funded — Web + Funded

```yaml
frontend: Next.js 16 (App Router, Turbopack), React 19, TypeScript 6, Tailwind CSS 4, shadcn/ui
backend: Python FastAPI 0.135 (uvicorn, async, structured logging)
database: AWS RDS PostgreSQL 18 (SQLAlchemy 2 + Alembic)
cache: AWS ElastiCache Redis 8
auth: FastAPI JWT + OAuth (Google, GitHub, Apple)
payments: Stripe (Checkout, Subscriptions, Webhooks)
storage: AWS S3 + CloudFront CDN
deploy: AWS EKS (Kubernetes 1.35) or ECS Fargate
monitoring: Prometheus + Grafana, structlog
ci_cd: GitHub Actions
infra: Terraform 1.14
runtime: Node.js 24 LTS (frontend), Python 3.13 (backend)
```

**Directory structure:**
```
packages/
├── frontend/         # Next.js 16 app
├── api/              # FastAPI backend
├── shared/           # Shared types
├── infrastructure/   # Terraform, K8s manifests, CI/CD
└── scripts/          # Seed, setup, migrations
```

## Mobile App Presets

### mobile-solo — Mobile + Solo Vibe Coder

```yaml
mobile: React Native 0.84 (Expo SDK 55, New Architecture default)
backend: Python FastAPI 0.135 (uvicorn)
database: Railway PostgreSQL 18 (SQLAlchemy 2 + Alembic)
auth: FastAPI JWT + OAuth / Expo AuthSession
payments: RevenueCat (in-app purchases) + Stripe (web billing)
storage: Cloudflare R2
push: Expo Push Notifications
deploy_backend: Railway
deploy_mobile: EAS Build + EAS Submit
runtime: Node.js 24 LTS, Python 3.13
```

**Directory structure:**
```
packages/
├── mobile/           # React Native 0.84 (Expo SDK 55)
├── api/              # FastAPI backend
├── shared/           # Shared types
└── scripts/          # Setup
```

### mobile-funded — Mobile + Funded

```yaml
mobile: React Native 0.84 (Expo SDK 55, bare workflow)
backend: Python FastAPI 0.135 (uvicorn, structured logging)
database: AWS RDS PostgreSQL 18 (SQLAlchemy 2 + Alembic)
cache: AWS ElastiCache Redis 8
auth: FastAPI JWT + OAuth + Apple Sign In
payments: Stripe + RevenueCat (in-app purchases)
storage: AWS S3
push: AWS SNS / Firebase Cloud Messaging
deploy_backend: AWS EKS (Kubernetes 1.35)
deploy_mobile: EAS Build + App Store / Play Store
ci_cd: GitHub Actions
infra: Terraform 1.14
runtime: Node.js 24 LTS, Python 3.13
```

**Directory structure:**
```
packages/
├── mobile/           # React Native 0.84 (Expo SDK 55)
├── api/              # FastAPI backend
├── shared/           # Shared types
├── infrastructure/   # Terraform, K8s, CI/CD
└── scripts/          # Seed, setup
```

## Full Stack Presets

### full-solo — Full Stack + Solo Vibe Coder

```yaml
frontend: Next.js 16 (App Router, Turbopack), React 19, TypeScript 6, Tailwind CSS 4, shadcn/ui
mobile: React Native 0.84 (Expo SDK 55)
backend: Python FastAPI 0.135 (uvicorn, async)
worker: Celery + Redis 8 (or ARQ for lightweight async tasks)
database: Railway PostgreSQL 18 (SQLAlchemy 2 + Alembic)
cache: Railway Redis 8
auth: FastAPI JWT + OAuth (shared between web/mobile)
payments: Stripe
storage: Cloudflare R2
deploy_frontend: Vercel
deploy_backend: Railway
deploy_mobile: EAS Build
monitoring: Sentry + Vercel Analytics
runtime: Node.js 24 LTS (frontend/mobile), Python 3.13 (backend)
testing: Pytest, Playwright 1.58
```

**Directory structure:**
```
packages/
├── frontend/         # Next.js 16 web app
├── mobile/           # React Native 0.84 (Expo SDK 55)
├── api/              # FastAPI backend (API + auth + billing)
├── worker/           # Celery workers (async jobs)
├── shared/           # Shared types (Pydantic + TS)
├── ui/               # Shared UI components
├── sdk/              # API client SDK (TypeScript)
└── scripts/          # Seed, setup
```

### full-funded — Full Stack + Funded (Photo AI reference architecture)

Battle-tested preset from the 311K LOC Photo AI project, updated to latest versions.
Backend unified to FastAPI.

```yaml
frontend: Next.js 16 (App Router, Turbopack), React 19, TypeScript 6, Tailwind CSS 4, shadcn/ui
mobile: React Native 0.84 (Expo SDK 55)
desktop: Electron 35 (optional)
backend: Python FastAPI 0.135 (uvicorn, async, structured logging)
ml_service: FastAPI (same codebase or separate, for AI/ML features)
worker: Celery + Redis 8 (heavy tasks) / ARQ (lightweight)
database: AWS RDS PostgreSQL 18 (SQLAlchemy 2 + Alembic)
cache: AWS ElastiCache Redis 8
auth: FastAPI JWT + OAuth (Google, GitHub, Apple)
payments: Stripe (Checkout, Subscriptions, Webhooks, Connect)
storage: AWS S3 + CloudFront CDN
deploy: AWS EKS (Kubernetes 1.35), Docker 29 (local)
monitoring: Prometheus + Grafana, structlog
ci_cd: GitHub Actions
infra: Terraform 1.14 + Kubernetes 1.35 manifests
testing: Pytest, Playwright 1.58 (E2E), k6 (load)
runtime: Node.js 24 LTS (frontend/mobile), Python 3.13 (backend)
```

**Directory structure:**
```
packages/
├── frontend/         # Next.js 16 web app
├── mobile/           # React Native 0.84 (Expo SDK 55)
├── desktop/          # Electron 35 (optional)
├── api/              # FastAPI backend (API gateway + auth + billing)
├── ml-service/       # FastAPI ML service (optional, for AI features)
├── worker/           # Celery job processors
├── shared/           # Shared types (Pydantic models + TS types)
├── ui/               # Radix UI primitives
├── ui-library/       # React component library
├── sdk/              # Typed API client (npm package)
├── cli/              # CLI tool (optional)
├── infrastructure/   # Terraform 1.14, K8s 1.35, Docker 29, CI/CD
├── scripts/          # Seed, setup, migrations
└── docs/             # Documentation
```

## Preset Selection Matrix

| Q1 (Type) | Q2 (Budget) | Preset | Packages | Backend | DB |
|-----------|-------------|--------|----------|---------|-----|
| Web | Solo | `web-solo` | 4 | FastAPI | PostgreSQL 18 |
| Web | Funded | `web-funded` | 5 | FastAPI | PostgreSQL 18 |
| Mobile | Solo | `mobile-solo` | 4 | FastAPI | PostgreSQL 18 |
| Mobile | Funded | `mobile-funded` | 5 | FastAPI | PostgreSQL 18 |
| Full | Solo | `full-solo` | 8 | FastAPI | PostgreSQL 18 |
| Full | Funded | `full-funded` | 13+ | FastAPI | PostgreSQL 18 |

## Common Stack (All Presets)

```yaml
backend: Python FastAPI 0.135 (uvicorn ASGI)
database: PostgreSQL 18
orm: SQLAlchemy 2.0 + Alembic (migrations)
validation: Pydantic v2
python: 3.13
```
