#!/usr/bin/env bash
# Usage:
#   scripts/append-task.sh --list        # show existing task IDs and priorities
#   echo '<json>' | scripts/append-task.sh  # append a task from stdin
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$SCRIPT_DIR/.."
[ -f "$REPO/.env" ] && source "$REPO/.env"
TASKS_FILE="${WORKDIR:-$REPO}/tasks.json"

if [ "${1:-}" = "--list" ]; then
    python3 - "$TASKS_FILE" <<'PYEOF'
import json, sys, os

path = sys.argv[1]
tasks = json.load(open(path)) if os.path.exists(path) else []
pending = [t for t in tasks if not t.get('completedAt')]
print(f"{len(pending)} pending task(s):")
for t in pending:
    print(f"  [{t['id']}] priority={t.get('priority','?')} project={t.get('project','?')}")
PYEOF
    exit 0
fi

python3 - "$TASKS_FILE" <<'PYEOF'
import json, sys, os

tasks_file = sys.argv[1]
new_task = json.load(sys.stdin)

tasks = json.load(open(tasks_file)) if os.path.exists(tasks_file) else []
tasks.append(new_task)

tmp = tasks_file + '.tmp'
with open(tmp, 'w') as f:
    json.dump(tasks, f, indent=2)
    f.write('\n')

# Validate
json.load(open(tmp))

os.replace(tmp, tasks_file)
print(f"Added task: {new_task.get('id', '?')}")
PYEOF
