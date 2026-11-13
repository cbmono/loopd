# Getting started

Your first hour with loopd: install it, run one project end to end, and know which two
decisions stay yours. If someone else already runs the bundle and you only need to join it,
skip to [Joining someone else's bundle](#joining-someone-elses-bundle).

Placeholders: `<group>` is the folder that holds a group of your repos, `<login>` is your
GitHub login.

---

## 1. Install

The **plugin** is installed once per machine. It carries every command and every agent.
The **bundle** is a small git repo, one per group of repos, that holds your projects, tasks
and notes. It never holds application code.

| # | Do this | Where |
|---|---|---|
| 1 | `/plugin marketplace add cbmono/loopd`, then `/plugin install loopd@loopd`, then restart Claude Code | any Claude Code session |
| 2 | `/loopd:init ~/workspace/<group>/_loopd-<group>` | any Claude Code session |
| 3 | In the bundle, set `org` and `defaultRepo` in `instance.config.json`, and `reposRoot` (the folder your clones live in) in `instance.config.local.json` | your editor |
| 4 | `/loopd:init` again, from inside the bundle — it links your repos into `repos/` | a session started in the bundle |
| 5 | `/loopd:welcome check` — each `✓` is something that could have been wrong and isn't | the same session |

**Why the name `_loopd-<group>`?** The underscore keeps the bundle at the top of the group
folder, and the suffix tells one group's bundle from another's.

**Always start Claude from inside the bundle** (`cd` into it, then `claude`). loopd reads the
bundle's config, banner and projects from the folder the session starts in, not from what
your editor has open.

---

## 2. Your first project

1. **Pick something small and real** — a change you'd be happy to merge or to throw away.
2. **Describe it:** `/loopd:new-project <one sentence>`. loopd asks at most one question (build
   or research, and whether you'll add input files first), then writes a project with draft
   tasks and proposed success criteria you can edit in `project.md`.
3. **Read the drafts.** Each task is a markdown file under `projects/<slug>/tasks/`. The
   project manager fills in acceptance criteria and lists anything it needs from you as
   numbered `open_questions`.
4. **Answer the questions** — in chat with `/loopd:answer`, or in the task file by adding
   ` --- <your answer>` to the end of the question's line:

   ```text
   Q1: which region should we default to? --- eu-central-1
   ```

5. **Promote one task:** change its `status: draft` to `status: ready`.
6. **Start the loop:** `/loopd:dispatch`. Every ten minutes the project manager checks the
   bundle, sends ready tasks to engineer agents and tracks their pull requests.
7. **Walk away.** Agents work in the background. When something needs you, it appears in the
   session banner, in `/loopd:whats-up`, and on the board (`/pane`, or `/loopd:board`).
8. **Read the PR's criteria table, then merge.** Each criterion is a row marked ✓ or ✗. The
   table, not the green CI check, is what you're deciding on.

The next pass of the loop notices the merge, marks the task done and cleans up its worktree.
When every task is done, it suggests `/loopd:close-project <slug>`.

`/loopd:dispatch stop` ends the loop; `/loopd:dispatch once` runs a single pass.

---

## 3. The two gates

```text
build     /loopd:new-project  →  you promote draft → ready  →  /loopd:dispatch  →  you merge the PR
research  /loopd:new-project  →  you promote draft → ready  →  you do the work  →  you approve the deliverable
```

| | Gate 1 — promote | Gate 2 — accept |
|---|---|---|
| You | change a task from `draft` to `ready` | merge the PR (build), or approve the deliverable (research) |
| Until you do | nothing is built | nothing lands — no agent ever merges |
| What holds it up | the task still has open questions | a ✗ in the PR's criteria table |

A **research** project produces documents inside the bundle instead of code: no repo, no PR.
You do the work in your session and the loop keeps track of it.

Both gates stay yours unless you install the separate `loopd-yolo` plugin and opt a project
in. Uninstalling it makes every project gated again. See [autonomy.md](autonomy.md).

---

## 4. Which command, when

| You want to | Run |
|---|---|
| start something | `/loopd:new-project <description>` |
| know what's waiting on you | `/loopd:whats-up` |
| answer the project manager | `/loopd:answer` |
| run the loop, or stop it | `/loopd:dispatch` · `/loopd:dispatch stop` |
| see everything at a glance | `/pane`, or `/loopd:board` for the browser |
| finish a project | `/loopd:close-project <slug>` |
| check your setup | `/loopd:welcome check` |
| update loopd | `/loopd:update`, then `/reload-plugins` |

The rest — `fanout`, `handoff`, `prune-wt`, `init` — and every flag are in
[reference.md](reference.md#commands). You won't need them on day one.

**One loop per bundle checkout.** Two `/loopd:dispatch` loops on the same folder are refused.

---

## Joining someone else's bundle

You were given a bundle repo and someone else runs it.

1. **Install the plugin:** `/plugin marketplace add cbmono/loopd`, then
   `/plugin install loopd@loopd`, then restart Claude Code.
2. **Clone the bundle** next to the repos it works on:
   `git clone <bundle-remote> ~/workspace/<group>/_loopd-<group>`.
3. **Stamp your copy:** start Claude inside it and run `/loopd:init`. It fills in what your
   machine already knows and asks one question: whether it may write the permission rule
   that lets the loop start agents without stopping you each time. Answer **Y**.
4. **Say who you are:** put `{ "ownerGithubUser": "<login>" }` in
   `instance.config.local.json`, so your loop only picks up your own tasks.
5. **Check it:** `/loopd:welcome check`.

Every session in the bundle opens with a **banner**: which bundle it is, which model each
agent runs on, where the board is, and what's waiting for a person. Nothing on it needs an
answer right away.

**If a line shows ⚠**, copy the whole line to whoever runs the bundle. It's written for them.

Sharing one bundle between two or three people — `owner:` on projects, `defaultOwner`, the
`people` map — is in [sharing.md](sharing.md).

---

## Plugins that pair well

loopd depends on no other plugin. These are worth knowing about:

| Plugin | Adds | Verdict |
|---|---|---|
| `loopd-yolo` | lets a project delegate the two gates | optional; never on a bundle with production credentials unless you mean it |
| `security-guidance` | warnings on risky edits, a security review of each diff | install |
| `typescript-lsp` | real references, types and diagnostics for TS/JS | install on TS/JS repos |
| `frontend-design` | better UI generation | install on UI repos |
| `chrome-devtools-mcp` | inspect a live Chrome | install; foreground sessions only |
| `playwright` | browser automation for e2e suites | where the repo uses Playwright |
| `terraform` | HashiCorp's Terraform tools | where the repo owns Terraform |
| `context7` | up-to-date library docs | optional |
| `superpowers` | skill-first workflows | **don't install with loopd** — its start-up hook fights the agents' task instructions |

Install with `/plugin install <name>@claude-plugins-official`.

Running agents unattended in a container or VM:
[operations.md → Running the role agents in a sandbox](operations.md#running-the-role-agents-in-a-sandbox).
