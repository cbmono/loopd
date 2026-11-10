# Conventions detail: working in a product repo

Detail for `../CONVENTIONS.md` — moved there verbatim, so the core stays short. Open a section only when the core's pointer to it names a trigger that applies. **The core wins on any disagreement**; fix this file to restate it.

<!-- tool-mention: Agent(2), EnterWorktree(1), mcp__claude-in-chrome__*(1) — named to state their ABSENCE for some readers, never to instruct: only qa-reviewer holds Agent, and the Explore rule gives the route for the others; EnterWorktree may be missing for a subagent; failure-analyst holds no browser tools. Enforced by tests/agent-tool-allowlist.test.sh. -->

### Parallel-safety

- **Parallel-safety:** if the product repos share one clone / one package store,
  each agent uses its own worktree under `worktreeRoot` (from `instance.config.json`
  — outside any synced folder; **never** inside `reposRoot`. Absent that key, fall
  back to `<reposRoot>/_wt`) and a **private package
  store** where the repo's own package manager has one (that manager, as the
  target repo's `CLAUDE.md` states it — never assume one; e.g. a pnpm repo takes
  `--store-dir <worktree>/.pnpm-store`), and pushes early.
  **THE HOOK CREATES IT — CHECK BEFORE YOU CREATE ONE.** A session started as
  `claude --worktree <task-id>` is placed by `plugin/hooks/worktree-create.sh` in
  `<worktreeRoot>/<task-id>` of your `target_repo`, on the task's `branch:`, and that is
  your cwd from the first turn. `pwd` and `git rev-parse --abbrev-ref HEAD` answer it in
  two commands. Already there ⇒ **do not add a second worktree** — you will branch off
  your own branch and open a PR against it.
  **Only when it did not**, which is every in-session subagent dispatch (the hook's payload
  carries `agent-<opaque-id>`, never the task, so it cannot place one for you):
  `git worktree add <path> -b <branch> origin/<default-branch>`. Don't rely on the
  `EnterWorktree` tool, which may be unavailable to you as a subagent.
  (`settings.json` sets `worktree.bgIsolation: none` so the control panel manages
  worktrees itself; harness isolation would only isolate this repo, not the product repos.)
  **Nothing deletes your worktree while you are working in it, and what deletes it after
  refuses on anything of yours.** `prune-worktrees.sh` still only prints removal commands;
  the one thing that deletes is `reclaim-worktree.sh`, which the tick runs for a task that
  is `done` with every PR MERGED — and it refuses a dirty tree, an unpushed commit, a
  detached HEAD, an ignored file that is not a known cache, and a live process inside the
  tree. So uncommitted work is never taken from you; it just means the tree stays, and
  nobody tidies it.
  **Scratch files go in `<worktree>/tmp/`, never a shared scratchpad.** Mutation
  scripts, probe output and throwaway configs collide when several agents run at once.
  Keep them inside your own worktree — verified working with three concurrent agents on
  one tick.
  **A scratch path that the repo does not IGNORE is not scratch.** Until 2026-09-09 this
  rule named a directory `cbmono/loopd` TRACKS, so an obedient agent wrote its drafts
  into version control and its own cleanup deleted a tracked file. `tmp/` is ignored by
  every bundle this seed stamps and by that repo; elsewhere, `git check-ignore -q` before
  you write, and pick a path the repo does ignore if it says no.
  **It fails silently:** two agents sharing one scratchpad path on 2026-09-08 overwrote
  each other's PR-body draft, and the body that got posted was well-formed, merely the
  wrong task's. `prune-worktrees.sh` recognises `tmp` as scaffolding, so obeying
  this never leaves you a worktree that reads as dirty forever.

### Browser (only if the project opts in)

- **Browser (only if the project opts in):** when the task's project sets `browser:
  claude-for-chrome` **and** the `mcp__claude-in-chrome__*` tools are actually present,
  **rung 1 above applies to the browser like any other tool**: verify the change in the
  real page, read the logged-in view, take the screenshot. This paragraph used to state
  that as a browser-only rule; it is the general one now, stated once, so the two cannot
  drift. You get your **own tab group**, not the human's tabs, so always navigate from an
  explicit URL. Tools absent (e.g. a headless tick) → **that is a capability gap, so take
  the non-browser route, say so, and carry on** — never report blocked *only* for a missing
  browser. **Browser writes follow the project's
  `autonomy`:** **ask first** — that's the default and the only behaviour unless the project
  delegates writes (`AUTONOMY.md` at the bundle root defines the modes; no such file means
  always ask). Read-only navigation and screenshots never need asking. Scope discipline
  still applies — a write nobody asked for isn't licensed by autonomy. And
  no customer PII from a logged-in page
  ever reaches a task doc, PR text, `log.md`, any log or console output, or the KB.
  Describe the *shape* of what you saw, not the records. Full rules: `SCHEMA.md` →
  "Browser access".

### Reading a product repo

- **Reading a product repo: a question that would take more than a few files to answer
  goes to an `Explore` subagent; a direct `Read` is for the file you are about to edit or
  verify.** Explore returns the conclusion instead of the file dumps and runs on the cheap
  `explorer` tier. Measured by the owner on one monorepo, 5 real questions: Explore 5/5,
  plain grep 4/5, CodeGraph 1/5. It is scoped to the target repos this document governs.
  **The direct read is the other half of the rule, not a fallback from it:** a summary
  carries no reliable line numbers, so an edit never works from one. Locate with Explore,
  then read the one file you are about to change.
  **Which route you take is decided by your own `tools:` list, not by what is installed on
  the machine.** Hold `Agent`? — `qa-reviewer` does — dispatch an Explore subagent on the
  model and effort your dispatch brief names (`scripts/resolve-model.sh explorer`;
  no entry ⇒ the seed default `light`, and the brief says which it is;
  `scripts/resolve-effort.sh explorer`, nothing printed ⇒ no `effort:`). Don't hold it? — `software-engineer`,
  `devops-engineer` and `failure-analyst` don't — then the second half is your whole route:
  narrow with `Grep`/`Glob`, read only what you will edit or verify, and put the `Agent`
  request in the task's `open_questions` (the middle rung above) when a question genuinely
  needed the delegation.

### codegraph keeps exactly one job

- **`codegraph` (if present) keeps exactly one job: TypeScript blast radius.**
  `codegraph node <sym>` for one symbol's callers/callees, `codegraph impact <sym>` /
  `codegraph affected <files>` before a change. Don't reach for it first for anything else
  — in the measurement above it placed last, it indexes no SQL, and its index is a stale
  snapshot that reports itself current. Skip silently if absent; it's an optional local
  index (see the loopd README).
