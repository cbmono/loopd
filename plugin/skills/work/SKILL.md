---
name: work
description: Work one OKF task in THIS session — native Claude Code flow, with the bundle's ledger kept for you
argument-hint: "<task path, or enough of a title to find it>"
disable-model-invocation: true
---

Work **one task** from this bundle in the current session — the solo alternative to
dispatching a background role agent. Same rules as any role agent; the difference is
only where the work happens.

## Preconditions

Run from a control-panel instance root (`instance.config.json` in the cwd,
`SCHEMA.md` at the resolved schema path — `AB_SCHEMA`; the root on a legacy layout — checked
with exactly `ls instance.config.json "$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/bundle-paths.sh AB_SCHEMA)" 2>/dev/null || ls instance.config.json SCHEMA.md`). Resolve `$ARGUMENTS` to exactly one task under `projects/*/tasks/`; if it
matches none or several, list the candidates and stop. The task must be `ready` or
`in-progress` — a `draft` is not yours to work (say so: the human promotes it first),
and a `done`/`cancelled` task is finished.

## Set up — the same record a dispatch would leave

1. Read the task document in full, its project's `project.md`, and — for a `build`
   task — `CONVENTIONS.md` before your first write in the target repo.
2. If the task is `ready`: set `status: in-progress` and, for a build task, record
   `worktree:` (absolute) and `branch:` on the task — **both, or neither** — before
   any target-repo work, so an interrupted session still leaves the record the
   reclaim machinery depends on. Commit that edit by explicit path:
   `${CLAUDE_PLUGIN_ROOT}/scripts/commit-as.sh human 'chore: start <task-id> in-session' --stage -- <task-path>`.
3. For a **build** task: create the worktree explicitly —
   `git worktree add <worktreeRoot>/<slug> -b <branch> origin/<default-branch>`
   (detect the default branch; `worktreeRoot` from `instance.config.json`, absent ⇒
   `<reposRoot>/_wt`). Use a private package store if the repo shares one. For a
   **research** task: work the deliverables under the project folder directly.

## Work it — the invariants hold here exactly as they do for agents

- **Never merge. Never work on the default branch. No customer PII anywhere. Never
  echo or log secrets.** A target-repo commit keeps its `Co-Authored-By: Claude` trailer
  — resolve this instance's setting once with
  `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-config.sh commitAttribution` (absent ⇒ `claude`;
  `none` ⇒ no trailer and no session URL).
- Verify against the task's `acceptance_criteria`; the PR body carries them as a
  `✓`/`✗` table — tick only what you actually verified, and run
  `${CLAUDE_PLUGIN_ROOT}/scripts/pr-body-clearance.sh --body-file <draft>` before posting.
- Push early; open the PR against the default branch with the task id in the title,
  tagged per `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-config.sh ticketPrefix` (absent ⇒
  no tag; `ABC` ⇒ `[ABC-<n>]`, or `[ABC-0]` with no ticket).
- Hit a genuine ambiguity ⇒ add a numbered entry to the task's `open_questions` and
  say so — in-session the human may answer immediately, which you then fold in and
  MOVE to `answered_questions` (verbatim, timestamped, stamped `by <login>`) per the
  bundle rules.

## Close the loop — the part solo work usually forgets

When the PR is open (or the deliverable drafted): write the PR URL into the task's
`pr:` list, a short `# Result`, set `status: in-review`, and commit those bundle
edits by explicit path (as `human`). Then stop — **review and merge are not this
skill's business**: the independent verifier and the human's merge gate apply to
in-session work exactly as to dispatched work. Report: what was built, the PR link,
what remains for review.
