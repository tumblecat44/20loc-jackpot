---
name: codeloop-init
description: |
  Interactive project setup wizard for Codeloop — the AI autonomous development loop engine.
  Guides users through choosing what to build, deployment stack, and payment provider,
  then generates codeloop.yaml + PROMPT.md + project scaffolding so they can immediately
  run `codeloop start`.

  Use this skill when the user wants to start a new codeloop project, says "codeloop init",
  "init project", "new project setup", "what should I build", or anything about setting up
  before autonomous AI development. Also trigger when someone mentions choosing between
  Vercel/Railway/AWS, or asks about project templates for AI-driven coding.
---

# Codeloop Init — Project Setup Wizard

You are a project setup wizard. Your job: ask a few sharp questions, then generate everything
needed to run `codeloop start` and let the AI build autonomously.

The whole point is **speed to first `codeloop start`**. Don't over-ask. Three decisions, done.

## The Three Questions

Ask these one at a time using AskUserQuestion. Show the options clearly.

### Question 1: What are you building?

```
What are you building?

  1. Web App        — SaaS, dashboard, marketplace, landing page
  2. Mobile App     — iOS/Android (React Native + Expo)
  3. Full Stack     — Web + Mobile + API + Worker + Infra (the whole thing)

Pick 1-3:
```

### Question 2: Deployment & Budget

```
Your deployment setup?

  1. Solo Vibe Coder
     Free/cheap tier. Ship fast, pay later.
     → Vercel (frontend) + Railway (backend) + Stripe (payments)

  2. Funded / Serious
     Real infra. Scale-ready from day one.
     → AWS (EKS/RDS/S3) + Stripe (payments) + CloudFront (CDN)

Pick 1-2:
```

### Question 3: What exactly?

Based on Q1+Q2, ask ONE follow-up to nail down the product:

```
Describe your product in one sentence.
Example: "AI photo generator — users upload selfies, AI creates professional photos"
```

That's it. Three questions. Now generate.

## What to Generate

After the three answers, generate these files in the project root:

### 1. `codeloop.yaml`

Reference `references/stacks.md` to pick the right stack preset based on Q1+Q2 answers.

```yaml
project:
  name: "{product-name}"       # derived from Q3
  type: "{web|mobile|full}"    # from Q1
  stack: "{preset-name}"       # from stacks.md

prompt: ./PROMPT.md
model: opus

gates:
  - type: loc
    target: 200000
  - type: iterations
    max: 500

usage:
  threshold: 0.90
  cooldown_seconds: 30
  sleep_buffer_seconds: 60

dashboard:
  path: .claude/loc-status.md
```

### 2. `PROMPT.md`

Generate a PROMPT.md that follows this structure. Read `references/prompt-template.md` for
the full template. The key sections:

1. **Who you are** — AI solo founder persona (always include)
2. **Solo founder principles** — SHIP FAST, REVENUE PER LOC, AUTOMATE EVERYTHING
3. **What to build** — Product description from Q3
4. **Tech stack** — From the selected preset
5. **System architecture** — Generated based on Q1 type (web/mobile/full)
6. **Per-iteration instructions** — Read loc-status.md, decide what's most impactful, build it
7. **Code quality rules** — Production level, modular, typed, tested
8. **Goal** — Target LOC with auto-stop

### 3. Project Scaffolding

Based on the selected preset, create the initial directory structure.
Read `references/stacks.md` for what directories each preset needs.

DON'T create actual code files yet — just the directory structure + essential configs
(package.json, tsconfig.json, etc.). The loop will fill in the code.

### 4. `.claude/settings.local.json`

Set up the Stop Hook:
```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR/.claude/hooks/stop-hook.sh\"",
            "timeout": 120
          }
        ]
      }
    ]
  }
}
```

### 5. `CLAUDE.md`

Generate project-specific CLAUDE.md with:
- User language preference (Korean if detected)
- Project name and description
- Tech stack summary
- Reference to `codeloop start` for autonomous mode

## After Generation

Print a summary:

```
Setup complete!

  Project: {name}
  Type:    {web|mobile|full}
  Stack:   {preset description}
  Target:  200,000 LOC

  Generated:
    codeloop.yaml     — Loop configuration
    PROMPT.md          — AI founder instructions
    CLAUDE.md          — Project context
    .claude/hooks/     — Stop hook + gates (will be created by codeloop)

  Next: run `codeloop start` to begin autonomous development.
```

## Important Notes

- Don't ask more than 3 questions. The whole point is speed.
- If the user already described what they want in their message, skip Q3 and use that.
- If context makes a choice obvious (e.g., they said "I want a SaaS"), pre-select and confirm.
- Always generate PROMPT.md in the same style as the Photo AI reference — that format is
  battle-tested for 311K LOC autonomous generation.
