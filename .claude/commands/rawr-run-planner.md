---
description: Manually run the planning agent - generate plan files in plans/ for review and update goals.md.
---

# Run Plan

## Steps

1. Run the script **in the background** (`run_in_background: true`):

   ```bash
   REPO=$(git rev-parse --show-toplevel); . ~/.zshrc 2>/dev/null; "$REPO/scripts/run-planner.sh" 2>&1 | tee -a "$REPO/rawr.log"
   ```

2. Start a Monitor watching rawr.log for planner progress lines:

   ```bash
   REPO=$(git rev-parse --show-toplevel); tail -f "$REPO/rawr.log" | grep --line-buffered "run-planner:"
   ```

   Set timeout to 180000ms. Tell the user: "Planning agent is running - I'll update you as it progresses."

3. Relay each monitor event to the user as it arrives (e.g. "run-planner: calling claude...").

4. When you see `run-planner: done` in the monitor events, stop monitoring and report what was generated (new plan files, goals.md updates).
