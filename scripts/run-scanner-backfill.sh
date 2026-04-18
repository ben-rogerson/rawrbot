#!/bin/bash
# One-time backfill: fingerprint all existing projects in a single Claude call.
# Reads each project's README.md + memory/index.md, generates the full catalog.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "${SCRIPT_DIR}/../.env" ] && source "${SCRIPT_DIR}/../.env"
WORKDIR="${WORKDIR:?WORKDIR must be set in .env}"

PROMPT_FILE=$(mktemp)
trap 'rm -f "$PROMPT_FILE"' EXIT

python3 - "$WORKDIR" "$PROMPT_FILE" <<'PYEOF'
import sys, os, json
from datetime import datetime, timezone

workdir = sys.argv[1]
prompt_file = sys.argv[2]

def read_file(path, default="(not found)"):
    try:
        with open(path) as f:
            return f.read().strip() or default
    except FileNotFoundError:
        return default

def read_truncated(path, chars=600):
    try:
        with open(path) as f:
            content = f.read().strip()
            if len(content) > chars:
                return content[:chars] + "\n...(truncated)"
            return content or "(empty)"
    except FileNotFoundError:
        return "(not found)"

# Collect all project directories (skip _archived)
projects_dir = os.path.join(workdir, "projects")
slugs = sorted([
    d for d in os.listdir(projects_dir)
    if os.path.isdir(os.path.join(projects_dir, d)) and not d.startswith("_")
])

# Build project sections
project_sections = []
for slug in slugs:
    path = os.path.join(projects_dir, slug)
    readme = read_truncated(os.path.join(path, "README.md"))
    pkg_raw = read_truncated(os.path.join(path, "package.json"), chars=300)
    project_sections.append(f"### {slug}\n{readme}\n\npackage.json (excerpt):\n{pkg_raw}")

projects_content = "\n\n---\n\n".join(project_sections)
memory_index = read_file(os.path.join(workdir, "memory", "index.md"))
now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
today = datetime.now().strftime('%Y-%m-%d')

prompt = f"""You are generating a complete project catalog for a portfolio of {len(slugs)} projects.

--- memory/index.md (existing project summaries, use as supplementary context) ---
{memory_index}

--- Project READMEs ({len(slugs)} projects) ---

{projects_content}

---

Your task: generate TWO files.

## FILE 1: memory/project-catalog.json

Write a JSON object with this exact shape:
{{
  "version": 1,
  "updatedAt": "{now}",
  "projects": [
    {{
      "slug": "<project-folder-name>",
      "domain": "<primary domain, e.g. 'personal productivity / journaling'>",
      "purpose": "<one sentence>",
      "keyFeatures": ["<feature 1>", "<feature 2>", "<feature 3>"],
      "techPatterns": ["<tech 1>", "<tech 2>", "<tech 3>"],
      "aiIntegration": "<AI model/SDK used, or 'none'>",
      "deployed": <true|false>,
      "deployedUrl": "<URL or null>"
    }}
  ]
}}

Include ALL {len(slugs)} projects. Sort alphabetically by slug.

Rules:
- domain: use short consistent labels like "personal productivity", "developer tooling", "food & cooking", "health & fitness", "entertainment", "finance", "content creation", "education", "utilities", "infrastructure"
- keyFeatures: 3-5 items, be specific (not "AI integration" - that goes in aiIntegration)
- techPatterns: list the key stack pieces (e.g. "Hono API", "TanStack Router", "Astro 6", "Lowdb", "Tailwind v4")
- deployed: true only if a live URL is mentioned in the README
- deployedUrl: the actual URL string or null

## FILE 2: memory/project-catalog.md

Write a Markdown table:

## Project Catalog ({today})

| Slug | Domain | Key Features | Tech Patterns | AI | Deployed |
|---|---|---|---|---|---|
(one row per project, sorted alphabetically, comma-separated values in cells)

Write both files now."""

with open(prompt_file, "w") as f:
    f.write(prompt)

print(f"Backfill: {len(slugs)} projects found", flush=True)
print(f"Backfill: prompt written, calling claude...", flush=True)
PYEOF

cd "${WORKDIR}"
echo "run-scanner-backfill: starting ($(date '+%Y-%m-%d %H:%M'))"
claude --dangerously-skip-permissions -p "$(cat "$PROMPT_FILE")"
echo "run-scanner-backfill: done"

# Validate the catalog JSON was written
python3 -c "
import json, sys
try:
    c = json.load(open('memory/project-catalog.json'))
    n = len(c.get('projects', []))
    print(f'Backfill: catalog has {n} projects')
    missing = [p for p in c['projects'] if not all(k in p for k in ['slug','domain','purpose','keyFeatures','techPatterns','aiIntegration','deployed','deployedUrl'])]
    if missing:
        print(f'Warning: {len(missing)} entries missing fields: {[p[\"slug\"] for p in missing]}', file=sys.stderr)
    else:
        print('Backfill: all entries have required fields')
except Exception as e:
    print(f'Backfill: ERROR reading catalog: {e}', file=sys.stderr)
    sys.exit(1)
"
