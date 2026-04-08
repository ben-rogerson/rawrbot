---
name: rawr-add-task
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

### 3. Challenge and pressure-test

Before building the task, act as a high-level advisor. Challenge the user's thinking, question assumptions, and expose blind spots. Don't default to agreement - if the reasoning is weak, break it down and show why. Consider:

- **Is this the right problem to solve?** Is there a simpler or higher-leverage approach?
- **Assumptions** - what's being taken for granted that might not hold? (e.g. "users want X", "this tech is the right fit", "this is urgent")
- **Scope** - is this too ambitious for one task, or too trivial to bother queuing?
- **Dependencies** - does this block on or conflict with existing tasks or projects?
- **Opportunity cost** - is this the best use of agent time right now given current priorities?

Present your pushback concisely. If the task holds up under scrutiny, say so and move on. If not, suggest a sharper alternative or ask the user to reconsider. Only proceed to step 4 once the user confirms they want to go ahead.

### 4. Build rich task entries

Use the gathered info to produce entries matching the richer schema used in tasks.json:

```json
{
  "id": "slug-here",
  "description": "Full, unambiguous description the agent can act on directly.",
  "steps": ["Concrete step 1", "Concrete step 2", "Verify the change works"],
  "reasoning": "Why this task matters and what success looks like.",
  "priority": 1,
  "project": "folder-name",
  "completedAt": null,
  "addedBy": "user",
  "addedAt": "2026-03-22T10:00:00Z"
}
```

- `id`: lowercase, hyphens only, max 40 chars; append `-2`, `-3` if slug already exists
- `description`: complete enough for the agent to start without asking questions
- `steps`: ordered, specific; do not include commit steps (the worker agent handles commits separately)
- `reasoning`: why the task is valuable and what "done" looks like
- `priority`: 1 = highest; look at existing tasks to assign relative priority
- `project`: the folder name under subfolder /work/ (required, even if folder doesn't exist yet)
- `completedAt`: always `null`
- `addedBy`: `"user"`
- `addedAt`: current ISO 8601 timestamp

### 5. Read existing tasks

Run `scripts/append-task.sh --list` to see existing task IDs and priority spread.

### 6. Preview and confirm

Show the new entries as formatted JSON, then ask: **"Add these to tasks.json?"**

- **Yes** → for each task, pipe its JSON to `scripts/append-task.sh`:
  ```bash
  echo '<task-json>' | scripts/append-task.sh
  ```
- **No** → discard and confirm nothing was written
