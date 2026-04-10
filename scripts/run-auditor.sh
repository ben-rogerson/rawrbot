#!/bin/bash
# run-validate.sh
#
# Automated idea validator: reviews staged plans/, approves strong ones,
# cancels weak/duplicate ones, and holds ambiguous ones for manual review.

set -e

PREAPPROVED=""
PRECANCELLED=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --approve) PREAPPROVED="$2"; shift 2 ;;
    --cancel)  PRECANCELLED="$2"; shift 2 ;;
    *) shift ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "${SCRIPT_DIR}/../.env" ] && source "${SCRIPT_DIR}/../.env"
WORKDIR="${WORKDIR:?WORKDIR must be set in .env}"
TODAY=$(date +%Y-%m-%d)
MEMORY_FILE="memory/${TODAY}.md"

# Bootstrap daily memory file
mkdir -p "${WORKDIR}/memory"
touch "${WORKDIR}/${MEMORY_FILE}"

# Exit early if no staged plans
STAGED_COUNT=$(ls "${WORKDIR}/plans"/*.md 2>/dev/null | wc -l | tr -d ' ')
if [ "$STAGED_COUNT" -eq 0 ]; then
  echo "run-auditor: no staged plans, nothing to do"
  exit 0
fi

# Build prompt via python to avoid shell quoting issues
PROMPT_FILE=$(mktemp)
DECISIONS_FILE=$(mktemp)
trap 'rm -f "$PROMPT_FILE" "$DECISIONS_FILE"' EXIT

python3 - "$WORKDIR" "$TODAY" "$MEMORY_FILE" "$STAGED_COUNT" "$PROMPT_FILE" "$PREAPPROVED" "$PRECANCELLED" "$DECISIONS_FILE" <<'PYEOF'
import sys, os, glob

workdir = sys.argv[1]
today = sys.argv[2]
memory_file = sys.argv[3]
staged_count = sys.argv[4]
prompt_file = sys.argv[5]
preapproved = sys.argv[6] if len(sys.argv) > 6 else ""
precancelled = sys.argv[7] if len(sys.argv) > 7 else ""
decisions_file = sys.argv[8] if len(sys.argv) > 8 else "/tmp/auditor-decisions.json"

def read_file(path, default="(empty)"):
    try:
        with open(path) as f:
            return f.read().strip() or default
    except FileNotFoundError:
        return default

# Read all staged plan files
plans_dir = os.path.join(workdir, "plans")
plan_files = sorted(glob.glob(os.path.join(plans_dir, "*.md")))
plans_sections = []
for path in plan_files:
    slug = os.path.splitext(os.path.basename(path))[0]
    content = open(path).read()
    plans_sections.append(f"### plans/{slug}.md\n\n{content}")

plans_content = "\n\n---\n\n".join(plans_sections) if plans_sections else "(none)"

goals_md = read_file(os.path.join(workdir, "goals.md"))
tasks_json = read_file(os.path.join(workdir, "tasks.json"), "[]")

if preapproved or precancelled:
    step1 = f"""STEP 1 - DECISIONS ARE PRE-SUPPLIED (skip evaluation)
The user has already reviewed the plans and made these decisions:
- APPROVE: {preapproved or "(none)"}
- CANCEL: {precancelled or "(none)"}
- HOLD: any remaining staged plans not listed above

Proceed directly to STEP 2."""
else:
    step1 = """STEP 1 - EVALUATE EACH PLAN
For each staged plan, assess these criteria:
- **Alignment**: Does it clearly fit goals.md priorities and stack preferences?
- **Duplication**: Is it substantially the same as a task already in tasks.json, or a near-duplicate of another staged plan?
- **Clarity**: Does it have specific steps and a realistic scope for the execution agent?
- **Quality**: Is the description concrete enough to act on, or too vague?

Assign each plan ONE decision:
- APPROVE - clearly aligns with goals, not a duplicate, quality is sufficient
- CANCEL - duplicate of existing task/plan, out of scope, or too vague to be actionable
- HOLD - genuinely unclear; a human should decide before it is acted on

Be conservative: when in doubt prefer HOLD over APPROVE or CANCEL."""

prompt = f"""You are an autonomous idea validator working in {workdir}. Today is {today}.

Your job is to evaluate staged plan files and make a decision on each one: approve strong plans (add to tasks.json), cancel weak or duplicate ones, and hold ambiguous ones for human review.

--- goals.md ---
{goals_md}

--- tasks.json (current queue) ---
{tasks_json}

--- Staged plans ({staged_count} total) ---

{plans_content}

---

Follow these steps exactly:

{step1}

STEP 2 - ENHANCE AGENT-GENERATED PLANS
Before extracting, check each APPROVE plan's Meta section for the addedBy field.

Skip plans where addedBy is "user" — they were shaped interactively and don't need enhancement.

For each plan where addedBy is "agent" (or the field is absent):
- Read plans/<slug>.md
- Assess: are steps concrete and actionable (scaffold, install, write, deploy — not vague like "set up", "handle", "build")? Does the plan cover init, implementation, AI integration (if applicable), and deployment? Is the description self-contained?
- If improvements are needed, write the enhanced version back to plans/<slug>.md
- Note what changed (or "no changes needed") — include this in the validation summary

Only fix what is clearly wrong. Do not restructure sound plans.

STEP 3 - WRITE DECISIONS JSON FILE
Write your final decisions as a JSON object to the file: {decisions_file}

The file must contain only this JSON structure:
{{"approve": ["slug1", "slug2"], "cancel": ["slug3"], "hold": ["slug4"]}}

Rules:
- Every staged plan slug must appear in exactly one list
- Use empty arrays for categories with no entries
- Do not include the .md extension in slugs
- Write raw JSON only - no markdown fences, no extra text

STEP 4 - WRITE VALIDATION SUMMARY
Append this section to {memory_file}:

## Idea validation - {today}

Staged: <N>  |  Approved: <N>  |  Cancelled: <N>  |  On hold: <N>

Approved:
- <slug>: <one-line reason> [enhanced: <what changed> | no changes needed]

Cancelled:
- <slug>: <one-line reason>

On hold (needs human review):
- <slug>: <one-line reason>

Omit any section that has no entries.

STEP 5 - LOG TO PROGRESS
Append a single concise line to memory/progress.txt:
auditor: <N> approved, <N> cancelled, <N> held — <brief summary of what was acted on>"""

with open(prompt_file, "w") as f:
    f.write(prompt)
PYEOF

cd "${WORKDIR}"
echo "run-auditor: starting ($(date '+%Y-%m-%d %H:%M')) - ${STAGED_COUNT} staged plan(s)"
echo "run-auditor: calling claude to evaluate plans (may take 2-3 minutes)..."
claude --dangerously-skip-permissions -p "$(cat "$PROMPT_FILE")"
echo "run-auditor: evaluation complete, processing decisions..."

if [ ! -s "$DECISIONS_FILE" ]; then
  echo "run-auditor: decisions file was not written or is empty" >&2
  exit 1
fi

# Shell handles extraction and archiving from Claude's decisions JSON
python3 - "$DECISIONS_FILE" "$WORKDIR" <<'PYEOF2'
import sys, json, os, subprocess, shutil

decisions_file = sys.argv[1]
workdir = sys.argv[2]

try:
    with open(decisions_file) as f:
        decisions = json.load(f)
except (FileNotFoundError, json.JSONDecodeError) as e:
    print(f"run-auditor: could not read decisions file: {e}", flush=True)
    sys.exit(1)

approved = decisions.get("approve", [])
cancelled = decisions.get("cancel", [])

if approved:
    subprocess.run(["bash", "scripts/extract-plans.sh"] + approved, check=True, cwd=workdir)

for slug in cancelled:
    src = os.path.join(workdir, "plans", f"{slug}.md")
    dst_dir = os.path.join(workdir, "plans", "cancelled")
    os.makedirs(dst_dir, exist_ok=True)
    if os.path.exists(src):
        shutil.move(src, os.path.join(dst_dir, f"{slug}.md"))

print(f"run-auditor: extracted {len(approved)} plan(s), archived {len(cancelled)} cancelled", flush=True)
PYEOF2

echo "run-auditor: done"

if [ -n "${TELEGRAM_BOT_TOKEN}" ] && [ -n "${TELEGRAM_CHAT_ID}" ]; then
  MSG=$(grep '^auditor:' "${WORKDIR}/memory/progress.txt" 2>/dev/null | tail -1 || echo "auditor: completed")
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${MSG}" > /dev/null || true
fi
