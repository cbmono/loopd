# Step 7 — Refresh the knowledge base

**Loaded on demand.** The tick reads this file only when `tick-delta.sh digest` names
it on its `steps:` line (`project-manager.md` → "Step files"). Every rule in the core
prompt still binds here — both authority gates, the ownership gate, the UNKNOWN rule.

7. **Refresh the knowledge base.** If this tick reflected one or more merges (or a
   task reached `done`) whose work produced durable, reusable knowledge, dispatch the
   `cataloguer` (subagent) to capture a `Finding` only when a later task would plausibly hit the same problem /
   update the `Service` catalog / add or update a `Runbook` (`loopd:cataloguer`), and link
   the `Finding`s from the relevant task doc. **Skip this refresh**
   if neither a merge nor a `done` task happened this tick, or the work is trivial —
   the sweep below has its own trigger and is not skipped with it.
   **Throttle: at most one `cataloguer` dispatch per TICK, across every step that can
   dispatch one** — step 6(a)'s closeout pass, this refresh and the KB sweep below are the
   three, and a tick that reflects the final merge *and* receives a close approval
   satisfies both. If step
   6 already dispatched one, dispatch none here and fold this refresh into that one's
   brief. Two cataloguers write `knowledge/` concurrently and take two slots off the cap.
   Read-only on product repos, writes only to `knowledge/`; counts toward the
   concurrency cap.

   **The papercuts pass is the other reason to dispatch one, and it runs on a cadence
   rather than on a merge.** Ask once per tick, and only act when it says DUE:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/papercuts.sh due   # exit 0 = due (unprocessed entries, last pass >= 7 days)
   ```

   Exit 1 is silence: no line in the report, no dispatch. Exit 0 ⇒ brief the cataloguer
   for the papercuts pass too (`cataloguer` step 5), inside the same one-dispatch throttle.
   It returns one proposal per surface, each tagged `plugin` or `instance` by
   `papercuts.sh report`, and **you** route each: an instance-owned surface becomes a
   `draft` task in its owning project; a loopd plugin surface is written to
   `.loopd/upstream-proposals.md` instead. A draft is never `ready`, the human promotes. A
   plugin row is `papercuts.sh propose --surface <s> --edit "<the cataloguer's concrete
   edit>"`, or `dismiss --surface <s> --reason "<why>"` for a surface that no longer
   reproduces; commit the file with `commit-as.sh` like any other path. Only then run
   `papercuts.sh pass`, which refuses and names the surfaces while a plugin surface still
   has no row. `pass` checks only the plugin side; the drafts are your duty.

   **The KB sweep is the third reason, and the only one that fires when NOTHING merged.**
   A tick that dispatched no role agent is the cheapest session there is to spend on a
   `knowledge/` that no longer checks out — defects arriving by hand or by an old seed port
   are on nobody's reflect path, so without this they wait for a human to notice. Ask once,
   **after step 3 has finished dispatching**, so the counts are final:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/kb-sweep-due.sh --dispatched <spawned this tick> \
     --in-flight <still running> [--cataloguer-in-flight]   # exit 0 = due
   ```

   Give that call a Bash `timeout` of 300000 so the tool never backgrounds it: you hold no
   Monitor and foreground sleep is blocked, so a backgrounded probe is one you cannot wait
   for. A probe that still did not answer closes the sweep UNKNOWN. An unchanged
   `knowledge/` answers from the last walk's stamp (`cached, stamp <time>`); a walk that
   found errors is re-walked only after `kbSweepIntervalHours` (absent ⇒ 24).

   Exit 0 ⇒ it prints the trigger line and the ERROR list; dispatch `loopd:cataloguer`
   with **that output pasted into the brief verbatim**, inside the same one-dispatch
   throttle. Exit 1 is silence: no line in the report, no dispatch — unless it printed a
   `KB SWEEP CACHED:` line, the open error count inside the interval: report that one line,
   still no dispatch. Exit 2 could not answer
   — report its line and dispatch nothing. Never re-derive the answer by running
   `build-kb-index.sh --check` yourself: the script is the one place the four conditions
   (idle, errors, no cataloguer in flight, a slot under `maxAgentsInFlight`) are decided
   (`docs/pm-design.md#step-7`).
   A zero-delta IDLE tick (step 0.9) skips steps 1-7 and therefore skips this too — which
   is correct: the errors arrived by a change, and a change is a `DELTA`.

   **The brief for this trigger is fixed, and every clause of it is load-bearing:**

   > Fix each error **at the source frontmatter**. Never hand-edit `knowledge/index.md` —
   > it is derived — and **never delete a `Finding`**: one that is wrong is superseded
   > (`cataloguer` step 3), not removed. Then regenerate the index and re-check to **0
   > errors**. **Warnings are reported, not chased.** One commit, as the `cataloguer`.

   **The stale list rides along with a cataloguer this tick already dispatches, and is
   never a reason to dispatch one.** Only when one of this step's reasons (or step 6's) is
   sending a cataloguer, run once and paste its output into that one brief:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/kb-stale.sh   # exit 0 = a list · 1 = nothing listed · 2 = could not run
   ```

   It names each Service and Runbook whose code has `kbStaleCommits` (absent ⇒ 20) commits
   since its `timestamp:`, and UNKNOWN for one it cannot measure. Exit 1 or 2 adds nothing to
   the brief. A non-empty list with no cataloguer going out dispatches nothing.


<!-- end of step 7 -->
