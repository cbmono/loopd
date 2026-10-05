# Your first hour

For **someone joining a loopd bundle** — a teammate's, or your own first one. It
covers three things and then stops: getting installed, which skill to reach for, and the
two decisions that never leave you. Short enough to read before a kickoff.

Every section links to the page that owns the detail. Nothing here restates one.

Placeholders throughout: `<group>` is the group folder, `<login>` is your GitHub login,
`<bundle-remote>` is the bundle repo somebody shared with you.

> **Already running a pre-plugin install** — bare `/new-project`, `/close-project`, and
> `.claude/commands/` full of symlinks? Do [migrating.md](migrating.md) first. It is a
> different job from this one, and this page assumes it is done.

---

## 1. Install — about ten minutes

**Two halves, on two clocks.** The **plugin** carries every skill, the hooks and the role
agents, and is installed once per **machine**. The **bundle** is the instance — one small
git repo per group, holding the state of the work and never any application code — and is
stamped once per **instance**. A machine with only the plugin has commands and nothing to
read; a bundle with no stamp has the data and no way to drive it. Do the plugin first.

| # | Step | Where | Do this |
|---|---|---|---|
| 1 | Install the plugin | once per **machine**, in any Claude Code session | `/plugin marketplace add cbmono/loopd`, then `/plugin install loopd@loopd` |
| 2 | Get the bundle | once per **bundle** | **joining** one: `git clone <bundle-remote> ~/workspace/<group>/_loopd-<group>` · **starting** one: [README § Install](../README.md#install), steps 2-5 |
| 3 | Stamp it | **each** clone | `/loopd:init ~/workspace/<group>/_loopd-<group>` — seeds what is absent and links `repos/` |
| 4 | Say which login this clone is | **each** clone | `{ "ownerGithubUser": "<login>" }` in `instance.config.local.json` (gitignored, per machine) |
| 5 | Turn the nudges on — **joining only** | your clone | `touch ~/workspace/<group>/_loopd-<group>/AWAITING.md`. A clone is not a first stamp, so the stamp deliberately does not create it |
| 6 | Open a session | | `cd ~/workspace/<group>/_loopd-<group>` then `claude` |

**There is no "clone the template" step.** The machinery ships in the plugin, so step 1 is
the whole of what a machine needs; the bundle holds data and nothing else.

**Always launch Claude from inside the instance directory.** The bundle's role agents, its
`SessionStart` banner and its `CLAUDE.md` load from the working directory — not from what
your editor has open. Everything the plugin carries resolves anywhere.

Then run **`/loopd:welcome check`**. It reports the state that could be wrong — a
template you are behind, machinery this clone was never linked to, uncommitted or unknown
config keys, a tick lock, a stray background process — each line a fact with its evidence.
`fix` repairs only the tier that has one right answer and prints the rest.

**Two humans sharing one bundle** need three more values on top of the table — a `people`
map, `defaultOwner`, and each clone's own `ownerGithubUser`. That is
[sharing.md](sharing.md). `scripts/add-second-human.sh <instance>` prepares the shared,
tracked half (`people` and `defaultOwner`) — reporting only, until you pass `--apply` — and
prints the commands the second machine has to run itself, which it cannot run for you.

---

## 2. The skills — what to reach for

Every command is namespaced (`/loopd:…`); a bare name does not resolve. Run them
**inside the instance**, never from a product repo. **Twelve ship. These seven carry your
first week**; the rest wait until you meet the problem they solve.

| Skill | Reach for it when |
|---|---|
| `/loopd:welcome [check\|fix]` | the banner scrolled past, or something looks off. `check` reports, `fix` repairs the idempotent tier |
| `/loopd:new-project <description>` | you have work. It scaffolds phases and `draft` tasks and asks for what it cannot infer |
| `/loopd:answer` | the PM left you numbered `open_questions` and you would rather answer in chat than in the file |
| `/loopd:dispatch [gap]` | you promoted something. One serial tick — `/loopd:dispatch 10m` keeps ticking every ten minutes |
| `/loopd:work <task>` | you want to do this one yourself, in this session, instead of dispatching an agent |
| `/loopd:brief-me [project]` | you were away, or you are walking into a meeting |
| `/loopd:close-project <slug>` | its tasks are all `done` or `cancelled` |

The other five — `pr-review-request`, `capture`, `fanout`, `handoff`, `audit` — and the
flags `/loopd:new-project` accepts are in the
[README's table](../README.md#commands). None of them is needed on day one.

**One `/loopd:dispatch` per clone.** It is serial and completion-gated, and the lock
that enforces that is per clone: it refuses a second loop on **your** checkout. On a shared
bundle each human runs their own, and what keeps those two from dispatching the same task
is `owner`, not the lock ([sharing.md](sharing.md)).

Who actually does the work, and on which model:
[README § The team](../README.md#the-team).

---

## 3. The two gates — the decisions that stay yours

```text
build     /loopd:new-project  →  you promote draft → ready  →  /loopd:dispatch  →  you merge the PR
research  /loopd:new-project  →  you promote draft → ready  →  you do the work  →  you approve the deliverable
```

A `research` project has no `target_repo`, dispatches no agent and opens no pull request —
you execute it in-session and the loop tracks it
([README § Two kinds of project](../README.md#two-kinds-of-project)). Both kinds pass
through the same two gates.

| | **Gate 1 — promote** | **Gate 2 — accept** |
|---|---|---|
| What you do | set `status: draft` → `status: ready` | merge the PR (`build`), or approve the deliverable (`research`) |
| Where | `projects/<slug>/tasks/<id>.md` | the pull request · `projects/<slug>/deliverables/` |
| Until you do it | **nothing is dispatched.** The PM refines and critiques a draft, and never sets `ready` | nothing lands. **No agent ever merges** |
| What holds it up | the task still lists `open_questions` — answer them by appending ` --- <your answer>` to the question line | one `✗` in the PR's criteria table blocks it, however green CI is |

**Both gates hold until you deliberately delegate them**, and the delegation is one
deletable file — delete it and every project is gated again, with no other edit. See
[autonomy.md](autonomy.md); the two authorities themselves are in
[`plugin/seed/SCHEMA.md`](../plugin/seed/SCHEMA.md), which the stamp copies into your bundle root.

**`AWAITING.md` is where the gates queue up** — the instance's one status artifact, and
just the items a human decision unblocks, each marked with what it needs from you
([README § What needs you](../README.md#what-needs-you) has the markers). It is derived
and gitignored, so **never hand-edit it**: each tick rewrites it. Deleting it turns the
nudges off for good, and `touch AWAITING.md` turns them back on.

---

## Day one, in order

1. Install — the table in [§ 1](#1-install--about-ten-minutes), then `/loopd:welcome check`.
2. Look around: `projects/` is the work, `knowledge/` is what has been learned, `AWAITING.md` is what needs you ([README § Where the work lives](../README.md#where-the-work-lives)).
3. `/loopd:new-project <something small and real>` — one you would be happy to merge or to throw away.
4. Answer its questions, read the drafts it wrote, and promote **one** task to `ready`.
5. `/loopd:dispatch` — then leave it alone. **Steer, don't watch**: agents run in the background and bubble up results and questions, not every step.
6. Read the PR's criteria table before you merge. That table, not the green check, is what you are deciding on.

**And the one habit worth forming first:** when the PM asks you something, answer it in
the task document. The answer is folded in on the next tick and kept as a permanent
record — so the reasoning behind a task survives the session it was decided in.

---

## Plugins that pair well

**loopd bundles no third-party plugin, and cannot.** Claude Code has no plugin
dependency mechanism (`claude plugin install --help`, 2.1.263, takes one `<plugin>` and no
dependency option), and the core is domain-agnostic. So this is a list. Verdicts are the
owner's, 2026-09-06.

| Plugin | What it adds, and to whom | Verdict |
|---|---|---|
| `loopd-yolo` (our companion) | `AUTONOMY.md`: the `yolo` mode for a bundle whose loop you already trust | optional; never on a bundle with production credentials unless you mean it |
| `security-guidance` | pattern warnings on edits, an LLM diff review on stop, 25+ vulnerability classes | **install** — before Claude edits a repo |
| `typescript-lsp` | TypeScript/JavaScript language server: real references, types, diagnostics | **install** on TS/JS repos |
| `frontend-design` | production-grade UI generation that avoids generic AI aesthetics | **install** on UI repos |
| `chrome-devtools-mcp` | control and inspect a live Chrome: traces, network, console | **install**; foreground sessions only — a dispatched role agent has no browser |
| `playwright` | Microsoft's browser-automation MCP for e2e suites | recommended where the repo runs Playwright |
| `terraform` | HashiCorp's Terraform MCP | recommended where the repo owns Terraform |
| `context7` | up-to-date library docs over a hosted MCP | optional |
| `code-review` | multi-agent PR review plugin | not needed: `/code-review` ships in Claude Code and `qa-reviewer` already dispatches it on your own usage; only `ultra` is billed separately |
| `superpowers` | brainstorming, TDD, subagent-driven development, as skills that insist on being invoked first | **do not install with loopd** — its SessionStart hook demands a skill before any response and pushes brainstorming on every creative ask, which fights a dispatched agent's task contract; its worktree skill overlaps loopd's, and its planning/verification skills overlap ai-setup's `/plan` and `/verify` |

Install with `/plugin install <name>@claude-plugins-official`; one line per plugin, user scope, and it is available in every session on that machine.

