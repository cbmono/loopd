---
name: prune-wt
disable-model-invocation: true
description: Remove the worktrees prune-worktrees.sh reports REMOVABLE, after one confirmation. Each path is re-checked at removal time and skipped on any doubt; KEEP, RECLAIMABLE and LIVE PROCESS worktrees are never touched. Refuses while a tick holds the lock.
allowed-tools: Bash(pwd), Bash(ls:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/bundle-paths.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/prune-wt.sh:*)
---

Remove the finished worktrees the pruner reports, after the human says yes once.

**Only a human starts this.** `prune-worktrees.sh` stays report-only, and nothing a tick or a
role agent runs reaches this command. It removes through `prune-wt.sh`, which re-checks every
path with `reclaim-worktree.sh`'s guards — never by piping the printed lines into a shell.

## Preconditions
Run from a control-panel instance root — confirm `instance.config.json` in the cwd with
`ls instance.config.json`; if it fails, tell the user to `cd` into the instance and stop.

## Steps
1. **Preview.** Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/prune-wt.sh` and relay its output:
   the pruner's report, then one `would remove:` or `skip:` line per REMOVABLE path. It
   touches nothing. Exit 1 means a tick holds the lock — relay that and stop. No
   `would remove:` line ⇒ say so and stop.
2. **Ask once.** "Remove these N worktrees?" Anything but a clear yes ends here.
3. **Remove.** `bash ${CLAUDE_PLUGIN_ROOT}/scripts/prune-wt.sh --yes`. It re-runs the pruner
   and every check, removes what still passes, then runs `git worktree prune` once per repo
   it removed from. Exit 0 done · 1 refused (the lock) or a removal failed · 2 cannot answer.
4. **Report** the `removed:`, `skip:` and `pruned:` lines. Each skipped path stays the
   human's to inspect by hand. Never retry a skip another way.

## What it never does
Remove a `KEEP`, `RECLAIMABLE`, `STALE` or `UNREGISTERED` worktree; remove one with a live
process in it, an ignored file that is not a known cache (a `.env`), uncommitted, untracked
or unpushed work, a `git worktree lock` or a detached HEAD; pass a forced-removal flag; delete a branch.
