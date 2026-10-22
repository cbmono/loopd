#!/usr/bin/env bash
#
# tick-lock.sh — the one-tick-at-a-time guarantee, as a file instead of a memory.
#
#   Usage: tick-lock.sh acquire [--as launcher|loop|tick] [--agent <id>] [--claimant <id>]
#                                       [--instance DIR]
#          tick-lock.sh release [--instance DIR]   ·   status [--instance DIR]
#          tick-lock.sh mint   — prints a fresh claimant id, tick-<UTC yyyymmddThhmmssZ>-<4 chars>
#
# WHY THIS EXISTS. `/<plugin>:dispatch` promises at most one PM tick at a time. Until this script,
# that promise rested on TWO things, and neither is a mechanism:
#
#   1. THE LAUNCHING SESSION REMEMBERING IT DISPATCHED. `/<plugin>:dispatch` step 4 defines "still
#      in flight" as "this session dispatched a tick and has not yet seen its
#      notification" — answered from session history, which a compaction, a `--resume` or
#      a human asking "what's next?" all discard. Measured 2026-08-29 in a real instance:
#      two ticks ran concurrently for ~34 minutes, doing the same refinement work twice.
#      The session that caused it said so plainly — "I dispatched a second tick before the
#      first one's completion notification arrived."
#   2. THE TICK'S OWN LEDGER CHECK (`project-manager.md` step 0.5), which is real and
#      well-written and CANNOT close this window, because it runs INSIDE the tick:
#
#        launcher dispatches A ──► A: step 0 `git pull` ──► A: 0.5 checks ──► A writes "open"
#                            ▲
#              a tick dispatched anywhere in here sees NO open entry
#
#      Seconds to minutes in which the ledger truthfully reports nothing running. That
#      ledger is untouched by this script and stays the TICK's own record; this is a
#      second, earlier gate, at the only moment anybody knows "I am dispatching right now".
#
# THE CHECK AND THE WRITE ARE ONE SYSCALL, WHICH IS THE POINT. `acquire` creates the lock
# under `set -o noclobber` — an `O_EXCL` create. There is no read-then-write to interleave,
# so the window that defeated the ledger check does not exist here even in principle. That
# is also why `status` exists as a SEPARATE subcommand and why the launcher must never call
# it: `status` then `acquire` would rebuild the very TOCTOU race this replaces.
#
# TWO PATHS MAKE A TICK RUN, AND ONLY ONE OF THEM MAY. The launcher takes the lock
# immediately before it dispatches, and that stays — only the launcher knows "I am
# dispatching right now", which is the window above. But a tick can also START WITHOUT
# PASSING THROUGH THE LAUNCHER: `SendMessage` wakes a completed agent directly, so no
# `acquire` runs, nothing is written, and a later `acquire` by a genuine dispatch correctly
# reports the lock free — because it is. Measured 2026-08-30, about an hour after this file
# merged: a resumed tick and a dispatched tick ran concurrently and the human, not the
# machinery, spotted it. The guard behaved exactly as designed and the outcome was still two
# ticks. A mechanism placed on the path you were thinking about is not a mechanism on every
# path, and the second path is the one that bites because nobody audits it. So `--as tick`
# is a second acquire site, run by the tick itself — but it is a GATE, not a second way in.
#
# A TICK RUNS ONLY UNDER A LOCK THE LAUNCHER TOOK, SO `--as tick` NEVER CREATES ONE. No
# lock on disk means nobody dispatched you, because the launcher takes it in the same
# breath as the spawn — so you are a resumed tick, or one somebody started by hand, and
# both are REFUSED (exit 4). Until 2026-08-30 this path took a lock of its own instead:
# the resumed tick then RAN and the next genuine dispatch stood down. Exactly one tick
# ran, which was the property being defended, and it was the wrong one — a tick re-entering
# a loop whose state has moved on, carrying context from work that is already finished. A
# tick is the one thing that is never resumed, without exception; the rule for every other
# agent (same task, same PR, next round) is in CONVENTIONS.md, where its readers are.
#
# THE CRUX: A DISPATCHED TICK MUST NOT REFUSE ITS OWN LOCK. The launcher takes the lock and
# then spawns; the tick it spawned then finds a held lock that is ITS OWN. A tick that
# cannot tell that from a sibling's refuses on entry, and then EVERY dispatched tick
# deadlocks — a total outage of the loop, strictly worse than the concurrency bug being
# fixed. The distinction is one bit of state, and deliberately NOT a guess about elapsed
# time (a resume seconds after a dispatch would sail through) nor a nonce passed down the
# dispatch prompt (prose carried by a model is the class of mechanism that keeps failing
# here). It is this: a lock the launcher took has NOT YET BEEN CLAIMED BY A TICK, and a lock
# a tick is running under HAS.
#
#   .tick-lock        the lock. Taken by the LAUNCHER, and now only ever by it. Its clock
#                     and its staleness rule are unchanged; since 2026-09-06 it also
#                     records the per-tick id the launcher minted (`claimant:`), which is
#                     the ONLY place that id lives on disk.
#   .tick-lock.claim  the tick's claim on that lock, created with `O_EXCL` like the lock
#                     itself the first time a tick runs under it. It records WHOSE it is —
#                     see the next section, which is why it is no longer mere existence.
#
#   --as tick, no lock                  -> REFUSED (4). Nothing dispatched you, so you are
#                                          a resume: end the tick, take nothing, run none.
#   --as tick, live lock, unclaimed     -> the dispatch that spawned you. Claim it and
#                                          proceed; the LAUNCHER releases it, not you.
#   --as tick, live lock, PROVABLY your -> you are already running under it. Proceed,
#                     claim               unchanged: `re-entered:`, then the same
#                                          obligation line your first acquire printed.
#   --as tick, live lock, NOT yours     -> report and hold: dispatch nothing, adopt
#                                          nothing, end.
#   --as tick, live lock, claim that    -> exit 2. Both identities are printed and a HUMAN
#                     MIGHT be yours      decides. Only reachable on the DERIVED fallback:
#                                          a launcher-supplied id makes it a 0 or a 1.
#   --as launcher (the default)         -> unchanged in every respect: any live lock
#                                          refuses, claimed or not, and it never claims.
#   --as loop                           -> a launcher on a CLOCK. Identical in every
#                                          decision it makes; a HELD lock is reported in
#                                          ONE line on stdout instead of the launcher's
#                                          block on stderr. See the next section.
#
# `--as loop` — THE INTERVAL-DRIVEN LAUNCHER, AND WHY IT IS A MODE AND NOT A SECOND SCRIPT.
# `/loop <interval> /<plugin>:dispatch` is the documented way to run the cadence, and a
# clock knows nothing about tick length: most firings of a 10m loop land while a tick from
# an earlier firing is still running. So for this caller a held lock is the ORDINARY
# outcome, not an incident — and the launcher's HELD block (three to six lines on stderr,
# written for a human who typed a command and expected a dispatch) reads as a fault every
# time the clock ticks. Repeated six times an hour, that is how a working loop teaches its
# operator to stop reading its output.
#
#   tick in progress since 2026-09-05T10:22:04Z (project-manager, taken 12m ago) — nothing
#   to dispatch this pass.
#
# One line, and on STDOUT rather than stderr, because it is not an error: the pass did
# exactly what it should. Everything else about the mode is the launcher's, deliberately:
# it takes a free lock the same way and stays byte-silent when it does, and STALE, AHEAD OF
# THE CLOCK, UNREADABLE and an unwritable root all keep their loud stderr text and their
# non-zero exits — those need a human whether a clock or a person asked.
#
# THE EXIT CODE DOES NOT MOVE, AND THAT IS THE WHOLE OF THE SAFETY ARGUMENT. A held lock is
# still exit 1 here. `0 is the only clearance to dispatch` is the one invariant every caller
# of this file rests on, and a mode in which 0 sometimes meant "do not dispatch" would force
# the caller to tell the two apart by PARSING WHAT WAS PRINTED — a second, weaker reader of
# a signal the exit code already carries exactly. What makes the /loop PASS clean is not a
# zero from this script: it is that the skill defines exit 1 as an expected, non-escalating
# skip and ends the pass on it. See `skills/dispatch/SKILL.md` -> "Running it on a cadence".
#
# An `--as tick` acquire that proceeds prints `adopted:` on stdout, optionally preceded by
# `re-entered:`, and that is its only success — a tick never takes a lock of its own, so it
# never releases one either. The `--as launcher` path stays byte-silent, exactly as before.
#
# A CLAIM THAT CANNOT SAY WHOSE IT IS TELLS A TICK IT IS AN INTRUDER. Existence was the
# whole signal until 2026-08-30, and hours after that shipped a dispatched tick held and
# dispatched nothing, reporting a different tick — the claim it had found was its own:
#
#     taken   13:28:49Z   the launcher, immediately before spawning
#     claimed 13:29:33Z   the tick it spawned, on entry
#
# The contract was correct only while a tick acquired EXACTLY ONCE. Any re-entry — a second
# `acquire`, a `SendMessage` resume, a retry after a transient error — makes a tick
# indistinguishable from an intruder to itself. So the claim now records a CLAIMANT, and
# the claimed branch splits in two: your own claim is a re-entry and proceeds; anyone
# else's still reports and holds.
#
# THE NARROWER FIX WAS CONSIDERED AND DOES NOT HOLD, which is why the claimant exists at
# all. The tempting argument is: the launcher spawns exactly one tick per lock, so a
# claimed lock met by an `--as tick` caller must BE that tick, and genuine concurrency is
# better caught where two LAUNCHERS collide — which the lock already catches before any
# claim exists. The premise is true and the conclusion is false, because the concurrency
# this file was extended for has only ONE launcher in it: a resumed tick never passes
# through a launcher at all. Launcher takes the lock, dispatched tick A claims it, resumed
# tick R arrives — R meets A's claim with no second launcher anywhere in the sequence, and
# "claimed means it is you" would let both run. That is the 34-minute double-dispatch of
# 2026-08-29, reopened. The claimed branch has to stay; it only has to learn whose.
#
# WHERE THE IDENTITY COMES FROM, AND WHY NOT FROM THE FOUR OBVIOUS PLACES. It must be
# reproducible by the same tick on a later call — including across a resume, where the
# process is gone — and different between two concurrent ticks:
#
#   NOT `--agent`.      Both the launcher and the tick pass `project-manager`; it names a
#                       ROLE, and two ticks of one role are exactly the case to separate.
#   NOT elapsed time.   A resume seconds after a dispatch reads identically to a fresh
#                       intruder — the guess this file already refused once.
#   NOT a nonce in the  Not as anything this script DERIVES: prose carried by a model
#   dispatch prompt.    across an agent boundary is the failure class this design keeps
#                       being bitten by. It is DECLARED instead — see the next section,
#                       which prices what that costs.
#   NOT the process.    `$$`/`$PPID` are a new value on every call and gone on a resume.
#
# So there are three sources, and they fall into TWO TIERS, which is the whole of the
# mechanism:
#
#   DECLARED   `--claimant <id>`, then `TICK_CLAIMANT`. The caller states "this names THIS
#              TICK" — a promise, the way `--agent` is a promise. Two declared ids that
#              match are the same tick, and that is the only thing this file ever treats
#              as proof.
#   DERIVED    `CLAUDE_CODE_SESSION_ID`, read from the environment when nothing was
#              declared. It is whatever the runtime happens to export, and NOBODY promised
#              it is per-tick. See below: it is not.
#
# THE RUNTIME'S ID NAMES A SESSION, NOT A TICK — MEASURED, NOT ASSUMED. On 2026-08-30 a
# parent session and a subagent it dispatched were read side by side:
#
#     parent    CLAUDE_CODE_SESSION_ID=aaf01a1c-fc30-4e96-99e9-a2c43733c10f
#     subagent  CLAUDE_CODE_SESSION_ID=aaf01a1c-fc30-4e96-99e9-a2c43733c10f
#
# Identical, character for character. Every tick one `/<plugin>:dispatch` session starts carries the
# same value, so as a positive signal it is worthless — and worse than worthless, because
# the sequence it gets wrong is the exact one the claimed branch was kept for: launcher S
# dispatches tick A, A claims, S resumes tick R, and R reads A's claim as its own. That is
# the 34-minute double-dispatch of 2026-08-29, waved through by the guard meant to catch
# it. `CLAUDE_CODE_CHILD_SESSION` does not rescue it (`1` on both sides). A per-agent id
# DOES exist on disk — see "THE PER-TICK IDENTITY IS REACHABLE" below, which corrects the
# path this comment used to guess at — but nothing per-agent is exported to the shell, so
# there is no per-tick identity this script can read.
#
# THEREFORE THE TRUST IS ASYMMETRIC: A DERIVED ID MAY REFUSE, BUT MAY NEVER CLEAR. That one
# rule is what makes this safe, and it is the whole difference from the first attempt:
#
#   both sides DECLARED and equal  -> a re-entry. Proceed (exit 0).
#   the two ids differ             -> not yours. Hold (exit 1), as before claimants.
#   either side has no id          -> not yours. Hold (exit 1), as before claimants.
#   equal, but either side DERIVED -> CANNOT TELL. Exit 2, both ids printed, a human rules.
#
# The last row was the normal case until the launcher started declaring an id (next
# section); it is now the FALLBACK tier's answer. Exit 2 is deliberately not exit 0 and not
# exit 1. Not 0, because "the ids match" does not mean "you", and proceeding on it is the
# double-dispatch. Not 1, because "a DIFFERENT tick is already running" is a claim this file
# cannot support and stating it anyway is precisely what sent a tick home on 2026-08-30.
# Exit 2 is this script's existing answer for a lock it will not judge — the same answer a
# stale lock gets, for the same reason: surface it and let a human decide. Note which row
# does NOT move: two DECLARED ids that DIFFER stay exit 1, `theirs`, exactly as before.
#
# THE LAUNCHER SUPPLIES THE ID — DECIDED 2026-09-06; the reasoning is in docs/operations.md.
# The launcher mints one per-tick literal, passes it to its OWN acquire (so it lands in
# `.tick-lock` as `claimant:`, the only place on disk it lives — the launcher never writes a
# claim), and hands the same literal to the tick, which passes it at step 0.5. Both sides are
# then DECLARED, so a tick's second acquire is `mine` and exit 0 rather than the `maybe`
# above. It is the twice-refused nonce, accepted knowingly and bounded: ADOPT NEVER MATCHES
# THE ID, so a mis-copied literal costs a reported note and never a refusal. Declare nothing
# and nothing changes — no `claimant:`, the derived tier answers, `maybe` is still exit 2.
#
# WHICH SOURCE ANSWERED IS RECORDED IN THE CLAIM (`claimant-source: flag|env|session`), so
# a change of identity source is visible in the file rather than inferred from behaviour,
# and both ids are printed on every refusal. The one question an operator has here — "is
# that a real sibling, or is my own id not stable?" — must be answerable by reading the
# output, because it is the question that got this mechanism rewritten once already.
#
# AND IT DEGRADES TOWARDS THE OLD BEHAVIOUR, NEVER PAST IT — IN BOTH DIRECTIONS. Identity
# ABSENT (the variable unset, or holding something that is not a plain id) means no
# `claimant:` is written and no claim matches: exactly what this script did before, and the
# refusal says which side was missing instead of leaving a human to wonder. Identity
# COLLAPSED — two ticks resolving to ONE id — is the direction that actually hurts, because
# a false match would PROCEED, and it is closed by the asymmetry above rather than by hoping
# it does not happen. There is no input to this file, environment or flag, that turns a
# claimed lock into a dispatch unless a caller declared a per-tick identity and it matched.
#
# THE CLAIM IS PART OF THE LOCK, NOT A SECOND LOCK. It carries a timestamp for a human to
# read, and that timestamp is NEVER a second staleness clock: "is this stale?" is computed
# from `.tick-lock` alone, exactly as before, so claiming cannot refresh a lock's deadline.
# The claimant does not change that and is deliberately checked LAST — a lock that is stale,
# future-dated or unreadable gets that answer even for the tick whose claim it is, because
# recognising yourself is not a licence to run past a deadline a human has to rule on.
# `release` removes both, and nothing else removes either.
#
# WHAT THIS DOES NOT CLOSE — STATED RATHER THAN LEFT TO BE DISCOVERED, AND MEASURED RATHER
# THAN CALLED SMALL. Two ticks can still swap places inside the launcher's own DISPATCH
# WINDOW: the interval between the launcher taking the lock and the tick it spawned claiming
# it. A resumed tick reaching its `acquire` in that window meets a live UNCLAIMED lock —
# which is exactly what a fresh dispatch looks like — so it adopts and runs, and the genuine
# tick then holds. Exactly one tick runs, which is the property that matters, but `/<plugin>:dispatch`
# step 2 releases that lock when its own (held) tick reports, freeing a lock the resumed
# tick is still running under.
#
# THE WINDOW IS NOT MICROSECONDS, AND AN EARLIER DRAFT OF THIS PARAGRAPH IMPLIED IT WAS.
# Measured twice in a live instance on 2026-08-30, hours apart, on two unrelated dispatches:
#
#   taken       claimed     window   the tick's transcript was created at
#   16:00:11Z   16:00:58Z   47s      16:00:38Z  (spawn 27s in, claim 20s after that)
#   18:18:30Z   18:19:11Z   41s      18:18:56Z  (spawn 26s in, claim 15s after that)
#
# FORTY-SEVEN and FORTY-ONE seconds, covering the spawn and everything the tick does before
# it reaches step 0.5. The previous wording said "the seconds between" and called this "the
# rarer half of an already rare race"; neither adjective had a measurement behind it, and
# both are gone. Two numbers rather than one because the first could have been an outlier
# and is not: agent-spawn latency alone is 26-27s in both, so no reordering of the existing
# calls gets this under half a minute. The microsecond race in this file is a different one
# — `release`'s two `rm`s, below.
#
# IT IS NOT CLOSED HERE, AND SINCE 2026-09-06 THAT IS A DECISION AND NOT A GAP. Closing it
# is now one line — refuse an adopt whose declared id differs from the lock's — and that line
# will not be written: every dispatched tick would rest on one literal surviving a copy
# through a brief, and one mis-typed character would refuse EVERY tick, the total outage this
# file calls strictly worse than the bug. The other two remedies are unchanged:
#
#   VERIFYING THE CLAIMANT BEFORE RELEASING means asking `release` who is calling, which an
#   override must never do. `release --as tick` is exit 3 precisely so `release` cannot be
#   scoped, and that is pinned by tests rather than left to discipline.
#
#   MAKING THE TICK ACQUIRE EARLIER shortens the window and cannot close it — the residue is
#   agent-spawn latency — and it would put the guarantee back into a model following prose.
#
# A per-tick identity read from the RUNTIME would have closed it without a literal to
# mis-copy. It was looked for on 2026-08-30, and the next two sections are what was found:
# it EXISTS, it is not usable from here, and both halves are written down so the search is
# not repeated.
#
# THE PER-TICK IDENTITY IS REACHABLE — MEASURED FROM INSIDE A DISPATCHED AGENT, NOT INFERRED.
# The question is not open any more, and the answer is not the one this file used to assume.
# EVERY PATH BELOW IS RECORDED, NOT READ: this script opens none of them and depends on none
# of them, which is reason 3 further down and not an oversight. They are stamped with the CLI
# version they were measured on so a reader can tell a stale note from a current one:
#
#   NOTHING PER-AGENT IS EXPORTED. Every variable in a dispatched agent's environment was
#   read. The ids among them are all SESSION- or PROCESS-POOL-scoped, none per-agent:
#     CLAUDE_CODE_SESSION_ID     the session (byte-identical to the parent's — a third
#                                independent confirmation of the measurement above)
#     CLAUDE_JOB_DIR             ~/.claude/jobs/<session-id-short> — the session again
#     CLAUDE_PID, and the socket path derived from it — a REUSED CLI process, not an
#                                agent: 19 live sockets against a handful of live agents
#     CLAUDE_CODE_CHILD_SESSION  `1` — a boolean, so it separates subagents from parents
#                                and never one subagent from another
#
#   THE ID EXISTS ON DISK, AND THIS FILE HAD ITS PATH WRONG. It is not `<session-id>/
#   subagents/<agent-id>` and not `<session-dir>/tasks/<agent-id>.output`; both guesses
#   predate anyone looking. Measured shape, CLI 2.1.251:
#     <session-dir>/subagents/agent-<agent-id>.jsonl        the transcript
#     <session-dir>/subagents/agent-<agent-id>.meta.json    {agentType, description,
#                                                            toolUseId, parentAgentId,
#                                                            spawnDepth, model}
#     $CLAUDE_JOB_DIR/state.json  ->  fan[] of {id, kind, label, startedAt}
#   The session dir needs no path-slug arithmetic. A glob on the one exported variable
#   reaches it: `~/.claude/projects/*/"$CLAUDE_CODE_SESSION_ID"/subagents`.
#
#   AN AGENT CAN FIND ITS OWN RECORD IN A SINGLE INVOCATION. The `tool_use` record carrying
#   a command is committed to the agent's own transcript BEFORE that command runs, so a
#   literal appearing only in this invocation's argv is already on disk when the process
#   starts. Measured: such a literal matched exactly 1 of 15 transcripts, and it was the
#   right one. No second tool call, no round-trip, nothing carried in a prompt.
#
#   AND THE ID SURVIVES A RESUME, which is the property a guard here would need. A resumed
#   agent APPENDS to its existing transcript — 4 of the 15 here do, each with a fresh user
#   turn arriving 394-1455s after the previous record, so they are resumes and not inline
#   injections — and one of the four is a PM TICK. The file name, and the first record's
#   timestamp, therefore stay the ORIGINAL dispatch. That is exactly the ordering fact the
#   window needs: a resumed tick's transcript predates the lock it is about to meet, and a
#   dispatched tick's does not.
#
# AND IT IS STILL NOT USED HERE — THIS SCRIPT CANNOT SELF-DERIVE A PER-TICK ID, AND SINCE
# 2026-09-06 THE LAUNCHER SUPPLIES ONE INSTEAD. Three reasons, each sufficient on its own,
# and all three are about DERIVING an identity in here; none of them touches a DECLARED one.
#
#   1. SELF-IDENTIFICATION NEEDS A PER-INVOCATION LITERAL, AND THIS SCRIPT'S ARGV HAS NONE
#      OF ITS OWN. It carries one only because a CALLER typed it: the launcher mints the
#      literal and both acquires pass it (see "THE LAUNCHER SUPPLIES THE ID" above), which
#      is a promise made outside this file — judged as DECLARED, never as read from disk.
#   2. WITHOUT ONE, THE FALLBACK IS AMBIGUOUS EXACTLY WHERE IT MATTERS. The remaining
#      discriminator is "the newest-mtime `project-manager` transcript", and in the window
#      this guard exists for there are two: the genuine tick, mid-spawn and being written,
#      and the resumed tick, whose own `tool_use` record was appended microseconds ago.
#      A guard that ties in its own motivating case is the stage-for-an-actor mistake again.
#   3. IT WOULD COUPLE A GENERIC TEMPLATE TO AN UNDOCUMENTED PRIVATE LAYOUT. This file reads
#      no org, repo or path literal by design. The layout above is one CLI version's
#      internals, and the evidence that it is not knowable from the outside is this file
#      itself: two documents guessed that path and BOTH were wrong.
#
# THE ORDERING-INVARIANT VARIANT WAS ALSO TRIED, AND IT IS THE ALREADY-REJECTED REMEDY IN A
# NEW COAT. "Adopt only if SOME project-manager agent was spawned after this lock was taken"
# needs no identity at all and is genuinely sound — but the table above prices it: the
# transcript appears 26-27s in and the claim lands 15-20s later, so it shrinks 41s to about
# 15s and CANNOT CLOSE IT. Shortens-but-cannot-close is precisely why "make the tick acquire
# earlier" is refused above, and a second mechanism earning the same verdict is not an
# improvement over a gap that is documented and shrinking. It is recorded so that the next
# reader prices it before building it.
#
# WHERE THIS LEAVES THE ASYMMETRIC RULE, STATED BEFORE ANY OF IT COULD BE USED. The
# transcript channel is DERIVED — read from the runtime, promised by nobody — so under the
# rule stated above it could only ever REFUSE, never clear. That direction happens to be the one
# the window needs, which is why it was worth measuring at all; the three reasons above are
# what stop it, not the asymmetry.
#
# AND THIS FILE STRICTLY SHRINKS THAT RACE RATHER THAN CREATING IT, which is why the gap
# does not block the refusal above. Before exit 4, a resumed tick meeting NO lock took one
# and ran — every time, with no window to hit. After it, the resume path gets through only
# by landing inside the dispatch window. The gap is open in both versions and smaller here.
#
# WHAT IS CHECKED HERE AND WHAT IS ONLY A CONVENTION, SAID PLAINLY SO NEITHER IS MISTAKEN
# FOR THE OTHER. Refusing a resumed tick HAS a reader and it is this file: no lock, no
# launcher, exit 4, driven by tests/tick-lock.test.sh. Two neighbouring rules have no
# reader anywhere, and must not be read as though this one covered them:
#
#   1. A resume that arrives INSIDE the launcher's dispatch window meets a live UNCLAIMED
#      lock and is, at that instant, indistinguishable from the tick the launcher took it
#      for — so it adopts and runs. That is the 47s/41s window measured above, and it is
#      the one way a resumed tick still gets through. Open, named, and not closed here.
#   2. Whether a resume of any OTHER agent is "the same task" cannot be seen from here or
#      from anywhere else: nothing can read a `SendMessage`'s intent. That half is a
#      convention held by whoever dispatches, written in CONVENTIONS.md and in the
#      dispatchers' own instructions because that is where its only readers are. It is
#      deliberately not implied to be enforced by anything.
#
# `release` REMOVES TWO FILES AND CANNOT REMOVE THEM AS ONE. Between `rm $CLAIM` and
# `rm $LOCK` the pair reads live-and-unclaimed, so a tick acquiring in that window adopts a
# lock that is about to be deleted underneath it. It is microseconds wide, it needs a human
# running the override at that instant, and the outcome is one tick running with no lock —
# recoverable, and strictly smaller than what a caller-aware `release` would cost.
#
# A SESSION THAT CHANGES ITS ID MID-TICK STILL DEADLOCKS, and that is the safe half. One
# conversation was observed running under two `CLAUDE_CODE_SESSION_ID`s in a day, because
# sessions fork and compact. A long tick that does so meets its own claim as a stranger and
# gets exit 1 — the pre-claimant behaviour, and the direction that costs a re-run rather
# than a duplicate dispatch. It is detectable rather than mysterious: the refusal prints
# both ids and the source that produced each, so "my own id moved" reads differently from
# "somebody else is running".
#
# LIVENESS IS DATA, NOT A JUDGEMENT. The lock carries an ISO-8601 UTC timestamp and the id
# of the agent that was dispatched, so "is this stale?" is computed from the file alone —
# never from session memory, `git log` or the tick ledger, none of which can answer it. A
# lock past `TICK_LOCK_STALE_MINUTES` (default 120) is NOT silently deleted and NOT
# silently treated as live: both are refused on purpose, because silent deletion re-opens
# the double-dispatch and silent adoption is the pressure that makes overriding a stalled
# loop tempting. It is surfaced — timestamp, agent, age, path — and a human decides.
#
# IT IS A PER-CLONE LOCK AND IT MUST NOT PRETEND OTHERWISE. The file is gitignored and
# lives in one working tree. Two humans sharing one bundle from two clones each dispatch
# independently, which is the SUPPORTED design (`/<plugin>:dispatch` → "Why serial"; SCHEMA.md →
# "Ownership on a shared instance"), and a committed or shared lock would break it. What
# stops those two loops dispatching the same TASK is `task-owner.sh`, not this.
#
# IT BOUNDS TICKS, NOT ROLE AGENTS. `maxAgentsInFlight` (via `resolve-max-agents.sh`)
# is the other concurrency limit and is untouched: it caps the role agents a tick dispatches.
# A held lock must never block those — nothing in the role-agent path reads this file.
#
# ABSENCE IS NEVER AN ERROR — A FAILED CREATE IS. No lock ⇒ `acquire` takes it and says
# nothing (exit 0), which is the launcher behaving exactly as it did before this file
# existed. `release` on a missing lock is a silent success too. But clearance to dispatch
# is the lock being CREATED, never merely being missing: an unwritable instance root is
# exit 3 and a refusal, because dispatching unguarded is the failure this replaces. The
# only silence this script breaks is a refusal.
#
# `release` IS UNCONDITIONAL, AND THAT PUTS AN OBLIGATION ON THE CALLER. It holds no
# session identity and cannot tell your lock from a sibling's — it is the human's
# override, and an override that asked who you were would not be one. So a caller must
# release only a lock IT took: an `/<plugin>:dispatch` session that skipped because another loop held
# the lock and then released it on the way out would delete a LIVE holder's lock and
# re-open the double-dispatch. `/<plugin>:dispatch` step 5 states that condition. The second acquire
# site does not relax this and has the simplest obligation there is: A TICK RELEASES
# NOTHING, EVER. The only lock it can be running under is one it ADOPTED, and that one is
# the launcher's to release when the tick reports; a tick that was refused (1, 2 or 4) has
# no lock to release either. A re-entry changes none of that: it re-prints the obligation
# its FIRST acquire printed, read back from `origin:` in the claim, so a tick that
# re-enters cannot turn an adopted lock into one it thinks it should release. `--as` and
# `--claimant` are `acquire` flags only; `release` takes neither, on purpose.
#
# IT READS NO CONFIG. `TICK_LOCK_STALE_MINUTES` and `TICK_CLAIMANT` are environment
# overrides in the shape `prune-worktrees.sh` already uses for `PRUNE_ACTIVE_MINUTES`;
# there is deliberately no `instance.config.json` key for either, so this adds nothing to
# the overridable-key surface. `CLAUDE_CODE_SESSION_ID` is read too and is not config
# either — it is the runtime's answer to "which session is calling", which is a strictly
# weaker question than "which tick is calling" and is treated as such above.
#
# Exit codes — 0 is the only clearance to dispatch:
#
#   0  acquire: the lock is now yours, dispatch.   release/status: nothing is held.
#   1  HELD — a live lock, younger than the staleness threshold. Do not dispatch. For
#      `--as tick` this means the claim on it is NOT YOURS as far as anything on disk can
#      show, INCLUDING two DECLARED ids that DIFFER: report and hold. Never a claim proved
#      to be yours — that is a 0 (`re-entered:`).
#      For `--as loop` it is the EXPECTED outcome of a firing that landed mid-tick: one
#      line on stdout, and the pass ends clean. Same code, because 0 still means dispatch.
#   2  needs a human, and these four only: the lock is STALE, dated in the FUTURE,
#      UNREADABLE, or claimed by an identity that MIGHT be yours (`maybe` — equal ids, at
#      least one DERIVED). Never a different id. Do not dispatch, do not delete it.
#   3  cannot answer: usage, a bad `--agent`/`--claimant`/threshold, or an unwritable root.
#      Never a silent pass — a lock nothing can write is a guarantee nothing is keeping.
#   4  REFUSED — `--as tick` with no lock: nobody dispatched you, so you are a resumed or
#      hand-started tick. End the tick. `--as launcher` never sees this: taking a lock
#      where there is none is exactly what a launcher is for.
#
# GENERIC PLUGIN FILE — ships inside the `loopd` plugin; nothing to edit per
# instance. It reads no org, repo or path literal.
#
# Verified by tests/tick-lock.test.sh.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]:-$0}")/bundle-paths.sh" || exit 2

LOCK_NAME="$AB_LOCK"
CLAIM_NAME="$AB_LOCK_CLAIM"

usage() {
  echo "Usage: $(basename "$0") acquire [--as launcher|loop|tick] [--agent <id>] [--claimant <id>]" >&2
  echo "                            [--instance DIR]" >&2
  echo "       $(basename "$0") release [--instance DIR]" >&2
  echo "       $(basename "$0") status  [--instance DIR]" >&2
  echo "       $(basename "$0") mint" >&2
  exit 3
}

cmd="${1:-}"; [ "$#" -gt 0 ] && shift
case "$cmd" in
  acquire|release|status) ;;
  mint)
    [ "$#" -eq 0 ] || usage
    # `tr` dies of SIGPIPE under pipefail, so the length is the check, not the status.
    suffix="$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom 2>/dev/null | head -c 4)"
    [ "${#suffix}" -eq 4 ] || { echo "tick-lock: cannot read /dev/urandom" >&2; exit 3; }
    echo "tick-$(date -u +%Y%m%dT%H%M%SZ)-$suffix"
    exit 0 ;;
  -h|--help) sed -n '3,9p' "$0"; exit 0 ;;
  *) usage ;;
esac

inst="."
agent="project-manager"
# `launcher` is the default because an unknown caller must get the STRICT behaviour: it
# refuses any live lock and never adopts one. Adopting is the narrow, named case, so it is
# asked for explicitly — a default that adopted would hand the dangerous branch to every
# caller that had not thought about it.
as="launcher"
as_given=no
claimant=""
claimant_given=no
while [ $# -gt 0 ]; do
  case "$1" in
    # `[ $# -ge 2 ]` before every `shift 2`: a bare trailing flag leaves one argument and
    # `shift 2` then FAILS WITHOUT SHIFTING, which with no `set -e` spins this loop
    # forever on the same argv — the bug resolve-model.sh hit and resolve-max-agents.sh
    # records.
    --instance)
      [ $# -ge 2 ] || { echo "tick-lock: --instance needs a directory" >&2; exit 3; }
      inst="$2"; shift 2 ;;
    --agent)
      [ $# -ge 2 ] || { echo "tick-lock: --agent needs an id" >&2; exit 3; }
      agent="$2"; shift 2 ;;
    --claimant)
      [ $# -ge 2 ] || { echo "tick-lock: --claimant needs an id" >&2; exit 3; }
      claimant="$2"; claimant_given=yes; shift 2 ;;
    --as)
      [ $# -ge 2 ] || { echo "tick-lock: --as needs launcher, loop or tick" >&2; exit 3; }
      case "$2" in
        launcher|loop|tick) as="$2"; as_given=yes ;;
        *) echo "tick-lock: --as must be launcher, loop or tick, got: $2" >&2; exit 3 ;;
      esac
      shift 2 ;;
    *) echo "tick-lock: unexpected argument $1" >&2; usage ;;
  esac
done

# `release` is unconditional and `status` is read-only, so neither has a caller identity to
# take. Refused rather than ignored: a `release --as tick` that silently did nothing
# different would read as a scoped release, which is exactly what release must never be.
if [ "$as_given" = yes ] && [ "$cmd" != acquire ]; then
  echo "tick-lock: --as applies to acquire only ($cmd is unconditional)" >&2; exit 3
fi
if [ "$claimant_given" = yes ] && [ "$cmd" != acquire ]; then
  echo "tick-lock: --claimant applies to acquire only ($cmd is unconditional)" >&2; exit 3
fi

[ -d "$inst" ] || { echo "tick-lock: no such instance directory: $inst" >&2; exit 3; }
ab_ensure_dir "$inst"
LOCK="$inst/$LOCK_NAME"
CLAIM="$inst/$CLAIM_NAME"

# The agent id goes into the file verbatim, so it is constrained to what an agent id can
# actually be. Not politeness: an unconstrained value could carry a newline and forge a
# second field, which would make a lock say whatever the caller wanted it to say.
case "$agent" in
  ''|*[!A-Za-z0-9._-]*)
    echo "tick-lock: --agent must be a plain id ([A-Za-z0-9._-]), got: $agent" >&2; exit 3 ;;
esac

# WHO IS CALLING, in three sources of falling explicitness, printed as `<source> <id>` so
# that WHICH source answered travels with the answer — the two tiers are judged differently
# and a value with no provenance could not be. A DECLARED source that cannot be used is an
# error: a caller that named an identity and had it silently dropped would believe it was
# protected by a check that never ran. The DERIVED one is different — it is whatever runtime
# this happens to be under, so a value it cannot use leaves the claimant empty and the
# script behaves exactly as it did before claimants existed.
#
# `TICK_CLAIMANT=` (set but empty) is NOT a declaration and does not refuse: an empty
# variable is how a caller unsets one, and `--claimant ''` — which IS a declaration, of
# nothing — remains exit 3. That asymmetry is deliberate and is the only place the two
# declared sources differ.
claimant_resolve() { # -> "<flag|env|session> <id>", or "none " when nothing answered
  local c
  if [ "$claimant_given" = yes ]; then
    case "$claimant" in
      ''|*[!A-Za-z0-9._-]*)
        echo "tick-lock: --claimant must be a plain id ([A-Za-z0-9._-]), got: $claimant" >&2
        exit 3 ;;
    esac
    printf 'flag %s' "$claimant"; return 0
  fi
  if [ -n "${TICK_CLAIMANT:-}" ]; then
    case "$TICK_CLAIMANT" in
      *[!A-Za-z0-9._-]*)
        echo "tick-lock: TICK_CLAIMANT must be a plain id ([A-Za-z0-9._-])" >&2; exit 3 ;;
    esac
    printf 'env %s' "$TICK_CLAIMANT"; return 0
  fi
  # One value per SESSION — measured, see the header — so it is recorded and compared but
  # never believed as proof of "the same tick". Anything shaped unexpectedly is ignored
  # rather than refused, because a runtime that renames or drops this must not stop ticks.
  c="${CLAUDE_CODE_SESSION_ID:-}"
  case "$c" in
    ''|*[!A-Za-z0-9._-]*) printf 'none ' ;;
    *) printf 'session %s' "$c" ;;
  esac
}
# The `exit 3`s above run inside this command substitution's subshell, so they end only
# that subshell — the status is what actually refuses, and it is checked rather than assumed.
CLAIMANT_RESOLVED="$(claimant_resolve)" || exit 3
CLAIMANT_SOURCE="${CLAIMANT_RESOLVED%% *}"
CLAIMANT="${CLAIMANT_RESOLVED#* }"
[ "$CLAIMANT_SOURCE" = none ] && CLAIMANT=""
# Declared means a caller PROMISED this names one tick. Only a match between two promises
# is ever treated as proof; see "THE TRUST IS ASYMMETRIC" in the header.
claimant_is_declared() { # [source, default: this caller's]
  case "${1:-$CLAIMANT_SOURCE}" in flag|env) return 0 ;; *) return 1 ;; esac
}

# Refused rather than rounded, for the reason resolve-max-agents.sh refuses a bad cap: a
# threshold nobody can read is worse than one that says it does not know. `0` is rejected
# too — it would make every lock instantly stale, i.e. silently turn the mechanism off.
STALE_MINUTES="${TICK_LOCK_STALE_MINUTES:-120}"
case "$STALE_MINUTES" in
  ''|*[!0-9]*|0)
    echo "tick-lock: TICK_LOCK_STALE_MINUTES must be a positive integer, got: $STALE_MINUTES" >&2
    exit 3 ;;
esac
STALE_SECONDS=$((STALE_MINUTES * 60))

NOW="$(date -u +%s)"
# The two timestamps in a lock are ONE moment, not two `date` calls a second apart: the
# epoch is what staleness is computed from and the ISO string is what a human reads, and
# a reader who saw them disagree would rightly wonder which one to trust. BSD `-r` first,
# GNU `-d @` second, and a plain `date` only if a machine has neither.
epoch_to_iso() { # <epoch>
  date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u +%Y-%m-%dT%H:%M:%SZ
}
NOW_ISO="$(epoch_to_iso "$NOW")"

# --- reading a lock -------------------------------------------------------------------
# Only the FIRST occurrence of a key counts, and `#` lines are comments — the same reader
# discipline check-dispatch.sh uses, for the same reason: a repeated key must not be judged
# from the later value.
lock_field() { # <key> [file, default: the lock]
  awk -v key="$1" '
    /^[[:space:]]*#/ { next }
    !got && index($0, key ":") == 1 {
      v = $0
      sub(/^[^:]*:[[:space:]]*/, "", v)
      sub(/[[:space:]]+$/, "", v)
      print v; got = 1
    }' "${2:-$LOCK}" 2>/dev/null
}

# The claim's fields are for a HUMAN and for the refusal message. Only `claimant:` is ever
# judged, and only under the rule in the header; staleness and liveness come from
# `.tick-lock` alone, which is what keeps the claim from becoming a second clock.
claim_note() { # -> " — <agent> at <ts>", or empty when the file says neither
  local cts cag out=""
  cag="$(lock_field agent "$CLAIM")"
  cts="$(lock_field timestamp "$CLAIM")"
  [ -n "$cag" ] && out=" — $cag"
  [ -n "$cts" ] && out="$out at $cts"
  printf '%s' "$out"
}

# BOTH IDENTITIES, ALWAYS, ON EVERY REFUSAL AND IN `status`. Printing only the timestamp and
# the role left the one question an operator actually has — "is that a real sibling, or is
# my own id not stable?" — unanswerable from the output, and answering it by hand is what
# rewrote this mechanism once already. `<none>` is spelled out rather than left blank so a
# missing id cannot be mistaken for a formatting slip.
identity_lines() { # <indent>
  local owner osrc
  owner="$(lock_field claimant "$CLAIM")"
  osrc="$(lock_field claimant-source "$CLAIM")"
  printf '%syours: %s (%s)\n' "$1" "${CLAIMANT:-<none>}" "$CLAIMANT_SOURCE"
  printf '%sclaim: %s (%s)\n' "$1" "${owner:-<none>}" "${osrc:-<unrecorded>}"
}

# The launcher's minted id, written into the LOCK and nowhere else. DECLARED only: a derived
# id names the session that RAN the launcher, never the tick it is about to spawn. Nothing
# judges this field, but dropping a declared identity silently would leave a caller believing
# in a record that does not exist. Returns the write's status: an unfinished lock is a failure.
lock_claimant_line() {
  claimant_is_declared || return 0
  printf 'claimant: %s\nclaimant-source: %s\n' "$CLAIMANT" "$CLAIMANT_SOURCE"
}

# The tick's claim, created the same way the lock is: `O_EXCL`, so two ticks racing for one
# unclaimed lock cannot both win. A claim made by reading then writing would re-open, one
# layer down, the exact race `acquire` exists to close.
#
# `claimant:` is the one field a LATER call judges anything by, and it is written only when
# an identity was resolvable — an empty one is omitted rather than written blank, so a claim
# that cannot say whose it is says nothing instead of saying "nobody's", which the matcher
# below would otherwise have to special-case. `claimant-source:` travels with it because the
# two tiers are judged differently and because a SILENT change of identity source would
# otherwise have to be inferred from behaviour. `origin:` is not a judgement either; it is
# the obligation this tick was given, stored so a re-entry can be told the same thing rather
# than guessing. THIS VERSION ONLY EVER WRITES `adopted` — a tick no longer takes a lock, so
# there is no `took` left to record. The field stays, and `reprint_obligation` keeps reading
# it, because a claim already on disk when an instance updates was written by a version that
# DID: dropping the read would tell that tick to release nothing, and the lock under it is
# genuinely its own.
#
# NO TRAILING `:`. The old `{ …; [ -n "$X" ] && printf …; :; }` swallowed a failed write:
# out of disk, the claim would be truncated before `claimant:`, the group would still exit 0
# and the next tick would be told the claim "was written by hand". An `if` returns the
# `printf`'s own status, so a claim that could not be finished is a failed claim.
claim_exclusive() { # <origin: adopted — `took` is legacy-read only, never written>
  ( set -o noclobber
    { printf '%s\n' \
        "# The TICK's claim on the $LOCK_NAME beside it — written by the tick, never by the" \
        "# launcher. It records WHOSE the claim is, and from WHICH source that identity came:" \
        "# a later acquire that can PROVE it is the same tick re-enters and proceeds; anyone" \
        "# else holds; an identity that merely matches is exit 2 and a human's call." \
        "# NOT a second lock and NOT a second clock: staleness is computed from $LOCK_NAME" \
        "# alone. Removed with the lock by: tick-lock.sh release" \
        "timestamp: $NOW_ISO" \
        "epoch: $NOW" \
        "agent: $agent" \
        "origin: $1"
      if [ -n "$CLAIMANT" ]; then
        printf 'claimant: %s\nclaimant-source: %s\n' "$CLAIMANT" "$CLAIMANT_SOURCE"
      fi
    } > "$CLAIM"
  ) 2>/dev/null
}

# WHOSE IS THE CLAIM ON DISK? One of four answers, and only the first is a licence to run:
#
#   mine       both sides DECLARED an identity and they match — proof, so proceed.
#   maybe      the ids match but at least one side is DERIVED from the runtime, which names
#              a session and not a tick. Cannot be resolved here; a human resolves it.
#   theirs     the ids differ. Not yours as far as disk can show — hold.
#   unknown    one side or the other has no id at all — hold, as before claimants existed.
#
# `maybe` is the one that must never collapse into `mine`; see the header's asymmetry rule.
claim_attribution() {
  local owner osrc
  owner="$(lock_field claimant "$CLAIM")"
  osrc="$(lock_field claimant-source "$CLAIM")"
  if [ -z "$CLAIMANT" ] || [ -z "$owner" ]; then printf 'unknown'; return 0; fi
  if [ "$owner" != "$CLAIMANT" ]; then printf 'theirs'; return 0; fi
  if claimant_is_declared && claimant_is_declared "$osrc"; then printf 'mine'; return 0; fi
  printf 'maybe'
}

# Re-print the obligation the FIRST acquire printed, read back from the claim rather than
# re-derived — a re-entering tick must not be told it may release a lock it only adopted.
# `took` is unreachable for a claim this version wrote and is kept for one written before a
# tick was refused a lock of its own; see `claim_exclusive`. An `origin:` that is missing or
# unrecognised reads as `adopted`, which is the safe half:
# the cost of not releasing a lock you took is one stale lock a human clears, and the cost
# of releasing one you adopted is a live tick's lock deleted under it.
reprint_obligation() {
  if [ "$(lock_field origin "$CLAIM")" = took ]; then
    echo "took: $LOCK — this tick holds the lock; release it when the tick ends."
  else
    echo "adopted: $LOCK — the dispatch lock the launcher took before spawning this tick."
    echo "         It releases that lock when this tick reports; do not release it yourself."
  fi
}

# The refusal a tick gets when nothing dispatched it. Its own function because two places
# reach it — the ordinary check and the microsecond race in `acquire` — and a refusal that
# read differently in the two would send somebody hunting for a second cause.
refuse_unlaunched() {
  echo "REFUSED — NO DISPATCH LOCK: $LOCK does not exist, so no launcher took one for you." >&2
  echo "          A tick runs only under a lock the launcher took immediately before it" >&2
  echo "          spawned that tick, so arriving here means you did not come through the" >&2
  echo "          launcher — a SendMessage waking a completed tick is exactly this case." >&2
  echo "          A tick is the one thing that is never resumed: it would re-enter a loop" >&2
  echo "          whose state has moved on, holding context from work already finished." >&2
  echo "          End the tick: dispatch nothing, adopt nothing, open no ledger entry," >&2
  echo "          release nothing. To run a tick, run the loop command — it takes the" >&2
  echo "          lock and dispatches a fresh tick." >&2
  exit 4
}

# A failed claim create has the same two causes the lock's has, and they are the same two
# different answers: somebody holds it, or this root cannot be written. `acquire` already
# refuses to collapse those for the lock, and collapsing them here would report an
# unwritable instance as "another tick is running" — the one message nobody would debug.
unwritable_claim() { # exits 3 when the claim is missing AFTER a failed create
  [ -e "$CLAIM" ] && return 0
  echo "tick-lock: cannot write $CLAIM — the instance root is not writable." >&2
  echo "           Refusing to run the tick: a tick that cannot record its claim is" >&2
  echo "           invisible to the next one, which is the failure this file prevents." >&2
  exit 3
}

# BSD first, then GNU: `date -j` is macOS's and `date -d` is coreutils', each is an illegal
# option to the other, and this repo's suite runs on macOS while instances run on both.
# Only an all-digits answer is accepted, so a shell that "succeeds" while printing a usage
# banner cannot become a timestamp.
iso_to_epoch() { # <iso-8601 UTC>
  local out
  out="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null)" \
    || out="$(date -u -d "$1" +%s 2>/dev/null)"
  case "$out" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$out"
}

# The lock's age in seconds, or nothing when the file cannot answer. `epoch:` is preferred
# because it needs no parsing; `timestamp:` is the fallback so a hand-written lock carrying
# only the human-readable field still works.
lock_age() {
  local e ts
  e="$(lock_field epoch)"
  case "$e" in ''|*[!0-9]*) e="" ;; esac
  if [ -z "$e" ]; then
    ts="$(lock_field timestamp)"
    [ -n "$ts" ] && e="$(iso_to_epoch "$ts")"
  fi
  [ -n "$e" ] || return 1
  printf '%s' "$((NOW - e))"
}

human_age() { # <seconds>
  local s=$1
  if [ "$s" -lt 60 ]; then printf '%ss' "$s"
  elif [ "$s" -lt 3600 ]; then printf '%sm' "$((s / 60))"
  else printf '%sh%sm' "$((s / 3600))" "$(((s % 3600) / 60))"; fi
}

# Judge an EXISTING lock. Prints the verdict and returns the exit code the caller uses, so
# `acquire` and `status` cannot drift apart about what "stale" means.
judge_existing() {
  local ts ag age minted
  ts="$(lock_field timestamp)"
  ag="$(lock_field agent)"
  age="$(lock_age)" || age=""

  if [ -z "$ts" ] || [ -z "$ag" ] || [ -z "$age" ]; then
    echo "UNREADABLE: $LOCK exists but does not say when it was taken or by whom," >&2
    echo "            so whether a tick is running cannot be computed from it. Refusing" >&2
    echo "            rather than guessing. Read the file, then either fix it or run:" >&2
    ab_say_run "             " tick-lock.sh release >&2
    return 2
  fi

  # A lock dated in the future never ages out, so it would stall the loop forever in the
  # "held" branch. Slop of 60s absorbs ordinary clock drift; past that it is an anomaly a
  # human should see, not a lock to wait on.
  if [ "$age" -lt -60 ]; then
    echo "AHEAD OF THE CLOCK: $LOCK is dated $ts, which is in the future." >&2
    echo "                    agent: $ag" >&2
    echo "                    A clock change or a hand-edit does this. It cannot go" >&2
    echo "                    stale on its own — decide, then release it if it is dead." >&2
    return 2
  fi

  if [ "$age" -ge "$STALE_SECONDS" ]; then
    echo "STALE: $LOCK was taken $(human_age "$age") ago, past the ${STALE_MINUTES}m threshold." >&2
    echo "       timestamp: $ts" >&2
    echo "       agent:     $ag" >&2
    echo "       This is NOT deleted for you and NOT assumed dead: a tick that dispatched" >&2
    echo "       role agents can legitimately run long, and deleting a live tick's lock is" >&2
    echo "       the double-dispatch this file exists to prevent. Decide, then either wait" >&2
    ab_say_run "       or run:" tick-lock.sh release >&2
    echo "       (TICK_LOCK_STALE_MINUTES raises the threshold if your ticks are longer.)" >&2
    return 2
  fi

  echo "HELD: a tick is in flight — $LOCK, taken $(human_age "$age") ago by $ag ($ts)." >&2
  if [ -e "$CLAIM" ]; then
    echo "      A tick has claimed it$(claim_note) — it is RUNNING, not merely dispatched." >&2
    # WHO, not just when. `status` is the human's probe, and until it printed the claimant
    # the only way to answer "is that claim mine?" was to cat the file and read the
    # environment by hand — which is how the identity in it went wrong unnoticed.
    identity_lines "      " >&2
  else
    echo "      No tick has claimed it yet: it was taken for a dispatch that is starting." >&2
    # WHICH dispatch — the only readable signal inside the 41-47s window, where a lock with
    # no claim beside it is all there is.
    minted="$(lock_field claimant)"
    [ -n "$minted" ] && echo "      minted for: $minted — the tick the launcher took it for." >&2
  fi
  return 1
}

case "$cmd" in
  acquire)
    # A claim with no lock beside it is residue — a lock somebody removed by hand, or a
    # release that died between its two `rm`s. Left alone it would make the NEXT dispatched
    # tick refuse a lock nobody holds, i.e. the deadlock this whole design exists to avoid.
    # READ IT BEFORE THE CREATE, AND THAT ORDER IS WHAT MAKES CLEARING IT SAFE: a legitimate
    # claim can only be created against a lock that already exists, so "claim present, lock
    # absent" cannot become "claim present, lock legitimately claimed" underneath us — and
    # while the residue occupies the name, nobody else can create a claim at all.
    claim_residue=no
    if [ -e "$CLAIM" ] && [ ! -e "$LOCK" ]; then claim_residue=yes; fi

    # A TICK NEVER CREATES A LOCK — no lock means no launcher dispatched you, and that is
    # a resume. Read BEFORE the create rather than inside it, which is safe here and would
    # not be on the launcher's path, because this branch WRITES NOTHING: the worst a lock
    # appearing in the microsecond after this read can cost is one refused tick, and a
    # refused tick is the same outcome as no tick. The write path below keeps its single
    # `O_EXCL` syscall exactly as before.
    if [ "$as" = tick ] && [ ! -e "$LOCK" ]; then
      refuse_unlaunched
    fi

    # THE CHECK AND THE WRITE, IN ONE `O_EXCL` CREATE. Nothing runs between them because
    # there is no "between" — this is the whole reason the script exists rather than a
    # `[ -f ] && write` in the launcher's prose.
    if ( set -o noclobber
         # The redirect stays INSIDE this subshell: `noclobber` is a shell option, so a
         # `> $LOCK` applied by the caller truncates an existing lock instead of refusing.
         { printf '%s\n' \
           "# loopd PM tick lock. Taken by the LAUNCHER immediately before it dispatches a" \
           "# tick, and only by it: a tick that finds no lock was not dispatched — it was resumed" \
           "# — and is refused rather than allowed to take one of its own." \
           "# PER CLONE and gitignored — NOT a cross-machine lock: two clones of one shared" \
           "# bundle each have their own, and each dispatches independently by design." \
           "# Stale after ${STALE_MINUTES}m (TICK_LOCK_STALE_MINUTES). Clear it with:" \
           "#   tick-lock.sh release" \
           "timestamp: $NOW_ISO" \
           "epoch: $NOW" \
           "agent: $agent" && lock_claimant_line
         } > "$LOCK"
       ) 2>/dev/null; then
      [ "$claim_residue" = yes ] && rm -f "$CLAIM" 2>/dev/null

      # The lock was there at the check above and gone by this create, so this tick has
      # just made a lock of its own — the case that check refuses, arriving through a
      # microsecond race instead of the ordinary way in. Remove what WE created, which is
      # never somebody else's lock (the `O_EXCL` create succeeded, so it is ours and it is
      # microseconds old), and refuse, rather than letting the race be the way in.
      if [ "$as" = tick ]; then
        rm -f "$LOCK" 2>/dev/null
        refuse_unlaunched
      fi

      # Silence is the contract on the launcher's path: the human ran a command, not a
      # briefing. Nothing about that changes here.
      exit 0
    fi

    # The create failed. Either something holds the lock, or this root cannot be written —
    # and those are different answers, so they are not collapsed into one.
    if [ ! -e "$LOCK" ]; then
      echo "tick-lock: cannot write $LOCK — the instance root is not writable." >&2
      echo "           Refusing to dispatch: a lock nothing can write is a guarantee" >&2
      echo "           nothing is keeping, and that is the failure this replaces." >&2
      exit 3
    fi

    # A lock exists. Judge it QUIETLY first: a launcher's HELD verdict is the final answer,
    # but for a tick the same verdict is only half of one, and printing "HELD" before
    # discovering the lock is the tick's own would be a lie the launcher's path never told.
    verdict="$(judge_existing 2>&1)"; vrc=$?

    # AN INTERVAL-DRIVEN PASS THAT LANDED MID-TICK. The decision is the launcher's — do not
    # dispatch, exit 1 — and only the REPORT changes: one line, on stdout, because a clock
    # firing into a running tick is the ordinary case and not a fault. Read from the lock
    # rather than from `$verdict`, so this line cannot drift with the launcher's wording.
    loop_ts=""; loop_ag=""; loop_age=""
    if [ "$as" = loop ] && [ "$vrc" -eq 1 ]; then
      loop_ts="$(lock_field timestamp)"
      loop_ag="$(lock_field agent)"
      loop_age="$(lock_age)" || loop_age=""
    fi
    # All three non-empty is implied by a verdict of 1 — `judge_existing` returns 2 when any
    # of them is missing — but this re-reads the file, so it is asserted rather than assumed:
    # an empty age would reach `human_age` as `[ "" -lt 60 ]`, and a shell error where a
    # quiet line belongs is exactly the noise this mode exists to remove. Empty falls through
    # to the launcher's block below, which is louder and never wrong.
    if [ -n "$loop_ts" ] && [ -n "$loop_ag" ] && [ -n "$loop_age" ]; then
      echo "tick in progress since $loop_ts ($loop_ag, taken $(human_age "$loop_age") ago) — nothing to dispatch this pass."
      exit 1
    fi

    if [ "$as" != tick ] || [ "$vrc" -ne 1 ]; then
      [ -n "$verdict" ] && printf '%s\n' "$verdict" >&2
      exit "$vrc"
    fi

    # A live lock, and this is a tick. UNCLAIMED means it is the dispatch that spawned this
    # tick — the launcher took it seconds ago and no tick has run under it yet — so claiming
    # it IS proceeding. CLAIMED means a tick is running under it, and the only question left
    # is which one.
    if claim_exclusive adopted; then
      echo "adopted: $LOCK — the dispatch lock the launcher took before spawning this tick."
      echo "         It releases that lock when this tick reports; do not release it yourself."
      # REPORTED, NEVER REFUSED: adopting proves you are the dispatch, not who you are, and
      # refusing here would deadlock every tick (header: "IT IS NOT CLOSED HERE").
      minted="$(lock_field claimant)"
      if [ -n "$minted" ] && claimant_is_declared && [ "$minted" != "$CLAIMANT" ]; then
        echo "note: this lock was minted for $minted and you declared $CLAIMANT. Adopted anyway —"
        echo "      an unclaimed lock proves the dispatch. Check the id your brief carried."
      fi
      exit 0
    fi
    unwritable_claim

    # WHOSE CLAIM IS IT? Four answers, and each gets its own exit code — the point of the
    # rewrite is that "the ids match" and "it is you" are different statements, and only the
    # second clears a dispatch.
    case "$(claim_attribution)" in
      mine)
        # PROVED, not guessed: both sides declared a per-tick identity and they matched.
        # Nothing on disk changes — the claim is already this tick's and re-writing it would
        # only move a timestamp nothing judges.
        claim_ts="$(lock_field timestamp "$CLAIM")"
        echo "re-entered: $LOCK — this tick already claimed it${claim_ts:+ at $claim_ts}; nothing on disk changed."
        reprint_obligation
        exit 0 ;;

      maybe)
        # THE ONE THIS FILE WILL NOT DECIDE. The ids are equal, but at least one came from
        # the runtime, and the runtime's id is one per SESSION: every tick an `/<plugin>:dispatch`
        # session starts carries it, so equality is consistent with "you, re-entering" AND
        # with "a sibling this session resumed". Guessing either way has a name — proceed is
        # the 2026-08-29 double-dispatch, hold is the 2026-08-30 stand-down — so it is
        # surfaced with both ids and left to a human, exactly as a stale lock is.
        echo "CANNOT ATTRIBUTE THIS CLAIM: $LOCK is live and claimed$(claim_note)," >&2
        echo "     and the identity on it EQUALS yours — which is not proof that it is you." >&2
        identity_lines "     " >&2
        echo "     A session-derived id names the SESSION, not the tick: every tick one" >&2
        echo "     /${PLUGIN_NAME}:dispatch session starts shares it, so this reads the same whether you are" >&2
        echo "     re-entering your own claim or meeting a sibling that session resumed." >&2
        echo "     Do not dispatch and do not delete anything. A human decides:" >&2
        ab_say_run "       - if no other tick is running, re-run after:" tick-lock.sh release >&2
        echo "       - if one is:                    let it finish; this tick ends here" >&2
        echo "     To make this decidable, give each tick a per-tick id: --claimant <id>." >&2
        exit 2 ;;

      theirs)
        echo "HELD BY ANOTHER TICK: $LOCK is live and a tick already claimed it$(claim_note)." >&2
        echo "                      You are not that tick — a tick that began outside the" >&2
        echo "                      launcher (a SendMessage resume) is exactly this case." >&2
        echo "                      Report and hold: dispatch nothing, adopt nothing, end the" >&2
        echo "                      tick, and release nothing — the lock is not yours." >&2
        identity_lines "                      " >&2
        # Two DIFFERENT ids are not quite proof of two ticks either: a session that forks or
        # compacts gets a new id mid-run, so a long tick can meet its own claim as a stranger.
        # That resolves to "hold", which is the safe half — but a human staring at two ids
        # should be told which reading they are looking at rather than deducing it, and only
        # where it applies: with two DECLARED ids, different means different, full stop.
        if ! claimant_is_declared || ! claimant_is_declared "$(lock_field claimant-source "$CLAIM")"; then
          echo "                      (Session-derived on at least one side. If you believe" >&2
          echo "                       both are the same tick, your session id moved — a fork" >&2
          echo "                       or a compaction does that. It is a hold either way.)" >&2
        fi
        exit 1 ;;
    esac

    # unknown: one side or the other has no identity at all. Exactly the pre-claimant
    # behaviour — hold — with the missing side named, because a tick that keeps meeting this
    # on a lock it believes is its own has an environment that cannot identify it, not a
    # sibling, and that is a different thing to fix.
    echo "HELD BY ANOTHER TICK: $LOCK is live and a tick already claimed it$(claim_note)." >&2
    echo "                      Report and hold: dispatch nothing, adopt nothing, end the" >&2
    echo "                      tick, and release nothing — the lock is not yours." >&2
    identity_lines "                      " >&2
    if [ -z "$CLAIMANT" ]; then
      echo "                      (No identity for THIS tick: neither --claimant nor" >&2
      echo "                       TICK_CLAIMANT nor CLAUDE_CODE_SESSION_ID gave one, so a" >&2
      echo "                       claim you made yourself would look exactly like this.)" >&2
    else
      echo "                      (That claim records no claimant — it predates this check" >&2
      echo "                       or was written by hand, so it cannot be matched to you.)" >&2
    fi
    exit 1
    ;;

  release)
    # Absence is a silent success, not an error — releasing a lock nobody holds is the
    # normal outcome of a loop that was interrupted, and it must never scroll or fail.
    [ -e "$LOCK" ] || [ -e "$CLAIM" ] || exit 0
    # The CLAIM goes first, and the order is not cosmetic: a crash between the two `rm`s
    # then leaves a lock with no claim — adoptable, which is a state the design already
    # handles — rather than a claim with no lock, whose only effect would be to make the
    # next tick refuse. Either half surviving is cleared by the next `acquire` anyway.
    rm -f "$CLAIM" 2>/dev/null
    rm -f "$LOCK" 2>/dev/null
    left=""
    [ -e "$LOCK" ] && left="$LOCK"
    [ -e "$CLAIM" ] && left="${left:+$left and }$CLAIM"
    if [ -n "$left" ]; then
      echo "tick-lock: could not remove $left" >&2
      exit 3
    fi
    exit 0
    ;;

  status)
    # READ-ONLY, AND NOT FOR THE LAUNCHER. This is the human's (and the harness's) probe.
    # A launcher that called `status` and then `acquire` would have re-created the
    # check-then-write window that `acquire` exists to close.
    if [ ! -e "$LOCK" ]; then
      echo "free: no $LOCK — the next dispatch tick takes it."
      [ -e "$CLAIM" ] && echo "note: $CLAIM outlived its lock; the next acquire clears it."
      exit 0
    fi
    judge_existing; exit $?
    ;;
esac
