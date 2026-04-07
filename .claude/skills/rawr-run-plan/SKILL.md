---
name: rawr-run-plan
description: Use when the user wants to manually run the planning agent - generates plan files in plans/ for review, updates goals.md
---

# Run Plan

## Steps

1. Note the current line count of `cron.log`:
   ```bash
   wc -l /Users/ben/Projects/work/cron.log
   ```

2. Run the script **in the background** (`run_in_background: true`):
   ```bash
   . ~/.zshrc 2>/dev/null; /Users/ben/Projects/work/scripts/run-plan.sh >> /Users/ben/Projects/work/cron.log 2>&1
   ```

3. Wait for the background task completion notification. Do NOT poll cron.log while waiting.

4. Once notified, read only the new lines (offset = line count from step 1) using the Read tool on `cron.log`, and report the results.
