---
name: rawr-run-worker
description: Manually run the task execution agent - pick the highest priority task from tasks.json and execute it. Optionally pass a task ID to target a specific task, skipping the queue.
---

# Run Task

## Steps

1. Run the script **in the background** (`run_in_background: true`):

   ```bash
   REPO=$(git rev-parse --show-toplevel); . ~/.zshrc 2>/dev/null; "$REPO/scripts/run-worker.sh" ${ARGUMENTS} 2>&1 | tee -a "$REPO/rawr.log"
   ```

2. Start a Monitor watching rawr.log for worker progress lines:

   ```bash
   REPO=$(git rev-parse --show-toplevel); tail -f "$REPO/rawr.log" | grep --line-buffered "run-worker:"
   ```

   Set timeout to 600000ms. Tell the user: "Worker is running - I'll update you as it progresses. Feel free to ask questions while it runs."

3. Relay each monitor event to the user as it arrives (e.g. "run-worker: targeting task '...'", "run-worker: calling claude...").

4. When you see `run-worker: task executed` or `run-worker: all tasks already complete` in the monitor events, stop monitoring and report what was done (check the last line of `memory/progress.txt` for a summary).

## Usage

- `/rawr-run-worker` - runs the next pending task (queue order)
- `/rawr-run-worker <task-id>` - runs a specific task by ID, skipping the queue
