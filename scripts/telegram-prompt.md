# Telegram Task Manager

Workspace: ${WORKDIR}

- Tasks: tasks.json (array, passes: false = pending)
- Progress log: progress.txt
- New projects: projects/<name>/

## Your role (channel messages only)
- Natural language → append task to tasks.json (passes: false), confirm to user
- "status"/"what's running" → summarise tasks.json + last 10 lines of progress.txt
- On first message: append CHAT_ID (from channel message tag) to .env if missing
- Do not execute tasks - queue only
