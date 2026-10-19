---
name: unblock
disable-model-invocation: true
description: Unblock one `blocked` task — show why it stopped, take your one decision, record it in the task's `# Notes` stamped with your login, reset its stall counter and return it to `ready`, so the next tick re-dispatches it with that decision. Refuses any task that is not blocked.
argument-hint: "<task path> [<your decision>]"
allowed-tools: Bash(pwd), Bash(ls:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/bundle-paths.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/unblock.sh:*), Read, AskUserQuestion
---

Unblock one task the loop stopped on, with the one decision only you can make.

## Preconditions
Run from a control-panel instance root — confirm `instance.config.json` in the cwd with
`ls instance.config.json`; if it fails, tell the user to `cd` into the instance and stop.

## Arguments — `$ARGUMENTS`
The first word is the task: a path that resolves to a file under `projects/*/tasks/`. Anything
else — no argument, a project, a `.md` elsewhere — is refused: say what did not match and stop.
Any further words are the decision.

## Steps
1. **Show.** Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/unblock.sh <task path>` and relay its
   output here: the task's `last_blocker` and its escalation note. **Exit 1** — the task is
   not `blocked`: relay its one sentence and stop. This text belongs in the session, never
   in the pane, which draws no blocker text (`plugin-mod-pane/README.md`).
2. **Decide.** When the arguments carried no decision, ask for exactly one with
   `AskUserQuestion` — what the next agent should do differently, in a line. Offer the
   obvious ways forward as options when the blocker suggests them; take free text otherwise.
3. **Record.** Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/unblock.sh <task path> --decision <the decision>`.
   It appends one `# Notes` line, `- <ISO 8601> by <login>: unblocked — <decision>`, with the
   login from `decision-stamp.sh --self`; resets the counter with `stall-counter.sh reset`;
   sets `status: ready`; commits as you through `commit-as.sh human` and pushes when the
   clone has an upstream. **Exit 3** — a write failed: relay it and stop. **Exit 4** — the
   decision is recorded but not pushed: relay the line and stop; never force-push and never
   resolve a rebase for the human.

## Notes
- **This never promotes, dispatches or merges.** `ready` is where a human-gated task waits;
  the next `/loopd:dispatch` tick picks it up and the agent reads your decision from `# Notes`.
- No customer PII or secret in the decision — `# Notes` keeps it for the life of the repo.
