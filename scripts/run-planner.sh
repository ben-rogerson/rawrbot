#!/bin/bash
set -e

TASKS_TO_GENERATE=5
MAX_PENDING_TASKS=20

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "${SCRIPT_DIR}/../.env" ] && source "${SCRIPT_DIR}/../.env"
source "${SCRIPT_DIR}/claude-run.sh"
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

log_event() {
  local agent="$1" event="$2" detail="${3:-}"
  RAWR_AGENT="$agent" RAWR_EVENT="$event" RAWR_DETAIL="$detail" \
  python3 -c "
import json, datetime, os
entry = {'ts': datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
         'agent': os.environ['RAWR_AGENT'], 'event': os.environ['RAWR_EVENT'],
         'detail': os.environ.get('RAWR_DETAIL', '')}
with open('${WORKDIR}/rawr-events.log', 'a') as f:
    f.write(json.dumps(entry) + '\n')
"
}

INITIAL_PLAN_COUNT=$(ls "${WORKDIR}/plans"/*.md 2>/dev/null | wc -l | tr -d ' ' || echo "0")
PENDING_COUNT=$(python3 -c "
import json, sys
try:
    data = json.load(open('${WORKDIR}/tasks.json'))
    tasks = data.get('tasks', data) if isinstance(data, dict) else data
    print(sum(1 for t in tasks if not t.get('completedAt')))
except Exception:
    print(0)
" 2>/dev/null || echo "0")

TS=$(date +%Y%m%dT%H%M%SZ)
LOG_FILE="${WORKDIR}/logs/planner-${TS}.jsonl"
mkdir -p "${WORKDIR}/logs"

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
catalog_md = read_file(os.path.join(workdir, "memory/project-catalog.md"), "")
catalog_section = f"\n<project_catalog>\n{catalog_md}\n</project_catalog>\n" if catalog_md else ""

with open(os.path.join(workdir, 'prompts', 'planner.md')) as f:
    template = f.read()

if template.startswith('---'):
    parts = template.split('---', 2)
    if len(parts) >= 3:
        template = parts[2].lstrip('\n')

replacements = {
    '<<WORKDIR>>': workdir,
    '<<TODAY>>': today,
    '<<MEMORY_FILE>>': memory_file,
    '<<GOALS_MD>>': goals_md,
    '<<NOTES_MD>>': notes_md,
    '<<TASKS_JSON>>': tasks_json,
    '<<PROGRESS>>': progress,
    '<<MEMORY_MD>>': memory_md,
    '<<CATALOG_SECTION>>': catalog_section,
    '<<PROJECTS_LIST>>': projects_list,
    '<<EXISTING_PLANS>>': existing_plans,
    '<<TASKS_TO_GENERATE>>': tasks_to_generate,
    '<<MAX_PENDING_TASKS>>': max_pending_tasks,
}
for placeholder, value in replacements.items():
    template = template.replace(placeholder, value)

with open(prompt_file, 'w') as f:
    f.write(template)
PYEOF

cd "${WORKDIR}"
echo "run-planner: starting ($(date '+%Y-%m-%d %H:%M'))"
echo "run-planner: calling claude (planning may take 1-2 minutes)..."
log_event "planner" "start" "pending=$PENDING_COUNT initial_plans=$INITIAL_PLAN_COUNT"
run_claude "$PROMPT_FILE" "$LOG_FILE"
echo "run-planner: claude finished (log: $LOG_FILE)"

# Handoff validation
FINAL_PLAN_COUNT=$(ls "${WORKDIR}/plans"/*.md 2>/dev/null | wc -l | tr -d ' ' || echo "0")
if [ "$PENDING_COUNT" -le "$MAX_PENDING_TASKS" ] && [ "$FINAL_PLAN_COUNT" -le "$INITIAL_PLAN_COUNT" ]; then
  log_event "planner" "error" "expected new plans but none written (pending=$PENDING_COUNT max=$MAX_PENDING_TASKS)"
  echo "run-planner: WARNING: queue was below cap but no new plans were written" >&2
elif [ "$PENDING_COUNT" -gt "$MAX_PENDING_TASKS" ]; then
  log_event "planner" "skip" "queue at $PENDING_COUNT (max $MAX_PENDING_TASKS), no plans generated"
else
  NEW_PLANS=$((FINAL_PLAN_COUNT - INITIAL_PLAN_COUNT))
  log_event "planner" "success" "$NEW_PLANS new plan(s) staged"
fi
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
