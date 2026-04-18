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

if [ "$STAGED_COUNT" -eq 0 ]; then
  echo "run-auditor: no staged plans, nothing to do"
  log_event "auditor" "skip" "no staged plans"
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
catalog_md = read_file(os.path.join(workdir, "memory/project-catalog.md"), "")
catalog_section = f"\n--- memory/project-catalog.md ---\n{catalog_md}\n" if catalog_md else ""

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

with open(os.path.join(workdir, 'prompts', 'auditor.md')) as f:
    template = f.read()

if template.startswith('---'):
    parts = template.split('---', 2)
    if len(parts) >= 3:
        template = parts[2].lstrip('\n')

replacements = {
    '<<WORKDIR>>': workdir,
    '<<TODAY>>': today,
    '<<MEMORY_FILE>>': memory_file,
    '<<GOALS_MD>>': goals_md,
    '<<TASKS_JSON>>': tasks_json,
    '<<CATALOG_SECTION>>': catalog_section,
    '<<STAGED_COUNT>>': staged_count,
    '<<PLANS_CONTENT>>': plans_content,
    '<<DECISIONS_FILE>>': decisions_file,
    '<<STEP1>>': step1,
}
for placeholder, value in replacements.items():
    template = template.replace(placeholder, value)

with open(prompt_file, 'w') as f:
    f.write(template)
PYEOF

cd "${WORKDIR}"
echo "run-auditor: starting ($(date '+%Y-%m-%d %H:%M')) - ${STAGED_COUNT} staged plan(s)"
echo "run-auditor: calling claude to evaluate plans (may take 2-3 minutes)..."
log_event "auditor" "start" "$STAGED_COUNT staged plan(s)"
claude --dangerously-skip-permissions -p "$(cat "$PROMPT_FILE")"
echo "run-auditor: evaluation complete, processing decisions..."

if [ ! -s "$DECISIONS_FILE" ]; then
  log_event "auditor" "error" "decisions file not written or empty"
  echo "run-auditor: ERROR: decisions file was not written or is empty" >&2
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

APPROVED_COUNT=$(python3 -c "
import json, sys
try:
    d = json.load(open('$DECISIONS_FILE'))
    print(len(d.get('approve', [])))
except Exception:
    print('?')
" 2>/dev/null || echo "?")
log_event "auditor" "success" "approved=$APPROVED_COUNT of $STAGED_COUNT plans"

echo "run-auditor: done"

if [ -n "${TELEGRAM_BOT_TOKEN}" ] && [ -n "${TELEGRAM_CHAT_ID}" ]; then
  MSG=$(grep '^auditor:' "${WORKDIR}/memory/progress.txt" 2>/dev/null | tail -1 || echo "auditor: completed")
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${MSG}" > /dev/null || true
fi
