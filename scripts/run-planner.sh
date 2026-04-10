#!/bin/bash
set -e

TASKS_TO_GENERATE=5
MAX_PENDING_TASKS=20

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "${SCRIPT_DIR}/../.env" ] && source "${SCRIPT_DIR}/../.env"
WORKDIR="${WORKDIR:?WORKDIR must be set in .env}"
TODAY=$(date +%Y-%m-%d)
MEMORY_FILE="memory/${TODAY}.md"

# goals.md is required - abort if missing
if [ ! -f "${WORKDIR}/goals.md" ]; then
  echo "[run-planner] ERROR: goals.md not found. Aborting." >&2
  exit 1
fi

# Bootstrap daily memory file if it doesn't exist
mkdir -p "${WORKDIR}/memory"
touch "${WORKDIR}/${MEMORY_FILE}"

# Collect projects listing (top-level directory names only)
PROJECTS_LIST=$(ls -d "${WORKDIR}/projects"/*/ 2>/dev/null | xargs -I{} basename {} | tr '\n' ', ' || echo "(none)")

# Collect existing plan filenames to avoid clashes
mkdir -p "${WORKDIR}/plans"
EXISTING_PLANS=$(ls "${WORKDIR}/plans"/*.md 2>/dev/null | xargs -I{} basename {} .md | tr '\n' ', ' || echo "(none)")

# Build prompt via python to avoid shell quoting issues with file contents
PROMPT_FILE=$(mktemp)
trap 'rm -f "$PROMPT_FILE"' EXIT

python3 - "$WORKDIR" "$TODAY" "$MEMORY_FILE" "$PROJECTS_LIST" "$PROMPT_FILE" "$TASKS_TO_GENERATE" "$MAX_PENDING_TASKS" "$EXISTING_PLANS" <<'PYEOF'
import sys, os

workdir = sys.argv[1]
today = sys.argv[2]
memory_file = sys.argv[3]
projects_list = sys.argv[4]
prompt_file = sys.argv[5]
tasks_to_generate = sys.argv[6]
max_pending_tasks = sys.argv[7]
existing_plans = sys.argv[8]

def read_file(path, default="(empty)"):
    try:
        with open(path) as f:
            return f.read().strip() or default
    except FileNotFoundError:
        return default

def tail_file(path, n=100, default="(empty)"):
    try:
        with open(path) as f:
            lines = f.readlines()
            return "".join(lines[-n:]).strip() or default
    except FileNotFoundError:
        return default

goals_md = read_file(os.path.join(workdir, "goals.md"))
notes_md = read_file(os.path.join(workdir, "notes.md"))
tasks_json = read_file(os.path.join(workdir, "tasks.json"), "[]")
progress = tail_file(os.path.join(workdir, "memory/progress.txt"))
memory_md = read_file(os.path.join(workdir, "memory/index.md"))

prompt = f"""You are an autonomous planning agent working in {workdir}. Today is {today}.

Your job is to review context, generate tasks if the queue is short, self-update your goals document, and write a morning plan summary. You do NOT execute tasks - you only plan.

--- goals.md ---
{goals_md}

--- notes.md ---
{notes_md}

--- tasks.json ---
{tasks_json}

--- memory/progress.txt (last 100 lines) ---
{progress}

--- memory/index.md ---
{memory_md}

--- projects/ (top-level directories) ---
{projects_list}

--- plans/ (existing staged plans - avoid name clashes) ---
{existing_plans}

---

Follow these steps exactly:

STEP 1 - VALIDATE tasks.json
Check that tasks.json above is valid JSON. If it is not valid JSON (and it is not empty), stop immediately and append this to {memory_file}:
  ## Morning plan - {today}
  ERROR: tasks.json is invalid JSON. Planning aborted.
Then exit without making any other changes.

STEP 2 - COUNT PENDING TASKS
Count tasks in tasks.json where completedAt is null. Call this PENDING_COUNT.

STEP 3 - GENERATE PLANS (only if PENDING_COUNT <= {max_pending_tasks})
If PENDING_COUNT > {max_pending_tasks}, skip this step and go to STEP 4.

Otherwise, generate between 1 and {tasks_to_generate} new plans. For each plan:
- Choose work that aligns with goals.md priorities
- Convert any clearly actionable entries from notes.md into plans
- Do not repeat work already in tasks.json (check by description similarity)
- Check the plans/ directory for existing files to avoid name clashes

Write each plan as a SEPARATE markdown file in the plans/ directory.
Filename: plans/<slug>.md where slug is a short-hyphenated-name (max 5 words).

Use this exact format for each plan file:

# <Plan Title>

<Description of what to build. 1-2 sentences.>

## Reasoning

<Why this work is being prioritised now. Reference goals.md priorities, notes.md entries, or observed patterns. 2-4 sentences.>

## Steps
1. <concrete step 1>
2. <concrete step 2>
3. <verify the change works>

## Meta
- **project:** <folder-name under projects/>
- **addedBy:** agent

Do NOT include commit steps - the execution agent handles commits separately.
For any notes.md entries you converted to plans, remove only those lines from notes.md. Leave all other content untouched.

IMPORTANT: Do NOT read or modify tasks.json. Only write plan files to the plans/ directory.

STEP 4 - UPDATE goals.md (always run)
Review the progress history and current task patterns. If you observe anything worth recording (e.g. types of tasks that stall, preferences that are emerging, patterns in what gets done), update goals.md under the Self-Evolution section. Only make changes if there is something meaningful to record. Do not make cosmetic edits.

STEP 5 - WRITE MORNING PLAN SUMMARY (always run)
Append the following to {memory_file}:

If plans were generated in STEP 3:
  ## Morning plan - {today}

  Plans staged (N) - awaiting review in plans/:
  1. <slug> - description - reasoning
  ... (one line per plan)

  (If goals.md was updated, add a line: "goals.md updated: <what changed>")

If PENDING_COUNT > {max_pending_tasks} (plans skipped):
  ## Morning plan - {today}

  No plans staged - queue already has ${{PENDING_COUNT}} pending tasks.

  (If goals.md was updated, add a line: "goals.md updated: <what changed>")"""

with open(prompt_file, "w") as f:
    f.write(prompt)
PYEOF

cd "${WORKDIR}"
echo "run-planner: starting ($(date '+%Y-%m-%d %H:%M'))"
echo "run-planner: calling claude (planning may take 1-2 minutes)..."
claude --dangerously-skip-permissions -p "$(cat "$PROMPT_FILE")"
echo "run-planner: done"

if [ -n "${TELEGRAM_BOT_TOKEN}" ] && [ -n "${TELEGRAM_CHAT_ID}" ]; then
  PLAN_COUNT=$(ls "${WORKDIR}/plans"/*.md 2>/dev/null | wc -l | tr -d ' ')
  if [ "$PLAN_COUNT" -gt 0 ]; then
    MSG="Morning plan: ${PLAN_COUNT} plan(s) staged for review in plans/"
  else
    MSG="Morning plan: no new plans staged"
  fi
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${MSG}" > /dev/null || true
fi
