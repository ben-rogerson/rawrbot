#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "${SCRIPT_DIR}/../.env" ] && source "${SCRIPT_DIR}/../.env"
WORKDIR="${WORKDIR:?WORKDIR must be set in .env}"
TASK_ID="${1:-}"
TODAY=$(date +%Y-%m-%d)
MEMORY_FILE="memory/${TODAY}.md"

# Bootstrap daily memory file if it doesn't exist
mkdir -p "${WORKDIR}/memory"
touch "${WORKDIR}/${MEMORY_FILE}"

# Build prompt via python to avoid shell quoting issues with file contents
PROMPT_FILE=$(mktemp)
TMPOUT=$(mktemp)
trap 'rm -f "$PROMPT_FILE" "$TMPOUT"' EXIT

python3 - "$WORKDIR" "$MEMORY_FILE" "$PROMPT_FILE" "$TASK_ID" <<'PYEOF'
import sys, os

workdir = sys.argv[1]
memory_file = sys.argv[2]
prompt_file = sys.argv[3]
task_id = sys.argv[4] if len(sys.argv) > 4 else ""

def read_file(path, default="(empty)"):
    try:
        with open(path) as f:
            return f.read().strip() or default
    except FileNotFoundError:
        return default

def tail_file(path, n=50, default="(empty)"):
    try:
        with open(path) as f:
            lines = f.readlines()
            return "".join(lines[-n:]).strip() or default
    except FileNotFoundError:
        return default

memory_md = read_file(os.path.join(workdir, "memory/index.md"))
daily_memory = read_file(os.path.join(workdir, memory_file))
tasks_json = read_file(os.path.join(workdir, "tasks.json"), "[]")
progress = tail_file(os.path.join(workdir, "memory/progress.txt"))

if task_id:
    task_selection = (
        f"Execute the task with id '{task_id}'. "
        f"If that id is not present in tasks.json, output <promise>NOT_FOUND</promise> and stop. "
        f"If found but already complete (completedAt is non-null), output <promise>COMPLETE</promise> and stop. "
        f"Otherwise execute it."
    )
else:
    task_selection = (
        "Pick the highest-priority task from tasks.json where completedAt is null. "
        "Priority is array order - first incomplete task wins."
    )

prompt = f"""You are an autonomous agent working in {workdir}. Here is your context:

--- memory/index.md ---
{memory_md}

--- {memory_file} ---
{daily_memory}

--- tasks.json ---
{tasks_json}

--- memory/progress.txt (last 50 lines) ---
{progress}

---

1. Review the context above.
2. {task_selection}
   When marking a task complete, match it by its "id" field. If a task has no "id" field, match by description. Set completedAt to the current ISO 8601 timestamp on the matched task only.
3. Execute the task. New projects go in projects/<name>/.
4. Run relevant checks (typecheck, tests) if the task involves code.
5. Mark the task complete by setting completedAt to the current ISO 8601 timestamp in tasks.json.
   CRITICAL - safe write pattern for tasks.json (prevents data loss from pipe truncation):
     a. Read the current tasks.json contents into memory
     b. Make the change in memory (set completedAt on the matched task)
     c. Write the full updated JSON array to tasks.json.tmp
     d. Verify tasks.json.tmp is valid JSON: python3 -c "import json; json.load(open('tasks.json.tmp'))"
     e. mv tasks.json.tmp tasks.json
   NEVER pipe output directly into tasks.json. NEVER use patterns like 'jq ... | tee tasks.json' or 'cat > tasks.json' where the same file is both read source and write target.
5a. If the task created a new project directory, create a .gitignore in the project root with at minimum: node_modules/, dist/, .tanstack/ (add other entries as appropriate for the project type, e.g. .astro/ for Astro projects, .env for projects with secrets).
5b. If the task created a new project directory, write a README.md in the project root using this exact structure:
    - One or two sentences at the top: what it is and why it was built. Frame it as personal interest — curiosity, a problem to solve, something to learn. Never mention employers or portfolios.
    - ## What it does — bullet points only
    - ## How it works — a Mermaid diagram explaining key logic or data flow. Use flowchart TD for request/data flows, sequenceDiagram for multi-party interactions, or stateDiagram-v2 for state machines.
    - ## Getting Started — how to install and run it
    - ## What I learned — short paragraph
    - ## Future Improvements — short paragraph
    - ## Tech — bullet list of key technologies
    Rules: plain language, no buzzwords, short and scannable, no badges or decorative elements.
6. Append to progress.txt: task completed, key decisions, files changed, blockers. Be concise. Sacrifice grammar for concision.
7. Append to {memory_file}: session summary, key decisions, what to carry forward tomorrow.
8. If any long-term facts emerged (new project, key decision, user preference), update memory/index.md.
9. Do NOT commit changes. Do NOT git init the new project.
Important: Do NOT modify goals.md under any circumstances. goals.md is managed exclusively by the planning agent.
If all tasks have a non-null completedAt, output <promise>COMPLETE</promise> and stop."""

with open(prompt_file, "w") as f:
    f.write(prompt)
PYEOF

cd "${WORKDIR}"
echo "run-worker: starting ($(date '+%Y-%m-%d %H:%M'))"
[ -n "$TASK_ID" ] && echo "run-worker: targeting task '$TASK_ID'"
echo "run-worker: calling claude (task execution may take several minutes)..."
claude --dangerously-skip-permissions -p "$(cat "$PROMPT_FILE")" | tee "$TMPOUT"
OUTPUT=$(cat "$TMPOUT")
echo "run-worker: claude finished, processing result..."

# Task ID not found - list pending tasks as a hint
if echo "$OUTPUT" | grep -q '<promise>NOT_FOUND</promise>'; then
  PENDING=$(python3 -c "import json; [print(t['id']) for t in json.load(open('tasks.json')) if not t.get('completedAt')]" 2>/dev/null)
  echo "run-worker: task '$TASK_ID' not found. Pending tasks:"
  echo "$PENDING" | sed 's/^/  /'
  exit 1
fi

# Only notify if a task was actually executed (not when all tasks are already complete)
if echo "$OUTPUT" | grep -q '<promise>COMPLETE</promise>'; then
  echo "run-worker: all tasks already complete, nothing to do"
  exit 0
fi

echo "run-worker: task executed"

if [ -n "${TELEGRAM_BOT_TOKEN}" ] && [ -n "${TELEGRAM_CHAT_ID}" ]; then
  MSG=$(grep -v '^$' "${WORKDIR}/memory/progress.txt" | tail -1)
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${MSG}" > /dev/null || true
fi
