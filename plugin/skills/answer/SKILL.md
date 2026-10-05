---
name: answer
disable-model-invocation: true
description: Answer the PM's pending open_questions interactively — gather the unanswered questions (all projects, one project, or one task), ask them in one batch, then fold the answers back into the tasks (clearing them). In-session convenience instead of editing each task file by hand.
argument-hint: "[<project-slug> | projects/<slug> | <task path>]  omit for every project"
allowed-tools: Bash(pwd), Bash(ls:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/bundle-paths.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/decision-stamp.sh:*), Read, Edit, Glob, Grep, AskUserQuestion
---

Answer the Project Manager's pending `open_questions` **interactively**, instead of
opening each `taskX.md` and appending ` --- <answer>` by hand.

## Preconditions
Run from a control-panel instance root — confirm `instance.config.json` in the cwd and
`SCHEMA.md` at the resolved schema path (`AB_SCHEMA`; the root on a legacy layout) with exactly
`ls instance.config.json "$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/bundle-paths.sh AB_SCHEMA)" 2>/dev/null || ls instance.config.json SCHEMA.md`; if it fails, tell the user to `cd` into the instance and stop. (A bundle
carries no `.claude/agents`; the roles ship in the plugin — `SCHEMA.md` → "Which document
wins", row 1.)

## Scope — `$ARGUMENTS`
- **Empty** ⇒ every project: glob `projects/*/tasks/*.md`.
- **A project** — a slug (`ai-bridge-v2`), a `projects/<slug>` path, or a full path to
  a project directory ⇒ only that project's `tasks/*.md`.
- **A task** — a path that resolves to a file under `projects/*/tasks/` ⇒ exactly
  that one file. A `.md` anywhere else is NOT a task and is rejected like a no-match:
  only task documents carry `open_questions`, and the fold-back step must never
  write answers into an arbitrary file.
- Anything that resolves to no project directory and no task file: say what didn't
  match, list the project slugs that exist, and stop — never fall back to all
  projects on a typo, silently widening what gets edited.

## Steps
1. **Gather.** Within the scope above, collect every task with a non-empty
   `open_questions` list. For each entry (numbered `Q1:`, `Q2:`, …) record the task path
   + question text.
2. **Ask.** Present them with `AskUserQuestion`, batched (max 4 per call — loop if there
   are more), grouped by task so the context is clear. Where you can propose plausible
   answers, offer them as options; otherwise take free-form. When several options could
   jointly apply, mark that question `multiSelect` so more than one can be picked —
   selections then fold back as ONE combined answer on the question's line.
3. **Fold back.** For each answered question, bake the answer into the task itself
   (`# Context`, a tightened `acceptance_criteria`, or `# Notes` as fits) and **move
   that entry** out of `open_questions` into `answered_questions` — the same effect as
   the ` --- <answer>` delimiter, applied here. Write the moved entry as one flat line —
   the current ISO 8601 timestamp, then ` by <login> · `, then the original question with
   the answer appended after ` --- `, e.g.
   `2026-01-01T00:00:00Z by example-user-007 · Q1: which region? --- eu-central-1`.
   **The login is YOURS** — you are answering in this session — from
   `${CLAUDE_PLUGIN_ROOT}/scripts/decision-stamp.sh --self`, written as `<unknown>` when
   this clone configures no `ownerGithubUser`. A decision a document records says who
   made it (`SCHEMA.md` → "Decisions name the human").
   Make sure it is **gone from `open_questions`**: that list emptying is
   what makes the draft promotable, so an entry left in both places blocks it forever.
   `answered_questions` is a human audit record — nothing reads it (see `SCHEMA.md`).
4. **Report** which tasks became clean (empty `open_questions`). Under `gated` they're
   now promotable by the human; where the project delegates promotion (`AUTONOMY.md`), the next `/loopd:dispatch` tick will
   auto-promote the clean **build** tasks (research stays human-driven). This command
   **only answers questions** — it never promotes,
   dispatches, or merges.

## Notes
- **Foreground/interactive only** — a background `/loopd:dispatch` tick can't prompt you; it
  parks questions on the 🔴 board, and you clear them here (or by editing the task docs).
- Commit is optional: the next `/loopd:dispatch` tick commits the doc changes under the PM
  identity, or commit them yourself using this bundle's usual process.
- No customer PII in answers written to task docs — and note `answered_questions`
  **keeps them for the life of the repo**, so an answer you would not commit is an
  answer to give in person instead.
