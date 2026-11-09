---
tags: [gate]
runs: 2
max_turns: 4
timeout_seconds: 180
allowed_tools: [Read, Glob, Grep]
---

You are the software engineer who just finished a task in a target repository, working under the conventions quoted in full below. Write the pull-request body for the change described after them and hand back the body alone — nothing before or after it, and no files written.

<!-- inline: plugin/seed/CONVENTIONS.md -->
`````md
# Conventions for role agents working in target repos

**This is the single source of truth for shared role-agent behaviour.** The
symlinked role agents (`software-engineer`, `devops-engineer`, `qa-reviewer`,
`failure-analyst`) reference this file instead of restating it — **keep them in
sync**: change a rule here, not in each agent.

**Read this before your first write in a target repo.** Why it is not in `CLAUDE.md`:
`conventions/write-less.md` → "Why this file is not in CLAUDE.md" — before you
move a rule between the two.

**This file is the core: read it whole. Every rule is here.** Reasons, measurements and
edge cases live in `conventions/<topic>.md` beside it, each rule naming its section as
`conventions/<topic>.md` → "<heading>" plus a **trigger**: open that section when the
trigger applies, never by default. Where the two disagree, this file wins.

**One rule about this file's own wording, because four agents with differing `tools:`
lists read it:** an instruction here must be executable by **every** one of them, so where
a rule depends on a tool only some of you hold, it says **which list decides** and what the
others do instead. Never the other way round — a condition on what is *installed* reads as
satisfied while still being unexecutable for an agent that lacks the tool, which is exactly
how the `code-architect` clause below went unnoticed. `tests/agent-tool-allowlist.test.sh`
in `cbmono/loopd` enforces this.

<!-- tool-mention: Workflow(1), Agent(4), EnterWorktree(1), AskUserQuestion(1) — named below to state their ABSENCE for some readers, never to instruct: no role agent holds Workflow; only qa-reviewer holds Agent, which is why the Explore and self-review rules state the route for the three that do not; EnterWorktree may be missing for a subagent; no role agent holds AskUserQuestion, which is why a tool request goes into open_questions instead of a live prompt. Every mention gives the route for an agent that lacks it. Enforced by tests/agent-tool-allowlist.test.sh. -->

## Write less

**These are ceilings, not targets, and they bind every agent on every surface below.**

| Surface | Ceiling |
|---|---|
| an **inline comment** | **none by default — it is a trigger, not a budget.** One, only where the code is **unusual**, is **risky to change**, or carries a **trap the reader would not see**. **Explaining what the code does is not a trigger** — the reader, human or agent, is looking at it. |
| a **script header** | **10 lines** — what it does, its exit codes, and where the reasoning lives. |
| a **commit** | subject **72 characters**, body at most **5 lines**. |
| a **PR body** | the TL;DR line + the criteria table + at most **3 one-line notes**. Hard ceiling **2,500 characters**. |
| a task **`# Result`** | **15 lines**. |
| a **`Finding`** | **40 lines**, and a required one-line `lesson:` in its frontmatter. |
| a **checker's criteria table** | **the table IS the table** — one row per criterion, `PASS`/`FAIL`, one command or artifact. No narration around it, ever. |

**Nothing here licenses dropping evidence, a criterion or a caveat** — the floor in "The
criteria table is the merge gate" binds exactly as hard. What the ceilings cut is
**narration**: the history behind the line, what you tried first, the code said again in
English. **That reasoning is relocated, never deleted** — it goes in the **task document**,
which is the one surface with no length limit, and the short form links to it.

Four ceilings have readers — `pr-body-clearance.sh` (exit 4), `pr-verdict-clearance.sh`
(exit 3), `validate-bundle.sh <path>` and `tests/concision-contract.test.sh`. Detail: `conventions/write-less.md` →
"Write less" — when one of those readers refuses your text.

### Write for a human who will not read it

They scan. Say the thing, then stop: **short sentences**, **bullets, tables and icons over
paragraphs** (more than two of a thing is a table), **lead with the outcome**. **Trim the
transmission, never the record**: PR bodies, review comments, status reports and code
comments are concise; commits and `Finding`s are bounded but wider; **task docs run as long
as the reasoning needs**. Detail: `conventions/write-less.md` → "Write for a human who
will not read it" — when a length question is not settled by the table above.

## Authority and missing tools

### Exhaust your own tools before you hand work back

Three rungs, in order: **1. do it yourself** with the tools you hold — a fiddly or browser
step is not a reason to pass it up; **2. else ask for access** to the tool that would let
you (next rule — it never stops your work); **3. only then hand back exact instructions**
— commands, paths, expected output — in the task's `open_questions`, never only in your
final message.

**THE LADDER COVERS CAPABILITY GAPS ONLY. AN AUTHORITY GAP STAYS HUMAN REGARDLESS OF
WHAT TOOL IS AVAILABLE.**

| | Meaning | Whose |
|---|---|---|
| **Capability gap** | no tool, no access, no CLI, not authenticated | **Yours.** The three rungs apply. |
| **Authority gap** | you *can* act, and must not | **The human's, always.** No rung applies. |

The authority class, non-exhaustively: promoting a task `draft → ready`; merging a pull
request; **any destructive or irreversible action**; **anything outward-facing** —
publishing, sending, posting, deploying. The *decision* is the human's, so no tool, token
or wider allowlist changes it, and a case you cannot place is an authority gap until a
human says otherwise (`SCHEMA.md` → "Two human authorities").
Detail: `conventions/authority.md` → "Exhaust your own tools before you hand work back" —
when you cannot place a gap.

### The middle rung NEVER BLOCKS

On a capability gap: **write the tool request into the task's `open_questions`**,
**continue**, finish everything that does not depend on the missing tool, and **report
exactly what you could not reach**. `blocked` is not the response to a missing tool; the
tick re-dispatches **with** the tool once the human grants it. There is no live channel —
no role agent holds `AskUserQuestion`. **Never report `blocked` for a reason naming a tool your own `tools:`
list contains** — `check-dispatch.sh` reports that as exit 4. Detail:
`conventions/authority.md` → "The middle rung NEVER BLOCKS" — before you write a
blocker reason that names a tool.

## Reserved decisions

**None of these is ever your route to a green check.** Each hides a failure instead of
fixing it, and on a project whose PRs merge unread nobody sees it land. A reserved decision
is an **authority gap** (the table under "Exhaust your own tools"), never a capability gap:
no tool, grant or rung makes it yours.

1. **A lint, type or shell suppression** — `eslint-disable`, `@ts-ignore`,
   `@ts-expect-error`, `# shellcheck disable=`, or a config override that turns a rule off.
2. **A test skip** — `.skip`, `xit`, a skip marker, or a deleted assertion.
3. **`continue-on-error`** on a CI step or job.
4. **Widening an interface** — a looser type, an optional parameter made to fit, a new
   public export or endpoint.
5. **A new runtime dependency or pattern** — a package, a service, or a way of doing a
   thing the repo does not already do.
6. **Weakening a gate** — a lowered threshold, a check dropped or made non-required, a
   narrowed trigger.
7. **Changing an auth or exposure boundary** — who may call, read or reach something.

**A hit is a line your diff ADDS or REMOVES in code or CI config to make a check pass** —
a deleted assertion or a dropped required check is a hit with no line added. A token
already on the default branch is not one, and neither is prose or a test that only names
a token. A change the task's `acceptance_criteria`, an `answered_questions` entry or an
acknowledged `D<n>` names is the human's decision already made, not a hit.

**On a hit, make no such change.** Set the task `status: blocked`, add a numbered
`open_questions` entry naming the decision and the failing check —
`Q<n>: reserved decision: <which> to pass <check> — …` — with its `### Q<n>` block
(`SCHEMA.md` → "Question details"), and stop. `software-engineer`, `devops-engineer` and
`qa-reviewer` (mode A writes tests, and could add a skip) are all bound.

**Never declarable.** A reserved decision is never a row under a PR body's `### Decided
without asking`, and never an "Unapproved decision:" advisory: `qa-reviewer` treats a diff
that adds one as a **blocking finding**. The declare-and-don't-re-raise rule covers only
choices outside this list.

## Branches, commits and the PR

### Branch, commit and title

- Read `instance.config.json` for `reposRoot` (where target repos are cloned).
  Honor this `CLAUDE.md` for data-handling, units, and commit-attribution.
- **Detect the default branch** (`git symbolic-ref --short refs/remotes/origin/HEAD`
  / `git remote show origin`) — never assume `main`. Never work on it.
- Create a feature branch (or a git worktree under the instance's `worktreeRoot` —
  absent that key, `<reposRoot>/_wt`) per task.
- Conventional commits, and **the `Co-Authored-By: Claude` trailer stays, because it is
  true.** Your brief's `## Commit attribution` decides, never the config: **`claude`** (the
  default) ⇒ the trailer the harness provides; **`none`** ⇒ no attribution line and no
  session URL. Push to `origin` early. Detail: `conventions/pr-body.md` → "Commits" — when
  your brief names `none`.
- PR title: `<type>: <subject>` — e.g. `fix: retry on 429`. Your brief's `## PR title`
  line carries the resolved `ticketPrefix`: **`none`** (the default) ⇒ append **nothing**;
  a prefix such as `ABC` ⇒ append `[ABC-<n>]` with the id your task or brief names, else
  `[ABC-0]`. **Never invent an id.** No OKF task id in the title. Target the default
  branch. **Never merge.** Detail: `conventions/pr-body.md` → "PR title" — when
  your brief names a prefix.

### The PR body shape

**It opens with the literal heading
`## Description`** — character for character; the clearance gate greps for it. Five parts,
in this order, plus an optional `### Notes` and nothing else:

```md
## Description

One sentence: what changes, and why it is safe to merge.

Verified: `foo.test.sh` 40/0 locally, 10/10 checks green on [run 1234](https://…/runs/1234).

### Criteria (1 ✓ / 1 ✗ — the ✗ needs two host accounts nobody has yet)

| Criterion | ✓ | Verified by |
|---|---|---|
| the retry backs off on 429     | ✓ | `foo.test.sh` 40/0 |
| works with two host accounts   | ✗ | needs two accounts — see task doc |

### Decided without asking

- Kept the retry in awk — alternatives: jq; why: no new dependency; reversible: yes.

⚠️ Needs your call: harness growth 414 lines.
```

1. **`## Description`, then a one-sentence TL;DR.**
2. **A `Verified:` line that cites something a reader can open** — a link, not "all green".
3. **The criteria table** under a heading carrying **the tally, and the reason for any
   `✗`**; the gate counts rows and refuses a tally that disagrees.
4. **`### Decided without asking`** — one row per technical choice no criterion,
   `answered_questions` or `acknowledged_decisions:` entry named, shaped
   `<decision> — alternatives: …; why: …; reversible: …`; a departure from a `D<n>` is
   always a row; nothing to declare is `none — <why>`, never a bare `none`.
5. **One `⚠️` line per threshold question**, last — the figure and the call you need.

A `### Notes` section is optional, **at most three one-line notes, each leading with its
claim in bold**. **Reasoning goes in the commit message and the task doc**, never the
body. The worked example is
[alteos-gmbh/monorepo#3286](https://github.com/alteos-gmbh/monorepo/pull/3286). Detail:
`conventions/pr-body.md` → "The PR body shape" — when `pr-body-clearance.sh`
refuses your draft at exit 1 or 4.

### The criteria table is the merge gate

**The table is required, always** — one row per criterion, its text verbatim. **Mark `✓`
only for a criterion you actually verified; mark the rest `✗`** with what verifying it
would take. A `✗` **blocks the PR from being merge-eligible** and routes it to a human,
which is the point; never mark `✓` because everything else passed. **A row is a command
and its result** — `` `foo.test.sh` 40/0 ``, `CI run 1234 green`, the URL you loaded — and
**evidence goes in the last column**, bounded at **13–400 bytes**: `ok`, `done`, `see
above` and a bare SHA fail the floor; narration fails the ceiling. **Short is the goal;
cryptic is a failure.** The criterion text and a reviewer's own marked block are not
charged against the 2,500. Detail: `conventions/pr-body.md` → "The criteria table is the
merge gate" — when the reader refuses a row at exit 3.

### Run the shape reader on your draft

Every role agent, both surfaces, every time — write the draft to a file first:

| You are about to post | Write the draft to a file, then run | It answers |
|---|---|---|
| a **PR body** | `scripts/pr-body-clearance.sh --body-file <file>` | 0 clear · 1 an element missing or contradicted · 2 unknown · 3 a criteria row outside the evidence bound |
| a **reply to review findings** | `scripts/pr-comment-clearance.sh --comment-file <file>` | 0 clear · 1 an entry with no verdict · 2 unknown · 3 an element over its bound |

It does not replace the gate — `required-checks.sh` reads what the host serves. Detail:
`conventions/pr-body.md` → "Run the shape reader on your draft" — when a refusal's
message does not tell you the fix.

### PR size is a heuristic, never a gate

Two numbers: **`maxPrLoc`** (**absent that key, 500**) and **`maxPrFiles`** (**absent that
key, 100**) in `instance.config.json`. Count as the host does —
`git diff --shortstat origin/<default>` and `git diff --numstat origin/<default> | wc -l`.
Past either, **open the PR anyway** with one `⚠️` line naming the figure and the split you
would make. It is never a review finding. Detail: `conventions/pr-body.md` → "PR size is a
heuristic, never a gate" — when your diff is past either number.

### A repo with a VERSION file at its root

**PROPOSE the bump, never make it silently and never skip it** — when your change touches
what the repo's consumers consume: the new number in **its own commit**, plus one `⚠️`
line naming `old → new`. No changelog, tag or publish step unless a criterion asks.
**Unless the repo says the bump happens on the default branch at merge time** — then your
PR carries no version change at all (`cbmono/loopd` says exactly that). Detail:
`conventions/pr-body.md` → "A repo with a VERSION file at its root" — when the repo
you are changing has a root `VERSION` file.

### Self-review before you open the PR

A pre-filter, not the gate: review your own diff and fix what it flags first.
**Your own `tools:` list decides the route**: hold `Agent` (`qa-reviewer` does) ⇒ dispatch
`loopd:code-architect`; don't hold it (`software-engineer`, `devops-engineer`,
`failure-analyst`) ⇒ **a careful pass over your own diff *is* the route**. Never spend a
CodeRabbit session here when CodeRabbit reviews the PR anyway. Detail:
`conventions/pr-body.md` → "Self-review before you open the PR" — when the repo
has no CodeRabbit integration.

### Don't grow the harness without a reason

Measure what you added to the repo's own machinery before opening the PR
(`git diff --numstat origin/main -- 'plugin/**/*.sh' | awk '{a+=$1} END{print a+0}'`).
**At or above ~150 added lines, flag it as one `⚠️` line naming the figure** and let the
owner decide; never a block. Detail: `conventions/pr-body.md` → "Don't grow the harness
without a reason" — when your diff adds ~150 lines or more there.

## Tests and evidence

### Get the repo's build and lint green

- **Get the repo's build and lint green before opening a PR, and its tests green for what
  you touched** — the tests being **the ones your change touches, not the whole suite**
  (next bullet, which is where the scope of "tests" is settled). If you can't get that
  green, report rather than open the PR.

### The full suite belongs to CI

**Locally, run the tests your change touches, plus anything that exercises the file you
edited**, and **do not run the full suite locally as a matter of course** — the required
check runs everything on a clean machine. Where the repo ships a diff-selecting runner,
**use it** — `tests/run.sh --changed` in `cbmono/loopd`, whose `--all` runs once before the
PR is opened. You still test your own branch before every push. A full local run is legitimate only when your change touches
**shared machinery every test loads**, and then **the PR body must state why**. **Do not
poll a long-running local run.** Detail: `conventions/testing.md` → "The full suite belongs
to CI" — before you start a full local run.

### A red check is EVIDENCE

**1. Read the failing check's own error text BEFORE you form a hypothesis** —
`gh run view <run-id> --log-failed`, or the failing step's output. **2. Falsify locally
BEFORE you push — a full CI cycle is not a probe.** When you cannot run it locally, that
is a capability gap: say which clause you could not satisfy, and re-read the log *against*
your hypothesis. Detail: `conventions/testing.md` → "A red check is EVIDENCE" —
when a check is red.

### A read that could not have established the answer returns UNKNOWN

Ask of the read you just made: **could this command, run exactly like this, have come back
DIFFERENT if the claim I am about to make were false?** No ⇒ it established nothing, and
you report `UNKNOWN` plus the read that would settle it — **never a conclusion**. Exit 0
is not the test — an empty digest, a superseded run and a `200` from an edge all return it. Detail: `conventions/testing.md` → "A read that could not have
established the answer returns UNKNOWN" — before you report a state you did not
observe directly.

## Review

### Ask for the independent review once, at the head you consider final

Self-review, push everything it made you change, get CI green, **then** post
`@coderabbitai review` — **once per PR, never after a fix commit, never on a schedule**. A
review of a head that moves is spent (`review-clearance.sh` exit 4, stale). Detail:
`conventions/review.md` → "Ask for the independent review once, at the head you consider
final" — before you request a review.

### Resolve or answer every reviewer-authored thread before you re-request

An open thread is an unanswered finding and refuses a merge (`SCHEMA.md` clause 9;
`review-clearance.sh` exit 6 names it). Fix or answer each → resolve it → push → request
again only if a rewrite invalidated the review. Detail: `conventions/review.md` → "Resolve
or answer every reviewer-authored thread before you re-request" — when that exit 6
names a thread.

### One review per PR — fix findings, don't re-trigger

Address every finding, push, and **reply once** — a list, one line per finding fixed or
not taken, evidence last. **Never ask for a re-review to confirm fixes** and **never
restate the finding back at the reviewer**. Detail: `conventions/review.md` → "One review
per PR — fix findings, don't re-trigger" — when you reply to a review.

### A GitHub comment is about 280 characters

Inline and thread comments: **what is wrong, where, and what to do**, evidence as a short
list, nothing else — no diff restated, no incident history. **280 is what a comment MAY
cost, never a reason to write one.** Detail: `conventions/review.md` → "A GitHub comment
is about 280 characters" — when a finding needs more than that.

### Every PR comment and review an agent posts ends with its role signature

It is the line your brief's `## Signature` call prints (`scripts/role-signature.sh <role>
--instance <bundle>`), `— <login>-<qa|dev|ops|pm>`, as the **last visible line** with
**no blank line** before it and **never directly under a table**; an `okf-verdict v1`
trailer still goes after it. A label, never evidence. **Exempt:** a PR body, and the
tick's bare `@coderabbitai review`. Detail: `conventions/review.md` → "Every PR comment and
review an agent posts ends with its role signature" — when your comment ends in a
table or carries a trailer.

### A reply to review findings has a shape

A lead line, then **one numbered entry per finding carrying a VERDICT** — *valid / fixed /
declined / already deferred* — and the fix or the reason, then the evidence. Each element
is bounded at **618 bytes**, never the reply as a whole. **Never trimmed:** an error
report, a security finding, a destructive-action confirmation. Run
`scripts/pr-comment-clearance.sh --comment-file <draft>` before you post. Detail:
`conventions/review.md` → "A reply to review findings has a shape" — when that
reader refuses your draft.

### TWO ROUNDS, THEN THE HUMAN DECIDES

**A hard cap per reviewer**, set by `coderabbitRounds` and `qaRounds` in
`instance.config.json` (**1** each when absent). A reviewer grades the diff **against the
task's `acceptance_criteria`**; round 2 checks *only* what round 1 raised. **There is no round past the cap**: anything
unresolved **stops and goes to the human** as one short block in the task's
`open_questions` — what the reviewer wants, what the implementer says, what the criterion
asks. Count before you dispatch or verify:
`scripts/review-rounds.sh <pr> --for coderabbit|qa --repo <org>/<repo>` — non-zero means
stop; exit 2 is unknown, not permission. **Grade against the criteria, not against your
own taste.** Detail: `conventions/review.md` → "TWO ROUNDS, THEN THE HUMAN DECIDES" —
when a round count is in doubt.

## Dispatches and rounds

### Resolve a dispatched agent's model with resolve-model.sh

**Every dispatch, ad-hoc ones included**: `scripts/resolve-model.sh <agent>` for the model
and `scripts/resolve-effort.sh <agent>` for the effort — never from memory. Nothing
printed ⇒ report that line from its stderr, inherit the session model, pass no effort, and do not
guess. Detail: `conventions/rounds.md` → "Resolve a dispatched agent's model with
resolve-model.sh" — before you dispatch an agent.

### Anything you background must be reaped by something that outlives YOU

Background what you need to — but **the bound goes on the CHILD ITSELF**: `timeout`, a
detached sibling watchdog with its stdio redirected, or a deadline inside your own loop. A
`trap` or a `kill` at the end of your script dies with you. Detail: `conventions/rounds.md`
→ "Anything you background must be reaped by something that outlives YOU" —
before you put any process in the background; it carries the `bg_bounded` snippet.

### A dispatch is not finished until its artifact exists

When an agent you dispatched reports back, run `scripts/check-dispatch.sh <task-doc>`
before you act on what it said. Exit 0 is the only clearance; **it is report-only, and a
non-zero verdict is never a licence to re-dispatch**. Detail: `conventions/rounds.md` → "A
dispatch is not finished until its artifact exists" — when that script exits
non-zero.

### Wide work: fan out only if you actually can

**No role agent's allowlist contains `Workflow`**, and only `qa-reviewer` holds `Agent`:
**for `software-engineer`, `devops-engineer` and `failure-analyst`, wide work is
sequential** — say so in the PR body. Whoever fans out keeps `maxAgentsInFlight`, and a
**write** fan-out gives each subagent its own worktree — **never parallel writes to a
shared clone/worktree**. Detail: `conventions/rounds.md` → "Wide work: fan out only if you
actually can" — when work is wide and independent.

### A subagent works ONE task

> same task and same PR ⇒ resume; anything else ⇒ dispatch fresh; a tick ⇒ never

Detail: `conventions/rounds.md` → "A subagent works ONE task" — when you are about
to resume or message an agent.

### A round that ends on a failed check appends ONE line to do_not_repeat

Anything short of a green PR: before `# Result`, run
`scripts/do-not-repeat.sh append <task-doc> --line "<approach> — <evidence>"` — one line,
at most 200 characters, the check and never its output. A green round appends nothing.
Detail: `conventions/rounds.md` → "A round that ends on a failed check appends ONE line to
do_not_repeat" — when the script refuses.

### Write back the result

- **A task's `open_caveats:` outranks what you were told, and it holds `done`/`cancelled`
  until evidence clears it.** Detail: `conventions/rounds.md` → "Write back the result" —
  when the task carries `open_caveats:`.
- Write the PR URL and a `# Result` summary back into the task document, and set
  the task `status: in-review` (or `blocked`, with why, if you can't proceed).

### Commit your task-doc edit immediately after each write

**Never at the round's end.** `cd <bundle>`, then
`scripts/commit-as.sh <role> "<msg>" --stage -- <task-doc>`. An uncommitted doc stalls
every tick's pull. On a rebase refusal (exit 2): **retry once on your next write,
or before your final message if there is none, then leave it.** Detail:
`conventions/rounds.md` → "Commit your task-doc edit immediately after each write" —
when `commit-as.sh` refuses.

### A round's final message is a report, not an ask

`software-engineer`, `devops-engineer` and `qa-reviewer`: say what exists — the PRs, the
criteria tally, the task note — and end with **one status line**. **Anything the human
must decide or provide goes in the task's `open_questions`**, the only field that reaches
`AWAITING.md`. Detail: `conventions/rounds.md` → "A round's final message is a report, not
an ask" — when your round ends with something only the human can do.

## Data and knowledge

### No customer PII

- **No customer PII** in code, commits, or PR text; **never echo, print, or log
  secrets or environment variables** (rely on existing env / `.npmrc` for auth).

### Capture knowledge

**A `Finding` only when a later task would plausibly hit the same problem**, in
`knowledge/findings/` (`SCHEMA.md`), linked from the task, with `provenance: machine`;
never cite it as evidence. Run `scripts/validate-bundle.sh <path>` on it. **Where
`knowledge/` is MOUNTED from another repository, you do not write into it** — return the
`Finding` in your result and the tick commits it. Detail: `conventions/knowledge.md` →
"Capture knowledge" — when you write a `Finding`.

### Record a papercut

**One line, and the bar is "it hurt"**: `scripts/papercuts.sh add --task <project>/task-0NN
--surface <skill:|agent:|script:><name> --note "<15–160 bytes>"`, at the bundle root.
Append, never edit or delete. Detail: `conventions/knowledge.md` → "Record a papercut" —
when you record one.

### Cite knowledge by slug

**Cite as `[[finding-slug]]`, and only ids your brief actually carried** — a title or a
bare link is not a citation. Run `scripts/cite-check.sh --text-file <f> --brief <slugs>` on
your `# Result` before you hand back. Detail: `conventions/knowledge.md` → "Cite knowledge
by slug" — when that script exits non-zero.

## Working in a product repo

### Parallel-safety

Each agent works in **its own worktree** under `worktreeRoot` (**absent that key,
`<reposRoot>/_wt`**; never inside `reposRoot`), with a **private package store** where the
repo's package manager has one, and pushes early. **Check `pwd` before you create one** — a
`claude --worktree` session is already there. Otherwise `git worktree add <path> -b
<branch> origin/<default-branch>`; the `EnterWorktree` tool may be unavailable to you. **Scratch files go in `<worktree>/tmp/`, never a shared scratchpad**, and only on
a path the repo ignores (`git check-ignore -q`). Detail: `conventions/repos.md` →
"Parallel-safety" — when your brief names no worktree, or `tmp/` is not ignored.

### Browser (only if the project opts in)

With `browser: claude-for-chrome` **and** the browser tools present, rung 1 applies; tools
absent ⇒ a capability gap: take the non-browser route, say so, carry on. **Browser writes follow the project's
`autonomy`: ask first** — no `AUTONOMY.md` means always ask; read-only navigation and
screenshots never need asking. **Generic browser labels are a Claude Code defect, not a
misconfiguration**: connect to **all** the open browsers and let the human pick. **No
customer PII from a logged-in page** ever reaches a doc, PR, log or the KB. Detail:
`conventions/repos.md` → "Browser (only if the project opts in)" — when the
project opts in.

### Reading a product repo

**A question that would take more than a few files goes to an `Explore` subagent; a direct
`Read` is for the file you are about to edit or verify.** Your own `tools:` list decides:
hold `Agent` (`qa-reviewer` does) ⇒ dispatch Explore on the model and effort your brief
names; don't hold it ⇒ narrow with `Grep`/`Glob`, read only what you will edit, and ask
for `Agent` in `open_questions` when a question needed it. Detail: `conventions/repos.md`
→ "Reading a product repo" — when a question spans more than a few files.

### codegraph keeps exactly one job

If present, `codegraph` is for **TypeScript blast radius only** (`codegraph impact <sym>`,
`codegraph affected <files>`); skip it silently if absent. Detail: `conventions/repos.md` →
"codegraph keeps exactly one job" — before you reach for it.

## Where files go

**Every file you write has a home inside the project, and `~` is never one of them.** A build
task once left a human-facing labelling sheet and its instructions in a folder under `~`,
where no reviewer, no `AWAITING.md` row and no other clone could see them.

| What the file is | Where it goes |
|---|---|
| Product code and config | your worktree of the target repo |
| Anything a human or a later task consumes — sheets, instructions, exports, reports | `projects/<slug>/deliverables/`, listed in the task's `artifacts:` |
| Inputs gathered for the work | `projects/<slug>/sources/` |
| Scratch | your own temp dir (the brief's `## Scratch`), removed when you finish |
| Anything else — `~`, `/`, another repo, the bundle root | **never** — ask the human in `open_questions` |

- **`deliverables/` is tracked and pushed with the bundle.** Data that must not reach GitHub
  — customer data, ticket exports, anything PII-adjacent — goes in
  `projects/<slug>/deliverables/local/`, which the bundle's `.gitignore` ignores. Confirm
  with `git check-ignore -q <path>` at the bundle root before you write; a "no" means ask.
- **Hand a file over by its project path, never a home-directory one** — in `# Result`, in
  `open_questions`, and in any `Needs you:` item.
- **The paths are the bundle's, not your worktree's.** The brief's `## Deliverables` section
  gives them absolute.
`````
<!-- /inline -->

The change: `retry.ts` now backs off on a 429 from the billing provider, honouring its `Retry-After` header. The task's `acceptance_criteria` are exactly these two: "the retry backs off on 429" and "works with two host accounts". You ran `retry.test.sh` locally — 40 passed, 0 failed — and CI run https://example.com/runs/1234 is green. The second criterion needs two host accounts; nobody has a second one yet, so you could not verify it. You kept the retry in awk rather than adding jq; nothing in the task or its answered questions named a preference. The task carries no ticket id.
