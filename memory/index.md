# Memory

Long-term agent memory. Updated by the agent after each session.

## Key Decisions

- run-task.sh runs every hour via launchd
- run-plan.sh runs daily at 7am via launchd
- ANTHROPIC_API_KEY is not exported in the agent shell environment. Scripts that call the Anthropic SDK directly need the key set manually or via .env loading.

## Projects

- `projects/new-releases/` - Spotify new releases browser (Express token proxy + Vite/React)
- `projects/garden-planner/` - Garden plant log (Express REST API + Vite/React)
- `projects/ai-digest/` - AI digest generation script (TypeScript + @anthropic-ai/sdk, pnpm run generate)
- `projects/visual-comms/` - Visual communication SPA for Christiane (Vite/React, Web Speech API, localStorage phrases)
- `projects/grocery-tracker/` - Grocery price tracker (Express REST API + Vite/React/Tailwind, tracks Coles/Woolworths/ALDI prices, highlights cheapest)
- `projects/ai-client/` - Multi-provider AI client library (TypeScript, createClient() factory, ClaudeClient/OpenAIClient/GeminiClient adapters, FallbackClient)
- `projects/interview-prep/` - Behavioural interview prep (Next.js 16 App Router, STAR stories, Claude AI review with clarity score + feedback, data/stories.json persistence)
- `projects/github-notifier/` - GitHub friend activity notifier (TypeScript + ts-node, polls public events API, sends Telegram notifications for new repos/pushes)
- `projects/med-tracker/` - Daily cholesterol pill reminder (TypeScript + ts-node, Telegram, 24-pill supply tracking)
- `projects/plant-waterer/` - Plant watering reminder (TypeScript + ts-node, Telegram, seasonal adjustments for Adelaide)
- `scripts/clean-downloads.sh` - Weekly ~/Downloads organiser (bash, sorts by type, archives old, dedupes by md5)
- `scripts/check-network.sh` - Weekly network diagnostic (bash, connectivity/speed/DNS/devices/VPN)
- `projects/forge/` - Multi-agent orchestration framework (Mastra v1.3 + TypeScript + Zod v4, config-driven model swapping, 11 tools with createTool)
- `projects/bens-tech-sync/` - GitHub stars + Chrome history + stack prefs syncer (TypeScript + Gemini 2.5 Flash, feeds real interests into goals.md for plan-tick, launchd daily 6:30am)
- `projects/clay-journal/` - Clay sculpting progress journal (Hono API port 3027 + TanStack Router/Query, vertical timeline layout, material inventory, firing log, Gemini AI advisor)
- `projects/email-digest/` - Daily Gmail digest script (googleapis + Gemini 2.5 Flash categorisation + Telegram, launchd 9am daily)
- `projects/page-summariser-ext/` - Chrome MV3 extension (one-click page summaries via Gemini, esbuild, React popup)
- `projects/build-monitor/` - Real-time CI/CD build monitor (Hono SSE + GitHub Actions API + React + Gemini AI, port 3028)
- `projects/knowledge-base/` - Personal RAG knowledge base (Hono API + Gemini embeddings + cosine similarity + cheerio + React, port 3029)
- `projects/network-dashboard/` - Home network dashboard (Hono API + ARP scan + networkQuality + DNS + React + Gemini AI, port 3030)
- `projects/news-aggregator/` - Personalised news aggregator (Astro 5 + React islands + 9 RSS sources + fast-xml-parser + per-user thumbs-down prefs)
- `projects/claude-launcher/` - Ink-based CLI preset launcher for Claude Code (ccl command, fuzzy filter, ~/.config/claude-launcher/presets.json config)
- `projects/webhook-inspector/` - Self-hosted webhook inspector (Hono SSE + React + Gemini AI, port 3034, deployed to CF Workers/Pages)
- `projects/grocery-list/` - AI-powered grocery list builder with 4-step wizard (Hono + React + Gemini AI, port 3031, deployed to CF Workers/Pages)
- `projects/airfryer-recipes/` - Air fryer recipe collection with AI suggestions (Hono + React + Gemini AI, port 3012, deployed to CF Workers/Pages)
- `projects/retro-shelf/` - Retro game collection manager with TanStack Table (Hono + React + Gemini AI, port 3021, deployed to CF Workers/Pages)
- `projects/woodwork-planner/` - Woodworking project planner with board feet calculator (Hono + React + Gemini AI, port 3019, deployed to CF Workers/Pages)
