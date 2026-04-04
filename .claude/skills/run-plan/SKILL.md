---
name: run-plan
description: Use when the user wants to manually run the morning planning agent - generates new tasks, updates goals.md, writes morning plan summary
---

# Run Plan

Run the planning agent exactly as the launchd agent would.

## Command

```bash
. ~/.zshrc 2>/dev/null; /Users/ben/Projects/work/scripts/run-plan.sh >> /Users/ben/Projects/work/cron.log 2>&1
```

Run this via Bash and report what was logged to cron.log afterwards.
