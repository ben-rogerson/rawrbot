#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$SCRIPT_DIR/.."
[ -f "$REPO/.env" ] && source "$REPO/.env"
WORKDIR="${WORKDIR:-$REPO}"

python3 - "$WORKDIR" <<'PYEOF'
import json, os, sys, glob, re

repo = sys.argv[1]

# Pending tasks
tasks_file = os.path.join(repo, 'tasks.json')
tasks = json.load(open(tasks_file)) if os.path.exists(tasks_file) else []
pending = [t for t in tasks if not t.get('completedAt')]
priority_counts = {}
for t in pending:
    p = t.get('priority', '?')
    priority_counts[p] = priority_counts.get(p, 0) + 1

task_line = f"Tasks:    {len(pending)} pending"
if priority_counts:
    breakdown = ', '.join(f"{v} priority-{k}" for k, v in sorted(priority_counts.items()))
    task_line += f" ({breakdown})"
print(task_line)

if pending:
    for t in pending:
        print(f"          [{t['id']}] p{t.get('priority','?')} — {t.get('project','?')}")

# Staged plans
plans = sorted(glob.glob(os.path.join(repo, 'plans', '*.md')))
print(f"Plans:    {len(plans)} staged in plans/")
for p in plans:
    print(f"          - {os.path.basename(p)}")

# Recent progress
progress_file = os.path.join(repo, 'memory', 'progress.txt')
if os.path.exists(progress_file):
    lines = [l.rstrip() for l in open(progress_file) if l.strip()]
    if lines:
        print(f"Recent:   {lines[-1][:100]}")
PYEOF

echo ""
"$SCRIPT_DIR/launchd.sh" status
