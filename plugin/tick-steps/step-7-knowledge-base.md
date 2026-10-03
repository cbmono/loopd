# Step 7 — Refresh the knowledge base

**Loaded on demand.** The tick reads this file only when `tick-delta.sh digest` names
it on its `steps:` line (`project-manager.md` → "Step files"). Every rule in the core
prompt still binds here — both authority gates, the ownership gate, the UNKNOWN rule.

7. **Refresh the knowledge base.** If this tick reflected one or more merges (or a
   task reached `done`) whose work produced durable, reusable knowledge, dispatch the
   `cataloguer` (subagent) to capture `Finding`s / update the `Service` catalog / add
   or update a `Runbook` (`loopd:cataloguer`), and link the `Finding`s from the
   relevant task doc. **Skip this refresh**
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

   Exit 0 ⇒ brief the cataloguer for the papercuts pass too (`cataloguer` step 5), inside
   the same one-dispatch throttle. It returns one proposal per surface; **you** create each
   as a `draft` task in the project that owns the surface — never `ready`, the human
   promotes — and only then run `papercuts.sh pass` to mark the entries processed. Exit 1
   is silence: no line in the report, no dispatch.

   **The KB sweep is the third reason, and the only one that fires when NOTHING merged.**
   A tick that dispatched no role agent is the cheapest session there is to spend on a
   `knowledge/` that no longer checks out — defects arriving by hand or by an old seed port
   are on nobody's reflect path, so without this they wait for a human to notice. Ask once,
   **after step 3 has finished dispatching**, so the counts are final:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/kb-sweep-due.sh --dispatched <spawned this tick> \
     --in-flight <still running> [--cataloguer-in-flight]   # exit 0 = due
   ```

   Exit 0 ⇒ it prints the trigger line and the ERROR list; dispatch `loopd:cataloguer`
   with **that output pasted into the brief verbatim**, inside the same one-dispatch
   throttle. Exit 1 is silence: no line in the report, no dispatch. Exit 2 could not answer
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

   **The reflection pass is the fourth reason, and the only one that dispatches nobody.**
   It is a SCRIPT, not an agent: it proposes merges and supersessions and writes none of
   them, so byte-identity over `knowledge/` is something a plain harness can assert rather
   than something an agent holding `Write` promises. Ask once per tick:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/kb-propose.sh --proposer "<the instance's proposer>"   # exit 0 = a report was written
   ```

   It runs the archive sweep first, with or without a proposer: a current, machine-written
   Finding past every qualifier `scripts/kb-usage.sh sweep` prints becomes a
   `status=archived` proposal. Exit 0 ⇒ it has already written the report as a `draft`
   task; print its line and do **nothing else** — step 8 renders the row from that
   document like any other. Exit 1 is silence (nothing to archive and no proposer
   configured, nothing to propose, or a report still waiting on the human). Exit 2 could
   not answer — report its line.
   **Never apply a report from here, and never promote one.** `/loopd:kb-apply` is the
   only path that writes `knowledge/` from a report, a human types it, and a report is
   declined by cancelling it — not by promoting it to `ready`, which would dispatch an
   agent and make a second apply path.


<!-- end of step 7 -->
