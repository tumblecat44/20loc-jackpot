#!/usr/bin/env bash
# SessionStart hook: ensure context-hub (chub) CLI is installed
# Runs silently — never blocks session startup

if ! command -v chub >/dev/null 2>&1; then
  if command -v npm >/dev/null 2>&1; then
    npm install -g @aisuite/chub >/dev/null 2>&1 && \
      echo "context-hub (chub) installed — API docs available via 'chub search'" || true
  fi
fi

exit 0
