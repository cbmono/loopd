---
type: Reference
title: Delegated Authority (autonomy modes)
description: The optional modes that let the loop hold a gate the human otherwise holds — and the preconditions each one must satisfy.
timestamp: 2026-08-10T00:00:00Z
---

> **Generic companion file.** Ships with the `loopd-yolo` plugin, identical across
> every instance. Instance-specific values live in `instance.config.json` and the
> instance's `CLAUDE.md` — never hardcode them here.

# This file is the capability

`SCHEMA.md` gives every project an `autonomy` field but deliberately defines only
`gated`, where **both human gates hold absolutely**: the human promotes `draft → ready`,
and the human merges. Every other mode is defined *here*, which makes this file the
on/off switch for the whole capability:

- **This file found** → the modes below are available, and a project's `autonomy`
  field selects one.
- **This file not found** → there are no other modes. **Every project is `gated`
  regardless of what its `autonomy` field says.** The field is inert, not an error: a
  bundle copied from an instance that had this file keeps working, it just waits for the
  human at both gates.

**Two places count as "found", and `scripts/resolve-autonomy.sh` is the one thing that
looks.** The **bundle's own root** (`<bundle>/AUTONOMY.md`) wins outright — a v1-era
bundle keeps working byte for byte and no companion overrides it — and otherwise this
copy, shipped by the **`loopd-yolo` companion plugin** at `companion/AUTONOMY.md`
under its plugin root. Core itself ships no capability file at all.

Fail-closed is the whole point. A deployment that must not self-merge achieves that by
**not installing the companion**, not by auditing eight documents for a stray permission.

**Read this file only when a project's `autonomy` is something other than `gated`.**
Most ticks never need it.

# Mode: `yolo`

One mode, deliberately. `yolo` runs a project **all-out** — it delegates *both* gates
and browser writes.
There is no partial variant, and adding ask-first carve-outs
on top of it is a mistake we already made and reverted: a loop that self-promotes and
self-merges but stops to ask about a form submit is inconsistent without being safer.

What it delegates, and to what anchor:

| Gate | Under `gated` | Under `yolo` | Anchor that replaces the human |
|---|---|---|---|
| Promote `draft → ready` | Human only | The loop may promote | The draft is fully refined (`acceptance_criteria` filled) with an **empty** `open_questions` |
| Merge the PR | Human only | The loop may merge | Independent clearance + required checks green at the exact verified SHA (below) |
| Browser writes | Ask first | Permitted without asking | The task itself — a write nobody asked for is still out of scope |

The anchor is always a **machine** signal, never a self-report. `yolo` removes the
human, not the evidence.

**Dispatching the `qa-reviewer` fallback is not in this table, because no mode gates it.**
It used to be a fourth row (gated asked first on exit 5). It is now decided by
`scripts/review-next.sh` identically under `gated` and `yolo` — see "The QA fallback, in
every mode" below.

## Promotion under `yolo`

The loop may set `ready` on a **`kind: build`** draft that is fully refined
(`acceptance_criteria` filled) and whose `open_questions` is **empty**. Anything with an
open question stays `draft` and waits for the human — that is not negotiable, because an
unanswered question means the spec is incomplete, and no amount of autonomy substitutes
for the missing answer.

**`kind: research` tasks are never auto-promoted.** They are human-driven by definition
(`SCHEMA.md`), so `yolo` is near-inert on a research project — expected, not a bug.

## Merge under `yolo`

Merge only on **deterministic signals fetched immediately before merging** — never on a
reading of the PR body or comment prose. A PR carries text an attacker can write; it must
not be able to talk the loop into a merge. Confirm all four and **abort if any fails**:

1. **Every *required* check passes, and a review clears the head** — `scripts/required-checks.sh <pr> --head
   <verified-sha>` exits **0**. It now asks precondition 2 for clearance on every PR
   rather than deciding from a check's *name* whether a reviewer is involved, because a
   name table cannot enumerate every vendor: a check called "Codex Review", or one named
   for any hosted reviewer whose product name carries no word about reviewing, used to
   read as plain CI and settle on its green bucket. Only that clears this precondition; don't hand-roll the
   `gh` calls, the script exists because the failure modes are subtle enough to get
   wrong (a *failing* required check and *no protection at all* both make `gh pr checks
   --required` exit non-zero, and only one of them is safe to fall back from).

   It resolves the required set from **branch protection** first, and falls back to
   **`.github/required-checks.txt` on the PR's base branch** — one check name per line —
   where the host reports none. That fallback exists for hosts that can't enforce
   protection at all: on a free plan, a private repo answers **403** from both the
   branch-protection and the rulesets API. Either way an **empty** set does **not** pass
   (exit 3): never auto-merge a repo that requires nothing.

   Two properties to know before leaning on the declared list:

   - **Only `pass` clears** — missing, pending and *skipped* all refuse. So declare only
     checks that always run: a path-filtered job that skips itself would otherwise be a
     green light for something nobody ran.
   - **A PR that edits the list is never auto-merged** (exit 4). An open PR can't weaken
     its own gate — the list is read from the base branch — but merging it would weaken
     every later one. Surface it, exactly as no agent raises `autonomy` itself.
   - **So is a PR that edits the merge gate's own files** (exit 4, `GATE_FILES` in
     `required-checks.sh`: this file, the hook and the clearance scripts) — the gate
     must not clear the PR that rewrites it.
2. **The independent reviewer has cleared the current head** — *cleared* exactly as
   `SCHEMA.md` → "Independent verification gate" defines it (the `okf-verdict` trailer
   for the `qa-reviewer`; an identity-matched, non-dismissed, count-reconciled review for
   an external one), with **no reviewer-authored thread still unresolved**.
   `reviewThreads.isResolved` alone is **not** sufficient: a thread the PR
   author/executor resolved itself does not count as cleared unless the reviewer
   re-acknowledged it by re-reviewing the current head without re-raising.
   **The unresolved half of that is checked, not trusted:** `scripts/review-clearance.sh`
   exits **6** — never 0 — for a completed review at the head with a reviewer-authored
   thread still open, and names each one. The re-acknowledgement half stays a judgement
   nothing here can make, so it stays the reviewer's.

   **That a review happened at all is `scripts/review-clearance.sh <pr> --head
   <verified-sha>` exiting 0**, and nothing else clears it — in particular not the
   reviewer's status check, which is green whether it reviewed or declined. It asserts a
   review **artifact that evidences a completed review** — and it takes that evidence, and
   the pin to the commit, from the **API**: a review object whose `state` is `APPROVED`,
   `CHANGES_REQUESTED` or `COMMENTED` and whose `commit_id` is the head, a validated
   `okf-verdict` trailer, or the reviewer's own machine-emitted review marker in a comment
   naming the head. *Not* merely an artifact that fails to read as a refusal, which the
   reviewer's "currently processing" placeholder does on nearly every PR; and *not* a body
   that happens to mention the head SHA, which the refusal also does. Text matching there
   has exactly one job, spotting a refusal, where a false positive fails closed. It refuses
   on a **transient** refusal or a placeholder (exit 1, quoting it and the reopen time), on
   a **terminal** one — an account out of credits, unpaid or unauthenticated, which no
   waiting reopens (exit 5), on no reviewer
   signal (exit 3), on an artifact that evidences no review or is not of the current head
   (exit 4), and on an unreadable reviewer state (exit 2).
   **Exit 8 is the one refusal nothing reopens: NOBODY EVER ASKED.** Where auto reviews are
   disabled — this template's own repo — the reviewer posts *"Review skipped … invoke the
   `@coderabbitai review` command"* on every push, and reading that as exit 1 makes the loop
   wait for an event that has no cause (measured 2026-09-15: four PRs, three ticks, one
   comment would have got a review in 4 seconds). The remedy is a **request at the current
   head**, never a merge and never a `qa-reviewer` spend; a request costs no review round.
   Where several PRs answer 8 and the quota is one review per window, spend it on the PR
   whose criteria table carries no `✗` — only that one can become merge-eligible. Exit 0 is only the *first* half of this precondition: the
   clauses above still decide whether that review **cleared**.
   **It asks the merge question FIRST, and that one an auto-merge cannot argue with:**
   a PR the host reports `mergeable: CONFLICTING` / `mergeStateStatus: DIRTY` is **exit 7**
   and is never auto-merged — it is a rebase round, not a review problem. An **UNKNOWN**
   mergeability is **exit 2**, a hold, because the host computes it lazily and answers
   UNKNOWN for seconds after the base moves. Both are re-read every tick: mergeability
   changes when the default branch moves with no commit on the PR.
   **1 and 5 refuse identically here** — this precondition asks whether a review cleared,
   and neither did. The split decides what the loop does *next*, which is the section
   below, and never whether this gate passes.

   **Exit 4 will be the answer most of the time, and it is not exit 1.** Wherever the
   reviewer does not re-review every push — CodeRabbit's `auto_incremental_review:
   false`, which this template's own repo sets deliberately — it reads the first push,
   the agent then pushes fixes, and the review is of a commit that is not the head. That
   is a **stale** review, not a refusal: surface it as "reviewed at `<sha>`, head has
   moved", and ask for a review at the current head. Reporting it as "the reviewer
   declined" sends someone looking for a quota that was never exhausted.
3. **Every acceptance-criteria row in the PR body's table is `✓`.** A `✗` — the unchecked
   box — is a criterion nobody verified (`SCHEMA.md`), and green CI is not evidence for one
   no check covers. This is the condition that catches the class of bug deterministic checks
   cannot see.

   **And a `✓` is the WORKER's claim, so it is not enough on its own.** Where no external
   reviewer cleared the head, the `qa-reviewer` posts its own `PASS`/`FAIL` table,
   re-derived from the task and the diff. **External** means a `REVIEWERS` vendor login
   clearing by route A (a review object at the head) or route C (its own review marker
   naming the head) of `review-clearance.sh`; a trailer or a `--reviewer` account that is
   no vendor is internal, and needs the table. `scripts/pr-verdict-clearance.sh <pr> --repo <org>/<repo>`
   compares the two and **exit 0 is the only clearance**: exit 1 is a row the worker
   passed and the checker failed, and that is the human's — a delegated merge never
   adjudicates one, and an exit 1 refuses the merge even where an external reviewer
   cleared it — except after the last round, once a fix commit has landed ("Merge after
   the last round" below). On a solo bundle the checker shares the author's `gh` login, so exit 4 is
   the answer there and the merge stays the human's (`SCHEMA.md` clause 8) — unless the
   checker's comment carries the trailer of a QA dispatch the project-manager recorded at
   that head (`scripts/qa-dispatch.sh`), or an external reviewer cleared the head, which
   needs no checker table.

   **And the table has to BE THERE for that to mean anything**, which is a separate
   question with a separate reader. Two halves, stated together because neither is worth
   anything without the other, and **neither can talk the loop into a merge** — which is
   what the rule above forbids: both are one-way, able only to *refuse*. No wording anyone
   can put in a body makes this precondition pass that would not have passed without it.

   **That the shape is there at all is `scripts/pr-body-clearance.sh <pr> --head
   <verified-sha>` exiting 0**, and `scripts/required-checks.sh` asks it for every PR it
   is about to clear, exactly as it asks precondition 2. It reads the **actual body from
   the host** and requires a **TL;DR line** (the heading `## Description`, a
   leading `**TL;DR**`, or the bare token opening a line), a **`Verified:` line carrying
   at least one link**, **a well-formed criteria table** — a header row, a delimiter row
   with the same number of cells, at least one data row, and at least one `✓`/`✗` among
   them — **under a heading whose `N ✓ / M ✗` tally matches those rows** and, when `M >
   0`, carries a reason after it, with every bullet of a `## Notes` section — at whatever
   heading depth — **leading with bold**. All of
   it is read from a rendering with fenced code blocks removed so a body that merely
   *quotes* the convention's example does not clear on the example. It refuses at **exit
   1** naming every element that is missing, incomplete or contradicted by the table, and
   at **exit 2** when the body cannot be fetched or read — unreadable is never clearance.
   **What the `Verified:` line claims, and whether a `✗`'s reason is a good one, are not
   decided here** — the gate asks that the citation and the reason EXIST, which is
   checkable; whether they are true is the reviewer's and the owner's, which is not.
   It exists because the short-form rule's only reader used to be a test asserting the
   rule **is named in `CONVENTIONS.md`**, and five hours after that rule merged an agent
   that had it opened a 14,673-character description.

   **It also refuses on LENGTH, at exit 4** — over 2,500 characters, or more than 3
   `## Notes` bullets (`CONVENTIONS.md` → "Write less", the owner's decision 2026-09-06).
   A separate code from the structural refusal because the fix is separate: exit 1 says
   add the missing element, exit 4 says move the reasoning to the task doc. The
   14,673-character body that motivated the gate is refused there now.

   **Whether every row is `✓` stays this clause's own job**, not the predicate's — one
   question, one reader, so the repo never ends up with two answers to it. The predicate
   asks only whether the artifact the clause reads is present and well-formed.
4. **The head is still the verified SHA.**

Then merge that exact commit:
`gh pr merge --squash --match-head-commit <verified-sha> <pr>` — which **aborts** on head
drift. Re-checking here matters: comments and checks can change after verification
without the head moving.

**That exact shape is also the only one the harness permits, and it reads the
preconditions off disk rather than trusting the caller.** Each of `required-checks.sh`,
`review-clearance.sh`, `pr-body-clearance.sh` and `pr-verdict-clearance.sh` records its own
exit 0 against the PR and the head it read — `review-clearance.sh` with whether the clearing
reviewer was external, `pr-verdict-clearance.sh` its exit 1 too — and the PreToolUse hook
permits the merge only for the `project-manager` (`agent_type` exactly `loopd:project-manager`;
a PR URL operand names its own repo, and a `--repo` that disagrees refuses), only where this file defines the owning
project's mode as delegating the merge, and only at the SHA they name: all four, or the
first three where an external reviewer cleared the head, and never over a checker `FAIL`. A review receipt alone is
precondition 2's first half and never a merge permit. Anything missing — no companion, no
owning project, two projects in different modes, a record at an earlier head — refuses, and
the refusal names what is missing.

**Only after confirming the merge succeeded** (exit 0 / `gh pr view <pr> --json state` is
`MERGED`) set the task `done`. If it aborted, leave it `in-review` and re-verify the new
head next tick.

**Platform-enforced protection is strictly better than the declared list**, and switching
costs nothing here: configure branch protection (on GitHub, private repos need a paid
plan) requiring the same checks plus an approved review, and precondition 1 starts
resolving from it automatically — the declared file becomes dead weight, and the gate
starts applying to human merges and to anything else pushing at the branch, not just to
this loop. It is still an **additional** layer, not a replacement for the verified-SHA
precondition — always keep `--match-head-commit`.

### Merge after the last round

**No re-review after the last round.** Where `review-clearance.sh` refuses the head with 1, 3,
4, 5 or 8, `required-checks.sh` asks `scripts/review-next.sh --clear`, which clears the review
half only when `review-next.sh` already answers `merge-path` and one of these holds:

- **`last-round`** — CodeRabbit is past `coderabbitRounds` with no QA owed, or QA stopped (a
  pass, or `qaRounds` reached). The reviewed commit is `review-rounds.sh --for <r> --last`;
  for CodeRabbit it must also be a vendor review object's `commit_id`, so a round evidenced
  only by the edited summary comment (route C) never opens this. The host's
  `GET /repos/{o}/{r}/compare/{reviewed}...{head}` must say `ahead` with at least one changed
  line — an empty commit is no fix — and its per-file additions plus deletions must total at
  most **`reviewFixMaxLines`** (**300** when absent). A binary, a rename, a mode-only change, a submodule bump or 300+ files hold for
  the human instead of counting 0; so does a rebase that orphans the reviewed commit
  (`diverged`) and a merge from the base branch that busts the cap — the reason names which.
- **`qa-head`** — a QA pass at the head itself: the checker table is still required, and any
  checker FAIL line refuses.
- **`qa-zero`** — `qaRounds: 0` with a real CodeRabbit refusal before its last round and no QA
  verdict at the head: no review round runs.
- **`zero-zero`** — `coderabbitRounds: 0` and `qaRounds: 0`: no review round runs at all.

**A fix is required first.** Open CodeRabbit threads at the head (exit 6) and FAIL rows from
a QA round at the head answer `implementer-round`, never a merge. **Once a fix commit has
landed after the last round, they block nothing**: no review is at the new head, so clause 9
is not asked, and a `last-round` line ignores a `pr-verdict-clearance.sh` fail line recorded
before it — never one recorded after it at the same head.

**`qaRounds: 0` is an explicit opt-in to merging a PR nobody reviewed.** A refusal is read
from comment text, so a misread comment can open such a merge. The owner accepted both
(2026-10-24).

The receipt gets one `last-round`, `qa-head`, `qa-zero` or `zero-zero` line from `review-next.sh` at the
exact head. Then:

- `required-checks.sh` accepts it for its review half; it reads no project mode. A
  reviewer's check the **host** requires is never waived — the host refuses the merge
  without it — so that PR holds for the human with that reason.
- The hook's `merge-permit.sh` accepts the line in place of the review pass (and, except for
  `qa-head`, the checker table) **only for a `yolo` project**; a `gated` one is refused and the human merges.
- Every other precondition holds: required checks green at the head (a reviewer's check
  that is not required never blocks), `pr-body-clearance.sh` exit 0, every criteria row
  `✓`, not CONFLICTING, the head the verified SHA, the same squash merge pinned to it, and
  only the `project-manager` merges.

A head with no review **before** the last round still refuses (exit 4 is a review request).

## Preflight: is the merge authority even exercisable?

**Run this once per tick per `yolo` build project, and at `/new-project` when `yolo` is
chosen.** Three things make the merge **unsatisfiable by construction** — two
configurations and the harness itself — and discovering that mid-run wastes a whole session:

1. **Single identity.** GitHub will not record an `APPROVED` review on a PR authored by
   the same account, and every agent in this instance shares one `gh` login. So if the
   independent reviewer is the `qa-reviewer` fallback, no approval object can ever exist
   — its trailer-bearing **comment** review is the clearance signal (`SCHEMA.md`), and
   anything demanding an `APPROVED` state will block forever. Check with
   `gh api user --jq .login` against the PR author.
2. **No required checks.** Precondition 1 refuses an empty required-check set, so a repo
   with neither branch protection nor a declared list can never satisfy it. Check by
   running `scripts/required-checks.sh <pr>` against any open PR: **exit 3 is exactly
   this condition**, and it names the file it looked for.

3. **The destructive-action baseline itself.** `plugin/hooks/deny-destructive.sh` (rule
   `subagent_merge`) sits in front of the merge and refuses everything but the one shape
   below, decided from this file, the owning project's `autonomy`, the caller's role and a
   clearance record at the exact SHA. On 2026-09-14 a tick reached all four preconditions
   on two PRs and was refused here; a human merged both by hand. **Probe it with the REAL
   command and nothing merges** — the payload is a decision, not an invocation:

   ```sh
   jq -n --arg d "$PWD" --arg c "gh pr merge --squash --match-head-commit $SHA $PR" \
     '{cwd:$d, hook_event_name:"PreToolUse", tool_name:"Bash", agent_id:"probe",
       agent_type:"loopd:project-manager", tool_input:{command:$c}}' \
     | CLAUDE_PROJECT_DIR="$PWD" bash "$AB/../hooks/deny-destructive.sh" \
     | jq -e '.hookSpecificOutput.permissionDecision != "deny"'   # 0 = the merge would run
   ```

   A non-zero exit prints the hook's own reason, which names the precondition that is
   missing. `gh pr merge --help` is not a probe: the rule matches the invocation.

**When any of them holds, say so plainly and once** — in the project's `# Notes` and on the
board:

> `<project>`: merge authority delegated but not exercisable (<reason>). Every PR will be
> surfaced for you instead.

Then keep verifying and surfacing PRs as `gated` would. **Do not** silently retry every
tick, do not escalate, and never work around it by switching `gh` identities to
manufacture an approval — that defeats the two-party control this whole gate exists to
provide. The fix is the human's: configure an external reviewer (e.g. CodeRabbit); set up
branch protection, or commit a `.github/required-checks.txt` where the host can't enforce
one; or accept that this project's merges are manual.

## The QA fallback, in every mode

**What this decides is WHO reviews, never WHETHER anybody does.** A verdict is still
required and still has to be clean — see "What `yolo` never delegates", item 4.

`scripts/review-next.sh` decides it, and **it reads no mode**: `gated` and `yolo` get the
same answer. It answers `dispatch-qa` when CodeRabbit is **unavailable** — a real refusal
(`review-clearance.sh` exit 1 with `class: declined`: a rate limit, a used-up allowance;
or exit 5: out of credits, unpaid, unauthenticated) before its last round, or
`coderabbitRounds: 0` with `qaRounds` ≥ 1 — and the project-manager dispatches
`loopd:qa-reviewer` **in the same tick, with no ask and no waiting window**, then records
that it did. Under `gated` the human still merges.

**Not unavailable, in either mode, and never a QA round:** the "currently processing"
placeholder (exit 1, `class: placeholder`, on nearly every PR) and exit 3 hold; exit 8 is a
request at the head (above). A real refusal outranks a placeholder at the same head, in
whatever order the host streamed them.

**QA runs only while CodeRabbit is unavailable.** Once CodeRabbit has completed its
`coderabbitRounds` rounds, a later refusal dispatches nothing. QA round n+1 runs only when
round n was not a pass and a fix landed after it; QA stops at the first pass or at
`qaRounds` (`scripts/review-rounds.sh --for qa`, **1** when absent). A dispatch record at
the head with no verdict yet holds, so a second tick never dispatches a second QA there.

## Browser writes under `yolo`

Permitted without asking — submitting a form, changing a setting, clicking through a
flow — when they serve the task. Under `gated`, **ask first**. Read-only navigation and
screenshots never need permission in either mode.

Two limits are **not** browser-specific and hold under `yolo` too:

- **An agent doesn't redefine scope.** A write nobody asked for isn't licensed by
  autonomy — the same rule that stops an agent inventing code changes.
- **Irreversible actions well outside the task** — a payment, deleting an account,
  mailing a customer — are worth one confirmation on **cost** grounds, not permission
  grounds. In genuine doubt about blast radius, say what you're about to do and continue
  unless told otherwise.

Full browser rules (availability, tab groups, PII): `SCHEMA.md` → "Browser access".

# What `yolo` never delegates

These hold in every mode. They are the anchors an optimizer is most tempted to relax, so
treat any pressure to move one as a signal that something else is wrong:

1. **A `draft` with open `open_questions`** — waits for a human answer, always.
2. **A `blocked` task** — waits for a human decision, always.
3. **Closing a project** — the loop only ever *proposes* it (`SCHEMA.md` → "Project &
   objective completion"). Closeout deletes the folder; that stays a human call.
4. **The independent verification gate itself** — `yolo` replaces the *human merger*,
   never the *reviewer*. A verdict is still required, and still has to be clean — **until
   the last round**: once a fix commit has landed after it, that round's open threads and
   FAIL rows count as addressed and the fix merges unreviewed within `reviewFixMaxLines`,
   and `qaRounds: 0` opts into merging with no review at all ("Merge after the last
   round").
5. **Escalating autonomy.** The human sets `autonomy` at `/new-project`. No agent raises
   it, and no agent infers it from a project's urgency or its own convenience.

# Turning it off

**Uninstall `loopd-yolo`** (`/plugin` → Manage → uninstall): every project reverts
to `gated` with no other edits anywhere. If the file is instead a bundle's own real
`AUTONOMY.md` at its root — a v1-era instance — delete that file; the root copy is what
wins, so uninstalling the companion alone would not turn it off there.

To disable it for one project instead, set that project's `autonomy: gated`. Note the
companion is installed **per machine** while a root file is **per bundle**, so installing
it arms every bundle on that machine — the per-project setting is the opt-out.
