# AI Bridge — the plugin

The OKF control panel, delivered as a Claude Code plugin instead of a symlink farm.
Skills, agents, hooks **and the machinery itself** ship here, reading and writing bundles
(`projects/`, `knowledge/`, `instance.config.json`) that hold data and nothing else. A
bundle carries no machinery and no link into any checkout: `/loopd:init` stamps one,
and converts one stamped by the retired `install.sh`.

## Install

```
/plugin marketplace add cbmono/loopd
/plugin install loopd@loopd
```

Updates ship by version bump (no ambient auto-update): `/plugin` → Marketplaces.

**It also ships a colour theme.** `themes/loopd.json`, declared by `experimental.themes`
and listed in `/theme` as `custom:loopd:loopd` — select it there, because nothing
here writes your `theme` setting. The palette is a duotone — blue is the machine's, pink is
yours — and every colour in it comes from
[`tests/fixtures/theme-palette.txt`](../tests/fixtures/theme-palette.txt); the token names a
theme file may use are listed once, in
[`tests/fixtures/theme-tokens.txt`](../tests/fixtures/theme-tokens.txt).

**What ships here, and the one thing that does not.** An installed plugin is the CONTENTS
of this directory — `agents/ evals/ hooks/ scripts/ skills/` and, since task-022, the three
files a stamp reads: `seed/`, `RETIRED` and a mirror of the template `VERSION`. So
`/loopd:init` needs **no clone of `cbmono/loopd`**, which is the whole point of
shipping the installer in the plugin and was not true before 0.15.0: the root detection
looked two directories above `scripts/` for `seed/`, which is where a *checkout* keeps it
and not where a plugin cache does, so init exited 2 on every machine that installed it the
supported way.

**`init-bundle.sh --config` is the exception, and it is the only one.** It links three
agent files into `${CLAUDE_CONFIG_DIR:-~/.claude}` by absolute path, so it must know where
those paths point and `config/` deliberately stays outside the plugin: it is a per-machine
decision, not a bundle one, and `plugin/` must never *require* it. Run it from a clone;
run it never, and a bundle stamp behaves exactly the same, because the role agents probe
for those agents with `test -f`. From an installed plugin `--config` refuses by name and
prints the clone command rather than reporting a missing directory.

## Skills today

| Skill | What it does |
|---|---|
| `/brief-me [project]` | Read-only. No argument: the board brief — what needs you, what's in flight, what moved since the last full tick. With a project slug: a meeting-ready brief with questions quoted by number and a "decide today" list. |
| `/capture <notes>` | Intake. Turns a decision or meeting notes into `draft` projects/tasks with provenance, fitted into existing projects where they belong. Never promotes; refinement stays the loop's job, promotion stays yours. |
| `/work <task>` | Work one `ready` task in the current session — the solo alternative to a background dispatch, leaving the same record (worktree/branch on the task, PR in `pr:`, `in-review` at the end). The gates still hold: no merging, review still independent. |
| `/dispatch [gap]` | The gated background loop. It carries the contract itself now — during the migration it delegated to the bundle's own copy verbatim, so there was never a second implementation to drift. |
| `/handoff <path> <login>` | Ownership transfer with the context that makes it real: `owner:` set, a dated handoff note, and a paste-ready summary (open questions, PRs, linked Findings) for the new owner. Dispatch-gating only — never a promotion. |
| `/welcome` | The welcome screen: bundle, owner, config layers, tier→model routing, board path, what awaits you. `check` reports state that could be wrong; `fix` repairs only the idempotent tier. |
| `/init <dir>` | Create a bundle, refresh one, or convert one stamped by the retired `install.sh` — data only, and the only symlinks it leaves are under `repos/`. |

Both also answer to their namespaced forms (`/loopd:brief-me`, `/loopd:capture`).
**`ai-bridge-v2` was the transition name** — its one-version deprecation stub was
removed in 1.0.0; the swap is in [`docs/migrating.md`](../docs/migrating.md).
Run them from a bundle root (where `SCHEMA.md` and `instance.config.json` live).

## Evals

`evals/` holds the `claude plugin eval` suite: real model runs, graded, pinning the one
class of contract a file check cannot reach. **Seven cases.** Three that the model never
reaches for `/dispatch`, `/work` or `/answer` on its own, plus a control arm that proves
those three are not vacuous; and three that grade the **main thread** rather than a skill —
diagnosis dispatched instead of run inline, an unanswerable read reported as unknown, and a
tick caveat outranking the launcher's own conclusion. See
[`evals/README.md`](evals/README.md) for how to run it and why it self-skips where
`plugin eval` is not enabled.

## Hooks

Registered by `hooks/hooks.json`. Unlike the skills these are **not invoked** — they fire
on their own at every `PreToolUse` boundary, in every session, which is the point: a
guarantee that depends on someone remembering to run it is not a guarantee.

| Hook | What it does |
|---|---|
| `hooks/deny-destructive.sh` | The destructive-action deny baseline. Refuses `terraform destroy`, irreversible `kubectl delete`s, destructive DDL against a remote host, `rm -rf` at a repo root, a force-push to a protected branch, secret exfiltration, and a dispatched agent merging a PR or pushing a product repo's default branch. Narrow on purpose, and the escape hatch is a human running the command in their own terminal. |
| `hooks/agent-control.sh` | The live kill switch. `gate`, `steer` and `halt` against ONE dispatched agent, keyed on `agent_id` so it can never take the human's own session down with it. The operator side is `scripts/control.sh`, beside it in this plugin — arming a bundle on a machine whose plugin is not installed writes directives nothing reads. Also the doom-loop breaker: with `maxRepeatedToolCalls` set, one agent's Nth identical tool call is denied (never killed); absent, nothing is counted. And the wall clock: past `maxAgentMinutes` (absent ⇒ 45; `roleMinutes.<role>` per role, and the `project-manager` absent ⇒ 180) an agent may only read, land what it has and hand back. Registered on `SubagentStart` and `SubagentStop` too, which start and park that per-agent state. |
| `hooks/permission-mode.sh` | Bash-matched, and writes only for the one call that runs `scripts/spawn-preflight.sh`: records that call's `permission_mode` **and its `--token`** under the session id in `.loopd/.permission-mode/` (self-ignoring), so step 3 can report *what mode is this session in?* before the wave. Never a decision; every failure is silent, and an unrefreshed record then reads as `could-not-read` rather than as this call's. |
| `hooks/report-shape.sh` | `SubagentStop`, for the `project-manager` only. Runs the tick's final message through `scripts/report-clearance.sh` before the launcher relays it — what happened, `Blocking:` only when something is, a numbered `Needs you:` list in dependency order. Refused once ⇒ the tick rewrites it; refused twice ⇒ it goes out with a `systemMessage` naming what failed, so a false positive can never loop a tick. |
| `hooks/session-banner.sh` | The `SessionStart` banner: which bundle this is, what it is configured to do, where the board is, what awaits the human — and, above all of it, an alarm if the bundle still carries machinery symlinks into a template checkout. Every line is a fact that can be false; none of it is a rules recital. |
| `hooks/push-state.sh` | `UserPromptSubmit`. Encodes the bundle's live state — projects, tasks in flight, what is awaiting a human — into the turn's context, at one awk choke point so a filename cannot forge the fence's markers. |

**All of them no-op SILENTLY outside a bundle root.** A plugin is installed once per user, so
these fire in every project on the machine. Each resolves `$CLAUDE_PROJECT_DIR` (never the
payload's `cwd` — a dispatched agent's cwd is a worktree of a target repo) and exits 0 with
no stdout, no stderr and nothing written unless `instance.config.json` is there. The two safety hooks have one way back in: when the project dir is a **linked worktree** (its `.git` is a file) they read `<repo>/.git/loopd-bundle`, the marker `scripts/link-repos.sh` writes into every linked repo, and treat the bundle it names as the instance — because a role agent is a `claude --bg` session rooted in its worktree, and without that the baseline allowed everything it ran. Zero noise
in any other folder is the requirement, not a side effect.

**The banner and push-state moved here in ai-bridge-v2/task-013**, from a bundle's own
`.claude/settings.json` — itself a symlink into a template checkout, so they reached only
the bundles somebody had re-stamped, and a template that moved took the registration with
it. A detector made of symlinks cannot see its own failure; a plugin hook is a real file
the plugin manager replaces whole.

**`permissions.deny` stays in the bundle's `settings.json`**, which `/loopd:init`
seeds. It is the second, unconditional layer behind the deny baseline, and a plugin
manifest has no permissions block to carry it.

## Companion plugins

**Core is gated-only, and stays that way.** Optional behaviour — delegated autonomy
today, an account switch and an alternative LLM backend next — ships as a **separate
plugin in this same marketplace**, and core picks it up **by presence**. Nothing is
configured, nothing is flagged: install the companion and the behaviour exists, uninstall
it and it doesn't.

**One rule, and it is not negotiable: a companion may ADD behaviour but may never remove a core gate.**
The two human authorities (`SCHEMA.md`) — the human promotes
`draft → ready`, the human merges — hold with no companion installed, and no companion
may make either of them hold *less*. `loopd-yolo` is not a counter-example: it does
not delete a gate, it ships the file that defines a mode in which the loop may hold one,
and the human still chooses that mode per project. A companion that removed a gate would
be indistinguishable from a supply-chain downgrade of the thing this whole design exists
to protect. Read it as a constraint on what may be *built*, not only on what is
installed today: the next companion (an account switch, an alternative LLM backend) is
held to it too, and a companion that could remove a core gate would not be a companion.

### The contract

| | |
|---|---|
| **How it registers** | An entry in [`.claude-plugin/marketplace.json`](../.claude-plugin/marketplace.json) with its own `source: ./<dir>` and `.claude-plugin/plugin.json` — installed with `/plugin install <name>@loopd`. |
| **Where core looks** | `<companion plugin root>/companion/<file>` — a **fixed relative path**, so a companion's own `README.md` or docs can never be mistaken for something core reads. |
| **Which plugins count** | Only those installed from the **same marketplace core itself came from**, read out of `~/.claude/plugins/installed_plugins.json`. An unrelated plugin that happens to carry that path is not a companion. |
| **What core reads** | Only names it already knows. Core never executes a companion's code, and a companion ships no settings hook and no agent — a second copy of a `PreToolUse` hook fires in every session on the machine. A **mod** companion (`plugin-mod-*/`, a hooks module Claude Code runs in-process) is the one shape that does ship under `hooks/`, and it is held to a narrower rule by `tests/mods.test.sh`: it observes, records and draws; it never calls a model, never answers the permission event, never starts a process or reaches the network, never writes a file — and it reads a file only when its own README's "What it reads" section names the exact path. |
| **When it is absent** | The gated default, silently. Absence is never an error, and every unknown (no registry, an unreadable one, a root gone from disk) resolves to absence. |

### How a companion is versioned

**A companion tracks core's MAJOR and moves its own MINOR and PATCH independently.**
`loopd-yolo 2.0.x` is the companion of `loopd 2.x`, and it releases a MINOR or a
PATCH whenever its own contents change, without waiting for core to move. **The reason:**
MAJOR is the only field carrying a compatibility claim — the fixed `companion/<file>` path
and the names core reads out of it — so a shared MAJOR says *this companion speaks the core
contract you have installed*, while independent MINOR/PATCH keeps a companion's own fixes
from forcing a core release nobody needed. `tests/template-version.test.sh` asserts both
halves for every companion entry in the marketplace, so a companion cannot drift silently.
`plugin/scripts/release-bump.sh major` moves every companion to the new major alongside core;
`minor` and `patch` leave them alone.

### Today's companions

| Companion | Ships | Read by |
|---|---|---|
| [`loopd-yolo`](../plugin-yolo/README.md) | `companion/AUTONOMY.md` — the delegated-autonomy capability and the `yolo` preflight | `scripts/resolve-autonomy.sh`, and through it `scripts/commit-as.sh`'s promotion guard |
| [`loopd-accounts`](../plugin-accounts/README.md) | `companion/accounts.md` — the per-bundle account capability — and `bin/ai-bridge-claude`, the launcher the **human** runs | `scripts/resolve-account.sh`, and through it the SessionStart banner's account line |
| [`loopd-llm`](../plugin-llm/README.md) | `companion/llm.md` — the alternative-LLM-backend capability — and `bin/ai-bridge-deepseek`, the launcher the **human** runs, opt-in per machine | nothing — core reads its presence nowhere. The banner's backend warning reads `ANTHROPIC_BASE_URL` from its own environment, so it fires with or without this companion |
| [`loopd-mod-usage`](../plugin-mod-usage/README.md) | `hooks/register.ts` — a mod that records each session's tokens, requests, tool calls, tool errors, wall time and model in the plugin store under `loopd.usage.<session id>` | `scripts/session-usage.sh`, which reads that store record before the transcript and falls back to the transcript on any doubt |
| [`loopd-mod-pane`](../plugin-mod-pane/README.md) | `hooks/register.ts` — a mod whose `/board` opens a pane drawing this bundle's board from `.loopd/SNAPSHOT.json` in the session's cwd: a **fourth renderer** over `scripts/write-snapshot.sh`'s contract, with a Tick button that runs `/loopd:dispatch` in that session and a Refresh button | nothing — core reads its presence nowhere. It reads core's snapshot (never the bundle), and absent, the three core renderers are all there is |

`scripts/resolve-autonomy.sh` is the **one** reader of "does delegated autonomy exist
here": the **bundle root wins outright** (a v1-era bundle carrying its own real
`AUTONOMY.md` keeps working, installed companion or not), then an installed companion,
then exit 1 — which is `gated`. One lookup with one reader, so the promotion guard and
the loop cannot come to disagree about whether delegation exists at all.

## During the transition — what stays an instance command, and why

A plugin skill **shadows** a same-named project command, so each command migrated in a
slice that moved the contract and retired the instance copy **in one change**, with the
template's test suite as the spec — `/loopd:welcome` first (its whole contract is this
plugin's `/welcome`), then `/audit`, `/answer`, `/fanout`, `/pr-review-request`,
`/new-project`, `/close-project` and finally the loop itself, which is `/dispatch` here.
The
**enforcement hooks** have made that move (above); `session-banner.sh` and
`push-state.sh` are still instance hooks and carry the same instance-root guard when
they follow.

**Agents had the REVERSE precedence, and that is why they moved last:** a same-named
project agent shadows the plugin copy (plugins are the lowest agent scope). So the eight
role agents shipped here in byte-parity with the instance copies first, and the name swap
retired those copies — the plugin is the only place they ship from now.
**Dispatch them namespaced, `loopd:<role>`.** A bare agent name does NOT resolve
(measured 2026-09-02), which is why the strings changed exactly once, here.
