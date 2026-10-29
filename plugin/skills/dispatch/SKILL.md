---
name: dispatch
disable-model-invocation: true
description: Start the Project Manager loop as a SERIAL, completion-driven loop (one tick at a time) in this control-panel instance repo — bare, it owns its own cadence
argument-hint: "[gap|once|dry-run|stop]  cadence between passes, default 10m (e.g. 30m); once = a single tick, no cadence; dry-run = once, reporting only; stop = end the loop"
allowed-tools: Bash(pwd), Bash(ls:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/bundle-paths.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/tick-lock.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/tick-reap.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/tick-spawn.sh:*), ScheduleWakeup, CronCreate, CronList, CronDelete
---

Start the **Project Manager loop** — but as a **SERIAL, completion-driven** loop:
**exactly one tick runs at a time.**

> **This file is the steps.** The reasoning — why serial and not `/goal`, why the lock
> exists and what it closed, why publishing was deleted, the measured incidents behind
> each rule — is in `docs/pm-design.md` in the loopd template ("The launcher").
> Read it before *changing* a rule here; you never need it to *run* the loop.

Three standing facts the steps below rest on:

- **Serial, gated on completion.** A tick runs to its committed ledger close before the
  next one is dispatched: overlapping ticks double-dispatch a task, corrupt a shared package store and
  race each other's pushes. **A clock is allowed to ASK — it is not allowed to overlap.**
  That distinction is what makes `/loop` safe here and it is younger than this rule: before
  `.tick-lock`, a fixed-interval loop shorter than a tick genuinely did overlap, so the
  cadence had to be hand-driven. Now the firing that lands mid-tick is refused at `acquire`
  before anything is spawned, so the interval decides only how often the loop LOOKS.
- **The guarantee is backed by `.tick-lock`, not by session memory** — memory does not
  survive a compaction. The tick runs its own acquire too (`--as tick`, its step 0.5),
  because a resume never passes through this launcher. The tick is a detached `claude --bg`
  session, so nothing notifies you: step 0's reaper reads its ledger close on the next
  fire. You mint a per-tick id and hand it to the tick you spawn, so that tick's own re-entry is provable (exit **0**); a bundle
  that declares none falls back to the session's id, where a mere match is exit **2** and
  the human's. **Never wake a completed tick with a
  message — dispatch a fresh one, every time.** The rule for every other agent is
  stated once in `CONVENTIONS.md` → "A subagent works ONE task", and this is its one
  line:

  > same task and same PR ⇒ resume; anything else ⇒ dispatch fresh; a tick ⇒ never
- **Your step 1 is unchanged** by the tick's claim: `--as launcher` refuses any live lock,
  claimed or not, and never claims one — and the tick's **own claim** on the lock you took
  for it is not a conflict; an unclaimed lock is precisely the dispatch it is.
- **It is a PER-CLONE lock.** Two loops from two clones of a shared bundle is the
  *design* (each dispatches only its own human's tasks, `${CLAUDE_PLUGIN_ROOT}/scripts/task-owner.sh`); two
  loops against one clone is the bug. The lock bounds **PM ticks only** — never the role
  agents a tick dispatches (`maxAgentsInFlight` is that limit).

## Preconditions

**Two checks. What the launcher may look at is an ALLOWLIST of four** — see "The launcher
reads nothing else"; anything not on it is a tick or a subagent. Both checks below are on it.

1. Must run from a **control-panel instance root**: confirm `instance.config.json` in the
   cwd and `SCHEMA.md` at the resolved schema path (`AB_SCHEMA`; the root on a legacy
   layout) with exactly
   `ls instance.config.json "$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/bundle-paths.sh AB_SCHEMA)" 2>/dev/null || ls instance.config.json SCHEMA.md`
   — if it fails, tell the user to `cd` into the instance and stop. (Never hardcode a
   path. The role agents ship in the plugin, so a bundle has no `.claude/agents` and the
   check must not look for one.)
2. **Own the cadence — one session cron, created once.** `CronList`. If a job's prompt
   is `run the project-manager agent for one LIVE tick` (an older approach), `CronDelete`
   it. Then, **unless** the argument is `once` or `stop`, or a `/loop` with no interval is
   driving this pass (its instructions are in your context): if **no** listed job's prompt
   names `/loopd:dispatch`, `CronCreate` one — `cron` = `*/<gap in minutes> * * * *`,
   `prompt` = `/loopd:dispatch <gap>`, recurring — and print the actual next-run time the
   result gives. A job that already names `/loopd:dispatch` — this skill's own from an
   earlier pass, or one a human's `/loop 10m /loopd:dispatch` created — means the cadence
   is owned: create nothing, say nothing. **Never two jobs.**

### The launcher reads nothing else — an ALLOWLIST of four, and everything else is a tick

**Everything the launcher may look at — this bundle, git, the GitHub API, the network,
the machine — is exactly these operations:**

1. **The cwd precondition** — `instance.config.json` in the cwd and `SCHEMA.md` at the
   resolved schema path, which is precondition 1 above and nothing wider.
2. **`${CLAUDE_PLUGIN_ROOT}/scripts/tick-lock.sh acquire`** — a **write** only the launcher can
   make, which returns an exit code rather than content and prints nothing on the normal path.
3. **`${CLAUDE_PLUGIN_ROOT}/scripts/tick-reap.sh`** — step 0's reaper: one script that
   answers whether the tick the lock records has finished, releases the lock when it has,
   and prints what the human needs from it. It is here because a detached tick notifies
   nobody, and the question is bounded to that one tick; the script owns every read.
4. **The cron step** — `CronList`, then `CronDelete` on the old job whose prompt matches
   and `CronCreate` when no job of ours is listed: precondition 2 above, and the three
   tools the frontmatter's `allowed-tools` grants for it. It reads and writes the
   **scheduler**, never this bundle's state, so it is inside the category the list closes
   over rather than an exception to it.

**Anything that is not one of those is a TICK or a SUBAGENT.** That is the whole
rule, and it is a **category**, so there is no list to keep current and nothing to add
to when the world grows a new kind of source. **And here is the disposal, so you are
told what to do and not only what to stop:** dispatch the tick and let it read —
`project-manager.md` step 0 and step 1 do every one of them, in a context that is thrown
away — or, when the question is genuinely not the tick's, hand it to a **background
subagent** and let that context pay. Never here, and never before a tick or instead of
one: not the whole thing, not a summary, not "just to orient".

**The one write follows from the same category, and so does the one it forbids.** Item 2 is
the launcher's own write because it needs no view of this bundle's state — an exit code, not
content; item 3's writes are the script's, never yours. **So the launcher may not clear a caveat it did not raise:** a task's
`open_caveats:` (`SCHEMA.md`) comes out only on evidence, and evidence about this bundle's
state is precisely what the category above puts out of the launcher's reach. Not a further
entry, and not something to weigh against being able to dispatch — the tick or a subagent
raised it, and the same actor clears it.

**A further entry is the regression, not an exception** — the list closes over a
**category**, reads that cannot observe this bundle's state, and not over a count of nouns.
**No other reader may be added by analogy** — what stood here was an enumeration of
forbidden sources that said it was closed, and it was, and it rotted anyway the day the
expensive reads were a category it had never named.
Item 3 is the one entry added since, by decision and not by analogy: a detached tick
notifies nobody, so the question "has it finished?" moved into one script.
The launcher's own harness under `tests/` counts these operations and fails when the
list grows.

**And what the four you DO have establish is bounded — say UNKNOWN when they did not
answer.** `CONVENTIONS.md` → "A read that could not have established the answer returns
UNKNOWN" is a launcher rule before it is anyone else's: the four failures it carries were
all made here, in this context, from reads that returned something. A cwd probe and an
exit code answer their own two questions and nothing about a rollout, a check run, a
region or a workflow — so an answer of that kind is `UNKNOWN` plus the read that would
settle it, handed to the tick or a subagent, never a conclusion reported to the human.

Why: every byte read here lands in the main session's context — the one context this
loop must survive on for hours — while the tick's context is disposable; the full
argument is `docs/pm-design.md#launcher-reads-nothing`.
And never call `${CLAUDE_PLUGIN_ROOT}/scripts/tick-lock.sh status` before `acquire` — the check
and the write are deliberately one operation; looking first rebuilds the race this closes.

### Why there is no publish grant, and no publish step

The board is a **local file** the tick
renders as its last act (`project-manager.md` step 8, one `BOARD: rendered <path>`
line). Publishing is a **human-typed skill**, `/loopd:board publish`, for two independent
reasons: it is account-scoped, so one URL can never be written by two humans
(`docs/pm-design.md#launcher-no-publish`), and a headless `claude -p` session holds no
artifact tool at all — measured 2026-09-05 on Claude Code 2.1.261, inventory and tool
search both. So the tick prints `run /loopd:board publish to refresh` and stops there.

## Running it on a cadence: the skill owns one session cron

**`/loopd:dispatch` is the standard way to run this loop in a session — bare.** It is a
loop, not a tick: precondition 2 creates **one session-scoped cron job** whose prompt is
`/loopd:dispatch <gap>`, and from then on the job re-fires this skill on the clock. That job
is the same first-party primitive `/loop [interval] <prompt>` creates (Claude Code
2.1.261 — `/loop 5m /foo` is a `CronCreate` job), so **`/loop 10m /loopd:dispatch` still
works and is the same loop**: precondition 2 sees that job and creates none. Nothing else is
installed, started or supervised — **there is no watcher, no `sleep` loop and no script for
cadence**; the one cron job is session-only, written to no file, and gone when the session
ends. Precondition 2 also deletes the fixed-interval cron an older approach left behind.

**10m, and here is the number it comes from.** The gap is not tuned to tick length — a tick
that dispatches role agents runs as long as it runs, and the lock is what keeps that safe.
It is tuned to **the slowest thing a tick waits on**, which is an external review
round-trip: a CodeRabbit review plus the required checks lands in **minutes, not seconds**,
so a pass every 10 minutes meets a merged PR or a finished review roughly one pass after it
happens, and a shorter interval buys nothing but passes that find the same state. Longer
than ~30m and the loop stops being the thing that notices. **The clock is approximate**:
the scheduler shifts a recurring job by a fixed per-job offset of up to half its period, so
a 10m job fires 10–15 minutes apart, and it fires only while the session is idle. Report
the next-run time `CronCreate`/`CronList` gives, never the cron expression.

**The job expires after seven days** — recurring session jobs do; it fires one last time
and is deleted. A pass that finds no job of ours listed re-creates it (precondition 2), so
the loop survives the expiry by being run; a session left untouched for a week stops, and
the next bare `/loopd:dispatch` starts it again.

**Two other forms, both still the same skill:**

| | |
|---|---|
| **`/loopd:dispatch once`** | one tick, no cadence. Nothing is created, nothing scheduled; step 2 waits for its close. |
| **`/loopd:dispatch dry-run`** | `once`, with the tick briefed DRY RUN: steps 1–2 and a report, no role agent spawned, no target repo written. |
| **`/loopd:dispatch stop`** | end the loop: `CronDelete` every listed job whose prompt names `/loopd:dispatch` — this skill's own or a human's `/loop` — and cancel any pending wakeup; then step 5. |
| **`/loop /loopd:dispatch`** | no interval ⇒ `/loop`'s dynamic mode — the model paces its own iterations instead of a clock doing it. The right shape for a quiet bundle whose passes would mostly find nothing. Precondition 2 creates no cron under it; step 3 is the cadence. |

**Under the cron, or a `/loop` with an interval, two of the steps below change, and only
two:**

1. **Step 1 takes the lock with `--as loop`** — `${CLAUDE_PLUGIN_ROOT}/scripts/tick-lock.sh
   acquire --as loop --agent project-manager --claimant <id>`. Every decision is the
   launcher's — the id included — and the only
   difference is that a held lock is reported in **one line** instead of a block, because
   at a fixed interval most firings land while an earlier tick is still running. `once`
   keeps `--as launcher`: a human typed it and expected a dispatch, so a held lock is the
   loud block.
2. **Skip step 3.** The cron job *is* the cadence, so scheduling a wakeup as well gives the
   session two schedulers and double the passes. Skip step 2's wait too: reap, acquire,
   spawn, and end the pass — the next fire's step 0 reaps what this one spawned.

**Exit 1 from that acquire is a CLEAN SKIP, not an error.** It is the expected outcome of a
firing that landed mid-tick. Print the one line it gave you, **end the pass successfully**,
and let the next firing try again: no error, no `⚠️`, nothing put in front of the human,
and nothing retried. A loop that reports a fault six times an hour for working correctly is
one an operator stops reading. The other codes are unchanged and still stop the loop: 2
and 3 go to the human exactly as step 1 says.

**A clock can never spawn a second orchestrator, and the lock is the proof — not this
paragraph.** The cron fires on a clock, so it will fire into a running tick; `acquire`
refuses with exit 1 in that firing, before anything is spawned, and the check and the write
are one `O_EXCL` create with nothing to interleave. So the "one orchestrator" guarantee
holds under the cron for the same reason it holds for `once` — the guarantee never rested
on the cadence, and adding a clock does not touch it. **One loop per clone**, exactly as
before: the lock bounds ticks, not loops, so two sessions looping one working tree is still
the bug it always was — the lock catches it rather than blessing it. Inside one session,
precondition 2's "never two jobs" is what keeps a second `/loopd:dispatch`, or a `/loop`
typed on top of a running loop, from doubling the passes.

**Not a cloud routine.** `/schedule` (alias `/routines`) creates *remote* agents; a bundle
is a local checkout whose every operating input is gitignored, so a routine cannot run this
loop at all. The measurement is in `docs/operations.md` → "Running the loop on a cadence".

## How the serial loop works

Parse `$ARGUMENTS`: `stop` ⇒ the stop form above, then step 5, and nothing else; `once`
⇒ a single tick (no cron, no wakeup, `--as launcher`); `dry-run` ⇒ the same single tick,
spawned with `--dry-run`; anything else is the inter-tick
**gap** (default **10m**, whole minutes — a 5-field cron has no finer unit, so there is no
`0m`). Then:

0. **Reap the last tick first — every pass, including the first after `stop`:**

       bash ${CLAUDE_PLUGIN_ROOT}/scripts/tick-reap.sh

   It reads the one bg tick `.tick-lock` records and releases the lock **only** on a
   committed ledger close for that tick's minted id — or after writing the close itself
   when the tick's session ended or vanished with its entry open (a dead tick). Never on a
   notification, never on a session state alone. Act on its exit code:
   - **0** — nothing held, or it reaped one: print what it printed (the tick's close line,
     `Needs you:` from `AWAITING.md`, a `COST:` line) verbatim, then go to step 1.
   - **1** — the tick is still running. Print its one line and **end the pass**: the fire
     is dropped, never queued.
   - **4** — `BLOCKED`: the tick's session waits on a prompt before a committed close. Put
     its line in front of the human and end the pass; it is neither idle nor done.
   - **2** — it cannot tell. Report the line and stop; the lock stays.

   It never prints the tick's transcript, and neither do you: the tick's own report goes
   nowhere, because **the ledger and `AWAITING.md` are the result**.
   The decision table and why this is the one reader added:
   `docs/pm-design.md#launcher-reaper`.

1. **Take the lock, then dispatch — in that order, with nothing in between.**
   First **mint this tick's id** — one fresh literal per tick, never reused, printed by

       ${CLAUDE_PLUGIN_ROOT}/scripts/tick-lock.sh mint

   (e.g. `tick-20260906T152233Z-a7f3`; never compose it yourself — a local clock labelled
   `Z` is the bug this command exists for) — then run

       ${CLAUDE_PLUGIN_ROOT}/scripts/tick-lock.sh acquire --agent project-manager --claimant <id>

   (add `--as loop` when the cron job or a `/loop` is driving — every form but `once` and
   `dry-run`; see "Running it on a cadence" above)

   and act on its exit code. **The check and the write are that one call** (`O_EXCL` —
   no read-then-write to interleave with): it closes a window of seconds to minutes —
   between your dispatch and the tick's own ledger entry — in which the ledger truthfully
   reports nothing running. And nothing may sit between the acquire and the spawn:
   no `git pull`, no state read, no other tool call.

   **That literal is the tick's identity, and you hand it on.** `acquire` records it in
   `.tick-lock` as `claimant:` — the only place it lives, and you write no file yourself —
   and `tick-spawn.sh` puts the id you minted at step 1, verbatim, into the tick's brief and
   its ledger line, because that tick's own acquire passes the same id and step 0 finds its
   entry by it. Mis-copy it and the tick still runs: adopting an unclaimed lock
   never matches the id, and the script reports the mismatch instead of refusing.

   - **0** — the lock is yours, and it printed nothing. **Spawn the tick now**, as the
     very next thing you do.
   - **1** — HELD: a tick is in flight that step 0 could not see (an older launcher's).
     Do **not** dispatch. Under the cron or a `/loop` with an interval, print the one line
     and end the pass clean. Under `/loop`'s dynamic mode, schedule the gap (step 3,
     `noop: true`) and skip. Under `once`, report the block and stop.
   - **2** — stale, future-dated, or unreadable; the script printed the details. Do
     **not** dispatch and do **not** delete it: put what it printed in front of the
     human and stop until they answer. `${CLAUDE_PLUGIN_ROOT}/scripts/tick-lock.sh release` is the human's answer, not yours.
   - **3** — it could not write the lock at all. Report and stop; never dispatch
     unguarded.

   **Exit 4 cannot reach you** — it is the tick's refusal for finding no lock, and
   taking a lock where there is none is what you are for.

   The tick itself — a **fresh** detached `claude --bg` session, **never an `Agent`-tool
   child** (a background subagent's whole transcript is re-sent every ~30 s for a status
   line, 14.3% of a busy tick's input measured in tick-as-bg-session/task-001, and its
   result lands in this context):

       bash ${CLAUDE_PLUGIN_ROOT}/scripts/tick-spawn.sh --tick <id> --gap <gap>

   (`once` passes `--gap once`; `dry-run` adds `--dry-run`, so
   `tick-spawn.sh --tick <id> --gap <gap> --dry-run` — the tick does steps 1–2 and
   reports, spawns no role agent and writes no target repo.)
   It spawns `claude --bg --agent loopd:project-manager --permission-mode auto` (namespaced
   — a bare agent name does not resolve), with `--model` from
   `resolve-model.sh project-manager` and `--effort` from `resolve-effort.sh project-manager`
   (none printed ⇒ no flag), the brief built from `skills/dispatch/tick-brief.md` — the gap,
   the id and the standing guardrails, and **not state**: the tick reads the bundle, `git`
   and `gh` itself. It records the session on `.tick-lock` (`agent-sessions.sh full`) for
   step 0, and prints one `spawned:` line; print it. A `resolve-model:` line it passed
   through means no model was chosen — report that line, so an unchosen model is visible
   rather than assumed. **Fresh every time — never wake a completed tick with a message**; step 0.5 refuses such a tick
   anyway. Exit **1** means the spawn did not start and the script already released the
   lock (`${CLAUDE_PLUGIN_ROOT}/scripts/tick-lock.sh release` — a lock with no tick behind
   it is the stale case, arriving hours early); report it. Exit **3** is a refusal; report it.

2. **Wait for it to finish — only under `once` and `dry-run`.** Under the cron or a
   `/loop` the pass ends at the spawn, and the next fire's step 0 is the wait. A human who
   typed `once` expected a result, so run

       bash ${CLAUDE_PLUGIN_ROOT}/scripts/tick-reap.sh --wait

   with the Bash tool's longest timeout. It polls the same way step 0 reads, returns when
   the tick's committed close (or its death) releases the lock — printing the close line,
   `Needs you:` and `COST:` — and is bounded by the tick's wall-clock budget
   (`roleMinutes.project-manager`, else `maxAgentMinutes`, absent ⇒ 45). Exit **5** means
   its slice ran out first: run it again. Exit **1** is the budget spent: say the tick is
   still running and that the next `/loopd:dispatch` reaps it. **4** and **2** are step 0's.

   **The `COST:` line is the ONE metadata footer, printed by a script:**
   `agent-usage.sh fmt` over the numbers `session-usage.sh` reads from the ended tick
   session's transcript — never reformatted and never composed by you: `agent-usage.sh`
   owns the one usage form. **There is no model name in it**: the transcript's numbers carry
   none here, so there is nothing to print that would not be a guess.
   **`usage UNKNOWN` ⇒ print no footer at all** — the reaper prints none.
   **The tick report ONLY.** A role agent's numbers are already on its task document as a `* DISPATCH`
   line (`project-manager.md` step 3).

   **After a compaction, the in-flight memory is gone — and the answer is still not
   yours to look up.** Step 0 and `.tick-lock` answer it; re-deriving the in-flight set is
   one of the tick's opening steps (`project-manager.md` step 0.5: ledger, then task
   `status:`, then `git log`/`gh pr list`), and a tick that finds an open ledger entry
   **reports it and holds**.

   There is no step 2b. It was the per-tick `advisor` observer, retired 2026-10-08: no
   bundle had enabled it, and it read the same inputs as the tick to produce a second
   opinion the tick then adjudicated (the argument it rested on is kept at
   `docs/pm-design.md#launcher-advisor`). An `"advisor"` entry a bundle still carries in
   `roles` or `roleTiers` is inert — `/loopd:welcome check` names it; nothing dispatches it.

3. **On completion**, end the pass. Under the cron, or a `/loop` with an interval, the
   clock re-fires `/loopd:dispatch <gap>` on its own and you schedule **nothing** — two
   schedulers is double the passes. Under `once` there is no next tick. **Only under
   `/loop`'s dynamic mode** (no interval) schedule the next tick after the gap yourself:
   `ScheduleWakeup` with `delaySeconds` = the gap and `prompt` = `/dispatch <gap>`.
   **Always pass `noop` and `reason`.** `noop: true` when step 0 reaped nothing or a tick
   whose close line reports no change; `noop: false` when it did.
   **A board refresh or a render is not a change** — every tick refreshes the board, so
   counting it would pin `noop` to `false` forever and hand the human back the
   scrolling idle loop the streak collapse exists to prevent. `reason` is one specific
   sentence about what this tick is waiting on ("holding for qa-reviewer on #214"),
   not "waiting".

4. **When `/dispatch` re-fires — from the cron job, a `/loop`, or that wakeup:** go to
   step 0. Its reaper and step 1's `acquire`, not this session's memory, decide whether a
   tick is in flight. Query nothing else here.

5. **Stop** on `/loopd:dispatch stop`, or when the user says so: `CronList`, `CronDelete`
   every job whose prompt names `/loopd:dispatch`, cancel any pending wakeup, and
   dispatch no further ticks. **Release nothing.** A tick still running closes its own
   entry, and the next fire's step 0 — whenever a `/loopd:dispatch` next runs — reaps it
   and releases its lock; a tick that dies meanwhile is closed as dead there. A live
   sibling's lock is never this session's to delete.

This guarantees **at most one PM tick at any moment**, with a `gap` pause between
ticks, regardless of how long a tick runs.

## Standing guardrails for each tick dispatch

They are the tick's brief, so they live in **`skills/dispatch/tick-brief.md`**, the
template `tick-spawn.sh` fills — never retyped here, and never composed by you.
`tests/tick-bg-session.test.sh` asserts each line reaches the spawned session verbatim.

## Notes

- One serial loop per session — and **one active loop per clone**: don't start a
  second session looping the same working tree. Two humans on one bundle from two
  clones is supported (see the standing facts). To change the gap: `/loopd:dispatch stop`,
  then `/loopd:dispatch <gap>` — precondition 2 never replaces a job that is already there.
- **The dispatch lock is `.tick-lock` at the instance root** — gitignored, per clone,
  written by step 1 (and `tick-spawn.sh` adds the tick's `session:`), released by step 0's
  reaper on the tick's committed close. The tick claims
  it (step 0.5, `--as tick`, recorded in `.tick-lock.claim`) and releases nothing.
  `${CLAUDE_PLUGIN_ROOT}/scripts/tick-lock.sh status` reads it without touching it (for a human, never this
  launcher); `TICK_LOCK_STALE_MINUTES` (default 120) sets when step 1 stops waiting
  and asks. A missing lock is never an error.
- **Starting the loop prints a handful of lines, not a screen**: a failed
  precondition, one line naming the gap and the job's actual next run (first pass only —
  a re-fire that finds the job already there says nothing about it), and that the tick is
  dispatched. If a start
  scrolls the terminal, the launcher did work that belonged in the tick — move it
  there; do not quiet it in place.
- A tick with nothing to do is a fast no-op — the gap keeps idle cycles cheap — and
  **its whole report is one line naming the next check** (`project-manager.md` step
  0.9). Pass the gap on: the tick puts it in `tick-delta.sh check --gap <gap>` so
  that line can say when you will next hear from the loop.
- Each tick refreshes `AWAITING.md` **only when that file already exists, and only
  when the tick changed something** (a `noop: true` tick leaves it alone rather than
  restamping its `Last refreshed:` line). The loop never creates it: `/loopd:init`
  does, on any stamp, unless `"awaiting": false` in `instance.config.json` — the
  durable off switch; deleting the file turns the queue off until the next stamp.
- Each tick also refreshes `SNAPSHOT.json` (`${CLAUDE_PLUGIN_ROOT}/scripts/write-snapshot.sh --quiet`, at
  the end of the tick) — same rule and same off switch: the writer rewrites the file
  **only when it already exists**, so `rm SNAPSHOT.json` takes this instance off the
  board and `touch SNAPSHOT.json` puts it back. `boardInstances` in
  `instance.config.json` names what a board shows; **absent or empty ⇒ just this
  instance**.
- **The board page is re-rendered by the same tick, to a local file** —
  `${CLAUDE_PLUGIN_ROOT}/scripts/build-board.sh --standalone` — which resolves its own
  output path from `AB_BOARD_DIR` — today `.loopd/.board-live/board.html` — so do
  NOT pass `--out`: a hardcoded one overrides the resolver and renders outside the
  layout. It is the gitignored
  path `${CLAUDE_PLUGIN_ROOT}/scripts/watch-board.sh` also writes. Per machine, not per account; nothing is
  published anywhere. `board: false` in `instance.config.json` ⇒ no render and no
  mention; absent or `true` ⇒ it renders and the tick reports the path. The page is
  only as fresh as the last tick (its masthead timestamp says); `${CLAUDE_PLUGIN_ROOT}/scripts/watch-board.sh`
  is the live view, and `/loopd:board serve` is the same page on a local URL.
- **No tick commits a board page.** The tracked `/board.html` is gone: a derived file
  every clone re-rendered and pushed made the path contended on every tick, and the local
  route replaced it. `/loopd:board serve` serves the file above on
  `http://localhost:<boardPort>`, 127.0.0.1 only, re-rendering when the snapshot changes.
  How to open it is `docs/operations.md` → "Opening the board".
