#!/usr/bin/env bash
# Posts a Telegram MarkdownV2 summary of AI eval results to the configured chat.
# Usage: notify-ai-evals.sh <artifacts-dir>
# Required env: TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, GITHUB_RUN_URL
# Each artifact is a single .status file containing "ok" or "fail" - written by
# the matrix job after evalite finishes.
# Falls back to stdout when Telegram credentials are absent.

set -euo pipefail

ARTIFACTS_DIR="${1:-artifacts}"

summary_lines=()
overall_status="OK"

shopt -s nullglob
for status_file in "$ARTIFACTS_DIR"/*.status; do
  slug=$(basename "$status_file" .status)
  status=$(cat "$status_file" 2>/dev/null || echo "unknown")
  case "$status" in
    ok)
      summary_lines+=("- ✅ ${slug}")
      ;;
    fail)
      summary_lines+=("- ❌ ${slug}")
      overall_status="FAIL"
      ;;
    *)
      summary_lines+=("- ❓ ${slug}: unknown")
      overall_status="FAIL"
      ;;
  esac
done

if [ ${#summary_lines[@]} -eq 0 ]; then
  summary_lines+=("- ❓ no eval status files found")
  overall_status="FAIL"
fi

header="*AI Evals: ${overall_status}*"
body=$(printf '%s\n' "${summary_lines[@]}")
footer="[View run](${GITHUB_RUN_URL:-})"
text=$(printf '%s\n\n%s\n\n%s\n' "$header" "$body" "$footer")

if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
  echo "[notify-ai-evals] no Telegram credentials, printing to stdout"
  echo "$text"
  exit 0
fi

# MarkdownV2 escape: . - ! ( ) etc. Keep this minimal - only escape what we know
# our message can contain.
escape_md() {
  printf '%s' "$1" | sed -e 's/\([_*\[\]()~`>#+=|{}.!\-]\)/\\\1/g'
}

escaped=$(escape_md "$text")

curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -H 'Content-Type: application/json' \
  -d "$(printf '{"chat_id":"%s","text":%s,"parse_mode":"MarkdownV2","disable_web_page_preview":true}' \
        "$TELEGRAM_CHAT_ID" \
        "$(printf '%s' "$escaped" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')")" \
  >/dev/null
echo "[notify-ai-evals] posted summary to Telegram (status=$overall_status)"
