#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "${SCRIPT_DIR}/../.env" ] && source "${SCRIPT_DIR}/../.env"
WORKDIR="${WORKDIR:?WORKDIR must be set in .env}"
INIT='{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Telegram channel listener ready. Wait for incoming messages."}]}}'

(echo "$INIT"; tail -f /dev/null) | claude \
  --dangerously-skip-permissions \
  --append-system-prompt "$(WORKDIR="$WORKDIR" envsubst '$WORKDIR' < "${WORKDIR}/scripts/telegram-prompt.md")" \
  --input-format stream-json \
  --output-format stream-json \
  --verbose \
  >> "${WORKDIR}/telegram.log" 2>&1
