---
name: answer
disable-model-invocation: true
description: Answer the PM's pending open_questions interactively — gather the unanswered questions (all projects, one project, or one task), ask them one at a time, then record each through answer.sh (clearing them). Given a blocked task, take your one decision and return it to ready. In-session convenience instead of editing each task file by hand.
argument-hint: "[<project-slug> | projects/<slug> | <task path> [Q<n>] <n | more | later | text> | <blocked task path> [<decision>]]  omit for every project"
allowed-tools: Bash(pwd), Bash(ls:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/bundle-paths.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/decision-stamp.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/answer.sh:*), Read, Write, Glob, Grep, AskUserQuestion
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
- **A project** — a slug (`checkout-v2`), a `projects/<slug>` path, or a full path to
  a project directory ⇒ only that project's `tasks/*.md`.
- **A task** — a path that resolves to a file under `projects/*/tasks/` ⇒ exactly
  that one file. A `.md` anywhere else is NOT a task and is rejected like a no-match:
  only task documents carry `open_questions`, and the record step must never
  write answers into an arbitrary file.
- Anything that resolves to no project directory and no task file: say what didn't
  match, list the project slugs that exist, and stop — never fall back to all
  projects on a typo, silently widening what gets edited.

## One answer from the arguments — `<task path> [Q<n>] <n | more | later | text>`
When a task path is followed by more words, run exactly
`bash ${CLAUDE_PLUGIN_ROOT}/scripts/answer.sh <task path> [Q<n>] <the rest>` and relay its
output; skip the steps below. It answers `Q<n>`, else the first open question: a bare
integer records that option's **text** from the `### Q<n>` block (`SCHEMA.md` → "Question
details"), `--text <words>` records the words even when they are a number or `more`, and
any other words are the answer. It moves the entry into `answered_questions`, stamped
`by <login>` from `decision-stamp.sh --self`, commits it as you through `commit-as.sh human`, then pushes it through `push-commit.sh` when the clone has
an upstream, and refreshes `SNAPSHOT.json` (`write-snapshot.sh --quiet`, best-effort) so `/pane` shows it. It bakes nothing into the body: the moved line and the `### Q<n>` block are
the record. `more` prints the next stored depth (1, then 2, then 3) and changes no tracked file.
`later` sends `Q<n>` to the end of the pane's inbox (one line in this clone's untracked
`AB_ANSWER_LATER` file) and changes no tracked file either; only a numbered question can wait.
- **Exit 5** — `more` is past the stored depths: answer the question yourself, here, from
  the task document and its sources, one level deeper than depth 3. Write nothing.
- **Exit 1** — relay its one sentence and stop. **Exit 3** — the move was refused,
  nothing written. **Exit 4** — the answer is recorded but not pushed: relay the line
  and stop; a rebase it did not start is left alone. **Exit 6** — `more` or `later` could not save
  its record: relay the line and stop. Never force-push, never resolve a rebase for the human.

## A blocked task — `<task path> [<decision>]`
When the task's `status:` is `blocked` and no `Q<n>` was given, `answer.sh` hands it to
`unblock.sh`. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/answer.sh <task path>` first and relay
its `last_blocker` and escalation note — in the session, never the pane. **Exit 1** — the task
still has open questions, named in its one sentence: ask those through the steps below and stop;
it is unblocked only once they are gone (`answer.sh --first <task path> <answer>` answers the first,
numbered or not). `more`, `later` or a bare number is refused as a decision; pass it with `--text`. With no decision in the arguments, ask for exactly one
with `AskUserQuestion` — what the next agent should do differently, in a line. Then run
`bash ${CLAUDE_PLUGIN_ROOT}/scripts/answer.sh <task path> --text <the decision>`: one `# Notes`
line `- <ISO 8601> by <login>: unblocked — <decision>`, the stall counter reset, `status: ready`,
committed as you. Exit 3 and 4 read as above. It never dispatches: the next tick does.

## Steps
1. **Gather.** Within the scope above, collect every task with a non-empty
   `open_questions` list. For each entry (numbered `Q1:`, `Q2:`, …) record the task path
   + question text.
2. **Ask.** Present them with `AskUserQuestion`, one question per call, in task order so
   the context is clear. **Show each question's recommendation
   beside it** — the `Recommendation:` line of its `### Q<n>` block, or `no recommendation`
   when the block has none — and offer the block's `Options:` in order, option 1 first and
   labelled `(Recommended)`: picking it takes the recommendation, as `answer.sh … 1` does.
   With no block, propose plausible answers as options where you can; otherwise take free-form. When several options could
   jointly apply, mark that question `multiSelect` so more than one can be picked —
   selections are then recorded as ONE answer (step 3).
3. **Record.** One `answer.sh` call per answer, in the order asked — **never edit the task
   doc yourself** (no `Edit`, perl or sed):
   - a picked option `k`: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/answer.sh <task path> Q<n> <k>`;
   - free text, or a `multiSelect` answer joined into one line (the picked options' texts,
     `; `-separated): `Write` it to `<bundle root>/tmp/answer.txt` (gitignored), then
     `… answer.sh <task path> Q<n> --text-file <that path>` — never as an argument;
   - an unlabelled entry: `answer.sh --first <task path> …` only while it is the task's first
     open entry; otherwise record nothing and name it in the report, to be asked by name.
   `answer.sh` stamps the moved line `by <login>`, commits it as you and pushes; it bakes
   nothing into the body — the next tick re-bakes it into the criteria (`refine owed`).
   **Any non-zero exit at answer k of N stops here**: report which answers were recorded
   (exit 4: answer k is committed but not pushed) and which were not, and leave the rest
   for a re-ask. Never retry, never edit the doc by hand.
4. **Report** which tasks became clean (empty `open_questions`). Under `gated` they're
   now promotable by the human; where the project delegates promotion (`AUTONOMY.md`), a later `/loopd:dispatch` tick re-bakes
   the answers, then may auto-promote the clean **build** tasks (research stays human-driven). This command
   **only answers questions** — it never promotes,
   dispatches, or merges.

## Notes
- **Foreground/interactive only** — a background `/loopd:dispatch` tick can't prompt you; it
  parks questions on the 🔴 board, and you clear them here (or with `answer.sh` in a terminal).
- Every answer is committed and pushed by `answer.sh` as you give it; there is nothing left
  to commit.
- No customer PII in answers written to task docs — and note `answered_questions`
  **keeps them for the life of the repo**, so an answer you would not commit is an
  answer to give in person instead.
