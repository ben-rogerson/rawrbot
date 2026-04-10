---
name: rawr-run-auditor
description: Manually run the auditor - review staged plans in plans/ and approve or cancel them into tasks.json.
---

# Approve Plans

## Steps

### 1. Check for staged plans

Run `scripts/list-plans.sh`. If the output is "No staged plans.", tell the user and stop.

### 2. Display each plan

Format the `list-plans.sh` output as a markdown table with columns: **#**, **Title**, **Description** (truncated to ~250 chars).

### 3. Give your take and ask what to approve

After the table, immediately give your own recommendation without waiting to be asked:

- Flag any obvious duplicates (same concept, different slug)
- Suggest a shortlist to approve and which to defer/cancel, with brief reasoning

Then ask: "Which would you like to approve?"

- If the user wants to cancel specific plans, note their slugs
- If the user wants to edit fields, apply those changes to the task being built

### 4. Hand off to the auditor script

Build the command from the user's decisions and run it **in the background** using `run_in_background: true` on the Bash tool:

```bash
REPO=$(git rev-parse --show-toplevel); . ~/.zshrc 2>/dev/null; "$REPO/scripts/run-auditor.sh" --approve slug1,slug2 --cancel slug3 2>&1 | tee -a "$REPO/rawr.log"
```

- Omit `--approve` if nothing was approved
- Omit `--cancel` if nothing was cancelled
- If the user only wants to hold everything, skip the script entirely - staged plans left untouched stay in `plans/`

### 5. Monitor progress

Immediately after launching, start a Monitor watching rawr.log for auditor progress lines:

```bash
REPO=$(git rev-parse --show-toplevel); tail -f "$REPO/rawr.log" | grep --line-buffered "run-auditor:"
```

Set timeout to 300000ms. Tell the user: "Auditor is running - I'll update you as it progresses. Feel free to ask questions while it runs."

Relay each monitor event to the user as it arrives. When you see `run-auditor: done`, stop monitoring and summarise what was approved, cancelled, and extracted into tasks.json.

The script handles plan enhancement, extraction into `tasks.json`, archiving cancelled plans, logging, and the Telegram notification.
