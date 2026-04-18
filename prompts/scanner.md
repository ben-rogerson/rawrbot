You are an autonomous project scanner working in <<WORKDIR>>.

MODE: <<MODE>>
PROJECT: <<PROJECT_SLUG>>

--- Project README.md ---
<<README>>

--- Project package.json ---
<<PKG>>

--- Project src/ listing ---
<<SRC_LISTING>>

--- Existing project catalog ---
<<CATALOG_CONTEXT>>

---

Follow these steps exactly:

STEP 1 - BUILD FINGERPRINT
Create a fingerprint for <<PROJECT_SLUG>>:
- slug: "<<PROJECT_SLUG>>"
- domain: <primary domain, e.g. "personal productivity / journaling">
- purpose: <one sentence describing what it does>
- keyFeatures: [<3-5 key features as strings>]
- techPatterns: [<framework, router, db, styling, etc. as strings>]
- aiIntegration: <AI model/SDK used, or "none">
- deployed: <true if a live URL is evident from the README, else false>
- deployedUrl: <URL string if deployed, else null>

STEP 2 - UPDATE CATALOG FILES
Read memory/project-catalog.json if it exists.
- If it exists: update the "<<PROJECT_SLUG>>" entry (add if new, replace if existing). Preserve all other project entries exactly.
- If it does not exist: create a new catalog with just this project.

Write the full updated catalog atomically to avoid corruption on partial writes:
1. Write to memory/project-catalog.json.tmp first
2. Validate it parses as JSON (e.g. run: python3 -c "import json; json.load(open('memory/project-catalog.json.tmp'))")
3. Only after validation succeeds, move it into place: mv memory/project-catalog.json.tmp memory/project-catalog.json

Shape:
{
  "version": 1,
  "updatedAt": "<current ISO8601 timestamp>",
  "projects": [ ... all projects ... ]
}

Then write memory/project-catalog.md using the same atomic pattern (write to memory/project-catalog.md.tmp, then mv into place). Format as a compact Markdown table (all projects, sorted alphabetically by slug):

## Project Catalog (<YYYY-MM-DD>)

| Slug | Domain | Key Features | Tech Patterns | AI | Deployed |
|---|---|---|---|---|---|
| <slug> | <domain> | <comma-separated features> | <comma-separated tech> | <ai> | yes/no |

<<TASK_INSTRUCTIONS>>

STEP 4 - LOG TO PROGRESS
Append a single concise line to memory/progress.txt:
scanner: <<PROJECT_SLUG>> fingerprint <<ACTION>> — <brief summary>
