---
paths:
  - "/tests/**"
---

# Test conventions

Loads when you read anything under `tests/`. bash harnesses, no framework, no
build step.

**Run the harnesses your change touches before pushing — not all of them:**

```bash
tests/run.sh --changed        # the core plus every harness that NAMES a path you changed
tests/run.sh --all            # all of them — once, before you open the PR, and never polled
tests/run.sh --all --jobs 4   # the pool is CPU-wide by default; bound it when you need the machine
tests/run.sh --deep           # ONLY the `# deep` harnesses: they spawn the claude CLI and cost money
tests/run.sh --iced           # ONLY the `# iced` harnesses: a subject on hold (today: the board)
bash tests/<one>.test.sh      # still fine while you iterate on one harness
```

`--changed` is the same selection CI takes on a plugin-only PR — any path outside `plugin/`
buys the full suite, and since every change carries its test that is every PR — because CI runs
`tests/run.sh --ci` — one implementation, and `tests/ci-workflow.test.sh` fails if the
workflow grows a second copy. It reads committed, uncommitted and untracked paths against
`origin/HEAD` (`--base <ref>` for another base). **No changed path runs the core; a changed
path no harness names runs the core and says so in one line** — never a zero-harness run
that reads as a pass, which is why `--all` is still the answer before the PR.
**Two tiers and a pool** (ai-bridge-v3/task-038). A harness declares `# serial` in its
header to run alone, and `# deep` to leave the merge gate altogether — `--deep` and the
nightly `tests-deep.yml` are the only things that run a `# deep` harness, and every other
mode puts a refusing shim in front of `claude` so no gate run can spend a paid eval. The shim
lets exactly two argument shapes through to the real binary, `claude plugin test …` and
`claude plugin validate …` — no session, no sign-in, no network, nothing spent — and
`AB_CLAUDE_REAL` names that binary (empty where the machine has none, as CI's runners do),
so a harness that needs it prints a SKIP by name instead of a vacuous pass. **`AB_NO_CLAUDE=1`
makes that probe answer empty on a machine that HAS one** — a binary that hangs at exec (a
fresh Gatekeeper quarantine) is found by `command -v` and sits a harness at the 600s kill
bound; the operator says so and gets the SKIP instead. It is a flag of its own rather than a
pre-set `AB_CLAUDE_REAL` because `run.sh` exports that, and a nested run would inherit it.
Everything else runs in a bounded pool, output replayed in file order.
**A third marker, `# iced`, pauses a subject without retiring it.** The owner put the board
on hold on 2026-10-05, and its twelve harnesses were still 241 of 3,015 harness-seconds on
every PR (run 37310865693) for a verdict nothing was moving. An iced harness runs under
`--iced`, in the nightly `iced tier` job of `tests-deep.yml`, and in a gate run **only when
a changed path names it or is it** — the case derivation is sound for. What that cannot see
is an iced harness reading a directory wholesale; the nightly catches it a day late, and
that delay is the accepted price. A pull request whose diff cannot be read runs them all.
**Never ice a live surface** — `session-banner`, `awaiting-queue`, `status-line` and
`push-state` run in every session and stay in the gate. Thawing is deleting the marker.

**The time budget.** A run prints its harness-seconds and its five slowest; a **full** run
over `SUITE_BUDGET_S` (**3600** when unset — 20 minutes on the 3-CPU runner) is warned, and
so is any one harness over `HARNESS_WARN_S` (**300** when unset, half the kill bound). It
**warns and never fails**: two runs of the same tree measured 3,015 and 4,108
harness-seconds on that runner, so a failing bound would be a coin. The suite had no budget
and grew 3,178 → 4,108 in a day. **A PR that adds a harness says in its body what the
harness costs in seconds** (the `took` line of a local run) and, when the suite is over
budget, what it replaces. CI writes the fifteen slowest to the job's step summary.
**Each harness is also bounded in wall clock** (`HARNESS_TIMEOUT`, 600s; 1800s under
`--deep`): the pool replays nothing until every worker is done, so a harness that never
returns would otherwise take the whole job down with an empty log — ai-bridge-v3/task-040.
Measured on an M3 Pro, 2026-09-13, `claude` masked off PATH: a one-line edit to
`plugin/scripts/commit-as.sh` selects 18 harnesses and takes **1m 21s** (was 2m 25s
sequential, and 9m 12s with the eval in the core); all 111 take **6m 15s** in a pool of
11, against **39m 47s** sequential. In CI, where the runner has 3 CPUs: **10m 35s**,
against 29m 45s sequential (run 34774374082).

The full suite is CI's job: `harness suite` is a required check, a push to `main` always
runs everything, and so does a PR whose diff touches anything outside `plugin/`. **That
is deliberate and must stay**: `--changed` derives a selection from the paths a harness
NAMES, and about 40 harnesses ask "is every file under `plugin/…` documented, executable,
linked, on brand?" and name none. Admitting `tests/*.test.sh` to the fast path (#324) let
a new script through without its README row and turned `main` red the same day. So
`--changed` is a local convenience, never proof — which is why `--all` is run once before
a PR. A full CI run measured **20m 10s** on 2026-10-04 (3,178 harness-seconds on the
3-CPU runner; the 10m 35s above was 111 harnesses, it is 141 now). Branch protection's
`strict` flag is **off** (read from the API on 2026-10-05) — a `pull_request` run tests the
merge of the branch into the base as of that run, and nothing re-runs it when the base moves. Locally the same loop measured **39m 47s and
269.4k tokens** (2026-08-29) before the pool, and tokens are still spent on a local run
that CI would do for nothing. So run it only when
your change touches shared machinery every harness loads, and say why in the PR body —
`plugin/seed/CONVENTIONS.md` → "The full suite belongs to CI" is the rule this defers to.

## The core

`tests/run.sh` always runs these nine, because no changed path can be expected to name
them — they read `plugin/` wholesale or reach their subject indirectly:

| Harness | Why it cannot be derived |
|---|---|
| `plugin-manifest`, `plugin-skills`, `plugin-agents` | structural, whole-tree |
| `agent-body-links` | it reads every `plugin/agents/*.md` wholesale and resolves each path from the body's own directory. Derivation would select it only for a changed agent body, and the defect it guards is a path that goes dead because something *else* moved — `plugin/seed/CONVENTIONS.md`, a script — with no agent file in the diff |
| `deny-baseline`, `agent-control` | the two enforcement **hooks** (ai-bridge-v2/task-003) |
| `commit-as-guard`, `companion-plugins` | the two-human-authority guard (ai-bridge-v2/task-030). Both are also reachable by derivation and stay here anyway: the guard's behaviour depends on `plugin/scripts/resolve-autonomy.sh`, which `commit-as-guard.test.sh` never names |
| `harness-read-paths` | it reads the whole `tests/` tree and resolves every literal path against the plugin tree — the one diff that names none of its own subject (ai-bridge-v2/task-029) |

Everything else is **derived**: a harness is selected because it *names* a changed path
(or a ≥2-component suffix of one — never a bare basename), so the next path move under
`plugin/` carries its own harness in. A hand-kept list is what let #124 move the authority
guard and leave its harness behind, with the required check green.

## Rules

- **`ok()` compares actual to expected, in that argument order**, and every harness prints its own `pass=/fail=` (or `N passed, N failed`) line and exits non-zero on any failure. Keep both.
- **Harnesses live here, never under `/plugin/`.** Everything under `plugin/` ships into every instance, and a fixture harness is not machinery an instance needs.
- **A test that only asserts the refusal is vacuous.** Assert **both directions** — that the guard fires *and* that the normal path still works. `installer-worktree-guard.test.sh` says so in its header: "It refuses in a worktree" alone would pass a script that refuses everywhere.
- **Assert the property, not the implementation text.** `derived-indexes.test.sh` checks `git check-ignore --no-index` rather than the pattern string; `snapshot.test.sh` asserts no key outside the documented allowlist is emitted.
- **Every capability that can be turned off needs a test proving it is off when the file is gone** — `commit-as-guard.test.sh` for `AUTONOMY.md`, `awaiting-queue.test.sh` for `AWAITING.md`. ([conventions 4](../../docs/conventions.md#4-a-capability-some-deployments-must-not-have-should-be-one-deletable-file))
- **A path that can emit a *false zero* or a false success is the highest-value thing to test here.** `push-state.test.sh` guards an authoritative `in-flight 0` produced by an unreadable file; `migrate-bundle.test.sh` guards a `FIXED` printed for a write that never landed.
- **Extend a `gh` stub to mirror real quirks rather than working around them in the script** — a 404 body goes to **stdout**, the "no required checks" message to **stderr**. `required-checks.test.sh` owns that stub.
- **Compare resolved paths.** `mktemp` hands back `/var/...` while git reports `/private/var/...` on macOS, so an unresolved grep fails on a correct message. This trap has appeared three times in this codebase.
- **`rule-globs-anchored.test.sh` asserts a measured fact the official docs contradict** — a `paths:` pattern is only root-anchored with a leading `/`. It is a test rather than a convention precisely because a convention that contradicts the documentation gets "corrected" back.
- **An operator-facing "run this" notice emits through `ab_say_run <lead> <script> [arg...]`** (`plugin/scripts/bundle-paths.sh`), so `printed-commands.test.sh` can execute what it prints; a `<slot>` or variable in it needs a stated dummy in that harness, or it goes red. A command welded into a sentence is invisible to it, and the sentence is what shipped `migrate-bundle.sh --layout --apply` against a parser that accepts only `--apply`.
- **Fixtures must not touch the user's real `~/.claude` or a real instance.** Build a throwaway repo under `mktemp -d` and copy the script under test into it.

## Run the suite from the MAIN checkout, never a worktree

Four harnesses — `derived-indexes`, `link-repos`, `snapshot` and `board-renderers` —
invoke this repo's own `init-bundle.sh --config`, which **refuses to run from a git worktree**
by design (it would create symlinks into a directory that `git worktree remove` later
deletes). So running the suite inside a worktree fails those four, well over a hundred
assertions, for a reason that has nothing to do with the code under test.

That is the guard working, not a bug — but it reads exactly like a regression, so: run the
suite from the main working tree, or from a fresh clone. None of the four needs `# serial`:
from a real checkout all 111 pass in the pool (measured 2026-09-13, 8,581 assertions, 0
failed). If you are working in a worktree,
clone to a temp directory to verify.

## The 256-descriptor cliff — why `harness-read-paths` hangs, and how to re-measure it

`/bin/bash` 3.2.57 leaks one file descriptor per `< <( )` **evaluated inside a `$( )`**;
at top level it leaks none. `harness-read-paths.test.sh` had **five** such sites per
harness inside `REAL="$(scan …)"` — one for `HERE`, one for each of the three
`ROOT_VARS`, one for the candidate `awk` pass — but four of the five are guarded by
`[ -n "$(assign_lines …)" ]`, and most harnesses bind only `HERE`, so **251 of the 560
possible sites actually fire across the 112 files** (2.24 per harness, 1 fd each) and the
capture ends on **256** open descriptors. Standalone the cliff is at ~254 substitutions —
253 survives, 254 is fatal — so the scan lands right on it, and **two inherited
descriptors are enough to cross**, which is all the pool has to leave behind. Past it a
`fork()` never returns: the child spins at 100% CPU in `_notify_fork_child`, holding the
capture's stdout, so every ancestor blocks.

`tests/tools/fd-cliff.sh` measures the margin in about two minutes (exit 1 while the
harness still hangs, 0 once it clears). It is deliberately not a `*.test.sh`: it fails
today. Measurements and the sampled stack: ai-bridge-v3/task-042.
