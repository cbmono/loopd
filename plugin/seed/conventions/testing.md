# Conventions detail: tests and evidence

Detail for `../CONVENTIONS.md` — moved there verbatim, so the core stays short. Open a section only when the core's pointer to it names a trigger that applies. **The core wins on any disagreement**; fix this file to restate it.

### The full suite belongs to CI

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
  ([loopd#42](https://github.com/cbmono/loopd/pull/42)), and branch protection sets
  **`strict=true`**, which forces that check to run **against the merged base** before the
  PR can land. Your machine cannot produce that verdict, so skipping the local full run
  asks nobody to trust **less** verification — it moves the verification to the only place
  the merge gate actually reads. `tests/local-vs-ci-testing.test.sh` in `cbmono/loopd`
  pins the clauses above by name.

### A red check is EVIDENCE

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

### A read that could not have established the answer returns UNKNOWN

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
