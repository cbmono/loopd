# Design invariants, and why each one exists

This is the reasoning behind loopd's design. Every bullet here exists because
something went wrong once, and the "why" is the record of what went wrong — so
preserve it when you edit a rule rather than summarising it away.

**Audiences.** This file is for a human reading deliberately. The root
[`CLAUDE.md`](../CLAUDE.md) carries a one-line headline for each invariant below,
because a prohibition has to be in context *before* you consider the change it
forbids; and [`.claude/rules/`](../.claude/rules) carries the same prohibitions
path-scoped, so they load when an agent reads a file they govern. Neither of those
repeats the story — this file is the single home for it. If you shorten a "why",
move it here intact instead.

> **History.** These paragraphs were relocated verbatim from `ai-setup`'s root
> `CLAUDE.md`, then from `ai-setup/.claude/rules/ai-bridge.md`, and finally into this
> repo when loopd was split out of `ai-setup`. Paths were rewritten for this repo's
> root (`ai-bridge/symlink/…` → `symlink/…`, `ai-bridge/tests/…` → `tests/…`); nothing
> else was changed.

## Contents

| # | Invariant | Governs |
|---|---|---|
| 0 | [Layout](#layout) | the whole repo |
| 1 | [Retiring seed content is only reported](#1-retiring-content-is-asymmetric) | `/loopd:init`, `/loopd:welcome fix`, `RETIRED`, `plugin/seed/` |
| 2 | [Retiring machinery sweeps the links](#2-retiring-machinery-means-deleting-the-file-and-letting-loopdinit-sweep-the-links) | `/loopd:init`, `plugin/` |
| 3 | [`AWAITING.md` is opt-in by presence](#3-awaitingmd-is-loopds-only-status-artifact-and-it-is-opt-in-by-presence) | `/loopd:init`, the PM agent, `session-banner.sh` |
| 4 | [A deletable capability is one file](#4-a-capability-some-deployments-must-not-have-should-be-one-deletable-file) | `plugin-yolo/` (the `loopd-yolo` companion), `resolve-autonomy.sh`, `commit-as.sh` |
| 5 | [`build` and `research` are asymmetric](#5-build-and-research-projects-are-deliberately-asymmetric) | `/new-project` |
| 6 | [The merge gate: exit 0 is the only clearance](#6-the-delegated-merge-gate-resolves-its-required-checks-in-required-checkssh-and-exit-0-is-the-only-clearance) | `required-checks.sh`, `review-clearance.sh` |
| 7 | [`prune-worktrees.sh` is report-only](#7-prune-worktreessh-is-report-only-and-that-is-load-bearing) | `prune-worktrees.sh` |
| 8 | [`validate-bundle.sh` was scoped by measuring](#8-validate-bundlesh-was-scoped-by-measuring-first-and-that-is-the-point) | `validate-bundle.sh` |
| 9 | [`migrate-bundle.sh` fixes only what has one right answer](#9-migrate-bundlesh-fixes-only-what-has-one-right-answer-and-is-report-only-by-default) | `migrate-bundle.sh` |
| 10 | [The scaffold review is a three-stage chain](#10-the-scaffold-review-is-a-three-stage-chain-with-a-declared-fallback-never-a-skip) | `/new-project` step 8 |
| 11 | [The board's five invariants](#11-the-cross-instance-board-is-a-writer-three-renderers-and-one-deletable-generated-file) | `write-snapshot.sh`, `build-board.sh`, `print-board.sh`, `watch-board.sh` |
| 12 | [Three behaviours against a silent wrong answer](#12-three-loopd-behaviours-that-all-exist-because-a-silent-wrong-answer-is-worse-than-a-loud-one) | `push-state.sh`, `answered_questions`, `maxPrLoc` |
| 13 | [A shared instance is three no-ops and one gate](sharing.md) | `task-owner.sh`, config split, derived indexes |
| 14 | [`knowledge/references/` is the fifth knowledge kind](#14-knowledgereferences-is-the-fifth-knowledge-kind) | `validate-bundle.sh`, `SCHEMA.md` |
| 15 | [The config layer is one tier, and the arrow stays one-way](#15-the-config-layer-is-one-tier-and-the-arrow-stays-one-way) | `init-bundle.sh --config`, `config/` |
| 16 | [The kill switch is one hook, and it fails open](#16-the-kill-switch-is-one-hook-and-it-fails-open) | `plugin/hooks/agent-control.sh`, `control.sh` |
| 17 | [An instruction is executable only if the agent *holds* the tool](#17-an-instruction-addressed-to-an-agent-is-executable-only-if-that-agent-holds-the-tool) | every agent body, `plugin/seed/CONVENTIONS.md`, `plugin/seed/CLAUDE.md` |
| 18 | [The allowlist check is pinned from both sides](#18-the-tool-allowlist-check-is-pinned-from-both-sides-and-silence-is-a-failure) | `agent-tool-allowlist.test.sh` |
| 19 | [The destructive-action baseline is a hook, and it is narrow on purpose](#19-the-destructive-action-baseline-is-a-hook-and-it-is-narrow-on-purpose) | `plugin/hooks/deny-destructive.sh`, `permissions.deny` |
| 20 | [The version is a number the MERGE moves](#20-the-version-is-a-number-the-merge-moves-and-the-drift-check-speaks-only-when-behind) | `VERSION`, `release-bump.sh`, `check-template-version.sh`, `core` paths |
| 21 | [`/loopd:welcome` reports facts that can be false, and `fix` is tiered in code](#21-loopdwelcome-reports-facts-that-can-be-false-and-fix-is-tiered-in-code) | `welcome.sh`, `/loopd:welcome`, `session-banner.sh` |

---

## Layout

- **This repo** — a **reusable OKF control-panel template**. `plugin/` holds generic machinery (SCHEMA, `CONVENTIONS.md` — the shared role-agent conventions, read on dispatch because they govern the target repos, which no `paths:` glob can reach, role agents, `/loopd:dispatch`, `/new-project`, `/close-project`, `/pr-review-request`, `/answer`, `/fanout`, `/audit`, `commit-as.sh`, `required-checks.sh`, `task-owner.sh`, `prune-worktrees.sh`, `close-project-folder.sh`, `validate-bundle.sh`, `migrate-bundle.sh`, `write-snapshot.sh`, `build-board.sh`, `print-board.sh`, `watch-board.sh`, `index-kb.sh`, `link-repos.sh`, a `SessionStart` hook for tasks-awaiting-you, a `UserPromptSubmit` hook pushing current instance state) shipping in the `loopd` plugin, installed once per machine and never copied into a per-group **instance**; `plugin/seed/` holds starting content copied once; `/loopd:init` stamps out / refreshes an instance and manages its gitignore; `RETIRED` declares seed paths the template has stopped shipping, which are reported and never deleted. Each instance is its own repo under `~/workspace/<group>/_loopd-<group>/` (leading underscore, named distinctly from this template dir). `AUTONOMY.md` is deliberately NOT in that list: it is neither machinery nor seed, and ships from the `loopd-yolo` COMPANION plugin, `plugin-yolo/` (ai-bridge-v2/task-018). Keep machinery generic — org/repo/path/team/channel literals live in an instance's `instance.config.json` / `CLAUDE.md`, never in `plugin/`. <!-- This bullet was duplicated three times by conflict resolutions; it is now ONE line carrying the union of all three. If you resolve a conflict here, merge into this line — never append a second copy. -->
- **Not part of the `~/.claude` config layer.** loopd used to live as an `ai-bridge/` subtree inside the [`ai-setup`](https://github.com/cbmono/ai-setup) repo, whose own root installer is scoped to `.claude` and never touched it. That separation is now physical: **this repo is the canonical copy**, an instance's machinery ships from *this* repo as the `loopd` plugin, and `ai-setup`'s installer has nothing to do with it. **`ai-setup` no longer carries that subtree at all** — [`ai-setup#69`](https://github.com/cbmono/ai-setup/pull/69) removed it, and its last state is in git history only (`git -C ai-setup show f8b09a4:ai-bridge/`), so a path under `ai-setup/ai-bridge/` does not exist rather than being stale. This sentence used to say the subtree was still there and frozen — which contradicted `README.md` and pointed maintainers at a checkout path that is gone. That is the same "documentation describes a deleted thing as live" defect that removing the subtree was meant to end, and the third instance of it corrected in this PR. `ai-setup`'s *config* layer briefly lived here too — forked wholesale under `config/` behind a second install target (`init-bundle.sh --config`) — but that fork is what caused 24 colliding `~/.claude` paths with 14 diverged, so it has since been handed back: `config/` now ships only the three agents loopd itself probes for, and `~/.claude` is `ai-setup`'s alone again — see [15](#15-the-config-layer-is-one-tier-and-the-arrow-stays-one-way). The two halves share the worktree guard and nothing else.

---

## Conventions when editing

## 1. Retiring content is asymmetric

**Retiring content is asymmetric: machinery is swept, seed content is only reported.** A dangling symlink pointing into this template has exactly one possible meaning, so `/loopd:init` step 2b deletes it. A **seed** file does not — it was copied in once and has been the human's to edit ever since, and `todos.md` was literally their notes. `/loopd:init`'s safety property is that it only links and seeds-if-absent, never removing instance content, which is what makes it safe to run blindly on a repo full of someone's work; spending that to save one `rm` would be a bad trade. So retired seed paths are declared in `RETIRED` (`<path>\t<reason>`, tab-separated) and **reported with the exact `rm`**, and `/loopd:welcome fix` puts them in the numbered "what's left for you" list — which is the whole point, since that list is what a collaborator actually reads. **Add the entry in the same commit that deletes the seed file, and never prune the manifest**: an instance stamped years ago still has the file, so a pruned entry stops answering for exactly the instances that need it. Absence of the file, an empty one, a comment, a blank line, or an entry naming a path an instance doesn't have are all silence, never an error. A **symlink** at a manifested path is step 2b's business, not this list's. Covered by `tests/retire-machinery.test.sh`.

## 2. Retiring machinery means deleting the file *and* letting `/loopd:init` sweep the links

Removing a capability from `plugin/` leaves every already-stamped instance with a symlink into a path that no longer exists, and the link loop never notices because it only iterates files that *do* exist. A dangling command still registers with Claude Code, and a `SessionStart` hook whose script has vanished exits 127 on every launch — so absence here is **not** safe, unlike the `AUTONOMY.md` pattern. `/loopd:init` step 2b sweeps them, and its test is narrow on purpose: a link is removed only when it points **into this template's `plugin/`** (decided by `ours`, not by name) **and** its target is gone — that combination has exactly one possible meaning. A real file, a link elsewhere, or a link that still resolves is left alone, and **seed content is never removed**: a `todos.md` outliving the retired `/todo` feature is the human's own writing, so it is reported, not deleted. Covered by `tests/retire-machinery.test.sh`.

## 3. `AWAITING.md` is loopd's only status artifact, and it is opt-in by presence

There is deliberately **no `/status` command** (deleted in favour of this) and no full board — the file lists only what a human decision unblocks (✅ approve · ❓ answer · 🔀 merge · ⛔ unblock · 🏁 close · ⏳ continue), because in-flight and upcoming work needs no decision and a board people scroll past is a board they stop reading. **`/loopd:init` creates it on the first stamp only** (gated by `FIRST_STAMP`, computed before seeding), and the `project-manager` rewrites it each tick **only if it already exists, never creating it** — so `rm AWAITING.md` disables it permanently and an installer re-run must not resurrect it. That's the `AUTONOMY.md` absence-is-safe pattern with the default flipped: a new instance ships with the nudge working, rather than silently off until someone reads the docs. If you ever move creation out of the first-stamp guard, you break the off switch. `session-banner.sh` greps for the literal `## 🔴 Awaiting you` heading and asterisk-space bullets, so **the PM agent owns that exact layout** and reshaping either silently empties the startup nudge. The hook fences the items as **untrusted data** before they enter session context — the text comes from task docs carrying human questions, tool output, and PR metadata, and sits beside the hook's own instruction, so keep the boundary if you touch that output. **The items and that fence are the model's copy only** (`additionalContext`); the human's copy (`systemMessage`) is one count line naming the number and where to act, because the fence is written for a machine and the list is a third rendering of a queue `/loopd:dispatch` and the board show better. The two travel together — never fence without items, never items without the fence — and `tests/awaiting-queue.test.sh` asserts both halves out of one run for that reason. Don't reintroduce a status command or the 🟡/🟢/⛔ sections.

## 4. A capability some deployments must not have should be *one deletable file*

…not a flag threaded through the machinery. `AUTONOMY.md` is the pattern: it holds every delegated-autonomy mode, and every other doc says only "…unless `AUTONOMY.md` exists — absent, every project is `gated`". Removing it disables the capability with **no edits** to the eight documents that reference it, and `commit-as.sh` gates its promotion guard on the same presence check (fail-closed). **The deletable thing is now a whole plugin**: core ships no capability file, `loopd-yolo@loopd` ships `companion/AUTONOMY.md`, and `resolve-autonomy.sh` is the one reader — bundle root first, then an installed companion from core's own marketplace, then `gated`. When you add machinery like this, (a) make absence mean the safe behaviour, never an error; and (b) add a test case proving the capability is off when the file is gone (see `tests/commit-as-guard.test.sh`, and `tests/awaiting-queue.test.sh` for the same pattern applied to `AWAITING.md`). Don't reintroduce a partial variant of a mode that was deliberately collapsed into one all-out setting.

**The caveat that motivated the companion split, and the one that replaced it.** `AUTONOMY.md` used to live under the machinery, and `/loopd:init` re-links machinery unconditionally — by design, since repairing broken links is what a refresh is for. The two collided: `rm AUTONOMY.md` disabled autonomy for one instance, and the next stamp silently switched it back on, which is fail-**open** on the one capability that lets agents merge without asking. **Making it a companion plugin removes the collision at the root** — core ships no capability file, so a stamp has nothing to re-link. **A deletable capability made out of a file under `plugin/` still inherits that hazard**: build it as a **companion** (`plugin/README.md` → "Companion plugins"), or put it in `plugin/seed/` (where seeds-if-absent still resurrects it, so guard it the way `AWAITING.md` is guarded by `FIRST_STAMP`). The caveat that replaces it is smaller and is stated in `docs/autonomy.md`: a plugin is installed **per machine** while a root file is **per bundle**, so installing the companion arms every bundle on that machine and the per-project `autonomy: gated` is the opt-out.

## 5. `build` and `research` projects are deliberately asymmetric

**Don't restore a question for symmetry.** `/new-project` asks a research project for *less*: no `target_repo`, no `clis` prompt (`clis` declares what a project's **agents** may use, and research dispatches none — the PM tracks, the human works in-session), and no step-8 scaffold review (the whole three-stage chain, not just its CodeRabbit stage). Each was removed because it describes machinery a research project never runs, so asking it makes the human authorise tools nothing will use; the CodeRabbit skip is the sharper case, since a code reviewer's real teeth (authorization holes, injection) find nothing in a markdown scaffold and the one check that matters — PII/secrets — has only `sources/README.md` to read at creation time. `browser` **is** still asked (web research is its clearest case). Be exact about what gets written, so nobody "restores" the prompt or invents a value: `/new-project` writes `clis:` **from the explicit `clis=` flag if one was passed, and otherwise as an empty list** — it neither asks nor probes, and it never substitutes a placeholder such as `none`, which would read as a declared capability named "none". `kind` must therefore be settled *before* the batched capability question, not inside it. Versioning needs no GitHub MCP: the bundle is itself a git repo and deliverables are committed via `commit-as.sh`.

## 6. The delegated merge gate resolves its required checks in `required-checks.sh`, and exit 0 is the only clearance

It prefers **branch protection** and falls back to `.github/required-checks.txt` on the PR's base branch, because a private GitHub repo on a free plan returns 403 from both the branch-protection and rulesets APIs — without a fallback, `yolo` merges are unexercisable by construction there. Keep the ordering (platform wins, so upgrading a plan is a no-op switchover that also binds human merges) and keep every ambiguity refusing: only `pass` clears, a declared name no check reports is drift not absence, and a PR editing the list is a human decision. Classify the platform probe on its **payload**, never its exit code, and recognise exactly **three** answers — JSON (protection spoke; an empty array legitimately falls through), the literal "no required checks" message (no protection; the fallback may answer), and **anything else ⇒ exit 2**. `gh pr checks --required` exits non-zero both when a required check *fails* and when no protection exists, so an exit-code test downgrades the gate; and a transient 5xx or expired token must never read as "nothing is required", which would swap protection-we-failed-to-read for a possibly weaker list. Note the message goes to **stderr** while JSON goes to stdout, so capture the two streams separately — never merged, or a stray `gh` warning prefixes the payload and a good answer classifies as garbage. Covered by `tests/required-checks.test.sh`; the stub there mirrors real `gh` quirks (a 404 body goes to **stdout**), so extend the stub rather than working around them in the script.

**The same clearance discipline, one layer over: a green check from a reviewer that DECLINED to review is not verification.** A hosted reviewer that hits its quota exits *successfully*, so its status check publishes `pass` — identical to the check on a PR it actually read. Three PRs went out in one tick on 2026-08-26: one was reviewed, two carried "Review limit reached. Next included review available in 44 minutes", all three were green, and both refusals merged — one shipping a shell script at mode `100644` that no caller can execute. So `review-clearance.sh` asserts a review **artifact that evidences a completed review**, and `required-checks.sh` asks it for one on **every** PR it is about to clear rather than deciding from a check's *name* whether a reviewer is involved. **Detect the refusal by LANGUAGE, never by the commit range it quotes** — the refusal comment carries the same `between <base> and <head>` line a real review carries, and on the PR that merged unreviewed that head was the PR head exactly, so a range-keyed detector reads a refusal as a review. Classify against the refusal table first and consider clearance only for what survives; reversing the two re-opens the hole, and `tests/review-clearance.test.sh` pins that exact false positive against the two recorded comment bodies in `tests/fixtures/reviewer/`. Every vendor fact lives in that script's tables, so switching reviewers is a row rather than a rewrite — and a missing or wrong row now costs a **refusal**, never a clearance. A missing `review-clearance.sh` makes `required-checks.sh` exit 2: without it the reviewer state is unknown, and unknown fails closed.

**Fail-closed is a property of the *caller*, and it has four edges — all four were open in the first cut.** (1) A **present-but-broken** sibling is worse than a missing one: `[ -x ]` tests a mode bit, so a dead shebang, a syntax error, a zero-byte file or a copy truncated mid-install all pass it and then fail every call — which used to read as "no required check is a reviewer's", consult no clearance, and report `ok: N required check(s) pass` on an unreviewed PR. The gate does not fail; it disappears. So the sibling must **prove it runs** (`--self-test`: two table-driven controls plus a sentinel string agreed between the two files, spelled out in both rather than sourced — sourcing the suspect file is the thing being tested for), and `--match-check` answers outside `{0,1}` are unknown state, never "no reviewer owns it". (2) **A check's NAME never settles whether anybody looked.** This used to be a table of vendor names and review phrasings, and `Codex Review` — or bare `Cursor` / `Copilot` / `Devin` / `PR Agent` — matched no row, read as plain CI and settled on its green bucket with zero artifacts read: the original incident with a 2026 vendor's name on it. A name table cannot be finished, so the table is **deleted** and clearance is asked for on every PR whatever its checks are called. (3) Clear each reviewer-owned name **against the reviewer that owns it** (`--for-check`), or on a two-reviewer repo one vendor's review clears the other vendor's refusing check; where no vendor owns any required name, one unscoped call still has to clear. (4) **Unbalanced code fences fail closed.** The fence stripper is a toggle, so one prepended ``` inverted it, blanked the rest of the body, and left the head test reading raw text — the recorded refusal cleared, from one character typed into a comment. An odd count now hands the **raw** body to refusal detection (where reading too much is safe) while the **clearing** side gets a strict rendering that is empty, so an unreadable body evidences nothing.

**And the fifth edge was the classifier's own default — five more routes, found by a second round of review.** (1) **Positive evidence is now REQUIRED**, because asking only "is this a refusal" and clearing everything else is default-allow: the reviewer's *"Currently processing new changes in this PR…"* placeholder, published on nearly every PR before it reads anything, exited 0. An artifact that evidences nothing is exit 4, and a placeholder is exit 1. (2) The **`okf-verdict` trailer is parsed, not grepped** — the marker alone on its line, a closing `-->`, and `verdict`/`reviewer`/`head_sha` present with the SHA equal to the head being cleared — and it is honoured only for an account named with `--reviewer` that is **not** a vendor in the table, because naming the vendor re-armed the highest tier in the file against that vendor's own refusal. It is parsed from a rendering with **indented** blocks stripped as well as fenced ones, and a block nested in an outer HTML comment (which GitHub renders blank) or left unclosed is discarded. (3) **`--self-test` proves the file RUNS, not that it is COMPLETE**: it sits near the top, so a copy truncated below it still passed while its tables were gone — 112 of 606 truncation points passed, 109 of those then cleared an unreviewed PR. The last line of the script is now a completeness sentinel the self-test asserts. (4) **A table that will not compile matches NOTHING**, which for a refusal table reads every refusal as a review; `grep` says 1 for "no match" and 2 for "bad pattern", so every row is compiled up front and every match checks the status. (5) **The reviewer logins are exact**, not `greptile.*` and `(qodo|codium).*` — a whole-string match ending in `.*` let `greptile-evil` and `qodo-attacker` pass as the vendor.

**Evidence and pinning come from the API; text matching only ever detects a refusal.** A review object's `state` (exactly `APPROVED`, `CHANGES_REQUESTED` or `COMMENTED`, compared case-sensitively against the API's own spellings) and its `commit_id`, read from `/repos/{o}/{r}/pulls/{n}/reviews`, are what clear it — not whether its body happens to mention the head SHA, which is precisely the property the *refusal* also has. A **comment** can still clear, because this repo's reviewer publishes a clean review as an issue comment and files no review object for it, but only on the vendor's own machine-emitted `<!-- … -->` review marker plus the head named as a bare token; every row of prose evidence (`i (have )?reviewed`, `lgtm`, `changes requested`) is **deleted**, since unanchored prose cleared quoted approvals and matched negated sentences like `Unreviewed <sha>`. The refusal table stays over-broad on purpose — a false refusal costs a human glance, a missed one costs an unreviewed merge — and it is outranked only by that machine marker, so `Review skipped — Auto incremental reviews are disabled` (above the walkthrough on **10 of this repo's 22 reviewed PRs**, because `.coderabbit.yaml` sets `auto_incremental_review: false` deliberately) does not unmake the review it sits in, while the reviewer's machine-readable rate-limit sentinel loses to nothing. **Expect exit 4 to be the common answer** — **18 of this repo's 35 PRs** carry a CodeRabbit review object and exactly **one** was made at that PR's final head — and read it as *stale, not absent*. Most PRs will need a review requested at the final head before they can clear. That is a real operating cost of the gate, not a threshold to tune away.

**Three things the move to the API cost or left open, and each is a rule rather than a patch.** (1) **A review object that says NOTHING is not evidence on its own.** The old body-SHA pin was wrong for every reason above, but in this one respect it failed closed — an empty body cannot name a head — so once `commit_id` became the pin, an **empty-bodied `COMMENTED` object at the head cleared over the reviewer's own verbatim rate-limit refusal at that same head**. `COMMENTED` is not a claim: the host mints one for any inline comment or thread reply (twelve empty ones sit in this repo's corpus), so an empty one evidences nothing (exit 4). An empty `APPROVED` / `CHANGES_REQUESTED` **is** a claim — the state is the verdict — but it is decided only after every artifact has been read, so a refusal **naming this head** still wins; an older refusal at another commit does not, because a PR that was skipped once has to be able to recover. **No corpus rescore can see this class**: it needs a PR carrying both shapes, and none does. Construct the case. (2) **The two body renderings must agree on what a fence is**, and they must agree with the *host's renderer*. The refusal side stripped leading whitespace before testing for a fence while the clearing side treated a ≥4-space or tab line as an indented code block, so an **indented fence hid the unconditional refusal sentinel** while a review marker outside it cleared — inverting the file's own invariant, which is that the strict rendering is a **subset** of the stripped one. One shared fence state machine serves both. (3) **A missing field silently switches a rule off.** An absent or empty PR-author login left both author comparisons testing against `""`, which no login equals, so SCHEMA.md clause 8 stopped applying and a reviewer could clear its own PR. Every PR has an author: not being told who it is is unknown state, exit 2.

**And making the two renderings agree with each other is not making them agree with the host — the round that claimed both had only done the first.** Three disagreements with CommonMark, each failing open, and all three reproduced against the recorded refusal: **blockquote containment was discarded**, so a fence opened at quote depth 1 was closed by a line at depth 0 and the refusal inside it vanished (that is the reviewer's *native idiom* — its notices arrive inside a `> [!WARNING]` blockquote, so this was reachable with no construction at all); **tabs were never expanded to four-column stops**, so `1–3 spaces + TAB` was markup here and literal code on the page, which let a comment merely *quoting* the `okf-verdict` trailer validate as a real verdict; and a closing fence's **run length and info string were ignored**, so a ```` ```` ```` opener closed by ``` ``` ``` paired — which also turns an odd number of markers even and defeats the unbalanced-fence net. The rule now measures containers and indentation in **columns** and carries the opener's quote depth, run length and info string. Two more of the same shape: **"content" must mean what RENDERS** (any non-whitespace byte counted a zero-width space or an empty `<!-- -->` as a claim, restoring (1) exactly), and **a refusal must be weighed before anything can be dropped** — one that names *no* commit is of unknown scope rather than an old one, a non-submitted review state can still carry a refusal, and an artifact whose author the host reports as `null` is unreadable state (exit 2), not an irrelevant one. **Nothing clears inside the classifier loop**, so the answer cannot depend on the order the host streamed the artifacts in.

**Enumerating what to remove is the defect; deciding what renders is the fix — and it made the file SMALLER.** Six rounds had each answered a route by adding a row, a character or a case, and the seventh's three routes were all the same shape again. (1) **The block machine models no containers**, so a construct that changes what ``` *means* put the refusal back behind a fence the host does not see: inside a raw-HTML block the content is HTML, and `<details>`/`<summary>` is the shape the recorded fixture is itself built from, so `<details>`, `<pre>`, `<div>` and `<table>` each cleared with the recorded refusal on the page — as did a fence that the host closes at the end of the **list item** holding it. The fix is not a list of block-level tag names: the machine is **read twice** — reading A is fences and blockquotes, reading B adds raw-HTML blocks and list items — and the **refusal side takes the union of the two readings while the clearing side takes the intersection**. A refusal must be code under *every* reading to disappear and a clearance must be markup under *every* one to count; `strict ⊆ stripped` becomes structural rather than tested; a reading may be crude in either direction; and the next construct is a **third reading**, not another case. (2) **"What renders" was a list of invisible characters**, and thirteen more code points went through it, along with `&#8203;`, `[//]: # ()` and `<div></div>`, which no character list reaches. Inverted: markup is removed *because it is markup* (HTML comments, tags, character references) and what must be **left** is an ASCII letter or digit. `print-board.sh` reaches the same conclusion from the terminal end — drop every code point in Unicode general category C, "one rule rather than a blocklist of known-bad sequences" — and its implementation is deliberately **not** reused, because it needs python3 and because category C would not cover U+115F, U+3164 or U+FE0F anyway. The cost, stated: a body with no ASCII alphanumeric at all is read as saying nothing, which is a refusal and a human glance. (3) **A header claim the code does not keep is a defect in itself.** "Prose cannot reach the evidence half" was false — the vendor's marker spelled inside an inline code span is visible text and matched anyway — so the evidence rows are now anchored to a **whole line** and the strict rendering drops multi-line code spans; and **issue comments are fetched paginated from the REST endpoint**, because `gh pr view --json comments` answers one page and the artifact that must never be lost is a *refusal*.

**Two models of a renderer cannot bound the distance from either to the renderer — so the oracle is the renderer.** The construction above says the refusal side keeps a line either reading keeps, and that was argued to make a crude reading cost at most a false refusal. It does not. **A union removes a line only when EVERY reading removes it** — it is an AND-gate over the readings, and a mistake they *share* is inherited by their union. Measured: a refusal spelled as three sibling list items (` - ``` ` / the words / ` - ``` `) was hidden by reading A, which models no list items, *and* by reading B, which ended an item only on a dedent — so the union hid it, while GitHub renders the middle line as an ordinary bullet. **A false clearance is reachable through the refusal side**, which is the one thing the construction existed to rule out. `strict ⊆ stripped` is still true and still structural; it was never the property that mattered. What replaces the argument is a measurement: `tests/fixtures/reviewer/host-rendering.txt` holds **154 bodies answered by github.com's own Markdown endpoint**, recorded by a script checked in beside it, and the suite asserts the two directions that cost something — *the host renders it as readable prose ⇒ the gate refuses*, and *the host puts the characters on the page ⇒ the gate does not clear*. Adding a reading is still how a construct is covered; "we added a reading, so it is safe" is not an argument.

**A test that cannot go red is worse than no test, because it is counted.** The property the previous round proved over 400 generated bodies — strict ⊆ stripped — is true of *any* intersection and union, so the sweep confirmed a shape rather than a behaviour and stayed green through every destructive mutant aimed at it, including on the day the union was hiding a refusal. The 22-row invisible-character battery beside it was the character list the fix had just deleted, kept as a test. Both are gone; the recorded host answers replaced them, and the suite got faster. **The same class caught the author too:** an over-escaped quote in a new test section left an unterminated string that swallowed nine assertions, and the suite reported them as absent rather than failing — found by a *surviving mutant*, not by reading the diff.

**A closed set is a decision; a growing set is an enumeration.** `renders_content` had been inverted to "remove markup, require a letter left", but it knew two markup *shapes* — an HTML comment and a tag — and eleven constructs github.com renders blank walked through it (`[//]: # (a comment)`, `[x]: /y`, `[](url)`, `![](/x.png)`, `<a href="1>2"></a>`, `<!DOCTYPE html>`, `<?php ?>`, `<!ENTITY x "y">` …), each one a review object with an empty page counting as a claim. The fix is not a longer list: CommonMark defines **exactly six** raw-HTML productions and there is no seventh, so all of them are implemented, alongside the two other places the source carries bytes the page never shows — a **link reference definition** and a link or image **destination**. And where the specification and the host disagree, **the host wins and it is recorded**: asked for `<![CDATA[a > b]]>` github.com answers ` b]]&gt;`, ending the construct at the first `>` exactly as it ends a declaration, so the CDATA production is *not* implemented and the case is in the fixture saying why.

**A hash is a whole token.** Matching a 7–40 character run of hex finds one inside every UUID — the reviewer stamps its own refusals with `Run ID: f4981ca2-…`, whose fields are runs of 8 and 12 — and that fed the one place the answer is used in the opening direction, where "it names some commit, and not this one" demotes a refusal to an older one. Cut the body into tokens on everything a hash cannot contain *first*, and a UUID field is joined to the rest by `-`, so the token is not hex. Both callers get safer: a pin is lost (no clearance) and a refusal keeps its weight.

**The residual, stated rather than glossed:** a refusal at this head **loses** to an artifact carrying evidence at this head. That is deliberate — the reviewer is rate-limited and then reviews the same commit — and the only way to tell it from "posted a reply with words in it" would be to read the reviewer's *prose*, which is the primitive this file exists to stop using. The operator is told on stderr when it happens.

**A corpus rescore is a change detector, not a correctness proof.** All 37 PRs, both versions, the same live GitHub state re-read from the API on each invocation (never a snapshot), **0 of 37 exit codes changed** — for five rounds running. That is a null result about *reachability*: every behavioural change in the last three rounds is unreachable in this corpus, so the rescore gives **zero coverage of the new logic**. It shows the gate was not widened; the evidence that a route is closed is the constructed case and its passing control.

**The self-test still decides; it is no longer re-run for bytes it has already passed.**
`pr-body-clearance.sh --self-test` is a deliberate battery of probes and takes 2–4 seconds;
`required-checks.sh` ran it, and `review-clearance.sh`'s, on **every** invocation — every
gate evaluation in a tick, and 100 seconds of one harness (52 after, measured 2026-10-05).
A self-test reads nothing but the script's own file, so its answer is a property of those
bytes: `selftest_ok` keys the verdict on the file's checksum and byte count, records **only
a pass**, and treats an unreadable, unwritable or mismatching record as no record. An
edited, truncated or swapped sibling has a different key and is always tested again; a
failing one is refused and re-tested on every call. Fail closed is untouched — the saving
is the only thing a broken cache can cost. `tests/selftest-reuse.test.sh` pins each of
those from both sides, driving the real caller with a counting stand-in for its sibling.

## 7. `prune-worktrees.sh` is report-only, and that is load-bearing

It classifies worktrees and prints `git worktree remove` commands; it never deletes. The removal path was deleted in v2 because it had destroyed three running agents' worktrees, and because no first-party mechanism covers this root: native worktree isolation and its retention sweep only reach worktrees the harness itself created, of the **session** repo — measured, see the `worktree-isolation-spike` finding — while loopd's live under `<reposRoot>/_wt` and are created by agents calling `git worktree add`. **Do not reintroduce a delete into THIS script, not even behind a flag**; the auto-mode permission classifier independently refuses bulk worktree deletion, which is the same conclusion reached from the other side.

**THE PROHIBITION IS ABOUT THE SCANNING, NOT ABOUT THE DELETING — and `reclaim-worktree.sh` is a different object.** The v2 incident was an INFERENCE failure: the pruner scans a directory and works out which worktrees look finished, and a fresh dispatch that has not committed yet is identical in git to an already-merged branch. `reclaim-worktree.sh <task-path>` infers nothing. It reads one task's own record — `worktree:`, `branch:`, `target_repo:`, `pr:`, written at dispatch by the thing doing the dispatching — and removes that one path: no scan, no candidate list, no "all finished worktrees" mode. **Exit 0 is the only clearance.** The flag stays forbidden on `prune-worktrees.sh` exactly as before, and every report-only assertion in this repo still moves together — a flag there would be the same inference with an extra argument.

**Thirteen gates replace the inference, and two of them are why this is not the deleted v2 path.**

- **G11 — every URL in `pr:` resolves MERGED through `gh pr view`, and `pr: [ ]` is a REFUSAL.** The pruner reaches `REMOVABLE` on merged **or closed**, so delegating to its set would auto-delete the worktree of an abandoned PR — the one most likely to hold the only copy of unpushed work. And "every PR recorded has merged" is vacuously true of an empty list, so a task hand-set to `done` with no PR must refuse rather than clear. Checked by URL, never by branch name: a recycled name once carried an old merged PR onto a live worktree.
- **G12 — no ignored content outside an exact-match cache allowlist**, because `git worktree remove` does **not** refuse it. Measured on git 2.50.1: a worktree holding only an ignored `.env` is removed with rc=0 and the file goes with it — `git status --porcelain` never sees it, so the clean-tree gate cannot either. `git ls-files -o -i --exclude-standard --directory` must come back empty apart from the allowlist, matched exactly on the first path component so `.envrc` cannot ride in on `.env`. `prune-worktrees.sh` carried the opposite claim in a comment until 2026-10-03.
- The rest, briefly: the task is `done` (never `cancelled`); `worktree:` without `branch:` refuses; the path is inside a configured worktree root and is a registered, unlocked, branch-attached worktree of the recorded repo whose branch matches the record; the tree is clean and fully pushed; a detached HEAD refuses unconditionally; and **G13**, a live process inside the tree, refuses. G13 replaces the `PRUNE_ACTIVE_MINUTES` mtime veto rather than inheriting it — that veto is dead on arrival here, because step 5 loads only for `in-review` tasks, so every fast merge is reflected inside the 120-minute window and no later tick revisits a `done` task.

**No forced removal, ever** — the string does not appear in that script, comments included, and the harness asserts 0 hits. **The accepted cost changes rather than disappearing:** a worktree belonging to a terminal task is now reclaimed by the tick, but everything else — an abandoned branch, a rescued tree, a recycled path, anything the pruner reports that no task record names — still grows the root, and draining those is still a periodic human job.

**The classification guards still matter, because the labels are the product.**

- (a) A branch with **no commits of its own** is always `KEEP`: `git merge-base --is-ancestor HEAD origin/<default>` is true exactly when `rev-list --count origin/<default>..HEAD` is 0, so "already merged" and "fresh dispatch that hasn't committed" are the *same* set with no discriminator — the tie goes to KEEP, and the `branch-recycled-name` fixture is the only thing that sees a regression here (`gh pr list --head` matches by branch **name**, so a recycled name carries an old merged PR). In a repo on GitHub's default merge-commit strategy a *successfully merged* branch is an ancestor and so never reaches `REMOVABLE`; squash-merging repos are unaffected. Note the script treats a **closed** PR as finished too, so a clean branch whose PR was closed unmerged can still be `REMOVABLE` anywhere — the merge-strategy caveat is about merged branches only.
- (b) **Count, never compare** — `HEAD == origin/<default>` is the trap two independent implementations fell into ten days apart, and it breaks the moment anything merges.
- (c) A **detached-HEAD** worktree is never labelled `REMOVABLE`: it has no branch ref, so removing it destroys its only reachability (HEAD + the per-worktree reflog). It reports `RECLAIMABLE` for a human to judge.
- (d) The `PRUNE_ACTIVE_MINUTES` mtime veto must stay **recursive** (an agent editing `src/**` never touches the root's mtime; measured 39 ms on a 664 MB repo), and the caller-side rule survives beside it: the PM reports only when its in-flight count is zero.

Also: `worktreeRoot` is optional, and **every doc naming it must state the fallback** (`<reposRoot>/_wt`), since the seed docs are copied into bundles whose config predates the key. Covered by `tests/prune-worktrees.test.sh` (43 assertions), which lives outside `plugin/` deliberately — everything under `plugin/` ships into every instance, and a fixture harness is not machinery an instance needs.

## 8. `validate-bundle.sh` was scoped by measuring first, and that is the point

Before it was written, three live instances (~570 documents) were checked by hand. That measurement was **partly wrong, and the script found the error**: the hand pass sampled only Objective/Project/Phase/Task and reported **0** enum violations, while `knowledge/` — Finding and Service, never sampled — holds **23** (Findings marked `open`/`active` against `current|superseded`; six Services marked `current`, the Finding enum applied to a Service). It also found **16** documents with no `timestamp`, and **15 of 115** frontmatter cross-references dangling. So both halves earn their place: **referential integrity was the motivating rot, and enum drift turned out to be real too — concentrated exactly where the sample did not look.** The lesson is about sampling, not about enums — `/close-project` removes a project folder by design, and one closure had left 38 dangling `depends_on:` refs across two surviving projects. Two things the v2 plan asked for were dropped on the same evidence: a required **`id`** (the path is already the identifier, so a second one can only drift) and renaming `timestamp` to **`updated`** (OKF names it `timestamp`). Validate only the schema-defined locations — the first version also checked `index.md`, `log.md`, `sources/` and `deliverables/`, and buried 6 real errors under 77 warnings, which is how a validator teaches people to ignore it. `artifacts:` warns rather than fails, because a research task legitimately declares a deliverable before writing it. Covered by `tests/validate-bundle.test.sh` (40 assertions), including the ignored-files property.

## 9. `migrate-bundle.sh` fixes only what has one right answer, and is report-only by default

It repairs the mechanical `validate-bundle.sh` errors — a `Finding` status of exactly `open` or `active` (both mean "still applies") → `current`, a `Service` status of exactly `current` (the Finding enum applied to a Service) → `active`, and a missing `timestamp`, filled from **git**: the author date of the commit that added the file. A missing knowledge `provenance` comes from git too — `machine` only when a `commit-as.sh` role created the file and no other author ever touched it, `mixed` when a person edited it since, `human` for everything else, unresolved included, because a wrong `machine` is the label that licenses a rewrite. **The mapping list is closed**, and that matters: an unrecognised value — a typo, or a lifecycle state nobody has seen — carries a meaning the script cannot read, so normalising it to a fixed value would destroy that meaning while looking like a repair. Held for a human instead.

**Three refusals are the design.** A file git cannot date is skipped, not given an invented date — a wrong timestamp is indistinguishable from a right one, which is worse than the error it replaces. And a **dangling reference is never rewritten**: whether to drop a `depends_on:` depends on whether the task it pointed at finished, and once that project folder is gone the state is unknowable from the bundle — so it belongs in `/close-project` step 6, while the source task is still readable. Default is a report; `--apply` writes. Same reasoning as `prune-worktrees.sh`: a script that edits many files should not be one keystroke from doing it.

Writes through a temp file **beside** the target carrying the target's mode, never `$TMPDIR`: `mktemp` creates 0600, so a rename from there would silently make every repaired document 0600, and a cross-filesystem `mv` degrades to copy-and-remove, where an interruption leaves a half-written file. **Every write is verified after it lands, and a claimed-but-absent write prints FAILED and exits 1.** That guard is there because the script once printed `FIXED` for a write it never made, on a real bundle: `add_field` inserts before the *second* `---`, and a document whose frontmatter never closes has only one, so the insert silently no-opped while the counter incremented. Such a document is now skipped up front — it is malformed, which is a content decision, and `validate-bundle.sh` names it precisely. **A false success is worse than the error it claims to fix**, so treat any silent no-op path here as a bug. Idempotent, and covered by `tests/migrate-bundle.test.sh` (46 assertions, most of them about the refusals).

## 10. The scaffold review is a three-stage chain with a declared fallback, never a skip

`/new-project` step 8 runs `validate-bundle.sh` first (deterministic, free, and the consistency class is exactly what a fresh scaffold gets wrong — an external reviewer re-deriving a dangling path from prose spends a whole session reaching a conclusion `grep` already had), then an **external reviewer** (CodeRabbit or equivalent), then **`qa-reviewer` mode C** when no *usable* external reviewer is available — absent, unauthenticated or erroring alike. Step 8 used to skip to nothing there, which contradicted `SCHEMA.md`'s merge-time gate — that has always read "an external one when the repo configures it, **else the `qa-reviewer` agent**" — and left a project scaffolded on a CLI-less machine with no second opinion at all. **Mode C is not mode B with the PR removed:** there is no PR, no CI and no target repo, so it reads `git diff <pre-commit-sha>..HEAD -- projects/<slug>` and writes its verdict into the project's `log.md`. Because it reads `SCHEMA.md`, it must **not** raise step 8c's by-design findings (empty `acceptance_criteria`, `draft` status, empty `pr:`, committing to `main`) — one of those appearing is a bug in the agent, not a finding to triage. Keep every stage advisory: none of them gates project creation. One environment trap worth keeping documented: CodeRabbit needs a base branch, and a remote-less instance has no `origin/HEAD` to infer one from, so it fails with "Unable to determine base branch" until `git config coderabbit.baseBranch` is set — and falls back to the free CLI allowance regardless.

## 11. The cross-instance board is a writer, three renderers and one deletable, generated file

**…and every piece of that is deliberate.** `write-snapshot.sh` derives `SNAPSHOT.json` at the bundle root from the schema-defined locations; three renderers turn one or more snapshots into a page or a table. Five invariants.

- **(a) Absence is the off switch, and the file is generated ROOT content — never a file under `plugin/`.** The writer rewrites it only when it already exists, `/loopd:init` creates it on the **first stamp only** (`FIRST_STAMP`), and the renderer leaves a snapshot-less instance off the page entirely, with no placeholder. That is the `AWAITING.md` pattern, and putting the file under `plugin/` instead would inherit the `AUTONOMY.md` hazard directly above — machinery is re-linked unconditionally, so a per-instance `rm` comes back by itself.
- **(b) The field list is a data-governance boundary, not a format.** The board's HTML can be *published*, while `AWAITING.md` never leaves the instance, so the snapshot carries strictly less: titles, statuses, an assignee **role**, an awaiting **verb**, an open-question **count**, PR links — never a task `description:`, never a document body, never the **text** of a question or a blocker, never `authorEmail`, never a path outside the bundle (the page names an instance by its directory **name**, not its path). Titles are carried because a board without them is unreadable, which is exactly why the JSON states in its own `_sensitivity` key that it is as sensitive as the task documents it derives from. Read that header before adding a field; `tests/snapshot.test.sh` asserts that no key outside the documented set is emitted, so a field added without reading it fails there rather than on a published page. **One identity field crosses that line by decision rather than by drift**: a project's `owner`, a GitHub *username*. It was on the excluded side until 2026-08-26, when artifact publishing turned out to be **account-scoped** — each human publishes their own board, and a board that cannot say whose project is whose cannot do the one thing it is now for. The reversal is written into `write-snapshot.sh`'s own header instead of being made quietly, because a rule and a behaviour that contradict each other leave the next reader no way to tell which is current; `authorEmail` stays excluded beside it, and the collapse on the other owners' section is ergonomics — their names are in the published HTML either way, and the page says so.
- **(c) Untrusted text, published sink.** Every snapshot string is HTML-escaped at one point, a PR URL becomes a link only on an http/https scheme, the page's only external request is one declared webfont, and its single `<script>` (a clipboard helper) receives nothing from a snapshot — collapsing is `<details>`, not JavaScript. That last clause used to read "zero external requests and no `<script>` at all", which described the kanban `columns` page; that page was rejected by the owner as unreadable and **deleted** on 2026-08-24, so the invariant now names what the published board actually does. Discovery is explicit — named dirs, else `boardInstances` in `instance.config.json`, and **if that key is absent or empty, just this instance** — never a glob, because the script ships in the plugin and serves instances whose workspace layout it cannot know. `build-board.sh` is the one script here that uses `python3` (stdlib), justified in its header: a hand-rolled awk JSON reader mis-handling a quote inside a title is precisely the bug that turns an untrusted title into markup on a published page.
- **(d) A snapshot's TYPES are untrusted too, not just its text, and one drifted instance must not blank the board for the rest.** "Malformed" splits in two and only one half is a parse error: unparseable JSON — or a top level that is not an object, which raises `AttributeError` rather than `ValueError` and so needs its own `isinstance` check — becomes a named "Unreadable snapshot" note, but **valid JSON carrying wrong types** (`"tasks": "many"`, an `"order"` of `"first"`, a non-string `group`) parses cleanly and only surfaces later at an `int()` or a sort comparison, where an uncaught `ValueError`/`TypeError` means **no output file is written at all** — every healthy instance goes down with the drifted one. So every number goes through one `toint()` helper and `group` is forced to `str()`: the bad field degrades to `0` and everything else still renders. Don't reintroduce a bare `int()` on snapshot data, and note that the same reasoning makes portability a correctness issue in the writer — a GNU-only regex escape like `\b` is a wrong *answer* on a grep that lacks it, not an error, so the test keeps a static check that none has come back.

- **(e) The renderers are presentation over a settled contract, and that is what makes each one after the first cheap.** Three now read the same snapshot: `build-board.sh` (an HTML page you may publish), `print-board.sh` (columns in a terminal) and `watch-board.sh` (a local page kept fresh, which reuses `build-board.sh` rather than forking its markup — two pages to keep escaping correctly is one page too many). None of them reads the bundle, so (a)–(d) hold for all of them without being re-implemented. Three things follow. **Escaping is per-MEDIUM, not one shared routine:** a terminal's metacharacters are worse than HTML's, because ESC repaints what the reader has already read and a newline forges a ROW — a board reporting work nobody has — so `print-board.sh` drops every code point in Unicode general category C rather than blocklisting known-bad sequences. **Colour is a TTY property**: piped output carries no escape byte (`NO_COLOR` honoured), or every board redirected into a file or a ticket is corrupted. **A number is never truncated** — narrowing drops whole all-zero columns, naming them, and clips names; a clipped count is a *wrong* number and indistinguishable from a right one. And the watcher's cost is stated in the docs where someone chooses a renderer, not buried: it needs a resident process, which loopd deliberately does not have, which is the same constraint that made munder-difflin's live telemetry unreachable. `fswatch` is probed and never assumed, degrading to a polling loop (`--interval`, default **2** seconds) with `WATCH_BOARD_WATCHER` (`auto` when absent) overriding the probe. The watcher refreshes only **this** instance's snapshot: an earlier version ran the writer in every watched directory, so a watcher started in one group rewrote another group's file every two seconds.

Covered by `tests/snapshot.test.sh` (146 assertions, mostly negative) for the writer and the HTML board, and `tests/board-renderers.test.sh` (155) for the terminal board and the watcher.

## 12. Three loopd behaviours that all exist because a *silent* wrong answer is worse than a loud one

**(a) `push-state.sh`** (a `UserPromptSubmit` hook) restates current instance state every turn, because "told to read `fleet.json`" is not "always knows" — `/loopd:dispatch` is a long-lived session whose context still describes tick one after five ticks, and a stale roster is corrected only by a **newer statement** of the truth, so the injection says out loud that it supersedes any earlier count. It must stay **self-detecting** (silent outside an instance root — it ships in `plugin/seed/.claude/settings.json`, so a version that printed elsewhere would fire on every turn of every unrelated project) and it must **always print inside one, zeros included**, because an absent line is indistinguishable from a broken hook and `in-flight 0` is exactly the correction a session remembering three live dispatches needs. It emits **slugs and task ids only, never task `title:` prose** — that would multiply the per-turn cost for no correlation value — fences them as untrusted data, and caps each list at `PUSH_STATE_MAX` (default 12) while reporting what it dropped.

The sharpest guard in `tests/push-state.test.sh` (84 assertions) is a regression test for a real bug: awk is fatal on a file it cannot open and its stdout is a block-buffered pipe, so **one unreadable task document lost the output for every file already scanned** and the hook printed an authoritative `in-flight 0` — three lines above its own claim to supersede the true count. `collect()` therefore drops unreadable files; treat any path that can emit a **false zero** here as the same class of bug as `migrate-bundle.sh`'s false `FIXED`.

Three later fixes are the same lesson from a different direction, and all three are about values the bundle's own **filenames** carry.

- (i) Every file-derived value is **encoded to one line** in `FM_PROG` — a slug, task id and phase stem are filenames, and both macOS and Linux permit a newline, a carriage return and a tab inside one. Raw, a CR let a directory print `--- END INSTANCE STATE ---` as its **own line**, putting everything after it — this hook's own closing instruction included — **outside** the untrusted-data fence; an LF split an awk record so `mmm<LF>qqq` was reported as `qqq` and, when the surviving fragment began with `-`, `basename` option-parsed it and the whole injection became three lines of usage text; and a TAB collided with the field separator so the project **and** its in-flight tasks vanished from the counts. awk is the **single choke point** for that encoding, because it is the only place file-derived text enters — do **not** add a second sanitising pass over the assembled line, which would mask the very regression the test watches for, and keep the item **surfaced** rather than filtered (the `awaiting-queue.test.sh` rule: a slug you cannot see is a slug you cannot fix). The accepted cost is that such a path no longer resolves on disk, so that project's phase is not looked up.
- (ii) Only the **first** frontmatter `status:` counts, via a per-file flag: printing every match let a document with a repeated key be listed twice, counted twice, and classified from the **later** value.
- (iii) `PUSH_STATE_MAX` is normalised with `$((10#…))` before any arithmetic — the digit check accepts a leading zero and the two uses then disagree, since `[ n -le 08 ]` reads decimal while `$((n-08))` reads octal, so the list was capped correctly while the `(+N not listed)` notice died on an invalid octal digit (and `010` quietly reported four dropped when it dropped two).

**(b) An answered question is moved, never deleted**: it goes from `open_questions` into `answered_questions` as one flat line, `<ISO 8601> · <the entry verbatim>`. Flat, not a nested `{q, a, askedAt}` mapping, because `open_questions` already carries question and answer on one line either side of the ` --- ` delimiter, so *moving* the line preserves both with **zero new parsing** — and the bundle's tooling is bash + awk by contract, which cannot read nested YAML. It is **not machine-read**: `open_questions` emptying stays the only promotion signal (an entry left in both lists blocks the draft forever), and `validate-bundle.sh` deliberately gains **no check** — a free-text list is neither an enum nor a reference, and a "missing delimiter" warning is precisely the noise that file's own scoping rule says buries real errors. `validate-bundle.test.sh` instead asserts the validator stays **silent** on a task carrying the key, so a later noisy check fails there. Because these are human answers that now persist for the life of the repo, every doc documenting the convention carries the **no-customer-PII** caution.

**(c) `maxPrLoc`** (`instance.config.json`, **500** when the key is absent — state that fallback in *every* doc naming it, the `worktreeRoot` rule, since the seed docs are copied into bundles whose config predates the key) makes a PR-opening role agent **propose** a split and open the PR anyway; generated boilerplate, codemods and dense logic all move the real number, so it is never a block and never a review finding.

## 13. A shared instance is three no-ops and one gate

The gate is on the wrong verb if you get it backwards. The full reasoning — ownership resolution vs. comparison, why `defaultOwner` must stay tracked-only, the per-instance `people` map, the per-machine override set, and the derived-index split — lives in **[docs/sharing.md](sharing.md)**, because it is one topic and splitting it would leave half the argument on each side.

## 14. `knowledge/references/` is the fifth knowledge kind

**…and promoting it was a two-line change because the location filter was never a list of four names.** `validate-bundle.sh` collects `knowledge/<kind>/*.md` as a *shape*, so the one live instance's 7 `type: Reference` documents were already being checked for `type`, `timestamp` and dangling refs — measured, 0 findings. The only gap was `status`, unchecked because `Reference` had no enum, which left invisible exactly the drift class the script was built for (one type's enum applied to another: `open` on a Reference reads as a Finding). So the fix is `Reference) echo "current superseded"` plus the `SCHEMA.md` section — all 7 already carry `current`, so it is a no-op on live data and a real check on the next edit. Declaring the enum also makes `status` **required** there; root documents typed `Reference` (`SCHEMA.md`, `AUTONOMY.md`) carry none and are unaffected, because they sit outside every schema-defined location. Relocating those documents into `findings/` was rejected: they are specs and contracts, not one decision each, and moving someone's content to satisfy a validator that already reads it is the wrong direction.

## 15. The config layer is one tier, and the arrow stays one-way

**loopd depended on a separate repo for four things, and all four failed silently.**
The measurement that forced this: **nine** top-level entries of the live `~/.claude` were
symlinks into that other checkout, so "it will never be used again" was false on the very
machine running loopd — it was the parent config layer of every session, instances
included. Four of those entries were load-bearing here: the `@~/.claude/claude-defaults.md`
import in `plugin/seed/CLAUDE.md` (the hard one — every new instance inherited it), and probed
lookups for `code-architect`, `deep-bug-scan` and `plan-architect`. A missing `@import` is
a **no-op** and a failed `test -f` merely skips a fan-out, so on a machine that never ran
that installer an instance lost its session defaults, `qa-reviewer` lost its second opinion
and the PM lost its plan critic — and nobody could tell. **Silent degradation is the worst
shape a failure can take**, which is the whole argument for folding the layer in.

**The import is INLINED, not re-pointed.** An `@import` is loaded at launch anyway, so a
separate file bought organisation rather than context — and it bought one more thing that
could dangle. The section now lives in `plugin/seed/CLAUDE.md` itself. Seed content is copied only
when absent, though, so an instance stamped earlier keeps the dead import forever:
`/loopd:init` reports it with the exact replacement and **never edits `CLAUDE.md`**, which
is instance data the human owns and has very likely edited around. Report-only, the same
contract as `RETIRED`.

**One tier now, and it ships only what loopd itself needs.** `config/required/` — the
three agents (`code-architect`, `deep-bug-scan`, `plan-architect`) loopd's own role
agents probe for with `test -f` — is the entire config layer. `config/opinionated/`, the
second tier this section used to describe (one person's commands, output style, hooks and
scripts, the only place in this repo a company's internal tool could be named — `/dave`),
is **gone**: it was a fork of `ai-setup`'s `.claude/` tree, 24 of its 26 installable
entries collided with ai-setup's own, 14 had diverged in both directions, and ownership was
decided by whichever installer ran last. `ai-setup` now owns
`${CLAUDE_CONFIG_DIR:-~/.claude}` outright and received every fix the fork had made that it
lacked; see [`docs/claude-config-ownership.md`](claude-config-ownership.md) for the full
accounting. **Deleting the tier is still safe** — the `AUTONOMY.md` pattern applied to the
one directory that is left, with `--config` linking whatever files remain and erroring
nowhere. (Deleting `config/` *itself* is a different thing and exits 2: a refusal to do
nothing, not a breakage.)

**"Deleting the tier" means removing the DIRECTORY, and the distinction is now load-bearing
rather than pedantic.** `--config` retires a link by asking whether its target is still in
the discovered source set, so an *empty* set reads as "retire everything" — and a source
directory that cannot be listed produces exactly the same empty set as one that is gone.
Measured on a real upgrade fixture, three permission modes, all identical: **exit 0, every
link retired including the ones this layer still ships, none left, no warning**, and the
quietest mode printed nothing on stderr at all. Keeping `find`'s exit status does not close
that: `find . -type f` in a directory that is unreadable but executable exits **0** with no
output. So the guard is stated over the two sets instead — *discovery returned nothing while
links into `config/` still exist* ⇒ **refuse, name it, exit non-zero, retire nothing** — and
a tier directory that is **absent** is what distinguishes the legitimate `rm -rf
config/required` from a tier we merely could not read. A tier emptied but left in place
therefore lands on the refusing side, and says so: remove the directory, or run
`--config --uninstall`, if that is what you meant. A second refusal covers the case the set
statement structurally cannot see — one unreadable subdirectory among several readable ones
still yields files, so the set is not empty while the links beneath it read as dangling.

**The arrow stays one-way, and that is what makes this modular rather than merely
bundled.** `plugin/` must never *require* `config/`: the role agents keep probing with
`test -f`, so an instance stamped on a machine that never ran `--config` still works — it
loses `qa-reviewer`'s Opus **escalation** (the cheap `/code-review low` second opinion needs
nothing installed) and the PM's plan critic, not a feature. The bare `/loopd:init <dir>` interface is unchanged
for the same reason: three live instances and `/loopd:welcome fix` call it that way, so
`--instance` is only its explicit spelling and never a new requirement.

**No drop-in directory is ever linked as a directory.** `agents/`, `commands/` and
`skills/` receive new subdirectories from skill and plugin installers at any time, so a
whole-directory symlink aims them at this checkout and every drop-in lands inside a public
git repo. Not hypothetical: it is how four uninvited skills got committed to `ai-setup` on
2026-08-22, three of them symlinks to a path that existed under `~/.claude` but not in the
repo — dead links its installer would then have pushed into every consumer's config dir.
Two fixes were available: carry that repo's `.gitignore` allow-list (`.claude/skills/*`
denied, one `!` per shipped skill) plus its test, or link per **file**. **Per-file linking
was chosen because it removes the hazard instead of policing it** — nothing this installer
creates is a directory link, so a drop-in cannot reach *this* checkout at all and no
allow-list has to be maintained as skills come and go. It does not make every directory in
the config dir real: `ai-setup` links `~/.claude/agents` as a unit, so on a machine that ran
its installer the parent of our three agents is a symlink, which is why (a) below is a
conditional refusal rather than a flat one. It also
gives back the slot the allow-list approach costs: a personal global command can live in
`~/.claude/commands/` beside the linked ones, which a whole-dir link makes impossible.

**A conditional refusal, a retired guard, and an abstention complete it.** (a) `--config`
never writes *through* a symlinked directory — if `~/.claude/agents` is a link into another
checkout, writing `agents/x.md` would create a file **inside that other repo**, silently,
and leave the config dir with nothing of its own. The answer depends on whether the entry
already resolves through that link, and both halves matter: `ai-setup` links
`~/.claude/agents` as a whole directory, so a symlinked parent is **the normal
configuration** on any machine that ran its installer, not an error. When the path resolves,
that provider is shipping it — the required tier's contract is that the file EXISTS on this
machine, not that our copy is the one used — so it is **reported and nothing is written**,
exit 0. When it does not resolve, nobody ships it and we cannot write it: refuse, name the
directory, print the `mv` that fixes it, exit non-zero. Refusing in *both* cases would make
`--config` fail on the normal setup and make the two installers order-dependent, which is
the whole thing this split removes. (b) The old refusal for two tiers declaring the same
relative path — whichever ran second would move the first aside as a `.bak` and shadow
it — is **gone**, not because the risk went away but because it cannot fire any more: there
is one tier. What holds the invariant now is `tests/config-ownership.test.sh`, which derives
the whole shippable set from the `test -f` probes in `plugin/` and cannot name the tier
directories it scans, with the tier names pinned separately against `/loopd:init`'s own
`CONFIG_TIERS` in both directions — so a second tier could not reappear here unnoticed, under
its old name or a new one. (c) **`settings.json` is not this layer's file at all.** It is not
shipped, not linked, not backed up, not merged, and not reported on; `tests/config-layer.test.sh`
asserts a real one is left untouched and **not even mentioned**. It is the one path in the
config dir that can already hold permissions, env vars and plugin choices somebody tuned by
hand — the only place where writing a value could widen what Claude is allowed to *do* rather
than how it reports — so two installers writing it is exactly the collision the ownership
split removes. `ai-setup` owns it, including the display-only merge into an established real
one, and — from [`ai-setup#71`](https://github.com/cbmono/ai-setup/pull/71), which lands
before this change for exactly this reason — it **adopts a `settings.json` that is a symlink
into some other checkout**: a symlink holds a path rather than a file, so there is nothing
of the human's there to protect, and declining left the path installed by nobody once this
layer retired its own link. Stated with the source because the tense matters: *before* that
change ai-setup declined, and this is the sentence a reader would otherwise use to conclude
the loss cannot happen. `tests/config-ownership.test.sh`'s cross-repo group runs ai-setup's
own installer from that starting state and fails if it declines, so the claim is checked
against the code rather than asserted here. `--config` therefore stays purely additive — every write it makes is a symlink it
created itself — and the paths it retires are not left unexplained: it names `cbmono/ai-setup`
as where they went.

The worktree guard covers both halves, because it runs before the flags are parsed — a
config install from a worktree fails identically, every link pointing into a checkout that
is about to be deleted. Covered by `tests/config-layer.test.sh`.


## 16. The kill switch is one hook, and it fails open

loopd could dispatch a role agent but not **redirect or cleanly stop** one. A bad
dispatch ran to completion or was killed, and a kill mid-worktree leaves the worktree and
its index in whatever state the agent had reached — which nothing then cleans up, because
`prune-worktrees.sh` is report-only ([7](#7-prune-worktreessh-is-report-only-and-that-is-load-bearing)).
With `AUTONOMY.md` present an agent commits, pushes and merges without asking, and the
only counter-metric is `/audit`, which is retrospective and slow-cadence. So the missing
piece was a **live** one: `plugin/hooks/agent-control.sh` (a `PreToolUse` hook) plus
`scripts/control.sh` (the operator side), supporting `gate`, `steer` and `halt` against
one agent. The two halves install separately — the operator script is instance machinery
`/loopd:init` stamps, the hook ships with the `loopd` plugin — so arming an instance
whose plugin is not installed writes directives nothing reads.

**It is keyed on `agent_id`, and that was measured rather than assumed.** A spike proved
two things: `PreToolUse` *does* fire for a dispatched subagent's own tool calls, and the
payload carries `agent_id` / `agent_type` on the subagent's event while the parent's
`Agent` call carries neither. The trap it closed is the important half — **`session_id`
and `transcript_path` are IDENTICAL for parent and subagent**, so a design keyed on
either would silently have been all-or-nothing: halt one agent, lose the human's own
session with it. Two properties follow and both are load-bearing: the *presence* of
`agent_id` is the parent-vs-subagent test with no heuristic, and an absent `agent_id`
therefore means **exit 0 immediately** — this hook can never gate the parent. There is
deliberately **no all-agents wildcard**, because it would reintroduce exactly the failure
the measurement exists to have avoided. This is the third scoping assumption in the
project to have been wrong (native worktree isolation, `paths:` globs, nearly this one),
so treat "does this identifier distinguish what I think it does?" as always needing a
measurement.

**Absence is the safe default, and the state deliberately lives nowhere in `plugin/`.**
No `.claude/control/` directory ⇒ the hook is a strict no-op: no read, no write, no
output, exit 0. That is the `AUTONOMY.md` idiom
([4](#4-a-capability-some-deployments-must-not-have-should-be-one-deletable-file)), but it
could **not** be a file under `plugin/`, because machinery is re-linked unconditionally
and a per-instance `rm` would come back by itself. The directory is runtime state that
`control.sh arm` creates and `disarm` removes. It carries a `.gitignore` holding a single
`*`, which ignores every file in the directory **including itself**, so git sees the
directory as empty and tracks none of it — and that is not cosmetic: committed, this state
would travel to another clone of a shared bundle and gate that human's agents from a file
they never wrote. Doing it that way also keeps the whole feature out of `/loopd:init` and
out of `plugin/seed/.gitignore`, so it behaves identically on an instance stamped today and one
stamped a year ago, with no installer run and no seed delivery.

**Fail open, loudly — this is the one place where a refusal is the worse error.** The hook
sits in front of *every* tool call in *every* session of the instance. No `jq`, an
unparseable payload, an unreadable or malformed control file, a verb it does not
recognise: all of them log and **let the call through**. A hook that blocks work because
its own state file is corrupt is worse than no hook. The exit code is never used to signal
a refusal (exit 2 would block); a refusal is JSON on stdout and the script's only exit
status is 0. `set -e` is deliberately absent — with it, an unexpected non-zero becomes a
"non-blocking error" printed on every single tool call for no gain. An unrecognised verb
is the sharpest case: it carries a meaning the hook cannot read, so honouring it as a
denial would be inventing one, exactly the closed-mapping reasoning
[9](#9-migrate-bundlesh-fixes-only-what-has-one-right-answer-and-is-report-only-by-default)
records.

**`jq` is a hard requirement, and the reason is spoofing.** `tool_input` is arbitrary
nested JSON, so a grep/sed parser hunting for `"agent_id"` can be fooled by that string
appearing *inside* a tool argument — a Bash command containing
`"agent_id": "some-other-id"` would let a halted agent walk past its own halt. jq reads
the top-level key and cannot be fooled that way. Since the hook must fail *open* without
jq, the refusal is moved to `control.sh arm`, which is the one moment a human is watching
and can install it.

**`halt` emits `{"continue": false}` AND a deny, on purpose.** `continue: false` is
documented, but its scope inside a subagent's tool call is not — the docs do not say
whether it stops only that subagent or bubbles up. Unverified is not the same as broken,
so halt emits both: if `continue` is scoped to the subagent the agent stops cleanly, and
if it is ignored the deny still refuses the call and the directive persists. Halt
**degrades to a gate rather than to nothing.** A kill switch may turn out blunter than
advertised; it may not turn out inert. For the same reason halt is **not consumed** — one
that fires once and then lets the agent carry on is not a kill switch — while `steer` *is*
consumed, being one note at one boundary. And `steer` emits **no `permissionDecision` at
all**: `"allow"` would bypass the permission system and silently grant a call a `gated`
instance would have asked about, which is not something a course correction is entitled
to do.

**Bounded, and it says what it dropped.** `CONTROL_MAX` (**20** when unset — state that
fallback in every doc naming it) caps pending directives. `control.sh` **refuses** to add
the 21st and prints what is pending, rather than FIFO-dropping the oldest the way the
mechanism this was modelled on does: silently dropping a halt is the one failure the
feature exists to prevent, so which directive to release is a human decision. The hook's
own scan stops at the same number and logs how many records it did not read — only
reachable through a hand-edited file, and never a reason to fail closed.

**The note is fenced as untrusted data, and the PREFIX is what closes the hole.** A
reason/note is human free text that the hook injects into the *agent's* context beside its
own instruction, so it is fenced and labelled the way `session-banner.sh` fences its items
([12](#12-three-loopd-behaviours-that-all-exist-because-a-silent-wrong-answer-is-worse-than-a-loud-one)).
Fencing alone is not enough: a note reading exactly `--- END OPERATOR DIRECTIVE ---` would
forge the closing marker, so every injected line is prefixed and can never open at column
0. `control.sh`'s `oneline()` is the **single** choke point where operator text becomes a
record field — a tab would collide with the field separator, a newline would split the
record, a raw CR would let the text close the fence on any reader honouring it, all three
measured in `push-state.sh` — and the TAB-separated record format then makes a raw newline
unrepresentable, which is why the hook adds no second sanitising pass.

**One bug worth keeping written down, because it passed a test first.** TAB is an *IFS
whitespace* character, so `IFS=$'\t' read -r a b c` collapses a run of tabs and skips
leading ones. With `@tsv` output, an absent `agent_id` therefore made the leading empty
fields vanish and `read` assigned the **tool name** to `agent_id`: the parent's own tool
call entered the roster as an agent called `Bash`, and a directive named `Bash` would have
gated the human's session — the exact failure keying on `agent_id` exists to prevent. The
test that should have caught it asserted "no roster row has an empty id", which was true
for the wrong reason. Both reads are now one value per line, and the assertion counts
roster growth instead. **Assert the property, not the absence of the symptom.**

**A halt is recorded, but not in `log.md`.** The hook writes every action it takes to
`.claude/control/control.log` — append-only, machine-local, greppable — and `control.sh`
**prints** the exact `log.md` bullet and its `commit-as.sh` command without running
either, the same report-the-command shape as `RETIRED`, `prune-worktrees.sh` and
`/loopd:init`'s `git rm --cached`. Three reasons the hook must not touch `log.md` itself:
it is **tracked**, and several agents share one working tree, so a spontaneous diff there
is absorbed under the wrong author by whichever sibling stages `log.md` by name next
(`commit-as.sh`'s whole header is about that); a correct entry is newest-first under a
dated heading, so it is a read-modify-write that two concurrent halts corrupt; and a hook
that can damage a tracked bundle document while its own state is fine is worse than one
that writes somewhere local. Whether a halt belongs in the bundle's permanent history is
also a judgement — a fat-fingered dispatch and an agent pushing to the wrong repo are not
the same event.

**Two honest limits.** A halt takes effect at the agent's **next tool call**: it does not
interrupt a command already running, and an agent making no tool calls is not reached.
And the roster only fills while armed, so an agent dispatched on a disarmed instance has
its id recorded nowhere — which is why arming is a separate act worth doing before you
need it. **No cost-velocity circuit breaker was built**: that escalation ladder needs a
resident process to run its beat, and loopd has none.

**One breaker does exist, and it needed no beat — the doom loop.** Same tool name, same
argument fingerprint, N consecutive times for one `agent_id` is a `deny` naming the tool
and the counter; N is `maxRepeatedToolCalls`, and **absent from both config layers it is
off**, so nothing is hashed, counted or written. It rides this hook because the hook
already sees every call with an `agent_id`, and it needs no beat because every event it
counts is one it was being handed anyway. Three properties are deliberate. The state is
one file per `agent_id` under `.claude/control/repeats/`, carrying a **fingerprint and
never the argument text** — a command line holds tokens, and machine-local state outlives
the session. A **read-only wait is not a loop**: `gh pr checks`, `gh run view|watch|list`,
`gh pr view` and `sleep` are transparent to the counter however often they repeat, which
is the difference between an agent watching CI and an agent stuck — as the WHOLE command,
since `sleep 1; make test` is a `make test` loop behind a poll's prefix. And the config read is
off the hot path — the limit is cached beside the counters, refreshed when a config file
is newer **or** when the cached answer is over a minute old, because `-nt` cannot see an
edit that lands in the same mtime second. The counter is dropped by the **`SubagentStop`**
registration of this same script, and an orphan expires by age, so a crashed agent leaves
nothing. The hook still writes no task document: the breach lands in `control.log` and the
next `project-manager` tick maps the `agent_id` to a task, writes one `# Notes` line and
emits at most one queue row.

**A second breaker with no beat either — the wall clock.** The doom loop catches an agent
that has stopped making progress; on 2026-09-13 a whole wave ran over an hour while
progressing, and nothing in the harness could say so or stop it. `maxAgentMinutes` is that
bound: **absent from both config layers it is 45**, so unlike the doom loop it is on by
default on an armed instance, and `0` is how you turn it off. Past the budget the agent's
next tool call is a `deny` whose text is the whole instruction — commit and push what you
have, open or update the PR, report — and the **allowlist is what makes that report
honest**: `Read`, `Grep`, `Glob`, `SubagentHandback`, and a `Bash` made only of `git add|commit|push`,
`commit-as.sh`, `cd` and `gh pr create|edit|view|checks`, joined by `&&` or `;`; `Edit`,
`Write` and every other `Bash` are refused. **That `Bash` is scanned quote-aware**, because
until 2026-09-29 it refused any `(` or newline anywhere, so `git commit -m x` was the only
commit it admitted: a scoped message, a heredoc and `commit-as.sh` were all denied, and a
73-minute tick lost four finished files it could not commit. **The budget is per role**
(`roleMinutes`, merged per role): the `project-manager` walks the whole bundle, so its
absent-key budget is **180**, not the role agents' 45 — measured ticks ran 73 and 121+
minutes with no critique in flight, so the walk, not the critiques, outgrew 45. The clock
starts at the **`SubagentStart`** registration of this same script, which writes
`.claude/control/agents.d/<agent_id>.started`, and **nothing else**: no record ⇒ the cap is
off for that agent and `control.log` says `clock-unknown … elapsed=unknown`. **The transcript
is never a clock** — it is the parent session's, so until task-029 every handback was capped
at the session's age (14,439 minutes, identical for two agents 18 seconds apart). The stop
event **parks** the record rather than deleting it, because a stop is not terminal when the
harness re-prompts an agent to hand back; the next `SubagentStart` restarts it, so a
**resumed** agent is given a fresh budget rather than an expired one. `SubagentHandback` is
allowed past the cap, because refusing it refuses the very report the cap asks for.
Same reflection path as the doom loop: `agent-cap` in `control.log`, one `capped: <minutes>`
line on the task at the next tick.

Covered by `tests/agent-control.test.sh` (299 assertions, most of them refusals).

## 17. An instruction addressed to an agent is executable only if that agent *holds* the tool

**Possession, not installation — and the difference is invisible in the prose.** A `tools:`
allowlist lives in frontmatter the instruction never mentions, so `CONVENTIONS.md` read
perfectly for months while telling `software-engineer` to "dispatch `code-architect` **if
it's installed in `~/.claude/agents/`**". `code-architect` *is* installed, so the condition
evaluated **true** — and `software-engineer` holds no `Agent` tool, so the branch it chose
could not run. That is the worst shape a defect can take: **it reads as satisfied.** Three
more sat beside it (`Workflow` in `auditor.md`, `qa-reviewer.md`, `software-engineer.md`;
`EnterWorktree` in `CONVENTIONS.md`), and a condition on *installation* can never detect
the thing that decides the outcome. So: **never write an instruction that depends on a
tool absent from the addressed agent's `tools:` list, and never condition on what is
installed when what decides is what is held.** Three consequences worth keeping. **For a
shared doc the addressed agent is a SET, and the constraint is the intersection** — an
instruction in a doc read by four agents must be executable by all four, or the same
sentence silently means two different things. **Stating an absence beats deleting the
mention**: deleting is cheaper but loses the reason and the clause comes back, so name the
missing tool *and* the route to take instead — which is also what makes it checkable.
**Widening an allowlist is a standalone decision**, never something a convenience clause
settles; `Workflow` is in no role agent's list and stayed out, with the honest statement of
absence written in its place. Enforced by [18](#18-the-tool-allowlist-check-is-pinned-from-both-sides-and-silence-is-a-failure).

## 18. The tool-allowlist check is pinned from both sides, and silence is a failure

**…because the first version of it failed in exactly the shape it was built to catch.**
`tests/agent-tool-allowlist.test.sh` matches a **backticked identifier** from a tool
vocabulary — backticks are already how this codebase means "the identifier, not the word",
and without that restriction ordinary English ("never *write* to the bundle", "the *agent*
roster", "*workflow* structure", "the *task* document") fools the sweep. `Task` stays out
of the vocabulary on purpose: OKF's own document type is `Task` and the bundle backticks it
constantly, so including it would flag the core vocabulary and earn the check a deletion.
Four things then make it hold, and each exists because the version without it was measurably
weaker.

- **(a) The vocabulary is pinned from BOTH sides, because a closed list leaks silently.** A
  tool missing from it is not treated as prose — it is **invisible**, and the check passes,
  which is indistinguishable from there being nothing to find. `AskUserQuestion`,
  `ExitWorktree` and `Artifact` were all missing at once, and `Artifact` surfaced only
  because a PM tick happened to start granting it. So: every tool a shipped agent
  **grants** must appear in the vocabulary (a new harness tool becomes real here at the
  moment it is granted, which is the one event that cannot be missed), **and** a backticked
  capitalised name that no classification rule recognises **fails as unclassified**. That
  second guard first shipped scoped to *multi-word* CamelCase, on the argument that the
  grant guard covered the single-word residue — and **that argument is false for the case
  that matters most**, which was reproduced rather than debated: `` Use the `Deploy` tool ``
  in an agent body left the harness at 62 passed, 0 failed. The grant guard only ever covers
  a tool some agent **actually grants**, never a hallucinated name granted nowhere, which is
  precisely what a prose-vs-allowlist check exists to catch. So the guard now fires on every
  backticked capitalised identifier, and the 61 legitimate non-tool mentions in the scanned
  set are kept quiet **by rule, not by list** — of FOUR rules, two are derived or
  shape-based: OKF's document types come from `plugin/seed/SCHEMA.md`'s own `type:` headings, so
  a new type classifies itself (43 mentions); an all-capitals name is a literal output token,
  which is a shape and needs no upkeep (17); and a fourth, hand-maintained residual list
  (`NOT_A_TOOL`) covers what neither derivation nor shape reaches. **A hand-maintained list
  of non-tools is the same closed-list problem one level over — except for the direction it
  leaks:** an unclassified name here produces a **build failure** naming the file, the line
  and the routes to classify it, where the closed vocabulary produced **silence**. Noise a
  maintainer fixes is not the same defect as silence nobody can see, and that asymmetry is
  the whole argument for accepting this direction and not the other. Residual, stated because
  it is real: no harness tool has ever been named in all capitals, which is what the shape
  rule rests on and is asserted — so `` `DEPLOY` `` would still be missed where `` `Deploy` ``
  is now caught. **The fourth rule is a recognition route too, and it is not exempt from its
  own asymmetry:** a hand-maintained list can rot silently the same way `VOCAB` did if an
  entry is added before anything actually names it — which happened. The whole Claude Code
  hook-event family was pre-populated into `NOT_A_TOOL` (11 names) on the argument that "the
  next one documented must not break the build", and a live check against the real tree
  found **9 of the 11 had zero backticked mentions anywhere in `plugin/`, `.claude/` or
  `CLAUDE.md`** — each a silent classification route for exactly the shape this file exists
  to catch (`` `Notification` ``, `` `PreToolUse` ``, `` `PreCompact` `` and
  `` `SubagentStop` `` were reproduced as invisible against a live head). So the fourth rule
  now asserts what it grants: every `NOT_A_TOOL` entry must be **JUSTIFIED BY A REAL
  MENTION** in that same tree, or the build fails naming the dead entry. The 9 un-earned
  names are gone; two remain, each backed by a mention — `SessionStart` (a real hook event)
  and `Makefile` — and a name can only be added back in the same commit as the mention that
  justifies it.
- **(b) The scanned set is DERIVED, never listed.** Two paths were hardcoded, so the check
  could only ever look at the two someone remembered — and `plugin/seed/SCHEMA.md`'s
  browser-access section named `mcp__claude-in-chrome__*` to five readers whose allowlist
  intersection is `Bash Glob Grep Read`, unseen. A doc addresses an agent when an agent is
  **told to read it**, so that is what is derived: the `*.md` references in restricted agent
  bodies, resolved against `plugin/` then `plugin/seed/`. Adding a doc reference to an agent body
  puts the doc in scope by itself. `plugin/seed/CLAUDE.md` keeps an explicit override — it loads
  into every session whether an agent names it or not, so every restricted agent is a
  reader and deriving a smaller set would *widen* the intersection.
- **(c) A waiver carries a budget AND has to state the absence — the count is not what
  decides.** Naming an absent tool is often correct (`failure-analyst.md` names `Skill`
  precisely to record that the invocation must not come back), so a file may declare
  `<!-- tool-mention: Workflow(2), Agent(2) — why -->`. A **bare** declaration was measured
  too weak: re-introducing the original defect verbatim still passed, because a per-file
  waiver covers every future mention. The `(N)` budget fixed that. But a budget is a
  **count**, and a count is exactly what a reword holds constant — swap one honest statement
  of absence for a live instruction and it stays green. So the deciding condition is the
  prose, and it is **two-sided**, because requiring a possession cue alone tests only half of
  what the rule says — "states the absence **instead of instructing the use**". The half that
  was missing was defeated **0-for-2** by ordinary prose: "You can author a `Workflow` for
  wide work — the `Workflow` idiom is available … deliberately not written here … granting it
  is a standalone decision" clears on *available*, *not* and *granting* while telling the
  reader to do the forbidden thing. A declared mention must therefore state the absence
  **and** not be governed by a non-negated directive verb in the five words before it. A
  **negated** directive is a statement of absence, not an instruction ("don't rely on the
  `EnterWorktree` tool"), and a verb two clauses away governs something else, so both stay
  green. `only` and `available` were **deleted** from the cue list on the same evidence:
  neither is about possession, both were the masking word in a reproduced counter-example,
  and no real mention needs them. The budget is kept for the different hole it catches (an
  *added* mention) and is no longer what decides. **`if` is deliberately not an absence
  cue** — accepting it would bless the original installation-conditioned defect. A
  declaration with no reason, or a name with no `(N)`, exempts nothing; stale (tool no longer
  named) and redundant (tool actually granted) declarations are flagged so a waiver cannot
  rot into a rubber stamp. Per-mention markers were rejected as too brittle for reflowing
  prose. **Residual, measured not argued:** the directive verb list is a deny list, so a
  mention carrying a possession cue and governed by no listed verb can still read as an
  instruction — "a `Workflow` fan-out is the route for wide work, since nothing else is
  granted" is not caught. It is a second requirement layered on the first, never the sole
  decider, and the task's acceptance criterion was narrowed to exactly that promise.
- **(d) Assert the quiet cases, not only the loud ones.** The four prose words, a backticked
  `Task`, the OKF types, the SCREAMING tokens, the hook-event names, an MCP wildcard covering
  its own prefix and nothing else, a same-count reword that *still* states the absence, a
  negated directive verb — all are fixtures. A checker for this class is only trustworthy if
  "it stays quiet on ordinary English" is a test rather than a claim, and every new guard is
  paired with the input it must reject. **Demonstrate by mutation on real prose, and on more
  than one shape.** One successful mutation proves a mechanism *can* fail loud; it does not
  prove every equivalent mutation does, which is how "one is enough to fail" and "the grant
  guard covers the residue" both got into a PR body and both turned out to be properties of
  the single example that had been tried. Three structurally different rewords of the same
  real `CONVENTIONS.md` sentences are run against this check, each failing, alongside a
  same-count control that must stay green.

**Out of reach from this repo, and stated rather than hidden:** a live instance's own
`CLAUDE.md` is a real file per bundle, not a symlink, so a rule that drifts into it cannot
be checked from here. `plugin/seed/CLAUDE.md` is covered instead and `/loopd:welcome fix` is the route for
existing instances — which is exactly how one instance kept the defective wording after the
template had already been fixed. Any rule duplicated between `CONVENTIONS.md` and an
instance `CLAUDE.md` needs **both** edits, and only the template side is testable. Agents
declaring no `tools:` key (`config/*/agents/`) inherit everything and are skipped — and
that skip is asserted, not assumed, so one of them growing a `tools:` key fails here.
Covered by `tests/agent-tool-allowlist.test.sh` (86 assertions).


## 19. The destructive-action baseline is a hook, and it is narrow on purpose

`permissions.deny` was **empty in all three live instances** while one of them ran 13
projects on `yolo` autonomy holding live production credentials. The gap was never that
nobody had written the rule down — it was that the rule was written as prose, and prose is
a request an agent may decline. `plugin/hooks/deny-destructive.sh` refuses the
tool call at the `PreToolUse` boundary, before it runs: the same category as branch
protection, and categorically unlike a `CONVENTIONS.md` line.

**Why a hook and not `permissions.deny` patterns.** A `permissions.deny` entry matches a
command **prefix**, and every shape worth denying is conditional on something a prefix
cannot see — `DROP TABLE` against a remote host versus a test container, `kubectl delete
pod` versus `kubectl delete namespace`, `rm -rf node_modules` versus `rm -rf` at the repo
root (which depends on the session's cwd), a force-push to a feature branch versus to the
default branch. Written as prefixes each rule is either **too broad**, and gets switched
off — the failure mode of every over-strict lint, and a baseline nobody keeps protects
nothing — or **too narrow**, which is *false comfort*, and false comfort is worse than an
empty list because the instance now believes it is covered. A hook sees the whole command,
the cwd and the repo, so a rule can be narrow enough to keep.

**And it is the only form that can be proven.** A prefix pattern's matching is the
harness's business, so a harness assertion about it would be a re-implementation of the
matcher passing for its own reasons. The hook is a pure function from a payload to a
decision, so `tests/deny-baseline.test.sh` feeds it real payloads and reads the verdict.
`permissions.deny` still carries a short block for the handful of shapes that **are**
unconditional (`rm -rf /`, `terraform destroy`), and every entry in it is deliberately
duplicated by a hook rule, so **nothing depends on the layer that cannot be proven**. An
entry there must be an exact command or a true prefix: `Bash(rm -rf /*)` is a *wildcard*,
and would refuse every absolute-path delete on the machine.

**Both directions, per rule, always.** A rule is only tested when the harness shows the
shape it refuses **and** a neighbouring command — same tool, same verb, one condition
different — that it must still allow. "It denies `kubectl delete namespace`" alone passes
a hook that denies every `kubectl` call, which is the version that gets deleted. The allow
half is the load-bearing half: `psql` against a test container, `rm -rf node_modules`,
`rm -rf "$TMP"`, `terraform plan -destroy`, `git push --force-with-lease` to a feature
branch are what agents here run every day.

**It has to reach the agents it was built for, and for a while it did not.** The guard
keys on `$CLAUDE_PROJECT_DIR/instance.config.json` so that a plugin hook is silent in every
unrelated project. A role agent used to be a subagent of the PM's session, whose project
dir is the bundle; since it became a detached `claude --bg` session launched *inside its
worktree*, its project dir is the worktree, which holds no such file — and the hook fired
and allowed everything. Measured live on 2026-10-04: a force-push to a default branch
landed with the hook's own `PreToolUse` events in the transcript. Nothing was red, because
every probe in `tests/deny-baseline.test.sh` pinned the project dir at the bundle: the
harness modelled the world the hook was written in. The way back is one file,
`<repo>/.git/loopd-bundle`, written by `link-repos.sh` into each linked repo's common git
dir and read only when the project dir is a **linked worktree** (`.git` is a file) — three
reads with builtins, no git process, a human's main clone left un-armed, and a marker
naming a non-instance ignored so "absent ⇒ silent" still holds. The rule it leaves
behind: **a deny test must include the shape production launches in**, not only the shape
the rule was designed in.

**The escape hatch is the human's own terminal, and it is what keeps the rules narrow.**
Every refusal is satisfiable by a human running the command outside the harness, so no
rule ever has to be widened for a legitimate emergency and no instance has a reason to
disable the baseline. The deny message says so, and tells the agent **not** to re-issue a
variant that evades the pattern — without that sentence a guard just teaches rewording.

**Fail open on plumbing, never on a match.** No `jq`, an unparseable payload: log to stderr
and let the call through, for the same reason `agent-control.sh` does ([16](#16-the-kill-switch-is-one-hook-and-it-fails-open)) — a
guard that blocks all work because its own plumbing broke is a guard that gets removed. A
rule that *matches* always denies. A refusal is JSON on stdout and the script's only exit
status is 0.

**Two limits, stated rather than papered over.** (i) This is pattern matching over a
command string. It stops the named shapes, not every route to the same outcome — a path
built from a variable, SQL read from a file, a wrapper script, a language runtime. It
raises the floor; it is not a proof. (ii) **Credentials are the real boundary.** An agent
that cannot reach production cannot harm it whatever it decides, and that audit is
separate, stronger, and not replaced by this list.

**It is not deletable per instance** ([4](#4-a-capability-some-deployments-must-not-have-should-be-one-deletable-file) is the *opposite* case). It was instance
machinery `/loopd:init` re-linked unconditionally; since AI Bridge 2.0 it is a **plugin
hook**, which is stronger for the same reason: one install arms every instance on the
machine, including ones stamped before the guard existed. A safety floor an instance can
`rm` is not a floor.

**Because it fires user-wide, it no-ops SILENTLY outside an instance root.** A plugin hook
runs in every session on the machine, so both enforcement hooks open with the same guard:
resolve `CLAUDE_PROJECT_DIR` — never the payload's `cwd`, since a dispatched agent's cwd is
a worktree of a target repo — and exit 0 with no stdout, no stderr and no state written
unless `instance.config.json` is there. One marker, deliberately: keying on `.claude/agents/`
as well would make the guard fail exactly when the plugin finishes replacing the symlink
farm. Silence is the requirement, not merely the behaviour — a skip line per tool call would
be noise in every unrelated project on the machine, and `tests/deny-baseline.test.sh` asserts
stdout **and** stderr empty rather than only the verdict.

**The plugin/instance double-fire window is ACCEPTED, and no upgrade-lockstep machinery is
added.** During a migration both registrations can be live at once. Measured before
accepting it: `agent-control.sh`'s roster append is dedup-guarded by agent id, so the second
fire finds the id and skips and a roster row cannot be duplicated; only the best-effort
action log gains duplicate lines, which is cosmetic observation. Deny rules double-fire to
identical verdicts at double cost. **A version gate would cost more than the window it
closes** — it is machinery to build, test and later delete, for a condition that resolves
itself the moment the instance re-stamps. Its absence is the design, so a reviewer looking
for one should find nothing.

**The one interval that is NOT covered, and it is the merge decision.** `settings.json` is
itself a symlink into the template, so its registration goes live the moment the template
clone is pulled, while the plugin arrives only when the human installs or updates it. The
instance-side enforcement is therefore removed in the same change that adds the plugin-side,
and between those two clocks there is no baseline from either. (The old `[ -x "$h" ]` wrapper
on the instance registration existed for the mirror image of that skew and did **not** travel:
`hooks.json` and the scripts ship in one package and cannot skew, so the wrapper would only
hide a real packaging error.)

**The 2026-08-31 audit's top finding — "`gated` is enforced by prose, not mechanism" — is
CLOSED, and these are the names that close it.** It measured a tree whose `PreToolUse` rules
matched no `gh` shape at all, so a dispatched agent could self-merge its own green PR, and
whose only push rule (`force_push_protected`) let a plain push to `main` through by design.
Both are hook rules now: **`rule_subagent_merge`** refuses `gh pr merge`,
`gh pr review --approve` and the REST `/pulls/N/merge` and `/merges` endpoints for a caller
carrying an `agent_id` ([#93](https://github.com/cbmono/ai-bridge/pull/93)) — and since
ai-bridge-v3/task-044 the merge half binds every caller in a bundle session, permitting only
the SHA-pinned squash `AUTONOMY.md` delegates, decided by `plugin/scripts/merge-permit.sh`
from the bundle's own mode, the caller's role and a clearance record at that SHA — and
**`rule_subagent_push_default`** refuses a dispatched agent's push to a product repo's
default branch, exempting the bundle the tick pushes by design
([#97](https://github.com/cbmono/ai-bridge/pull/97)). The third strand of the same finding —
a `project-manager` tick running with no dispatch lock — is refused by
`plugin/scripts/tick-lock.sh` at **exit 4** (no lock, no launcher), not by a hook, because
that fact is in the lock file and not in the tool payload. The audit report is a snapshot of
2026-08-31 and still reads as current; on this finding it is not.

Covered by `tests/deny-baseline.test.sh` (135 assertions), and mutation-checked in both
directions: neutering one rule fails 7 assertions, making one unconditional fails 6, and
adding a rule to `RULES` with no test here fails by name.

## 20. The version is a number the MERGE moves, and the drift check speaks only when behind

**There was no version anywhere in this repo until 0.9.1** — no `VERSION` file, no
`package.json`, no string in `README.md` or `/loopd:init`. That was survivable while one
person ran one instance, and it stopped being survivable the week three instances went
seven days missing four scripts with nothing reporting it.

**Why a version at all.** The reasoning was written while an instance still consumed the
template through per-file symlinks: most merges reached it live, so a "commits behind"
counter would have fired for changes that had already arrived. Two kinds did *not* arrive
by themselves, and they were the expensive ones: a **new** file under `plugin/` reached an
instance only when `/loopd:init` ran again — measured twice in one week, `deny-destructive.sh`
([#61](https://github.com/cbmono/ai-bridge/pull/61)) and `tick-lock.sh`
([#62](https://github.com/cbmono/ai-bridge/pull/62)) were absent in all three instances
after merge, and the deny guard was **inert** until stamped — and `plugin/seed/` content is copied
**once, ever**. A number that moves when those move is a signal; a number that moves on
every merge is not.

**A plain `VERSION` file, no extension.** `cat VERSION` — no parser, no dependency, no
format to get wrong, which is the right shape for a repo made of shell and markdown. The
alternatives were worked through and rejected: `README.md` as the *source* means parsing a
heading out of prose (the brittle-grep class this project keeps finding broken); `VERSION.md`
or `.txt` implies a structure that is not there; a `package.json` would exist only to hold
one string, in a repo that publishes no package. **One source, mirrored not duplicated** —
where a doc *displays* the number, `tests/template-version.test.sh` asserts the two agree,
because a version that lies is worse than no version, and this repo has already shipped docs
claiming behaviour the code did not have.

**The bump is made ON MAIN, by the merger, right after the merge — never inside the PR.**
It was the other way round until 2026-09-06, and the reason it changed is arithmetic rather
than taste. The number is **five files**, one of them the shared `docs/operations.md`, so
every open core PR proposed the same number in the same five places: any two of them
conflicted, and each had to land alone after a fresh merge-main and a full suite run. With
seven PRs open that day the version files were the only conflict in **five of six merges**,
at roughly one suite run each, and a user-owned repo cannot have a merge queue to absorb
it. So a core PR now carries **no** version
change at all, and `plugin/scripts/release-bump.sh <major|minor|patch>` — the only writer
of the five — moves them together on `main` afterwards, in one commit the merger pushes **straight
to main** (admin bypass of the required check, which is how this repo is already
configured; main's own suite on that push is the check). **Still not automatic**: no
workflow bumps anything, a human runs the script and decides which field moves: `patch` for a
fix, `minor` for an ordinary merge, and `major` when the owner declares a release — the field
that zeroes both lower ones, so it is the owner's call and never an agent's, and the only one
that also moves the companion plugins (they track core's MAJOR).
There is deliberately **no release process** behind this — no changelog, no tags, no
packaging, no publish step. This repo has one consumer group and one plugin; a
release pipeline here would be exactly the team-scale apparatus `ai-bridge-v4` spent ten
cancellations removing.

**`core` is a closed list of paths, not a judgement call**, because "is this a core change?"
asked of every PR is a question that gets answered "no" by default. Core is what the
installer ships or runs — `plugin/` (which carries `seed/`, `RETIRED` and the shipped
`VERSION`), `config/`, `/loopd:init`, `/loopd:welcome fix` — which is *exactly* the union of the two path-scoped rule files' `paths:` globs
([`.claude/rules/machinery.md`](../.claude/rules/machinery.md),
[`.claude/rules/installer.md`](../.claude/rules/installer.md)), so the rule loads precisely
when an agent opens a file it governs. `tests/template-version.test.sh` asserts that
equality, so the list cannot rot away from the globs that deliver it. Everything else —
`docs/`, `tests/`, this repo's own `.claude/`, `.github/`, the root `scripts/` — is not
core. The list still decides one thing: whether a merge is one the **merger** bumps for.

**The drift check speaks ONLY when behind, and a failure is never "behind".** Equal or ahead
is byte-empty; a line at every session start is wallpaper, and wallpaper is how `AWAITING.md`
rows come to be skipped. Unreachable, unauthenticated, offline, no git, no remote-tracking
ref, no `VERSION` on either side, a version it cannot parse — every one of those is silence
too, for the reason absence is never an error anywhere else in this machinery: a false "you
are behind" trains the human to ignore the true one. The comparison is **numeric field by
field**, so `0.10.0` is newer than `0.9.1` and the string compare that says otherwise is
the one way this could quietly lie. And there is **no network call on the session path** at
all: `scripts/check-template-version.sh` reaches the remote only with `--fetch`, so the
banner reads the remote-tracking ref already on disk, which can under-report and can never
false-alarm.

**What it cannot see, stated rather than glossed:** a template checkout parked on an old
commit whose `VERSION` happens to equal the remote's is invisible. The number moves when
the bump convention says it moves, so this detects drift across a bump and nothing finer —
which is why the convention and the check are one invariant and not two.

## 21. `/loopd:welcome` reports facts that can be false, and `fix` is tiered in code

> Since the plugin replatform, this contract ships as the `loopd` plugin's
> `/welcome` skill (`/loopd:welcome [check|fix]`); the instance command file it
> describes is retired. Everything below still governs the script and the relay.

**The rejected shape first, because it is the one that keeps getting proposed.** The
original ask was a command that *loads the rules* at session start — conventions,
guardrails, "always defer to subagents", "always use the dispatch loop". It was rejected
evidence and must not be quietly reintroduced. The rules are already loaded: `CLAUDE.md` is
injected into every turn and the banner fires unprompted. More decisively, of the failures
measured on 2026-08-30, **not one was caused by a rule not being loaded** — a stamp taken
from a stale template clone that printed `already linked` and changed nothing, three config
keys left uncommitted, an instance configured to call a hook it did not have, a `.tick-lock`
bypassed by a resume. Four invisible states and one missing reader. Reciting rules into
context enforces nothing and costs context every session; two of the proposed lines
(*"always use the dispatch loop"*) even contradict `plugin/seed/CLAUDE.md`, which says
ad-hoc work must
**not** go through the loop.

**So every line the command prints is a fact that CAN BE FALSE, with its evidence.** If a
line would read the same on a healthy instance and a broken one, it does not belong there.
That is the test to apply to the next line somebody wants to add.

**The bare form INVOKES the banner; it does not reprint it.** `/loopd:welcome` `exec`s
`session-banner.sh`, because its whole purpose is that a long session scrolled the real
banner out of view — and the moment the two print differently, the form is a lie about what
the session was told. `tests/welcome-command.test.sh` asserts byte-identical output, so a
header or a courtesy blank line fails the build.

**What it may decide is the RENDERING, and nothing else.** The one thing this form knows
that the hook cannot is who is about to read the output: a pipe here is the Bash tool, and
what comes out of it is relayed into an assistant message that renders markdown and destroys
ANSI. So with no arguments, no `NO_COLOR` and stdout not a terminal it asks for the hook's
third rendering (`--format md`), whose only difference from the plain text one is `**…**` on
the identity line and the two table headers; a terminal gets the bare form. It also asks for
`--no-logo` on both of those branches: the ship renders on the SessionStart channel alone,
because a relayed copy is markdown, which drops the leading space of the ship's first line
and carries none of its colour — the human was reading a second, shifted ship under the Bash
tool's own output. The byte-identity
assertion is then against the hook *in that same rendering* — the form still adds not one
byte of its own, and any argument at all leaves the decision alone, because the flags belong
to the banner. It is the same ladder `--style` resolves for `check`, `NO_COLOR` first.

**`check` and `fix` read ONE list, and each row declares its own tier.** Two lists drift —
the checker learns about seven things, the fixer about five, and the gap is silent — so
`fix` does not know the name of a single check: it walks the same rows and dispatches on
the declared tier. Adding a check is one edit in one place. The banner's filter is a third
column on the same row rather than a name in the hook, for the same reason.

**The three tiers are a risk classification, and collapsing them is how this becomes
dangerous.** `idempotent` (pull the template clone, re-stamp) is repaired; `ambiguous` and
`human` are printed and never acted on. The two that must never be repaired have live
evidence behind them, and both are enforced structurally — the functions do not exist, and
the script **refuses to run at all** if one is ever added:

- **Uncommitted config is a QUESTION, never a defect.** An instance carried an uncommitted
  `maxPrLoc: 2000 → 500` that was a deliberate decision by its owner, taken minutes
  earlier and indistinguishable from drift to anything reading only the file. A `fix` that
  reverted it would have destroyed that choice while printing a success line.
- **A stale `.tick-lock` is not a dead one.** `scripts/tick-lock.sh release` is documented
  as the human's override. A tick that dispatched role agents can legitimately run long, so
  "stale" is a threshold, not a death certificate — and clearing a lock on that evidence
  re-opens the double-dispatch that ran two ticks concurrently for 34 minutes on
  2026-08-29.

**Wiring `check` into the SessionStart hook is what turns a Finding into a mechanism.** The
trap it was built for — pulling the template half-upgraded every unstamped instance, because
an edit to an already-linked file arrived on the pull while a *new* file waited for a stamp —
had no reader at all: it was prose someone had to remember to apply. On that path the
section prints **byte-nothing** when the instance is healthy and at most two lines per
failing check when it is not: the verdict and the one command that addresses it. The bound
is deliberate. The banner has a measured line budget, and a section that grew with the
number of affected files would blow it exactly when the banner most needs to be read.

**What the on-disk inventory answered that the git diff could not — and why that row is now
gone.** While a stamp still delivered machinery, the post-merge question was `git diff
--name-status <old>..<new> -- symlink/ | grep '^A'`, and `--since` ran exactly that. But
**no instance ever recorded `<old>`** — there was no stamp receipt anywhere in this
machinery — so from inside an instance that range could not be built. The equivalent that
could always be answered was "which of the files a stamp *would* link are not linked here",
enumerated with the same `find` the installer walked, so the two could not disagree about
what a stamp covered. **A bundle has carried no machinery since the plugin replatform**, so
the question has no answer left to give: the `unstamped-machinery` row is retired and
`--since` is parsed and then dropped, kept for one version so a saved command line does not
become a fatal unknown argument (`plugin/scripts/welcome.sh`). What it leaves behind still
governs every other row: **empty output is a reported answer**, never silence.

---

---

## Repo conventions that are not invariants

- **Test harnesses live in `tests/`, never under `plugin/`.** Everything under `plugin/` ships into every instance, and a fixture harness is not machinery an instance needs.
- **CI runs the whole suite as one required check named `harness suite`, through the same script you run locally.** [`.github/workflows/tests.yml`](../.github/workflows/tests.yml) calls [`tests/run.sh --ci`](../tests/run.sh) — the selection and the runner live there, the workflow carries no copy of either (`tests/ci-workflow.test.sh` fails if it grows one), and `tests/run.sh --changed` takes the identical selection on your machine. It runs every `tests/*.test.sh` on each PR against `main` and each push that lands on it, on `macos-latest` — the platform this suite's baseline was actually measured on (a first Linux run failed four harnesses for environment-specific reasons; fixing those is its own task, not something to absorb silently). **The job name is a merge-gate contract**: `main`'s branch protection requires that exact check and is **strict** (a branch must be up to date with `main` before it merges, so expect a rebase when a sibling PR lands first), and [`.github/required-checks.txt`](../.github/required-checks.txt) declares the same name for the fallback `required-checks.sh` uses only when the platform reports no required set at all ([invariant 6](#6-the-delegated-merge-gate-resolves-its-required-checks-in-required-checkssh-and-exit-0-is-the-only-clearance)). Renaming the job means editing that file and the branch-protection rule in the same commit. The workflow does not trust the suite's own tally either: a harness with a broken `TMPDIR` guard can delete its own checkout and still print `fail=0`, so it re-verifies the checkout after every harness and stops at the first that damages it.
- **A harness must give the same answer from a linked git worktree.** Every role agent works in one, and the installer used to refuse to run from one — so harnesses that handed it the checkout's own copy stamped nothing and then failed downstream for reasons unrelated to the change under test (six of them, across `ai-bridge-v4` tasks 029-031). **The refusal narrowed to `--config` in ai-bridge-v2/task-013**, because a bundle stamp no longer writes any symlink into this checkout and so has no hazard left to guard; `--config` still links into `${CLAUDE_CONFIG_DIR:-~/.claude}` by absolute path, so there it stands. `tests/worktree-suite-parity.test.sh` pins **both halves at once**: those harnesses cope from a fresh linked worktree, a bundle stamp from that same worktree is allowed and leaves no symlink behind, **and** `--config` still refuses there — so neither half can be quietly traded for the other. Since 2026-10-05 the first half is no longer seven re-runs (229 s, 5.6% of a 23-minute suite): every listed harness is checked to stamp only through its routing block, that harness's own block is executed against the worktree, one harness still runs there end to end, and mutants prove each check can fail — the file's header says what that trade gives up.
- **Harness growth is a threshold you measure against your own diff, not a test.** `git diff --numstat origin/main -- 'plugin/**/*.sh' | awk '{a+=$1} END{print a+0}'` — at or above ~150 added lines, name the figure in the PR body as one `⚠️` line and let the owner decide ([`plugin/seed/CONVENTIONS.md`](../plugin/seed/CONVENTIONS.md) carries the rule and the scale behind the number). This replaced `tests/machinery-ceiling.test.sh` (944 lines, retired in [#45](https://github.com/cbmono/ai-bridge/pull/45)): pinning integers on `main` made every PR touching `plugin/` re-measure and collide with PRs it had nothing to do with, while a threshold checked against your own diff cannot collide with anyone else's. Same measurement, none of the coupling.
- **`paths:` globs are only root-anchored with a leading slash.** Write `/plugin/**`, not `plugin/**`: a bare pattern matches that basename in *any* directory, and a trailing `/**` is not anchored either. Measured against Claude Code v2.1.239 with an `InstructionsLoaded` hook — and the official docs table says the opposite, which is why `tests/rule-globs-anchored.test.sh` asserts it rather than leaving it a convention the next reader "corrects".
- **Placeholders in tracked files must be verified unclaimed.** This repo is public. `example-user-007` / `example-user-008` are 404 on github.com and `example.com` is RFC 2606 reserved. `alice`, `bob` and `jane-doe` are all real accounts, so a plausible-looking example names a stranger — and an example is the thing people copy verbatim. `tests/commit-as-identity.test.sh` asserts the seed carries no live-account name and no address outside `example.com`.
- **One review per PR.** `.coderabbit.yaml` pins `auto_incremental_review: false` and `chat.auto_reply: false` (both default `true`). Fix findings, push, reply once — never ask for a re-review of the same diff.
- **PR bodies, review replies and progress reports have a required short shape** (`CONVENTIONS.md`; `plugin/seed/CLAUDE.md` → "Reporting progress"): **each surface has its own shape**, not one shared template — a PR body opens with the literal heading `## Description` and one sentence, then the `acceptance_criteria` as a `✓`/`✗` table with the evidence per row, and threshold questions as one `⚠️` line each; a **review reply** is one line per finding fixed or skipped with its reason, and no criteria table; a **progress report** leads with the outcome, prefers tables to paragraphs, and puts what needs a decision last. **The length was never required** — the rules only ever asked for the criteria and the threshold note; the "Why" narratives and rejected-alternatives essays accumulated because each PR was also arguing a decision to the owner, and nobody separated *what a reviewer must check* from *what the owner might like to know*. Reasoning moves to the commit message and the task doc, which already carry it. The one thing terseness must not cost is **auditability**, and it doesn't: `` `foo.test.sh` 40/0 `` is both shorter than a paragraph and more checkable than one, since a reader can re-run it. `tests/pr-body-shape.test.sh` asserts the required elements are still named as required, so "be brief" can never quietly delete the merge gate. **The heading is a fixed literal because a gate cannot check "opens with a sentence".** `plugin/scripts/pr-body-clearance.sh` reads real PR bodies at the clearance gate, and the only property of a TL;DR it can decide on is a string it can grep for — so the rule names `## Description` character for character, and the two agree by construction rather than by anyone's care. **The bound on a criterion row is two-sided, and that is deliberate.** Asked 2026-08-30 whether the verbosity was required for CodeRabbit, the owner answered no, with a test rather than a length: treat the reviewer as an AI agent reading the table to review code, give it enough to check the claim and no more, and keep every row human-understandable. Only the ceiling would have been the obvious rule to write, and it is the wrong one — "be brief" alone produces `ok` and `see above`, which are shorter than a paragraph and check nothing, trading a verbose failure for a cheap one. The floor ("a person reading the row can check the claim from it") is what makes the rule land where the owner aimed it, and recording the answer next to the rule is what stops the next agent re-opening a settled question by surveying reviewer behaviour.
