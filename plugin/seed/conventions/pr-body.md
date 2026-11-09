# Conventions detail: the PR body

Detail for `../CONVENTIONS.md` — moved there verbatim, so the core stays short. Open a section only when the core's pointer to it names a trigger that applies. **The core wins on any disagreement**; fix this file to restate it.

<!-- tool-mention: Agent(1) — named to state its ABSENCE for three readers, never to instruct: only qa-reviewer holds it, and the self-review rule gives the route for the others. Enforced by tests/agent-tool-allowlist.test.sh. -->

### Commits

- Conventional commits, and **the `Co-Authored-By: Claude` trailer stays, because it is
  true** — Claude co-authored the commit. **You never read the config for this.** Your
  dispatch brief carries the installation's resolved value under `## Commit attribution`:
  **`claude`** (the default, and what an absent `commitAttribution` key means) ⇒ end the
  commit with the `Co-Authored-By: Claude <model> <noreply@anthropic.com>` trailer the
  harness provides; **`none`** ⇒ no attribution line and no session URL, which is the
  documented opt-out for an organisation that requires one. Push to `origin` early
  (don't wait until the end) so an interrupted worktree loses nothing.

### PR title

- PR title format: `<type>: <subject>` — e.g. `fix: retry on 429`. **You never read the
  config for a ticket tag either.** Your brief's `## PR title` line carries this
  installation's resolved `ticketPrefix`: **`none`** (the default, and what an absent key
  means) ⇒ append **nothing** — no bracketed tag of any kind; a prefix such as `ABC` ⇒
  append `[ABC-<n>]`, with the id your task or brief names, and `[ABC-0]` when neither
  names one. **The id is the human's to supply.** Never invent an id, never guess a
  project prefix, and never block a PR on the absence of one; nothing in this bundle
  carries a ticket id, so there is nowhere to look one up. Where a
  real id exists, its **ticket URL goes in the body**, one line under the TL;DR. **No OKF
  task id in the title** — the task-to-PR link is the task document's own `pr:` field.
  Target the default branch. **Never merge.**

### The PR body shape

- **The PR body has a required shape, and it is short — 2,500 characters, hard** (→ "Write
  less"). Its reader is a **human deciding whether to merge** — not an agent
  reconstructing how you worked. **It opens with the
  literal heading `## Description`.** Five required parts, in this order, plus an
  optional `## Notes` section (below) and nothing else:

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

  ### Notes

  - **A grep-derived inventory would have been short by 8 and looked complete.** `emails.ts`
    holds a literal NUL byte, so `grep` calls it binary and exits 0.

  ⚠️ Needs your call: harness growth 414 lines.
  ```

  **The worked example is [alteos-gmbh/monorepo#3286](https://github.com/alteos-gmbh/monorepo/pull/3286)** —
  3,554 characters for a +1,657-line change, read in under a minute. It predates the
  `## Description` heading and the `### Decided without asking` section; add both. Open
  it before you write your first one. A rule with an exemplar is followed; a rule
  described in the abstract is the one that produced a 14,673-character body five hours
  after it shipped.

  1. **The heading `## Description`, first**, then **a one-sentence TL;DR** under
     it. **That exact string, character for character** — it is the shape's only greppable
     anchor, which is why the rule names a fixed heading rather than "open with a
     sentence". `plugin/scripts/pr-body-clearance.sh` looks for it at the clearance gate,
     so a body that opens some other way is refused there rather than merged.
  2. **A `Verified:` line, immediately under the lead, and it must cite something.** One
     line: what you ran, what it said, and a **link** a reader can open — *"Verified:
     277/0 locally, 10/10 non-deploy checks green on [run 33430116558](…)"*. A reader
     learns in one line whether to trust the rest, which is the whole job. **What it
     claims is your business; that it cites something is the gate's** — the reader cannot
     check whether 277/0 is true, and it can check that you left somewhere to go and find
     out. A line asserting "all green" with nothing to open is the same
     evidence-free claim the criteria floor already refuses one column over, and it is
     refused here for its own reason, separately from the line being absent.
  3. **The task's `acceptance_criteria` as a table** — one row per criterion, its text
     verbatim, a `✓`/`✗`, and the evidence. **Required, always** (next bullet).
     **Under a heading that carries the tally AND the reason for the `✗`s** —
     `### Criteria (10 ✓ / 8 ✗ — every ✗ is a later slice or task-001)`. This is the single
     most valuable line in the body. `SCHEMA.md` makes an unverified criterion block
     clearance, so a PR carrying eight `✗` looks alarming until the heading says that
     every one of them is deferred by design — and without it a reader reconstructs that
     from eighteen rows before they can decide anything. **The tally must match the
     table**: a heading claiming 10 `✓` over a table carrying 9 is a defect, the gate
     counts the rows and compares, and a tally nobody can trust costs more than no tally,
     because it is the one number a reader never re-derives. **When there are no `✗`, no
     reason is needed**; when there are any, the reason is required and *that it is there*
     is what is checked — whether it is a good one stays the reviewer's call.
  4. **`### Decided without asking`, after the table** — your answer to "what did you
     decide that I did not tell you to decide?". One row per technical choice that no
     criterion, `answered_questions` entry or `acknowledged_decisions:` entry named, shaped
     `<decision> — alternatives: …; why: …; reversible: …` — the shape of a project's `D<n>`
     rows, so the two lists compare directly. A choice that departs from a `D<n>` is always
     a row. Nothing to declare is the single line `none — <why>`, never a bare `none`.
     `pr-body-clearance.sh` refuses an empty section, rows beside a none line, a second
     none line, a row missing one of the three keys, a bare `none`, and a body without the
     section — `MISSING: the 'Decided without asking' section; with nothing to declare it is the one line 'none — <why>'.` Its rows
     are not charged against the 2,500, up to 800 characters each.
  5. **A short flagged line per threshold question** the owner must answer — harness
     growth, PR size, a wide change you could not split. One line each, `⚠️`-prefixed,
     last. Not a section, not an essay. **Each `⚠️` stays one line — the figure, and the
     call you need from the owner.** A `⚠️` that runs to a paragraph has stopped being a
     flag and become the essay it replaced; when the reasoning does not fit on the line it
     belongs in the task doc, and the line points at it.

  **Reasoning goes in the commit message and the task doc.** Why you chose this design,
  what you rejected, the incident that motivated it, what you tried first — all of it is
  already carried by those two, both travel with the change, and **none of it is needed to
  decide a merge.** A reader who wants the story has `git log` and the task document; a
  reader deciding a merge has thirty seconds. Add a `## Notes` section only for something a
  *reviewer* cannot see from the diff (a hint about where to look, a deliberate omission)
  — **one line per note, at most THREE of them, bounded exactly as the `⚠️` lines are.**
  **Its depth is not significant**: the reader matches the heading's *text* and not its
  `#` count, so
  `## Notes` here and the `### Notes` of the worked example are one section to it. "Judgement calls for the
  reviewer" is the heading this section grows under once it is unbounded, and that is the
  same essay arriving by another name.
  **Every note leads with its claim, in bold.** The bolded opening sentence **is** the
  finding — *"**A grep-derived inventory would have been short by 8 and looked
  complete.**"* — with the explanation after it, so the section is skimmable in bold alone
  and a reader who stops there has still got every finding. A note that opens with its
  background and arrives at the point three clauses later is refused by
  `pr-body-clearance.sh`. **The section stays optional and no number of notes is ever
  required** — a small PR needs none, and the gate never asks for one; a fourth note is
  refused at exit 4.

### The criteria table is the merge gate

- **The criteria table is the merge gate — so it is required, and terseness never costs
  evidence.** It is what the independent reviewer — an external one (e.g. CodeRabbit) or
  the `qa-reviewer` fallback — evaluates the change against, so it must travel with the
  PR, not just your own "it's done." The `✓`/`✗` column **is** the checkbox state
  `SCHEMA.md` reads (→ "Two structured inputs; prose is never one"): one mark per
  criterion, machine-checkable, and the only place criteria coverage is read from.
  **Mark `✓` only for a criterion you actually verified; mark the rest `✗`** and say in
  the same row what verifying it would take. A `✗` **blocks the PR from being
  merge-eligible** (`SCHEMA.md` → "An unverified acceptance criterion blocks clearance"),
  which is the point: a criterion no test covers — a price that must match an upstream
  rule, a flow only a human or a browser can walk — is exactly where green CI means
  nothing. Leaving it honestly unmarked routes the PR to a human instead of letting it
  ride the deterministic checks. Never mark `✓` because everything else passed.
  **This rule has a reader, and it reads the body — not this document.**
  `scripts/pr-body-clearance.sh <pr>` fetches the actual PR body from the host and
  refuses one that is missing the TL;DR line, the `Verified:` line or a link on it, the
  criteria table, its heading's tally, a tally that matches the rows, the reason for any
  `✗` in that tally, the bold claim opening a `## Notes` bullet, or a well-formed
  `### Decided without asking`;
  `scripts/required-checks.sh` asks it for every PR it is about to clear, and
  `AUTONOMY.md` precondition 3 names it. **It refuses on missing structure at exit 1 and
  on LENGTH at exit 4** — over 2,500 characters, or more than 3 `## Notes` bullets, per
  "Write less" above. The two are separate codes because the fixes are: exit 1 says add
  the missing element, exit 4 says move the reasoning to the task doc.
  **The 2,500 are YOURS**: a block a reviewer generates into the body between its own
  marker comments is stripped before the count, because a ceiling on text its author
  cannot shorten refuses whoever pushed last. Text carrying no marker is counted in full.
  **The markers are not an exemption you can write yourself** — nothing in a body says who
  typed a line, so the strip is worth at most 1,000 characters (real blocks measure 531,
  740, 741), and a marked block larger than that is counted in full, markers and all.
  **Criterion text is not charged either**: each criteria row's verbatim criterion cell
  is left out of the count, up to 800 characters a row, so quote it in full — never
  abridge it to fit; its evidence cell is yours and is counted.
  Run it on your draft before you open the PR
  (`scripts/pr-body-clearance.sh --body-file <file>`); it is the cheapest check you have.
  **Short and auditable are the same thing here, which is why brevity costs nothing.**
  `` `foo.test.sh` 40/0 `` is *shorter* than a paragraph and *more* checkable than one: it
  names an artifact the reader can re-run, and a claim a reader can re-run is the only
  kind that counts. So the short form is licence to drop the narration, **never** licence
  to assert without evidence — "verified, works as expected" is a long way of saying
  nothing. Name the command, the test file and its tally, the CI run, or the URL you
  loaded.
  **A row carries what a reviewer needs to CHECK THE CLAIM, and stops** — a command and
  its result wherever that suffices: `` `foo.test.sh` 40/0 ``, `` `shellcheck -x run.sh`
  clean ``, `CI run 1234 green`, the URL you loaded. **Narration is not wanted** — not what
  you tried first, not why the approach is right, not the criterion restated in your own
  words, not the incident behind it. Every one of those is already in the commit message
  and the task doc, and repeating it in the row costs the reviewer the one thing the table
  exists to give them.
  **The floor is readability, and it binds exactly as hard as the ceiling: a person reading
  a row can check the claim from it.** `` `foo.test.sh` 40/0 `` clears the floor — a reader
  knows what to run and what they should see. `ok`, `done`, `see above` and a bare commit
  SHA do not: none tells a reader what to do next. **Short is the goal; cryptic is a
  failure**, and cutting past the point a human can act on the row fails this rule as
  surely as a paragraph does.
  **That two-sided bar is the rule's own test, and it settles a question already asked and
  answered — do not re-open it.** Asked 2026-08-30: is any of this verbosity required for
  CodeRabbit or another external reviewer? **No.** Treat the reviewer as an **AI agent**
  reading the table to review code — give it enough to check the claim and no more — **and
  keep every row human-understandable.** **Both halves bind**: a row an AI could parse but
  no person can act on fails just as surely as a paragraph neither of them needed. The
  answer is the owner's, so settle a row against the bar above rather than surveying past
  reviewer behaviour to re-derive it.
  **That bar has a reader, and the reader is the same one that reads the shape.** The
  ceiling and the floor shipped as prose on 2026-08-29 with nothing checking them, and a
  day later a PR landed three criteria rows of 500–600 characters carrying shell
  one-liners and their own reasoning — so `pr-body-clearance.sh` now measures **each
  criteria row's EVIDENCE cell**, refuses at **exit 3**, and names every offending row by
  index, length and criterion text. **Floor 13 bytes, ceiling 400 bytes.**
  **Evidence goes in the LAST column** — `| Criterion | ✓ | Verified by |` — which is
  where a reader looks for it and the only cell the bound reads.
  **The bound is on ONE CELL, never on the body.** That is not a compromise between the
  two, it is the opposite of a body cap: a body grows because the change is large, which
  is honest; a row grows because its author put the reasoning in the table instead of the
  task doc. Bounding the body would refuse the first. The criterion text does not count
  against the bound either — you copy it verbatim, so it is not yours to shorten.
  **Both numbers are measured, not round.** Over 34 criteria rows of three real PRs at
  2026-08-30T16:24Z (bytes, `LC_ALL=C`): #67 **92–377**, #70 **19–189**, #71 **160–341**
  plus **422, 462, 487**. 400 is the midpoint of the empty band 378–421 — 23 clear of the
  largest honest cell, 22 short of the smallest offending one — and it fails exactly those
  three rows and no other of the 34. 13 is the midpoint of `see above` (9), the longest
  floor failure named above, and `CI run 1234 green` (17), the shortest evidence named
  above. **Moving either number means re-measuring**; the harness pins all four boundary
  values as fixtures, so a change made without the measurement goes red.
  **A body written to this style clears it with room to spare** — #70's round-2 body,
  rewritten to these rules and complete on all 11 criteria, has a longest row of **264
  bytes** and a longest evidence cell of **189**, under half the ceiling that catches #71.
  The bound refuses bloat, not thoroughness.

### Run the shape reader on your draft

- **Run the shape reader on your draft, fix what it refuses, then post — every role
  agent, both surfaces, every time.** This is a step, not a suggestion, and it is the
  cheapest check any of you has: it needs no network, no reviewer session and no PR.

  | You are about to post | Write the draft to a file, then run | It answers |
  |---|---|---|
  | a **PR body** | `scripts/pr-body-clearance.sh --body-file <file>` | 0 clear · 1 an element missing or contradicted · 2 unknown · 3 a criteria row outside the evidence bound |
  | a **reply to review findings** | `scripts/pr-comment-clearance.sh --comment-file <file>` | 0 clear · 1 an entry with no verdict · 2 unknown · 3 an element over its bound |

  **Both refusals name the element and what to do about it**, so fixing one is a minute.
  **Before you post is the only cheap moment:** a body you have to force-push a correction
  into is a body a reviewer has already half-read, and an edited comment has already
  notified everyone watching. **This does not replace either gate** —
  `scripts/required-checks.sh` runs the body reader against what the host actually serves,
  which is the artifact that decides — it just means you never learn about the shape from
  the gate. **It exists because the rule was already there and nobody read it**: the short
  form was documented from 14:59 UTC on 2026-08-29 and five hours later an agent that had
  the rule opened a 14,673-character body. A rule with no reader at the moment of writing
  is a rule that gets discovered at the moment of merging.

### PR size is a heuristic, never a gate

- **PR size is a heuristic that suggests a split, never a gate.** **And it is TWO
  numbers.**
  Before opening, check the diff against **`maxPrLoc`** in `instance.config.json`
  (**absent that key, 500**) **and against `maxPrFiles`** in the same file (**absent that
  key, 100**);
  past either, say so in the PR body as one `⚠️` line — the figure and the split you would make
  (by phase, by layer, or as a stack) — and put the detail in the commit message and the
  task doc, per the PR-body shape above.
  **`maxPrFiles` is the one the reviewer counts, and past it there is no review at all.**
  A free-plan CodeRabbit refuses a pull request over 100 files outright, before any quota
  question, offering only "split the PR or upgrade" (measured 2026-09-05 on a 147-file
  PR). The two numbers disagree in both directions — a `git mv` sweep is one file per
  rename and almost no lines, one generated lockfile is thousands of lines in one file —
  which is why neither can be inferred from the other. Count them the way the host does:
  `git diff --numstat origin/<default> | wc -l` for files,
  `git diff --shortstat origin/<default>` for lines. Then **open the PR
  anyway**: generated boilerplate, codemods, lockfiles and dense logic all move the real
  number, so a line count cannot decide reviewability on its own, and a task that
  legitimately needs one large change must not be blocked by arithmetic. It is **not** a
  review criterion either — a reviewer never withholds clearance over it, and it never
  appears as a finding. If the split is obviously right and cheap, do it before opening.

### A repo with a VERSION file at its root

- **A repo with a `VERSION` file at its root: PROPOSE the bump, never make it silently and
  never skip it.** If the repo you are changing keeps its version in one file at the root
  (a plain `VERSION`, one line, no extension is the shape to expect) and your change
  touches what that repo's **consumers actually consume** — the paths other people or
  other systems install, link, copy or run, as opposed to its docs, tests and CI — then
  the change arrives with the new number already in the diff, in **its own commit** so it
  can be dropped, plus **one `⚠️` line in the PR body** naming the proposed
  `old → new` and which part of the version moved — it is a threshold question the owner
  answers, so it is bounded like every other one, and the *why* lives in the task doc and
  the commit message. **The human approves it by merging and rejects it by asking
  for that commit to go** — you are proposing, not releasing. Two things that are not
  yours to add: a **silent** bump (a number that moves with no line in the body is a
  number nobody agreed to), and a **release process** — no changelog, no tag, no publish
  step, unless the task's `acceptance_criteria` asks for one. The repo names its own
  consumed paths in its `CLAUDE.md` or its rule files; if it names none and the boundary
  is genuinely unclear, say so in the PR body rather than guessing a number.
  **UNLESS THE REPO SAYS THE BUMP HAPPENS ON THE DEFAULT BRANCH AT MERGE TIME — then your PR
  carries no version change at all.** `cbmono/loopd` says exactly that: leave every place
  the number lives alone, propose nothing, and let the merger run the repo's bump script on
  the default branch afterwards. The reason is one a big repo hits too — the number is
  usually several files, so while each PR carries it, any two open PRs conflict on all of
  them and must merge one at a time, at a full CI run each. Read the repo before you reach
  for this bullet: its own rule wins, and this one applies when it has none.

### Self-review before you open the PR

- **Self-review before you open the PR (a pre-filter, not the gate).** On your own diff,
  run a review and fix what it flags *first* (correctness, edge cases, security, tests).
  **Which route you take is decided by your own `tools:` list, not by what is installed on
  the machine.** Hold `Agent`? — `qa-reviewer` does — dispatch `loopd:code-architect`
  (it ships in the plugin beside you; the bare name does not resolve). Don't hold
  it? — `software-engineer`, `devops-engineer` and `failure-analyst` don't — then **a
  careful pass over your own diff *is* the route**, not a fallback from one, because
  there is nothing to fall back from. Check your allowlist if you are unsure: a shipped
  `code-architect` changes nothing for an agent that cannot dispatch, which is why this
  reads on possession rather than on installation.
  **Don't spend a CodeRabbit session here if CodeRabbit reviews the PR
  anyway** — running the same paid reviewer twice per PR is the single easiest cost to
  delete, and the pre-filter's job (catch the cheap stuff) is served just as well by a
  local agent. Reach for `coderabbit review` locally **only** when the repo has *no*
  CodeRabbit integration, i.e. when the `qa-reviewer` fallback would be the gate. This
  pre-filter does **not** replace the independent verifier: you review your own work
  leniently, so the fresh-context reviewer still runs after (see `SCHEMA.md`
  "Independent verification gate").

### Don't grow the harness without a reason

- **Don't grow the harness without a reason — and past ~150 lines, ask.** This machinery
  is a means, not the product. Before you open a PR, measure what you added to it:

  ```sh
  git diff --numstat origin/main -- 'plugin/**/*.sh' | awk '{a+=$1} END{print a+0}'
  ```

  Under ~150 added lines, carry on. **At or above it, flag it in the PR body as one
  `⚠️` line naming the figure** — `⚠️ Needs your call: harness growth 414 lines.` — and put
  what the lines buy and what you considered instead in the **commit message and the task
  doc**, per the PR-body shape above. Then let the owner decide. It is not a block; it is a
  question the owner answers, and raising it is never a failure.

  For scale: ordinary fixes here add 30-55 lines; the two largest features added 360 and
  363. The whole harness is ~8,500 lines, so 150 is roughly a 2% jump in one PR.

  **Why a number in a rule rather than a test.** This used to be `machinery-ceiling.test.sh`
  — 944 lines pinning two integers that every PR touching `plugin/` had to re-measure. The
  measurement was free; the *coupling* was not. It put a placeholder on `main` and turned it
  red (#31, needing #32 purely to undo), it was the single conflict `git merge-tree` found
  across ten PR pairs (#34 x #35), and it forced rebases on PRs that had nothing to do with
  each other. A threshold you check against **your own diff** cannot collide with anyone
  else's, which is the whole point.
