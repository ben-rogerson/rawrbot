---
name: rawr-run-plan
description: Manually run the planning agent - generate plan files in plans/ for review and update goals.md.
---

# Run Plan

## Steps

1. Note the current line count of `cron.log`:

   ```bash
   REPO=$(git rev-parse --show-toplevel); wc -l "$REPO/cron.log" 2>/dev/null || echo "0 $REPO/cron.log"
   ```

2. Run the script **in the background** (`run_in_background: true`):

   ```bash
   REPO=$(git rev-parse --show-toplevel); . ~/.zshrc 2>/dev/null; "$REPO/scripts/run-plan.sh" >> "$REPO/cron.log" 2>&1
   ```

3. Wait for the background task completion notification. Do NOT poll cron.log while waiting.

4. Once notified, read only the new lines (offset = line count from step 1) using the Read tool on `cron.log`, and report the results.
