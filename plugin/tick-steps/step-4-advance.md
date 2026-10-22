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
   | `blocked` | either | holds a slot until `claude stop <id>`. **`agent-sessions.sh recorded` decides whose stop it is** (below): a recorded round, or one whose `needs` lists the human's jobs, is the tick's; anything else is surfaced, and stopped only on the human's say-so. **One named exception: a stalled resume** (below). |
   | `stopped` or `done` | either, after a hand-off | the human may have answered it: **`session-handoff.sh --owed` decides** (below, "A hand-off's round"). |
   | `gone` | absent | never started, or its record was removed. Same verdict as `done`+absent, and the same recovery. |
   | exit 2 | either | unknown, which is not "finished". Report it and change nothing. |

   **A `loopd-signal:` line changes the ORDER of this sweep and nothing else.** Where the
   optional `loopd-mod-signal` companion is installed on this machine, a role agent's
   session sends this session one line the moment its turn ends — `loopd-signal: role
   session <id> finished a turn in <worktree> (reason …, … ms) — settle it first …`. When
   such a line has arrived naming a session, run the reads above for that task **first**
   — `agent-sessions.sh state`, then `session-usage.sh --settle` and `check-dispatch.sh`
   exactly as written below — and then sweep every other `in-progress` task as before.
   The line is a hint about order, never a fact about status: a turn that ended is not a
   PR that exists, so nothing is advanced on the message itself, a named session that
   `agent-sessions.sh` still calls `working` is left alone, and the rule above stands —
   the line is not something a tick waits for. Absent the companion, no line ever
   arrives and this step runs exactly as before (`docs/pm-design.md#step-4`).

   **Settle the round's usage once, when its session has ended.** A dispatch line is
   written at the spawn and records `usage UNKNOWN` (step 3). For a task whose session
   has ended — `agent-sessions.sh state` prints `done`, `gone` or `stopped` (a session
   somebody ran `claude stop` on has a transcript like any other) — **and whose last
   `* DISPATCH` line still says `usage UNKNOWN`**, run:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/session-usage.sh <the task's `session:`> --settle <task-path>
   ```

   It reads that one session's transcript, counts each message once, and fills the line:
   `usage tokens=N tools=N ms=N cached=N errors=N by=Bash:152,Agent:30,…` — `tokens` is
   fresh input, cache writes and output; `cached` is cache reads, kept apart; `errors` is
   the tool calls whose result came back `is_error`; `by` is the top five tool names by
   call count (`-` when the session called none). **Exit 1 printed `usage UNKNOWN`: leave
   the line exactly as it is** — no transcript, two candidates or an unreadable one is not
   a zero, and you never compose the numbers yourself. A line that already carries numbers
   is never settled again. **A round that thrashed is REPORTED, never re-run:** when
   `errors` is more than 20% of `tools` and `tools` is at least 20, add one `# Notes` line
   to that task — `thrashing: errors=N of tools=N` — and change nothing else, neither the
   status nor the dispatch, for the same reason `check-dispatch.sh` is report-only
   (`CONVENTIONS.md`); the figure is the human's to read (`docs/pm-design.md#step-3-background`).

   **A `blocked` session whose round is RECORDED is the tick's to stop.** The CLI also
   calls a session `blocked` when its turn ENDED with a message addressed to the human
   (measured on 2.1.296: nearly every round whose criteria owe a merge or an answer).
   **After** the advance above has written what the agent reported — a `check-dispatch.sh`
   4 that advance fixes reads 0 — run, for each such task:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/agent-sessions.sh recorded <the task's `session:`> <task-path>
   ```

   - **`recorded <uuid>` (exit 0)** — blocked, `check-dispatch.sh` exit 0, and the job
     record shows a finished turn with no live prompt. **Stop it, unconditionally:**
     `claude stop <the UUID's first field>`, then `agent-sessions.sh state <the UUID>`
     once. `stopped`, `done` or `gone` means it landed — a "No job matching" from a
     session the CLI already retired included. Anything else: report it, resume nothing,
     and leave the rest to the next tick. Then settle its dispatch line exactly as above:
     a session the tick stopped is `stopped` like one the human stopped, and the settle
     runs **before** any resume replaces `session:`.
   - **Resume it only when a round is OWED** — a rule in this step sends that task's
     agent a message this tick: a missing criteria table, a `rebase-pr.sh` exit 3, a
     `qa-reviewer` re-run on a malformed checker table (below). That message is the resume's,
     by the two calls below, and **only to the session that round addresses**: when the
     role on the task's last `* DISPATCH` line is not the round's role, the round is a
     fresh dispatch as step 3 spawns it. **Write no `* DISPATCH` line for the resume** —
     its transcript opens with a copy of the round it continues, so settling it would
     count that round twice. Nothing owed ⇒ stop only; nothing reaches `AWAITING.md`.
   - **`unrecorded <uuid> check-dispatch=<n>`** — the human gate, as before: surface it,
     and this is the only `blocked` that puts a `claude stop` in `AWAITING.md`.
   - **`prompt <uuid> needs`** — the round ended listing what it needs from the human
     (measured on 2.1.303: "review, apply and merge terraform#866; re-login SSO …").
     **Hand it off, never attach:**
     `${CLAUDE_PLUGIN_ROOT}/scripts/session-handoff.sh <task-path>`. The agent's text goes
     only to the ignored `.loopd/.handoffs/<id>.txt`, which `AWAITING.md` renders as one
     `👉 do` row with its PR and run links; the task gets fixed text — ONE
     `Q<n>: do: …hand-off <id>…` entry, its block and a `needs handed off` note, in one
     write — and the session is stopped. The task keeps its status. Exit 3 — the stop did
     not land: report it; the next tick retries and writes nothing twice. Exit 1 (a live
     `waitingFor` prompt, or no `needs`) or 2 — change nothing.
   - **`prompt <uuid> <why>`, any other why** — a `waitingFor` prompt, or nothing shows
     its turn ended. Never stopped by the tick: surface it as `claude attach <the UUID's
     first field>` to answer it. A stalled resume (below) is checked first.
   - **`not-blocked <state>`** — the rows above apply. **Exit 2** — unknown: change nothing.

   **A hand-off's round is RESUMED once the human has answered it** — same task, same PR
   (`CONVENTIONS.md` → "A subagent works ONE task"). For EVERY task whose `# Notes` carry a
   `needs handed off` line, whatever its status — `in-progress`, `in-review` or `blocked` —
   run, after step 2's fold:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/session-handoff.sh --owed <task-path>
   ```

   **Exit 0** prints `owed <uuid> <id>` and `answer: <text>`: the latest hand-off names the
   task's `session:`, its `Q<n>: do:` entry is answered, no `woke`/`resumed` note follows it,
   and the session is `stopped` or `done`. Resume it by the two calls below with the message
   `The human finished hand-off <id>: <text>. Carry on with this task.`, read the id back with
   `resume-id`, and write the `woke`/`resumed` note — that note, or the `resume launched` one
   below, is what makes the next tick answer `not-owed already-resumed`. **Exit 1** (`not-owed <why>`) — nothing to send. A
   `done` task is never owed: its hand-off row stays in `AWAITING.md` until answered, and
   the answer is the human's record, not a round.

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
   host does not resolve. **4** — status and `pr:` contradict each other. **5** —
   UNRECORDED: everything else cleared, but an open or merged PR from the task's
   `branch:` is not in `pr:`; record it or close it before step 5 closes the task. A 1, 3
   or 4 lists such PRs too and keeps its code; `UNRECORDED: UNKNOWN` never means "none".
   **2** — it
   could not answer; treat as unknown, not as fine.
   **A non-zero verdict is never a re-dispatch.** On exit 1, read the agent's worktree
   and `claude logs <the session's first field>` first: the work is usually already
   committed, and one message asking it to open the PR on what it has recovers it — the
   same task and same PR,
   which is the resume step 3 allows. **The resume is two calls:
   `${CLAUDE_PLUGIN_ROOT}/scripts/agent-sessions.sh full <the recorded session>`, then
   `cd <worktree> && claude --bg --resume <the UUID full printed> '<the message>'`**,
   and nothing else: the session keeps the agent, model, permission mode and add-dir it
   was spawned with, and passing any of them starts a COPY under a new id (measured on
   2.1.296). `full` runs on every recorded value, so a task
   dispatched before step 3 recorded the full id — its `session:` still the short
   one — is resolved before any resume. **`--resume` takes the FULL session id, never the
   short one**: a short id is a picker search term, the picker finds "No sessions match",
   and a `--bg` session parks `blocked` on it with no turn taken (three times on
   2026-10-08/09). **A non-zero `full` is neither a resume nor a re-dispatch**: exit 1
   (more than one session matches) and exit 2 (none, or unknown) leave the task as it is —
   name it in the tick report and surface it as a 🔴 item. Resume only a session
   `agent-sessions.sh state` calls `done`, or `stopped` after the tick's own stop of a
   recorded round or a hand-off — never one still `blocked` or `working`. **Read the id off what
   the resume printed, before the tick moves on:**
   `${CLAUDE_PLUGIN_ROOT}/scripts/agent-sessions.sh resume-id <the UUID> '<everything the resume printed>'`.
   A flag-free resume prints `note: woke session <short> with its saved options (…)` then
   `backgrounded · <short> · <name>`, and the id is unchanged: **`same <uuid>`** — leave
   `session:` alone and write one `# Notes` line `woke <that UUID>`. A resume that forked
   prints `… started a copy as <new short>.` then `backgrounded · <new short>`:
   **`copy <uuid>`** is that new id's full UUID — write it as `session:` and one `# Notes`
   line `resumed <that UUID>`. **Exit 1 or 2, the resume has launched anyway**: set
   the task `blocked`, write `resume launched; session id unresolved: <the printed id>`
   under `# Notes`, report it as a 🔴 item, and never resume the old recorded session.
   **`claude stop` and `claude logs` refuse a full UUID** ("No job matching"),
   so give them its first field. Anything beyond that is the human's
   call — surface it in `AWAITING.md` (measured case: `docs/pm-design.md#step-4`).

   **A STALLED RESUME falls back on the next tick — the one named exception to the
   `blocked` row above.** For each task whose `session:` is the UUID on its last
   `resumed` or `woke` note, run `${CLAUDE_PLUGIN_ROOT}/scripts/agent-sessions.sh stalled <the task's session UUID>`
   at this sweep. It reads `claude agents --json` and that session's transcript — never
   `session-usage.sh`, which prints `usage UNKNOWN` for a live session. **Exit 0**
   (`stalled <uuid>`: `blocked`, no turn since the resume, and no `waitingFor`):
   1. `claude stop <the UUID's first field>`, then `agent-sessions.sh state <the UUID>`
      once; anything but `stopped`, `done` or `gone` means the stop has not landed —
      report it and leave the rest to the next tick.
   2. `${CLAUDE_PLUGIN_ROOT}/scripts/stall-counter.sh record <task-doc> --blocker 'resume stalled'`.
      A count of **1** on stdout is this round's one fallback: write `resume stalled:
      <uuid> stopped` under `# Notes` and dispatch ONE fresh round in the same worktree,
      exactly as step 3 spawns. Anything else is a second stall — dispatch nothing:
      exit 1 ⇒ `stall-counter.sh escalate <task-doc>`; exit 0 ⇒ a 🔴 `AWAITING.md` item.
   **Exit 1** is not a stall, and the rows above apply — **including a session `blocked`
   on a login or other `waitingFor` prompt before its first turn**: a fresh round would
   park on the same prompt, so it stays the human's. **Exit 2** is unknown: change
   nothing. The never-wait rule and the no-re-dispatch rule above are unchanged — this
   is a read at the sweep, and no `check-dispatch.sh` verdict is a fallback.

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
     **The one opt-in exception: `mergeAtReviewCap`** (`instance.config.json`, default
     off). With it `true`, a `yolo` PR at the cap whose `review-clearance.sh` answers **6**
     (reviewed at the head, threads open) is merged rather than surfaced, if every other
     precondition of `AUTONOMY.md` → "Merge at the review cap (opt-in)" holds. Exit 4
     never qualifies. After the merge, write one `# Notes` line on the task:
     `merged at review cap <ISO 8601>`. Without the key, or under `gated`, surface it as
     above.
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
       default branch, resolve, push with
       `--force-with-lease="refs/heads/${BRANCH}:${SHA}"` — braced and quoted, because
       zsh reads `$BRANCH:h…` as a modifier and drops the colon — re-run the
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
     **Run it on EVERY in-review PR, external review or not**: exit 1 writes the fail line
     the merge receipt refuses on, whatever cleared the review. Where an EXTERNAL reviewer
     cleared the head (a `REVIEWERS` vendor, route A or C of `review-clearance.sh`), the
     receipt needs no checker table, so exit 2 and 4 there do not hold the merge.

   **Pin verification to the head SHA.** Record which SHA passed (task `# Notes`). If
   a PR's head advances, its prior pass is stale — invalidate and re-verify. Surface
   the task as a 🔴 *merge* item only once **all** its PRs have an independent pass
   **and** green CI **at their current head SHA**. This never bypasses the human merge
   gate; where a project delegates merging, this same clearance is the precondition
   `AUTONOMY.md` builds on.


<!-- end of step 4 -->
