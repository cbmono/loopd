---
name: handoff
description: Transfer ownership of a task or project to another human — with the context that makes the transfer real
argument-hint: "<task-or-project path> <github-login> [one line of context]"
disable-model-invocation: true
---

Ownership transfer as a first-class operation: reassign, record why, and hand the new
owner the context — so a project outlives whoever started it.

## Preconditions

Run from a control-panel instance root. Resolve the first argument to exactly one
task (`projects/*/tasks/*.md`) or project (`projects/*/project.md`); ambiguity lists
candidates and stops. The second argument is the new owner's **GitHub login**. If the
tracked `instance.config.json` has a `people` map and the login is not in it, say so
and continue anyway — the map gates commit authorship, not ownership — but recommend
adding them before their clone runs a loop.

## What a handoff changes — and what it never touches

1. **Set `owner: <login>`** in the document's frontmatter (add or replace). Handing
   off a project covers its tasks by the resolution chain (task `owner:` → project
   `owner:` → `defaultOwner`); warn about any task carrying its own conflicting
   `owner:` and list them rather than silently overriding.
2. **Record the handoff** in the document's `# Notes`:
   `Handoff <ISO date>: <old-owner-or-unowned> → <login>. <the context line>` —
   never invent the context; if none was given and none is obvious from the
   document, ask.
3. **An `in-progress` task bound to the old owner's machine is named, not handed over
   silently.** Its `worktree:`, `branch:` and `session:` point at a checkout and a
   detached session that exist only there; the new owner's clone can neither observe
   nor settle that session, so its tick reports the task as parked with no process
   (measured 2026-10-05: a handed-over task pinned a worktree under the old owner's
   home directory).
   List each such task with the two routes — the old owner finishes it, or releases
   it (`status: ready`, drop `worktree:`/`branch:`/`session:`) and pushes — and
   change nothing on it yourself: status is not yours (rule 5).
4. **Assemble the new owner's context, cheaply**: the task/project's open questions
   (verbatim), its PRs with state, its recorded `worktree:`/`branch:` if any, and
   the 1–3 `knowledge/` Findings the document links. Put that summary in your
   report — it is the handoff.
5. **Touch nothing else.** Status is not yours (a handoff is not a promotion, a
   block, or a close), `AWAITING.md` is derived, and dispatch decisions belong to
   the loops. Ownership gates dispatch only — either human may still promote.

## Commit

By explicit path, as the human's own act:
`${CLAUDE_PLUGIN_ROOT}/scripts/commit-as.sh human 'chore: hand <slug> to <login>' --stage -- <paths...>` —
strip `$`, backticks, quotes and backslashes from any argument-derived text and pass
the message single-quoted, exactly as `/capture` does. If the bundle has a remote,
pull `--rebase` (never `--autostash`) and push, so the other human's clone sees the
transfer on their next tick.

Report: what changed owner, the handoff line as written, and the context summary for
the new owner — ready to paste into a message to them.
