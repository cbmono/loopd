# Reference

Everything the [README](../README.md) leaves out: every command and flag, the team, the
bundle's layout, the config keys, every script, and what to do when something looks wrong.
New to loopd? Start with [getting-started.md](getting-started.md) instead.

**`scripts/<name>.sh` on this page means the plugin's scripts directory,**
`${CLAUDE_PLUGIN_ROOT}/scripts/` — a bundle carries no scripts and no hooks of its own; both
ship in the plugin. Run a script from a bundle root unless its row says otherwise.

| Section | Covers |
|---|---|
| [Commands](#commands) | every `/loopd:` command, and the flags `/loopd:new-project` takes |
| [Who runs what, end to end](#who-runs-what-end-to-end) | one build project from scaffold to merge, step by step |
| [The team](#the-team) | the six role agents, the three advisers, and the two checkers |
| [Where the work lives](#where-the-work-lives) | the bundle's layout |
| [Two kinds of project](#two-kinds-of-project) | `build` and `research` |
| [Answering the PM's questions](#answering-the-pms-questions) | the ` --- ` answer form |
| [What needs you](#what-needs-you) | `AWAITING.md`, its markers, and its off switch |
| [Three ways to see the board](#three-ways-to-see-the-board) | the terminal, a page, the local server, the published artifact |
| [Larger teams](#larger-teams) | one bundle each, one shared knowledge repo |
| [Safety rails](#safety-rails) | the gates and the scripts behind them |
| [Configuration reference](#configuration-reference) | `instance.config.json` and `instance.config.local.json` |
| [Scripts](#scripts) | every script the plugin ships |
| [Troubleshooting](#troubleshooting) | symptom, cause, fix |

---

## Commands

Run these from a session started inside a bundle. Every one is namespaced `/loopd:`; so is
every agent (`loopd:software-engineer`), because a bare name does not resolve.

| Command | What it does |
|---|---|
| `/loopd:new-project <description> [kind=research] [autonomy=<mode>] [inputs=later]` | scaffolds a project: phases, draft tasks, success criteria. Asks at most one question — kind, autonomy (only where `AUTONOMY.md` defines a mode) and whether you'll add input files first — for whichever you didn't pass; everything else is a flag or a default. With no description, opens a five-field form (in the pane) instead |
| `/loopd:dispatch [gap\|once\|dry-run\|stop]` | the serial background loop: dispatch, track, report. Bare, it ticks every ten minutes on its own; a gap such as `30m` sets the cadence, `once` is a single tick, `dry-run` is one tick that only reports, `stop` ends it |
| `/loopd:answer` | answer the PM's open questions from inside the session — all of them, one project's, or one, as `<task> [Q<n>] <n \| more \| later \| text>`. Given a `blocked` task, shows why it stopped, takes your one decision and sends it back to `ready` with that decision in its `# Notes` |
| `/loopd:whats-up` | "what do you need from me?" — reprints `AWAITING.md`'s Needs-you rows, numbered, with its last refresh, and ends with the working agents and their tasks. Read-only |
| `/loopd:board [serve\|publish\|--help]` | `serve` — **the default, so a bare call serves** — the board on a local URL, one process per bundle (every session starts it while `boardServe` is on); `publish` — the same page as a private artifact, at the same URL every run; `--help` — the forms |
| `/loopd:close-project [<slug>] [--dry-run] [--force]` | close a project and fold its conclusions into `knowledge/`, then remove its folder — or freeze and keep it, on `retain: true`. No slug opens a multi-select picker of the projects and asks about `--force`. [→](schema.md#closing-a-project) |
| `/loopd:welcome [check]` | reprint the SessionStart banner; `check` reports state that could be wrong. It repairs nothing: the repair pass runs inside `/loopd:init`. [→](conventions.md#21-loopdwelcome-reports-facts-that-can-be-false-and-fix-is-tiered-in-code) |
| `/loopd:init <dir>` | create a bundle or refresh one, then run the check-and-fix pass. Flags: `--org O [--name R]`, `--with-objectives`, `--normalise-config`, `--owner L`, `--email A`, `--repos-root D`, `--spawn-grant` |
| `/loopd:update` | update the marketplace and every user-scope plugin installed from it, re-stamp the bundle it runs in with the new version's init, then tell you to `/reload-plugins` |
| `/loopd:fanout <task; task; task>` | fan a batch of independent ad-hoc requests out to parallel background agents; the main session coordinates and reports results as they land. Empty, it fans out the independent asks already in the turn |
| `/loopd:handoff <path> <login> [context]` | transfer a task or project to another human, with the context that makes the transfer real |
| `/loopd:prune-wt` | remove the worktrees `prune-worktrees.sh` reports `REMOVABLE`, after one yes — each re-checked at removal time, skipped on any doubt; refuses while a tick holds the lock. [→](operations.md#4-worktrees-two-scripts-delete-the-pruner-still-reports) |

`/pane` is a mod, not a skill: the board, or an inbox of questions and stuck tasks, beside the
session ([`plugin/hooks/MODS.md`](../plugin/hooks/MODS.md)). The plugin ships three mods —
hooks modules Claude Code runs inside every session, each a switch in `/config`, on by default:

| Mod | What it does | Switch |
|---|---|---|
| usage | records what a session spent, so `session-usage.sh` can read it back | `usage` |
| pane | adds `/pane`: the board in a pane beside the transcript, or a simple view of projects, questions and blocks, with a form to start a project | `pane`, `paneMode` |
| signal | lets a role agent's session tell the PM's session its turn is over, the moment it is | `signal` |

**Flags `/loopd:new-project` accepts:**

| Flag | Means |
|---|---|
| `kind=build\|research` | the project kind; asked when absent (`build` under `--no-ask`) |
| `inputs=later\|now` | `later`: you'll add files to `projects/<slug>/sources/` first — refinement waits, AWAITING.md shows one `📥 inputs` row, and the first file there releases it; asked when absent (`now` under `--no-ask`) |
| `repo=<name\|owner/name>` | build only — the `target_repo`; absent, `<org>/<defaultRepo>` |
| `deliverables="a; b"` | research only — what the project produces |
| `objective=<slug>` | link to `objectives/<slug>.md`; never asked or inferred |
| `autonomy=<mode>` | asked only when `AUTONOMY.md` defines a mode, else `gated` ([autonomy.md](autonomy.md)); a mode's shorthand such as `/yolo` works the same |
| `clis="a; b"` · `/cli a, b` | external CLIs or integrations the project's agents may use; never asked |
| `browser=off\|claude-for-chrome` · `/claudeforchrome` | let agents drive the browser; default `off`, never asked |
| `owner=<login>` | a shared bundle only — whose project this is |
| `timebox=<N>d\|<N>w` | an experiment to stop when the box runs out |
| `title="…"` · `need="…"` · `success_criteria="a; b"` | recorded verbatim. Absent, the criteria are proposed and written (edit `project.md` to change) and the value gate is filled only from what the description says |
| `--no-ask` | ask nothing; the one question takes its defaults |
| `--no-commit` | scaffold only; don't commit |

---

## Who runs what, end to end

```text
/loopd:new-project  →  you promote draft → ready  →  /loopd:dispatch  →  you merge the PR
```

`/loopd:dispatch` is serial and completion-gated — one tick at a time. Run **one per bundle
clone**. The launcher takes a per-clone lock (`.tick-lock`) immediately before each
dispatch, and the tick runs the same check on entry — a resumed tick never passes through
the launcher, so one that finds no lock is refused rather than allowed to run. That
guarantee survives a compaction instead of resting on the session remembering it
dispatched — [→](operations.md#one-tick-at-a-time-the-dispatch-lock). The bare form owns one
session-scoped cron job — the same primitive Claude Code's `/loop 10m /loopd:dispatch`
creates, which still works and is the same loop. A pass that fires while a tick is still
running prints one line and skips. [Running the loop on a
cadence](operations.md#running-the-loop-on-a-cadence) has the reasoning.

One `kind: build` project, from `/loopd:new-project` to merge. Every step links to the
document that **owns** its rule; nothing here restates one. Tiers are the **seed defaults**
— each bundle sets its own in `roleTiers`/`models`
([model routing](operations.md#model-routing)).

| # | Step | Who runs it |
|---|---|---|
| 1 | **Scaffold** — slug, objective, phases, seed `draft` tasks | you and the main session, interactively [→](../plugin/skills/new-project/SKILL.md) |
| 2 | **Commit** the scaffold and its registration as one change | main session, via `commit-as.sh` |
| 3 | **Scaffold review**, three stages: `validate-bundle.sh`, then an external reviewer, then the `qa-reviewer` fallback. Stage 1 gates the rest; stages 2 and 3 are advisory, and stage 2 is *dispatched* rather than waited on | main session; `qa-reviewer` (`apex`) on the fallback [→ step 8](../plugin/skills/new-project/SKILL.md) |
| 4 | **Refine** each `draft` — fill `acceptance_criteria`, raise `open_questions` | `project-manager` (`deep`) [→](../plugin/agents/project-manager.md) |
| 5 | **Approach critique** — **mandatory on its trigger** (a complex or heavily-inferred `kind: build` draft), advisory in what it may decide; its concerns land in `advisor_notes` and gate nothing | `plan-architect` (`apex`), dispatched by the PM [→](../plugin/agents/project-manager.md) |

> ### HUMAN GATE 1 — you promote the task `draft → ready`
>
> **Nothing is dispatched until you do.** The PM refines and critiques a draft but never
> sets `ready` ([two human authorities](../plugin/seed/SCHEMA.md)).

| # | Step | Who runs it |
|---|---|---|
| 6 | **Dispatch** the `ready` task — its own worktree and branch, both recorded on the task before the agent spawns | `project-manager` → the assignee [→](../plugin/agents/project-manager.md) |
| 7 | **Build it**, then **self-review your own diff** — a pre-filter, never the gate | `software-engineer` / `devops-engineer` (`deep`) [→](../plugin/seed/CONVENTIONS.md) |
| 8 | **Open the PR** carrying the task's `acceptance_criteria` as a ✓/✗ table — the artifact `pr-body-clearance.sh` reads. The agent never merges | the same agent |
| 9 | **Independent review** at the PR's current head: the external reviewer where one is configured, else the `qa-reviewer` fallback. The PM reads that verdict with `review-clearance.sh`, and `review-rounds.sh` stops each reviewer at its cap (`coderabbitRounds` / `qaRounds`, 1 each when absent) | external reviewer, else `qa-reviewer` (`apex`) [→](../plugin/seed/SCHEMA.md) |

> ### HUMAN GATE 2 — you merge the PR
>
> **One `✗` in that criteria table blocks it, however green CI is**
> ([SCHEMA.md](../plugin/seed/SCHEMA.md)).

The next tick reflects the merge — `status: done`, and the task's worktree is reclaimed.

Both gates can be delegated — see [autonomy.md](autonomy.md). That capability is **off
unless installed**, literally: it lives entirely in the separate
[`loopd-yolo`](../plugin-yolo/README.md) companion plugin, and uninstalling that plugin
makes every project `gated` again with no other edits.

---

## The team

| Role | Does |
|---|---|
| `project-manager` | runs the loop: refines drafts, dispatches, tracks, reports |
| `software-engineer` | writes code in a target repo and opens the PR |
| `devops-engineer` | infrastructure, CI, deploys |
| `qa-reviewer` | the **independent** verification gate — fresh context, real signals |
| `cataloguer` | folds conclusions into `knowledge/` |
| `failure-analyst` | diagnoses a failing check or a broken build |

All six ship in the **plugin** and are dispatched **namespaced** —
`loopd:software-engineer`, `loopd:qa-reviewer`, and so on. A bare agent name does not
resolve (measured 2026-09-02). A task's `assignee:` field stays bare; the PM adds the
namespace when it spawns.

**Three more agents ship beside them, and no task is ever assigned to one.**

| Agent | Called by | Does |
|---|---|---|
| `plan-architect` | the PM, at refine time | the approach critique: missing edge cases, wrong layering, scope creep |
| `code-architect` | the `qa-reviewer`, on a trigger | a staff-engineer read of a diff: architecture, patterns, trade-offs |
| `deep-bug-scan` | the `qa-reviewer`, on a trigger | a deep bug hunt: logic errors, races, SQL, assertion gaps |

They too are dispatched namespaced (`loopd:plan-architect`), and they are unrestricted by
design: no `tools:` allowlist, so a dispatched one can reach skills without widening any
role agent's list.

Role dispatches are routed to a cost-appropriate model per tier
([operations.md § model routing](operations.md#model-routing)).

**Two `roleTiers` rows are not team members.** `plan-architect` is the approach critique
above; its row keeps its bare key, and only the dispatch string carries the namespace.
`explorer` is not a loopd agent at all: it is the price tag for Claude Code's built-in
**Explore** subagent, which a role agent sends a broad read to — "which services call this
endpoint?", "where is this config read?" — instead of reading ten files into its own
context. Explore is read-only, returns the conclusion rather than the file dumps, and is
scoped to the target repos; a role agent then reads the one file it is about to edit
itself. Role agents that hold the `Agent` tool (the `qa-reviewer`, the PM) dispatch it,
every dispatch brief names its model and effort, and the `/loopd:close-project` picker runs
its state read on it. It never takes a task and never writes. Seeded at `light` / `low`;
with no entry the brief says `light` and says it is the default. Delete the row and nothing
breaks, but the only dial for the cheapest reads in the system is gone.

### The two checkers

**Two agents check, at two different scales.** `qa-reviewer` checks one PR,
`failure-analyst` diagnoses a red build.

| | `qa-reviewer` | `failure-analyst` |
|---|---|---|
| Question it answers | Does this PR meet its acceptance criteria? | Why is this build, CI run or deployment red? |
| Looks at | one PR's diff and CI against its task's `acceptance_criteria` | logs, recent changes, config |
| Started by | the PM, for a QA task or a PR without a usable external review; `/loopd:new-project`, for a scaffold review | ad hoc, usually in the background |
| Writes | tests, and its verdict on the PR; for a scaffold, an advisory verdict in the project's `log.md` | nothing; returns a report |
| Output | on a PR, PASS/FAIL per criterion, read by the merge gate; on a scaffold, an advisory verdict that gates nothing | root cause, ranked next steps, an optional Finding draft |

`failure-analyst` is read-only by instruction. It holds `Bash`, so the allowlist does not
enforce it (see [`plugin/agents/failure-analyst.md`](../plugin/agents/failure-analyst.md)).

---

## Where the work lives

```text
_loopd-<group>/
├── objectives/                  OPTIONAL — goals that outlive one project (/loopd:init <dir> --with-objectives)
├── projects/<slug>/
│   ├── project.md               kind, status, autonomy, owner, target_repo
│   ├── phases/                  ordered stages
│   ├── tasks/                   the unit an agent is dispatched on
│   ├── sources/                 background material you drop in
│   └── deliverables/            research output (no repo, no PR)
├── knowledge/                   services, findings, teams, runbooks, references
├── repos/                       one symlink per repo of the group (gitignored)
├── .loopd/
│   ├── SCHEMA.md                the document types and the task lifecycle
│   ├── CONVENTIONS.md           the rules role agents follow in target repos
│   ├── log.md                   the ledger every tick appends to
│   ├── AWAITING.md              what needs you (derived, gitignored)
│   └── SNAPSHOT.json            board input (derived, gitignored)
├── CLAUDE.md                    the panel's instructions to every session
├── instance.config.json         tracked config, shared by every clone
└── instance.config.local.json   this machine's config (gitignored)
```

`repos/` is a read-only view: build work happens in a worktree under `worktreeRoot`
(absent, `<reposRoot>/_wt`). Document types and their fields: [schema.md](schema.md).

---

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
[conventions.md invariant 5](conventions.md#5-build-and-research-projects-are-deliberately-asymmetric).

---

## Answering the PM's questions

When a `draft` is blocked it lists numbered `open_questions` (`Q1:`, `Q2:`, …).
Each has a `### Q<n>` block under the task's `## Question details` with a recommendation,
the options and three depths of context; the answer still goes on the question line.

1. Open the task doc.
2. Append ` --- <answer>` to the question line:
   ```text
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

---

## What needs you

`.loopd/AWAITING.md` is the bundle's **one** status artifact: a queue of just the items a
human decision unblocks.

| Marker | Means |
|---|---|
| ✅ | approve |
| ❓ | answer |
| 🔀 | merge |
| ⛔ | unblock |
| 🏁 | close |
| 👉 | do — a hand-off only you can carry out, filed by the tick |
| ⏳ | continue — only where `continueAfterTasks`/`continueAfterDays` is set (absent ⇒ off) |

Each item carries a real link. Every `/loopd:dispatch` tick rewrites the file, and the
plugin's `SessionStart` hook prints its items in the banner at launch. `/loopd:whats-up`
reprints them, numbered, at any time.

In-flight and upcoming work is deliberately **excluded** — it needs no decision, and a
queue you scroll past is a queue you stop reading. **There is no `/status` command; don't
reintroduce one.**

**On by default; the config key is the switch.**

| Action | Effect |
|---|---|
| `"awaiting": false` in `instance.config.json` | the queue is off **for good** — no stamp creates the file |
| `rm .loopd/AWAITING.md` | off until the next `/loopd:init`, which recreates it |

Derived and gitignored; never hand-edit it. Reasoning:
[conventions.md invariant 3](conventions.md#3-awaitingmd-is-loopds-only-status-artifact-and-awaiting-in-config-is-its-switch).

---

## Three ways to see the board

One snapshot, several renderers. `scripts/write-snapshot.sh` derives each bundle's
`.loopd/SNAPSHOT.json`; every renderer reads it and none of them reads the bundle. Pick by
what you are doing, not by which is newest.

| You want | Run | Costs |
|---|---|---|
| a look right now, in the terminal you are in | `scripts/print-board.sh` | nothing |
| the board beside your Claude session | `/pane` | nothing — a mod |
| **a live page in the browser, on a fixed local URL** | `/loopd:board` (it is `serve`) — usually already running | **a process**, which the sessions start and stop for you |
| a page to open locally — the one each tick renders | `scripts/build-board.sh --standalone .` | a re-run, or a looping bundle |
| a page on your phone, with no clone there | `/loopd:board publish` | a private artifact you refresh by hand |
| a page that updates itself as you work, no server | `scripts/watch-board.sh` | **a process you keep running** |

```bash
scripts/print-board.sh                      # columns: instance, project, phases, tasks, awaiting
scripts/build-board.sh --standalone .       # .loopd/.board-live/board.html — THIS bundle only
scripts/build-board.sh --standalone         # the same, but every bundle in boardInstances (see below)
scripts/build-board.sh                      # the same page as a BODY — no <html> wrapper, for embedding
scripts/watch-board.sh                      # .loopd/.board-live/board.html, re-rendered on every change
scripts/board-serve.sh                      # http://localhost:<boardPort> — the same page, served and auto-reloading
```

**The page keeps itself current, locally.** Every `/loopd:dispatch` tick re-renders it to
`.loopd/.board-live/board.html` — gitignored, on this machine — and reports the path; the
`SessionStart` banner prints the same path when a session starts. `board: false` in
`instance.config.json` turns that off; absent or `true` leaves it on, which is the seeded
default ([operations.md § rendering it from each
tick](operations.md#rendering-it-from-each-tick)). It is only as fresh as the last tick —
the page's masthead says when that was, and `watch-board.sh` is the view that follows your
work in between.

**The local web app starts with the session**: with `boardServe` on (the default) every
Claude session on the bundle starts it, the banner's `Board` row is its
`http://localhost:<port>/loopd/board` (the line under it when a published artifact heads
the block), and it stops after the last session ends.
`boardServe: false` in the tracked `instance.config.json` turns that off and the banner
falls back to the `file://` row. `/loopd:board serve` — what a bare `/loopd:board` does —
starts it by hand, and `/loopd:board --help` lists the forms. One process per bundle, on a port
derived from the bundle path (`boardPort` in `instance.config.local.json` overrides it),
serving `.loopd/.board-live/` on `127.0.0.1` and nothing else. It re-renders within two
seconds of `SNAPSHOT.json` changing and the page reloads itself. No LLM is in that path.

**`/loopd:board publish` publishes the same page as a private artifact**, at a URL that does
not change between runs and that the session banner prints. It is the route to a phone
with no clone on it; `serve` stays the route on the machine itself. The
URL is recorded per machine, as `boardArtifactUrl` in `instance.config.local.json`, because
artifact publishing is account-scoped — no share level lets a second account update your
page. **A headless tick never publishes**: measured 2026-09-05 on Claude Code 2.1.261, a
`claude -p` session has no artifact tool at all, so the tick prints `run /loopd:board publish
to refresh` and stops there. Opening it, including from a phone: [operations.md §
opening the board](operations.md#opening-the-board-laptop-phone-published-live).

**The board is per installation, and it still shows everybody.** Your own projects come
from your `SNAPSHOT.json`; every other owner's is a collapsed, **named** section below
them, read from the tracked task documents at your current git `HEAD` (the one thing both
clones share) and cached against that SHA. That is why the local board loses nothing on a
shared bundle: the cross-owner half never came from a shared page, it came from git.

**The watcher's cost is the real one, so read it before you pick it.** It needs a resident
process you keep open: it stops when you close the terminal, sleep the machine, or lose the
session, and it gives you nothing to share and no phone access. The local server already
re-renders on every snapshot change, so reach for the watcher only when you want a page
with no server behind it.

Three properties are shared by every renderer, because they belong to the snapshot rather
than to any renderer:

1. **No `SNAPSHOT.json`, no appearance.** That bundle is absent — no placeholder, no
   warning — and no renderer ever creates the file.
2. **One broken bundle cannot blank the board.** An unreadable snapshot becomes a
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

**Read the field list before you carry a rendered page off the machine** — nothing
publishes it unless you run `publish`, but a rendered file is still a file
([operations.md § before it leaves the
machine](operations.md#before-it-leaves-the-machine-know-what-it-carries)).

---

## Larger teams

[sharing.md](sharing.md) shares **one** bundle: every person clones it and runs
their own loop, and each tick pulls `--rebase` and pushes the bundle. That suits two or
three people. Past that, the clones contend on the same repository every tick, and a pull
conflict stops the tick that hits it. The shape that scales:

| Piece | How |
|---|---|
| **One bundle per person** | each person runs `/loopd:init` on their own directory — a private repo of their own, or local git with no remote (the tick then skips pull and push). Projects, `AWAITING.md` and the loop stay theirs, and no `owner:` or `defaultOwner` is needed |
| **One shared knowledge repo** | every bundle sets the same `knowledge` key in `instance.config.json` — `{ "repo": "<org>/<kb-repo>", "path": "/" }`, plus an optional `ref` naming a branch. `/loopd:init` mounts it into `knowledge/` as a nested, gitignored clone, and `scripts/kb-sync.sh` is its only writer. An existing `knowledge/` moves there with `scripts/kb-migrate.sh`. [SCHEMA.md → "A mounted knowledge base"](../plugin/seed/SCHEMA.md) |
| **A combined board (optional)** | `boardInstances` in `instance.config.local.json` lists bundle directories **on this machine** — absent, the board is just this bundle. It reaches no bundle that lives only on a teammate's laptop |
| **A pair that truly works together** | can still share one bundle exactly as [sharing.md](sharing.md) describes: `owner:` per project, `defaultOwner` and the `people` map |

A worked example, for a team of twenty:

1. One person creates the knowledge repo, `<org>/<kb-repo>`, with at least one commit on its default branch.
2. Everyone else runs `/loopd:init ~/workspace/<group>/_loopd-<group>` for their **own** bundle and sets `"knowledge": { "repo": "<org>/<kb-repo>", "path": "/" }`.
3. Each runs `/loopd:init` again, which mounts it. On a fresh bundle it first prints the `rm -r …/knowledge` that clears the seed's placeholders; run that and stamp once more. From then on each person's `Finding`s and `Service` docs land in the shared repo, and their task documents never leave their own bundle.
4. Two people who split one project between them share one bundle instead, with `owner:` set per project.

---

## Safety rails

The short version. Each line links to the full reasoning; **none of them is decoration.**

| Rail | Rule |
|---|---|
| **Independent review** | every PR is cleared by a reviewer with fresh context, never the implementing agent's self-report. [→](autonomy.md#the-verification-gate) |
| **Merge gate** | `required-checks.sh` — **exit 0 is the only clearance.** Missing, pending, skipped and unreadable all refuse. [→](autonomy.md#required-checks--exit-0-is-the-only-clearance) |
| **Review gate** | `review-clearance.sh` — a **green check from a reviewer that declined to review is not verification.** It reads the reviewer's artifacts, takes evidence and pinning from the reviews **API** (`state` + `commit_id`), leaves text matching only the job of spotting a refusal, and refuses on unknown state. `required-checks.sh` asks it on **every** PR, so a check's name never settles whether anybody looked. [→](autonomy.md#the-verification-gate) |
| **Review rounds** | `review-rounds.sh` — **a round cap per reviewer, then the human decides**, as a number a dispatcher reads rather than a rule it must remember. Counted per reviewer against `coderabbitRounds` / `qaRounds` (**1** each when absent); exits non-zero at or past that cap, so another round is refused. A real CodeRabbit refusal dispatches a `qa-reviewer` round instead, and the last round's fix merges under `yolo` with no re-review when it changes at most `reviewFixMaxLines` (**300** when absent) lines. [→](autonomy.md#a-round-cap-per-reviewer-then-the-human-decides) |
| **Dispatch check** | `check-dispatch.sh` — an agent's "done" is not evidence that a PR exists. Did `status:` move, does `pr:` name a URL, does that PR resolve. **Report-only.** [→](autonomy.md#did-the-dispatch-produce-its-pr) |
| **Delegated autonomy** | one uninstallable plugin. Uninstall `loopd-yolo` and every project is `gated`; `resolve-autonomy.sh` is the one reader, and a bundle's own root file still wins. [→](conventions.md#4-a-capability-some-deployments-must-not-have-should-be-one-deletable-file) |
| **Dispatch lock** | `tick-lock.sh` — one PM tick at a time, taken by the launcher in the same operation that checks it, **and checked again by the tick itself**, since a resumed tick never passes through the launcher. A dispatched tick does not refuse its own lock: unclaimed means it is that dispatch. A tick that finds **no** lock was not dispatched at all — it is refused (exit 4), because **a tick is never resumed**. The claim on a lock records **whose** it is and from **which source**, and the trust is asymmetric — a runtime-derived id (`CLAUDE_CODE_SESSION_ID` names the *session*, not the tick) may refuse a claim but never clears one, so a merely-matching identity is exit 2 rather than a guess in either direction. Stale, or unattributable, means **ask the human**, never silently delete and never silently adopt. Per clone, not cross-machine. [→](operations.md#one-tick-at-a-time-the-dispatch-lock) |
| **Worktrees** | `prune-worktrees.sh` **reports, never deletes.** Do not add a delete there, not even behind a flag — it destroyed three running agents' worktrees once, by inferring from a scan. `reclaim-worktree.sh` deletes ONE path a task recorded, and only when that task is `done` with every PR merged. `/loopd:prune-wt` deletes the pruner's `REMOVABLE` set only when a human starts it and says yes, re-checking each path. [→](conventions.md#7-prune-worktreessh-is-report-only-and-that-is-load-bearing) |
| **Destructive commands** | the plugin's `deny-destructive.sh` hook refuses, before it runs, the shapes a command prefix cannot judge — `terraform destroy`, an irreversible `kubectl delete`, destructive SQL against a remote host, `rm -rf` of a repo root, a force-push to a protected branch, a write to a credential store, secret exfiltration, and a subagent's merge or push to the default branch unless a delegated mode permits it. Narrow on purpose; `tests/deny-baseline.test.sh` proves each rule both ways. [→](conventions.md#19-the-destructive-action-baseline-is-a-hook-and-it-is-narrow-on-purpose) |
| **Bundle repair** | `migrate-bundle.sh` is report-only by default and fixes only what has one right answer. **A false success is worse than the error it claims to fix.** [→](conventions.md#9-migrate-bundlesh-fixes-only-what-has-one-right-answer-and-is-report-only-by-default) |
| **Retiring content** | leftover machinery links from the symlink era are swept; **seed content is only ever reported**, never deleted. [→](operations.md#2-retiring-content-swept-vs-reported) |
| **Board data** | the board's field list is a data-governance boundary — no question text, no document bodies, no author identity, no out-of-bundle paths. Nothing publishes it unless you run `/loopd:board publish`, and a rendered file is still copyable. [→](operations.md#before-it-leaves-the-machine-know-what-it-carries) |
| **Untrusted text** | `AWAITING.md` items and the per-turn state injection are fenced as data before they enter session context. Keep the boundary. [→](conventions.md#12-three-loopd-behaviours-that-all-exist-because-a-silent-wrong-answer-is-worse-than-a-loud-one) |
| **No customer PII** | not in a task title, not in an answer, not in a `Finding`. Titles reach the board; answers persist for the life of the repo. |
| **Drift check** | a human's read on a slow cadence, advisory. It catches an autonomous loop gaming itself; it is not a merge-blocking guarantee. [→](autonomy.md#the-audit-counter-metric) |

---

## Configuration reference

Two files at the bundle root. `instance.config.json` is **tracked**: every value in it is a
statement every clone reads. `instance.config.local.json` is **gitignored** and per machine,
read first. The **one** authoritative list of which keys a machine may override is
[`SCHEMA.md` → "Per-machine config overrides"](../plugin/seed/SCHEMA.md); `/loopd:init`
runs `normalise-config.sh`, which reports a key in the wrong file.

| Key | Absent means | Which file |
|---|---|---|
| `org` | — (the seed's placeholder) | tracked — a shared fact |
| `defaultRepo` | `/loopd:new-project` asks for a repo | tracked |
| `group` | the bundle **directory** name minus `_ai-bridge-` / `_loopd-` | tracked — one bundle, one name |
| `reposRoot` | the readers report it unset and skip; nothing is guessed. Required for dispatch | **local only** — an absolute path on this machine |
| `worktreeRoot` | **`<reposRoot>/_wt`** | **local only** |
| `ownerGithubUser` | this clone has no configured human | **local only** |
| `authorEmail` | `people[ownerGithubUser]`, else the tracked value, else `git config user.email` | either; local wins |
| `people` (login → commit email) | no lookup; the `authorEmail` chain answers | tracked — every clone must agree |
| `defaultOwner` | unowned work is dispatched by **every** clone | tracked |
| `maxAgentsInFlight` | **4** | either; local wins |
| `maxPrLoc` | **500** (the seed ships 2000) | tracked |
| `maxPrFiles` | **100** | tracked |
| `models` / `roleTiers` | everything inherits the session model | either; `/loopd:init` seeds them into the local file |
| `roleEffort` | no effort is passed: an Agent-tool spawn runs at the agent's frontmatter `effort:`, a `claude --bg` spawn at the machine's `modelSettings[<model>].effortLevel` (else the model default); seeded on the next stamp — medium for orchestration roles, high for those that write code or adjudicate | either; seeded like `roleTiers` |
| `commitAttribution` | `claude` — target-repo commits keep the `Co-Authored-By: Claude` trailer; `none` drops it | either; local wins |
| `externalReviewer` | the CodeRabbit CLI | tracked — it names where code may be sent |
| `coderabbitRounds` / `qaRounds` | **1** review round each | tracked — a merge policy every clone must agree on |
| `reviewFixMaxLines` | **300** | tracked |
| `awaiting` | **on** — `.loopd/AWAITING.md` is created on any stamp that finds it missing | tracked |
| `board` | **on** — `SNAPSHOT.json` is seeded and each tick renders `.loopd/.board-live/board.html`, which `/loopd:board serve` serves | tracked — one bundle, one answer |
| `boardServe` | **on** — each session starts the local board server | tracked |
| `boardInstances` | the board is just this bundle | **local only** — paths on this machine |
| `boardPort` | derived from the bundle path, in the 4xxxx band | **local only** — a port belongs to a laptop |
| `boardArtifactUrl` | nothing was published from this machine | **local only**, written by `/loopd:board publish` |
| `knowledge` | `knowledge/` is a plain folder of this bundle | tracked |
| `codegraphSkip` | index every product repo | tracked |

Every other key — `maxStallRounds`, `maxAgentMinutes`, `roleMinutes`, `minFreeDiskGb`,
`continueAfterTasks`, `ticketPrefix` and the rest — is documented in place in the seeded
`instance.config.json`, each with a `$<key>` note beside it, and in `SCHEMA.md`.

Environment knobs: `PUSH_STATE_MAX` (default **12**), `PRUNE_ACTIVE_MINUTES`,
`CODEGRAPH_SKIP`, `CONTROL_PLANE_AUTHOR_EMAIL`, `NO_COLOR` (honoured by
`print-board.sh`), `WATCH_BOARD_WATCHER` (`auto` when absent — `poll` or `fswatch`
override the watcher's probe).

---

## Scripts

They ship in the plugin (`plugin/scripts/`) and are invoked as
`${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh`. Run from a bundle root unless noted.

| Script | Does | Writes? |
|---|---|---|
| `init-bundle.sh` | `<dir>` — creates or refreshes a bundle, and converts one stamped by the retired `install.sh`: seed content copied where absent, machinery links removed, `repos/` linked. `--config` is retired (2026-10-28) and refuses by name | yes, that bundle |
| `refresh-seeds.sh` | `<dir>` — 3-way merges a seed change the plugin made since the bundle was stamped; a hand-diverged file is reported, never forced, and its conflicted merge is saved as `.bak.<epoch>` | only with `--apply` |
| `validate-bundle.sh` | schema errors + dangling frontmatter references | no |
| `normalise-config.sh` | `<dir>` — reports what is out of place across the two config files: MISPLACED (a per-machine key in the tracked `instance.config.json`, or a tracked-only key such as `defaultOwner` in `instance.config.local.json`), MISSING (a seed key the tracked file lacks) and ORDER. Values are never changed — only placed, ordered, or added when absent — and the tracked file is left **staged**, never committed. Run by every `/loopd:init` stamp | only with `--apply` |
| `migrate-bundle.sh` | mechanical schema repairs; `--layout-only` runs just the two directory steps (the `.loopd/` move) and no content repair | only with `--apply` |
| `ledger.sh` | `append` / `show` a knowledge item's append-only `ledger:` line — why it changed, who applied it, which items; no verb edits or removes an entry | `append` only, that one item |
| `kb-compare.sh` | `[--instance DIR] <candidate.md>` — compares ONE candidate Finding against every `type: Finding` under `knowledge/`; no tick step calls it. The key is the content words of title + description + `lesson:`, and only an EQUAL key is the same. Prints at most one proposal (merge, or patch as `edit`) on stdout and one verdict on stderr — merge · patch · append as new · human-authored, review only. 0 compared · 1 unreadable · 2 usage | no |
| `kb-apply.sh` | run by a human in their own terminal: applies exactly the proposals one report names, plus the regenerated index, one `ledger:` entry per item, the report's `status: done` and ONE commit. Every proposal is checked first, so a stale or missing item, or a human-written one `--human-docs` does not name, refuses the whole report | yes, the items the report names |
| `kb-usage.sh` | `record` — the citation store: runs `cite-check.sh` on a text and stores the slugs it kept, one file per text; `--task` grades the task's citation of its own new Finding `SELF` | one citation file under the bundle directory |
| `dispatchable-ready.sh` | the one reader of which `ready` tasks step 3 could dispatch (kind, open questions, dependencies, pause, owner — an unanswered gate counts), shared by `tick-delta.sh check` and the session banner | no |
| `project-paused.sh` | answers whether a project is paused, as one predicate with a three-value exit | no |
| `project-inputs.sh` | `[--release] <path>` — whether a project on `inputs: later` still waits for its files: 0 ready · 1 waiting · 2 cannot answer · 3 arrived (`sources/` holds a file besides README.md). `--release` flips an arrived one to `inputs: now` and logs it by count. Reads file presence, never contents | `--release` only — that `project.md` and `log.md` |
| `prune-worktrees.sh` | classifies worktrees, prints the `remove` commands | **never** |
| `prune-wt.sh` | `[--yes]` — behind `/loopd:prune-wt`: previews, then removes the pruner's `REMOVABLE` set, re-checking each path with `reclaim-worktree.sh`'s guards (unlocked, clean, pushed, no non-cache ignored file, no live process) and running `git worktree prune` per repo. Refuses while the tick lock is held; never forces | `--yes` only — those worktrees |
| `update-plugin.sh` | `[--verbose]` — behind `/loopd:update`: `claude plugin marketplace update`, then `claude plugin update <p>@<marketplace> -s user` per user-scope plugin of it (never an install, never a project-scope entry — those are one summary line unless `--verbose`), then the new version's `init-bundle.sh` on the bundle in the cwd, resolved from the registry's user entry; ends with the `/reload-plugins` line. Exit 0 · 1 a plugin failed · 2 nothing stamped · else init's | the user-scope plugin installs, then the bundle in the cwd, through init |
| `reclaim-worktree.sh` | `<task-path>` — removes the ONE worktree that task recorded, with no scan. 0 removed (`--dry-run`: every guard passed) · 1 REFUSED · 2 cannot answer · 3 nothing to do · 4 REFUSED only by the task's own recorded session, a retry. Exit 0 needs `status: done` **and** every `pr:` URL MERGED, so closed-unmerged and an empty `pr:` both refuse, as do a dirty or unpushed tree, a detached HEAD, ignored content outside the cache allowlist (`node_modules`, husky's `.husky/_/`, build caches — never `.env`), and a live process in the tree | yes — that one worktree |
| `commit-as.sh` | commits as the right agent identity | yes |
| `required-checks.sh` | resolves a PR's required checks | no |
| `merge-queue.sh` | `<o>/<n> <branch> [--pr <n> --head <sha>]` — would a push to the default branch join a concurrency group with a pending or running run? 0 clear, 1 hold, 2 unknown, 3 unknown at the D3 bound (the 2nd unknown at one head); with `--pr` the hold mark keeps the reason on 2 and 3, one line of at most 200 characters | no |
| `review-clearance.sh` | asserts an artifact **evidencing a completed review** exists on a PR (never a green check) | no |
| `review-rounds.sh` | `<pr> --for coderabbit\|qa` — counts one reviewer's completed **rounds** on a PR (`--last`: its last reviewed commit; `--verdicts`: `<sha> <verdict>` per QA round); exit non-zero at or past `coderabbitRounds` / `qaRounds` (1 each when absent) | no |
| `review-next.sh` | `<pr>` — what the tick does next on an in-review PR, one word: `dispatch-qa`, `request-review`, `implementer-round`, `rebase-round`, `merge-path` or `hold`; the same under `gated` and `yolo` (`--decide` takes the facts directly) | no |
| `qa-dispatch.sh` | `mint\|check --repo <o>/<n> --pr <n> --head <sha>` — the project-manager's record of a `qa-reviewer` dispatch: `mint` prints a nonce for the brief and stores only its sha256; `check` (with `--nonce`, `--after`) is what lets a same-login QA verdict count | no |
| `resolve-review-config.sh` | prints `coderabbitRounds`, `qaRounds`, `reviewFixMaxLines` (absent ⇒ 1, 1, 300); exit 1 names a value that is not an integer ≥ 0 | no |
| `rebase-pr.sh` | `<pr>` — the deterministic first try at a CONFLICTING PR, so a one-hunk merge magnet costs no agent: rebase in a throwaway worktree and auto-resolve **only** the known shapes (an `EXPECTED_ASSERTIONS=N` counter → the three-way sum of both sides' deltas; a ratchet row both sides lowered → recomputed from the merged file; a comment history → both kept), assert the result parses and kept exactly one assignment, then push with an explicit `--force-with-lease=<ref>:<the host's own headRefOid>` and let CI verify. 0 pushed · 3 an **unclassified** conflict, named, which is the one exit that earns an agent round · 4 the resolution failed its own check · 5 refused (fork head, closed) · 6 the lease no longer holds. Every non-zero leaves the branch and the remote untouched | yes — a temp worktree, and a lease push to that PR's own branch |
| `pr-body-clearance.sh` | asserts a PR **body** carries the required shape — the TL;DR heading, a `Verified:` line that cites something, and a criteria table whose heading tally matches its rows. `--body-file` decides on a draft before you open it | no |
| `pr-comment-clearance.sh` | asserts a **reply to review findings** carries a verdict per finding, and that no element exceeds the measured ceiling. `--comment-file` decides before you post | no |
| `pr-verdict-clearance.sh` | compares the **worker's** `✓`/`✗` criteria table (the PR body) with the **checker's** re-derived `PASS`/`FAIL` one (a PR comment). 0 agree · 1 the worker passed what the checker failed · 3 a checker row with no verdict or no command · 4 the checker is the PR author · 2 unknown | no |
| `report-clearance.sh` | `--body-file <path\|->` — refuses a tick report that is not the three-part shape: what happened, what is blocking (only when something is), and a numbered `Needs you:` list. One `REFUSED <rule>: …` line per breach; 0 clear · 1 refused · 2 usage. Called by `hooks/report-shape.sh` on `SubagentStop`; the spec and what each detector does not catch are in `agents/project-manager.md` → "Output". `--self-test` proves the file is complete | no |
| `cite-check.sh` | keeps the `[[finding-slug]]` citations a brief actually carried, drops the rest, and exits 1 when a citing line ends up with none. Reports a dropped id as `UNREAD` (in `knowledge/index.md`, not in the brief) or `FABRICATED` (in no row) | no |
| `check-dispatch.sh` | `<task-doc>` — did the dispatch actually produce the PR it promised | **never** |
| `control.sh` | the live kill switch for one dispatched agent — `agents`, then `halt`, `gate` or `steer` it | yes, `.claude/control/` |
| `resolve-effort.sh` | `<agent>` (or `--all`) — prints the reasoning effort it should be spawned at, from `roleEffort` (local file first; the bundle stamp seeds it). No entry ⇒ nothing, exit 0, and the spawn passes no effort; an unknown level ⇒ exit 1 and a line naming it | no |
| `resolve-model.sh` | `<agent>` (or `--all`: every role in one process) — prints the model alias it should run on, from `roleTiers`/`models` (local file first; the bundle stamp seeds both there). No entry ⇒ nothing on stdout, exit 1, and **a line on stderr** saying the caller would otherwise inherit the session model | no |
| `tick-lock.sh` | `acquire [--as launcher\|tick]`/`release`/`status` — the per-clone PM dispatch lock; exit 0 is the only clearance to dispatch or to run a tick | `acquire`/`release` only, `.tick-lock` + `.tick-lock.claim` (gitignored) |
| `tick-reap.sh` | `[--wait]` — the `/loopd:dispatch` reaper, run before every acquire: reaps the bg tick `.tick-lock` records; releases the lock only on a committed ledger close for its minted id (and `claude stop`s the session when its turn is over — `status: idle` — rather than wait ~60m for the daemon to retire it), closes a dead tick's entry, reports `BLOCKED`; prints the close line, Needs-you and a `COST:` line | `.tick-lock` release, a `close:` line in `.loopd/log.md` for a dead tick, `claude stop` on a blocked or idle tick session |
| `tick-spawn.sh` | `--tick <id> [--gap] [--dry-run] [--print]` — spawns the tick as `claude --bg --agent loopd:project-manager --permission-mode auto` with the brief from `skills/dispatch/tick-brief.md`; records its session on the lock | `session:`/`spawned:` lines on `.tick-lock`; releases it when the spawn fails |
| `tick-delta.sh` | `check [--gap <interval>]`/`record`/`digest` — the idle-tick fast-path probe and the tick's one-command orientation: a full tick records a fingerprint (bundle HEAD, task statuses, open-PR heads/states/decisions/unresolved threads, the PR facts being the ones the tick read first, never a fresh host read at its end), the next tick compares — only a byte-for-byte match (exit 0) permits skipping the full walk, and every doubt is the full tick. The `IDLE:` line is ONE line and IS the quiet tick's whole report, so `--gap` makes it name the next check; `digest` prints the same walk enriched (project/task fields + PR facts) so step 1 is one read instead of N. `record --close "<summary>" [--tick ISO] [--tokens N --tools N --duration-ms N]` is the ledger half: it appends the `close:` line **beside** the tick's own `open:` line (never over it, so the pair carries the tick's wall duration), copying that line's timestamp and `by <login>`, with the three notification numbers in the one fixed form `agent-usage.sh fmt` owns — offline, and refused if the entry is already closed. `--tick` names which open entry to close, matched exactly; without it a close is taken only when exactly one entry is open, never guessed between two | `record` only, `.tick-state` (gitignored) and `log.md` on `--close` |
| `design-inputs.sh` | `<project-dir>` — the 16-hex fingerprint of what a project's `design.md` was drawn from: its decisions and each refined task's criteria and answered questions, stable across a fold. Step 2 writes it as `inputs_hash:`; `tick-delta.sh` reports a `redraw stale` DELTA on a mismatch. Unreadable input exits 1 and prints nothing | no |
| `agent-usage.sh` | `fmt`/`dispatch`/`total`/`settle`/`series` — what the harness handed back, **in tokens and never in money**: `fmt` is the one fixed `usage tokens=N tools=N ms=N` form every other writer calls, `dispatch <task-doc> --role R --model M` appends one `# Notes` line per role dispatch from that agent's notification (a re-dispatch appends a second), `total <task-doc> --pr <url>` sums those lines against the merged PR at reflect time (no dispatch lines ⇒ `usage UNKNOWN`, never zero), and `series` prints the month-by-month figures from `log.md`'s `TICK` pairs and those dispatch lines — file reads only, no `gh` and no transcript | `dispatch`/`total` only, that task document |
| `session-usage.sh` | `<session-id> [--settle <task-doc>]` — what ONE detached role-agent session cost: from the usage mod's plugin-store record when that mod was on in the session, else from the session's own transcript, counted **once per message** (a transcript repeats a message's usage on every content block's line): prints `usage tokens=N tools=N ms=N cached=N`, or `usage UNKNOWN` on any doubt — no transcript, two candidates, no usage record, no `jq`. `--settle` hands the numbers to `agent-usage.sh settle`, which fills that task's last UNKNOWN dispatch line. The one file that knows where a transcript lives | only with `--settle` |
| `prompt-cost.sh` | `[--projects-dir DIR] [--since ISO] [--limit N] [--kind tick\|dispatch] [--sessions]` — tokens **per assistant turn**, per tick step and per dispatch role, read from session transcripts: input, output, cache-read and cache-write, totals and per-turn means, counts only and never message text. A tick's turns go to the `tick-steps/` file last read before the turn (`core` before any); subagent turns bucket as `+sub`. The tick never runs it — it is the measuring stick for a prompt trim (`tests/prompt-cost.test.sh`). | no |
| `memory-stale.sh` | `[--instance DIR]` — lists each Claude Code auto-memory note of this bundle (`${CLAUDE_CONFIG_DIR:-~/.claude}/projects/<path>/memory`) that names a done/cancelled `<slug>/task-NNN`, a `projects/<slug>` with no folder, or a `loopd`/`v` version older than `VERSION` outside a since/from/before/until/as of/measured on/fixed by/fixed in/on phrase: file name and reason, never content; writes nothing. `/loopd:welcome check` row `memory-stale`. 0 read · 2 UNKNOWN · 3 usage | no |
| `pr-quality.sh` | `--repo <owner/name> [--limit 40] [--window 20] [--ledger <log.md>] [--rows]` — ✗ criteria rows per merged PR body, CodeRabbit inline review comments and qa-reviewer okf-verdict `FAIL` rows per PR (counted apart, `-` where that reviewer never reviewed), stall escalations from the ledger inside each window's merge span, and the band between two consecutive windows. Needs `gh`; exit 1 when the host cannot answer for every PR (`tests/pr-quality.test.sh`). | no |
| `task-owner.sh` | resolves and compares a task's owner | no |
| `stall-counter.sh` | `record`/`escalate`/`status`/`reset` — the per-task stall memory: `record <task-doc> --blocker <text>` after each round (`--progress` when the PR moved) counts consecutive rounds on the same blocker and **exits 1 at or past `maxStallRounds`** (absent ⇒ **2**); `escalate` then sets `status: blocked`, notes the blocker and prints the one `⛔ **unblock**` line for `AWAITING.md`; `reset` zeroes `stall_count` and keeps `last_blocker` (`unblock.sh`) | `record`/`escalate`/`reset` only, that task document |
| `do-not-repeat.sh` | `append`/`brief` — the per-task memory of DEAD ENDS: `append <task-doc> --line <text>` records one approach an ended round already tried and the evidence it failed on (folded to one line, 200 chars, deduped, **capped at 10** — exit 1 past it, fold the oldest into `# Notes`); `brief` prints those lines verbatim under a fixed heading for the next dispatch's brief, and nothing at all when there are none | `append` only, that task document |
| `fold-answers.sh` | `<task-doc>` (`--sweep <entry> <note>` appends a sweep note to one open entry and moves nothing) — moves every ` --- `-answered `open_questions` entry into `answered_questions`, stamped `<ISO> by <login> · <entry verbatim>` with the login from `decision-stamp.sh`. Exit 4 rather than leave one entry in both lists, exit 3 rather than emit a list it could not round-trip; `--list <doc> <key>` is the same parser, read-only; `--answer <entry> <text>` answers that one entry first; `--add <doc> <entry>...` appends entries through the same round-trip, skipping any already open or answered | yes, that task document |
| `session-handoff.sh` | `<task-doc> [--jobs-dir <dir>]` — the tick's stop of a role session only the human can move on. A `blocked` session with a `needs` (and no live `waitingFor` prompt) is HANDED OFF: its text goes verbatim to the ignored `.loopd/.handoffs/<id>.txt`, which `AWAITING.md` renders as one `👉 do` row, and the task gets one fixed-text `Q<n>: do:` entry, its block and a note in one atomic write; then `claude stop <short>`. A `done`/`cancelled` task's session is stopped unless it already ended, after filing any pending `needs`. `--owed <task-doc>` says when the answered hand-off's round is due a resume. 0 done · 1 not its case · 2 unknown · 3 the stop did not land. Never `claude rm` | yes — that task document, the hand-off file and one `claude stop` |
| `session-sweep.sh` | `<bundle-root>` — step 5's stop of this bundle's dead sessions no task owns: `claude stop` on each id `agent-sessions.sh dead-ids` selects (no live pid on the row or in the roster, no task records it or its `cwd`, a `cwd` under the bundle root, past 10m — 24h when `blocked`), each resolved back through `full` first, at most 20 a run; prints `stopped <short> (<age>)` or `stop-failed <short>` per id. Exit 2 is unknown and stopped nothing | no file; `claude stop` only |
| `answer.sh` | `<task-doc> [Q<n>] <n \| more \| later \| text>` — behind `/loopd:answer <task> …`: a `blocked` task with no `Q<n>` goes to `unblock.sh` (refused while it has an open question); a bare integer records that option's text from the `### Q<n>` block, `--text` records any words, `more` prints the next stored depth (counted per clone under `.loopd/.answer-depth/`), `later` appends `<task path>#Q<n>` to the per-clone `.loopd/.answer-later` the pane draws last. Moves the entry through `fold-answers.sh`, commits through `commit-as.sh human`, pushes through `push-commit.sh`, then runs `write-snapshot.sh --quiet` (best-effort) so `/pane` shows it. 0 done · 1 refused · 3 move refused · 4 committed, not pushed (never forced; aborts only a rebase it started) · 5 past the stored depths · 6 `more` or `later` could not save its record | yes, that task document and one commit |
| `unblock.sh` | `<task-doc> [--decision <words>]` — behind `/loopd:answer` on a `blocked` task (`answer.sh` routes it): refuses a task that is not `blocked` (exit 1); with no decision prints `last_blocker` and the escalation note; with one appends a `# Notes` line stamped `by <login>` (`decision-stamp.sh --self`), runs `stall-counter.sh reset`, sets `status: ready`, commits through `commit-as.sh human`, pushes through `push-commit.sh` and runs `write-snapshot.sh --quiet` (best-effort). 3 a write failed · 4 committed, not pushed | yes, that task document and one commit |
| `new-project-form.sh` | `[<n> <text> \| submit \| cancel]` — behind a no-description `/loopd:new-project`: the five-field form (title, what, for whom, done when, target repo, prefilled with `defaultRepo`) the pane draws. No arguments opens it, `<n> <text>` fills a field verbatim, `cancel` removes it; `submit` writes ✗ on each missing field (exit 1) or prints one JSON line the skill creates from, with `kind`, `autonomy` and `owner` (`decision-stamp.sh --self`) set by the script so field text never moves them. Exit 3: not a form command | yes — `.loopd/.new-project/form.json`, self-ignoring |
| `new-project-file.sh` | `<entry.json>` — run by `web-queue.sh consume` for a queued `new-project`: one project, `autonomy: gated` whatever the text says, every value a quoted string, one `draft` seed task, stage 1 of the scaffold review, then a commit as `human`, a push and `write-snapshot.sh --quiet` (best-effort). Exit 1: refused (e.g. the slug exists), nothing written | yes — the project, its ledger entry |
| `web-queue.sh` | `append`/`consume`/`pending`/`status` — the web board's answer queue: `board-serve.sh` appends a POSTed entry (strict schema, server-set `ts` and `from`); the dispatch tick consumes it under the tick lock (`project-manager.md`, after the idle probe), printing ids and verdicts only, into a durable ledger. Exit 3: another consumer · 4: no tick lock | yes — `.loopd/.queue/`, self-ignoring |
| `push-commit.sh` | `<dir>` — pushes the commit just made, for `answer.sh` and `/loopd:new-project`: fetch, `pull --rebase` only when the upstream moved (so a dirty tree still pushes), push. 0 pushed · 2 usage · 3 no upstream, silent · 4 committed, not pushed — one line (never forced; aborts only a rebase it started) | yes — pushes the current branch |
| `dispatch-brief.sh` | `<task-doc>` — the eight fixed sections the PM pastes into a dispatch brief verbatim: `## Grounding (<target_repo>)`, the entry points of the Service doc `service-doc.sh` matches, capped at **15 lines** (absent one, a line telling the agent to draft it for the `cataloguer`); `## Effort`, the files/LOC/turns budget; `## Commit attribution`; `## PR title`; `## Scratch`, a directory keyed on the task slug, `git check-ignore`d against the target repo's clone; `## Deliverables`; `## Signature`, the `role-signature.sh` call carrying this bundle's path; and `## Knowledge`, `kb-select.sh`'s Finding rows | no |
| `service-doc.sh` | `<task-doc> [--instance <bundle>]` — the one matcher from a task to its Service doc: `target_repo` (else the project's), `repo:` equal and not `deprecated`, then a literal `path:` the task names, `<repo-basename>.md`, the first slug. `--repo` prints the resolved repo; `--ties` every equally-ranked doc. 0 printed · 1 none · 2 unreadable | no |
| `deploy-mode.sh` | `<task-doc>` — prints `manual`, `auto`, `n/a` (research) or `UNKNOWN`: the task's `deploy:`, else the Service docs `service-doc.sh --ties` matches (any `manual` wins), else `auto`. 0 · 3 UNKNOWN · 2 usage | no |
| `reflect-deploy.sh` | `<task-doc>` — step 5's write for a `done` task that resolves `manual`: one `merged, not deployed` note, one `Q<n>: do: deploy …` entry naming the repo and merged PR, and its block, once. 0 written · 1 nothing to write · 2 refused · 3 UNKNOWN | yes — that task document |
| `kb-select.sh` | `<task-doc>` — the 1-5 current Findings a brief carries, as `[[slug]] — lesson` rows ranked by rarity-weighted content-word overlap (`kb-words.sh`), or one `none matched` line. `--record` appends the chosen slugs to the task's `# Notes`; `--recorded` prints them back for `kb-usage.sh record --brief` | `--record` only, one `# Notes` line |
| `kb-stale.sh` | `[--instance DIR]` — lists each active Service whose clone has `kbStaleCommits` (absent ⇒ **20**) commits on the `origin/HEAD` ref since its `timestamp:` (on `path:`, else the whole repo), and each Runbook whose `applies_to:` Services (exact slug or `title:`) moved since the Runbook's own `timestamp:`; UNKNOWN where it cannot measure, never 0. Never fetches. Step 7 pastes it into a cataloguer brief already going out. 0 listed · 1 nothing · 2 usage | no |
| `verified-facts.sh` | `[--instance DIR] [--presence] <task-doc>` — is a build task's `## Verified facts` section present and still true: `verified` 0, `missing` 1, `stale` 3 (a path it names changed on `origin/<default>` since its sha), `unknown` 4 (no clone, failed fetch, sha absent), `research` 5. One bounded `ls-remote` for the remote's default branch and one bounded fetch of it; `--presence` reads the document alone | no |
| `question-sweep.sh` | `[--instance DIR] [--apply] [<task-doc>...]` — evaluates each open question's trailing ` check: <kind> <arg>` (`pr-merged`, `file`, `decision`) from GitHub or the committed bundle and prints `true`/`false`/`unknown`/`refused` per entry; `--apply` appends ` · sweep: <predicate> true @ <evidence>` through `fold-answers.sh --sweep` and never answers. Run by every full tick (`project-manager.md` step 2.6); `SCHEMA.md` → "Evidence sweep" | `--apply` only, one open entry per true predicate |
| `kb-words.sh` | sourced, never run — the content-word key `kb-compare.sh` and `kb-select.sh` share | no |
| `release-bump.sh` | `<minor\|patch>` — moves the version in the **five** places that carry it (`VERSION`, `plugin/VERSION`, both manifests, and the banner sample, whose `─` rule is re-cut to the new header's width), on the **default branch, after a merge**. Refuses on a feature branch, a dirty tree, or a new version that reaches an open deprecation `until`; commits and prints the push, never pushes | yes, those five |
| `deprecation-windows.sh` | `[--root DIR] [--version X.Y.Z]` — lists each deprecation window under `plugin/`, `.claude/rules/` and in `README.md`, `docs/operations.md` and `docs/conventions.md` with no `until <x.y.z>` on its line (`BARE`) or whose `until` the version has reached (`EXPIRED`); `--cmp A B` is the per-field comparator. Run by `tests/deprecation-windows.test.sh` and `release-bump.sh`. 0 none · 1 listed · 2 usage | no |
| `check-template-version.sh` | is the plugin on this machine older than the remote's default branch — prints a line **only when behind**, silence on every failure | not the instance — `--fetch` (opt-in) updates the template checkout's remote-tracking refs; on an install, its cache and `latest-version` in the plugin's data dir |
| `close-project-folder.sh` | closeout's folder step — `git rm -r` the project, or freeze and keep it on `retain: true` | only with `--apply` |
| `write-snapshot.sh` | refreshes `SNAPSHOT.json` | only if it already exists |
| `build-board.sh` | renders the HTML board (anywhere; needs `python3`) — pass `.` to render THIS instance only | yes, the output file |
| `whats-up.sh` | backs `/loopd:whats-up` — `AWAITING.md`'s rows as a numbered `Needs you:` block, verbatim and in the file's order, plus its `Last refreshed:` age and the `tick-lock.sh status` verdict. Reads no task document, no `gh`, no `git`; `"awaiting": false` or no `AWAITING.md` ⇒ one off line naming the switch, and the file is never created | no |
| `print-board.sh` | prints the board in the terminal | no |
| `status-line.sh` | the bundle's Claude Code `statusLine`: one coloured line — `loopd · <n> in progress[ · <n> in review] · <n> working · <n> idle · <n> dead · <n> need you[ · lock held] · last tick <hh:mm>` — every number from `counts.sh`, the clock from `log.md`'s last `* TICK`, the lock from `.tick-lock`. No `jq`, no `gh`, no model; a number it cannot establish renders `?`; sessions count live processes, not work, `in review` shows only when non-zero, and a free lock is not shown; outside a bundle it prints nothing. The `need you` segment is three-state: `"awaiting": false` or a deleted `AWAITING.md` is the queue off, so the segment goes; an unreadable one says so and names its own `chmod +r` repair. Each run also writes `.loopd/counts.json` (gitignored) for the pane. `/loopd:init` installs it into the BUNDLE's `.claude/settings.json` and never the user's | yes — `.loopd/counts.json`, and the 10-second sessions cache under `${XDG_CACHE_HOME:-~/.cache}/loopd/` |
| `watch-board.sh` | renders the board into `.board-live/` and re-renders on every change | yes, the page (gitignored) |
| `board-serve.sh` | serves `.board-live/` on `127.0.0.1:<boardPort>` and re-renders it when `SNAPSHOT.json` changes — one process per bundle | yes, the page (gitignored) |
| `link-repos.sh` | refreshes `<instance>/repos/`, and writes each linked repo's `.git/loopd-bundle` — the marker the plugin's safety hooks follow from a role agent's worktree back to this bundle | yes |
| `index-kb.sh` | builds local CodeGraph indexes for the group's repos (code intelligence — **not** the knowledge base) | yes |
| `continue-checkpoint.sh` | names each active project past `continueAfterTasks`/`continueAfterDays` (absent ⇒ off) or its `timebox:`, for `build-awaiting.sh`'s `continue` row and `tick-delta.sh`'s fingerprint | no |
| `build-awaiting.sh` | renders `AWAITING.md` — the heading and its count, the `* ` marker `session-banner.sh` greps literally, the glyph, the verb and the link — from the task documents, never `SNAPSHOT.json`. It classifies `grant` against `answer` from the `open_questions` entry itself, narrows to this clone's human with `task-owner.sh`, takes each row's trailing sentence as a `--trailer`, and marks a build draft's `approve` row `unverified` or `stale` from the `--facts` verdict `verified-facts.sh` printed. No `AWAITING.md` ⇒ it writes nothing and exits 0 | yes, that file (gitignored) |
| `build-kb-index.sh` | regenerates `knowledge/index.md` from document frontmatter; `--check` fails on a doc with no row, a row pointing at no file, an empty summary, an unescaped pipe, a status outside `{current, superseded, corrected}`, a tag outside `knowledge/vocab.md`, a dangling supersession edge, or (as a warning, an error under `--strict`) a bundle-relative link in `knowledge/**` or a `source:` path token that resolves to nothing | yes, that index |
| `kb-sync.sh` | mounts, reads and writes a knowledge base held in another repository (`knowledge` in `instance.config.json`) — `mount` clones it into `knowledge/` as a nested, gitignored clone, `pull` fast-forwards it under a named timeout, `status` reports unpushed KB commits, and `commit` is the one bounded write transaction: rebase, regenerate the index, commit, push, one retry, then stop and report. Absent the key it exits 3 and touches nothing | yes, the mounted KB (never the bundle) |
| `kb-migrate.sh` | moves a bundle's own `knowledge/` into the repo `knowledge.repo` names — one recorded commit pair, refuses a dirty tree, prints every path it moved, and seeds the KB repo's harness-neutral reading rule | yes, both repos |
| `kb-sweep-due.sh` | does this tick owe the cataloguer a `knowledge/` sweep — due only when it dispatched nothing this round, no cataloguer is in flight, a slot is free under `maxAgentsInFlight`, and `build-kb-index.sh --check` reports at least one ERROR. On exit 0 it prints the trigger line and the error list, which is the cataloguer's brief. Every walk is stamped with its error list in the per-clone, ignored `.loopd/.kb-check-stamp`; it answers until anything under `knowledge/`, `build-kb-index.sh` or a script it sources is newer (`cached, stamp <time>`), and a stamp with errors also expires after `kbSweepIntervalHours` (absent ⇒ **24**) — inside it, exit 1 with a `KB SWEEP CACHED: <n> error(s)` line | no, beyond that stamp |
| `papercuts.sh` | the cheap end of the knowledge loop — `add` appends one validated line to `knowledge/papercuts.md`, `check` refuses a malformed entry, `report` groups the unprocessed entries by surface for the cataloguer, `due` answers whether a weekly pass is owed, `pass` marks the entries processed | `add`/`pass` only, that record |

**Internal helpers** — the machinery calls these; you normally don't. They are listed so
the table above accounts for **every** script in `plugin/scripts/`, which
`tests/readme-scripts-table.test.sh` asserts.

| Script | Does | Writes? |
|---|---|---|
| `welcome.sh` | backs `/loopd:welcome`: reprints the SessionStart banner, and `check` reports state that could be wrong. Its `fix` pass runs only inside `/loopd:init` (`LOOPD_INIT_PASS=1`); called any other way, `fix` is a usage error, exit 2 | only the `fix` pass, under `/loopd:init` |
| `role-signature.sh` | `<role> [--instance <bundle>]` — the line every agent PR comment and review ends with, `— <login>-<qa\|dev\|ops\|pm>`, the login from `decision-stamp.sh --self` (`(unknown)` when unset — GitHub would strip `<unknown>`). A label for humans: no gate reads it | no |
| `decision-stamp.sh` | the one resolver of *which GitHub login made a decision a document records* — `--self` for a decision taken in this session, `--author <path>`/`--promotion <path>` for one that arrived as a commit (the git author's email reverse-mapped through `people`, so a hand-promotion or a reply pushed from the other clone attributes to the other human). Unattributable prints `<unknown>` and exits 1; the stamp is written anyway. A login, never an address | no |
| `bundle-paths.sh` | the one place a bundle's layout is spelled — sourced it exports `AB_SCHEMA`, `AB_AWAITING`, `AB_LEDGER` and the rest as paths relative to a bundle root; run it, it prints them | no |
| `plugin-name.sh` | the one place the plugin names itself — sourced (via `bundle-paths.sh`) it sets `PLUGIN_NAME` and `PLUGIN_MARKETPLACE` from the install path `<cache>/<marketplace>/<plugin>/<version>`, or from the two manifests in a checkout; run it, it prints them | no |
| `counts.sh` | the one definition of the bundle's numbers — sourced by `status-line.sh`: `ab_counts` sets in progress, in review, sessions working/idle/dead (with a per-task word) and need you; `ab_write_counts` writes them to `.loopd/counts.json` atomically, `?` as `null`, no free text, plus `plugin_version` from the plugin's own `VERSION` and `latest_version` from the `latest-version` file `check-template-version.sh` keeps in the plugin's data dir (each omitted unless `x.y.z`) — skipped in a git bundle whose `.gitignore` lacks that line until `/loopd:init` adds it | yes — `.loopd/counts.json`, and the 10-second sessions cache under `${XDG_CACHE_HOME:-~/.cache}/loopd/` |
| `cli-theme.sh` | the one place a plugin surface's colour escapes are spelled — sourced by the banner, status line, board and `welcome.sh`; `ab_theme` picks the tier | no |
| `resolve-config.sh` | the one implementation of the two-file config precedence — `instance.config.local.json` first, `instance.config.json` second, dicts merged entry by entry | no |
| `resolve-max-agents.sh` | prints the concurrency cap **this machine** should honour, from the same two files | no |
| `resource-gate.sh` | step 3's other read before a wave: free disk under `worktreeRoot` and available memory against `minFreeDiskGb` / `minFreeMemGb` (decimal GB, per-machine; absent ⇒ no gate). Exit 1 below a floor and the wave spawns nothing; a failed measurement is `UNKNOWN` and allows | no |
| `spawn-preflight.sh` | step 3's read before a wave: what permission mode is **this session** in? Reads the mode `hooks/permission-mode.sh` recorded for this call, matched by its `--token` — no probe, no spawn. Exit 1 `auto`, 0 `not-auto`, 2 `could-not-read`, never folded into either. It reports the mode and predicts no launch outcome: the classifier judges the brief, not the command | no |
| `agent-sessions.sh` | the one reader of a dispatched role agent's **background** session — `state <id>` prints `working`/`blocked`/`done`/`gone`, `row <id>` prints its one `claude agents` row as JSON, `in-flight <bundle>` counts the recorded `session:` ids that still hold a `maxAgentsInFlight` slot, `view <bundle>` lists this bundle's sessions by task (joined on `worktree:`), state and whether a live process is behind each, `dead-ids <bundle>` prints the ones `session-sweep.sh` may stop, `worker <id>` reads its live pid off the daemon roster, `resume-id <uuid> <stdout>` says whether a resume kept the id or forked a copy. Exit 2 is unknown, never a free slot or zero agents | no |
| `resolve-autonomy.sh` | the one reader of *does delegated autonomy exist here* — prints the `AUTONOMY.md` in force (bundle root first, else an installed companion plugin from core's own marketplace), exit 1 when there is none, which is `gated` | no |
| `merge-permit.sh` | the policy half of the deny baseline's `subagent_merge` rule — 0 only where the owning project's mode delegates the merge, the caller is exactly `<plugin>:project-manager` and all four clearances are recorded at the head being merged; 1 refuses, printing why | no |
| `clearance-receipt.sh` | `record`/`verify`/`path` for those clearance records — one file per repo, PR and head under `.tick-receipts/`, written by the four clearance scripts and read offline by the hook | `record` only, `.tick-receipts/` (gitignored) |


---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `/loopd:dispatch` reports "Unknown command" | the **plugin** is not installed on this machine, or Claude Code has not restarted since — never the bundle, which delivers no commands at all | `/plugin marketplace add cbmono/loopd`, `/plugin install loopd@loopd`, then `/exit` and relaunch |
| A command or agent is missing after an update | the session still runs the plugin version it started with | `/reload-plugins`, or restart Claude Code |
| Commands work on one machine and not on another | the plugin is per machine; the bundle carries none of it | install the plugin on that machine, then `/loopd:init` inside its clone of the bundle |
| A seed change from a plugin update never arrived | seed content is copied once, and refreshed only by a stamp | `/loopd:init` — it 3-way merges the change and reports any file you edited by hand, which you port yourself |
| Validator errors right after an update | the plugin updated, the bundle's data didn't | `/loopd:init` runs the stamp and the check-and-fix pass in the right order |
| The banner's Needs-you block is empty | `.loopd/AWAITING.md` was deleted, `"awaiting": false` is set, or its layout was reshaped | `/loopd:init` recreates the file unless the key is `false`; `session-banner.sh` greps the heading and bullets **literally** |
| A bundle is missing from the board | it has no `.loopd/SNAPSHOT.json`, or `boardInstances` doesn't name it | `/loopd:init` in it recreates the snapshot while `board` is on |
| `print-board.sh` printed nothing at all | it was not run from a bundle root — that is silence by design, not an error | `cd` into the bundle |
| The terminal board is missing a status column | every row was zero there, so it was dropped to fit the width; the footer names which | widen the terminal, or `--width 0` |
| The live page never updates | the watcher or the server was stopped, or the change was outside `projects/` | `/loopd:board`, or restart `scripts/watch-board.sh`; it prints a line per render |
| A `yolo` project never merges anything | preflight failed: one `gh` identity, no external reviewer, or no required checks | the loop says which; fix that, or merge by hand |
| `required-checks.sh` exits 2 | the platform probe returned something it cannot classify | that is a refusal by design — read the message, don't loosen the script |
| A PR is all-green but not merge-eligible | the reviewer published "Review limit reached" behind a green check — `review-clearance.sh` exit 1 | wait for the reopen time it quotes, then ask for a **first** review; nothing re-reviews a skipped PR by itself |
| `required-checks.sh` exits 2, "review-clearance.sh not found" or "present but does not run" | the plugin's own copy of a sibling script is missing or broken — a damaged plugin install. A sibling that fails every call looks exactly like "no reviewer is required", so this refuses | `/loopd:update`; if it persists, reinstall the plugin (`/plugin install loopd@loopd`) |
| `required-checks.sh` exits 1, "no independent review clears" | every required check is green but no review artifact clears the head — the gate no longer decides from a check's *name* whether a reviewer is involved | ask for a review at the current head; if the repo genuinely has no reviewer, that is the thing to fix, not the gate |
| `review-rounds.sh` exits 1 | that reviewer has already had its `coderabbitRounds` / `qaRounds` rounds on the PR — this is the cap doing its job, not a fault | stop reviewing: put both positions (reviewer / implementer / what the criterion asks) in front of the human and let them decide |
| An agent reported "done" but no PR ever appeared | it parked before opening one — `check-dispatch.sh` exit 1, the parked signature | one message to that agent: open the PR on what it already committed. Never re-dispatch the task |
| `review-clearance.sh` exits 4 on a PR that *was* reviewed | the reviewer read an earlier push and does not re-review (`auto_incremental_review: false`) — the review is **stale**, not absent | ask for a review at the current head; this is the common case here, not a bug |
| `review-clearance.sh` exits 6 on a PR that *was* reviewed | the review is real and at the head, but a reviewer-authored thread is still unresolved — `SCHEMA.md` clause 9. The refusal names each open thread | answer or fix each thread, resolve it, push. **Do not request another review** — you already have one, and a 6 is not a 4 |
| `review-clearance.sh` exits 7 on a PR whose review and checks are green | the host reports the PR CONFLICTING / DIRTY — the default branch moved under it, with no commit on the PR. This is the first thing the script asks, because no review makes a conflicting PR mergeable | rebase onto the default branch, push with an explicit `--force-with-lease`, let CI re-run. **Do not request a review**, and do not present it as a merge row |
| `review-clearance.sh` exits 2, "is not a usable answer" on `mergeable`/`mergeStateStatus` | the host computes mergeability lazily and says UNKNOWN for seconds after the base moves; a token without push access never gets `mergeStateStatus` at all | ask again next tick. If it never clears, check that the `gh` token has push access on the repo — the merge gate needs one anyway |
| `review-clearance.sh` exits 4, "carries no evidence that a review was COMPLETED" | the only artifact is the reviewer's *"currently processing"* placeholder or similar — it names the head but nothing says anybody read it | wait for the real review, or ask for one; not-a-refusal is not a review, and clearing on it was a live false pass |
| CodeRabbit: "Unable to determine base branch" | a remote-less bundle has no `origin/HEAD` to infer one from | pass it explicitly: `--base "$(git rev-parse --abbrev-ref HEAD)"`, rather than writing `git config coderabbit.baseBranch` into the repo for a one-off review |
| Two loops dispatched the same task | `defaultOwner` is not set on a shared bundle | [sharing.md](sharing.md) |
