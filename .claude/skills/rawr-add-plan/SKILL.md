---
name: rawr-add-plan
description: Firm up a rough idea into a structured plan document in plans/. Shape a vague concept into something the autonomous agent can execute.
---

# Add Plan

Take a rough idea from the user and shape it into a well-defined plan document in `plans/`. Plans are NOT added to `tasks.json` - they sit in `plans/` for review, then get promoted via `/rawr-run-auditor`.

## Steps

### 1. Parse and identify gaps

Parse the user's idea into what's there and what's missing. It might be vague ("something that tracks my runs"), half-formed ("a webhook thing for GitHub"), or just a sentence. That's fine - your job is to firm it up.

For each idea, assess what's missing from this list:

- **Goal / why** - what problem does this solve or what outcome does it achieve?
- **What "done" looks like** - how will you know it's finished?
- **Approach** - any specific tech stack, file paths, or constraints?

### 2. Ask clarifying questions

If any of the above are unclear or missing, **ask the user before going further.** Bundle all questions into a single message. Examples:

> - What should the finished state look like - a working UI, a CLI script, a data pipeline?
> - Any specific libraries or tech stack preferences?
> - Where should the output live (new project folder, existing project)?
> - Is this urgent or can it wait behind existing tasks?

Skip questions where the answer is obvious from context. Don't ask for information you can reasonably infer.

### 3. Challenge and pressure-test

Before building the plan, act as a high-level advisor. Challenge the user's thinking, question assumptions, and expose blind spots. Don't default to agreement - if the reasoning is weak, break it down and show why. Consider:

- **Is this the right problem to solve?** Is there a simpler or higher-leverage approach?
- **Assumptions** - what's being taken for granted? (e.g. "users want X", "this tech is the right fit", "this is urgent")
- **Scope** - is this too ambitious for one task, or should it be split? Is it too trivial to bother planning?
- **Overlap** - does this duplicate an existing project or queued task?
- **Fit** - does this align with goals.md priorities?
- **Opportunity cost** - is this the best use of agent time right now given current priorities?

Present your pushback concisely. If the idea holds up under scrutiny, say so and move on. If not, suggest a sharper alternative or ask the user to reconsider. Only proceed to step 4 once the user confirms they want to go ahead.

### 4. Shape the plan

Write a plan file matching the format used by `run-planner`:

```markdown
# <Plan Title>

<Description of what to build and why. 1-3 sentences. Reference goals, notes, or observed patterns where relevant.>

## Steps

1. <concrete step 1>
2. <concrete step 2>
3. <verify the change works>

## Meta

- **project:** <folder-name under projects/>
- **addedBy:** user
```

Guidelines:

- Steps should be concrete and ordered - the autonomous agent will follow them literally
- Do NOT include commit steps (the worker agent handles commits separately)
- Keep the description focused on what and why, not how (that's what steps are for)
- The slug filename should be max 5 hyphenated words

### 5. Check for clashes

Run `scripts/list-plans.sh` (for plan slugs) and `scripts/append-task.sh --list` (for task IDs). Make sure the chosen slug doesn't collide with either.

### 6. Preview and confirm

Show the full plan document, then ask: **"Write this to plans/<slug>.md?"**

- **Yes** - write the file to `plans/<slug>.md`
- **No** - discard or revise based on feedback

### 7. Queue or stage

Ask the user: **"Add this directly to the task queue, or leave it staged in plans/ for batch review?"**

- **Queue now** - convert the plan into a task JSON entry (same schema as `/rawr-add-task`) and pipe it to `scripts/append-task.sh`. Delete the plan file from `plans/` after writing.
- **Stage** - leave it in `plans/`. Tell the user: "Run `/rawr-run-auditor` when you're ready to promote it to the task queue."
