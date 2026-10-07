---
name: fanout
disable-model-invocation: true
description: Fan a batch of independent ad-hoc requests out to parallel background agents — the main session coordinates and reports results as they land
argument-hint: "<task; task; task>  |  (empty) = fan out the independent asks already in this turn"
allowed-tools: Agent, Read, Glob, Grep, Bash(ls:*)
---

> **Kept (v2 audit, 2026-08).** The `Workflow` tool is the first-party equivalent for
> *tracked* fan-out and this bundle already routes in-task wide work there. This command
> covers **ad-hoc chat dispatch** — explicitly not tracked work — and carries a filter
> `Workflow` has no equivalent of: what stays in-thread versus what needs an interactive
> decision. Not a duplicate.

Dispatch independent **ad-hoc** requests to **parallel background agents** so the
main session stays free as a coordinator, instead of working them one at a time.

> **Generic plugin file** (ships inside the `loopd` plugin, never copied into a bundle). This is for
> **ad-hoc chat requests** (rephrase a doc, rename a folder, research a question) —
> **not** tracked `projects/` work. Anything that becomes a PR or a `projects/`
> deliverable goes through `/new-project` → promote `ready` → `/loopd:dispatch`, never here.

## Input
`$ARGUMENTS` is an optional `;`-separated list of tasks. If empty, fan out the set
of independent asks the user has already given in this turn.

## Steps
1. **Split into units.** Identify the genuinely independent asks. If one depends on
   another's output, say so and sequence those — only fan out what's truly parallel.
2. **Filter — keep in-thread anything that shouldn't dispatch:**
   - needs an **interactive decision** (a subagent can't ask the user) → settle it
     with the user first, then dispatch the *execution*;
   - **trivial lookup** → just answer it (an agent round-trip is slower);
   - **writes the same files** as another unit → serialise them, or give each its
     own worktree (`isolation: worktree`), so they don't clobber.
3. **Brief each agent fully.** Subagents have **none** of this conversation's
   context — write each a complete, standalone prompt (goal, exact files/paths,
   acceptance, "report back X"). They inherit this bundle's rules (no PII, metric
   units, data-question routing) from `CLAUDE.md`.
4. **Dispatch in one message.** Spawn all units as **`general-purpose` agents with
   `run_in_background: true`** in a single turn so they run concurrently. Use a more
   specific agent type when one fits (e.g. `deep-bug-scan`, `Explore`, or one of this
   plugin's seven role agents — **namespaced**, `loopd:cataloguer`,
   `loopd:failure-analyst` for a failing build / red CI / failed deploy, read-only
   diagnosis — because a bare role-agent name does NOT resolve).
5. **Coordinate.** Tell the user what was dispatched — and what you kept in-thread
   and why. As each agent finishes, **report its result**; don't block the session
   waiting on all of them.

## Notes
- This command **dispatches, it doesn't gate** — no `draft → ready` promotion, no
  merge. Those gates exist only for tracked `projects/` work.
- Cap concurrency to a sensible handful; if there are many units, batch them.
- No customer PII in any agent prompt.

## Model for each dispatched agent

Resolve it with `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-model.sh <agent>` before spawning, never from memory.
Most fan-outs use `general-purpose`, which has no `roleTiers` entry — the script then
prints nothing on stdout, exits 1, and says why on stderr, and inheriting the session model
is the correct answer. **That line is the expected answer here, not a fault**, so there is
no suppression list; for a NAMED role it is a real gap, and then you report that line to
the human rather than dispatching on a guess. But
when you fan out a **named role agent**, that agent has a tier, and reading it from the
config is the difference between the instance's setting governing the dispatch and it
not. See `CONVENTIONS.md`, "Resolve a dispatched agent's model with
`${CLAUDE_PLUGIN_ROOT}/scripts/resolve-model.sh`".
