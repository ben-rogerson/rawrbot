#!/bin/bash
# extract-plans.sh <slug> [<slug> ...]
#
# For each approved plan slug:
#   - Reads plans/<slug>.md and parses it into a tasks.json entry
#   - Appends the entry to tasks.json (safe write via tmp file)
#   - Deletes the plan file
#
# Exits non-zero if any step fails.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "${SCRIPT_DIR}/../.env" ] && source "${SCRIPT_DIR}/../.env"
WORKDIR="${WORKDIR:?WORKDIR must be set in .env}"

if [ $# -eq 0 ]; then
  echo "Usage: extract-plans.sh <slug> [<slug> ...]" >&2
  exit 1
fi

SLUGS=("$@")
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

python3 - "$WORKDIR" "$NOW" "${SLUGS[@]}" <<'PYEOF'
import sys, os, json, re

workdir = sys.argv[1]
now = sys.argv[2]
slugs = sys.argv[3:]

plans_dir = os.path.join(workdir, "plans")
tasks_path = os.path.join(workdir, "tasks.json")
tasks_tmp = tasks_path + ".tmp"

def parse_plan(slug):
    path = os.path.join(plans_dir, slug + ".md")
    with open(path) as f:
        content = f.read()

    # Title: first # heading
    title_match = re.search(r'^#\s+(.+)$', content, re.MULTILINE)
    title = title_match.group(1).strip() if title_match else slug

    # Description: text between # title and ## Steps
    desc_match = re.search(r'^#\s+.+\n+([\s\S]+?)(?=^##\s+Steps)', content, re.MULTILINE)
    description = desc_match.group(1).strip() if desc_match else ""

    # Steps: numbered list under ## Steps
    steps_match = re.search(r'^##\s+Steps\s*\n([\s\S]+?)(?=^##|\Z)', content, re.MULTILINE)
    steps = []
    if steps_match:
        for line in steps_match.group(1).splitlines():
            m = re.match(r'^\d+\.\s+(.+)', line.strip())
            if m:
                steps.append(m.group(1).strip())

    # Meta fields
    priority_match = re.search(r'\*\*priority:\*\*\s*(\d+)', content)
    project_match = re.search(r'\*\*project:\*\*\s*(\S+)', content)
    priority = int(priority_match.group(1)) if priority_match else 2
    project = project_match.group(1).strip() if project_match else ""

    return {
        "id": slug,
        "description": description,
        "steps": steps,
        "reasoning": description,
        "priority": priority,
        "project": project,
        "completedAt": None,
        "addedBy": "agent",
        "addedAt": now,
    }

# Load existing tasks
try:
    with open(tasks_path) as f:
        tasks = json.load(f)
except FileNotFoundError:
    tasks = []

existing_ids = {t["id"] for t in tasks}
added = []

for slug in slugs:
    if slug in existing_ids:
        print(f"[extract-plans] SKIP {slug} - already in tasks.json")
        continue
    plan = parse_plan(slug)
    tasks.append(plan)
    added.append(slug)
    print(f"[extract-plans] Queued {slug} (priority {plan['priority']}, project {plan['project']})")

# Safe write
with open(tasks_tmp, "w") as f:
    json.dump(tasks, f, indent=2)
    f.write("\n")

# Validate
with open(tasks_tmp) as f:
    json.load(f)

os.replace(tasks_tmp, tasks_path)

# Delete approved plan files
approved_dir = os.path.join(plans_dir, "approved")
os.makedirs(approved_dir, exist_ok=True)
for slug in added:
    plan_path = os.path.join(plans_dir, slug + ".md")
    os.rename(plan_path, os.path.join(approved_dir, slug + ".md"))
    print(f"[extract-plans] Moved plans/{slug}.md -> plans/approved/")

print(f"[extract-plans] Done - {len(added)} task(s) added to tasks.json")
PYEOF
