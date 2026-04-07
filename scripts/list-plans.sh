#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$SCRIPT_DIR/.."
[ -f "$REPO/.env" ] && source "$REPO/.env"
WORKDIR="${WORKDIR:-$REPO}"

python3 - "$WORKDIR" <<'PYEOF'
import sys, os, re, glob

repo = sys.argv[1]
plans = sorted(glob.glob(os.path.join(repo, 'plans', '*.md')))

if not plans:
    print("No staged plans.")
    sys.exit(0)

print(f"{len(plans)} staged plan(s):\n")
for path in plans:
    slug = os.path.splitext(os.path.basename(path))[0]
    content = open(path).read()

    title_m = re.search(r'^#\s+(.+)$', content, re.MULTILINE)
    title = title_m.group(1).strip() if title_m else slug

    # Description: text between title line and first ##
    desc_m = re.search(r'^#[^#].*\n+([\s\S]*?)(?=\n##|\Z)', content)
    desc = re.sub(r'\s+', ' ', desc_m.group(1).strip())[:120] if desc_m else ''

    steps = re.findall(r'^\d+\.', content, re.MULTILINE)

    priority_m = re.search(r'\*\*priority:\*\*\s*(\S+)', content)
    project_m = re.search(r'\*\*project:\*\*\s*(\S+)', content)
    priority = priority_m.group(1) if priority_m else '?'
    project = project_m.group(1) if project_m else '?'

    print(f"  [{slug}]")
    print(f"  Title:    {title}")
    print(f"  Project:  {project}  |  Priority: {priority}  |  Steps: {len(steps)}")
    if desc:
        print(f"  Desc:     {desc}")
    print()
PYEOF
