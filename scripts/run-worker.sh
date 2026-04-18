#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "${SCRIPT_DIR}/../.env" ] && source "${SCRIPT_DIR}/../.env"
WORKDIR="${WORKDIR:?WORKDIR must be set in .env}"
TASK_ID="${1:-}"
TODAY=$(date +%Y-%m-%d)
MEMORY_FILE="memory/${TODAY}.md"

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

INITIAL_COMPLETED=$(python3 -c "
import json, sys
try:
    data = json.load(open('${WORKDIR}/tasks.json'))
    tasks = data.get('tasks', data) if isinstance(data, dict) else data
    print(sum(1 for t in tasks if t.get('completedAt')))
except Exception:
    print(0)
" 2>/dev/null || echo "0")

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

with open(os.path.join(workdir, 'prompts', 'worker.md')) as f:
    template = f.read()

replacements = {
    '<<WORKDIR>>': workdir,
    '<<MEMORY_FILE>>': memory_file,
    '<<MEMORY_MD>>': memory_md,
    '<<DAILY_MEMORY>>': daily_memory,
    '<<TASKS_JSON>>': tasks_json,
    '<<PROGRESS>>': progress,
    '<<TASK_SELECTION>>': task_selection,
}
for placeholder, value in replacements.items():
    template = template.replace(placeholder, value)

with open(prompt_file, 'w') as f:
    f.write(template)
PYEOF

cd "${WORKDIR}"
echo "run-worker: starting ($(date '+%Y-%m-%d %H:%M'))"
[ -n "$TASK_ID" ] && echo "run-worker: targeting task '$TASK_ID'"
echo "run-worker: calling claude (task execution may take several minutes)..."
TARGET="${TASK_ID:-auto}"
log_event "worker" "start" "targeting task $TARGET"
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
  log_event "worker" "skip" "all tasks already complete"
  exit 0
fi

echo "run-worker: task executed"

# Handoff validation: if no promise tag, verify a task was actually marked complete
if ! echo "$OUTPUT" | grep -qE '<promise>(COMPLETE|NOT_FOUND)</promise>'; then
  NEW_COMPLETED=$(python3 -c "
import json, sys
try:
    data = json.load(open('${WORKDIR}/tasks.json'))
    tasks = data.get('tasks', data) if isinstance(data, dict) else data
    print(sum(1 for t in tasks if t.get('completedAt')))
except Exception:
    print(0)
" 2>/dev/null || echo "0")
  if [ "$NEW_COMPLETED" = "$INITIAL_COMPLETED" ]; then
    log_event "worker" "error" "no promise tag and no task marked complete"
    echo "run-worker: ERROR: Claude produced no promise tag and did not mark any task complete" >&2
    exit 1
  fi
fi
log_event "worker" "success" "task $TARGET executed"

SCANNER_SLUGS=$(python3 -c "
import sys, re
seen = set()
for m in re.findall(r'<scanner>PROJECT:([^<]+)</scanner>', sys.stdin.read()):
    s = m.strip()
    if s and s not in seen:
        seen.add(s)
        print(s)
" <<< "$OUTPUT" || true)
while IFS= read -r SCANNER_SLUG; do
  [ -z "$SCANNER_SLUG" ] && continue
  echo "run-worker: project change detected ($SCANNER_SLUG), running scanner..."
  bash "${SCRIPT_DIR}/run-scanner.sh" "$SCANNER_SLUG" || echo "run-worker: scanner failed (non-fatal)"
done <<< "$SCANNER_SLUGS"

if [ -n "${TELEGRAM_BOT_TOKEN}" ] && [ -n "${TELEGRAM_CHAT_ID}" ]; then
  MSG=$(grep -v '^$' "${WORKDIR}/memory/progress.txt" | tail -1)
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${MSG}" > /dev/null || true
fi
