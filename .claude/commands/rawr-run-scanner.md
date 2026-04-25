---
description: Manually run the project scanner - fingerprint a project and update the catalog, or backfill all projects at once.
argument-hint: "<slug> | --backfill"
---

# Run Scanner

Fingerprints a project (domain, features, tech patterns, deployment) and updates `memory/project-catalog.json` + `memory/project-catalog.md`. For new projects, also spawns quality-gate follow-up tasks (deployment, README, feature porting). For existing projects, refreshes the fingerprint only.

## Steps

1. Run the script **in the background** (`run_in_background: true`):

   **Single project:**
   ```bash
   REPO=$(git rev-parse --show-toplevel); . ~/.zshrc 2>/dev/null; "$REPO/scripts/run-scanner.sh" $ARGUMENTS 2>&1 | tee -a "$REPO/rawr.log"
   ```

   **Backfill all projects (no arguments):**
   ```bash
   REPO=$(git rev-parse --show-toplevel); . ~/.zshrc 2>/dev/null; "$REPO/scripts/run-scanner-backfill.sh" 2>&1 | tee -a "$REPO/rawr.log"
   ```

2. Start a Monitor watching rawr.log for scanner progress:

   ```bash
   REPO=$(git rev-parse --show-toplevel); tail -f "$REPO/rawr.log" | grep --line-buffered "run-scanner"
   ```

   Set timeout to 300000ms (600000ms for backfill). Tell the user: "Scanner is running - I'll update you as it progresses."

3. Relay each monitor event as it arrives.

4. When you see `run-scanner: done` or `run-scanner-backfill: done`, stop monitoring and report:
   - How many tasks were queued (if any)
   - Check `memory/project-catalog.md` for the updated catalog summary

## Usage

- `/rawr-run-scanner <slug>` - fingerprint a single project by folder name (e.g. `coffee-log`)
- `/rawr-run-scanner --backfill` - regenerate the full catalog from all projects in one Claude call
