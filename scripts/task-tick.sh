#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "${SCRIPT_DIR}/../.env" ] && source "${SCRIPT_DIR}/../.env"
WORKDIR="${WORKDIR:?WORKDIR must be set in .env}"
TODAY=$(date +%Y-%m-%d)
MEMORY_FILE="memory/${TODAY}.md"

# Bootstrap daily memory file if it doesn't exist
mkdir -p "${WORKDIR}/memory"
touch "${WORKDIR}/${MEMORY_FILE}"

# Build prompt with injected file contents
PROMPT=$(cat <<EOF
You are an autonomous agent working in ${WORKDIR}. Here is your context:

--- MEMORY.md ---
$(cat "${WORKDIR}/MEMORY.md" 2>/dev/null || echo "(empty)")

--- ${MEMORY_FILE} ---
$(cat "${WORKDIR}/${MEMORY_FILE}" 2>/dev/null || echo "(empty)")

--- tasks.json ---
$(cat "${WORKDIR}/tasks.json" 2>/dev/null || echo "[]")

--- progress.txt (last 50 lines) ---
$(tail -50 "${WORKDIR}/progress.txt" 2>/dev/null || echo "(empty)")

---

1. Review the context above.
2. Pick the highest-priority task from tasks.json where passes is false. Priority is array order — first incomplete task wins.
   When marking a task complete, match it by its "id" field. If a task has no "id" field, match by description. Set passes: true on the matched task only.
3. Execute the task. New projects go in projects/<name>/.
4. Run relevant checks (typecheck, tests) if the task involves code.
5. Mark the task passes: true in tasks.json.
5a. If the task created a new project directory, write a README.md in the project root using this exact structure:
    - One or two sentences at the top: what it is and why it was built. Frame it as personal interest — curiosity, a problem to solve, something to learn. Never mention employers or portfolios.
    - ## What it does — bullet points only
    - ## How it works — a Mermaid diagram explaining key logic or data flow. Use flowchart TD for request/data flows, sequenceDiagram for multi-party interactions, or stateDiagram-v2 for state machines.
    - ## Getting Started — how to install and run it
    - ## What I learned — short paragraph
    - ## Future Improvements — short paragraph
    - ## Tech — bullet list of key technologies
    Rules: plain language, no buzzwords, short and scannable, no badges or decorative elements.
6. Append to progress.txt: task completed, key decisions, files changed, blockers. Be concise. Sacrifice grammar for concision.
7. Append to ${MEMORY_FILE}: session summary, key decisions, what to carry forward tomorrow.
8. If any long-term facts emerged (new project, key decision, user preference), update MEMORY.md.
9. Commit all changes with a descriptive message.
Important: Do NOT modify goals.md under any circumstances. goals.md is managed exclusively by the planning agent.
If all tasks have passes: true, output <promise>COMPLETE</promise> and stop.
EOF
)

cd "${WORKDIR}"
claude --dangerously-skip-permissions -p "$PROMPT"

if [ -n "${BOT_TOKEN}" ] && [ -n "${CHAT_ID}" ]; then
  MSG=$(grep -v '^$' "${WORKDIR}/progress.txt" | tail -1)
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CHAT_ID}" \
    --data-urlencode "text=${MSG}" > /dev/null || true
fi
