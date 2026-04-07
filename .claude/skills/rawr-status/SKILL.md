---
name: rawr-status
description: Show a dashboard summary of the autonomous agent - pending tasks, staged plans, recent progress, and schedule status.
---

# Status

Quick read-only dashboard of the agent's current state. No mutations.

## Steps

### 1. Pending tasks

Read `~/Projects/work/tasks.json`. Count entries where `completedAt` is null. Show the count and list each pending task's id, priority, and project.

### 2. Staged plans

List `.md` files in `~/Projects/work/plans/`. Show the count and each filename.

### 3. Recent progress

Show the last 5 non-empty lines of `~/Projects/work/memory/progress.txt`.

### 4. Schedule status

Run:

```bash
./scripts/launchd.sh status
```

Show which agents are loaded or not.

### 5. Summary

Present all of the above in a compact format. Example:

```
Tasks:    3 pending (2 priority-1, 1 priority-2)
Plans:    2 staged in plans/
Schedule: task-tick LOADED, plan-tick LOADED
Recent:   <last progress line>
```
