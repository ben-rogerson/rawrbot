---
name: rawr-run-planner
description: Manually run the planning agent - generate plan files in plans/ for review and update goals.md.
---

# Run Plan

## Steps

1. Note the current line count of `rawr.log`:

   ```bash
   REPO=$(git rev-parse --show-toplevel); wc -l "$REPO/rawr.log" 2>/dev/null || echo "0 $REPO/rawr.log"
   ```

2. Tell the user: "Running the planning agent - this makes a Claude API call so it may take a minute or more."

3. Run the script **in the background** (`run_in_background: true`):

   ```bash
   REPO=$(git rev-parse --show-toplevel); . ~/.zshrc 2>/dev/null; "$REPO/scripts/run-planner.sh" >> "$REPO/rawr.log" 2>&1
   ```

4. Tell the user: "Planning agent is running - waiting for it to finish (may take a minute or more)..."

5. Wait for the background task completion notification. Do NOT poll rawr.log while waiting.

6. Once notified, read only the new lines (offset = line count from step 1) using the Read tool on `rawr.log`, and report the results.
