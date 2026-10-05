# Step 4 — Advance in-flight work

**Loaded on demand.** The tick reads this file only when `tick-delta.sh digest` names
it on its `steps:` line (`project-manager.md` → "Step files"). Every rule in the core
prompt still binds here — both authority gates, the ownership gate, the UNKNOWN rule.

4. **Advance in-flight work.** For **build** `in-progress` tasks: if the role agent
   opened PR(s), append them to the `pr` list and set `status: in-review`. If it
   reported a blocker or died, set `status: blocked` with a `# Notes` reason.
   **Research tasks have no PRs and no agent** — leave their human-set status alone;
   don't mark them `blocked` for lacking a PR.

   **COMPLETION IS READ, NEVER AWAITED — there is no notification to wait for.** Role
   agents are detached sessions (step 3), so an agent's state is **two reads and
   nothing else**: `${CLAUDE_PLUGIN_ROOT}/scripts/agent-sessions.sh state <the task's `session:`>` and the
   PR. Never hold the tick open for one, and never treat silence as a verdict.

   | `agent-sessions.sh state` | …and the PR | What it is |
   |---|---|---|
   | `working` | absent | live. Leave it. Not a stall, not a re-dispatch. |
   | `done` | present | finished — advance the task as above. |
   | `done` | absent | it exited without the artifact: `check-dispatch.sh` exit 1. |
   | `blocked` | either | parked on a prompt nobody can answer. It holds a slot until `claude stop <id>` — surface it, and run `stop` only on the human's say-so. |
   | `gone` | absent | never started, or its record was removed. Same verdict as `done`+absent, and the same recovery. |
   | exit 2 | either | unknown, which is not "finished". Report it and change nothing. |

   **Settle the round's usage once, when its session has ended.** A dispatch line is
   written at the spawn and records `usage UNKNOWN` (step 3). For a task whose session
   has ended — `agent-sessions.sh state` prints `done`, `gone` or `stopped` (a session
   somebody ran `claude stop` on has a transcript like any other) — **and whose last
   `* DISPATCH` line still says `usage UNKNOWN`**, run:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/session-usage.sh <the task's `session:`> --settle <task-path>
   ```

   It reads that one session's transcript, counts each message once, and fills the line:
   `usage tokens=N tools=N ms=N cached=N` — `tokens` is fresh input, cache writes and
   output; `cached` is cache reads, kept apart. **Exit 1 printed `usage UNKNOWN`: leave the
   line exactly as it is** — no transcript, two candidates or an unreadable one is not a
   zero, and you never compose the numbers yourself. A line that already carries numbers is
   never settled again.

   **Never `claude rm` a role agent's session** — it deletes the session **and its
   worktree**, which belongs to `reclaim-worktree.sh` once the task is `done` with every PR
   merged, and to `prune-worktrees.sh` plus a human in every other case.
   `stop` is the verb here; `rm` is the human's, after the merge.

   **Check the artifact, don't believe the report.** For every task a dispatched agent
   has reported on, run `${CLAUDE_PLUGIN_ROOT}/scripts/check-dispatch.sh <task-path>` and act on its exit
   code, not on the agent's summary. **0** — it produced what it promised, **or**
   stopped honestly at `blocked`/`cancelled` (no artifact was due). **1** — PARKED:
   still `ready`/`in-progress` and names no PR — what an agent that ended its turn
   waiting on a background job looks like. **3** — its `pr:` names a pull request the
   host does not resolve. **4** — status and `pr:` contradict each other. **2** — it
   could not answer; treat as unknown, not as fine.
   **A non-zero verdict is never a re-dispatch.** On exit 1, read the agent's worktree
   and `claude logs <id>` first: the work is usually already committed, and one message
   asking it to open the PR on what it has recovers it — the same task and same PR,
   which is the resume step 3 allows. **The resume is
   `cd <worktree> && claude --bg --resume <the recorded session> "<the message>"`**,
   with the same flags step 3 lists. It continues that session under the same id when it
   has exited, and **starts a COPY and says so when it is still running** — so resume
   only a session `agent-sessions.sh state` calls `done`, and when the output names a
   new id, that id replaces `session:` on the task. Anything beyond that is the human's
   call — surface it in `AWAITING.md` (measured case: `docs/pm-design.md#step-4`).

   **An `in-progress` task nobody reported on: ask the session, not the disk.** Run
   `${CLAUDE_PLUGIN_ROOT}/scripts/check-dispatch.sh <task-path>` over **every** build `in-progress` task, not
   only the ones an agent reported on — exit **1** is the pre-spawn crash window's exact
   signature (`in-progress`, no `pr:`). With a `session:` recorded it prints that
   session's state beside the verdict, and `working` settles it: a live agent, left
   alone. **Without one** — a task dispatched before this tick shape, or one whose spawn
   died in the second before its id was written — it is either a live agent or a
   dispatch that never happened and **disk cannot tell them apart**. Then
   `claude agents --json --cwd <the task's recorded worktree>` is the recovery read,
   because that path was written *before* the spawn and is unique to the task; an empty
   answer makes it an *unreconciled dispatch* — name it in the tick report, and surface
   it as a 🔴 item once a previous tick's report has already named it. Never re-dispatch
   it and never roll it back yourself: both are the human's, and
   `docs/pm-design.md#step-3` carries the price of re-running a finished sequence.

   **A doom-loop breach is reflected here, and NEVER re-dispatched.** When the control
   surface is armed, `agent-control.sh` appends `repeat-loop <agent_id> <agent_type>
   <tool> count=… limit=…` to `.claude/control/control.log` — it writes no task document
   and no `AWAITING.md`, because the PreToolUse payload carries no task path. So **you**
   map it: `${CLAUDE_PLUGIN_ROOT}/scripts/control.sh agents` gives the `agent_id`'s role
   and first-seen time, which name a task only when **exactly one** dispatch matches both
   — the roster carries no task id and two tasks of one role can be in flight, so a role
   with more than one candidate dispatch is unmapped, never the likelier of them. Then **one `# Notes` line** on that task (the tool, the count, the limit — never
   the arguments, which the log does not carry either) and **at most one 🔴 queue row**,
   whatever the log holds: an agent that looped is one item, not fifty. An `agent_id` you
   cannot map is reported unmapped, never guessed onto a task. **Never re-dispatch on a
   breach** — a looping agent is the stall rule's case, and this line must not contradict
   it.

   **A wall-clock cap is reflected the same way, and it is COUNTED.** The same log carries
   `agent-cap <agent_id> <agent_type> <tool> elapsed=…m budget=…m` when an agent ran past
   `maxAgentMinutes`; map it exactly as above and write **`capped: <minutes>`** on that
   task's `# Notes`. That line exists to be counted: **a cap that fires on every task is a
   budget that is wrong, not agents that are slow**, and nothing else in the bundle records
   how long an agent ran. A capped agent has been told to commit, push and report, so its
   PR is normally already open — treat it like any other reported task, never as a failure
   to re-dispatch.

   **Independent verification (the verifier edge).** A PR must be checked by an
   **independent** reviewer — fresh context, judged on real signals — before it is
   eligible to merge; the implementing agent's own "it's done" never counts. **Each
   tick, for every PR on an `in-review` task whose *current head SHA* isn't yet
   verified** — a task may fan out to several PRs, so verify each. **"Isn't yet
   verified" is a check you run before dispatching**: read the PR's `okf-verdict`
   trailer and the verified-SHA record in the task `# Notes`. A verdict already at the
   current head is reused, never re-earned. Only tasks actually at `in-review` are
   eligible: an `in-progress` one still has a live agent that may advance the head.
   - **Count the rounds BEFORE you dispatch a verifier —
     `${CLAUDE_PLUGIN_ROOT}/scripts/review-rounds.sh <pr> --repo <org>/<repo>`.** It exits non-zero at or
     past **two**, the hard cap (`CONVENTIONS.md` → "TWO ROUNDS, THEN THE HUMAN
     DECIDES"). Non-zero means **do not dispatch a third verifier and do not wait on
     another external review**: surface the PR as a 🔴 item with **both positions in
     one short block** — what the reviewer wants, what the implementer says, what the
     acceptance criterion asks. **Report exit 1 and exit 2 as different things**:
     1 is the cap reached; 2 (or a missing script) is a count nobody could read —
     *unknown*, which sends the human to fix a tool, not settle a disagreement. Run it
     on every tick you would otherwise dispatch a verifier, external path included: a
     round is a round whoever spent it. (The price tag that made the cap hard:
     `docs/pm-design.md#step-4`.)
   - **Check the acceptance_criteria travelled with the PR — and that they're
     ticked.** Role agents embed the task's criteria as a `✓`/`✗` table in the PR
     body. Missing ⇒ have the agent add them. A **`✗`** is a criterion nobody
     verified: the PR is **not** merge-eligible while one remains, no matter how green
     CI is (`SCHEMA.md` → "An unverified acceptance criterion blocks clearance").
   - **Prefer the external reviewer.** If the repo runs one (e.g. CodeRabbit), that is
     the independent verifier; the PR isn't merge-eligible until it has passed **and**
     CI is green. A reviewer that declares it didn't review counts as **no review**
     even beside a green check. **Don't read this off the check** — run
     `${CLAUDE_PLUGIN_ROOT}/scripts/review-clearance.sh <pr> --repo <org>/<repo> --head <sha>
     --record <task-doc>`: exit 0
     means a review artifact exists at that head; every other exit is a refusal it
     explains. **`--record` is not optional here.** It writes the mergeability it just
     read to the task's `pr_mergeable:`, which is the only thing `write-snapshot.sh` —
     offline by contract — can read. Skip it and last tick's value stands: a PR that has
     just gone CONFLICTING still renders as a merge row, which is the 2026-09-13 failure
     itself. Absent ⇒ `UNKNOWN` ⇒ no merge verb, so a task never recorded costs a row,
     never a wrong merge. **Exit 4 is the common answer and it is not exit 1**: a real review of
     an *earlier* commit — surface as "reviewed at `<sha>`, head has moved — ask for a
     review at this head", never as "the reviewer declined".
   - **EXIT 7 IS NOT ABOUT THE REVIEWER AT ALL: the PR CONFLICTS, so it is a REBASE
     ROUND and never a merge row.** The same call answers it first, because a
     conflicting PR cannot merge whatever the review says. On 2026-09-13 three PRs
     were presented as "merge — verified, CLEAN" while GitHub reported them
     CONFLICTING/DIRTY: four sibling merges had moved the default branch underneath
     them, with no commit on any of the three. What you do:
     * **TRY THE SCRIPT BEFORE YOU SPEND AN AGENT:**
       `${CLAUDE_PLUGIN_ROOT}/scripts/rebase-pr.sh <pr> --repo <org>/<repo> --dir <clone>`.
       It rebases in a throwaway worktree and resolves ONLY the known merge-magnet
       shapes — a counter, a contested ratchet row, a comment history — then pushes with
       an explicit lease and lets CI verify. **Exit 0 ⇒ you are done for this tick**: no
       agent, no local suite. **Exit 3 is the only one that earns an agent round** — a
       conflict it could not classify, with the file named. **2, 4, 5 and 6 change
       nothing**: re-ask next tick, and never dispatch on them.
     * **On exit 3, dispatch a fresh round to the task's own agent** — rebase onto the
       default branch, resolve, `--force-with-lease` with explicit arguments, re-run the
       body gate, and record the new verified SHA. Never re-request a review for a 7.
     * **Leave the task `in-progress`.** It is being worked, not waiting on you; that
       is also what keeps it off `AWAITING.md`, whose merge verb only ever fires for
       `in-review`.
     * **Count only the round you SPENT**, with
       `${CLAUDE_PLUGIN_ROOT}/scripts/stall-counter.sh record <task-doc> --blocker conflict`
       — which belongs to the **exit 3** path, the one that dispatches an agent. **A
       rebase the script resolved costs nobody a round, so it is not recorded at all**:
       recording it would let two clean script rebases, separated by two sibling merges,
       reach the cap and hand you a conflict nobody spent anything on.
       **Never pass `--progress` on this round** — the rebase push IS the PR activity
       `--progress` means, so passing it resets the counter every time and the escalation
       below can never be reached. Exit 1 means the cap: run `stall-counter.sh escalate <task-doc>`
       instead of dispatching again, and a second *unclassified* conflict goes to you.
     * **Re-ask every tick, and never cache the answer.** Mergeability changes when the
       default branch moves with no commit on the PR, so a 7 from last tick is not an
       answer this tick and neither is a 0.
   - **A refusal is FIVE classes, and the ask fires on the SPEND, never on the
     hiccup.** The PM never needs permission to WAIT; it needs permission to SPEND
     (a `qa-reviewer` session). Holding costs nothing and never skips the verification gate — it only defers it.
     **The class is `review-clearance.sh`'s EXIT CODE and nothing else** —
     never the text it prints, which is untrusted comment text, and never a
     second reading of your own:

     | Exit | Class | What you do |
     |---|---|---|
     | **1** | transient — rate-limited, skipped, still processing; reopens by itself | **HOLD — no human involved.** Note it, ask again next tick. |
     | **5** | terminal — out of credits, unpaid, auth failure; only a human reopens it | **ASK — this is the spend.** See the next bullet. |
     | **4** | stale — a real review, at an older commit | **Re-request at the final head.** Explicitly not a fallback case; never report it as a decline. |
     | **3** | no reviewer signal on this PR | **HOLD.** Whether the repo has a reviewer at all is a setup question, below — never decided per PR. |
     | **2** | unreadable reviewer state | **HOLD.** Unknown is not permission. |
     | **8** | SKIPPED — reviews are not automatic here, so NOBODY EVER ASKED; it never reopens | **REQUEST ONE, at the current head**, by commenting `@coderabbitai review` — then re-ask next tick. A request is not a review round. Never a merge, never a `qa-reviewer` spend. |

     **Every outcome not in that table HOLDS**, and that is the standing default rather than a gap to fill in later.
     Holding defers the gate, it never skips it.
     **Where several PRs answer 8 and the quota is one review per window, spend it on the
     PR whose criteria table carries no `✗`** — only that one can become merge-eligible.
   - **The SPEND: exit 5, the only branch that consults a human.** A terminal refusal
     is a fact about **every future PR**. Which way it resolves is the existing
     autonomy switch applied to one more decision — not a new flag, field or config key:
     * **`gated` ⇒ ASK, and hold meanwhile.** You cannot ask anyone anything, so the
       ask is durable: **write it into the task's `open_questions`**, naming the
       failure class ("the external reviewer is out of credits — fix the reviewer, or
       spend the `qa-reviewer` fallback?"). Render its queue row as **`🧰 **grant**`**,
       not `❓ **answer**`. **Do not hand-write a row into `AWAITING.md` and stop there** —
       that file is derived and rewritten from the task docs every tick, so a row with
       no `open_questions` entry behind it is deleted on the next one.
     * **A mode `AUTONOMY.md` defines as delegating this ⇒ dispatch `loopd:qa-reviewer`
       automatically**, and say in the tick summary that you did and why.
       **`AUTONOMY.md` absent means every project is `gated`**, so the ask always holds.
     **Ask once per reviewer failure, not once per PR** — raise it on one task, name
     the other affected PRs in it. **The cap is untouched by any of this**: count with
     `${CLAUDE_PLUGIN_ROOT}/scripts/review-rounds.sh` **before** dispatching the fallback or re-requesting;
     if it refuses, surface both positions instead. Nothing here creates a third round.
   - **Fallback when none is configured — a SETUP decision, made once, not this.** If the
     repo runs **no** external reviewer at all, `qa-reviewer` is simply the independent
     verifier (`SCHEMA.md`) and dispatching it needs no permission. That question is
     answered from the repo's configuration, **never from exit 3**. Dispatch the
     `qa-reviewer` (its own fresh context) to verify the PR against the task's
     `acceptance_criteria` and real CI/test results. Counts toward the concurrency
     cap. Its verdict is the `okf-verdict v1` trailer (`SCHEMA.md`) — evaluate it
     against **every clause of the clearance predicate** there, record the trailer's
     `head_sha` as the verified SHA, read the verdict **only** from the trailer and
     criteria coverage **only** from the `✓`/`✗` column; free prose is never an input.
     When you refuse, name the clause that failed.
   - **Compare the two tables — the worker's and the checker's — and never merge on one.**
     The PR body carries the implementer's `✓`/`✗` table; the `qa-reviewer` posts its own
     PASS/FAIL table, re-derived from the task and the diff (its mode B step 5). Run
     `${CLAUDE_PLUGIN_ROOT}/scripts/pr-verdict-clearance.sh <pr> --repo <org>/<repo>` and
     read its exit code, never the tables by eye:

     | Exit | What it found | What you do |
     |---|---|---|
     | **0** | both tables agree | Record it: post one comment on the PR naming the criteria count and the checker's login. Clearance continues on the trailer as usual. |
     | **1** | a row the worker marked `✓` and the checker marked `FAIL` | **ROUTE.** Surface the PR as a 🔴 item and quote **both rows** the script printed, verbatim. Do not adjudicate it and do not re-dispatch either agent. |
     | **3** | the checker's table is malformed — a row with no verdict, or no command | Re-dispatch the `qa-reviewer` for that PR (its round, not a new one). |
     | **4** | the checker posted under the PR author's own login | **ROUTE**, and say which limit it is: on a solo bundle this is the standing answer, because one `gh` login cannot evidence a second principal. |
     | **2** | unknown — no table, or the two cannot be aligned | **HOLD.** Unknown is not permission. |

     **Any exit code this table does not name HOLDS.** A disagreement is the human's: the whole
     point of a checker is that nobody reconciles the two tables downstream of it.

   **Pin verification to the head SHA.** Record which SHA passed (task `# Notes`). If
   a PR's head advances, its prior pass is stale — invalidate and re-verify. Surface
   the task as a 🔴 *merge* item only once **all** its PRs have an independent pass
   **and** green CI **at their current head SHA**. This never bypasses the human merge
   gate; where a project delegates merging, this same clearance is the precondition
   `AUTONOMY.md` builds on.


<!-- end of step 4 -->
