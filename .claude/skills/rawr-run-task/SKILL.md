---
name: rawr-run-task
description: Manually run the task execution agent - pick the highest priority task from tasks.json and execute it.
---

# Run Task

## Command

```bash
REPO=$(git rev-parse --show-toplevel); . ~/.zshrc 2>/dev/null; "$REPO/scripts/run-task.sh" 2>&1 | tee -a "$REPO/cron.log"
```

Run this via Bash. Output streams to both stdout (visible here) and cron.log. Report what happened when it finishes.
