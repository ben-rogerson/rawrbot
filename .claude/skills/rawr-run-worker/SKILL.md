---
name: rawr-run-worker
description: Manually run the task execution agent - pick the highest priority task from tasks.json and execute it.
---

# Run Task

## Command

```bash
REPO=$(git rev-parse --show-toplevel); . ~/.zshrc 2>/dev/null; "$REPO/scripts/run-worker.sh" 2>&1 | tee -a "$REPO/rawr.log"
```

Run this via Bash. Output streams to both stdout (visible here) and rawr.log. Report what happened when it finishes.
