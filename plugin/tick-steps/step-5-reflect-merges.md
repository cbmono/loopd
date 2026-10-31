# Step 5 — Reflect merges

**Loaded on demand.** The tick reads this file only when `tick-delta.sh digest` names
it on its `steps:` line (`project-manager.md` → "Step files"). Every rule in the core
prompt still binds here — both authority gates, the ownership gate, the UNKNOWN rule.

5. **Reflect merges.** For `in-review` tasks, check the PR(s): when **all** of a
   task's PRs are **merged** → `status: done`, then **reclaim that one task's worktree**
   with `${CLAUDE_PLUGIN_ROOT}/scripts/reclaim-worktree.sh <task-path>` (below).
   Never remove a path by hand, never use `prune-worktrees.sh` for it — that one still
   deletes nothing — and never widen either into a sweep (`docs/pm-design.md#step-5` has
   the incident). Then re-evaluate dependents. If review
   **requests changes** → back to `in-progress`. If a PR is **closed unmerged** and
   abandoned → `cancelled` (or `blocked`) with a note. A multi-PR task stays
   `in-review` until all merge. **`done` and `cancelled` are the two writes a task's
   `open_caveats:` holds** (step 0): a non-empty list means clear it with evidence first,
   in its own edit, or leave the status alone and report it.

   **Never merge unless the project delegates it.** By default surface each verified,
   green PR as a 🔴 *merge* item. **Only** where the owning project's `autonomy`
   delegates merging **and** `AUTONOMY.md` defines that mode may you merge, and then
   strictly on the deterministic preconditions that file lists — including its
   **preflight**. Never merge on your reading of PR prose. `AUTONOMY.md` absent ⇒
   surface, don't merge.

   **A preview approval is a human decision, so it is stamped like one.** Where a task's
   deliverable is something a human LOOKS at, the agent opens a draft PR, records a
   `preview: <url>` line under `# Notes` and stops at `in-review`; a draft is never
   merge-eligible, so report the URL in the tick summary and never queue it as a merge.
   When the human approves it — in-session, or by marking the draft ready for review —
   append one
   `# Notes` line, `preview approved <ISO 8601> by <login>` from
   `${CLAUDE_PLUGIN_ROOT}/scripts/decision-stamp.sh --self`, then let the PR through the
   ordinary gate unchanged. **The same form and the same resolver as every other stamp**
   (`SCHEMA.md` → "Decisions name the human"): the approval before the review is the one
   decision that otherwise leaves no record anywhere, because marking a draft ready
   touches no bundle file.

   **ONE script removes a worktree, and only on the terminal case.**
   `${CLAUDE_PLUGIN_ROOT}/scripts/reclaim-worktree.sh <task-path>` — one task per call,
   driven by the task's own `worktree:`/`branch:`/`pr:` record, never by a scan.
   **Exit 0 only when that task is `done` AND every URL in its `pr:` has MERGED**; run it
   for each task you just moved to `done`, and report what it removed. **Stop the task's
   own session first, whatever state it is in**:
   `${CLAUDE_PLUGIN_ROOT}/scripts/session-handoff.sh <task-path>` runs
   `claude stop <short>` on a `done` or `cancelled` task's recorded session unless it has
   already ended — `blocked` on a prompt or not, recorded or not — then reclaim. A done
   task's session left for the human to stop is the nag this removes (measured
   2026-10-21). **A `needs` it still holds is filed first** — jobs meant for after the merge
   ("merge #559, then run the backfill") — so its `👉 do` row outlives the `done` until the
   human answers it; say so in the tick report. That one recorded session only: never a
   process the task does not record, never `claude rm`. **Exit 4 is a RETRY**: every live process in the tree is that
   session's own, which can outlive the stop by a moment — no `# Notes` line, no
   `AWAITING.md` row, nothing for the human. **Exit 1 is a
   REFUSAL** — a PR CLOSED-UNMERGED, an empty `pr:`, a dirty tree, an unpushed commit, an
   ignored `.env`, a detached HEAD, a live process the session does not own. Record it,
   and an exit 2, on the task as one `# Notes` line, `worktree retained: <reason>`, and
   never retry around it. Exit 3 is nothing to do.

   **Then stop the dead sessions no task owns — once, every tick that reads this step.**
   `${CLAUDE_PLUGIN_ROOT}/scripts/session-sweep.sh <bundle-root>` runs `claude stop` on what
   `agent-sessions.sh dead-ids` selects: no live pid on the row or in the daemon roster, no
   task records it, a `cwd` under this bundle's root or a task's `worktree:` (never the shared
   worktree root, never a row with no `cwd`), older than 10 minutes — 24 hours when `blocked`
   — and at most 20 a tick. Carry every `stopped <short> (<age>)` and `stop-failed <short>`
   line it prints onto your `log.md` close summary; a `stop-failed` is not retried this tick
   and never stopped by hand. Exit 2 stopped nothing: one line in the tick report.

   **The retry is the one time step 5 revisits a `done` task.** A `done` task whose
   recorded `worktree:` is still on disk and whose `# Notes` hold no `worktree retained:`
   line gets the same stop-then-reclaim on every tick — `tick-delta.sh` names this step
   for it and never calls that tick IDLE — until reclaim exits 0 or 3, or a 1 or 2
   writes the note.

   **`${CLAUDE_PLUGIN_ROOT}/scripts/prune-worktrees.sh` is unchanged and still report-only**,
   and it is still the only thing that sees a worktree no task record names: it classifies
   and prints the exact `git worktree remove` commands. Surface its `REMOVABLE` and
   `RECLAIMABLE` sets as a human job; never run the printed commands yourself. **Run it at
   most once per tick, and only when you have no role agents in flight** — its
   `PRUNE_ACTIVE_MINUTES` mtime veto (default 120) is a backstop for the pruner, not the
   guard; your in-flight count is the guard. **The veto does not apply to
   `reclaim-worktree.sh`**: step 5 runs for `in-review` tasks, so a fast merge is always
   reflected inside the window and only the retry above revisits a `done` task — the
   live-process check replaces it there.

   **A merge is not a deploy where the repo deploys by hand.** For each task you move to
   `done`, run `${CLAUDE_PLUGIN_ROOT}/scripts/reflect-deploy.sh <task-path>`. On `manual`
   (`deploy:` on the task, else its Service doc — `SCHEMA.md` → Service) it prints
   `deploy-owed Q<n>` after writing one `merged, not deployed` `# Notes` line and one
   `Q<n>: do: deploy …` entry with its block: report the task as merged, NOT shipped. Its
   `👉 do` row stays in `AWAITING.md` until the human answers ` --- done`, and that answer is
   the deploy's record — it is no hand-off, so nothing is ever resumed for it. Exit 1
   (`auto`, `n/a`, `already Q<n>`) leaves the file alone. Exit 3 (`deploy-unknown Q<n>`) fails
   toward manual: the same write, worded `deploy UNKNOWN`, so the row is never lost — report
   it as `deploy UNKNOWN`, never "shipped". Exit 2 leaves the file untouched: report it, and
   re-run the script by hand once fixed — it writes nothing twice.

   **Sum what that task cost, against the PR(s) that merged.** For each task you move to
   `done`, once:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/agent-usage.sh total <task-path> --pr <merged-pr-url> [--pr …]
   ```

   It adds up that task's own `* DISPATCH` lines and appends one `* TOTAL` line to
   `# Notes`. **A task with no dispatch lines records `usage UNKNOWN`, never zero** — an
   unmeasured task and a free one are not the same fact. Exit 1 means a `* TOTAL` line is
   already there; leave it alone.

   **Check the citations you are reflecting, and store them.** For each task you move to
   `done`, run
   `${CLAUDE_PLUGIN_ROOT}/scripts/kb-usage.sh record --source <id> --text-file <f> --brief <slugs>`
   over its `# Result` section and over each merged PR body, with `<slugs>` the output of
   `${CLAUDE_PLUGIN_ROOT}/scripts/kb-select.sh --recorded <task-path>` passed verbatim — the
   set step 3 recorded at dispatch, never a re-run of the selector, which reads today's KB
   (exit 1: dispatched before the record existed, so pass `none`) — `<id>` is
   `<task-slug>.result` or `<repo>-pr-<n>`, so a re-run rewrites the same record instead
   of counting it twice. It runs
   `${CLAUDE_PLUGIN_ROOT}/scripts/cite-check.sh --text-file` and passes its report and exit
   code through unchanged; that record is the only usage signal the archive sweep in
   step 7 has, so a skipped run is a citation the KB never sees. Anything dropped (exit 3, or exit 1 where a citing line lost every id) is
   **recorded as a `# Notes` line** naming the id and its verdict — `UNREAD` (a real doc
   nobody read) or `FABRICATED` (no such doc) — and exit 1 also goes in the tick report.
   It never changes the reflect verdict: a merged PR is merged. `CONVENTIONS.md` → cite
   knowledge as `[[finding-slug]]`.


<!-- end of step 5 -->
