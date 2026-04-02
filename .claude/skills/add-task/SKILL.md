---
name: add-task
description: Add one or more tasks to tasks.json from natural language. Use when the user wants to queue work for the autonomous agent.
---

# Add Task

Convert the user's natural language input into one or more richly-detailed entries in `tasks.json`. **Always gather enough detail to make each task self-contained and unambiguous for the autonomous agent.**

## Steps

### 1. Parse and identify gaps

Parse the user's input into discrete tasks. Split compound requests - e.g. "build a garden planner and also send a digest" → two tasks.

For each task, assess what's missing from this list:
- **Goal / why** - what outcome does this achieve?
- **Acceptance criteria** - how does the agent know it's done?
- **Steps / approach** - any specific tech stack, file paths, or constraints?
- **Priority** - how urgent is this relative to existing tasks?

### 2. Ask clarifying questions

If any of the above are unclear or missing, **ask the user before generating the task entry.** Bundle all questions into a single message. Examples:

> - What should the finished state look like - a working UI, a CLI script, a markdown file?
> - Any specific libraries or tech stack preferences?
> - Where should the output live (file path)?
> - Is this urgent or can it wait?

Skip questions where the answer is obvious from context. Don't ask for information you can reasonably infer.

### 3. Build rich task entries

Use the gathered info to produce entries matching the richer schema used in tasks.json:

```json
{
  "id": "slug-here",
  "description": "Full, unambiguous description the agent can act on directly.",
  "steps": [
    "Concrete step 1",
    "Concrete step 2",
    "Verify the change works"
  ],
  "reasoning": "Why this task matters and what success looks like.",
  "priority": 1,
  "passes": false,
  "addedBy": "user",
  "addedAt": "2026-03-22T10:00:00Z"
}
```

- `id`: lowercase, hyphens only, max 40 chars; append `-2`, `-3` if slug already exists
- `description`: complete enough for the agent to start without asking questions
- `steps`: ordered, specific; do not include commit steps (the task-tick agent handles commits separately)
- `reasoning`: why the task is valuable and what "done" looks like
- `priority`: 1 = highest; look at existing tasks to assign relative priority
- `passes`: always `false`
- `addedBy`: `"user"`
- `addedAt`: current ISO 8601 timestamp

### 4. Read existing tasks

Read `~/Projects/work/tasks.json`. If missing or empty, treat as `[]`. Collect existing `id` values and note current priorities.

### 5. Preview and confirm

Show the new entries as formatted JSON, then ask: **"Add these to tasks.json?"**

- **Yes** → append to existing array and write back to `~/Projects/work/tasks.json`
- **No** → discard and confirm nothing was written
