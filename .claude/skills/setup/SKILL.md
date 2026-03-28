---
name: setup
description: Use when setting up this autonomous agent workspace for the first time - creates missing config files, initialises the task queue, and installs launchd agents.
---

# Setup

Walk the user through first-time setup of this workspace. Create each missing file with example content, then install the launchd agents.

## Steps

### 1. Detect what's already there

Check which of these files/directories exist:

- `.env`
- `goals.md`
- `notes.md`
- `tasks.json`
- `progress.txt`
- `MEMORY.md`
- `memory/`

Skip creating any that already exist. If everything exists, say so and stop.

### 2. Create `.env`

If `.env` is missing, create it by copying `.env.example` and ask the user for the correct `WORKDIR` value (absolute path to this repo). Write the filled-in file:

```
WORKDIR=/absolute/path/to/this/repo

# Optional: Telegram notifications
TELEGRAM_BOT_TOKEN=your-telegram-bot-token
TELEGRAM_CHAT_ID=your-telegram-chat-id
```

Tell the user: Telegram vars are optional - leave them as placeholders if not using Telegram.

### 3. Create `goals.md`

If missing, create it with this example structure:

```markdown
# Goals

## What I'm building

<!-- Describe the project or domain you want the agent to work on -->

A collection of small tools and experiments.

## Priorities

1. <!-- Your top priority -->
2. <!-- Second priority -->

## Constraints

- <!-- Any hard limits, e.g. "TypeScript only", "no paid APIs" -->

## Self-Evolution

<!-- The planning agent appends observations here over time -->
```

Tell the user: this is the agent's north star - edit it freely to steer what gets built.

### 4. Create `notes.md`

If missing, create an empty file with a single comment line:

```markdown
<!-- Drop ideas here in plain English. The planning agent converts actionable ones to tasks each morning. -->
```

### 5. Create `tasks.json`

If missing, write an empty JSON array:

```json
[]
```

### 6. Create `progress.txt`

If missing, create an empty file.

### 7. Create `MEMORY.md`

If missing, create it with a header comment:

```markdown
# Memory Index

<!-- The agent maintains this index. Each entry links to a dated file in memory/. -->
<!-- Example: - [memory/2026-03-23.md](memory/2026-03-23.md) — first session, bootstrapped workspace -->
```

### 8. Create `memory/` directory

If missing, create the directory with a `.gitkeep` so it's tracked:

```bash
mkdir -p memory && touch memory/.gitkeep
```

### 9. Install launchd agents

Ask the user: "Would you like me to install the launchd agents now?"

If yes, run:

```bash
./scripts/launchd.sh install
```

Then run `./scripts/launchd.sh status` to confirm they loaded.

If no, tell the user they can install later with `./scripts/launchd.sh install`.

The plist files in `launchd/` define the schedules. The user can edit them and re-run `./scripts/launchd.sh install` to apply changes.

### 10. Summary

Print a checklist of what was created/skipped, and remind the user:

- Edit `goals.md` to describe what they want built
- Run `./scripts/plan-tick.sh` manually to generate the first batch of tasks
- Use `/add-task` in Claude Code to queue tasks directly
- Add ideas to `notes.md` to guide the tasks the agent will generate
