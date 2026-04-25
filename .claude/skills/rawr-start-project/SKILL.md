---
name: rawr-start-project
description: Use to run, start, launch, or use a sub project - detects and starts frontend and/or backend services so the project is usable in the browser
---

# Start Project

## Overview

Detect the project structure, identify how to start each part, and launch everything so the user can immediately use the project.

## Detection

Check the project root for these patterns in order:

**Single fullstack app:**

- `package.json` with `dev` script at root, no separate `frontend/` or `backend/` subdirectories with their own `package.json`
- Run: `pnpm dev`

**Separate frontend + backend:**

- `frontend/package.json` AND `backend/package.json` (or `client/` and `server/`)
- Run both concurrently in background

**Other patterns:**

- `Makefile` with a `dev` or `start` target - use `make dev`
- `docker-compose.yml` - ask user if they want Docker or direct
- Backend only (no frontend dir) - run the backend, note it's API only

## How to Start

1. Read `package.json` (and subdirectory ones if present) to find the actual `dev`/`start` script
2. Check lockfile to confirm package manager: `pnpm-lock.yaml` → pnpm (default), `yarn.lock` → yarn, `package-lock.json` → npm
3. Check `.env` exists - if not, remind user it may be needed (don't block on this)
4. Run each process using Bash with `run_in_background: true`
5. After launching, report what's running and the likely URL(s)

## Common URLs

After starting, tell the user where to look:

- Vite frontend: usually `http://localhost:5173`
- Next.js: usually `http://localhost:3000`
- Express backend: check the port in the source or `.env`, commonly `3001`, `4000`, `8080`

## Quick Reference

| Pattern                  | Command                        |
| ------------------------ | ------------------------------ |
| Root `package.json` only | `pnpm dev` at root             |
| `frontend/` + `backend/` | `pnpm dev` in each, background |
| `client/` + `server/`    | `pnpm dev` in each, background |
| Next.js                  | `pnpm dev` at root             |

## Notes

- Default to pnpm unless a different lockfile is present
- Always run in background so the terminal stays usable
- If `node_modules` is missing, run `pnpm install` first (check before starting)
- If ports are already in use, report the error - don't try to kill processes without asking
