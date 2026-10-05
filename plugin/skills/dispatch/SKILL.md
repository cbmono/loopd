---
name: dispatch
disable-model-invocation: true
description: Start the Project Manager loop as a SERIAL, completion-driven loop (one tick at a time) in this control-panel instance repo
argument-hint: "[gap]  pause between ticks, default 10m  (e.g. 0m for back-to-back, 30m)"
allowed-tools: Bash(pwd), Bash(ls:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/bundle-paths.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/tick-lock.sh:*), Agent, ScheduleWakeup, CronList, CronDelete
---

Start the **Project Manager loop** — but as a **SERIAL, completion-driven** loop:
**exactly one tick runs at a time.**

> **This file is the steps.** The reasoning — why serial and not `/goal`, why the lock
> exists and what it closed, why publishing was deleted, the measured incidents behind
> each rule — is in `docs/pm-design.md` in the loopd template ("The launcher").
> Read it before *changing* a rule here; you never need it to *run* the loop.

Three standing facts the steps below rest on:

- **Serial, gated on completion.** A tick runs to its notification before the next one is
  dispatched: overlapping ticks double-dispatch a task, corrupt a shared package store and
  race each other's pushes. **A clock is allowed to ASK — it is not allowed to overlap.**
  That distinction is what makes `/loop` safe here and it is younger than this rule: before
  `.tick-lock`, a fixed-interval loop shorter than a tick genuinely did overlap, so the
  cadence had to be hand-driven. Now the firing that lands mid-tick is refused at `acquire`
  before anything is spawned, so the interval decides only how often the loop LOOKS.
- **The guarantee is backed by `.tick-lock`, not by session memory** — memory does not
  survive a compaction. The tick runs its own acquire too (`--as tick`, its step 0.5),
  because a resume never passes through this launcher. You mint a per-tick id and hand it
  to the tick you spawn, so that tick's own re-entry is provable (exit **0**); a bundle
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

**Two checks. What the launcher may look at is an ALLOWLIST of three** — see "The launcher
reads nothing else"; anything not on it is a tick or a subagent. Both checks below are on it.

1. Must run from a **control-panel instance root**: confirm `instance.config.json` in the
   cwd and `SCHEMA.md` at the resolved schema path (`AB_SCHEMA`; the root on a legacy
   layout) with exactly
   `ls instance.config.json "$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/bundle-paths.sh AB_SCHEMA)" 2>/dev/null || ls instance.config.json SCHEMA.md`
   — if it fails, tell the user to `cd` into the instance and stop. (Never hardcode a
   path. The role agents ship in the plugin, so a bundle has no `.claude/agents` and the
   check must not look for one.)
2. **Kill any fixed-interval PM cron** from an older approach: `CronList`, and if a
   job's prompt is `run the project-manager agent for one LIVE tick`, `CronDelete` it.
   Do **not** create a cron here.

### The launcher reads nothing else — an ALLOWLIST of three, and everything else is a tick

**Everything the launcher may look at — this bundle, git, the GitHub API, the network,
the machine — is exactly these operations:**

1. **The cwd precondition** — `instance.config.json` in the cwd and `SCHEMA.md` at the
   resolved schema path, which is precondition 1 above and nothing wider.
2. **`${CLAUDE_PLUGIN_ROOT}/scripts/tick-lock.sh acquire`** — a **write** only the launcher can
   make, which returns an exit code rather than content and prints nothing on the normal path.
3. **The cron cleanup** — `CronList`, then `CronDelete` on a job whose prompt matches:
   precondition 2 above, and the two tools the frontmatter's `allowed-tools` already grants.
   It reads the **scheduler**, never this bundle's state, so it is inside the category the
   list closes over rather than an exception to it.

**Anything that is not one of those is a TICK or a SUBAGENT.** That is the whole
rule, and it is a **category**, so there is no list to keep current and nothing to add
to when the world grows a new kind of source. **And here is the disposal, so you are
told what to do and not only what to stop:** dispatch the tick and let it read —
`project-manager.md` step 0 and step 1 do every one of them, in a context that is thrown
away — or, when the question is genuinely not the tick's, hand it to a **background
subagent** and let that context pay. Never here, and never before a tick or instead of
one: not the whole thing, not a summary, not "just to orient". (Step 2b's advisor
adjudication runs *after* a tick reports and is that step's own contract.)

**The one write follows from the same category, and so does the one it forbids.** Item 2 is
the launcher's only write because it needs no view of this bundle's state — an exit code, not
content. **So the launcher may not clear a caveat it did not raise:** a task's
`open_caveats:` (`SCHEMA.md`) comes out only on evidence, and evidence about this bundle's
state is precisely what the category above puts out of the launcher's reach. Not a further
entry, and not something to weigh against being able to dispatch — the tick or a subagent
raised it, and the same actor clears it.

**A further entry is the regression, not an exception** — the list closes over a
**category**, reads that cannot observe this bundle's state, and not over a count of nouns.
**No other reader may be added by analogy** — what stood here was an enumeration of
forbidden sources that said it was closed, and it was, and it rotted anyway the day the
expensive reads were a category it had never named.
The launcher's own harness under `tests/` counts these operations and fails when the
list grows.

**And what the three you DO have establish is bounded — say UNKNOWN when they did not
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

## Running it on a cadence: `/loop`, and nothing else

**`/loop 10m /loopd:dispatch` is the standard way to run this loop in a session.**
`/loop [interval] <prompt>` is first-party (Claude Code 2.1.261, `/loop 5m /foo`); it
re-fires a slash command on a clock in the session you are already in. Nothing else is
installed, started or supervised — **there is no watcher, no `sleep` loop, no cron and no
script for cadence**, and precondition 2 above deletes the fixed-interval cron an older
approach left behind.

**10m, and here is the number it comes from.** The gap is not tuned to tick length — a tick
that dispatches role agents runs as long as it runs, and the lock is what keeps that safe.
It is tuned to **the slowest thing a tick waits on**, which is an external review
round-trip: a CodeRabbit review plus the required checks lands in **minutes, not seconds**,
so a pass every 10 minutes meets a merged PR or a finished review roughly one pass after it
happens, and a shorter interval buys nothing but passes that find the same state. Longer
than ~30m and the loop stops being the thing that notices.

**A quiet bundle wants the self-paced form: `/loop /loopd:dispatch`, with no
interval.** Omitting the interval is `/loop`'s dynamic mode — the model paces its own
iterations instead of a clock doing it — which is the right shape when most passes would
find nothing to do. Reach for it on a bundle with one or two active projects; reach for the
interval form when work is landing and you want a fixed heartbeat.

**Under `/loop`, two of the steps below change, and only two:**

1. **Step 1 takes the lock with `--as loop`** — `${CLAUDE_PLUGIN_ROOT}/scripts/tick-lock.sh
   acquire --as loop --agent project-manager --claimant <id>`. Every decision is the
   launcher's — the id included — and the only
   difference is that a held lock is reported in **one line** instead of a block, because
   at a fixed interval most firings land while an earlier tick is still running.
2. **Skip step 3.** `/loop` *is* the cadence, so scheduling a wakeup as well gives the
   session two schedulers and double the passes. Dispatch, wait for the notification,
   release the lock, and end the pass.

**Exit 1 from that acquire is a CLEAN SKIP, not an error.** It is the expected outcome of a
firing that landed mid-tick. Print the one line it gave you, **end the pass successfully**,
and let the next firing try again: no error, no `⚠️`, nothing put in front of the human,
and nothing retried. A loop that reports a fault six times an hour for working correctly is
one an operator stops reading. The other codes are unchanged and still stop the loop: 2
and 3 go to the human exactly as step 1 says.

**A `/loop` can never spawn a second orchestrator, and the lock is the proof — not this
paragraph.** `/loop` fires on a clock, so it will fire into a running tick; `acquire`
refuses with exit 1 in that firing, before anything is spawned, and the check and the write
are one `O_EXCL` create with nothing to interleave. So the "one orchestrator" guarantee
holds under `/loop` for the same reason it holds when you type the command yourself — the
guarantee never rested on the cadence, and adding a clock does not touch it. **One `/loop`
per clone**, exactly as before: the lock bounds ticks, not loops, so two loops against one
working tree is still the bug it always was — the lock catches it rather than blessing it.

**Not a cloud routine.** `/schedule` (alias `/routines`) creates *remote* agents; a bundle
is a local checkout whose every operating input is gitignored, so a routine cannot run this
loop at all. The measurement is in `docs/operations.md` → "Running the loop on a cadence".

## How the serial loop works

Parse `$ARGUMENTS` as the inter-tick **gap** (default **10m**). Then:

1. **Take the lock, then dispatch — in that order, with nothing in between.**
   Resolve the tick's model first (below), **mint this tick's id** — one fresh literal per
   tick, shaped `tick-<UTC yyyymmddThhmmssZ>-<4 random chars>` (e.g.
   `tick-20260906T152233Z-a7f3`), characters `[A-Za-z0-9._-]` only, never reused — then run

       ${CLAUDE_PLUGIN_ROOT}/scripts/tick-lock.sh acquire --agent project-manager --claimant <id>

   (add `--as loop` when a `/loop` is driving — see "Running it on a cadence" above)

   and act on its exit code. **The check and the write are that one call** (`O_EXCL` —
   no read-then-write to interleave with): it closes a window of seconds to minutes —
   between your dispatch and the tick's own ledger entry — in which the ledger truthfully
   reports nothing running. And nothing may sit between the acquire and the spawn:
   no `git pull`, no state read, no other tool call.

   **That literal is the tick's identity, and you hand it on.** `acquire` records it in
   `.tick-lock` as `claimant:` — the only place it lives, and you write no file yourself —
   and the brief you spawn the tick with carries it verbatim, because that tick's own
   acquire passes the same id. It is what makes a second acquire *by that tick* a proved
   re-entry (exit **0**) rather than exit **2** and a human's call. Mis-copy it and the tick
   still runs: adopting an unclaimed lock never matches the id, and the script reports the
   mismatch instead of refusing.

   - **0** — the lock is yours, and it printed nothing. **Spawn the tick now**, as the
     very next thing you do.
   - **1** — HELD: a tick is in flight. Do **not** dispatch. Schedule the gap (step 3,
     `noop: true`) and skip, exactly as step 4 does. Under `/loop` there is no gap to
     schedule: print the one line and end the pass clean.
   - **2** — stale, future-dated, or unreadable; the script printed the details. Do
     **not** dispatch and do **not** delete it: put what it printed in front of the
     human and stop until they answer. `${CLAUDE_PLUGIN_ROOT}/scripts/tick-lock.sh release` is the human's answer, not yours.
   - **3** — it could not write the lock at all. Report and stop; never dispatch
     unguarded.

   **Exit 4 cannot reach you** — it is the tick's refusal for finding no lock, and
   taking a lock where there is none is what you are for.

   If the spawn itself fails to start, run `${CLAUDE_PLUGIN_ROOT}/scripts/tick-lock.sh release` before you
   report — a lock with no tick behind it is the stale case, arriving hours early.

   The tick itself: spawn a **fresh** `project-manager` agent
   (`subagent_type: loopd:project-manager` — **namespaced**, because the role agents
   ship in the `loopd` plugin and a BARE agent name does not resolve, measured
   2026-09-02) for ONE LIVE tick (background), with the standing guardrails below. **Fresh every time — never wake a completed tick with a message**;
   step 0.5 refuses such a tick anyway. **Brief it with the gap, the guardrails and the tick
   id you minted at step 1, verbatim — and not with state** — it reads the bundle, `git` and `gh` itself. **Run the tick on the
   orchestrator's configured model:** resolve it with
   `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-model.sh project-manager` (`roleTiers`, default `deep` → an alias
   via `models`, default `deep` → `opus`) and pass that as the tick's model. If
   `models`/`roleTiers` are absent the script says so on stderr — **report that line in
   the tick summary** and then inherit the session model, so an unchosen model is
   visible rather than assumed. (The `apex` tier is reserved for the `plan-architect`
   critique, not the routine tick.) A LIVE tick refines drafts, dispatches `ready`
   tasks, advances/reflects PRs, reports finished worktrees, proposes closing completed
   projects, and — after reflecting merges — may dispatch the `cataloguer` (throttled
   to one per tick; skipped on idle/trivial ticks).

2. **Wait for it to finish.** Do **not** start another tick while one is in flight.
   **That tick's `<task-notification>` is the only valid "finished" signal** — no tool
   listing and no amount of elapsed time substitutes for it; a tick that has looked
   done for *hours* is not done until its notification arrives. Don't poll; a quiet
   repo proves nothing.

   **That notification now means the tick's OWN exit, and a tick is minutes.** The
   harness withholds a parent's notification until every background child has stopped,
   so while role agents were `Agent`-tool children of the tick, this step waited for the
   slowest one and the lock below was held for the whole wave — measured 2026-09-13,
   ticks of 49, 75, 84 and 125 minutes that had each finished dispatching inside ~5. Role
   agents are detached `claude --bg` sessions now (`project-manager.md` step 3) and are
   nobody's children, so nothing here changed except the number. **A tick still running
   after an hour is a tick to look at, not a wave to wait out.**

   **When that notification arrives, release the lock** — run
   `${CLAUDE_PLUGIN_ROOT}/scripts/tick-lock.sh release` before you schedule the gap. That is the only place
   it is released in the normal path; releasing on anything weaker hands the next tick
   a dispatch the running one has not finished. A loop that dies before it releases
   leaves the lock to age out into step 1's case 2, where a human sees it — the
   intended failure, not a leak.

   **And end the report you relay with ONE metadata footer, printed by a script.** Its last
   line is the output of

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/agent-usage.sh fmt \
     --tokens <subagent_tokens> --tools <tool_uses> --duration-ms <duration_ms>
   ```

   — the three numbers straight off **this tick's** notification, never reformatted and
   never composed by you: `agent-usage.sh` owns the one usage form, and a second spelling of
   the same numbers is what makes two reports impossible to compare.
   **There is no model name in it**: the notification carries none, so there is nothing to
   print that would not be a guess.
   **`usage UNKNOWN` ⇒ print no footer at all.** A notification without the fields is a tick
   nobody measured, and a zero is a claim nothing supports.
   **The tick report ONLY.** A role agent's result is consumed by the tick, not by you, and
   its numbers are already on the task document as a `* DISPATCH` line
   (`project-manager.md` step 3) — a footer there would be the same figure twice.

   **After a compaction, the in-flight memory is gone — and the answer is still not
   yours to look up.** That is what `.tick-lock` is for, and you consult it in exactly
   one way: by taking it in step 1. **Do not read the disk here to reconstruct
   anything else** — re-deriving the in-flight set is one of the tick's opening steps
   (see `project-manager.md` step 0.5: ledger, then task `status:`, then
   `git log`/`gh pr list`), and a tick that finds an
   open ledger entry **reports it and holds**. Such a tick is a finished tick: schedule
   the gap as usual (step 3) and surface what it says.

2b. **Ask the advisor, if this instance has one.** One condition, and **its absence
   means skip this step silently** — never an error:

   - `"advisor"` appears in `roles` in `instance.config.json`. **That key is the whole
     off switch now.** It used to be two conditions, the second being that
     `.claude/agents/advisor.md` exists — but the name swap retired the instance agent
     links, so the plugin ships `advisor` to every machine and a file that is always
     absent would have turned this step off everywhere, silently.

   Dispatch it as `loopd:advisor`, namespaced like every role agent.

   Its model comes from `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-model.sh advisor`, like every role; **absent ⇒
   `light`**, the cheapest tier — the script prints why on stderr, so report that line.

   Dispatch it once, read-only, with the tick's summary. It replies `ADVISOR: clear`
   (say nothing, move on) or `ADVISOR: concern` + one line of `<task-path> --- <question>`.

   **YOU ADJUDICATE IT, AND THE HUMAN IS THE LAST RESORT — not the first.** Read the
   documents it cites and decide:

   - **It does not hold** ⇒ drop it silently.
   - **It holds and you can act** ⇒ act, record it in `answered_questions` prefixed
     `advisor:`. The human is not involved.
   - **It holds and you genuinely cannot decide** ⇒ escalate: copy it into that task's
     `open_questions` prefixed `advisor:`. That is the one path to a human.

   Untriaged concerns go in `advisor_notes` (`SCHEMA.md`) — deliberately not a gate;
   triage next tick. If you find yourself escalating most concerns, the advisor is
   miscalibrated — say so in the tick report rather than forwarding the noise (the full
   asymmetry argument: `docs/pm-design.md#launcher-advisor`).

   **It never blocks.** A verified concern does not undo a dispatch or delay the next
   tick. If the advisor errors, times out, or answers in any other shape, ignore it and
   continue.

3. **On completion**, schedule the next tick after the gap: `ScheduleWakeup` with
   `delaySeconds` = the gap and `prompt` = `/dispatch <gap>`. (Gap `0m` ⇒ dispatch the
   next tick immediately instead.)
   **Always pass `noop` and `reason`.** `noop: true` when the tick changed nothing —
   no dispatch, no status change, no task-document edit (a refined draft or a folded
   answer is real work, not idle), no `AWAITING.md` edit; `noop: false` when it did.
   **A board refresh or a render is not a change** — every tick refreshes the board, so
   counting it would pin `noop` to `false` forever and hand the human back the
   scrolling idle loop the streak collapse exists to prevent. `reason` is one specific
   sentence about what this tick is waiting on ("holding for qa-reviewer on #214"),
   not "waiting".

4. **When `/dispatch` re-fires from that wakeup:** if this session's own history says a
   tick is still in flight (dispatched, no notification yet), reschedule the gap and
   skip — never overlap. Otherwise go to step 1, whose `acquire` refuses the dispatch
   by itself if a live tick holds the lock; the lock, not memory, is what actually
   decides. Query nothing else here.

5. **Stop** when the user says so: dispatch no further ticks and cancel any pending
   wakeup. **Release the lock only if THIS session took it and its tick has since
   finished** — otherwise leave it exactly where it is: `release` is unconditional and
   cannot tell your lock from a sibling's, so releasing on the way out would delete a
   live holder's lock and re-open the double-dispatch. If you dispatched but are stopping before
   the notification arrives, say so and leave the lock — it ages out into step 1's
   case 2, the intended failure.

This guarantees **at most one PM tick at any moment**, with a `gap` pause between
ticks, regardless of how long a tick runs.

## Standing guardrails for each tick dispatch

- Honor the human gates **per the owning project's `autonomy`** (default `gated`):
  never promote `draft → ready` and never merge. A project may delegate a gate **only**
  where `AUTONOMY.md` exists and defines the mode — resolved by
  `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-autonomy.sh --bundle <bundle>`, which reads the
  **bundle root first** and then an installed **companion plugin**
  (`loopd-yolo@loopd`); exit 1 is absent. Then follow that
  file exactly, including its preflight. **No `AUTONOMY.md` ⇒ every project is
  `gated`** and the field is inert. When `autonomy` is unset, act as `gated`.
- Reconcile doc `status:` against live `gh`/`git` before acting; act only on deltas.
- **Dispatch only this clone's human's work.** On a shared instance,
  `${CLAUDE_PLUGIN_ROOT}/scripts/task-owner.sh <task-path>` decides, and **exit 0 is the only clearance** —
  exit 1 (someone else's) and exit 2 (cannot answer) both refuse. Resolution: task
  `owner:` → project `owner:` → tracked `defaultOwner` → unowned; then compare against
  this clone's `ownerGithubUser` (local file first). `defaultOwner` is **not** locally
  overridable. **With none of them set, every task is this clone's.** It gates
  **dispatch only** — never promotion, never a commit, never the KB — and it is not a
  lock. `AWAITING.md` is the one artifact that narrows to this human's decisions; the
  tick report still names the other human's work.
- **The tick syncs the bundle around its own work — when there is a remote.** It pulls
  `--rebase` (never `--autostash`, which can exit 0 with a conflicted tree)
  before it re-derives anything from disk, defers the pull to step 8 when the tracked
  tree is dirty, and pushes right after it commits; a bundle with no `origin`
  does neither, silently. A pull conflict **stops the tick**: it aborts the rebase, writes nothing,
  and reports the contested paths — a tick never resolves contested state between two
  humans on its own. And nothing here ever force-pushes a shared bundle.
- **The same blocker twice ESCALATES — it is never re-dispatched.** After each round run
  `${CLAUDE_PLUGIN_ROOT}/scripts/stall-counter.sh record <task-doc> --blocker "<blocker>"`
  (add `--progress` when the PR moved — a new commit or a new review thread — which resets
  the counter); its **exit 1** means the cap is reached, so run `… escalate <task-doc>`
  instead of dispatching and put the line it prints in `AWAITING.md`. The cap is
  `maxStallRounds` in `instance.config.json` (**absent ⇒ 2**). **A spawn the host
  refused is not a round and is never recorded** — no agent ran (step 3).
- **An answered question is MOVED, never deleted** — from `open_questions` into
  `answered_questions`, one flat line `<ISO 8601> by <login> · <the entry verbatim>`,
  the login from `${CLAUDE_PLUGIN_ROOT}/scripts/decision-stamp.sh` (`SCHEMA.md` →
  "Decisions name the human"; an `advisor:` entry the loop wrote carries no `by`). `open_questions` must still empty — that is the promotion signal; an
  entry left in both lists blocks the draft forever.
- Concurrency cap: **at most `maxAgentsInFlight` role agents in flight**, a still-running
  `plan-architect` critique counting as one (`tick-steps/step-2-refine-drafts.md`) — resolve
  with `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-max-agents.sh` (local file first, tracked second; prints
  nothing and exits 1 when neither sets it — fall back to 4 then, the seeded, measured
  default per SCHEMA.md). Each agent uses its own worktree under `worktreeRoot`
  (absent, `<reposRoot>/_wt`) + a **private package store** (e.g. `pnpm install
  --store-dir <worktree>/.pnpm-store`) and **pushes early** — never two installs
  against the shared store at once.
- A LIVE tick may also dispatch the **`cataloguer`** (`loopd:cataloguer`) after
  reflecting merges — read-only on product repos, writes only to `knowledge/`,
  **counts toward the cap**, **throttled to one per tick**, never promotes or merges.
- **Every role-agent dispatch is namespaced `loopd:<role>`** — all eight of them.
  The three USER-level agents `init-bundle.sh --config` installs (`code-architect`, `deep-bug-scan`,
  `plan-architect`) are not plugin agents and stay bare.
- Commit hygiene in this repo: commit only your own changed files, by explicit path
  (never `git add -A`), via
  `${CLAUDE_PLUGIN_ROOT}/scripts/commit-as.sh project-manager "<msg>" --stage -- <path>...`
  — `--stage` stages exactly those paths first; never `--no-verify` in target repos.
- **Worktree hygiene, two scripts.** `${CLAUDE_PLUGIN_ROOT}/scripts/reclaim-worktree.sh <task-path>`
  removes the ONE worktree a `done` task recorded, and only when every URL in its `pr:` has
  MERGED — step 5 runs it per task; exit 1 is a refusal to record, never to retry around.
  `${CLAUDE_PLUGIN_ROOT}/scripts/prune-worktrees.sh` (≤ once per tick) **reports only —
  it never deletes anything**; surface its `REMOVABLE`/`RECLAIMABLE` sets as a human
  job. **Run it only when your in-flight count is zero** — the `PRUNE_ACTIVE_MINUTES`
  mtime veto (default 120) is a backstop, not the guard, and does not apply to reclaim.
- **Project close is human-gated.** The PM only *proposes* closing (all tasks
  terminal); the human confirms (or runs `/close-project`). The folder step is always
  `${CLAUDE_PLUGIN_ROOT}/scripts/close-project-folder.sh <slug> --apply`, never a hand-written `rm`;
  `retain: true` keeps the folder as the record (`SCHEMA.md`). Never close
  autonomously.
- Return a tight summary: live-vs-docs deltas, dispatched/reflected, in-flight count,
  and what awaits the human.

## Notes

- One serial loop per session — and **one active loop per clone**: don't start a
  second session looping the same working tree. Two humans on one bundle from two
  clones is supported (see the standing facts). To change the gap: stop, then
  `/dispatch <gap>`.
- **The dispatch lock is `.tick-lock` at the instance root** — gitignored, per clone,
  written by step 1 and released in step 2 by the session that took it. The tick claims
  it (step 0.5, `--as tick`, recorded in `.tick-lock.claim`) and releases nothing.
  `${CLAUDE_PLUGIN_ROOT}/scripts/tick-lock.sh status` reads it without touching it (for a human, never this
  launcher); `TICK_LOCK_STALE_MINUTES` (default 120) sets when step 1 stops waiting
  and asks. A missing lock is never an error.
- **Starting the loop prints a handful of lines, not a screen**: a failed
  precondition, one line naming the gap, and that the tick is dispatched. If a start
  scrolls the terminal, the launcher did work that belonged in the tick — move it
  there; do not quiet it in place.
- A tick with nothing to do is a fast no-op — the gap keeps idle cycles cheap — and
  **its whole report is one line naming the next check** (`project-manager.md` step
  0.9). Pass the gap on: the tick puts it in `tick-delta.sh check --gap <gap>` so
  that line can say when you will next hear from the loop.
- Each tick refreshes `AWAITING.md` **only when that file already exists, and only
  when the tick changed something** (a `noop: true` tick leaves it alone rather than
  restamping its `Last refreshed:` line); deleting
  it turns the queue off for good (the loop never recreates it); `touch AWAITING.md`
  turns it back on.
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
