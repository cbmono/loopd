---
name: kb-apply
disable-model-invocation: true
description: Apply one knowledge/ reflection report after you have read it — the human half of the reflector. A scheduled run proposes into a draft report; this is the only path that writes the proposals to knowledge/. Applies exactly what the report names, in one commit.
argument-hint: "<path to the report, e.g. projects/knowledge-reflection/tasks/task-001-knowledge-reflection.md>"
allowed-tools: Bash(pwd), Bash(ls:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/bundle-paths.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/kb-apply.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/decision-stamp.sh:*), Read, Glob, Grep
---

Apply one reflection report to `knowledge/`, after a human has read it.

**The split this command is one half of: a scheduled run PROPOSES, and this APPLIES.**
`kb-propose.sh` runs on the tick's cadence and writes a draft report; it never touches
`knowledge/`. Nothing but this command applies one. An unattended process that rewrote
`knowledge/` on a timer would hold an authority no agent here has, over the documents every
brief is built from (`SCHEMA.md` → "Two human authorities").

## Preconditions
Run from a control-panel instance root — confirm `instance.config.json` in the cwd and
`SCHEMA.md` at the resolved schema path (`AB_SCHEMA`; the root on a legacy layout) with exactly
`ls instance.config.json "$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/bundle-paths.sh AB_SCHEMA)" 2>/dev/null || ls instance.config.json SCHEMA.md`; if it fails, tell the user to `cd` into the instance and stop.

## Steps
1. **Resolve the report.** `$ARGUMENTS` is a path to a task document under
   `projects/*/tasks/`. Empty ⇒ list every `status: draft` task carrying `P1 · ` lines
   across **all** of `projects/*/tasks/*.md` and ask which — the proposer's `--project` is
   a flag, so a report can live under any slug. No match ⇒ say so and stop.
2. **Show the human the proposals first.** Print each `P<n> · …` line of the report with
   the item it names. This is the gate the whole design exists for: do not run step 3
   until they have said to.
3. **Apply.** One command, which does all of it:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/kb-apply.sh --by <login> <report>
   ```

   `<login>` is the human applying it, from
   `${CLAUDE_PLUGIN_ROOT}/scripts/decision-stamp.sh --self` — never a role name, which
   `ledger.sh` refuses. Exit 0 applied · 1 refused, with the reason · 2 usage.
4. **Report** what landed: the proposals applied, the commit, and the items' new state.
   Never re-run a refused report with a different argument to get past the refusal.

## What it writes, and nothing else
The frontmatter field each proposal names · one `ledger:` entry per item · the regenerated
`knowledge/index.md` · the report's own `status: done` · one commit. A change the report
does not name is not applied — that is the contract, and it is why the script refuses a
whole report rather than applying the part of it that still checks out.

## Notes
- **Declining is cancelling the report**, not editing it: set the task's
  `status: cancelled`. The row clears on the next tick and the proposal can be raised
  again by a later run.
- **A refusal is information, not an obstacle.** `provenance: machine` is missing (a person
  wrote that item), the item changed since the report was written, the report is already
  `done`, or a tick holds the dispatch lock and may be writing `knowledge/`. Re-run
  `kb-propose.sh` rather than editing the report by hand.
- **`ledger:` and `provenance:` are refused as proposal fields.** The first has one
  append-only writer; the second is the guard this path reads before it touches anything.
- This command **never proposes, never promotes a task and never merges a PR**. The report
  is read, applied or cancelled.
