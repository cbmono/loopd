# Conventions for role agents working in target repos

**This is the single source of truth for shared role-agent behaviour.** The
symlinked role agents (`software-engineer`, `devops-engineer`, `qa-reviewer`,
`failure-analyst`) reference this file instead of restating it — **keep them in
sync**: change a rule here, not in each agent.

**Read this before your first write in a target repo.** It lives here rather
than in the instance `CLAUDE.md` because it governs work in the **target
repos**, which are outside this bundle — so it cannot be a `paths:`-scoped
rule (globs are matched relative to this directory and never match a file under
`reposRoot`), and as always-loaded text it sat in every session's context
including the majority that dispatch no role agent. The `CLAUDE.md` section of
the same name keeps the handful of invariants that must hold whether or not you
got here.

**One rule about this file's own wording, because four agents with differing `tools:`
lists read it:** an instruction here must be executable by **every** one of them, so where
a rule depends on a tool only some of you hold, it says **which list decides** and what the
others do instead. Never the other way round — a condition on what is *installed* reads as
satisfied while still being unexecutable for an agent that lacks the tool, which is exactly
how the `code-architect` clause below went unnoticed. `tests/agent-tool-allowlist.test.sh`
in `cbmono/loopd` enforces this.

<!-- tool-mention: Workflow(2), Agent(4), EnterWorktree(1), mcp__claude-in-chrome__*(1), AskUserQuestion(1) — named below to state their ABSENCE for some readers, never to instruct: no role agent holds Workflow; only qa-reviewer holds Agent, which is why the Explore rule states the route for the three that do not; EnterWorktree may be missing for a subagent; failure-analyst holds no browser tools; no role agent holds AskUserQuestion, which is why a tool request goes into open_questions instead of a live prompt. Every mention gives the route for an agent that lacks it. Enforced by tests/agent-tool-allowlist.test.sh. -->

## Write less

**Owner's verdict, 2026-09-06: agents write far too much, everywhere.** Measured on this
tree the same day — `init-bundle.sh` 1,115 comment lines of 2,400, `session-banner.sh`
1,016 of 1,463, PR bodies [#122](https://github.com/cbmono/ai-bridge/pull/122) and
[#135](https://github.com/cbmono/ai-bridge/pull/135) at 5,826 and 6,423 characters, 133
`Finding`s averaging 110 lines. **These are ceilings, not targets, and they bind every
agent on every surface below.**

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

**Four of these have readers, so they are not prose.**
`pr-body-clearance.sh` refuses a body over 2,500 characters or carrying more than 3 notes
(**exit 4**); `pr-verdict-clearance.sh` refuses a checker row with no `PASS`/`FAIL` or no
command (**exit 3**); `validate-bundle.sh` warns on a `Finding` over 40 lines or missing its
`lesson:` — **on the document you name (`validate-bundle.sh <path>`) as well as on the whole
bundle**, so the cap lands while you are writing rather than at the next full run; and
`tests/concision-contract.test.sh` in `cbmono/loopd` fails when a
`plugin/**/*.sh` file's comment-line share exceeds **35%**, ratcheting the files already
above it so none may grow its share.

- **Exhaust your own tools before you hand work back — three rungs, in order.** The default
  when you cannot do something is **not** to report it back:

  1. **Do it yourself**, with the tools you hold — a CLI, an MCP server, a browser, a
     script you write. That a step is fiddly, or is a browser step, or is the kind of thing
     a human usually does, is not a reason to pass it up.
  2. **Else ask for access to the tool that would let you.** Record the request and carry
     on — the next bullet is the whole of how, and it never stops your work. Asking fixes
     the gap once; reporting it fixes nothing, and the same gap blocks the next task and
     the one after.
  3. **Only then hand back exact instructions** — the commands, the paths, the output to
     expect — for a human to run, and only when no tool could have let you do it.

  **THE LADDER COVERS CAPABILITY GAPS ONLY. AN AUTHORITY GAP STAYS HUMAN REGARDLESS OF
  WHAT TOOL IS AVAILABLE.** "I can't" has two meanings and only one of them is yours:

  | | Meaning | Whose |
  |---|---|---|
  | **Capability gap** | no tool, no access, no CLI, not authenticated | **Yours.** The three rungs apply exactly as written. |
  | **Authority gap** | you *can* act, and must not | **The human's, always.** No rung applies. |

  The authority class, non-exhaustively: promoting a task `draft → ready`; merging a pull
  request; **any destructive or irreversible action**; **anything outward-facing** —
  publishing, sending, posting, deploying. **And its principle, so a case not on that list
  still resolves correctly: tool availability was never what made these human.** They are
  the human's because the *decision* is the human's, so acquiring the tool, finding a
  token, or being handed a wider allowlist changes nothing about any of them. A case you
  cannot place is an authority gap until a human says otherwise.

  **Nothing in this bullet is licence over the authority class.** Rung 1 is not "do it if
  you can" — **it never reaches an authority gap at all**, because those were never yours
  to be capable of. An agent reading this rule as permission to merge, promote, publish or
  delete has read it exactly backwards, and would be reversing the deny baseline this
  bundle runs on (`.claude/settings.json`, `AUTONOMY.md`, `SCHEMA.md` → "Two human
  authorities"). That misreading is most dangerous exactly where this rule has most
  effect — a background dispatch tick, hours from anyone watching — which is why it
  is stated here as a prohibition rather than left to be inferred from the table.
- **The middle rung NEVER BLOCKS: record the tool request, then carry on.** `blocked` is
  not the response to a missing tool, and an agent that halts at the first gap turns a
  missing CLI into a stalled task. On a capability gap: **write the request into the task's
  `open_questions`**, **continue**, finish everything that does not depend on the missing
  tool, and **report exactly what you could not reach** — named, so a reviewer can see it.
  You do not get to quietly take a worse route and call it done; the naming is what makes
  "continue" reviewable instead of silent.
  **Use the mechanism that already exists — nothing new is built for this.**
  `open_questions` → the tick surfaces it in `AWAITING.md` as a `🧰 **grant**` item (its own
  verb, distinct from `❓ **answer**`, because installing a thing is not typing an answer)
  → the human appends ` --- <answer>` to the entry → the next tick folds it in and
  re-dispatches the task **with** the tool. That is the entire path.
  **There is no live channel, and here is why, so nobody proposes one.** No role agent
  holds `AskUserQuestion`, and none is granted a message-sending tool, so a subagent's only
  upward channel is its final message on termination — bubbling up mid-run means dying and
  losing its context. A live grant would not help even if one existed: a subagent's tool
  list is fixed at dispatch and MCP servers connect at session start, so access granted
  mid-flight never reaches the running agent. It has to be re-dispatched either way, which
  is exactly what a live prompt was meant to avoid.
  **The contradiction this has a reader for:** reporting `blocked` for a reason that names
  a tool your **own** `tools:` list contains. `check-dispatch.sh` — the dispatch-artifact
  bullet below gives its path — reports that as exit 4, the record contradicting itself,
  and `tests/blocked-vs-own-tools.test.sh` in `cbmono/loopd` pins it. Re-read your
  allowlist before you write a blocker reason.
- Read `instance.config.json` for `reposRoot` (where target repos are cloned).
  Honor this `CLAUDE.md` for data-handling, units, and commit-attribution.
- **Detect the default branch** (`git symbolic-ref --short refs/remotes/origin/HEAD`
  / `git remote show origin`) — never assume `main`. Never work on it.
- Create a feature branch (or a git worktree under the instance's `worktreeRoot` —
  absent that key, `<reposRoot>/_wt`) per task.
- Conventional commits, and **the `Co-Authored-By: Claude` trailer stays, because it is
  true** — Claude co-authored the commit. **You never read the config for this.** Your
  dispatch brief carries the installation's resolved value under `## Commit attribution`:
  **`claude`** (the default, and what an absent `commitAttribution` key means) ⇒ end the
  commit with the `Co-Authored-By: Claude <model> <noreply@anthropic.com>` trailer the
  harness provides; **`none`** ⇒ no attribution line and no session URL, which is the
  documented opt-out for an organisation that requires one. Push to `origin` early
  (don't wait until the end) so an interrupted worktree loses nothing.
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
- **Write for a human who will not read it.** They scan. Say the thing, then stop —
  a reader who wants depth will ask, and asking is cheap where re-reading to find the
  point is not. **One house style, for every surface below:**
  - **Short sentences.** One idea each.
  - **Bullets, tables and icons over paragraphs.** More than two of a thing is a table.
  - **Lead with the outcome** — what happened and what it means, before how you got there.

  **Trim the transmission, never the record.** This split decides every length question
  in this document, and getting it backwards deletes the reasoning the work runs on:

  | Surface | Rule |
  |---|---|
  | PR bodies, review comments and replies, status reports, code comments | **concise** — a reader is deciding something, now |
  | Commit messages, `Finding`s | **bounded, but wider** — 5 lines and 40 (→ "Write less"): the durable record still fits on a screen |
  | Task docs | **as long as the reasoning needs** — the ONE surface with no ceiling, and where everything the others cut belongs |

  **Brevity is never an excuse to drop evidence, a criterion or a caveat.** It is licence
  to drop *narration* — the story of how you got there — because that story belongs in the
  task doc, which travels with the change and is the one surface with no length limit.
  **So there is nowhere for reasoning to be lost:** every rule below that says "short" is
  telling you where to put it, not to delete it.
- **The PR body has a required shape, and it is short — 2,500 characters, hard** (→ "Write
  less"). Its reader is a **human deciding whether to merge** — not an agent
  reconstructing how you worked. **It opens with the
  literal heading `## Description`.** Four required parts, in this order, plus an
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

  ### Notes

  - **A grep-derived inventory would have been short by 8 and looked complete.** `emails.ts`
    holds a literal NUL byte, so `grep` calls it binary and exits 0.

  ⚠️ Needs your call: harness growth 414 lines.
  ```

  **The worked example is [alteos-gmbh/monorepo#3286](https://github.com/alteos-gmbh/monorepo/pull/3286)** —
  3,554 characters for a +1,657-line change, read in under a minute, and the shape every
  body here is measured against. Open it before you write your first one. A rule with an
  exemplar is followed; a rule described in the abstract is the one that produced a
  14,673-character body five hours after it shipped.

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
  4. **A short flagged line per threshold question** the owner must answer — harness
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
  `✗` in that tally, or the bold claim opening a `## Notes` bullet;
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
- **Get the repo's build and lint green before opening a PR, and its tests green for what
  you touched** — the tests being **the ones your change touches, not the whole suite**
  (next bullet, which is where the scope of "tests" is settled). If you can't get that
  green, report rather than open the PR.
- **The full suite belongs to CI — locally, run the tests your change touches.** The
  required check on the PR runs everything on a clean machine anyway, so a full local run
  buys the same answer twice and the second copy is the expensive one. Concretely:
  **run the tests your change touches, plus anything that exercises the file you edited**,
  and **do not run the full suite locally as a matter of course**.
  **Where the repo ships a runner that selects on the diff, use it rather than choosing by
  hand** — `tests/run.sh --changed` in `cbmono/loopd` runs exactly what CI runs, and
  its `--all` runs once before the PR is opened. Selecting by hand is how a changed path
  ends up with no harness covering it and nobody noticing.
  **This is a rule about RE-RUNNING, not about testing.** Follow it literally and you still
  test before every push — that is the point of it, not a loophole in it.
  **Keep the per-branch signal, and this is why:** an agent needs a result **for its own
  branch, before it pushes**, because batching several agents' work tells you *the batch*
  is broken without telling you *whose change* broke it. Delete that sentence and the rule
  reads as "stop testing locally", which is the one thing it does not say.
  **The escape hatch exists and is bounded.** A full local run is legitimate when your
  change touches **shared machinery every test loads** — a common fixture, a helper each
  file sources, a config every test reads — and in that case **the PR body must state why
  the full run was needed**. It is an exception carrying a stated cost, not a free choice.
  **Do not poll a long-running local run.** This is its own prohibition, not a restatement
  of the one above: you can obey "don't run the full suite" and still burn an hour
  watching some *other* long job. A run you started and are now checking every minute is
  the **parked-watcher failure `check-dispatch.sh` exists for, with a pulse** — a
  40-minute poll and a parked watcher cost the same and look equally busy. Start a long
  job only if you will leave it alone; otherwise stop it.
  **The trade, with the measured numbers, so you can tell when it stops applying.** One CI
  round-trip costs **about 20 minutes of wall clock and no tokens** for the full suite
  (20m 10s on 2026-10-04, when it was 141 harnesses; it was 8-10 minutes at 111); the local full run
  measured **2026-08-29** cost **39m 47s and 269.4k tokens** on a machine that was also
  running a `/loopd:dispatch` tick. Same answer, several times the wall clock, and tokens on top.
  This is a **proportion argument, not a ban**: a *red* local run would have saved a CI
  round-trip, and the day a repo's CI is slower than its local suite, this rule inverts.
  **The local run never was the gate.** In `cbmono/loopd`, the `harness suite` job is a
  **required check** on every PR
  ([ai-bridge#42](https://github.com/cbmono/ai-bridge/pull/42)), and branch protection sets
  **`strict=true`**, which forces that check to run **against the merged base** before the
  PR can land. Your machine cannot produce that verdict, so skipping the local full run
  asks nobody to trust **less** verification — it moves the verification to the only place
  the merge gate actually reads. `tests/local-vs-ci-testing.test.sh` in `cbmono/loopd`
  pins the clauses above by name.
- **A red check is EVIDENCE, and it is already written down: read the failing check's own
  error text BEFORE you form a hypothesis, and falsify locally BEFORE you push.** Two
  clauses, and each one ships with **the cost of skipping it**, because the instruction on
  its own is already believed by everyone who skipped it — nobody sets out to guess.
  **1. THE ERROR TEXT FIRST, BEFORE ANY HYPOTHESIS EXISTS.** `gh run view <run-id>
  --log-failed`, or the failing step's own output — read before you hold a theory, not to
  confirm the one you already hold. **Order is the whole rule**: a hypothesis you are
  already holding turns a log into something you skim for support, and the line that
  refutes it reads as noise.
  **The cost, measured on the day this rule comes from (`alteos`, 2026-09-08):** the failing
  check's error text **already named both** the RBAC problem and the wrong ArgoCD project.
  Both were guessed instead, in that order, wrongly. The answer was sitting in a log nobody
  had opened, and the guessing is where the day went.
  **2. FALSIFY LOCALLY BEFORE YOU PUSH — A FULL CI CYCLE IS NOT A PROBE.** Reproduce the
  failing step's command on your own machine and try to **break** your hypothesis before you
  push it. A push is how you confirm a hypothesis you have already tried to falsify; it is
  never how you test one.
  **The cost, measured:** a CI run takes **every stage through to testing**, so a wrong guess
  costs a **whole pipeline** and not the one step you doubted — about **20 minutes** here (→
  "The full suite belongs to CI"), far longer on a deploy pipeline. Probing by push is the
  **direct cause** of the "hours, and many builds" the owner reported on that day.
  **When you genuinely cannot run it locally** — a runner-only tool, a credential you do not
  hold — that is a capability gap (→ the three rungs above): say **which clause you could
  not satisfy**, and take the cheapest falsification you do have, which is re-reading the
  log *against* your hypothesis for the line that refutes it.
  `tests/read-the-error-text-first.test.sh` in `cbmono/loopd` pins both clauses and both
  costs, here and in `plugin/agents/failure-analyst.md` — the agent whose whole job this is
  carries clause 1 as its **first** diagnosis step, because a diagnostician that reaches a
  hypothesis first has nothing left for the evidence to do.
- **A read that could not have established the answer returns UNKNOWN — and UNKNOWN is
  reported as UNKNOWN, never as a conclusion.** The test is **what the read could have
  established**, and it is **NOT whether the read errored**: all four failures below
  returned something, exit 0, no error, and the something was taken for the answer. That
  is the distinction every one of them crossed. **So ask it of the read you just made:
  could this command, run exactly like this, have come back DIFFERENT if the claim I am
  about to make were false?** No ⇒ it established nothing, and what you report is
  `UNKNOWN` plus the read that would settle it.
  **The four, measured in one day (`alteos`, 2026-09-08), each a claim made to a human** —
  what came back, and what it could not have shown. **The abstract form of this rule is
  already believed by everyone who then breaks it**, so the examples ship with it and are
  not decoration:

  | The read returned | It could not have established |
  |---|---|
  | a mid-rollout image digest compared against the **empty string** — no digest, no error, exit 0 | that the new build is not live anywhere: an empty digest is what "nothing is there" and "I could not look" both print |
  | a check run whose conclusion is failure — but the run was **superseded** | that the head's checks are failing: a superseded run is a verdict on a commit that has already been replaced |
  | **`200`** from a region with **no pod behind it** | that the region is serving: an edge that answers in front of the pods reports on itself, not on them |
  | a **matcher** read out of a workflow config, asserted as a 20-workflow regression | that 20 workflows regressed when **no other workflow had run**: a pattern says what would match, never what did |

  **This rule belongs to the LAUNCHER as much as to the tick, which is why it is here and
  not in one agent.** `agent:project-manager` has adjacent discipline; the launcher
  (`skills/dispatch/SKILL.md`) has none at all — and the launcher is what made all four of
  those claims. **It ships in the SEED because an installation had already reinvented it**:
  one stamped bundle wrote *"never manufacture a decision out of a side effect that isn't
  live yet"* into its own `CLAUDE.md` by hand, which is now the seed's own dormant-side-effect
  rule and the narrow case of this one. A rule two installations write independently belongs
  in the seed rather than in a bundle.
  **Its two readers, because prose alone already rotted once — on 2026-08-23.**
  `plugin/evals/unverified-state-is-unknown` in `cbmono/loopd` grades the behaviour (the
  empty-digest case: pass only when nothing is left standing as a conclusion), and
  `tests/unverified-read-is-unknown.test.sh` pins this rule, all four examples and the
  references to it.
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
- **Self-review before you open the PR (a pre-filter, not the gate).** On your own diff,
  run a review and fix what it flags *first* (correctness, edge cases, security, tests).
  **Which route you take is decided by your own `tools:` list, not by what is installed on
  the machine.** Hold `Agent`? — `qa-reviewer` does — dispatch `code-architect`. Don't hold
  it? — `software-engineer`, `devops-engineer` and `failure-analyst` don't — then **a
  careful pass over your own diff *is* the route**, not a fallback from one, because
  there is nothing to fall back from. Check your allowlist if you are unsure: an installed
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
- **ASK FOR THE INDEPENDENT REVIEW ONCE, AT THE HEAD YOU CONSIDER FINAL — never after a
  fix commit.** This is the ordering rule, and it comes before the "don't re-trigger" rule
  below because it is what makes that one cheap: **self-review your own diff first, push
  everything it made you change, get CI green, and only then post
  `@coderabbitai review`.** A review of a head that moves ten minutes later is a spent
  review that clears nothing — `review-clearance.sh` answers **exit 4 (stale)** for it,
  which looks identical on the PR page to no review at all.
  **The quota is shared and it is per hour, not per PR.** Three agents pushing fixes into
  three PRs in one hour is one queue, so every request an agent makes at a non-final head
  is taken out of the request some *other* agent needs at its final one. Measured
  2026-09-05/06: three PRs merged on the owner's override — one carried a real review at a
  commit it does not name (exit 4), two carried *"Review limit reached"* behind a **green**
  CodeRabbit check (exit 1). That is the ninth, tenth and eleventh instance of the same
  pattern.
  **So request at most once per PR, and never on a schedule.** The one exception is a
  substantial rewrite that invalidates the review you already have — see the next bullet,
  which is about not re-reviewing the *same* diff.
  Repos should make the ordering hold by configuration rather than by everyone's
  discipline: pin **`reviews.auto_review.enabled: false`** in `.coderabbit.yaml` so the
  explicit request at the final head is the *only* thing that spends a review, and know the
  trade-off — an unrequested PR then gets no review at all, which is caught by
  `review-clearance.sh` exit 3 (no reviewer signal) and never by a green check.
- **Resolve or answer every reviewer-authored thread before you re-request** —
  `SCHEMA.md` clause 9, and it refuses a merge exactly as a stale review does. A thread you
  leave open is an unanswered finding whatever the review object says, so the sequence at
  the end of a round is: **fix or answer each thread → resolve it (or say in it why you
  are not taking it) → push → then, if a rewrite genuinely invalidated the review, request
  once at the new final head.** Resolving your own thread is not the reviewer agreeing with
  you; it records your answer so a human can see one. **The reader is
  `review-clearance.sh`, which exits 6 and NAMES the threads it found open** — so an
  unresolved thread is a line you can act on, not something a reviewer has to notice.
  **Why this bullet exists and it is not about quota.** The 2026-09-05 audit of the seven
  1.0 PRs found **four failing on clauses 3 and 9** — a stale-head review and unresolved
  reviewer threads. Three of the seven were quota; these four had a reviewer that answered
  and were merged anyway.
- **One review per PR — fix findings, don't re-trigger.** Address every review comment,
  push the fix, and reply once stating what changed (or why you disagree). Do **not** ask
  for a re-review to confirm your fixes: a re-review of addressed findings reliably finds
  nothing and costs a full session. Request one (`@coderabbitai review`) only after a
  *substantial rewrite* that invalidates the original review. Repos should pin this with
  `.coderabbit.yaml` (`auto_review.enabled: false`, `auto_incremental_review: false`,
  `chat.auto_reply: false`) so it holds by default rather than by everyone's discipline.
  **The reply is a list, not a letter** — same discipline as the PR body, same reason:

  ```md
  - Finding 1 — fixed: `foo.sh` now quotes `$dir` (a1b2c3d).
  - Finding 2 — not taking: the path is `mktemp -d`-owned, never user input.
  - Finding 3 — fixed: added the null case, `foo.test.sh` 41/0.

  Evidence: `foo.test.sh` 41/0 · CI run 1234 green · `shellcheck` clean.
  ```

  One line per finding **fixed** (what changed, and where), one line per finding **not
  taken** (with the reason), and the evidence as a short list at the end. **Never restate
  the finding back at the reviewer** — it wrote the finding, it still has it, and quoting
  it back is the single biggest source of reply length. The reviewer is deciding whether
  each finding is closed, not re-reading its own review. If you disagree, say so once with
  the evidence and move on (the two-round cap below is what ends it, not persistence).
- **A GitHub comment is about 280 characters — roughly a tweet.** This covers the two
  surfaces the shapes above never reached: an **inline code comment** and a **PR thread
  comment**, whoever writes them. Longer only when the finding genuinely needs it — a race
  whose trigger takes three sentences to state — and **never by default**.
  **280 is what a comment MAY cost, never a reason to write one.** The inline half is
  gated first by the row in "Write less": none unless the code is unusual, risky to change,
  or carries a trap — so the usual number of inline comments in a diff is **zero**, and 280
  bounds the one that clears the trigger.
  **The shape is: what is wrong, where, and what to do.**

  ```md
  `run.sh:42` — `$dir` is unquoted, so a path with a space splits into two arguments.
  Quote it: `rm -rf "$dir"`.

  Evidence: `harness-temp-safety.test.sh` 12/1 · `shellcheck` SC2086.
  ```

  Nothing else. **Never restate the diff back at the reader** — the host prints the lines
  you are commenting on directly above your comment, so summarising them is pure length.
  **No incident history, no rejected alternatives**, no essay on why the class of bug
  matters: that reasoning belongs in the commit message and the task doc, exactly as it
  does for the PR body. **Evidence as a short list, not prose.**
  **The verbosity is not needed for the agent readers either** — that was the open
  question, and the answer is no. A reviewing agent reads the **diff** and the **criteria
  table**, not our narration, and no clearance predicate in `SCHEMA.md` reads a comment
  body at all. So **brevity costs nothing on either side**: the human gets a comment they
  can act on, and the agent gets exactly what it was already reading.
  **Measured, so the target is grounded rather than a taste.** On `monorepo#3244`, our
  agents averaged **2,027 characters** across 6 inline comments; the two human reviewers on
  the same pull request averaged **120** across 2 — **17x the humans**, and 7x a tweet. The
  short form landed for PR bodies, review replies and progress reports while comments kept
  the old habit, because nothing named them as a surface. They are named here, and
  `tests/pr-body-shape.test.sh` keeps them named.
  **Read the 6 as well as the 2,027.** The humans wrote 2 comments where the agents wrote
  6, so the count was half the gap and a shorter budget would have fixed neither — which is
  why the row above became a trigger on 2026-09-11 instead of a smaller number.
- **A reply to review findings has a shape, and now it has a reader.** The list form above
  is the rule; this is the part a gate can check. It exists because the reply style was
  prose-only on the one surface nothing read — `pr-body-clearance.sh` reads a PR *body* and
  never a comment — and on 2026-08-31 a reply whose whole content was *"both findings are
  valid, neither is fixed in this PR, and here is why"* ran to **2,986 characters over 20
  lines**: about 250 characters of decision in twelve times its own weight. The shape:

  ```md
  Round 1 addressed in `a1b2c3d` — one entry per finding, no re-review requested.

  1. **`run.sh:42` unquoted `$dir`** — fixed: quoted it, `harness-temp-safety.test.sh` 12/0.
  2. **`http.ts` timeout is per attempt** — already deferred: item 3 on the task's list.
  3. **no test for a 200 with no token** — declined: unreachable until slice 4 registers it.

  Evidence: `foo.test.sh` 41/0 · CI run 1234 green.
  ```

  **Each entry carries a VERDICT** — *valid / fixed / declined / already deferred* — and
  then the fix or the reason, and nothing else. The verdict is to a reply what the `✓`/`✗`
  column is to the criteria table: the one thing the reviewer on the other end must read,
  and what tells a reply to findings from any other list.
  **`scripts/pr-comment-clearance.sh --comment <id>` is the reader**, and
  `--comment-file <draft>` decides before you post — the cheapest moment, because an edited
  comment has already notified everyone who was watching. It refuses an entry with no
  verdict at **exit 1** and any element over **618 bytes** at **exit 3**, naming the element
  and its measured size; a comment it cannot fetch or read is **exit 2**, which is unknown
  and never clearance.
  **It bounds ONE ELEMENT, never the reply.** The lead, each entry and the closing evidence
  block are bounded separately, so **N findings buy N entries**: a reply addressing eleven
  findings clears at eleven times the budget of one addressing one. A total character cap is
  the opposite rule and the wrong one — it refuses the legitimately detailed reply and
  clears the short self-defending one. The two best-shaped replies measured are **2,149 and
  1,744 characters and both clear**.
  **618 is measured, not round.** Over every comment this repo's own agents wrote on pull
  requests 60–84 (16 replies, 65 elements, bytes under `LC_ALL=C`) plus the motivating
  comment: it is the midpoint of the empty band **531–705**, 88 clear of the largest element
  measured (530) and 88 short of the smallest one the incident calls bloat (706). It refuses
  13 of those 65 elements. **Moving it means re-measuring** —
  `tests/pr-comment-clearance.test.sh` pins the boundary values and drives a mutant in each
  direction.
  **What gets cut is the self-defence, not the detail.** The excess in the measured reply
  was *"this is the third time an independent reviewer has converged…"* and *"for the
  record, the branch is not untested…"*; neither changes what the reader does next. **The
  detail is relocated, never deleted** — it goes in the **task doc**, the **commit message**
  or a **`Finding`**, and **the short entry links to it**, exactly as "reasoning belongs
  where it is durable" says two rules up.
  **Three things are NEVER trimmed, and the reader honours them:** an **error report**, a
  **security finding**, and a **destructive-action confirmation**. A reply that leads a line
  with one of those clears at any element size, and the clearance quotes the line that
  claimed the exemption so the exemption is visible rather than silent. The failure mode of
  a terseness gate is trimming the one thing the reader needed in order to act safely.
- **TWO ROUNDS, THEN THE HUMAN DECIDES. This is a hard cap.**
  A reviewer's job is to evaluate the diff **against the task's `acceptance_criteria`**.
  It is *not* to re-litigate those criteria, argue the design, or look for a reason the
  change should not land. Grade the work against the bar it was given.
  - **Round 1** — the reviewer reports findings. The implementer fixes them and replies
    once, saying what changed or why it disagrees.
  - **Round 2** — the reviewer checks *only the things it raised in round 1*. New
    findings outside that set are **recorded, not blocking**.
  - **There is no round 3.** Anything still unresolved after round 2 **stops and goes to
    the human**, with both positions stated in one short block: what the reviewer wants,
    what the implementer says, and what the criterion actually asks for. The human
    decides; the agents do not converge on it.
  **Why this is a hard number and not a guideline.** ai-bridge#34 ran **eight rounds**,
  and rounds 3-8 produced adversary-shaped findings against a change that already met its
  criteria — the reviewer kept finding new ground to contest because nothing told it to
  stop. That single PR, and others like it, consumed roughly **70% of a Max account's
  weekly budget**. An unresolved disagreement costs the human one decision; an unbounded
  review costs a week.
  **And the number is countable — `scripts/review-rounds.sh <pr> --repo <org>/<repo>`.**
  It prints how many rounds a PR has already had and **exits non-zero at or past two**, so
  whoever is about to spawn a verifier can be refused instead of trusted to remember. Run
  it *before* dispatching one (the `project-manager`'s verification step) and *before*
  verifying one (`qa-reviewer` mode B, first thing); non-zero means stop and write the
  both-positions block above. It counts **completed verifications of distinct commits**,
  decided by `review-clearance.sh` — so a rate-limited reviewer's refusal, which publishes
  a green check and names the head in its own body, is **not** a round, and an absent
  reviewer adds none. Exit 2 is *unknown*, which is not permission. A missing or broken
  script exits non-zero too, so the failure direction is "ask the human", never "review
  again". This rule spent a week of budget while it was prose; it is not prose now.
  **Corollary — grade against the criteria, not against your own taste.** If you believe
  the criteria themselves are wrong, say so *once*, in the verdict, as a note to the
  human. Do not express it by withholding a pass.
- **Resolve a dispatched agent's model with `scripts/resolve-model.sh <agent>`, never from
  memory.** `roleTiers`/`models` in `instance.config.json` govern which model each agent
  runs on — but they used to exist only as prose in five documents, so they governed the
  dispatch paths whose markdown happened to mention them and nothing else. Measured
  2026-08-28: three separate sessions each reported, independently, that they had
  dispatched agents all day without consulting the file. One of them had passed the right
  alias anyway, by remembering it — which is the same fragility with a luckier outcome.
  The script prints the alias, or prints nothing and exits 1 when the agent has no entry.
  **It is not quiet about that: it prints why on stderr — report that line to the human,
  then inherit the session model and do not guess.** Exiting silently was the failure
  shape rather than the fallback: an unresolved role looks exactly like a resolved one at
  the call site, so every role can run on the wrong tier with nothing anywhere saying so.
  `/loopd:init` seeds `models`/`roleTiers` into `instance.config.local.json`, which is where
  the fix goes. This applies to **every** dispatch, including an ad-hoc dispatch from a
  main session, which is exactly the path the prose never reached.
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
- **Anything you background must be reaped by something that outlives YOU.** A rule about
  the whole CLASS — every child you put in the background, whatever it happens to be: a dev
  server, a watcher, a file-watch probe, a long build, a load generator you wrote to
  reproduce a flake. It is this repo's ONLY rule about backgrounded children, and it
  subsumes the dev-server teardown rule that used to stand here: that one named servers, so
  it had nothing to say about the 34 spinners below. **A rule that enumerates kinds of
  process is a rule that misses the next kind**, which is why this one names none.
  **It does not ban backgrounding.** Background the long build, the dev server, the
  deliberate load generator — that is legitimate work and none of it is being taken away. A
  "fix" that deletes the `&` satisfies nothing here: what is required is a REAPER, not
  abstinence.
  **The bound goes on the CHILD ITSELF, and that part is not optional.** Measured
  2026-08-31: an agent generating CPU load to reproduce a flaky suite started ten
  `(while :; do :; done) &` spinners, captured their pids, and put the `kill` at the end of
  the script. Its shell died before that line ran — **34 orphans across three batches, every
  one reparented to `ppid 1`**, at ~24% of a core each, running 3, 15 and 16 minutes with
  nothing left on the machine that could ever reap them; load average 310, 0% idle. A
  `trap … EXIT INT TERM` needs you alive to fire and a process-group kill needs someone left
  to issue it, so **both were already defeated** by the time anyone looked. Add them if you
  like; neither may ship as the whole answer. Same class with a slower fuse: two `pnpm dev`
  servers found still running after **2 days 16 hours** and **2 days 13 hours**
  (2026-08-27), from worktrees whose tasks had merged long before.

  ```sh
  # bg_bounded <seconds> <command…> — a bound that still holds when this shell is gone.
  bg_bounded() {
    local secs=$1; shift
    if command -v timeout >/dev/null 2>&1; then
      timeout "$secs" "$@" &                       # coreutils. NOT on a stock macOS
      return
    fi
    "$@" &                                        # no timeout: bound it with a watchdog
    local child=$!
    # A SIBLING, so it fires whether or not we live. `>/dev/null` is not tidiness — see below.
    ( sleep "$secs"; kill "$child" 2>/dev/null ) >/dev/null 2>&1 &
  }
  ```

  The watchdog is a sibling rather than something this shell does later, and that is the whole
  trick: it is already detached when we are killed, and `sleep` bounds the watchdog itself, so
  nothing is left running either way. It outlives a child that finishes early by up to `secs`
  — so keep the bound in minutes, not hours — and `kill`ing it once you have reaped the child
  is a fine ADDITION.
  **Redirect the watchdog's stdio, and know why:** killing `( sleep N; … ) &` kills the
  SUBSHELL and leaves the `sleep` behind, and a `sleep` that inherited your stdout holds the
  pipe open — so a caller reading your output with `$( … )` (this repo's own CI loop does)
  blocks for the rest of the bound on a job that finished. Measured while writing this rule:
  a harness that took 15 seconds took 99.

  A loop you wrote yourself needs no watchdog at all — carry the deadline inside it:
  `end=$(( $(date +%s) + 300 ))`, then `while [ "$(date +%s)" -lt "$end" ]; do …; done`.
  **Two readers, because what stood here was prose and prose did not stop this:**
  `tests/background-teardown.test.sh` fails the build on a background spawn in this repo's
  own `scripts/` and `tests/` that carries no bound (an allowlist entry has to state its
  reason), and the welcome skill’s `check` (`/loopd:welcome check`) carries a row naming every orphaned process whose cwd is
  under `worktreeRoot` — the one line that would have printed all 34. `prune-worktrees.sh`
  still reports a worktree with a live process attached. All three only ever REPORT, so the
  teardown is yours, and your report still says what you stopped.
- **A dispatch is not finished until its artifact exists — check, don't believe the
  report.** When an agent you dispatched reports back, run `scripts/check-dispatch.sh
  <task-doc>` before you act on what it said. It reads three things and judges nothing
  else: did `status:` advance, does `pr:` name a URL, and does that pull request exist.
  Exit 0 is the only clearance — exit 1 is the parked signature (still `ready`/`in-progress`
  with no PR), 3 a `pr:` the host does not resolve, 4 a record contradicting itself, 2 a
  question it cannot answer. **Exit 0 does not mean "there is a PR":** a task the agent left
  `blocked` or `cancelled` with no PR also clears, because no artifact was due — read the
  stated reason rather than reading a stopped task as a verified artifact. Measured 2026-08-28: two agents finished their work, committed
  it — one had already pushed — then ended their turns waiting on a background job that
  nothing was left running to notify, and **reported as completed** with no PR open. The
  wall-clock rule missed it (one parked at **16 minutes**), the two-round cap missed it
  (neither reached review), and the completion notification *was* the failure. Asking
  whether the PR exists takes two seconds and nothing was doing it. This applies to
  **every** dispatch, including an **ad-hoc** dispatch from a main session — the path with
  no coverage at all today, because no tick ever reads it.
  **It is report-only, and that is the point: a non-zero verdict is never a licence to
  re-dispatch.** Re-running a task sequence that already finished is the most expensive
  failure this loop has (`/loopd:dispatch` step 2), and the usual recovery is one message to the
  parked agent telling it to open the PR on what it already has.
- **Wide work: fan out only if you actually can — most of you can't.** For genuinely wide,
  *independent* work a parallel fan-out beats grinding serially (find the real edges → fan
  out → verify → synthesize), but check your `tools:` list before you plan around one.
  **No role agent's allowlist contains `Workflow`**, so the `Workflow` idiom is dead for
  every one of you and is deliberately not written here as an option — granting it is a
  standalone decision with its own cost, not something a convenience clause settles. Only
  `qa-reviewer` holds `Agent`, so only `qa-reviewer` can fan out at all, and it does so by
  dispatching several agents in parallel. `software-engineer`, `devops-engineer` and
  `failure-analyst` hold neither: **for you, wide work is sequential**, and that is the
  intended behaviour rather than a gap to route around — say so in the PR body and lean on
  the PR-size heuristic above if the result is large. Whoever *does* fan out: **read-only**
  fan-out (review, audit, research, code-navigation) needs **no worktree isolation**
  (nothing writes) but still obeys the instance's concurrency/resource limits (the
  `maxAgentsInFlight` cap) — it does **not** license unlimited dispatches; a **write**
  fan-out must *also* give each subagent its own worktree — never parallel writes to a
  shared clone/worktree (the same collision the per-task isolation rule prevents). Skip it
  for small/sequential work (pure overhead). `/loopd:dispatch` stays serial — a fan-out lives
  *inside* a task, never at the loop level.
- **A subagent works ONE task, and is resumed only for that task's next round.** Waking a
  completed agent with a message reuses its context, and reuse is right exactly while that
  context is about *this* work. **This is the one statement of the rule.** Everywhere else
  cites it and carries at most its one line, word for word, so the copies cannot drift:

  > same task and same PR ⇒ resume; anything else ⇒ dispatch fresh; a tick ⇒ never

  In full:

  | What you would hand it | |
  |---|---|
  | The **same task**, the **same PR**, the next round — review findings, a re-rebase, "open the PR on what you already have" | **RESUME.** It knows this repo squash-merges and which `--onto` base to use; a cold agent re-derives that at real cost. |
  | A **different task**, a **different PR**, or an unrelated ad-hoc job | **DISPATCH FRESH.** |
  | A `project-manager` **tick** | **NEVER RESUME — no exception, no "unless".** |

  Measured 2026-08-30: one `software-engineer` resumed three times — two rebases and then
  a round of review findings — ended carrying 163k tokens; a resumed tick produced two
  concurrent ticks. The tick case is absolute because a resume never passes through the
  launcher that takes the dispatch lock, and because it re-enters a loop whose state has
  moved on.

  **Which half of this has a reader, said plainly rather than left to sound enforced.**
  The tick half is CHECKED, and the reader is named so you can go and look: the control
  panel's `scripts/tick-lock.sh` refuses a tick acquire that finds no lock (exit 4) — no
  lock means no launcher, and no launcher means nobody dispatched that tick. Nothing on
  your path reads that file; only the loop and the tick do. The same-task half, by
  contrast, is NOT checked and cannot be, because nothing can see the intent behind a
  message; it is held by whoever dispatches, which is why it is written here and in the
  dispatchers' own instructions instead of being asserted somewhere no one reads. **Most readers of this file dispatch nothing** (see the
  wide-work bullet above), so for you it is the rule your dispatcher follows, and it
  cashes out as one thing: a message picking up **your own task's** next round is
  legitimate work; anything else should have been a fresh agent, and saying so is better
  than quietly absorbing it.

  **No "delete the agent" primitive exists and none is wanted** — agents complete on their
  own, so resumption is the only lever there is. That is why this rule is about resumption
  and not about how long an agent lives.
- **A round that ends on a failed check or a reviewer refusal appends ONE line to the
  task's `do_not_repeat:` BEFORE you stop.** Anything short of a green PR — a check you
  could not get green, a reviewer refusal you did not take, a blocker — and the last thing
  you do before writing `# Result` is
  `scripts/do-not-repeat.sh append <task-doc> --line "<approach> — <evidence>"`.
  **One line, at most 200 characters** (the script folds whitespace and truncates): the
  approach you took and the evidence it failed on, not the story of the round —
  `"widened the ERE to allow closed ATX — pr-body-shape.test.sh 40/2, rows 3 and 7 still refused"`.
  **The next dispatch receives those lines verbatim in its brief**, which is the only thing
  standing between a fresh agent and your wall: it has no memory of your round, and
  `stall_count` says how MANY rounds, never what was tried. **The evidence is the check,
  never its output** — no pasted log, no secrets, no PII, same rule as `last_blocker`.
  The list caps at 10: at the cap the script refuses (exit 1) and the `project-manager`
  folds the oldest into `# Notes`. A round that ends green appends nothing.
- **A task's `open_caveats:` outranks what you were told, and it holds `done`/`cancelled`
  until evidence clears it** — never your own conclusion that the caveat no longer applies
  (`SCHEMA.md` → the field; the bundle validator errors on that write while the list is
  non-empty). It is not a promotion gate and never blocks your round.
- Write the PR URL and a `# Result` summary back into the task document, and set
  the task `status: in-review` (or `blocked`, with why, if you can't proceed).
- **No customer PII** in code, commits, or PR text; **never echo, print, or log
  secrets or environment variables** (rely on existing env / `.npmrc` for auth).
- **Capture knowledge:** if you discover something durable and reusable, write or
  update a `Finding` in `knowledge/findings/` (per `SCHEMA.md`) and link it from
  the task, so the next agent doesn't re-derive it. It carries **`provenance: machine`**
  (`SCHEMA.md` → `provenance:`) — never on a document a person wrote. **Run
  `scripts/validate-bundle.sh <path>` on the one you just wrote** — it is the 40-line cap
  and the `lesson:` checked at the moment they are cheap to fix.
  **Where `knowledge/` is MOUNTED from another repository** (`knowledge` in
  `instance.config.json`; `SCHEMA.md` → "A mounted knowledge base"), **you do not write
  into it** — return the `Finding` in your result exactly as you would anyway and the tick
  commits it. There is **one writer per bundle** and it is the tick, so up to
  `maxAgentsInFlight` agents never share one git tree. `commit-as.sh` refuses a path under
  the mount by name, so a stale instruction fails loudly rather than committing nothing.
  **Absent the key nothing changes** and `knowledge/` is the bundle's own folder as before.
- **Record a papercut — ONE line, and the bar is "it hurt", not "it is durable".** A
  `Finding` costs 40 lines and a judgement call, so the small stuff never gets written down
  at all: a tool that failed, a doc that misled you, a step you did twice. Those go in the
  bundle's `knowledge/papercuts.md`, one appended line each:

  ```sh
  scripts/papercuts.sh add --task <project>/task-0NN --surface script:validate-bundle.sh \
    --note "exits 0 on an unreadable file, so a dangling ref reads as clean"
  ```

  Run it at the bundle root (where the task document lives), not in your worktree — or pass
  `--file <bundle>/knowledge/papercuts.md`. `--surface` names the file that should CHANGE:
  `skill:`, `agent:` or `script:`, then its name. The note is **15-160 bytes** and the tool
  refuses anything else, which is the whole shape.
  **Append, never edit or delete — including your own lines.** Ten entries naming one
  surface are the evidence that surface needs work, and they only read as ten while nobody
  tidies them; a wrong entry is corrected by a new entry. The `cataloguer` groups the
  record by surface and proposes the concrete edit as a `draft` task, which is what makes
  writing the line worth your ten seconds.
- **Cite knowledge as `[[finding-slug]]`, and only ids your brief actually carried.** A
  bracketed slug is the ONLY thing that counts as a citation — a title in prose, *"as the
  worktree finding notes"*, a bare link: all references, none of them citations, and
  nothing reads them. The slug is the file's name without `.md`, and **`knowledge/index.md`
  is the id source of truth**: the `cataloguer` writes one row per doc there, so a slug in
  no row names no document at all.
  **Then the citation is checked instead of trusted.** `scripts/cite-check.sh --text-file
  <f> --brief <slugs>` keeps the ids the brief carried, drops the rest, and grades what is
  left — **exit 0** nothing dropped, **exit 3** dropped but every citing line still cites
  something, **exit 1** a citing line ended up with none, which is a claim whose whole
  provenance vanished and is flagged rather than accepted (**exit 2** is unknown: no index
  to judge against). Run it on your own `# Result` before you hand back; the
  `project-manager` runs it again at reflect time.
  **The two ways an id gets dropped are reported apart, and that distinction is the
  point.** An id that IS an index row but was not in your brief is **`UNREAD`** — a real
  document nobody read, which is a briefing gap. An id in no row is **`FABRICATED`** —
  invented provenance, which is a different failure with a different fix. Collapsing them
  into "invalid" loses the only thing the report was for. It is a cheap control and a
  narrow one: it proves an id was in front of you, never that the claim you hung on it is
  true.
- **Parallel-safety:** if the product repos share one clone / one package store,
  each agent uses its own worktree under `worktreeRoot` (from `instance.config.json`
  — outside any synced folder; **never** inside `reposRoot`. Absent that key, fall
  back to `<reposRoot>/_wt`) and a **private package
  store** (e.g. `pnpm install --store-dir <worktree>/.pnpm-store`), and pushes
  early.
  **THE HOOK CREATES IT — CHECK BEFORE YOU CREATE ONE.** A session started as
  `claude --worktree <task-id>` is placed by `plugin/hooks/worktree-create.sh` in
  `<worktreeRoot>/<task-id>` of your `target_repo`, on the task's `branch:`, and that is
  your cwd from the first turn. `pwd` and `git rev-parse --abbrev-ref HEAD` answer it in
  two commands. Already there ⇒ **do not add a second worktree** — you will branch off
  your own branch and open a PR against it.
  **Only when it did not**, which is every in-session subagent dispatch (the hook's payload
  carries `agent-<opaque-id>`, never the task, so it cannot place one for you):
  `git worktree add <path> -b <branch> origin/<default-branch>`. Don't rely on the
  `EnterWorktree` tool, which may be unavailable to you as a subagent.
  (`settings.json` sets `worktree.bgIsolation: none` so the control panel manages
  worktrees itself; harness isolation would only isolate this repo, not the product repos.)
  **Nothing deletes your worktree while you are working in it, and what deletes it after
  refuses on anything of yours.** `prune-worktrees.sh` still only prints removal commands;
  the one thing that deletes is `reclaim-worktree.sh`, which the tick runs for a task that
  is `done` with every PR MERGED — and it refuses a dirty tree, an unpushed commit, a
  detached HEAD, an ignored file that is not a known cache, and a live process inside the
  tree. So uncommitted work is never taken from you; it just means the tree stays, and
  nobody tidies it.
  **Scratch files go in `<worktree>/tmp/`, never a shared scratchpad.** Mutation
  scripts, probe output and throwaway configs collide when several agents run at once.
  Keep them inside your own worktree — verified working with three concurrent agents on
  one tick.
  **A scratch path that the repo does not IGNORE is not scratch.** Until 2026-09-09 this
  rule named a directory `cbmono/loopd` TRACKS, so an obedient agent wrote its drafts
  into version control and its own cleanup deleted a tracked file. `tmp/` is ignored by
  every bundle this seed stamps and by that repo; elsewhere, `git check-ignore -q` before
  you write, and pick a path the repo does ignore if it says no.
  **It fails silently:** two agents sharing one scratchpad path on 2026-09-08 overwrote
  each other's PR-body draft, and the body that got posted was well-formed, merely the
  wrong task's. `prune-worktrees.sh` recognises `tmp` as scaffolding, so obeying
  this never leaves you a worktree that reads as dirty forever.
- **Browser (only if the project opts in):** when the task's project sets `browser:
  claude-for-chrome` **and** the `mcp__claude-in-chrome__*` tools are actually present,
  **rung 1 above applies to the browser like any other tool**: verify the change in the
  real page, read the logged-in view, take the screenshot. This paragraph used to state
  that as a browser-only rule; it is the general one now, stated once, so the two cannot
  drift. You get your **own tab group**, not the human's tabs, so always navigate from an
  explicit URL. Tools absent (e.g. a headless tick) → **that is a capability gap, so take
  the non-browser route, say so, and carry on** — never report blocked *only* for a missing
  browser. **Browser writes follow the project's
  `autonomy`:** **ask first** — that's the default and the only behaviour unless the project
  delegates writes (`AUTONOMY.md` at the bundle root defines the modes; no such file means
  always ask). Read-only navigation and screenshots never need asking. Scope discipline
  still applies — a write nobody asked for isn't licensed by autonomy. And
  no customer PII from a logged-in page
  ever reaches a task doc, PR text, `log.md`, any log or console output, or the KB.
  Describe the *shape* of what you saw, not the records. Full rules: `SCHEMA.md` →
  "Browser access".
- **Reading a product repo: a question that would take more than a few files to answer
  goes to an `Explore` subagent; a direct `Read` is for the file you are about to edit or
  verify.** Explore returns the conclusion instead of the file dumps and runs on the cheap
  `explorer` tier. Measured by the owner on one monorepo, 5 real questions: Explore 5/5,
  plain grep 4/5, CodeGraph 1/5. It is scoped to the target repos this document governs —
  `auditor` and `advisor` read the bundle, not a product repo, and this changes nothing
  for them.
  **The direct read is the other half of the rule, not a fallback from it:** a summary
  carries no reliable line numbers, so an edit never works from one. Locate with Explore,
  then read the one file you are about to change.
  **Which route you take is decided by your own `tools:` list, not by what is installed on
  the machine.** Hold `Agent`? — `qa-reviewer` does — dispatch an Explore subagent on the
  model your dispatch brief names (`scripts/resolve-model.sh explorer`; no entry ⇒ the seed
  default `light`, and the brief says which it is). Don't hold it? — `software-engineer`,
  `devops-engineer` and `failure-analyst` don't — then the second half is your whole route:
  narrow with `Grep`/`Glob`, read only what you will edit or verify, and put the `Agent`
  request in the task's `open_questions` (the middle rung above) when a question genuinely
  needed the delegation.
- **`codegraph` (if present) keeps exactly one job: TypeScript blast radius.**
  `codegraph node <sym>` for one symbol's callers/callees, `codegraph impact <sym>` /
  `codegraph affected <files>` before a change. Don't reach for it first for anything else
  — in the measurement above it placed last, it indexes no SQL, and its index is a stale
  snapshot that reports itself current. Skip silently if absent; it's an optional local
  index (see the loopd README).
