```text
   ▄▄▄▄
◀━▐    ▌   loopd — the loop, running
  ▝▄▄▄▄▘
```

**You steer. They build. Two gates stay yours.**

> [cbmono.github.io/loopd](https://cbmono.github.io/loopd/)

loopd is a [Claude Code](https://claude.com/claude-code) plugin that runs a small team of AI
agents on your repositories.

- **You** describe the work, and approve it before anyone starts.
- **A project-manager agent** breaks it into tasks and asks you what it can't work out.
- **Engineer agents** build each task in the background, open a pull request and get it reviewed.
- **You** merge.

You work like an engineering manager, not a pair programmer. Agents never merge, and nothing
starts until you say so.

---

## How it works

```text
/loopd:new-project  →  you promote draft → ready  →  /loopd:dispatch  →  you merge the PR
```

1. **Describe it.** `/loopd:new-project add rate limiting to the public API`. loopd scaffolds a
   project with draft tasks, each with acceptance criteria.
2. **Approve it.** Answer the questions the project manager raised, then promote the tasks you
   want from `draft` to `ready`. Nothing is built before you do.
3. **Let it run.** `/loopd:dispatch` starts the loop: every ten minutes it picks up ready tasks,
   gives each one its own git worktree and an engineer agent, and tracks the pull requests.
4. **Merge it.** An independent reviewer checks each PR first. The PR lists every criterion as
   ✓ or ✗; one ✗ blocks the merge, however green CI is.

Your work lives in a **bundle**: a small private git repo beside your code that holds only
plans, tasks and notes, never application code. One bundle per group of repos (work, a side
project, a client).

---

## Install

About ten minutes. **Needs:** Claude Code, `git`, the GitHub CLI `gh` (logged in), and bash.

**1. Install the plugin** — once per machine, in any Claude Code session:

```text
/plugin marketplace add cbmono/loopd
/plugin install loopd@loopd
```

Then restart Claude Code.

**2. Create a bundle** — once per group of repos. Put it in the folder that holds those repos:

```text
/loopd:init ~/workspace/<group>/_loopd-<group>
```

**3. Point it at your repos** — two files in the new bundle:

| File | Set |
|---|---|
| `instance.config.json` (shared) | `org` — your GitHub user or org; `defaultRepo` — the repo most work goes to |
| `instance.config.local.json` (this machine only) | `reposRoot` — the folder your clones live in |

Run `/loopd:init` once more to link the repos.

**4. Give it a remote** (optional, but it's how you back it up and share it):

```bash
cd ~/workspace/<group>/_loopd-<group>
git init && git add -A && git commit -m "chore: bootstrap loopd bundle"
gh repo create <you>/_loopd-<group> --private --source=. --push
```

**Joining a bundle someone else made?** Clone it and run `/loopd:init` inside it.
[docs/getting-started.md](docs/getting-started.md#joining-someone-elses-bundle) has the rest.

---

## Your first loop

Always start Claude **from inside the bundle** — that is where loopd finds its banner, its
config and your projects:

```bash
cd ~/workspace/<group>/_loopd-<group>
claude
```

Then:

```text
/loopd:new-project add rate limiting to the public API
```

Answer its questions, read the draft tasks, promote one to `ready`, and start the loop:

```text
/loopd:dispatch
```

Now leave it alone. **Steer, don't watch**: agents work in the background and come back with
results and questions, not every step. When something needs you, it shows up in the session
banner, in `/loopd:whats-up` and on the board.

A walkthrough of the first hour, including what to expect at each step:
[docs/getting-started.md](docs/getting-started.md).

---

## Commands

| Command | Use it to |
|---|---|
| `/loopd:new-project <description>` | start a project — build (code, PRs) or `kind=research` (documents, no repo) |
| `/loopd:dispatch` | run the loop every ten minutes · `once` for a single pass · `stop` to end it |
| `/loopd:whats-up` | see what needs you, numbered |
| `/loopd:answer` | answer the project manager's questions in chat, or unblock a stuck task |
| `/loopd:close-project <slug>` | close a finished project and keep what it learned |
| `/loopd:board` | open the board in your browser · `publish` for a private link you can open on a phone |
| `/loopd:welcome` | reprint the banner · `check` to look for setup problems |
| `/loopd:update` | update loopd, then run `/reload-plugins` |
| `/loopd:init` | create or refresh a bundle |
| `/loopd:fanout <asks>` | send several small, independent jobs to background agents at once |
| `/loopd:handoff <path> <login>` | hand a task or project to another person |
| `/loopd:prune-wt` | delete finished worktrees, after asking you |

`/pane` shows the board beside your session. Every option and flag is in
[docs/reference.md](docs/reference.md#commands).

---

## What needs you

loopd keeps one short list: the things only a person can decide. Each item carries a glyph
for what it needs — ✅ approve · ❓ answer · 🔀 merge · ⛔ unblock · 🏁 close — and a link
to the task or PR.

Everything else, including work in progress, stays off that list on purpose. A list you scroll
past is a list you stop reading.

On the board and in the pane, **two colours carry the meaning**. Blue `#5ea2ff` is the machine's:
agents, code, running work. Pink `#ff7ac2` is yours: anything waiting on a person. Green marks
only what is done.

---

## The team

| Agent | Does |
|---|---|
| `project-manager` | runs the loop: refines drafts, dispatches tasks, tracks PRs, reports |
| `software-engineer` | writes the code in a worktree and opens the PR |
| `devops-engineer` | CI, infrastructure and deploys |
| `qa-reviewer` | reviews each PR with fresh context, against its acceptance criteria |
| `failure-analyst` | finds out why a build or CI run is red; changes nothing |
| `cataloguer` | keeps the bundle's knowledge base current |

Three more agents are called in by those six as needed: `plan-architect` critiques a plan
before it is built, and `code-architect` and `deep-bug-scan` deepen a review.
Which model each one runs on is your choice:
[docs/operations.md § model routing](docs/operations.md#model-routing).

---

## Learn more

| Read | When |
|---|---|
| [Getting started](docs/getting-started.md) | your first hour, or joining a bundle someone else runs |
| [Reference](docs/reference.md) | commands and flags, config keys, scripts, troubleshooting |
| [Sharing a bundle](docs/sharing.md) | two or three people working from one bundle |
| [Autonomy](docs/autonomy.md) | letting the loop promote or merge without you (the separate `loopd-yolo` plugin) |
| [Operations](docs/operations.md) | upgrading, worktrees, the board, running the loop on a cadence |
| [Document types](docs/schema.md) | what a project, task or finding holds |
| [Migrating](MIGRATION.md) | you installed loopd under its old `ai-bridge` name |
| [Contributing](CONTRIBUTING.md) | you are changing loopd itself |

**License:** [MIT](LICENSE) · **Version:** [`VERSION`](VERSION)
