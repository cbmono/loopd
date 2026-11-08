# Conventions detail: dispatches and rounds

Detail for `../CONVENTIONS.md` — moved there verbatim, so the core stays short. Open a section only when the core's pointer to it names a trigger that applies. **The core wins on any disagreement**; fix this file to restate it.

### Resolve a dispatched agent's model with resolve-model.sh

- **Resolve a dispatched agent's model with `scripts/resolve-model.sh <agent>`, never from
  memory.** `roleTiers`/`models` in `instance.config.json` govern which model each agent
  runs on — but they used to exist only as prose in five documents, so they governed the
  dispatch paths whose markdown happened to mention them and nothing else. Measured
  2026-08-28: three separate sessions each reported, independently, that they had
  dispatched agents all day without consulting the file. One of them had passed the right
  alias anyway, by remembering it — which is the same fragility with a luckier outcome.
  The script prints the alias, or prints nothing and exits 1 when the agent has no entry.
  **It is not quiet about that: it prints why on stderr — report that line to the human,
  then inherit the session model and do not guess.** Exiting silently was the failure
  shape rather than the fallback: an unresolved role looks exactly like a resolved one at
  the call site, so every role can run on the wrong tier with nothing anywhere saying so.
  `/loopd:init` seeds `models`/`roleTiers` into `instance.config.local.json`, which is where
  the fix goes. This applies to **every** dispatch, including an ad-hoc dispatch from a
  main session, which is exactly the path the prose never reached.
  **Effort is the second axis, read the same way: `scripts/resolve-effort.sh <agent>`.** It
  prints a level from `roleEffort` (`low|medium|high|xhigh|max`) — pass it as the Agent
  tool's `effort:` or `claude --bg --effort` — or nothing, exit 0, when the agent has no
  entry: then pass none, and an Agent-tool spawn falls back to the agent's frontmatter
  `effort:`. Exit 1 is an unknown level; report its stderr line and pass none.

### Anything you background must be reaped by something that outlives YOU

- **Anything you background must be reaped by something that outlives YOU.** A rule about
  the whole CLASS — every child you put in the background, whatever it happens to be: a dev
  server, a watcher, a file-watch probe, a long build, a load generator you wrote to
  reproduce a flake. It is this repo's ONLY rule about backgrounded children, and it
  subsumes the dev-server teardown rule that used to stand here: that one named servers, so
  it had nothing to say about the 34 spinners below. **A rule that enumerates kinds of
  process is a rule that misses the next kind**, which is why this one names none.
  **It does not ban backgrounding.** Background the long build, the dev server, the
  deliberate load generator — that is legitimate work and none of it is being taken away. A
  "fix" that deletes the `&` satisfies nothing here: what is required is a REAPER, not
  abstinence.
  **The bound goes on the CHILD ITSELF, and that part is not optional.** Measured
  2026-08-31: an agent generating CPU load to reproduce a flaky suite started ten
  `(while :; do :; done) &` spinners, captured their pids, and put the `kill` at the end of
  the script. Its shell died before that line ran — **34 orphans across three batches, every
  one reparented to `ppid 1`**, at ~24% of a core each, running 3, 15 and 16 minutes with
  nothing left on the machine that could ever reap them; load average 310, 0% idle. A
  `trap … EXIT INT TERM` needs you alive to fire and a process-group kill needs someone left
  to issue it, so **both were already defeated** by the time anyone looked. Add them if you
  like; neither may ship as the whole answer. Same class with a slower fuse: two `pnpm dev`
  servers found still running after **2 days 16 hours** and **2 days 13 hours**
  (2026-08-27), from worktrees whose tasks had merged long before.

  ```sh
  # bg_bounded <seconds> <command…> — a bound that still holds when this shell is gone.
  bg_bounded() {
    local secs=$1; shift
    if command -v timeout >/dev/null 2>&1; then
      timeout "$secs" "$@" &                       # coreutils. NOT on a stock macOS
      return
    fi
    "$@" &                                        # no timeout: bound it with a watchdog
    local child=$!
    # A SIBLING, so it fires whether or not we live. `>/dev/null` is not tidiness — see below.
    ( sleep "$secs"; kill "$child" 2>/dev/null ) >/dev/null 2>&1 &
  }
  ```

  The watchdog is a sibling rather than something this shell does later, and that is the whole
  trick: it is already detached when we are killed, and `sleep` bounds the watchdog itself, so
  nothing is left running either way. It outlives a child that finishes early by up to `secs`
  — so keep the bound in minutes, not hours — and `kill`ing it once you have reaped the child
  is a fine ADDITION.
  **Redirect the watchdog's stdio, and know why:** killing `( sleep N; … ) &` kills the
  SUBSHELL and leaves the `sleep` behind, and a `sleep` that inherited your stdout holds the
  pipe open — so a caller reading your output with `$( … )` (this repo's own CI loop does)
  blocks for the rest of the bound on a job that finished. Measured while writing this rule:
  a harness that took 15 seconds took 99.

  A loop you wrote yourself needs no watchdog at all — carry the deadline inside it:
  `end=$(( $(date +%s) + 300 ))`, then `while [ "$(date +%s)" -lt "$end" ]; do …; done`.
  **Two readers, because what stood here was prose and prose did not stop this:**
  `tests/background-teardown.test.sh` fails the build on a background spawn in this repo's
  own `scripts/` and `tests/` that carries no bound (an allowlist entry has to state its
  reason), and the welcome skill’s `check` (`/loopd:welcome check`) carries a row naming every orphaned process whose cwd is
  under `worktreeRoot` — the one line that would have printed all 34. `prune-worktrees.sh`
  still reports a worktree with a live process attached. All three only ever REPORT, so the
  teardown is yours, and your report still says what you stopped.

### A dispatch is not finished until its artifact exists

- **A dispatch is not finished until its artifact exists — check, don't believe the
  report.** When an agent you dispatched reports back, run `scripts/check-dispatch.sh
  <task-doc>` before you act on what it said. It reads four things and judges nothing
  else: did `status:` advance, does `pr:` name a URL, does that pull request exist, and is
  a PR opened from its `branch:` missing from `pr:`.
  Exit 0 is the only clearance — exit 1 is the parked signature (still `ready`/`in-progress`
  with no PR), 3 a `pr:` the host does not resolve, 4 a record contradicting itself, 5 a
  PR opened from its `branch:` that `pr:` does not list, 2 a question it cannot answer. **Exit 0 does not mean "there is a PR":** a task the agent left
  `blocked` or `cancelled` with no PR also clears, because no artifact was due — read the
  stated reason rather than reading a stopped task as a verified artifact. Measured 2026-08-28: two agents finished their work, committed
  it — one had already pushed — then ended their turns waiting on a background job that
  nothing was left running to notify, and **reported as completed** with no PR open. The
  wall-clock rule missed it (one parked at **16 minutes**), the review-round cap missed it
  (neither reached review), and the completion notification *was* the failure. Asking
  whether the PR exists takes two seconds and nothing was doing it. This applies to
  **every** dispatch, including an **ad-hoc** dispatch from a main session — the path with
  no coverage at all today, because no tick ever reads it.
  **It is report-only, and that is the point: a non-zero verdict is never a licence to
  re-dispatch.** Re-running a task sequence that already finished is the most expensive
  failure this loop has (`/loopd:dispatch` step 2), and the usual recovery is one message to the
  parked agent telling it to open the PR on what it already has.

### Wide work: fan out only if you actually can

- **Wide work: fan out only if you actually can — most of you can't.** For genuinely wide,
  *independent* work a parallel fan-out beats grinding serially (find the real edges → fan
  out → verify → synthesize), but check your `tools:` list before you plan around one.
  **No role agent's allowlist contains `Workflow`**, so the `Workflow` idiom is dead for
  every one of you and is deliberately not written here as an option — granting it is a
  standalone decision with its own cost, not something a convenience clause settles. Only
  `qa-reviewer` holds `Agent`, so only `qa-reviewer` can fan out at all, and it does so by
  dispatching several agents in parallel. `software-engineer`, `devops-engineer` and
  `failure-analyst` hold neither: **for you, wide work is sequential**, and that is the
  intended behaviour rather than a gap to route around — say so in the PR body and lean on
  the PR-size heuristic above if the result is large. Whoever *does* fan out: **read-only**
  fan-out (review, audit, research, code-navigation) needs **no worktree isolation**
  (nothing writes) but still obeys the instance's concurrency/resource limits (the
  `maxAgentsInFlight` cap) — it does **not** license unlimited dispatches; a **write**
  fan-out must *also* give each subagent its own worktree — never parallel writes to a
  shared clone/worktree (the same collision the per-task isolation rule prevents). Skip it
  for small/sequential work (pure overhead). `/loopd:dispatch` stays serial — a fan-out lives
  *inside* a task, never at the loop level.

### A subagent works ONE task

- **A subagent works ONE task, and is resumed only for that task's next round.** Waking a
  completed agent with a message reuses its context, and reuse is right exactly while that
  context is about *this* work. **This is the one statement of the rule.** Everywhere else
  cites it and carries at most its one line, word for word, so the copies cannot drift:

  > same task and same PR ⇒ resume; anything else ⇒ dispatch fresh; a tick ⇒ never

  In full:

  | What you would hand it | |
  |---|---|
  | The **same task**, the **same PR**, the next round — review findings, a re-rebase, "open the PR on what you already have", the round after the human did the jobs a stopped session left them | **RESUME.** It knows this repo squash-merges and which `--onto` base to use; a cold agent re-derives that at real cost. |
  | A **different task**, a **different PR**, or an unrelated ad-hoc job | **DISPATCH FRESH.** |
  | A `project-manager` **tick** | **NEVER RESUME — no exception, no "unless".** |

  Measured 2026-08-30: one `software-engineer` resumed three times — two rebases and then
  a round of review findings — ended carrying 163k tokens; a resumed tick produced two
  concurrent ticks. The tick case is absolute because a resume never passes through the
  launcher that takes the dispatch lock, and because it re-enters a loop whose state has
  moved on.

  **Which half of this has a reader, said plainly rather than left to sound enforced.**
  The tick half is CHECKED, and the reader is named so you can go and look: the control
  panel's `scripts/tick-lock.sh` refuses a tick acquire that finds no lock (exit 4) — no
  lock means no launcher, and no launcher means nobody dispatched that tick. Nothing on
  your path reads that file; only the loop and the tick do. The same-task half, by
  contrast, is NOT checked and cannot be, because nothing can see the intent behind a
  message; it is held by whoever dispatches, which is why it is written here and in the
  dispatchers' own instructions instead of being asserted somewhere no one reads. **Most readers of this file dispatch nothing** (see the
  wide-work bullet above), so for you it is the rule your dispatcher follows, and it
  cashes out as one thing: a message picking up **your own task's** next round is
  legitimate work; anything else should have been a fresh agent, and saying so is better
  than quietly absorbing it.

  **No "delete the agent" primitive exists and none is wanted** — agents complete on their
  own, so resumption is the only lever there is. That is why this rule is about resumption
  and not about how long an agent lives.

### A round that ends on a failed check appends ONE line to do_not_repeat

- **A round that ends on a failed check or a reviewer refusal appends ONE line to the
  task's `do_not_repeat:` BEFORE you stop.** Anything short of a green PR — a check you
  could not get green, a reviewer refusal you did not take, a blocker — and the last thing
  you do before writing `# Result` is
  `scripts/do-not-repeat.sh append <task-doc> --line "<approach> — <evidence>"`.
  **One line, at most 200 characters** (the script folds whitespace and truncates): the
  approach you took and the evidence it failed on, not the story of the round —
  `"widened the ERE to allow closed ATX — pr-body-shape.test.sh 40/2, rows 3 and 7 still refused"`.
  **The next dispatch receives those lines verbatim in its brief**, which is the only thing
  standing between a fresh agent and your wall: it has no memory of your round, and
  `stall_count` says how MANY rounds, never what was tried. **The evidence is the check,
  never its output** — no pasted log, no secrets, no PII, same rule as `last_blocker`.
  The list caps at 10: at the cap the script refuses (exit 1) and the `project-manager`
  folds the oldest into `# Notes`. A round that ends green appends nothing.

### Write back the result

- **A task's `open_caveats:` outranks what you were told, and it holds `done`/`cancelled`
  until evidence clears it** — never your own conclusion that the caveat no longer applies
  (`SCHEMA.md` → the field; the bundle validator errors on that write while the list is
  non-empty). It is not a promotion gate and never blocks your round.

### A round's final message is a report, not an ask

- **A round's final message is a report, not an ask** — `software-engineer`,
  `devops-engineer` and `qa-reviewer`, the roles a tick runs as `claude --bg` sessions.
  It says what exists — the PRs, the criteria tally, the task note you wrote — and ends
  with **one status line**. **Anything the human must decide or provide goes in the task's
  `open_questions`**, the only field that reaches `AWAITING.md`; `# Notes` is for the
  record. A final message nobody reads is an ask that is lost. Measured 2026-10-15, as a
  correlation: every round whose final message addressed the human ended `blocked`, every
  one that reported an artifact ended `done`. Unconfirmed; the CLI's verdict is read
  through `agent-sessions.sh state`, never predicted. **A round that ends asking anyway is
  not lost**: the CLI files the jobs it names as the session's `needs`, the tick shows them
  in `AWAITING.md` as one hand-off (`Q<n>: do:` on the task), stops the session, and
  resumes it — same task, same PR — with the human's answer (measured 2026-10-21).

### Commit your task-doc edit immediately after each write

- **Commit your task-doc edit immediately after each write — never at the round's end.**
  `cd <bundle>`, then `scripts/commit-as.sh <role> "<msg>" --stage -- <task-doc>`. An
  uncommitted doc is a dirty bundle tree, and every tick that sees one defers its pull:
  one session edited its doc at 15:13 and was still working two hours later. `commit-as.sh`
  refuses outside the bundle (exit 2), so a call from your worktree cannot commit into the
  target repo as your role, and refuses while a rebase is in progress (exit 2): **retry once
  on your next write, or before your final message if there is none, then leave it.**
  Nothing else commits it for you.
