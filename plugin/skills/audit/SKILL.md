---
name: audit
disable-model-invocation: true
description: Run the slow-cadence audit loop — the counter-metric that grounds each goal (an objective's success_criteria, or a project's own where it carries no objective) against reality and flags Goodhart drift, stale knowledge, and green-but-not-progressing work. The audit agent is read-only; the command's only write is prepending its report to log.md; never promotes, merges, or dispatches.
allowed-tools: Bash(pwd), Bash(ls:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/bundle-paths.sh:*), Bash(date:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/tick-lock.sh status:*), Read, Edit, Agent
---

Run one **audit pass** over this control-panel instance — the slow counter-metric loop
that complements `/loopd:dispatch`. It is **read-only**: it surfaces drift, it never promotes,
merges, dispatches, or changes task status.

## Preconditions
1. Run from a control-panel instance root — confirm `instance.config.json` in the cwd
   and `SCHEMA.md` at the resolved schema path (`AB_SCHEMA`; the root on a legacy layout) with exactly
   `ls instance.config.json "$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/bundle-paths.sh AB_SCHEMA)" 2>/dev/null || ls instance.config.json SCHEMA.md`; if it fails, tell the user to `cd` into the instance
   and stop. (A bundle carries no `.claude/agents`; the roles ship in the plugin.)
2. **Stand down while a tick is in flight.** Step 3 prepends to `log.md`, and so does every
   non-idle dispatch tick, so the two must not run at once. Run
   `${CLAUDE_PLUGIN_ROOT}/scripts/tick-lock.sh status` — **exit 0 (`free:`) is the only
   clearance.** Exit 1 (`HELD:`) means a tick is running: say so in one line and stop,
   exactly as a `/loop` dispatch pass does, and let the next firing take it. Exit 2 or 3 is
   a lock that needs a human — print what it said and stop. This is the read-only probe, so
   nothing is taken and nothing is released.
   **It narrows the window; it does not close it.** A tick dispatched in the moment between
   this read and the audit's write would still collide, and closing that properly needs a
   write lock over `log.md` shared by both paths — a mechanism neither this skill nor the
   tick has today. Run the slow cadence on a bundle whose dispatch loop you are not also
   watching, and read this as the cheap 90% rather than a guarantee.

## Steps
1. Read `instance.config.json`. **Resolve the auditor's model** the same way the PM
   routes dispatches: run `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-model.sh auditor` — it looks `auditor` up in `roleTiers` (default `deep`) and maps it to an
   alias via `models`; if those maps are absent it prints why on stderr — report that line,
   then inherit the session model rather than dispatching on a guess.
2. Dispatch the **`auditor`** agent (`subagent_type: loopd:auditor` — the plugin
   namespace, because a BARE agent name does not resolve) for one pass, passing the
   resolved model. It's read-only — it grounds each goal's `success_criteria` against
   live `gh`/`git` reality (an **objective**'s, or a **project's own** where it carries
   no `objective:` — `objectives/` is optional), reports **"no criteria"** for anything
   carrying neither, flags the four drift modes (Goodhart · measurement decay ·
   green-but-not-progressing · weakened anchors), and **returns** a dated audit report
   (it writes nothing itself).
3. **Persist it.** Prepend the returned report as a dated `## Audit — <date>` entry to
   the root `log.md` (date via `date -u +%Y-%m-%d`).
4. Relay its verdict + findings. These are **advisory** — acting on them (adjusting
   objectives/targets, re-validating stale findings, unwinding a Goodharted metric) is
   your governance call; the audit never does it for you.

## Cadence
This is a **slow** loop — run it weekly, or after a batch of projects close, not every
tick. It changes no task state, but it **prepends to `log.md`** — as does each
`/loopd:dispatch` tick — so run it **between** ticks, not concurrently, to avoid a
write race on that file.

**Run it with `/loop 7d /loopd:audit`, in a session on the machine that holds the
bundle** — the same first-party `/loop` the dispatch cadence uses, at a slow interval.
Nothing is installed for it: no cron, no watcher, no script.

**A scheduled cloud routine cannot do this job, and the reason is structural rather than a
preference.** `/schedule` (alias `/routines`) creates *remote* Claude Code agents via the
claude.ai API; a remote agent gets a fresh clone of a **GitHub repository**, and every
input this audit needs is either gitignored or outside the repo — `instance.config.local.json`,
`repos/`, `SNAPSHOT.json`, `AWAITING.md`, and the target-repo clones under `reposRoot`,
which is an absolute path on your machine. The measurement, and what a routine *can*
usefully do instead, are in `docs/operations.md` → "Running the loop on a cadence".
