#!/bin/bash
# run-validate.sh
#
# Automated idea validator: reviews staged plans/, approves strong ones,
# cancels weak/duplicate ones, and holds ambiguous ones for manual review.

set -e

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
trap 'rm -f "$PROMPT_FILE"' EXIT

python3 - "$WORKDIR" "$TODAY" "$MEMORY_FILE" "$STAGED_COUNT" "$PROMPT_FILE" <<'PYEOF'
import sys, os, glob

workdir = sys.argv[1]
today = sys.argv[2]
memory_file = sys.argv[3]
staged_count = sys.argv[4]
prompt_file = sys.argv[5]

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

STEP 1 - EVALUATE EACH PLAN
For each staged plan, assess these criteria:
- **Alignment**: Does it clearly fit goals.md priorities and stack preferences?
- **Duplication**: Is it substantially the same as a task already in tasks.json, or a near-duplicate of another staged plan?
- **Clarity**: Does it have specific steps and a realistic scope for the execution agent?
- **Quality**: Is the description concrete enough to act on, or too vague?

Assign each plan ONE decision:
- APPROVE - clearly aligns with goals, not a duplicate, quality is sufficient
- CANCEL - duplicate of existing task/plan, out of scope, or too vague to be actionable
- HOLD - genuinely unclear; a human should decide before it is acted on

Be conservative: when in doubt prefer HOLD over APPROVE or CANCEL.

STEP 2 - ENHANCE AGENT-GENERATED PLANS
Before extracting, check each APPROVE plan's Meta section for the addedBy field.

Skip plans where addedBy is "user" — they were shaped interactively and don't need enhancement.

For each plan where addedBy is "agent" (or the field is absent):
- Read plans/<slug>.md
- Assess: are steps concrete and actionable (scaffold, install, write, deploy — not vague like "set up", "handle", "build")? Does the plan cover init, implementation, AI integration (if applicable), and deployment? Is the description self-contained? Is the priority justified?
- If improvements are needed, write the enhanced version back to plans/<slug>.md
- Note what changed (or "no changes needed") — include this in the validation summary

Only fix what is clearly wrong. Do not restructure sound plans.

STEP 3 - APPROVE STRONG PLANS
If any plans are marked APPROVE, run this single command with all approved slugs:

bash scripts/extract-plans.sh <slug1> [<slug2> ...]

Skip this step entirely if nothing is approved.

STEP 4 - CANCEL WEAK PLANS
For each plan marked CANCEL, move it:

mkdir -p plans/cancelled && mv plans/<slug>.md plans/cancelled/

Skip this step entirely if nothing is cancelled.

STEP 5 - WRITE VALIDATION SUMMARY
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

STEP 6 - LOG TO PROGRESS
Append a single concise line to memory/progress.txt:
auditor: <N> approved, <N> cancelled, <N> held — <brief summary of what was acted on>"""

with open(prompt_file, "w") as f:
    f.write(prompt)
PYEOF

cd "${WORKDIR}"
echo "run-auditor: starting ($(date '+%Y-%m-%d %H:%M')) - ${STAGED_COUNT} staged plan(s)"
claude --dangerously-skip-permissions -p "$(cat "$PROMPT_FILE")"
echo "run-auditor: done"

if [ -n "${TELEGRAM_BOT_TOKEN}" ] && [ -n "${TELEGRAM_CHAT_ID}" ]; then
  MSG=$(grep '^auditor:' "${WORKDIR}/memory/progress.txt" 2>/dev/null | tail -1 || echo "auditor: completed")
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${MSG}" > /dev/null || true
fi
