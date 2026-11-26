# Step 6 — Close completed projects

**Loaded on demand.** The tick reads this file only when `tick-delta.sh digest` names
it on its `steps:` line (`project-manager.md` → "Step files"). Every rule in the core
prompt still binds here — both authority gates, the ownership gate, the UNKNOWN rule.

6. **Close completed projects (propose only — human-gated).** For each project the digest
   names on a `close due <project.md>` line — its tasks **all** terminal (`done`/`cancelled`)
   and `closeAfterDays` (5 when absent) past since the last went terminal (`SCHEMA.md` →
   "Closing a finished project after a delay") — and only those, on a digest fallback run
   `${CLAUDE_PLUGIN_ROOT}/scripts/close-delay.sh <slug>` per all-terminal project and act
   only on a `due` answer. If it holds no unanswered `Q<n>: do:`
   entry (a deploy or a hand-off — its row outlives `done`), do **not** close it yourself —
   surface it as a 🔴 *Awaiting you* item. Only on the human's OK (in-session or via
   `/close-project <slug>`) run closeout, in order (`SCHEMA.md` "Project & objective
   completion"): (a) dispatch the `loopd:cataloguer` for a final consolidation pass (counts
   toward the cap) — and it is THE cataloguer for this tick: step 7's throttle is
   tick-wide, not step-7-local, so brief this one to cover the closeout consolidation
   AND anything this tick's merges produced; for a research project, graduate the
   chosen `deliverables` into `knowledge/`; (b) prepend a dated **Project closed** entry to `.loopd/log.md`,
   stamped `by <login>` from `${CLAUDE_PLUGIN_ROOT}/scripts/decision-stamp.sh --self`
   exactly as a promotion and a preview approval are — closing is the human's OK and the
   entry is the only place that OK is ever written down — naming the project, its merged PR(s) as `[<repo>#<n>](url)`, the `Finding`(s)
   produced, and the removing commit SHA; (c) set `project.md` `status: done`, drop it
   from the active `## Projects` list in the ROOT `index.md`, refresh
   `projects/<slug>/index.md` when the project is retained, and update its objective —
   when **all** of an objective's projects are terminal, likewise **propose**
   `objective status: achieved`; (d) run `${CLAUDE_PLUGIN_ROOT}/scripts/close-project-folder.sh <slug>
   --apply` — never `git rm` or `rm` the folder yourself. It reads `retain:` and
   either removes the folder or keeps it pruned; it prints a `.loopd/log.md fragment` — put
   that in (b)'s entry. Then stage the edits from (b) and (c) by explicit path — plus
   `projects/<slug>` itself when retained, and `projects/CLOSED.md` when the script says it
   staged it — and commit in one go via
   `${CLAUDE_PLUGIN_ROOT}/scripts/commit-as.sh project-manager "chore: close <slug> project" --
   projects/<slug> .loopd/log.md objectives/<objective>.md <kb-path>...`. (The ROOT
   `index.md` is edited but **not** staged — derived and gitignored; a retained
   project's OWN `index.md` is the exception, step 8.) There is **no `archive/`** —
   git history + the KB are the record, except where `retain: true` says the folder IS
   the record. Closing is never autonomous. A project that is still running is asked
   whether to continue by step 8's `continue` row (`SCHEMA.md` → "The continue
   checkpoint"), never by this step.

<!-- end of step 6 -->
