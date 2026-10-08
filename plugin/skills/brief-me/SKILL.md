---
name: brief-me
description: A since-you-last-looked digest of this control panel — or a meeting-ready brief for one project
argument-hint: "[project-slug]  omit for the whole board"
---

Produce a **brief** for the human — read-only, decision-oriented, meeting-friendly.
You never dispatch, promote, merge, or edit anything here.

## Preconditions

Run from a control-panel instance root: `instance.config.json` must exist in the cwd and
`SCHEMA.md` at the resolved schema path (`AB_SCHEMA`; the root on a legacy layout) — check with exactly
`ls instance.config.json "$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/bundle-paths.sh AB_SCHEMA)" 2>/dev/null || ls instance.config.json SCHEMA.md`. If it fails, say which instance directories exist nearby (if any) and stop.

## Gather — cheaply, in this order

1. `${CLAUDE_PLUGIN_ROOT}/scripts/tick-delta.sh digest` — one command yields every live project, every task's
   status/kind/assignee/deps/open-question count, and each open PR's state, head and
   review decision. Any exit but 0 ⇒ fall back to reading `projects/*/project.md` and
   task frontmatter yourself (skip `status: done` projects at their frontmatter).
2. `AWAITING.md`, if present — the queue of what needs the human.
3. The `recorded:` line of `.tick-state`, if present — it dates the last full tick, which
   is the honest "since" for any "what changed" framing.

Open a specific task or project document **only** when the brief needs its exact wording
(a question to quote verbatim, a goal statement). Never bulk-read the bundle or
`knowledge/` — consult `knowledge/index.md` first if a Finding is worth citing.

## Output — two modes

**No argument — the board brief.** Lead with one sentence: the single most important
thing (a decision waiting, a PR ready to merge, or "all quiet since <recorded>"). Then:

1. **Needs you** — the queue, one line per item, verb first (approve / answer / merge /
   unblock / close), each with its real link. If `AWAITING.md` is absent, derive the
   same list from the digest. Nothing else goes in this list.
2. **In flight** — a table: task · project · status · PR (as `[<repo>#<n>](url)`) ·
   review state. Only non-terminal work.
3. **Since the last full tick** — what actually moved (merges reflected, statuses
   changed, questions answered). If nothing moved, one line says so; do not pad.

**With a project slug — the meeting brief.** For `projects/<slug>/`: one-paragraph goal
(from `project.md`, in plain language), then a task table (id · title · status · PR
link), open questions **quoted verbatim** with their `Qn:` numbers so the human can
answer by number, blockers with owners, and last a **"decide today"** list — the one to
three decisions that unblock the most work, each one line.

## Style

Follow the instance `CLAUDE.md` reporting rules: lead with the outcome, tables over
paragraphs, decisions last and short, every PR as `[<repo>#<n>](url)`, no bare URLs.
The whole brief should read in under a minute. No customer PII, ever — describe shapes,
not records.
