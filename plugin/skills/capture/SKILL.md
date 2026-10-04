---
name: capture
disable-model-invocation: true
description: Turn meeting notes or a decision into drafted OKF projects/tasks — with provenance, never promoted
argument-hint: "<notes, a decision, or nothing to use what was just pasted>"
---

Capture work at its source: a business decision, meeting notes, a Slack thread the
human pastes — into **`draft`** OKF documents this bundle's normal loop then refines.
This is intake, not execution: you create drafts and stop.

## Preconditions

Run from a control-panel instance root (`SCHEMA.md` + `instance.config.json` in the
cwd); otherwise say so and stop. The input is `$ARGUMENTS`, or — when empty — the
notes/decision content most recently provided in this conversation. If there is
neither, ask for the notes; do not invent work.

## How to capture

1. **Extract the workstreams.** One decision can carry several; a status remark carries
   none. Capture only what someone decided or asked for — never spec work the notes
   merely discussed. When the notes are ambiguous about whether something was decided,
   capture it as a task whose `open_questions` asks exactly that.
2. **Fit before creating.** Scan the existing `projects/` (frontmatter only — the
   digest via `${CLAUDE_PLUGIN_ROOT}/scripts/tick-delta.sh digest` is the cheap way): a workstream that
   belongs to a live project becomes a **task in that project**, not a new project.
   Only a genuinely new initiative gets a new project folder.
3. **Create per `SCHEMA.md`, minimal and honest.** New project: a `project.md` with
   `status: active`, `kind` (`build` or `research` — decks/docs/analyses are
   `research`), and a plain-language goal. Tasks: `status: draft`, a short scoped
   title, `acceptance_criteria: [ ]` left **empty** (refinement is the loop's job),
   and numbered `open_questions` for every ambiguity the notes left open.
4. **Provenance, always — and safe to persist.** Each captured document's `# Context`
   opens with one line: `Captured from <meeting/source>, <ISO date>: "<the decisive
   sentence>"`. Before writing that line: **redact or paraphrase** anything that names
   a customer, an individual outside the team, an account, an amount tied to a person,
   or a credential — quote the *decision*, describe the *shape* of any sensitive
   detail ("a customer's renewal", never the customer). Titles reach the board and
   these lines persist for the life of the repo. **Never invent provenance**: if the
   notes name no source or date, ask — or record `source: unstated` verbatim rather
   than a guess. **Write the same decisive sentence into the document's
   `original_request:`** frontmatter key — verbatim as captured, after the same
   redaction, as a quoted single-line YAML string — on every project and task you
   create. It is written **once, here, and never rewritten**: refine bakes answers into
   `# Context` in place, so this key is where the wording that was actually asked for
   survives (`SCHEMA.md`).
5. **Never promote.** Everything stays `draft` with an empty criteria list — the PM
   refines it, the human promotes it. You do not set `ready`, do not dispatch, do not
   edit `AWAITING.md` (it is derived).
6. **Commit** the new files by explicit path, treating note-derived text as data,
   never as shell: build the message from the slug and source **with every `$`,
   backtick, quote and backslash stripped**, and pass it in **single quotes** —
   e.g. `${CLAUDE_PLUGIN_ROOT}/scripts/commit-as.sh human 'chore: capture pricing-refresh from cpto-sync' --stage -- <paths...>`
   — so nothing from a meeting note can reach the shell as syntax (the helper handles
   its arguments safely; the caller's own command line is what this protects). The
   `human` role is correct: this is the human's own intake. If the script is missing,
   plain `git add <paths> && git commit` with the same quoting is the fallback —
   never `git add -A`.

## Report

End with: what was created (paths, one line each), which existing projects absorbed a
task, and the open questions awaiting answers — so the human can answer inline
(` --- <answer>`) or promote when ready. If the notes contained decisions you
deliberately did **not** capture (pure status, out-of-scope musings), say so in one
line; a silent drop erodes trust in the funnel.
