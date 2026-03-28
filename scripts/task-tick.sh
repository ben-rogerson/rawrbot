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

# Build prompt via python to avoid shell quoting issues with file contents
PROMPT_FILE=$(mktemp)
trap 'rm -f "$PROMPT_FILE"' EXIT

python3 - "$WORKDIR" "$MEMORY_FILE" "$PROMPT_FILE" <<'PYEOF'
import sys, os

workdir = sys.argv[1]
memory_file = sys.argv[2]
prompt_file = sys.argv[3]

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

memory_md = read_file(os.path.join(workdir, "MEMORY.md"))
daily_memory = read_file(os.path.join(workdir, memory_file))
tasks_json = read_file(os.path.join(workdir, "tasks.json"), "[]")
progress = tail_file(os.path.join(workdir, "progress.txt"))

prompt = f"""You are an autonomous agent working in {workdir}. Here is your context:

--- MEMORY.md ---
{memory_md}

--- {memory_file} ---
{daily_memory}

--- tasks.json ---
{tasks_json}

--- progress.txt (last 50 lines) ---
{progress}

---

1. Review the context above.
2. Pick the highest-priority task from tasks.json where passes is false. Priority is array order — first incomplete task wins.
   When marking a task complete, match it by its "id" field. If a task has no "id" field, match by description. Set passes: true on the matched task only.
3. Execute the task. New projects go in projects/<name>/.
4. Run relevant checks (typecheck, tests) if the task involves code.
5. Mark the task passes: true in tasks.json.
5a. If the task created a new project directory, initialise a git repo in it (git init && git add -A && git commit -m "Initial commit") so the project has its own version control. projects/ is gitignored from the main repo, so each project must track itself.
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
8. If any long-term facts emerged (new project, key decision, user preference), update MEMORY.md.
9. Commit changes: for the main repo (tasks.json, progress.txt, memory, goals.md), commit with a descriptive message. For project repos under projects/<name>/, commit within that project's own git repo. If the project has no .git directory, run git init first.
Important: Do NOT modify goals.md under any circumstances. goals.md is managed exclusively by the planning agent.
If all tasks have passes: true, output <promise>COMPLETE</promise> and stop."""

with open(prompt_file, "w") as f:
    f.write(prompt)
PYEOF

cd "${WORKDIR}"
OUTPUT=$(claude --dangerously-skip-permissions -p "$(cat "$PROMPT_FILE")")

# Only notify if a task was actually executed (not when all tasks are already complete)
if echo "$OUTPUT" | grep -q '<promise>COMPLETE</promise>'; then
  exit 0
fi

if [ -n "${TELEGRAM_BOT_TOKEN}" ] && [ -n "${TELEGRAM_CHAT_ID}" ]; then
  MSG=$(grep -v '^$' "${WORKDIR}/progress.txt" | tail -1)
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${MSG}" > /dev/null || true
fi
