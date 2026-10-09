# Autonomy and the merge gate

By default loopd keeps two gates for the human: **promote** a `draft` to `ready`,
and **merge** the PR (build) or **approve** the deliverable (research). Delegating
either one is optional, and off unless you install it.

**Normative source:** [`plugin-yolo/companion/AUTONOMY.md`](../plugin-yolo/companion/AUTONOMY.md)
defines the modes; [`plugin/seed/SCHEMA.md`](../plugin/seed/SCHEMA.md) → "Independent verification gate"
defines the clearance predicate. This page is orientation — don't implement from it.

---

## The on/off switch is one plugin

**Core ships no capability file at all.** `AUTONOMY.md` is what the **`loopd-yolo`
companion plugin** carries, and core finds it by presence:

```
/plugin install loopd-yolo@loopd     # on
/plugin  ->  Manage  ->  uninstall           # off
```

| State | What every project does |
|---|---|
| `AUTONOMY.md` **found** | a project's `autonomy:` field is honoured |
| `AUTONOMY.md` **not found** | every project is `gated`, whatever its `autonomy:` says |

**Uninstalling `loopd-yolo` disables delegated autonomy with no other edits** on a
bundle that carries no `AUTONOMY.md` of its own — that is the point of the design, and
for such a bundle it is the whole of turning it off. A bundle with its own root
`AUTONOMY.md` keeps delegating regardless (root wins, below); delete that file to turn
it off there. **Disabling it in
`/plugin` is not**: `resolve-autonomy.sh` reads `installed_plugins.json`, what is
installed, so a disabled companion still delegates. `commit-as.sh` gates
its promotion guard on the same lookup, fail-closed. Full reasoning, including the one
hazard the pattern does not cover:
[conventions.md invariant 4](conventions.md#4-a-capability-some-deployments-must-not-have-should-be-one-deletable-file).

`scripts/resolve-autonomy.sh` is the one reader, and it looks in exactly two places:

| Order | Where | Why |
|---|---|---|
| 1 | `<bundle>/AUTONOMY.md` | **Root wins outright.** A v1-era bundle carrying its own real file keeps working byte for byte, with or without a companion, and no companion can override what it says. |
| 2 | `<companion plugin root>/companion/AUTONOMY.md` | The companion, for a plugin installed from **core's own marketplace**. Read out of `installed_plugins.json` — never the plugin cache tree, which keeps every version ever fetched and would answer "installed" long after an uninstall. |

Exit 1 — neither — is `gated`, and so is every unknown: no registry, an unreadable one, a
companion root gone from disk. The full contract (how a companion registers, and the rule
that it may ADD behaviour but never remove a core gate) is in
[`plugin/README.md`](../plugin/README.md) → "Companion plugins".

> **The hazard, in one line.** The capability is now **per machine**, not per bundle: a
> plugin is installed once per user, so installing `loopd-yolo` arms every bundle on
> that machine at once. The per-bundle opt-out is unchanged and still the human's — set
> that project's `autonomy: gated` — and a bundle that must never delegate is best kept on
> a machine without the companion. `/loopd:init` no longer has anything to re-link
> here, which retires the older hazard in this slot: a per-instance `rm` that came back on
> the next stamp.

## Modes

| Mode | Promotion | Merge | Browser writes |
|---|---|---|---|
| `gated` (default, and the only mode when `AUTONOMY.md` is absent) | you | you | ask first |
| `yolo` | auto-promotes fully-refined build drafts with no open questions; research stays human-driven | merges on an independent clearance + fully green CI, at the exact verified commit | permitted |

There is **no partial variant, on purpose.** `yolo` is all-out. Don't reintroduce an
ask-first carve-out on top of it — carving out the browser while the loop self-merges is
inconsistent.

Pair it with `/audit`, the slow counter-metric that watches an autonomous loop for drift.

**Preflight.** With a single `gh` identity and no external reviewer, or with no required
status checks, the merge authority cannot be exercised at all. The loop says so once and
keeps surfacing PRs for you. **The deny baseline is trap three**: `deny-destructive.sh`'s
`subagent_merge` rule permits only `gh pr merge --squash --match-head-commit <sha>`, only
for the `project-manager`, only where the owning project's mode delegates the merge, and
only at the SHA every clearance script recorded — everything else refuses. The preflight
probes it by feeding the hook the real command in a PreToolUse payload, which decides
without merging anything.

## Did the dispatch produce its PR?

Everything below is about a pull request. This is the check that one exists.
`scripts/check-dispatch.sh <task-doc>`, run whenever a dispatched agent reports — from a
tick or from an ad-hoc dispatch — reads three things and judges nothing else: did
`status:` move off `ready`/`in-progress`, does `pr:` name a URL, does the host resolve
that PR. It is **report-only** — it never re-dispatches, never edits the task, and asks
the host only to read.

| Exit | Means |
|---|---|
| 0 | the dispatch produced what it promised — **or stopped honestly** (`blocked`/`cancelled`, so nothing was due). Read the stated reason; exit 0 does not mean "there is a PR" |
| 1 | **parked** — still `draft`/`ready`/`in-progress` with no PR. The signature it exists for, decided from the document alone with no network |
| 2 | cannot answer — usage, unreadable frontmatter, a research task (no PR by design; read its `artifacts:`), `gh` missing. Unknown is never reported as fine |
| 3 | `pr:` names a pull request the host does not resolve, or is not a URL at all |
| 4 | the record contradicts itself — `in-review`/`done` with an empty `pr:`, or a PR that resolves while `status:` never moved |

Ask it about a task you **dispatched**: one nobody has dispatched reads as exit 1 too,
correctly and uselessly. The measurement behind it is in
[`plugin/seed/CONVENTIONS.md`](../plugin/seed/CONVENTIONS.md) → "A dispatch is not finished until
its artifact exists".

## Required checks — exit 0 is the only clearance

The merge gate's first precondition is `scripts/required-checks.sh <pr>`.

| Source, in order | When it answers |
|---|---|
| **Branch protection** (platform) | whenever the API returns JSON — an empty array legitimately falls through |
| **`.github/required-checks.txt`** on the PR's base branch | only when the platform says "no required checks" |
| *anything else* | **exit 2** — refuse |

| Outcome | Result |
|---|---|
| every declared check reports `pass` | exit 0 — the only clearance |
| a declared name no check reports | drift, not absence — refuse |
| missing, pending or **skipped** | refuse |
| the PR itself edits the list | a human decision — never auto-merged |
| a required name that is a **reviewer's own check** | not settled by its bucket — handed to `review-clearance.sh` (below) |

Declare only checks that **always run**. Configuring real branch protection later needs
no change: the script prefers it automatically, and the gate then binds human merges too.

Full reasoning — why the probe is classified on its payload and never its exit code, and
why stdout and stderr must be captured separately:
[conventions.md invariant 6](conventions.md#6-the-delegated-merge-gate-resolves-its-required-checks-in-required-checkssh-and-exit-0-is-the-only-clearance).

## The verification gate

Before any PR merges it is checked by an **independent** reviewer — fresh context, judged
on real signals (acceptance criteria met, CI actually green), never the implementing
agent's self-report. Role agents embed the task's `acceptance_criteria` in the PR body so
the reviewer evaluates against them. The reviewer is an external one (e.g. CodeRabbit)
when the repo configures it, otherwise the `qa-reviewer` agent is the fallback. Before
*that*, the implementing agent **self-reviews its own diff** and fixes findings
(`code-architect` / a careful pass) — a pre-filter that shifts cheap issues left, **not**
a replacement for the independent gate.

**A verdict is structured, and clearance is a nine-clause predicate.** The `qa-reviewer`
ends its review with a machine-readable `okf-verdict` trailer; the loop reads the verdict
**only** from that trailer and criteria coverage only from the checklist's checkbox state,
never from prose. **The full predicate — the normative list every consumer must check — is
in [`SCHEMA.md`](../plugin/seed/SCHEMA.md) → "Independent verification gate".** Don't
implement from the summary below; it names three *failure classes* to convey the shape,
not the complete set of requirements.

| Failure class | What it looks like | Why it is a refusal |
|---|---|---|
| **An unfinished verdict** | trailer missing, partial, `inconclusive`, carrying `caveats`, or omitting a mandatory lens | an approval that admits its own analysis is unfinished is not an approval |
| **An unverified criterion** | any `acceptance_criteria` row left `✗` in the PR body's table | green CI is not evidence for a criterion no check covers |
| **A refusal dressed as a pass** | the reviewer declaring it didn't review (rate-limited, quota exhausted, skipped) while a **green check** publishes alongside | the most convincing false pass in the system |

The predicate also requires a current `head_sha`, the right reviewer identity, no
unresolved reviewer thread, and — for an external reviewer — a reconciled comment count.
Each failure class above has cleared a real bug in a real run; this is contract, not
etiquette.

**The third class is the one you cannot see, so it is a script.** `scripts/review-clearance.sh
<pr> --head <sha>` answers "did a review happen at this head" from the reviewer's
**artifacts** — a submitted review object, a body carrying the reviewer's own evidence of
having looked, or a parseable `okf-verdict` trailer — and never from a status check, which
is green whether the reviewer read the diff or hit its quota. Exit 0 is the only
clearance; 1 is a **transient** refusal or a not-yet-reviewed placeholder (quoted, with the
reopen time), 5 is a **terminal** one that no waiting reopens (out of credits, unpaid, an
auth failure), 3 is no reviewer signal at all, 4 is an artifact that evidences no completed
review or does not name the current head, **6 is a completed review at the current head
that clause 9 refuses — a reviewer-authored thread is still unresolved, and the refusal
names every open thread**, **8 is a skip notice — auto reviews are off on this repository,
so nobody ever asked and nothing will, and the remedy is one `@coderabbitai review` comment
at the current head** — and 2 is a reviewer state it could not read — unverified, never
a pass. It answers *whether* a review happened and, on 6, whether the reviewer's own
threads were answered; the other clauses above still decide whether that review **cleared**.

**And its FIRST question is not about the review at all: can this PR merge?** It asks the
host for `mergeable` / `mergeStateStatus` before it reads one artifact, because no review
makes a conflicting PR mergeable. CONFLICTING or DIRTY is **exit 7** — a rebase round, never
a merge row and never a review request. **UNKNOWN is exit 2, a hold**: the host computes
that value lazily and answers UNKNOWN for seconds after the base moves, which is exactly
the window that produced the failure this exists for. On 2026-09-13 three pull requests
were presented as merge rows — review at head, CI green — while GitHub reported all three
CONFLICTING/DIRTY, because four sibling merges had moved the default branch underneath them
with no commit on any of the three. The value is re-read **every** tick for that reason;
last tick's answer is not this tick's. The full table:

| Exit | Means | Next |
|---|---|---|
| **0** | a review artifact evidences a completed review of this head | the only clearance |
| **1** | transient refusal — rate limit, quota, placeholder | wait; it reopens by itself |
| **2** | unknown state, including an UNKNOWN mergeability | hold, re-ask next tick |
| **3** | no reviewer signal on this PR | hold |
| **4** | an artifact that is stale or evidences nothing | ask for a review at this head |
| **5** | terminal refusal — credits, billing, auth | a human fixes the reviewer |
| **6** | a review at this head, refused by clause 9 (open threads) | answer the threads; do **not** re-request |
| **7** | the PR CONFLICTS with its base | `rebase-pr.sh` first; do **not** re-request a review |
| **8** | skipped — auto reviews are off here, so NOBODY EVER ASKED | ask once at this head (`@coderabbitai review`); it never reopens by itself |

**A 7 is tried by a script before it costs an agent.**
`rebase-pr.sh <pr> --repo <org>/<repo> --dir <clone>` rebases in a throwaway worktree and
resolves **only** the known merge-magnet shapes — an `EXPECTED_ASSERTIONS=N` counter (the
three-way sum of both sides' deltas, which is neither side's number), a ratchet row both
sides lowered (recomputed from the merged file), a comment history (both kept) — asserts
the result parses and kept exactly one assignment, then pushes with an explicit
`--force-with-lease=<ref>:<the host's own headRefOid>` and lets CI verify. **Exit 3 — a
conflict it could not classify, with the file named — is the only exit that earns an agent
round**, and it is the only one a stall round is recorded for: a rebase the script resolved
cost nobody anything, so counting it would reach the cap on two clean rebases. Everything
non-zero leaves the branch and the remote exactly as they were.

**Where the answer is kept so the offline renderers agree with the host.**
`review-clearance.sh --record <task-doc>` writes the read it just made to the task's
`pr_mergeable:`. `write-snapshot.sh` is deterministic and no-network by contract, so
without that record the board and `AWAITING.md` minted the 🔀 **merge** verb from
`status: in-review` plus a PR link and nothing else. The verb now requires `MERGEABLE`;
**absent is `UNKNOWN`, which is not mergeable**, and a `CONFLICTING` in-review task renders
as in flight — a rebase round, not a queue position. It is not a cache consulted instead of
asking: every tick overwrites it, which is what "re-read every tick" means for a renderer
that cannot ask.

**4 and 6 send you in opposite directions, which is why they are two codes.** Exit 4 means
**ask for a review** — the one you have is stale or evidences nothing. Exit 6 means
**do not**: a review completed at this exact head, and what is outstanding is your reply to
it. Answer or fix each named thread, resolve it, and push. Requesting another review on a
6 buys a session to be told what the threads already say — and clause 9 was the one clause
in the predicate with no reader at all until this, which is how the 2026-09-05 audit found
**four of seven** PRs failing on clauses 3 and 9 with a reviewer that had answered. **1 and 5 refuse identically at this gate**
and differ only in what the loop does next: 1 is waited out, 5 is a spend decision
`AUTONOMY.md` routes to the human under `gated`.

**Positive evidence is required, because "not a refusal" is not a review.** The reviewer
posts a placeholder on nearly every PR the moment it opens — *"Currently processing new
changes in this PR…"*, quoting the head it is about to read — and a check that clears
anything it cannot classify as a refusal clears that, on every PR, before anybody has
looked. So an artifact has to carry evidence a review **completed**; the default is deny.
The same rule applies to the fallback reviewer's `okf-verdict` trailer, which is **parsed**
(marker line, closing `-->`, `verdict` / `reviewer` / a `head_sha` equal to the head being
cleared) and honoured only for the account named with `--reviewer`. As a substring it was a
one-line bypass that outranked the vendor's own refusal sentinel — and the string ships in
this repository's diffs, which reviewers quote.

**Do not detect the refusal by the commit range.** The refusal comment quotes the same
`between <base> and <head>` line a real review quotes, and on the PR this was found on
that head matched the PR head exactly — so the range says "reviewed" for both. Only the
language separates them, which is why the refusal table is matched first and the head
second. And a skipped PR is **not** re-reviewed on its own: after the quota resets
someone has to ask for a first review, which is not the discouraged "re-review of
addressed findings", because no review ever happened.

**Expect exit 4 to be the common answer, and read it as what it is.** Scored across all
37 pull requests on this repository: 18 carry a CodeRabbit review object and exactly
**one** of them was made at that PR's final head. The reviewer reads the first push, the
agent then pushes fixes, and `.coderabbit.yaml` here sets `auto_incremental_review:
false` on purpose (the "one review per PR" cost rule), so nothing re-reads them. Those
reviews are **stale, not absent** — clause 3 of the predicate — and the operational
consequence is real: wiring this into a delegated merge gate means most PRs need a review
requested at the **final** head before they can clear. That is the correct answer rather
than a threshold to tune; the alternative is merging on a review of a commit that is not
what would merge. **Do not "fix" it by matching more loosely.** A CodeRabbit review
comment routinely carries a `Review skipped — Auto incremental reviews are disabled`
notice *about a later commit*, on 10 of those PRs; the script keys the refusal on the
reviewer's machine-readable rate-limit sentinel and on prose only where nothing in the
body evidences a review, so those come back as **4 (stale)** rather than 1 (declined) —
a different refusal, never a pass.

**Three more ways it fails closed, each of which used to be a way through.** A required
check whose name reads as a **code reviewer's** while no reviewer in the table owns it
(`Cursor Bugbot`, `Copilot code review`, `Devin Review`) is not CI — it is unknown, and
`required-checks.sh` exits 2 rather than settling it on its green bucket. Each
reviewer-owned required name is cleared **against the reviewer that owns it**
(`--for-check`), so on a repo with two reviewers one vendor's review cannot clear the
other vendor's refusing check. And `required-checks.sh` makes the sibling **prove it
runs** (`review-clearance.sh --self-test`) before believing any answer from it: `[ -x ]`
tests a mode bit, and a dead shebang, a syntax error, a zero-byte file or a copy
truncated mid-install all carry the bit while failing every call — which would read as
"no required check is a reviewer's" and clear an unreviewed PR. The gate would not fail;
it would silently not be there.

### Under quota starvation, the order is fixed — and the override is the last step, not the first

The gate stays correct when the reviewer runs out: exit 0 is still the only clearance, so
a starved reviewer stalls the pipeline rather than opening it. What follows is what to do
with the stall, **in this order**, and none of the earlier steps may be skipped because a
later one is quicker:

| # | Step | When it applies | What it costs |
|---|---|---|---|
| 1 | **Wait for the window.** | `review-clearance.sh` exit **1** — a *transient* refusal, which quotes the reopen time the reviewer published | minutes to an hour, and nothing else. Measured 2026-08-31 on #85–#88: the reviewer came back within the hour and reviewed all four properly |
| 2 | **A second human on the bundle reviews it.** | the wait is not acceptable, or the refusal is exit **5** — *terminal*, so no waiting reopens it | one human's attention. The `people` map in `instance.config.json` is where a bundle's second human is named; `scripts/add-second-human.sh` prepares the shared half |
| 3 | **The owner overrides, recorded on the PR.** | steps 1 and 2 are both unavailable | the review. This is the step that costs something irreversible, which is why it is last |

**Step 2 has a precondition that is easy to get wrong and fails silently.** Clause 8 is
implemented as a string compare of each artifact's `user.login` against the PR author's,
and it reads none of `people` / `defaultOwner` / `ownerGithubUser` — so a second human is
a real second reviewer principal **only while their clone is `gh`-authenticated as their
own account**. One shared login collapses the gate back to the solo case with nothing
saying so.

**The override is a DECISION, not a mode.** It is the human choosing, once, on one pull
request, to merge without independent clearance — so it is recorded **on that PR**, in the
comment template
[operations.md](operations.md#merging-on-the-override-the-reason-is-read-off-the-pr) gives
the merger. It is emphatically not a setting: there is no `autonomy` value for it, no
config key turns it on, `review-clearance.sh` never returns 0 because of it, and an
override on one PR grants nothing to the next.

**How many have merged this way is a query, not a sentence in this file.** A running total
typed into prose has no reader: the number that stood here was stale by eight within 83
minutes of merging. Ask the host, which counts the marker line that template opens with:

```sh
gh search prs --repo <org>/<repo> --merged --match comments \
  '"Merged on the owner override"' --limit 100 --json number -q length
```

Comments written before that template used their own wording, so `--match comments
override` is the wider net over the history. What the count measures is recorded in
`knowledge/findings/nineteen-consecutive-prs-merged-on-the-override-so-the-verification-gate-is-a-report.md`:
an override that is convenient enough becomes the default route, and the exception stops
being visible as one.

> **The full incident is one `Finding` in the operator's own bundle, and it is not copied
> here.** `knowledge/findings/every-agent-fix-push-spends-a-shared-review-and-a-free-plan-caps-files-at-100.md`
> — how the hourly quota was spent by three parallel agents' fix pushes, why upgrading the
> plan did not help (a fair-usage ceiling credits do not lift), and the 147-file PR the free
> plan refused outright. A bundle's `knowledge/` is that operator's record and is not part
> of this repository; duplicating it here would fork it at the first update.

**Recommended:** set branch protection to require CI green + a review from that reviewer.
GitHub only enforces *that* CI passed and a review happened — whether the reviewer
actually checked the acceptance criteria is the reviewer's job, not something branch
protection can guarantee.

## One review per PR (cost control)

The gate needs *one* fresh-context review, not a review per push. Left at its defaults
CodeRabbit re-runs on **every push** and replies to **every comment**, so a PR whose
findings an agent then fixes burns several sessions to re-confirm a diff that's already
clean. Three rules keep it to one.

1. **Pin it in the target repo's `.coderabbit.yaml`** — `reviews.auto_review.auto_incremental_review: false`
   (stop re-reviewing each push) and `chat.auto_reply: false` (stop replying to every
   comment; it still answers an explicit `@coderabbitai`). Both default to `true`. This
   repo's own [`.coderabbit.yaml`](../.coderabbit.yaml) is a working, commented example.
2. **Don't pay for the same reviewer twice.** If CodeRabbit reviews the PR, the
   pre-filter self-review uses the *free local* reviewer (`code-architect`), not the
   `coderabbit` CLI. `qa-reviewer` likewise **reads** an existing CodeRabbit review off
   the PR (via the structured `--json reviews`, not `--comments`) rather than re-running
   the CLI over the same diff — and when the repo is configured but hasn't been reviewed
   *yet*, it reports the gate as pending instead of substituting a CLI run.
3. **Never re-review to confirm a fix.** Agents address findings, push, and reply once
   with what changed. A re-review is requested only after a rewrite substantial enough to
   invalidate the original review. **This is about the same diff.** A push moves the head,
   which makes any prior verdict stale (predicate clause 3), so the *new* commit still has
   to be verified before it can merge — that's re-verification of different code, not
   re-review of the same code, and the loop does it automatically.

## Two rounds, then the human decides

A **hard cap** on how many verification rounds one PR gets, so an unresolved disagreement
costs the human one decision rather than an unbounded review.
[`plugin/seed/CONVENTIONS.md`](../plugin/seed/CONVENTIONS.md) → "TWO ROUNDS, THEN THE HUMAN
DECIDES" is normative and carries the measurement behind the number.

| Round | What happens |
|---|---|
| 1 | the reviewer reports findings; the implementer fixes them and replies **once** |
| 2 | the reviewer checks **only** what it raised in round 1 — new findings outside that set are recorded, not blocking |
| 3 | **there is none.** Whatever is unresolved goes to the human in one short block: what the reviewer wants, what the implementer says, what the criterion actually asks |

`scripts/review-rounds.sh <pr> [--repo <owner>/<name>]` makes the cap a number a
dispatcher **reads** rather than a rule it has to remember. Run it before dispatching a
verifier, and before verifying as one.

| Exit | Means |
|---|---|
| 0 | under the cap |
| 1 | at or past two rounds — stop, and put both positions in front of the human |
| 2 | cannot answer. **Unknown is not permission**, and a missing or broken script lands here too, so the failure direction is "ask the human" |

A round is one **completed verification of a distinct commit**, and whether a candidate
counts is decided by `review-clearance.sh` unmodified — so a rate-limited reviewer's
refusal is not a round, and an absent reviewer adds none. The count is a **floor**: it can
be one low (which costs one extra dispatch) and it cannot be one high from anything an
artifact's text says.

## Browser writes

A project can let its role agents drive a real browser via Claude for Chrome
(`browser: claude-for-chrome`). Where a mode delegates them, browser **writes** are
permitted (forms included) — the loop already self-promotes and self-merges, so carving
out the browser would be inconsistent. Under `gated`, ask first. Read-only navigation and
screenshots need no permission either way.

Permissions are pre-wired so nothing stalls: Claude Code's tool permissions sit
*underneath* a project's `autonomy`, and left prompting a background agent would stall on
a prompt nobody is watching — the task would read as hung rather than blocked. So
`plugin/seed/.claude/settings.json` allows `mcp__claude-in-chrome__*` and every instance picks
it up through the symlink. From there the extension's **per-site permissions** are the
boundary that actually holds, so restrict there. To restore prompts, shadow the rule with
`ask` in the instance's `.claude/settings.local.json`.

Agent-facing rules: [`SCHEMA.md` → "Browser access"](../plugin/seed/SCHEMA.md).

### What browser access looks like in practice

There is **nothing to configure in the instance.** The Chrome extension *injects* the
`mcp__claude-in-chrome__*` tools into a live paired session — no `mcpServers` stanza, no
`.mcp.json`, and `claude mcp list` doesn't even show it. Machine-level setup is: install
the extension, then grant it **per-site** permissions there.

- **Background role agents can use it.** The connection is inherited by background subagents, so this is *not* foreground-only — agents dispatched by a `/loopd:dispatch` tick can drive Chrome. To make that reachable, `software-engineer`, `devops-engineer` and `qa-reviewer` carry `ToolSearch, mcp__claude-in-chrome__*` in their `tools:` allowlist (a closed allowlist otherwise excludes every MCP tool). The pattern resolves to nothing when the extension isn't paired, which is harmless — the rest of the allowlist still resolves.
- **Each agent gets its own tab group**, not the human's open tabs. Agents must navigate from an explicit URL; they can't "look at the tab you have open".
- **A headless/cron tick has no browser.** Agents degrade to a non-browser route and say so, rather than reporting the task blocked.

> **Upgrading an existing instance:** re-running `/loopd:init` picks up `SCHEMA.md` and the
> role agents (symlinked), but **not** `CLAUDE.md` — seed content is copied only when
> absent, never clobbered. Add the **Browser** bullet from `plugin/seed/CLAUDE.md`'s "Conventions
> for role agents working in target repos" to your instance's `CLAUDE.md` by hand.

---

## The audit counter-metric

`/loopd:dispatch` optimizes throughput; **`/audit`** is the independent check that the throughput
is actually moving the real goals. Run it on a **slow cadence** — weekly, or after a batch
of projects close.

The read-only `auditor` grounds each goal's `success_criteria` — an objective's, or a
project's own where it carries no `objective:` — against live `gh`/`git`
reality and flags the four ways a busy control panel drifts:

| Drift | What it looks like |
|---|---|
| **Goodhart** | lots closed, goal unmoved |
| **Measurement decay** | stale `Finding`s |
| **Green but not progressing** | projects passing every check without moving anything |
| **A weakened anchor** | a human gate or the verification gate slipping — or a merge-delegating project merging PRs an independent reviewer hasn't cleared |

It writes a dated audit to `log.md` and **never acts** — responding (adjust targets,
re-validate findings) is your governance call. It is the independent signal that catches
an autonomous loop gaming itself: a periodic, advisory guardrail, **not** a merge-blocking
guarantee.
