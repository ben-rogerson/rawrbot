---
name: task-tick
description: Use when the user wants to manually run the task execution agent - picks the highest priority task from tasks.json and executes it
---

# Task Tick

Run the task execution agent exactly as the launchd agent would.

## Command

```bash
. ~/.zshrc 2>/dev/null; /Users/ben/Projects/work/scripts/task-tick.sh >> /Users/ben/Projects/work/cron.log 2>&1
```

Run this via Bash and report what was logged to cron.log afterwards.
