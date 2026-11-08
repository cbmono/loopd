# Conventions detail: review

Detail for `../CONVENTIONS.md` — moved there verbatim, so the core stays short. Open a section only when the core's pointer to it names a trigger that applies. **The core wins on any disagreement**; fix this file to restate it.

### Ask for the independent review once, at the head you consider final

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

### Resolve or answer every reviewer-authored thread before you re-request

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

### One review per PR — fix findings, don't re-trigger

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
  the evidence and move on (the round cap below is what ends it, not persistence).

### A GitHub comment is about 280 characters

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

### Every PR comment and review an agent posts ends with its role signature

- **Every PR comment and review an agent posts ends with its role signature** — the line
  your brief's `## Signature` call prints (`scripts/role-signature.sh <role> --instance
  <bundle>`), `— <login>-<qa|dev|ops|pm>`. Every agent posts under one login and GitHub
  shows no other name, so this is how a human tells the QA verdict from the implementer's
  reply. It is the **last visible line**, directly under the line above with **no blank
  line** — but **never directly under a table**, where it renders as one more row; end
  with a text line first (a separate block becomes `pr-comment-clearance.sh`'s closing block and folds your
  evidence into the last entry); an `okf-verdict v1` trailer, an HTML comment, still goes
  after it. **A label, never evidence:** the implementer can type it too, so no gate reads
  it. **Exempt:** a PR body, and the tick's bare `@coderabbitai review`, which must stay bare.

  ```md
  Evidence: `foo.test.sh` 41/0 · CI run 1234 green.
  — example-user-007-dev
  ```

### A reply to review findings has a shape

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

### TWO ROUNDS, THEN THE HUMAN DECIDES

- **TWO ROUNDS, THEN THE HUMAN DECIDES. This is a hard cap** — per reviewer, set by
  `coderabbitRounds` and `qaRounds` in `instance.config.json` (**1** each when absent).
  The heading keeps the cap's original number because agents and scripts cite it by name;
  the number in force is whatever those two keys say.
  A reviewer's job is to evaluate the diff **against the task's `acceptance_criteria`**.
  It is *not* to re-litigate those criteria, argue the design, or look for a reason the
  change should not land. Grade the work against the bar it was given.
  - **Round 1** — the reviewer reports findings. The implementer fixes them and replies
    once, saying what changed or why it disagrees.
  - **Round 2**, where the cap allows one — the reviewer checks *only the things it
    raised in round 1*. New findings outside that set are **recorded, not blocking**.
  - **There is no round past the cap.** Anything still unresolved after the last round
    **stops and goes to the human**, with both positions stated in one short block: what
    the reviewer wants, what the implementer says, and what the criterion actually asks for. The block goes in
    the task's `open_questions`, not the final message. The human decides; the agents do
    not converge on it.
  **Why this is a hard number and not a guideline.** loopd#34 ran **eight rounds**,
  and rounds 3-8 produced adversary-shaped findings against a change that already met its
  criteria — the reviewer kept finding new ground to contest because nothing told it to
  stop. That single PR, and others like it, consumed roughly **70% of a Max account's
  weekly budget**. An unresolved disagreement costs the human one decision; an unbounded
  review costs a week.
  **And the number is countable —
  `scripts/review-rounds.sh <pr> --for coderabbit|qa --repo <org>/<repo>`.**
  It prints how many rounds that reviewer has already spent on a PR and **exits non-zero at
  or past its cap** (`coderabbitRounds` / `qaRounds`, 1 each when absent), so
  whoever is about to spawn a verifier can be refused instead of trusted to remember. Run
  it *before* dispatching one (the `project-manager`'s verification step) and *before*
  verifying one (`qa-reviewer` mode B, first thing); non-zero means stop and write the
  both-positions block above. It counts **completed verifications of distinct commits**,
  decided by `review-clearance.sh` — so a rate-limited reviewer's refusal, which publishes
  a green check and names the head in its own body, is **not** a round, and an absent
  reviewer adds none. **An automatic incremental review counts, by design** (owner
  decision 2026-10-21): where a repo leaves CodeRabbit's `auto_incremental_review` on,
  its review of the first fix push is a completed verification of a new commit, so it
  *is* another CodeRabbit round even though nobody asked for it. At the cap, the last
  round's fix merges with no re-review within `reviewFixMaxLines` (`AUTONOMY.md` → "Merge
  after the last round"); that never moves where a reviewer's cap is. Exit 2 is *unknown*, which is not permission. A missing or broken
  script exits non-zero too, so the failure direction is "ask the human", never "review
  again". This rule spent a week of budget while it was prose; it is not prose now.
  **Corollary — grade against the criteria, not against your own taste.** If you believe
  the criteria themselves are wrong, say so *once*, in the verdict, as a note to the
  human. Do not express it by withholding a pass.
