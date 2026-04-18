#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$SCRIPT_DIR/.."
[ -f "$REPO/.env" ] && source "$REPO/.env"
WORKDIR="${WORKDIR:-$REPO}"

python3 - "$WORKDIR" <<'PYEOF'
import json, os, sys, glob

repo = sys.argv[1]

# tasks.json - handle both {"tasks":[...]} and bare [...] format
tasks_file = os.path.join(repo, 'tasks.json')
if os.path.exists(tasks_file):
    data = json.load(open(tasks_file))
    tasks = data.get('tasks', data) if isinstance(data, dict) else data
else:
    tasks = []
pending = [t for t in tasks if not t.get('completedAt')]
priority_counts = {}
for t in pending:
    # Support both flat schema (priority at top level) and envelope schema (draft.priority)
    priority = t.get('priority') or (t.get('draft') or {}).get('priority', '?')
    priority_counts[priority] = priority_counts.get(priority, 0) + 1

task_line = f"Tasks:    {len(pending)} pending"
if priority_counts:
    breakdown = ', '.join(f"{v} {k}" for k, v in sorted(priority_counts.items()))
    task_line += f" ({breakdown})"
print(task_line)

if pending:
    for t in pending:
        tid = t.get('id', '?')
        priority = t.get('priority') or (t.get('draft') or {}).get('priority', '?')
        project = t.get('project') or (t.get('draft') or {}).get('project', '?')
        print(f"          [{tid}] {priority} — {project}")

# Staged plans
plans = sorted(glob.glob(os.path.join(repo, 'plans', '*.md')))
print(f"Plans:    {len(plans)} staged in plans/")
for p in plans:
    print(f"          - {os.path.basename(p)}")

# Recent events from rawr-events.log
events_file = os.path.join(repo, 'rawr-events.log')
if os.path.exists(events_file):
    with open(events_file) as f:
        lines = [l.strip() for l in f if l.strip()]
    recent = lines[-10:]
    if recent:
        print(f"Events:   last {len(recent)} entries")
        for line in recent:
            try:
                e = json.loads(line)
                ts = e.get('ts', '')
                # Format: [HH:MM] from ISO timestamp
                time_part = ts[11:16] if len(ts) >= 16 else ts
                agent = e.get('agent', '?')
                event = e.get('event', '?')
                detail = e.get('detail', '')
                suffix = f" — {detail}" if detail else ""
                print(f"          [{time_part}] {agent}: {event}{suffix}")
            except Exception:
                pass

# Recent progress
progress_file = os.path.join(repo, 'memory', 'progress.txt')
if os.path.exists(progress_file):
    lines = [l.rstrip() for l in open(progress_file) if l.strip()]
    if lines:
        print(f"Recent:   {lines[-1][:100]}")
PYEOF

echo ""
"$SCRIPT_DIR/launchd.sh" status
