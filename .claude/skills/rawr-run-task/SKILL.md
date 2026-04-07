---
name: rawr-run-task
description: Use when the user wants to manually run the task execution agent - picks the highest priority task from tasks.json and executes it
---

# Run Task

Picks the highest-priority pending task from `tasks.json` and executes it autonomously. One task per run.

## Command

```bash
. ~/.zshrc 2>/dev/null; /Users/ben/Projects/work/scripts/run-task.sh 2>&1 | tee -a /Users/ben/Projects/work/cron.log
```

Run this via Bash. Output streams to both stdout (visible here) and cron.log. Report what happened when it finishes.
