---
name: rawr-run-auditor
description: Manually run the auditor - review staged plans in plans/ and approve or cancel them into tasks.json.
---

# Approve Plans

## Steps

### 1. Check for staged plans

Run `scripts/list-plans.sh`. If the output is "No staged plans.", tell the user and stop.

### 2. Display each plan

Format the `list-plans.sh` output as a markdown table with columns: **#**, **Title**, **Project**, **Priority**, **Description** (truncated to ~250 chars).

### 3. Give your take and ask what to approve

After the table, immediately give your own recommendation without waiting to be asked:

- Flag any obvious duplicates (same concept, different slug)
- Group by priority and note which are the clearest wins
- Suggest a shortlist to approve and which to defer/cancel, with brief reasoning

Then ask: "Which would you like to approve?"

- If the user wants to cancel specific plans, note their slugs
- If the user wants to edit fields, apply those changes to the task being built

### 4. Review and enhance agent-generated plans

For each approved plan, check its `addedBy` field in the `## Meta` section.

**Skip** plans where `addedBy: user` — they were already shaped through the add-plan interview.

**For each `addedBy: agent` plan (or plans missing the field):**

4a. Use TaskCreate to add: "Review and enhance: `<slug>`"

4b. Use Read to load `plans/<slug>.md`, then assess:
- **Steps are concrete** - each names a real action (scaffold, install, write, deploy), not a vague directive ("set up", "handle", "build")
- **Full lifecycle** - covers init, implementation, AI integration (if applicable), and deployment
- **Description is self-contained** - what and why are clear from the opening paragraph alone
- **Priority is justified** - priority 1 implies urgency or dependency
- **Steps match the description** - no obvious gaps between the promise and the steps

If fixes are needed, use Edit to make targeted improvements in-place. Do not restructure a fundamentally sound plan - only fix what is clearly wrong or missing.

4c. Use TaskUpdate to mark the review task complete. Report one line per plan: what changed, or "no changes needed".

### 5. Extract approved plans

Run the extract script with the slugs (filenames without `.md`) of the approved plans:

```bash
bash scripts/extract-plans.sh <slug1> [<slug2> ...]
```

The script parses each plan file, appends entries to `tasks.json` (safe write via tmp), and moves approved plan files to `plans/approved/`.

### 6. Move explicitly cancelled plans

If the user asked to cancel specific plans, move only those to `plans/cancelled/`:

```bash
mkdir -p plans/cancelled && mv plans/<slug>.md plans/cancelled/
```

Do not move any plans the user did not explicitly ask to cancel. Unapproved plans that weren't cancelled stay in `plans/` untouched.

### 7. Confirm

Show the user what was added: count of tasks, their ids, priorities, and projects. Note any agent plans that were enhanced and any explicitly cancelled plans.
