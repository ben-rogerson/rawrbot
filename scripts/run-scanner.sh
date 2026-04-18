#!/bin/bash
set -e

PROJECT_SLUG="${1:?Usage: run-scanner.sh <project-slug>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "${SCRIPT_DIR}/../.env" ] && source "${SCRIPT_DIR}/../.env"
WORKDIR="${WORKDIR:?WORKDIR must be set in .env}"

PROJECT_PATH="${WORKDIR}/projects/${PROJECT_SLUG}"

if [ ! -d "$PROJECT_PATH" ]; then
  echo "run-scanner: project directory not found: $PROJECT_PATH" >&2
  exit 1
fi

PROMPT_FILE=$(mktemp)
TASKS_FILE="/tmp/scanner-tasks-${PROJECT_SLUG}.json"
trap 'rm -f "$PROMPT_FILE" "$TASKS_FILE"' EXIT

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

CATALOG_PATH="${WORKDIR}/memory/project-catalog.json"
CATALOG_MTIME_BEFORE=$(python3 -c "import os; print(os.path.getmtime('$CATALOG_PATH'))" 2>/dev/null || echo "0")

python3 - "$WORKDIR" "$PROJECT_SLUG" "$PROJECT_PATH" "$PROMPT_FILE" "$TASKS_FILE" <<'PYEOF'
import sys, os, json
from datetime import datetime, timezone

workdir = sys.argv[1]
project_slug = sys.argv[2]
project_path = sys.argv[3]
prompt_file = sys.argv[4]
tasks_file = sys.argv[5]

def read_file(path, default="(not found)"):
    try:
        with open(path) as f:
            return f.read().strip() or default
    except FileNotFoundError:
        return default

readme = read_file(os.path.join(project_path, "README.md"))
pkg = read_file(os.path.join(project_path, "package.json"))

src_path = os.path.join(project_path, "src")
src_listing = "\n".join(sorted(os.listdir(src_path))) if os.path.isdir(src_path) else "(no src/ directory)"

catalog_path = os.path.join(workdir, "memory", "project-catalog.json")
is_new = True
catalog_context = "(not yet created)"

if os.path.exists(catalog_path):
    try:
        with open(catalog_path) as f:
            catalog = json.load(f)
        catalog_context = json.dumps(catalog, indent=2)
        is_new = project_slug not in [p["slug"] for p in catalog.get("projects", [])]
    except (json.JSONDecodeError, KeyError) as e:
        print(f"run-scanner: warning: could not parse project-catalog.json: {e}", file=sys.stderr, flush=True)

mode = "NEW PROJECT" if is_new else "EXISTING PROJECT UPDATE"
action = "added" if is_new else "updated"
now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

if is_new:
    task_instructions = f"""
STEP 3 - SPAWN FOLLOW-UP TASKS
Write a JSON array of follow-up tasks to: {tasks_file}
Use [] if there are no genuine gaps.

Each task must use this exact shape:
{{
  "id": "<short-hyphenated-slug>",
  "state": "draft",
  "draft": {{
    "id": "<short-hyphenated-slug>",
    "description": "<what to do>",
    "roughSteps": ["<step 1>", "<step 2>", "<step 3>"],
    "source": "scanner",
    "project": "<project-folder-name>",
    "priority": "high|medium|low"
  }},
  "attempts": [],
  "createdAt": "{now}",
  "completedAt": null,
  "childIds": []
}}

Spawn tasks for these findings (priority order):
1. Near-duplicate of an existing project - review/differentiation task
2. Not yet deployed - deployment task (Cloudflare Workers + Pages)
3. README weak or missing sections - README improvement task
4. Feature from a similar project worth porting (self-contained, no shared libs) - porting task naming reference project
5. Missing AI integration where it would clearly add value - enhancement task

Hard rules:
- NO cross-project shared components or libraries
- Feature porting: reference project named for inspiration only; implementation lives entirely inside target project
- Similarity warnings are advisory, not blockers
- Write raw JSON array only - no markdown fences, no extra text
"""
else:
    task_instructions = f"""
STEP 3 - NO TASK SPAWNING
Existing project update. Write an empty array to {tasks_file}:
[]
"""

with open(os.path.join(workdir, 'prompts', 'scanner.yaml')) as f:
    template = f.read()

if template.startswith('---'):
    parts = template.split('---', 2)
    if len(parts) >= 3:
        template = parts[2].lstrip('\n')

replacements = {
    '<<WORKDIR>>': workdir,
    '<<PROJECT_SLUG>>': project_slug,
    '<<README>>': readme,
    '<<PKG>>': pkg,
    '<<SRC_LISTING>>': src_listing,
    '<<CATALOG_CONTEXT>>': catalog_context,
    '<<MODE>>': mode,
    '<<ACTION>>': action,
    '<<TASK_INSTRUCTIONS>>': task_instructions,
}
for placeholder, value in replacements.items():
    template = template.replace(placeholder, value)

with open(prompt_file, 'w') as f:
    f.write(template)
PYEOF

cd "${WORKDIR}"
echo "run-scanner: starting for '$PROJECT_SLUG' ($(date '+%Y-%m-%d %H:%M'))"
echo "run-scanner: calling claude..."
log_event "scanner" "start" "$PROJECT_SLUG"
claude --dangerously-skip-permissions -p "$(cat "$PROMPT_FILE")"
echo "run-scanner: claude finished, processing tasks..."

# Handoff validation: verify catalog was updated
CATALOG_MTIME_AFTER=$(python3 -c "import os; print(os.path.getmtime('$CATALOG_PATH'))" 2>/dev/null || echo "0")
if [ "$CATALOG_MTIME_AFTER" = "$CATALOG_MTIME_BEFORE" ]; then
  log_event "scanner" "error" "catalog not updated for $PROJECT_SLUG"
  echo "run-scanner: WARNING: project-catalog.json was not modified" >&2
else
  log_event "scanner" "success" "$PROJECT_SLUG fingerprint updated"
fi

TASK_COUNT=0
if [ -f "$TASKS_FILE" ] && [ -s "$TASKS_FILE" ]; then
  TASK_COUNT=$(python3 -c "import json; print(len(json.load(open('$TASKS_FILE'))))" 2>/dev/null || echo "0")
  python3 - "$TASKS_FILE" "$SCRIPT_DIR" <<'PYEOF'
import sys, json, subprocess

tasks_file = sys.argv[1]
script_dir = sys.argv[2]

try:
    with open(tasks_file) as f:
        tasks = json.load(f)
except (FileNotFoundError, json.JSONDecodeError) as e:
    print(f"run-scanner: could not read tasks file: {e}", flush=True)
    sys.exit(0)

count = 0
for task in tasks:
    result = subprocess.run(
        ["bash", f"{script_dir}/append-task.sh"],
        input=json.dumps(task),
        capture_output=True,
        text=True
    )
    if result.returncode == 0:
        print(f"run-scanner: queued {task.get('id', '?')}", flush=True)
        count += 1
    else:
        print(f"run-scanner: failed to queue {task.get('id', '?')}: {result.stderr}", flush=True)
print(f"run-scanner: {count} task(s) queued", flush=True)
PYEOF
fi

if [ -n "${TELEGRAM_BOT_TOKEN}" ] && [ -n "${TELEGRAM_CHAT_ID}" ]; then
  if [ "$TASK_COUNT" -gt 0 ]; then
    MSG="scanner: $PROJECT_SLUG fingerprint updated, $TASK_COUNT task(s) queued"
  else
    MSG="scanner: $PROJECT_SLUG fingerprint updated"
  fi
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${MSG}" > /dev/null || true
fi
