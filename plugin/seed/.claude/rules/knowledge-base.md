---
paths:
  - "/knowledge/**"
---

# Knowledge base

Loads when you read anything under `knowledge/`. The instance `CLAUDE.md` keeps
the reading rule itself, because it has to be in context *before* the first read —
by the time this file loads you are already reading a `knowledge/` doc.

- `knowledge/` is an OKF knowledge base in this bundle — a `Service` catalog,
  `Finding`s (decisions/learnings), `Runbook`s, `Team`s, and `Reference`s
  (durable specs/contracts) (see `SCHEMA.md`).
- The `cataloguer` agent builds/refreshes it (read-only on product repos); task
  agents write a `Finding` **only when a later task would plausibly hit the same problem**, and link it from the task.
- **Grep it, never read the index whole.** Before researching or implementing, start
  from your brief's `## Knowledge` rows, then `grep -i '<term>' knowledge/index.md`
  (capped) or `grep -ril '<term>' knowledge/` past the cap, and open **at most three**
  matching `Finding`s / `Service` / `Runbook` / `Team` docs — **never bulk-read `knowledge/`**. If a relevant `Finding` already answers a
  question, cite it and move on. The KB is **pull-based** (read on demand); it is
  deliberately *not* auto-loaded into context, so it never bloats a session.
- **A row under a `Superseded` heading is history, not guidance.** Open one to see why a
  decision was reversed; never cite it — `cite-check.sh` reports it as `SUPERSEDED` and
  drops it. Cite the replacement its `Superseded by` column names.
- **`index.md` is derived — fix the document, not the row.** `build-kb-index.sh` rebuilds
  every row from frontmatter (summary = the doc's `lesson:`), and `--check` fails when the
  file and the documents disagree. A hand-edited row is undone by the next rebuild.
- **Tags are a closed set: `knowledge/vocab.md`.** Ground a lookup by **longest match**
  over its **tag** and **alias** columns, use the canonical tag, and **never invent one** — if
  nothing fits, add the row in the same change. `--check` refuses anything else.
