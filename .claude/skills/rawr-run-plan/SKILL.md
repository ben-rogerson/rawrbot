---
name: rawr-run-plan
description: Use when the user wants to manually run the planning agent - generates plan files in plans/ for review, updates goals.md
---

# Run Plan

Reads `goals.md` and `notes.md`, generates 1-5 plan files in `plans/` for review. Does NOT execute anything or modify `tasks.json`.

After running, review the plan files in `plans/`, then clear context and run `/rawr-approve-plans` to extract approved plans into `tasks.json`.

## Command

```bash
. ~/.zshrc 2>/dev/null; /Users/ben/Projects/work/scripts/run-plan.sh >> /Users/ben/Projects/work/cron.log 2>&1
```

Run this via Bash and report what was logged to cron.log afterwards.
