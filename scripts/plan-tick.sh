#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "${SCRIPT_DIR}/../.env" ] && source "${SCRIPT_DIR}/../.env"
WORKDIR="${WORKDIR:?WORKDIR must be set in .env}"
TODAY=$(date +%Y-%m-%d)
MEMORY_FILE="memory/${TODAY}.md"

# goals.md is required — abort if missing
if [ ! -f "${WORKDIR}/goals.md" ]; then
  echo "[plan-tick] ERROR: goals.md not found. Aborting." >&2
  exit 1
fi

# Bootstrap daily memory file if it doesn't exist
mkdir -p "${WORKDIR}/memory"
touch "${WORKDIR}/${MEMORY_FILE}"

# Collect projects listing (top-level directory names only)
PROJECTS_LIST=$(ls -d "${WORKDIR}/projects"/*/ 2>/dev/null | xargs -I{} basename {} | tr '\n' ', ' || echo "(none)")

# Build prompt
PROMPT=$(cat <<EOF
You are an autonomous planning agent working in ${WORKDIR}. Today is ${TODAY}.

Your job is to review context, generate tasks if the queue is short, self-update your goals document, and write a morning plan summary. You do NOT execute tasks — you only plan.

--- goals.md ---
$(cat "${WORKDIR}/goals.md")

--- notes.md ---
$(cat "${WORKDIR}/notes.md" 2>/dev/null || echo "(empty)")

--- tasks.json ---
$(cat "${WORKDIR}/tasks.json" 2>/dev/null || echo "[]")

--- progress.txt (last 100 lines) ---
$(tail -100 "${WORKDIR}/progress.txt" 2>/dev/null || echo "(empty)")

--- MEMORY.md ---
$(cat "${WORKDIR}/MEMORY.md" 2>/dev/null || echo "(empty)")

--- projects/ (top-level directories) ---
${PROJECTS_LIST}

---

Follow these steps exactly:

STEP 1 — VALIDATE tasks.json
Check that tasks.json above is valid JSON. If it is not valid JSON (and it is not empty), stop immediately and append this to ${MEMORY_FILE}:
  ## Morning plan — ${TODAY}
  ERROR: tasks.json is invalid JSON. Planning aborted.
Then exit without making any other changes.

STEP 2 — COUNT PENDING TASKS
Count tasks in tasks.json where passes is false. Call this PENDING_COUNT.

STEP 3 — GENERATE TASKS (only if PENDING_COUNT < 3)
If PENDING_COUNT >= 3, skip this step and go to STEP 4.

Otherwise, generate between 1 and 5 new tasks. For each task:
- Choose work that aligns with goals.md priorities
- Convert any clearly actionable entries from notes.md into tasks
- Do not repeat tasks already in tasks.json (check by description similarity)
- Each task must have these fields:
  {
    "id": "<short-slug-max-5-words-hyphenated>",
    "description": "<what to build or do>",
    "steps": ["<step 1>", "<step 2>"],
    "category": "agent-generated",
    "reasoning": "<why this task — reference goals, notes, or observed patterns>",
    "passes": false,
    "priority": 2,
    "addedBy": "agent",
    "addedAt": "${TODAY}T07:00:00Z"
  }
- id must be unique — check existing tasks.json ids and choose something that does not clash
- Append the new tasks to tasks.json. If tasks.json is empty or missing, write a valid JSON array.
- For any notes.md entries you converted to tasks, remove only those lines from notes.md. Leave all other content untouched.

STEP 4 — UPDATE goals.md (always run)
Review the progress history and current task patterns. If you observe anything worth recording (e.g. types of tasks that stall, preferences that are emerging, patterns in what gets done), update goals.md under the Self-Evolution section. Only make changes if there is something meaningful to record. Do not make cosmetic edits.

STEP 5 — WRITE MORNING PLAN SUMMARY (always run)
Append the following to ${MEMORY_FILE}:

If tasks were generated in STEP 3:
  ## Morning plan — ${TODAY}

  Tasks queued (N):
  1. [category] description — reasoning
  ... (one line per task)

  (If goals.md was updated, add a line: "goals.md updated: <what changed>")

If PENDING_COUNT >= 3 (tasks skipped):
  ## Morning plan — ${TODAY}

  No tasks queued — queue already has \${PENDING_COUNT} pending tasks.

  (If goals.md was updated, add a line: "goals.md updated: <what changed>")

STEP 6 — COMMIT
Commit all changed files with the message: "chore: morning plan ${TODAY}"
Include in the commit: tasks.json (if changed), goals.md (if changed), notes.md (if changed), ${MEMORY_FILE}.
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
