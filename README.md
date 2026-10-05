```text
   ▄▄▄▄
◀━▐    ▌   loopd — the loop, running
  ▝▄▄▄▄▘
```

**You steer. They build. Two gates stay yours.**

**A control panel for running a small team of AI agents on your repositories.**

You describe the work. A project-manager agent breaks it into tasks. You approve. Engineer
agents build it **in the background**, open pull requests, and get reviewed. You merge.

You act like an engineering manager, not a pair programmer.

This repo is the **template**. You stamp out one **instance** per group of repos (work, a
side project, a client). Each instance is its own small git repo that sits beside those
repos and holds only the state of the work — never application code.

**Two colours, wherever loopd renders.** Blue `#5ea2ff` is the machine's — agents, code,
refs, running state. Pink `#ff7ac2` is yours — gates, decisions, anything waiting on a
person. No third accent, no status rainbow.

| | |
|---|---|
| **Needs** | [Claude Code](https://claude.com/claude-code), `git`, `gh`, bash. `python3` only for the optional board (all three renderers). |
| **Time to first loop** | about 10 minutes |
| **Storage format** | plain markdown ([OKF Knowledge Bundle](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md)) — the commands write the files for you |
| **License** | [MIT](LICENSE) |
| **Version** | [`VERSION`](VERSION) — one line, no extension, the only copy. A core change proposes the bump in its PR; the owner approves it by merging ([versioning](#versioning-and-drift)) |

---

## Contents

| Doc | Read it when |
|---|---|
| **This page** | setting up, or looking up a command or a config key |
| [docs/onboarding.md](docs/onboarding.md) | **you are new, or someone is joining you** — one page: install, the seven skills of week one, the two gates that stay yours |
| [docs/onboarding.md § Plugins that pair well](docs/onboarding.md#plugins-that-pair-well) | you are deciding which **other** plugins to install alongside loopd — four to install, two to skip, and why **`superpowers` must not be installed on a machine that runs the loop** |
| [docs/schema.md](docs/schema.md) | you need to know what a document type holds |
| [docs/autonomy.md](docs/autonomy.md) | you want the loop to promote or merge without you |
| [docs/operations.md](docs/operations.md) | installing and upgrading (the plugin half and the bundle half), the board's three renderers, worktrees, editor setup |
| [docs/migrating.md](docs/migrating.md) | **you already run a pre-plugin install** — upgrade it in place, or re-home it into a fresh folder without losing `projects/` or `knowledge/` |
| [docs/sharing.md](docs/sharing.md) | **several people will share one bundle** — the org's repo, `--org`, and who sets what |
| [docs/conventions.md](docs/conventions.md) | **you are changing this repo** — every design invariant and why it exists |
| [docs/releases/v1.0.0.md](docs/releases/v1.0.0.md) | **what 1.0.0 changed** — 91 merged PRs since the last tag, grouped: install, commands, agents, gates, docs |
| [The config layer](#the-config-layer) | you want this repo's agents, commands and hooks in `~/.claude` too |

Normative contracts live in the machinery itself: [`plugin/seed/SCHEMA.md`](plugin/seed/SCHEMA.md)
(document types, the verification predicate) and
[`plugin-yolo/companion/AUTONOMY.md`](plugin-yolo/companion/AUTONOMY.md) (the
delegated-autonomy modes, shipped by the `loopd-yolo` companion plugin).

---

## Install

**Two halves, on two clocks.** The **plugin** carries every slash command, the two
enforcement hooks and the eight role agents, and is installed once **per machine**; the
**bundle** carries the scripts, the `SessionStart` hook and the root documents, and is
stamped once **per instance**. A
machine with only the plugin has commands and nothing to read; a bundle with only the
stamp has the data and no way to drive it, and every `/loopd:…` reports *unknown
command*. Do the plugin first — it is one line, and it is what step 7 needs.
([docs/operations.md § 1](docs/operations.md#1-installing-and-upgrading-two-halves-and-neither-updates-the-other))

### 1. Install the plugin — once per machine

This repo is its own marketplace. In any Claude Code session:

```text
/plugin marketplace add cbmono/loopd
/plugin install loopd@loopd
```

Every command is namespaced: `/loopd:dispatch`, `/loopd:new-project`, and
the rest of the table [below](#commands); so is every role agent —
`loopd:software-engineer` and the rest — because a bare agent name does not resolve.
See [`plugin/README.md`](plugin/README.md).

**Installed as `ai-bridge@ai-bridge` before the rename?** [`MIGRATION.md`](MIGRATION.md)
moves the machine and each bundle over, in order.

**Already on `ai-bridge-v2`?** That name is gone in 1.0.0 — [the swap](docs/migrating.md).

### 2. Make the bundle directory

Name it **`_loopd-<group>`**, inside the group folder, beside that group's repos.

```bash
mkdir -p ~/workspace/<group>/_loopd-<group>
```

- The leading underscore pins it to the top of the group folder and keeps it visible (unlike a dotfile).
- The `-<group>` suffix distinguishes it from other groups' bundles.
- The group folder itself is **not** a repo — just a plain directory holding this bundle plus the group's repos, side by side, each its own repo.
- A bundle created before the rename keeps its `_ai-bridge-<group>` name: that prefix is still recognised wherever the directory name is read (`plugin/scripts/bundle-paths.sh`), so nothing has to move.

**No clone of this repo is needed.** The installer ships in the plugin. `/loopd:init`
creates the directory too, so this step is optional — it is here because naming it right
is the part worth doing deliberately.

### 3. Stamp it

```
/loopd:init ~/workspace/<group>/_loopd-<group>
```

It does three things, and **none of them is a symlink into a checkout**:

| # | Action | Detail |
|---|---|---|
| 1 | **Copies** `plugin/seed/` content — only if absent | never clobbers bundle data |
| 2 | **Converts** a bundle stamped by the retired `/loopd:init` | removes its machinery links and the managed `.gitignore` block; the data is untouched |
| 3 | **Links** the group's repos into `<bundle>/repos/` | skipped while `reposRoot` is the seeded placeholder. **The only symlinks a stamped bundle holds.** |

It is idempotent. It backs up any conflicting real file as `<name>.bak.<epoch>`.
`--refresh-seeds` additionally 3-way merges a seed change this repo has made since the
bundle was stamped; without it that drift is reported and nothing is written.

> **This replaced `/loopd:init`, and the reason is structural.** A plugin-shipped installer
> cannot stamp absolute symlinks into a plugin cache whose path changes on every update —
> every one of them would dangle. The symlinks existed so a `git pull` of this repo
> propagated into every bundle; `claude plugin update` gives that property for the whole
> tree, so they lost their reason to exist. `/loopd:init` and `/loopd:welcome fix` ship for one
> version as stubs that print the command to run instead.

#### It also asks who the team is — once

On a **first** stamp, at a terminal, it offers to collect the roster: one line per person,
`<github-login> <commit-email>`, **yourself first**. That fills in the tracked `people`
map and `defaultOwner`, plus this clone's gitignored `instance.config.local.json` — the
three values a shared bundle needs, which used to be hand-edited afterwards. See
[docs/sharing.md](docs/sharing.md#the-installer-asks-once).

- **Nothing is written until you confirm it.** ctrl-C, ctrl-D and an empty first line all
  write nothing at all, and say so — a half-answered roster is never left behind.
- **It never asks on a refresh, and never when stdin is not a terminal** (a script, a
  background agent). It prints what to edit by hand instead.
- **It never overwrites a value that is already there.**
- Skipping costs nothing: fill the same three values in by hand whenever you like.

### 4. Configure it

```bash
cd ~/workspace/<group>/_loopd-<group>
$EDITOR instance.config.json      # org, reposRoot, worktreeRoot, authorEmail
```

### 5. Give it a remote

```bash
git init && git add -A && git commit -m "chore: bootstrap control panel"
gh repo create <user>/_loopd-<group> --private --source=. --push
```

Keep the leading underscore in the repo name, so a fresh `git clone` lands a
`_loopd-<group>/` directory that matches the convention.

### 6. Run your first loop

```bash
cd ~/workspace/<group>/_loopd-<group>   # this matters — see below
claude
```

Then, inside the session:

```text
/loopd:new-project add rate limiting to the public API
```

Answer its questions. Review the draft tasks. Promote the ones you want (`draft → ready`).
Then:

```text
/loop 10m /loopd:dispatch
```

`/loop` is Claude Code's own repeat-a-slash-command primitive, and it is the standard way
to run the cadence: one pass every ten minutes, in the session you are already in, with
nothing installed to drive it. Omit the interval (`/loop /loopd:dispatch`) on a quiet
bundle and the model paces itself. A pass that fires while a tick is still running prints
one line and skips — the dispatch lock refuses it, so a clock can never start a second
orchestrator. `docs/operations.md` → "Running the loop on a cadence" has the reasoning.

**Always launch Claude from inside the instance directory.** The bundle's linked role
agents, its `SessionStart` banner and this panel's `CLAUDE.md` load from the instance's
`.claude/`, and that is chosen by the working directory — not by what your editor has
open. Everything the plugin carries is per machine and resolves anywhere.

---

## The core loop

```text
/loopd:new-project  →  you promote draft → ready  →  /loopd:dispatch  →  you merge the PR
```

`/loopd:dispatch` is serial and completion-gated — one tick at a time. Run **one per
instance**. The launcher takes a per-clone lock (`.tick-lock`) immediately before each
dispatch, and the tick runs the same check on entry — a resumed tick never passes through
the launcher, so one that finds no lock is refused rather than allowed to run. That
guarantee survives a compaction instead of resting on the session remembering it
dispatched — [→](docs/operations.md#one-tick-at-a-time-the-dispatch-lock).

Two gates stay yours by default:

1. **Promote** a task from `draft` to `ready`.
2. **Merge** the PR (build projects) or **approve** the deliverable (research projects).

The idea is to **steer, not watch**. Role agents run in the background and bubble up
results and questions, not every step.

Both gates can be delegated — see [docs/autonomy.md](docs/autonomy.md). That capability is
**off unless installed**, literally: it lives entirely in the separate
[`loopd-yolo`](plugin-yolo/README.md) companion plugin, and uninstalling that plugin
makes every project `gated` again with no other edits.

### Who runs what, end to end

One `kind: build` project, from `/loopd:new-project` to merge. Every step links to the document
that **owns** its rule; nothing here restates one. Tiers are the **seed defaults** — each
instance sets its own in `roleTiers`/`models`
([model routing](docs/operations.md#model-routing)).

| # | Step | Who runs it |
|---|---|---|
| 1 | **Scaffold** — slug, objective, phases, seed `draft` tasks | you and the main session, interactively [→](plugin/skills/new-project/SKILL.md) |
| 2 | **Commit** the scaffold and its registration as one change | main session, via `commit-as.sh` |
| 3 | **Scaffold review**, three stages: `validate-bundle.sh`, then an external reviewer, then the `qa-reviewer` fallback. Stage 1 gates the rest; stages 2 and 3 are advisory, and stage 2 is *dispatched* rather than waited on | main session; `qa-reviewer` (`deep`) on the fallback [→ step 8](plugin/skills/new-project/SKILL.md) |
| 4 | **Refine** each `draft` — fill `acceptance_criteria`, raise `open_questions` | `project-manager` (`deep`) [→](plugin/agents/project-manager.md) |
| 5 | **Approach critique** — **mandatory on its trigger** (a complex or heavily-inferred `kind: build` draft), advisory in what it may decide; its concerns land in `advisor_notes` and gate nothing | `plan-architect` (`apex`), dispatched by the PM [→](plugin/agents/project-manager.md) |

> ### HUMAN GATE 1 — you promote the task `draft → ready`
>
> **Nothing is dispatched until you do.** The PM refines and critiques a draft but never
> sets `ready` ([two human authorities](plugin/seed/SCHEMA.md)).

| # | Step | Who runs it |
|---|---|---|
| 6 | **Dispatch** the `ready` task — its own worktree and branch, both recorded on the task before the agent spawns | `project-manager` → the assignee [→](plugin/agents/project-manager.md) |
| 7 | **Build it**, then **self-review your own diff** — a pre-filter, never the gate | `software-engineer` / `devops-engineer` (`deep`) [→](plugin/seed/CONVENTIONS.md) |
| 8 | **Open the PR** carrying the task's `acceptance_criteria` as a ✓/✗ table — the artifact `pr-body-clearance.sh` reads. The agent never merges | the same agent |
| 9 | **Independent review** at the PR's current head: the external reviewer where one is configured, else the `qa-reviewer` fallback. The PM reads that verdict with `review-clearance.sh`, and `review-rounds.sh` stops it at two rounds | external reviewer, else `qa-reviewer` (`deep`) [→](plugin/seed/SCHEMA.md) |

> ### HUMAN GATE 2 — you merge the PR
>
> **One `✗` in that criteria table blocks it, however green CI is**
> ([SCHEMA.md](plugin/seed/SCHEMA.md)).

The next tick reflects the merge — `status: done`, and the task's worktree is reclaimed.

## Commands

Run these inside an instance.

| Command | What it does |
|---|---|
| `/loopd:new-project <description>` | (plugin) scaffolds a project: phases, draft tasks, acceptance criteria. Asks for the capability flags you didn't pass |
| `/loopd:dispatch [gap]` | (plugin) the serial background loop: dispatch, track, report. `/loopd:dispatch 10m` ticks every ten minutes |
| `/loopd:answer` | (plugin) answer the PM's open questions from inside the session |
| `/loopd:board` | (plugin) `serve` — **the default, so a bare call serves** — the board on a local URL, one process per bundle; `publish` — the same page as a private artifact, at the same URL every run |
| `/loopd:pr-review-request <pr>` | (plugin) ask for an independent review of a PR |
| `/loopd:audit` | (plugin) the slow counter-metric — is the throughput moving the real goals? Read-only, never acts |
| `/loopd:fanout <task>` | (plugin) parallel work across several repos |
| `/loopd:close-project [<slug>]` | (plugin) close a project and fold its conclusions into `knowledge/`, then remove its folder — or freeze and keep it, on `retain: true`. No slug opens a picker of the projects, multi-select, and asks about `--force`. [→](docs/schema.md#closing-a-project) |
| `/loopd:welcome [check\|fix]` | (plugin) reprint the SessionStart banner; `check` reports state that could be wrong, `fix` repairs only the idempotent tier. [→](docs/conventions.md#21-loopdwelcome-reports-facts-that-can-be-false-and-fix-is-tiered-in-code) |
| `/loopd:brief-me [project]` | (plugin) a since-you-last-looked digest, or a meeting-ready brief for one project. Read-only |
| `/loopd:capture <notes>` | (plugin) turn a decision or meeting notes into drafted projects and tasks, with provenance — never promoted |
| `/loopd:work <task>` | (plugin) work one task in **this** session, ledger kept for you — the solo alternative to dispatching an agent |
| `/loopd:handoff <path> <login>` | (plugin) transfer a task or project to another human, with the context that makes the transfer real |
| `/loopd:kb-apply <report>` | (plugin) apply one `knowledge/` reflection report after reading it — the only path that writes a proposal. The scheduled `kb-propose.sh` only ever proposes |

Flags `/loopd:new-project` accepts: `kind=research`, `autonomy=<mode>`, `clis="…"`,
`browser=off|claude-for-chrome` (default `off`), `/yolo`, `/cli …`, `/claudeforchrome`,
`--no-commit`.

## The team

| Role | Does |
|---|---|
| `project-manager` | runs the loop: refines drafts, dispatches, tracks, reports |
| `software-engineer` | writes code in a target repo and opens the PR |
| `devops-engineer` | infrastructure, CI, deploys |
| `qa-reviewer` | the **independent** verification gate — fresh context, real signals |
| `cataloguer` | folds conclusions into `knowledge/` |
| `auditor` | read-only drift check for `/loopd:audit` |
| `failure-analyst` | diagnoses a failing check or a broken build |

All eight ship in the **plugin** and are dispatched **namespaced** —
`loopd:software-engineer`, `loopd:qa-reviewer`, and so on. A bare agent name does
not resolve (measured 2026-09-02). A task's `assignee:` field stays bare; the PM adds the
namespace when it spawns.

Role dispatches are routed to a cost-appropriate model per tier
([docs/operations.md § model routing](docs/operations.md#model-routing)).

## Where the work lives

```
_loopd-<group>/
├── objectives/        OPTIONAL — goals that outlive one project (`/loopd:init <dir> --with-objectives`)
├── projects/<slug>/
│   ├── project.md     kind, status, autonomy, owner, target_repo
│   ├── phases/        ordered stages
│   ├── tasks/         the unit an agent is dispatched on
│   └── deliverables/  research output (no repo, no PR)
├── knowledge/         services, findings, teams, runbooks, references
├── repos/             symlinks to the group's repos (gitignored)
├── AWAITING.md        what needs you (derived, gitignored)
├── SNAPSHOT.json      board input (derived, gitignored)
└── instance.config.json
```

Document types and their fields: [docs/schema.md](docs/schema.md).

## Two kinds of project

| | `build` (default) | `research` |
|---|---|---|
| Output | PRs to a `target_repo` | deliverables inside the bundle (`projects/<slug>/deliverables/`) |
| Who executes | dispatched role agents | **the human**, in-session — the PM tracks but never dispatches |
| `target_repo` | required | not asked |
| `clis` prompt | asked, pre-filled from detected CLIs/MCPs | **not asked** (recorded if you pass `clis=`) |
| `browser` | asked | asked — web research is its clearest case |
| Scaffold review | three-stage chain | skipped |
| Gate | you merge the PR | you approve the deliverable |

A research project is asked **less on purpose**. Each dropped question describes machinery
a research project never runs, so offering it would ask you to authorise tools nothing will
use. **Don't restore a question for symmetry** —
[docs/conventions.md invariant 5](docs/conventions.md#5-build-and-research-projects-are-deliberately-asymmetric).

## Answering the PM's questions

When a `draft` is blocked it lists numbered `open_questions` (`Q1:`, `Q2:`, …).

1. Open the task doc.
2. Append ` --- <answer>` to the question line:
   ```
   Q1: which region should we default to? --- eu-central-1
   ```
3. The next tick treats everything after the ` --- ` as your answer, folds it into the
   task, and clears the question.
4. The `draft` becomes promotable once the list empties.

Answering in chat during a session works too (`/loopd:answer`).

The cleared entry is **moved, not deleted** — it lands in `answered_questions` as one flat
line, `<ISO 8601> by <login> · <the entry verbatim>`. It is a human audit record: nothing reads it and
no gate consults it. **No customer PII in an answer** — unlike the question you clear, this
list persists for the life of the repo.

## What needs you

`AWAITING.md` is the instance's **one** status artifact: a queue of just the items a human
decision unblocks.

| Marker | Means |
|---|---|
| ✅ | approve |
| ❓ | answer |
| 🔀 | merge |
| ⛔ | unblock |
| 🏁 | close |

Each item carries a real link. Every `/loopd:dispatch` tick rewrites the file, and a `SessionStart`
hook injects its items at launch.

In-flight and upcoming work is deliberately **excluded** — it needs no decision, and a
queue you scroll past is a queue you stop reading. **There is no `/status` command and no
full board; don't reintroduce one.**

**On by default, off by deletion.**

| Action | Effect |
|---|---|
| `rm AWAITING.md` | the queue is off **for good** — an installer re-run will not resurrect it |
| `touch AWAITING.md` | back on |

Derived and gitignored; never hand-edit it. Reasoning:
[docs/conventions.md invariant 3](docs/conventions.md#3-awaitingmd-is-loopds-only-status-artifact-and-it-is-opt-in-by-presence).

A cross-instance board is available too, on the same off-by-deletion rule
([docs/operations.md § the board](docs/operations.md#5-the-cross-instance-board-optional)).
**Read the field list before you carry one off the machine** — nothing publishes it, but a rendered file is still a file.

## Three ways to see the board

One snapshot, four renderers. `scripts/write-snapshot.sh` derives each instance's
`SNAPSHOT.json`; all four read it and none of them reads the bundle. Pick by what you
are doing, not by which is newest.

| You want | Run | Costs |
|---|---|---|
| a look right now, in the terminal you are in | `scripts/print-board.sh` | nothing |
| a page to open locally — the one each tick renders | `scripts/build-board.sh --standalone .` | a re-run, or a looping instance |
| **a live page in the browser, on a fixed local URL** | `/loopd:board serve` | **a process you keep running** |
| a page that updates itself as you work, no browser | `scripts/watch-board.sh` | **a process you keep running** |

```bash
scripts/print-board.sh                      # columns: instance, project, phases, tasks, awaiting
scripts/build-board.sh --standalone .       # ./board.html — THIS instance only, openable in a browser
scripts/build-board.sh --standalone         # the same, but every instance in boardInstances (see below)
scripts/build-board.sh                      # the same page as a BODY — no <html> wrapper, for embedding
scripts/watch-board.sh                      # ./.board-live/board.html, re-rendered on every change
scripts/board-serve.sh                      # http://localhost:<boardPort> — the same page, served and auto-reloading
```

**The page keeps itself current, locally.** Every `/loopd:dispatch` tick re-renders it to
`.board-live/board.html` — gitignored, on this machine — and reports the path; a
`SessionStart` hook prints the same path when a session starts. `board: false` in
`instance.config.json` turns that off; absent or `true` leaves it on, which is the seeded
default ([docs/operations.md § rendering it from each
tick](docs/operations.md#rendering-it-from-each-tick)). It
is only as fresh as the last tick — the page's masthead says when that was, and
`watch-board.sh` is the view that follows your work in between.

**`/loopd:board serve` is the local web app, and it is what a bare
`/loopd:board` does**: one process per bundle, on a port
derived from the bundle path (`boardPort` in `instance.config.local.json` overrides it),
serving `.board-live/` on `127.0.0.1` and nothing else. It re-renders within two seconds of
`SNAPSHOT.json` changing and the page reloads itself. No LLM is in that path — a tick used
to commit a `/board.html` into the bundle repo instead, and no longer does.

**`/loopd:board publish` publishes the same page as a private artifact**, at a URL that does
not change between runs and that the session banner prints. It is the route to a phone
with no clone on it; `serve` stays the route on the machine itself. The
URL is recorded per machine, in `instance.config.local.json`, because artifact publishing
is account-scoped — no share level lets a second account update your page. **A headless
tick never publishes**: measured 2026-09-05 on Claude Code 2.1.261, a `claude -p` session
has no artifact tool at all, so the tick prints `run /loopd:board publish to refresh` and stops
there. Opening it, including from a phone: [docs/operations.md §
opening-the-board](docs/operations.md#opening-the-board-laptop-phone-published-live).

**The board is per installation, and it still shows everybody.** Your own projects come
from your `SNAPSHOT.json`; every other owner's is a collapsed, **named** section below
them, read from the tracked task documents at your current git `HEAD` (the one thing both
clones share) and cached against that SHA. That is why the local board loses nothing on a
shared bundle: the cross-owner half never came from a shared page, it came from git.

**The watcher's cost is the real one, so read it before you pick it.** It needs a
resident process, and loopd deliberately has none — its agents are ephemeral
subagents inside one session, and nothing here runs between sessions. So the live page
is a terminal tab you keep open: it stops when you close it, sleep the machine, or lose
the session, and it gives you nothing to share and no phone access. If any of that
matters, the other two renderers cost nothing and you re-run them.

Three properties are shared by all three, because they belong to the snapshot rather
than to any renderer:

1. **No `SNAPSHOT.json`, no appearance.** That instance is absent — no placeholder, no
   warning — and no renderer ever creates the file.
2. **One broken instance cannot blank the board.** An unreadable snapshot becomes a
   visible note; a snapshot carrying wrong *types* degrades to zero for that field and
   everything else still renders.
3. **Every title is escaped for its output medium** — HTML for the page, control
   characters and ANSI sequences for the terminal. Task titles are human prose.

`print-board.sh` colours only a terminal and honours `NO_COLOR`, so a board piped into a
file, a ticket or a PR body carries no escape codes. On a narrow terminal it drops
columns that are zero in every row (and says which), clips **names** with `…`, and never
clips a **number** — a wrong count is worse than a missing column. Below the width where
a table still fits, it prints one short block per project instead of wrapping.

`watch-board.sh` uses `fswatch` when it is installed and a polling loop (default 2s) when
it is not; either way it is stopped with Ctrl-C and leaves nothing behind.

## Safety rails

The short version. Each line links to the full reasoning; **none of them is decoration.**

| Rail | Rule |
|---|---|
| **Independent review** | every PR is cleared by a reviewer with fresh context, never the implementing agent's self-report. [→](docs/autonomy.md#the-verification-gate) |
| **Merge gate** | `required-checks.sh` — **exit 0 is the only clearance.** Missing, pending, skipped and unreadable all refuse. [→](docs/autonomy.md#required-checks--exit-0-is-the-only-clearance) |
| **Review gate** | `review-clearance.sh` — a **green check from a reviewer that declined to review is not verification.** It reads the reviewer's artifacts, takes evidence and pinning from the reviews **API** (`state` + `commit_id`), leaves text matching only the job of spotting a refusal, and refuses on unknown state. `required-checks.sh` asks it on **every** PR, so a check's name never settles whether anybody looked. [→](docs/autonomy.md#the-verification-gate) |
| **Review rounds** | `review-rounds.sh` — **two rounds, then the human decides**, as a number a dispatcher reads rather than a rule it must remember. Exits non-zero at or past two, so a third verifier is refused. [→](docs/autonomy.md#two-rounds-then-the-human-decides) |
| **Dispatch check** | `check-dispatch.sh` — an agent's "done" is not evidence that a PR exists. Did `status:` move, does `pr:` name a URL, does that PR resolve. **Report-only.** [→](docs/autonomy.md#did-the-dispatch-produce-its-pr) |
| **Delegated autonomy** | one uninstallable plugin. Uninstall `loopd-yolo` and every project is `gated`; `resolve-autonomy.sh` is the one reader, and a bundle's own root file still wins. [→](docs/conventions.md#4-a-capability-some-deployments-must-not-have-should-be-one-deletable-file) |
| **Dispatch lock** | `tick-lock.sh` — one PM tick at a time, taken by the launcher in the same operation that checks it, **and checked again by the tick itself**, since a resumed tick never passes through the launcher. A dispatched tick does not refuse its own lock: unclaimed means it is that dispatch. A tick that finds **no** lock was not dispatched at all — it is refused (exit 4), because **a tick is never resumed**. The claim on a lock records **whose** it is and from **which source**, and the trust is asymmetric — a runtime-derived id (`CLAUDE_CODE_SESSION_ID` names the *session*, not the tick) may refuse a claim but never clears one, so a merely-matching identity is exit 2 rather than a guess in either direction. Stale, or unattributable, means **ask the human**, never silently delete and never silently adopt. Per clone, not cross-machine. [→](docs/operations.md#one-tick-at-a-time-the-dispatch-lock) |
| **Worktrees** | `prune-worktrees.sh` **reports, never deletes.** Do not add a delete there, not even behind a flag — it destroyed three running agents' worktrees once, by inferring from a scan. `reclaim-worktree.sh` deletes ONE path a task recorded, and only when that task is `done` with every PR merged. [→](docs/conventions.md#7-prune-worktreessh-is-report-only-and-that-is-load-bearing) |
| **Bundle repair** | `migrate-bundle.sh` is report-only by default and fixes only what has one right answer. **A false success is worse than the error it claims to fix.** [→](docs/conventions.md#9-migrate-bundlesh-fixes-only-what-has-one-right-answer-and-is-report-only-by-default) |
| **Retiring content** | machinery symlinks are swept; **seed content is only ever reported**, never deleted. [→](docs/operations.md#2-retiring-content-swept-vs-reported) |
| **Board data** | the board's field list is a data-governance boundary — no question text, no document bodies, no author identity, no out-of-bundle paths. Nothing publishes it now, and a rendered file is still copyable. [→](docs/operations.md#before-it-leaves-the-machine-know-what-it-carries) |
| **Untrusted text** | `AWAITING.md` items and the per-turn state injection are fenced as data before they enter session context. Keep the boundary. [→](docs/conventions.md#12-three-loopd-behaviours-that-all-exist-because-a-silent-wrong-answer-is-worse-than-a-loud-one) |
| **No customer PII** | not in a task title, not in an answer, not in a `Finding`. Titles reach the board; answers persist for the life of the repo. |
| **Drift check** | `/loopd:audit` is read-only and advisory. It catches an autonomous loop gaming itself; it is not a merge-blocking guarantee. [→](docs/autonomy.md#the-audit-counter-metric) |

## Configuration reference

`instance.config.json` (tracked) and `instance.config.local.json` (gitignored, per
machine). The **one** authoritative list of which keys are locally overridable is
[`SCHEMA.md` → "Per-machine config overrides"](plugin/seed/SCHEMA.md).

| Key | Absent means | Overridable per machine |
|---|---|---|
| `org` | — | yes |
| `group` | the bundle **directory** name minus `_ai-bridge-` / `_loopd-` | **no** — one bundle, one name |
| `reposRoot` | required for dispatch | yes |
| `worktreeRoot` | **`<reposRoot>/_wt`** | yes |
| `authorEmail` | fall through to `git config user.email` | yes |
| `people` (login → commit email) | fall through to `authorEmail` | **no** — both clones must agree |
| `defaultOwner` | unowned work is dispatched by **every** clone | **no** |
| `ownerGithubUser` | this clone has no configured human | **local file only** |
| `maxAgentsInFlight` | **4** | yes |
| `maxPrLoc` | **500** | yes |
| `maxPrFiles` | **100** | yes |
| `models` / `roleTiers` | everything inherits the session model | yes |
| `externalReviewer` | the CodeRabbit CLI | yes |
| `boardInstances` | the board is just this instance | yes |
| `boardPort` | derived from the bundle path, in the 4xxxx band | **per machine only** — a port belongs to a laptop, not to a bundle everyone clones |
| `board` | **on** — `SNAPSHOT.json` is seeded and each tick renders `.board-live/board.html`, which `/loopd:board serve` serves | **no** — one instance, one answer |
| `codegraphSkip` | index every product repo | yes |

Environment knobs: `PUSH_STATE_MAX` (default **12**), `PRUNE_ACTIVE_MINUTES`,
`CODEGRAPH_SKIP`, `CONTROL_PLANE_AUTHOR_EMAIL`, `NO_COLOR` (honoured by
`print-board.sh`), `WATCH_BOARD_WATCHER` (`auto` when absent — `poll` or `fswatch`
override the watcher's probe).

## Scripts

They ship in the plugin (`plugin/scripts/`) and are invoked as
`${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh`. Run from a bundle root unless noted.

| Script | Does | Writes? |
|---|---|---|
| `init-bundle.sh` | `<dir>` — creates or refreshes a bundle, and converts one stamped by the retired `/loopd:init`: seed content copied where absent, machinery links removed, `repos/` linked. `--config` links the `~/.claude` layer instead | yes, that bundle |
| `refresh-seeds.sh` | `<dir>` — 3-way merges a seed change this repo made since the bundle was stamped; a hand-diverged file is reported, never forced, and its conflicted merge is saved as `.bak.<epoch>` | only with `--apply` |
| `validate-bundle.sh` | schema errors + dangling frontmatter references | no |
| `normalise-config.sh` | `<dir>` — reports what is out of place across the two config files: MISPLACED (a per-machine key in the tracked `instance.config.json`, or a tracked-only key such as `defaultOwner` in `instance.config.local.json`), MISSING (a seed key the tracked file lacks) and ORDER. Values are never changed — only placed, ordered, or added when absent — and the tracked file is left **staged**, never committed. Run by every `/loopd:init` stamp | only with `--apply` |
| `migrate-bundle.sh` | mechanical schema repairs | only with `--apply` |
| `ledger.sh` | `append` / `show` a knowledge item's append-only `ledger:` line — why it changed, who applied it, which items; no verb edits or removes an entry | `append` only, that one item |
| `kb-propose.sh` | the scheduled half of the reflector: runs the instance's proposer and writes the surviving proposals to ONE draft task — the report. It writes nothing under `knowledge/`, never `AWAITING.md`, and never reaches the apply path. 0 a report was written · 1 nothing to propose · 2 usage | yes, one task document |
| `kb-apply.sh` | the human half, behind `/loopd:kb-apply`: applies exactly the proposals one report names, plus the regenerated index, one `ledger:` entry per item, the report's `status: done` and ONE commit. Every proposal is checked first, so a stale, hand-authored or missing item refuses the whole report | yes, the items the report names |
| `kb-usage.sh` | `record`/`sweep` — the citation store and the archive sweep that reads it. `record` runs `cite-check.sh` on a text and stores the slugs it kept, one file per text; `sweep` lists each current Finding against every archive qualifier, and `--propose` emits only the ones past all of them, as `kb-propose.sh` proposals that land through `kb-apply.sh`. Silence alone never archives | `record` only, one citation file under the bundle directory |
| `project-paused.sh` | answers whether a project is paused, as one predicate with a three-value exit | no |
| `prune-worktrees.sh` | classifies worktrees, prints the `remove` commands | **never** |
| `reclaim-worktree.sh` | `<task-path>` — removes the ONE worktree that task recorded, with no scan. 0 removed (`--dry-run`: every guard passed) · 1 REFUSED · 2 cannot answer · 3 nothing to do. Exit 0 needs `status: done` **and** every `pr:` URL MERGED, so closed-unmerged and an empty `pr:` both refuse, as do a dirty or unpushed tree, a detached HEAD, ignored content outside the cache allowlist, and a live process in the tree | yes — that one worktree |
| `commit-as.sh` | commits as the right agent identity | yes |
| `required-checks.sh` | resolves a PR's required checks | no |
| `review-clearance.sh` | asserts an artifact **evidencing a completed review** exists on a PR (never a green check) | no |
| `review-rounds.sh` | counts a PR's completed verification **rounds**; exit non-zero at or past **two** | no |
| `rebase-pr.sh` | `<pr>` — the deterministic first try at a CONFLICTING PR, so a one-hunk merge magnet costs no agent: rebase in a throwaway worktree and auto-resolve **only** the known shapes (an `EXPECTED_ASSERTIONS=N` counter → the three-way sum of both sides' deltas; a ratchet row both sides lowered → recomputed from the merged file; a comment history → both kept), assert the result parses and kept exactly one assignment, then push with an explicit `--force-with-lease=<ref>:<the host's own headRefOid>` and let CI verify. 0 pushed · 3 an **unclassified** conflict, named, which is the one exit that earns an agent round · 4 the resolution failed its own check · 5 refused (fork head, closed) · 6 the lease no longer holds. Every non-zero leaves the branch and the remote untouched | yes — a temp worktree, and a lease push to that PR's own branch |
| `pr-body-clearance.sh` | asserts a PR **body** carries the required shape — the TL;DR heading, a `Verified:` line that cites something, and a criteria table whose heading tally matches its rows. `--body-file` decides on a draft before you open it | no |
| `pr-comment-clearance.sh` | asserts a **reply to review findings** carries a verdict per finding, and that no element exceeds the measured ceiling. `--comment-file` decides before you post | no |
| `pr-verdict-clearance.sh` | compares the **worker's** `✓`/`✗` criteria table (the PR body) with the **checker's** re-derived `PASS`/`FAIL` one (a PR comment). 0 agree · 1 the worker passed what the checker failed · 3 a checker row with no verdict or no command · 4 the checker is the PR author · 2 unknown | no |
| `report-clearance.sh` | `--body-file <path\|->` — refuses a tick report that is not the three-part shape: what happened, what is blocking (only when something is), and a numbered `Needs you:` list. One `REFUSED <rule>: …` line per breach; 0 clear · 1 refused · 2 usage. Called by `hooks/report-shape.sh` on `SubagentStop`; the spec and what each detector does not catch are in `agents/project-manager.md` → "Output". `--self-test` proves the file is complete | no |
| `cite-check.sh` | keeps the `[[finding-slug]]` citations a brief actually carried, drops the rest, and exits 1 when a citing line ends up with none. Reports a dropped id as `UNREAD` (in `knowledge/index.md`, not in the brief) or `FABRICATED` (in no row) | no |
| `check-dispatch.sh` | `<task-doc>` — did the dispatch actually produce the PR it promised | **never** |
| `control.sh` | the live kill switch for one dispatched agent — `agents`, then `halt`, `gate` or `steer` it | yes, `.claude/control/` |
| `resolve-model.sh` | `<agent>` — prints the model alias it should run on, from `roleTiers`/`models` (local file first; the bundle stamp seeds both there). No entry ⇒ nothing on stdout, exit 1, and **a line on stderr** saying the caller would otherwise inherit the session model | no |
| `tick-lock.sh` | `acquire [--as launcher\|tick]`/`release`/`status` — the per-clone PM dispatch lock; exit 0 is the only clearance to dispatch or to run a tick | `acquire`/`release` only, `.tick-lock` + `.tick-lock.claim` (gitignored) |
| `tick-delta.sh` | `check [--gap <interval>]`/`record`/`digest` — the idle-tick fast-path probe and the tick's one-command orientation: a full tick records a fingerprint (bundle HEAD, task statuses, open-PR heads/states/decisions), the next tick compares — only a byte-for-byte match (exit 0) permits skipping the full walk, and every doubt is the full tick. The `IDLE:` line is ONE line and IS the quiet tick's whole report, so `--gap` makes it name the next check; `digest` prints the same walk enriched (project/task fields + PR facts) so step 1 is one read instead of N. `record --close "<summary>" [--tick ISO] [--tokens N --tools N --duration-ms N]` is the ledger half: it appends the `close:` line **beside** the tick's own `open:` line (never over it, so the pair carries the tick's wall duration), copying that line's timestamp and `by <login>`, with the three notification numbers in the one fixed form `agent-usage.sh fmt` owns — offline, and refused if the entry is already closed. `--tick` names which open entry to close, matched exactly; without it a close is taken only when exactly one entry is open, never guessed between two | `record` only, `.tick-state` (gitignored) and `log.md` on `--close` |
| `agent-usage.sh` | `fmt`/`dispatch`/`total`/`settle`/`series` — what the harness handed back, **in tokens and never in money**: `fmt` is the one fixed `usage tokens=N tools=N ms=N` form every other writer calls, `dispatch <task-doc> --role R --model M` appends one `# Notes` line per role dispatch from that agent's notification (a re-dispatch appends a second), `total <task-doc> --pr <url>` sums those lines against the merged PR at reflect time (no dispatch lines ⇒ `usage UNKNOWN`, never zero), and `series` prints the month-by-month figures from `log.md`'s `TICK` pairs and those dispatch lines — file reads only, no `gh` and no transcript | `dispatch`/`total` only, that task document |
| `session-usage.sh` | `<session-id> [--settle <task-doc>]` — what ONE detached role-agent session cost, read from that session's own transcript and counted **once per message** (a transcript repeats a message's usage on every content block's line): prints `usage tokens=N tools=N ms=N cached=N`, or `usage UNKNOWN` on any doubt — no transcript, two candidates, no usage record, no `jq`. `--settle` hands the numbers to `agent-usage.sh settle`, which fills that task's last UNKNOWN dispatch line. The one file that knows where a transcript lives | only with `--settle` |
| `task-owner.sh` | resolves and compares a task's owner | no |
| `stall-counter.sh` | `record`/`escalate`/`status` — the per-task stall memory: `record <task-doc> --blocker <text>` after each round (`--progress` when the PR moved) counts consecutive rounds on the same blocker and **exits 1 at or past `maxStallRounds`** (absent ⇒ **2**); `escalate` then sets `status: blocked`, notes the blocker and prints the one `⛔ **unblock**` line for `AWAITING.md` | `record`/`escalate` only, that task document |
| `do-not-repeat.sh` | `append`/`brief` — the per-task memory of DEAD ENDS: `append <task-doc> --line <text>` records one approach an ended round already tried and the evidence it failed on (folded to one line, 200 chars, deduped, **capped at 10** — exit 1 past it, fold the oldest into `# Notes`); `brief` prints those lines verbatim under a fixed heading for the next dispatch's brief, and nothing at all when there are none | `append` only, that task document |
| `fold-answers.sh` | `<task-doc>` — moves every ` --- `-answered `open_questions` entry into `answered_questions`, stamped `<ISO> by <login> · <entry verbatim>` with the login from `decision-stamp.sh`. Exit 4 rather than leave one entry in both lists, exit 3 rather than emit a list it could not round-trip; `--list <doc> <key>` is the same parser, read-only | yes, that task document |
| `dispatch-brief.sh` | `<task-doc>` — the four fixed sections the PM pastes into a dispatch brief verbatim: `## Grounding (<target_repo>)`, the target repo's `knowledge/services/<repo>.md` entry points capped at **15 lines** (absent that doc, one line telling the agent to draft it for the `cataloguer`); `## Effort`, the files/LOC/turns budget derived from the task's criteria count and the instance's `maxPrLoc`/`maxPrFiles`; `## Commit attribution`, the resolved `commitAttribution`; and `## Scratch`, a directory keyed on the task slug so two agents in one tick cannot pick the same file, `git check-ignore`d against the target repo's clone | no |
| `release-bump.sh` | `<minor\|patch>` — moves the version in the **five** places that carry it (`VERSION`, `plugin/VERSION`, both manifests, and the banner sample, whose `─` rule is re-cut to the new header's width), on the **default branch, after a merge**. Refuses on a feature branch or a dirty tree; commits and prints the push, never pushes | yes, those five |
| `check-template-version.sh` | is the plugin on this machine older than the remote's default branch — prints a line **only when behind**, silence on every failure | not the instance — `--fetch` (opt-in) updates the template checkout's remote-tracking refs, nothing else |
| `close-project-folder.sh` | closeout's folder step — `git rm -r` the project, or freeze and keep it on `retain: true` | only with `--apply` |
| `write-snapshot.sh` | refreshes `SNAPSHOT.json` | only if it already exists |
| `build-board.sh` | renders the HTML board (anywhere; needs `python3`) — pass `.` to render THIS instance only | yes, the output file |
| `print-board.sh` | prints the board in the terminal | no |
| `status-line.sh` | the bundle's Claude Code `statusLine`: one coloured line — `AI Bridge · <n> in flight · agents <n> running[, <n> no process] · <n> need you · lock free\|held · last tick <hh:mm>` — from task frontmatter, `agent-sessions.sh view`, `AWAITING.md`, `.tick-lock` and `log.md`'s last `* TICK`. No `jq`, no `gh`, no model; a number it cannot establish renders `?`, and outside a bundle it prints nothing. The `need you` segment is three-state: a deleted `AWAITING.md` is the queue's off switch, so the segment goes; an unreadable one says so and names its own `chmod +r` repair. `/loopd:init` installs it into the BUNDLE's `.claude/settings.json` and never the user's | yes — the 10-second `agents` cache under `${XDG_CACHE_HOME:-~/.cache}/loopd/` |
| `watch-board.sh` | renders the board into `.board-live/` and re-renders on every change | yes, the page (gitignored) |
| `board-serve.sh` | serves `.board-live/` on `127.0.0.1:<boardPort>` and re-renders it when `SNAPSHOT.json` changes — one process per bundle | yes, the page (gitignored) |
| `link-repos.sh` | refreshes `<instance>/repos/`, and writes each linked repo's `.git/loopd-bundle` — the marker the two safety hooks follow from a role agent's worktree back to this bundle | yes |
| `index-kb.sh` | builds local CodeGraph indexes for the group's repos (code intelligence — **not** the knowledge base) | yes |
| `build-awaiting.sh` | renders `AWAITING.md` — the heading and its count, the `* ` marker `session-banner.sh` greps literally, the glyph, the verb and the link — from the task documents, never `SNAPSHOT.json`. It classifies `grant` against `answer` from the `open_questions` entry itself, narrows to this clone's human with `task-owner.sh`, and takes each row's trailing sentence as a `--trailer`. No `AWAITING.md` ⇒ it writes nothing and exits 0 | yes, that file (gitignored) |
| `build-kb-index.sh` | regenerates `knowledge/index.md` from document frontmatter; `--check` fails on a doc with no row, a row pointing at no file, an empty summary, an unescaped pipe, a status outside `{current, superseded, corrected}`, a tag outside `knowledge/vocab.md`, a dangling supersession edge, or (as a warning, an error under `--strict`) a bundle-relative link in `knowledge/**` or a `source:` path token that resolves to nothing | yes, that index |
| `kb-sync.sh` | mounts, reads and writes a knowledge base held in another repository (`knowledge` in `instance.config.json`) — `mount` clones it into `knowledge/` as a nested, gitignored clone, `pull` fast-forwards it under a named timeout, `status` reports unpushed KB commits, and `commit` is the one bounded write transaction: rebase, regenerate the index, commit, push, one retry, then stop and report. Absent the key it exits 3 and touches nothing | yes, the mounted KB (never the bundle) |
| `kb-migrate.sh` | moves a bundle's own `knowledge/` into the repo `knowledge.repo` names — one recorded commit pair, refuses a dirty tree, prints every path it moved, and seeds the KB repo's harness-neutral reading rule | yes, both repos |
| `kb-sweep-due.sh` | does this tick owe the cataloguer a `knowledge/` sweep — due only when it dispatched nothing this round, no cataloguer is in flight, a slot is free under `maxAgentsInFlight`, and `build-kb-index.sh --check` reports at least one ERROR. On exit 0 it prints the trigger line and the error list, which is the cataloguer's brief | no |
| `papercuts.sh` | the cheap end of the knowledge loop — `add` appends one validated line to `knowledge/papercuts.md`, `check` refuses a malformed entry, `report` groups the unprocessed entries by surface for the cataloguer, `due` answers whether a weekly pass is owed, `pass` marks the entries processed | `add`/`pass` only, that record |

**Internal helpers** — the machinery calls these; you normally don't. They are listed so
the table above accounts for **every** script in `plugin/scripts/`, which
`tests/readme-scripts-table.test.sh` asserts.

| Script | Does | Writes? |
|---|---|---|
| `ai-bridge.sh` | backs the plugin's `/welcome`: reprints the SessionStart banner, `check` reports state that could be wrong, `fix` repairs only the idempotent tier | only under `fix` |
| `decision-stamp.sh` | the one resolver of *which GitHub login made a decision a document records* — `--self` for a decision taken in this session, `--author <path>`/`--promotion <path>` for one that arrived as a commit (the git author's email reverse-mapped through `people`, so a hand-promotion or a reply pushed from the other clone attributes to the other human). Unattributable prints `<unknown>` and exits 1; the stamp is written anyway. A login, never an address | no |
| `bundle-paths.sh` | the one place a bundle's layout is spelled — sourced it exports `AB_SCHEMA`, `AB_AWAITING`, `AB_LEDGER` and the rest as paths relative to a bundle root; run it, it prints them | no |
| `plugin-name.sh` | the one place the plugin names itself — sourced (via `bundle-paths.sh`) it sets `PLUGIN_NAME` and `PLUGIN_MARKETPLACE` from the install path `<cache>/<marketplace>/<plugin>/<version>`, or from the two manifests in a checkout; run it, it prints them | no |
| `cli-theme.sh` | the one place a plugin surface's colour escapes are spelled — sourced by the banner, status line, board and `ai-bridge.sh`; `ab_theme` picks the tier | no |
| `resolve-config.sh` | the one implementation of the two-file config precedence — `instance.config.local.json` first, `instance.config.json` second, dicts merged entry by entry | no |
| `resolve-max-agents.sh` | prints the concurrency cap **this machine** should honour, from the same two files | no |
| `spawn-preflight.sh` | step 3's read before a wave: what permission mode is **this session** in? Reads the mode `hooks/permission-mode.sh` recorded for this call, matched by its `--token` — no probe, no spawn. Exit 1 `auto`, 0 `not-auto`, 2 `could-not-read`, never folded into either. It reports the mode and predicts no launch outcome: the classifier judges the brief, not the command | no |
| `agent-sessions.sh` | the one reader of a dispatched role agent's **background** session — `state <id>` prints `working`/`blocked`/`done`/`gone`, `in-flight <bundle>` counts the recorded `session:` ids that still hold a `maxAgentsInFlight` slot, `view <bundle>` lists this bundle's sessions by task (joined on `worktree:`), state and whether a live process is behind each. Exit 2 is unknown, never a free slot or zero agents | no |
| `resolve-account.sh` | the one reader of *which Claude account is this bundle on* — prints `declared`/`active`/launcher path, exit 0 match, 3 mismatch, 4 no account on this session, 1 inert (no `loopd-accounts` companion, or nothing declared). Reads no credential | no |
| `resolve-autonomy.sh` | the one reader of *does delegated autonomy exist here* — prints the `AUTONOMY.md` in force (bundle root first, else an installed companion plugin from core's own marketplace), exit 1 when there is none, which is `gated` | no |
| `merge-permit.sh` | the policy half of the deny baseline's `subagent_merge` rule — 0 only where the owning project's mode delegates the merge, the caller is the `project-manager` and all four clearances are recorded at the head being merged; 1 refuses, printing why | no |
| `clearance-receipt.sh` | `record`/`verify`/`path` for those clearance records — one file per repo, PR and head under `.tick-receipts/`, written by the four clearance scripts and read offline by the hook | `record` only, `.tick-receipts/` (gitignored) |

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `/loopd:dispatch` reports "Unknown command" | the **plugin** is not installed on this machine (or Claude Code has not restarted since) — never the stamp, which delivers no commands at all now | `/plugin marketplace add cbmono/loopd`, `/plugin install loopd@loopd`, then `/exit` and relaunch |
| A command or agent is missing after a pull | it is a **new** `plugin/` file, so no symlink exists yet | `/loopd:init <bundle>` |
| A seed change from a pull never arrived | seed is copied only when absent, by design | `/loopd:init` and port what it reports |
| Commands and hooks vanished later, having worked | the installer was run from a git **worktree** | re-run `/loopd:init` from the main working tree |
| Installer exits 2, "refusing to install from a git worktree" | working as designed | `git -C <src> worktree list` — the first entry is the main tree |
| The startup nudge is empty | `AWAITING.md` was deleted, or the PM reshaped its layout | `touch AWAITING.md`; `session-banner.sh` greps the heading and bullets **literally** |
| An instance is missing from the board | it has no `SNAPSHOT.json`, or `boardInstances` doesn't name it | `touch SNAPSHOT.json` in it |
| `print-board.sh` printed nothing at all | it was not run from an instance root — that is silence by design, not an error | `cd` into the instance |
| The terminal board is missing a status column | every row was zero there, so it was dropped to fit the width; the footer names which | widen the terminal, or `--width 0` |
| The live page never updates | the watcher was stopped, or the change was outside `projects/` | restart `scripts/watch-board.sh`; it prints a line per render |
| A `yolo` project never merges anything | preflight failed: one `gh` identity, no external reviewer, or no required checks | the loop says which; fix that, or merge by hand |
| `required-checks.sh` exits 2 | the platform probe returned something it cannot classify | that is a refusal by design — read the message, don't loosen the script |
| A PR is all-green but not merge-eligible | the reviewer published "Review limit reached" behind a green check — `review-clearance.sh` exit 1 | wait for the reopen time it quotes, then ask for a **first** review; nothing re-reviews a skipped PR by itself |
| `required-checks.sh` exits 2, "review-clearance.sh not found" | the instance predates the review gate, so the new machinery isn't linked yet | `/loopd:init <bundle>` — until then it refuses rather than clear a reviewer check it cannot interpret |
| `required-checks.sh` exits 1, "no independent review clears" | every required check is green but no review artifact clears the head — the gate no longer decides from a check's *name* whether a reviewer is involved | ask for a review at the current head; if the repo genuinely has no reviewer, that is the thing to fix, not the gate |
| `required-checks.sh` exits 2, "present but does not run" | the linked sibling is broken, or predates its `--self-test` contract; a mode bit is not proof a file executes | `/loopd:init <bundle>` to relink — a sibling that fails every call looks exactly like "no reviewer is required", so this refuses |
| `review-rounds.sh` exits 1 | the PR has already had its two verification rounds — this is the cap doing its job, not a fault | stop reviewing: put both positions (reviewer / implementer / what the criterion asks) in front of the human and let them decide |
| An agent reported "done" but no PR ever appeared | it parked before opening one — `check-dispatch.sh` exit 1, the parked signature | one message to that agent: open the PR on what it already committed. Never re-dispatch the task |
| `review-clearance.sh` exits 4 on a PR that *was* reviewed | the reviewer read an earlier push and does not re-review (`auto_incremental_review: false`) — the review is **stale**, not absent | ask for a review at the current head; this is the common case here, not a bug |
| `review-clearance.sh` exits 6 on a PR that *was* reviewed | the review is real and at the head, but a reviewer-authored thread is still unresolved — `SCHEMA.md` clause 9. The refusal names each open thread | answer or fix each thread, resolve it, push. **Do not request another review** — you already have one, and a 6 is not a 4 |
| `review-clearance.sh` exits 7 on a PR whose review and checks are green | the host reports the PR CONFLICTING / DIRTY — the default branch moved under it, with no commit on the PR. This is the first thing the script asks, because no review makes a conflicting PR mergeable | rebase onto the default branch, push with an explicit `--force-with-lease`, let CI re-run. **Do not request a review**, and do not present it as a merge row |
| `review-clearance.sh` exits 2, "is not a usable answer" on `mergeable`/`mergeStateStatus` | the host computes mergeability lazily and says UNKNOWN for seconds after the base moves; a token without push access never gets `mergeStateStatus` at all | ask again next tick. If it never clears, check that the `gh` token has push access on the repo — the merge gate needs one anyway |
| `review-clearance.sh` exits 4, "carries no evidence that a review was COMPLETED" | the only artifact is the reviewer's *"currently processing"* placeholder or similar — it names the head but nothing says anybody read it | wait for the real review, or ask for one; not-a-refusal is not a review, and clearing on it was a live false pass |
| CodeRabbit: "Unable to determine base branch" | a remote-less instance has no `origin/HEAD` to infer one from | `git config coderabbit.baseBranch <branch>` |
| Validator errors right after an upgrade | the machinery updated, the data didn't | `/loopd:init` runs the stamp and the check-and-fix pass in the right order |
| Two loops dispatched the same task | `defaultOwner` is not set on a shared bundle | [docs/sharing.md](docs/sharing.md) |
| Machinery symlinks all dangle on a second machine | intentional — machinery is machine-local | re-run `/loopd:init` there |

---

## Why template + instance

Only `CLAUDE.md` cascades through parent directories in Claude Code — subagents, commands,
skills and `settings.json` load only from `~/.claude` or a **project root** `.claude/`. So
a group-level overlay can't exist. Instead each group gets a project-root control panel
holding its own documents and machinery, launched by opening Claude inside it. The role
agents come from the plugin, per machine; the generic machinery stays DRY via symlinks;
each instance keeps its own git history, so work and personal stay separate.

## Versioning and drift

The version lives at this root — [`VERSION`](VERSION), one line, no extension — and is
MIRRORED byte-for-byte into [`plugin/VERSION`](plugin/VERSION), because an installed plugin
has no checkout around it to read the root copy from. `cat VERSION` reads it;
`tests/template-version.test.sh` fails if the two disagree, so they only ever move together. Nothing parses
prose for it and there is no `package.json`, no tag and no changelog. **There is no release process here and none is wanted.**

**A change to `core` is bumped for AFTER it merges, by you, on `main`.** `core` is a closed
list — `plugin/` (which carries `seed/`, `RETIRED` and the shipped `VERSION`) and `config/` — and it is
exactly what the two path-scoped rule files ([`.claude/rules/machinery.md`](.claude/rules/machinery.md),
[`.claude/rules/installer.md`](.claude/rules/installer.md)) already govern, so an agent
editing one of those paths meets the rule as it opens the file. A PR touching only `docs/`,
`tests/`, `.claude/`, `.github/` or the root `scripts/` needs no bump at all. **No PR ever
edits the five places the number lives in** — merge it, then run
[`plugin/scripts/release-bump.sh`](plugin/scripts/release-bump.sh) `<major|minor|patch>` on `main`
and push the one commit it makes. That is what lets two core PRs be open at once: while
each carried its own bump they conflicted on the same five files and had to land one at a
time, at a full suite run each.

Rough scale, enough to act on without a policy document: **patch** for a fix inside
behaviour that already shipped, **minor** for a new capability or a new file under
`plugin/`, **major** for anything an instance has to be repaired by hand to survive.

**Why the number matters more than a label.** A bundle consumes nothing from this checkout
any more — the machinery ships in the plugin, replaced whole on every update — but
`plugin/seed/` content is copied into a bundle once, ever, so a seed edit reaches a stamped
bundle only through `/loopd:init`. That gap has cost real time: two hooks
merged and sat inert in every instance for a week, back when a stamp was the only route.

So the session banner prints one line — and only one, and only sometimes. The two numbers
below are an example, not this repo's current pair; the only place the current one is
written down is [`VERSION`](VERSION):

```text
⬆️  TEMPLATE UPDATE (loopd) — this instance links 0.9.1, origin/main has 0.11.0
```

`scripts/check-template-version.sh` decides it, and **silence is its normal answer**. Equal
or ahead prints nothing; so do offline, unauthenticated, no checkout, no remote-tracking
ref, a missing `VERSION` on either side, and a version it cannot parse — a false "you are
behind" would train you to ignore the true one. It makes **no network call** at session
start: it compares against the `origin/HEAD` ref already on disk, and only fetches when you
run it by hand with `--fetch`.

```bash
scripts/check-template-version.sh          # from an instance root; prints only if behind
scripts/check-template-version.sh --fetch  # refresh from the remote first
```

What it cannot see: a template checkout parked on an old commit whose `VERSION` happens to
match the remote's. The number moves when the bump convention says it moves, so this
catches drift **across a bump** and nothing finer.

## Changing this repo

Read [docs/conventions.md](docs/conventions.md) first. It records the design invariants and
what went wrong to produce each one — the reasoning is the asset, so relocate it rather
than shortening it.

- Machinery goes in `plugin/`. Keep it **generic**: no org, repo, path, team or channel literals — those belong in an instance's `instance.config.json` / `CLAUDE.md`.
- Starting content goes in `plugin/seed/`. Retiring a seed file needs an entry in [`RETIRED`](plugin/RETIRED) in the same commit.
- Tests live in `tests/`, never under `plugin/` — everything there ships into every instance.
- **Adding a pin to the plugin's skill contract? Two harnesses, and which one is not a judgement call:**

  | The property you want to hold | Where it goes |
  |---|---|
  | Something is **written** in a skill file — frontmatter, a named non-action, a phrase the contract turns on | [`tests/plugin-skills.test.sh`](tests/plugin-skills.test.sh) |
  | Something is **true of what the model does** with the plugin loaded — a skill it must not reach for, a tool order, a refusal | a case under [`plugin/evals/`](plugin/evals/README.md) |
  | The eval suite's own shape, and running it | [`tests/plugin-eval.test.sh`](tests/plugin-eval.test.sh) |

  Prefer the first: it is free, offline and runs on every machine. The eval costs real model
  runs and needs `claude plugin eval`, ungated on 2.1.270 and **early access** on builds up to
  2.1.263 — where it is unavailable the harness prints
  `skipped: plugin eval unavailable — <why>` rather than passing quietly.
  [→](plugin/evals/README.md)
- Run `tests/run.sh --changed` while you work and `tests/run.sh --all` once before you push. The required check **`harness suite`** calls the same script (`tests/run.sh --ci`): the full suite by default, and for a PR whose every changed path is under `plugin/` or `.claude-plugin/` a selected set of plugin harnesses instead; `main`'s branch protection requires it and is strict about it — so be up to date with `main`. [→](docs/conventions.md#repo-conventions-that-are-not-invariants)
- Adding to the harness itself? Measure what your diff adds under `plugin/**/*.sh`, and at or above ~150 lines ask in the PR body instead of assuming. [→](docs/conventions.md#repo-conventions-that-are-not-invariants)
- This repo is **public**. Placeholders must be verified unclaimed: `example-user-007` / `example-user-008` and `example.com`.

Agent-facing rules are in [`CLAUDE.md`](CLAUDE.md) and [`.claude/rules/`](.claude/rules).

## Relationship to `ai-setup`

loopd used to live as an `ai-bridge/` subtree inside
[`ai-setup`](https://github.com/cbmono/ai-setup), the Claude Code defaults repo. **This
repo is now the canonical copy** — every instance's machinery ships from *this* repo as
the `loopd` plugin, and `/loopd:init` and `/loopd:welcome fix` here are the
ones to run.

`ai-setup` **no longer carries the subtree** — [`ai-setup#69`](https://github.com/cbmono/ai-setup/pull/69)
removed it, because a stale second copy that documentation still described as live was
inviting edits that would reach nobody. The pre-split version is therefore in git history,
not in any checkout: `git -C ai-setup show f8b09a4:ai-bridge/` is the last state it had
(`ai-setup` commit `f8b09a4`, "fix: refuse to install from a git worktree (#68)").

Nothing here needs it. That measurement is why it went: `diff -rq` found **nothing** that
existed only in the subtree, while this repo was ahead by 4 scripts, 1 hook, 9 tests and
22 changed files.

The two repos are independent by design: `ai-setup`'s user-wide installer is scoped to
`.claude` and never touched this template.

**`~/.claude` belongs to that repo**, not this one — see
[The config layer](#the-config-layer) below and
[docs/claude-config-ownership.md](docs/claude-config-ownership.md) for why. This repo
installs only the three agents its own role agents probe for. The
`@~/.claude/claude-defaults.md` import that every instance used to inherit is gone: that
section is inlined in `plugin/seed/CLAUDE.md`, so nothing can dangle.

---

## The config layer

**`${CLAUDE_CONFIG_DIR:-~/.claude}` is owned by
[`cbmono/ai-setup`](https://github.com/cbmono/ai-setup)** — the commands, hooks, output
style, skills and `settings.json` all install from there. Run *that* repo's `/loopd:init`
for those.

loopd installs into that directory too, but only the paths **it probes for**: three
agents (`code-architect`, `deep-bug-scan`, `plan-architect`), so a fresh laptop works after
one clone and one install without needing a second repo.

It used to install 21 more, as a fork of ai-setup's tree — two installers claiming the same
paths, 14 of them diverged, ownership decided by whichever ran last. Two of the fixes that
existed only in the fork closed *secret-exposure* paths the public repo was still shipping.
[docs/claude-config-ownership.md](docs/claude-config-ownership.md) is the full record, and
`tests/config-ownership.test.sh` fails if the fork starts growing back.

```bash
# THE ONE THING THAT STILL WANTS A CLONE of this repo: it writes absolute symlinks INTO
# ~/.claude that point at the source tree, so it has to know where that tree is.
git clone git@github.com:cbmono/loopd.git ~/workspace/loopd   # if you have none
bash ~/workspace/loopd/plugin/scripts/init-bundle.sh --config
```

It links **one file at a time** into `${CLAUDE_CONFIG_DIR:-~/.claude}`. A real file in the
way is backed up as `<name>.bak.<epoch>`. It **never touches `settings.json`** — that is
ai-setup's file, it holds your permissions, and an installer that replaced it could widen
what agents are allowed to do. Restart Claude Code afterwards so it re-scans agents and
commands.

### What it ships

| Path | Holds | Why it is here and not in ai-setup |
|---|---|---|
| **`config/required/`** | `code-architect`, `deep-bug-scan`, `plan-architect` | the only three agents this repo's own role agents look for. Without them `qa-reviewer` loses the escalation behind its cheap second opinion and the PM loses its plan critic — **silently**. ai-setup ships them too, so on a machine that installed both, either copy satisfies the probe; this copy is what makes ai-setup optional |

That is the whole list, and it is enforced rather than documented:
`tests/config-ownership.test.sh` derives the expected set from the `test -f` probes in
`plugin/` and fails on anything else under `config/`. Delete `config/required/` and
`--config` links nothing and exits 0; delete `config/` itself and an **instance** stamp is
completely unaffected (`--config` then exits 2 saying there is nothing to link).

### Five rules it follows

1. **Never a whole-directory symlink.** `agents/`, `commands/` and `skills/` are *drop-in* directories — any skill or plugin installer can write a new subdirectory into them at any moment. Linking one as a unit aims it at this checkout, so every drop-in lands inside a public git repo. That is how four uninvited skills once got committed to the parent repo, three of them dead links. Per-file links keep `~/.claude/<dir>` a real directory that owns its own contents.
2. **It never writes *through* a symlinked directory.** ai-setup links `~/.claude/agents` as a whole directory, so on a machine that ran its installer every entry here has a symlinked parent. When the file already resolves through it, the requirement — *this agent exists on this machine* — is met, so `--config` reports `provided by …` and writes nothing. When it does **not** resolve, nobody ships it and writing would land inside the other checkout: `--config` skips it, names it, prints the `mv` that fixes it, and exits non-zero. Either way the two installers compose in any order.
3. **`settings.json` is not ours at all.** This layer does not ship one, does not link one, and does not report on one. A link left over from when it did is retired by the sweep in rule 4.
4. **A retired file's link is swept — and it says where the file went.** Delete something from `config/` and the next `--config` removes the dangling link. Delete or hide *everything* and it does the opposite: an empty source list is refused rather than acted on, loudly and non-zero, because "nothing is shipped" and "I could not read the checkout" produce the same empty list and only the first licenses a delete. Removing the tier **directory** is the way to mean the first. A dangling command still registers with Claude Code; a dangling hook exits 127 every launch. The sweep is also what performs the **handover**: this layer used to ship ~21 more paths, so an existing machine's first run on the new layer retires them all at once, and it prints that they moved to [`cbmono/ai-setup`](https://github.com/cbmono/ai-setup) rather than leaving a user told only what vanished. Steady-state runs stay quiet.
5. **Nothing here is required.** A bundle never needs the config layer, and the config layer never needs a bundle. A bundle stamp behaves exactly as it always did with `config/` deleted.
6. **It is the one half that still refuses a git worktree.** Every link it writes points AT this checkout, so a worktree that is later removed dangles all of them — silently, later. A bundle stamp writes no such link and is allowed from anywhere.

### Uninstall

```bash
# from a clone of this repo — the config layer is the one half that still needs one,
# because it links absolute paths INTO ~/.claude and must know where they point
bash <clone>/plugin/scripts/init-bundle.sh --config --uninstall
```

Removes only the symlinks it created — everywhere it created them, which includes a
`<root>.bak.<epoch>` directory another installer moved aside (ai-setup does that when it
takes `~/.claude/agents` over as a whole directory, and three links used to survive there,
still resolving into the checkout you had just detached from). Real files, `*.bak.*` backup
*files*, and your runtime state (`plugins/`, `projects/`, history) are left alone.

### Coming from the separate `ai-setup` repo

An instance stamped before this existed carries one line in its `CLAUDE.md`:
`@~/.claude/claude-defaults.md`. That file is no longer shipped, and a missing `@import`
fails **silently**. `/loopd:init <bundle>` now reports it. Replace that line with the
`## Session defaults` section from [`plugin/seed/CLAUDE.md`](plugin/seed/CLAUDE.md).
