#!/usr/bin/env bash
#
# test-runner.test.sh — tests/run.sh, the ONE implementation of the harness selection
# CI and a local shell both use (ai-bridge-v3/task-028). It is EXECUTED against fixture
# repos, never grepped: a text check goes green on a selector that never reads its own
# core, which is the defect class ai-bridge-v2/task-030 was filed for.
# The workflow-side half — that .github/workflows/tests.yml calls this and carries no
# second copy — is tests/ci-workflow.test.sh.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)" || { echo "test-runner.test: cannot locate self" >&2; exit 2; }
REPO="$(cd "$HERE/.." && pwd)" || { echo "test-runner.test: cannot locate repo root" >&2; exit 2; }
RUNNER="$REPO/tests/run.sh"

pass=0; fail=0; skip=0
assert()  { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
            else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
summary() { echo; echo "pass=$pass fail=$fail skip=$skip"; [[ "$fail" == 0 ]] || exit 1; exit 0; }
has()     { grep -qF -e "$2" <<<"$1" && echo 0 || echo 1; }
lacks()   { grep -qF -e "$2" <<<"$1" && echo 1 || echo 0; }

echo "== tests/run.sh exists, is executable and parses =="
assert "$RUNNER exists"        "$([ -f "$RUNNER" ] && echo 0 || echo 1)"
assert "…and is executable"    "$([ -x "$RUNNER" ] && echo 0 || echo 1)"
[ -f "$RUNNER" ] || { echo "test-runner.test: no runner to exercise" >&2; summary; }
assert "…and is syntactically valid bash" "$(bash -n "$RUNNER" >/dev/null 2>&1 && echo 0 || echo 1)"

echo "== every path verify_checkout probes for exists in this repo =="
# Not a tautology — verify_checkout fails CLOSED, so a probe naming a path the repo no
# longer has refuses EVERY checkout before a harness runs. It happened: `symlink/` was
# in the list, ai-bridge-v2/task-013 retired it, and the suite went red at 6 seconds
# while every assertion that did not read the NAME stayed green.
probe_missing=""
while IFS= read -r d; do
  [ -n "$d" ] || continue
  [ -e "$REPO/$d" ] || probe_missing="${probe_missing:+$probe_missing }$d"
done <<EOF
$(sed -n 's#.*\[ -[de] "\$workspace/\([A-Za-z0-9._-]*\)" \].*#\1#p' "$RUNNER" | sort -u)
EOF
assert "…and the extraction found some to check (not vacuous)" \
  "$(grep -q . <<<"$(sed -n 's#.*\[ -[de] "\$workspace/\([A-Za-z0-9._-]*\)" \].*#\1#p' "$RUNNER")" && echo 0 || echo 1)"
assert "every probed path exists${probe_missing:+ (missing: $probe_missing)}" \
  "$([ -z "$probe_missing" ] && echo 0 || echo 1)"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-runner.XXXXXX")" || {
  echo "test-runner.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# The fixture's harness set is read out of the runner, so a name added to the core
# cannot leave the fixture behind.
core_names="$(grep -oE 'tests/[A-Za-z0-9_-]+\.test\.sh' "$RUNNER" | sort -u)"
core_count="$(printf '%s\n' "$core_names" | grep -c . )"
assert "the fixture's core set was read out of the runner" \
  "$([ "$core_count" -ge 5 ] && echo 0 || echo 1)"

# <root> — a base repo plus a clone of it, so `git fetch origin main` and
# `git diff origin/main...HEAD` both work for real in --ci mode.
build() {
  local root="$1" h
  mkdir -p "$root/base/tests" "$root/base/plugin/scripts" "$root/base/plugin/agents"
  cp "$RUNNER" "$root/base/tests/run.sh"
  for h in $core_names; do
    printf '#!/usr/bin/env bash\necho "pass=1 fail=0"\n' > "$root/base/$h"
  done
  # NAMES the guard's path and is on no list — it must be selected by DERIVATION.
  printf '#!/usr/bin/env bash\n# reads "$REPO/plugin/scripts/commit-as.sh"\necho "pass=1 fail=0"\n' \
    > "$root/base/tests/fp-names-the-guard.test.sh"
  # Names nothing that changes below — it must NOT be selected, which is what tells a
  # real derivation from a selector that simply runs everything.
  printf '#!/usr/bin/env bash\necho "pass=1 fail=0"\n' \
    > "$root/base/tests/fp-names-nothing.test.sh"
  # The three tier/pool fixtures. Each PRINTS what it saw, so the assertions below read a
  # real run rather than the runner's own announcement of what it meant to do.
  printf '#!/usr/bin/env bash\n# deep — costs money, gate tiers must not reach it\necho "deep ran tier=${AB_TIER:-unset}"\necho "pass=1 fail=0"\n' \
    > "$root/base/tests/fp-deep.test.sh"
  printf '#!/usr/bin/env bash\n# serial — must never run beside another harness\necho "pass=1 fail=0"\n' \
    > "$root/base/tests/fp-serial.test.sh"
  printf '#!/usr/bin/env bash\necho "tier=${AB_TIER:-unset} claude=$(command -v claude || echo none)"\necho "pass=1 fail=0"\n' \
    > "$root/base/tests/fp-tier.test.sh"
  # The iced fixture: on hold, and it NAMES one path so a diff of that path can thaw it.
  # path-scan: absent plugin/agents/iced-subject.md — fixture content, built below
  printf '#!/usr/bin/env bash\n# iced — its subject is on hold\n# reads "$REPO/plugin/agents/iced-subject.md"\necho "iced ran"\necho "pass=1 fail=0"\n' \
    > "$root/base/tests/fp-iced.test.sh"
  printf 'subject\n'   > "$root/base/plugin/agents/iced-subject.md"
  printf '#!/bin/sh\n' > "$root/base/plugin/scripts/commit-as.sh"
  # path-scan: absent — fixture content, deliberately named by no harness in this repo
  printf 'seed\n'      > "$root/base/plugin/agents/unread-by-any-harness.md"
  printf 'readme\n'    > "$root/base/README.md"
  ( cd "$root/base" && git init -q . && git symbolic-ref HEAD refs/heads/main \
    && git config user.email t@example.com && git config user.name t \
    && git add -A && git commit -qm base ) >/dev/null 2>&1
  git clone -q "$root/base" "$root/work" >/dev/null 2>&1
}

edit() { ( cd "$1" && printf 'edited\n' >> "$2" ) ; }                       # <workdir> <path>
commit_on_branch() {                                                        # <workdir> <path>
  ( cd "$1" && git checkout -q -b feat && printf 'edited\n' >> "$2" \
    && git add -A && git commit -qm edit ) >/dev/null 2>&1
}
run_ci()      { ( cd "$1" && GITHUB_EVENT_NAME=pull_request GITHUB_BASE_REF=main \
                    bash "${2:-$1/tests/run.sh}" --ci 2>&1 ) ; }            # <workdir> [runner]
run_changed() { ( cd "$1" && bash "$1/tests/run.sh" --changed --base main 2>&1 ) ; }

echo "== --changed derives from a COMMITTED diff: the core plus what names a changed path =="
A="$TMP/a"; mkdir -p "$A"; build "$A"
commit_on_branch "$A/work" plugin/scripts/commit-as.sh
A_OUT="$(run_changed "$A/work")"
assert "it announces a changed-path selection"                "$(has "$A_OUT" 'changed-path selection')"
assert "…names the changed path"                              "$(has "$A_OUT" '  changed: plugin/scripts/commit-as.sh')"
assert "…runs the core's commit-as-guard.test.sh"             "$(has "$A_OUT" '  harness: tests/commit-as-guard.test.sh')"
assert "…and a harness that merely NAMES it, on no list"      "$(has "$A_OUT" '  harness: tests/fp-names-the-guard.test.sh')"
assert "…and NOT one that names nothing (it derives, it does not run everything)" \
  "$(lacks "$A_OUT" '  harness: tests/fp-names-nothing.test.sh')"
assert "…and the selected harnesses actually ran green"       "$(has "$A_OUT" 'ok: all')"

echo "== --changed also sees an UNCOMMITTED edit — the local case CI never has =="
B="$TMP/b"; mkdir -p "$B"; build "$B"
edit "$B/work" plugin/scripts/commit-as.sh
B_OUT="$(run_changed "$B/work")"
assert "an uncommitted edit is a changed path"                "$(has "$B_OUT" '  changed: plugin/scripts/commit-as.sh')"
assert "…and selects the harness that names it"               "$(has "$B_OUT" '  harness: tests/fp-names-the-guard.test.sh')"

echo "== the EMPTY case: no changed paths runs the core, and says so =="
C="$TMP/c"; mkdir -p "$C"; build "$C"
C_OUT="$(run_changed "$C/work")"
assert "it says there were no changed paths"                  "$(has "$C_OUT" 'no changed paths against main')"
assert "…and runs the core anyway"                            "$(has "$C_OUT" '  harness: tests/commit-as-guard.test.sh')"
assert "…exactly the core, nothing derived"                   "$(lacks "$C_OUT" '  harness: tests/fp-names-the-guard.test.sh')"
assert "…and the harness count printed is the core count"     "$(has "$C_OUT" "ok: all $core_count harnesses passed")"

echo "== the UNMATCHED case: a path no harness names runs the core AND says so — never zero =="
D="$TMP/d"; mkdir -p "$D"; build "$D"
commit_on_branch "$D/work" plugin/agents/unread-by-any-harness.md
D_OUT="$(run_changed "$D/work")"
assert "it names the paths no harness covers"                 "$(has "$D_OUT" 'no harness names these changed paths')"
assert "…and names them, so the gap is actionable"            "$(has "$D_OUT" 'plugin/agents/unread-by-any-harness.md')"
assert "…and points at --all before the PR"                   "$(has "$D_OUT" '--all')"
assert "…and still ran the core, not zero harnesses"          "$(has "$D_OUT" "ok: all $core_count harnesses passed")"
assert "…so no run reports a pass having run nothing"         "$(lacks "$D_OUT" 'ok: all 0 harnesses')"

echo "== a changed HARNESS selects ITSELF — no naming rule can reach that =="
# The case that let a red harness sit on the default branch: nothing names a harness by
# path, so editing one used to run the core and not the file you were editing.
R="$TMP/r"; mkdir -p "$R"; build "$R"
( cd "$R/work" && git checkout -q -b feat && printf '# edited\n' >> tests/fp-names-nothing.test.sh \
  && git add -A && git commit -qm edit ) >/dev/null 2>&1
R_OUT="$(run_changed "$R/work")"
assert "the edited harness is in the selection"               "$(has "$R_OUT" '  harness: tests/fp-names-nothing.test.sh')"
assert "…and is not reported as covered by nothing"           "$(lacks "$R_OUT" 'no harness names these changed paths')"
assert "…and the run is still green"                          "$(has "$R_OUT" 'ok: all')"

echo "== --ci keeps the workflow's own verdict, which FAILS TOWARD THE FULL SUITE =="
E_OUT="$(run_ci "$A/work")"
assert "a plugin-only diff takes the fast path"               "$(has "$E_OUT" 'plugin-only diff — running')"
assert "…selecting tests/commit-as-guard.test.sh — the harness #124 left behind" \
  "$(has "$E_OUT" '  harness: tests/commit-as-guard.test.sh')"
assert "…and tests/companion-plugins.test.sh"                 "$(has "$E_OUT" '  harness: tests/companion-plugins.test.sh')"
assert "…and the derived one"                                 "$(has "$E_OUT" '  harness: tests/fp-names-the-guard.test.sh')"
assert "…and not the one that names nothing"                  "$(lacks "$E_OUT" '  harness: tests/fp-names-nothing.test.sh')"

F_OUT="$(run_ci "$D/work")"
assert "a plugin path NO harness names buys the FULL suite in CI, unlike --changed" \
  "$(has "$F_OUT" 'running the FULL suite')"
assert "…and that full suite includes the harness the fast path leaves out" \
  "$(has "$F_OUT" 'tests/fp-names-nothing.test.sh')"

G="$TMP/g"; mkdir -p "$G"; build "$G"
commit_on_branch "$G/work" README.md
G_OUT="$(run_ci "$G/work")"
assert "ONE path outside plugin/ and .claude-plugin/ and the fast path is off" \
  "$(lacks "$G_OUT" 'plugin-only diff')"
assert "…so every harness runs"                               "$(has "$G_OUT" 'tests/fp-names-nothing.test.sh')"

echo "== a changed HARNESS in the diff still buys the FULL suite in CI =="
# Admitting tests/*.test.sh to the fast path was tried (#324) and turned main red the same
# day: a harness that reads plugin/ wholesale names no file, so nothing selects it.
RC_OUT="$(run_ci "$R/work")"
assert "a diff of one edited harness does NOT take the fast path" "$(lacks "$RC_OUT" 'diff — running the core')"
assert "…so a harness nothing selected still runs"            "$(has "$RC_OUT" 'tests/fp-names-the-guard.test.sh')"

echo "== PROVING THE CORE IS READ: strike a name out of it and the same fixture stops running it =="
# Inside the fixture's tests/, because run.sh resolves the repo it verifies from its
# OWN location — a mutant left in $TMP would exercise $TMP, not the fixture.
MUT_CORE="$A/work/tests/run-no-guard.sh"
grep -vF 'tests/commit-as-guard.test.sh' "$RUNNER" > "$MUT_CORE"
assert "the removal mutant dropped exactly one line" \
  "$([ "$(( $(wc -l < "$RUNNER") - $(wc -l < "$MUT_CORE") ))" -eq 1 ] && echo 0 || echo 1)"
MUT_CORE_OUT="$(run_ci "$A/work" "$MUT_CORE")"
assert "…the mutant still fast-paths (the difference is the selection, not a crash)" \
  "$(has "$MUT_CORE_OUT" 'plugin-only diff — running')"
assert "…and no longer runs the guard's harness (removal bites)" \
  "$(lacks "$MUT_CORE_OUT" '  harness: tests/commit-as-guard.test.sh')"

echo "== a harness that dies before printing a summary is a FAILURE, never a pass =="
H="$TMP/h"; mkdir -p "$H"; build "$H"
printf '#!/usr/bin/env bash\nexit 7\n' > "$H/work/tests/silent-death.test.sh"
H_OUT="$( cd "$H/work" && bash tests/run.sh --all 2>&1 )"; H_RC=$?
assert "the runner fails"                                     "$([ "$H_RC" -ne 0 ] && echo 0 || echo 1)"
assert "…says so by name"                                     "$(has "$H_OUT" 'printed no recognised pass/fail summary')"
assert "…lists it under FAILED harnesses"                     "$(has "$H_OUT" 'FAILED harnesses:')"
assert "…and never prints the all-passed banner"              "$(lacks "$H_OUT" 'ok: all')"

# Non-vacuity, the only way it can be shown: every assertion above passes on the first
# run with nothing broken. Strip the guard's two body lines, leaving a bare `continue`
# — the naive shape where a harness that dies before printing is indistinguishable from
# one that never ran — and confirm THAT version reports a false all-clear.
MUT_SUM="$TMP/runner-no-summary-guard.sh"
grep -v 'printed no recognised pass/fail summary' "$RUNNER" \
  | grep -v 'no summary, exit \$rc' > "$MUT_SUM"
cp "$MUT_SUM" "$H/work/tests/run-mutant.sh"
MUT_SUM_OUT="$( cd "$H/work" && bash tests/run-mutant.sh --all 2>&1 )"; MUT_SUM_RC=$?
assert "the mutant that drops the guard falsely passes (proves the pin bites)" \
  "$([ "$MUT_SUM_RC" -eq 0 ] && echo 0 || echo 1)"
assert "…reporting the all-clear banner it should not"        "$(has "$MUT_SUM_OUT" 'ok: all')"
rm -f "$H/work/tests/run-mutant.sh" "$H/work/tests/silent-death.test.sh"

echo "== --all, the default, and the refusals =="
ALL_OUT="$( cd "$A/work" && bash tests/run.sh --all 2>&1 )"
assert "--all runs the harness no changed path names"         "$(has "$ALL_OUT" 'tests/fp-names-nothing.test.sh')"
BARE_OUT="$( cd "$A/work" && bash tests/run.sh 2>&1 )"
assert "…and no flag at all behaves as --all"                 "$(has "$BARE_OUT" 'tests/fp-names-nothing.test.sh')"

( cd "$A/work" && bash tests/run.sh --nonsense >/dev/null 2>&1 ); UNK_RC=$?
assert "an unknown flag is refused at exit 2"                 "$([ "$UNK_RC" -eq 2 ] && echo 0 || echo 1)"

V="$TMP/v"; mkdir -p "$V/tests" "$V/plugin"
cp "$RUNNER" "$V/tests/run.sh"
( cd "$V" && git init -q . && git config user.email t@example.com && git config user.name t \
  && git add -A && git commit -qm seed ) >/dev/null 2>&1
V_OUT="$( cd "$V" && bash tests/run.sh --all 2>&1 )"; V_RC=$?
assert "a tests/ with no harnesses is refused, not reported as a pass" \
  "$([ "$V_RC" -eq 2 ] && echo 0 || echo 1)"
assert "…and says why"                                        "$(has "$V_OUT" 'refusing to report a vacuous pass')"

echo "== the tiers: a '# deep' harness runs under --deep and NOWHERE else =="
# The merge gate must be unable to spend a paid `claude plugin eval` run
# (ai-bridge-v3/task-038). Both directions: the gate tiers skip the deep harness, and
# --deep runs it and nothing else — a filter that excluded it everywhere would pass half
# of this and leave the eval unrunnable.
P_OUT="$( cd "$A/work" && bash tests/run.sh --all --jobs 4 2>&1 )"
assert "--all does not run the deep harness"                  "$(lacks "$P_OUT" 'deep ran')"
assert "…and --changed does not either"                       "$(lacks "$(run_changed "$A/work")" 'deep ran')"
assert "…and --ci does not either"                            "$(lacks "$(run_ci "$A/work")" 'deep ran')"
DEEP_OUT="$( cd "$A/work" && bash tests/run.sh --deep 2>&1 )"
assert "--deep runs it"                                       "$(has "$DEEP_OUT" 'deep ran')"
assert "…telling the harness it is the deep tier"             "$(has "$DEEP_OUT" 'deep ran tier=deep')"
assert "…and runs nothing else"                               "$(lacks "$DEEP_OUT" 'harness: tests/fp-tier.test.sh')"

echo "== the tiers: an '# iced' harness runs under --iced, and elsewhere ONLY when a changed path names it =="
# A pause, not a retirement — so each direction is pinned: skipped where nothing touches
# its subject, run where something does, and run whenever the diff cannot be read.
assert "--all does not run the iced harness"                  "$(lacks "$P_OUT" 'iced ran')"
assert "…and SAYS it left one out, with the way to run it"    "$(has "$P_OUT" "1 '# iced' harness(es) not run")"
assert "…and --changed does not, for a diff that does not name its subject" "$(lacks "$(run_changed "$A/work")" 'iced ran')"
assert "…and --ci does not either"                            "$(lacks "$(run_ci "$A/work")" 'iced ran')"
assert "…not even on the FULL suite a README diff buys"       "$(lacks "$G_OUT" 'iced ran')"
ICED_OUT="$( cd "$A/work" && bash tests/run.sh --iced 2>&1 )"
assert "--iced runs it"                                       "$(has "$ICED_OUT" 'iced ran')"
assert "…and runs nothing else"                               "$(has "$ICED_OUT" 'ok: all 1 harnesses passed')"
assert "…in a gate tier: no paid CLI there either"            "$(lacks "$ICED_OUT" 'deep ran')"
I="$TMP/i"; mkdir -p "$I"; build "$I"
commit_on_branch "$I/work" plugin/agents/iced-subject.md
assert "a --ci diff that NAMES its subject thaws it"          "$(has "$(run_ci "$I/work")" 'iced ran')"
assert "…and so does --changed"                               "$(has "$(run_changed "$I/work")" 'iced ran')"
I2="$TMP/i2"; mkdir -p "$I2"; build "$I2"
( cd "$I2/work" && git checkout -q -b feat && printf '# edited\n' >> tests/fp-iced.test.sh \
  && printf 'x\n' >> README.md && git add -A && git commit -qm edit ) >/dev/null 2>&1
assert "a diff that edits the iced HARNESS thaws it, on the full suite too" "$(has "$(run_ci "$I2/work")" 'iced ran')"
NOBASE_OUT="$( cd "$A/work" && GITHUB_EVENT_NAME=pull_request GITHUB_BASE_REF=no-such-branch bash tests/run.sh --ci 2>&1 )"
assert "a pull request whose diff cannot be read runs it — fail toward running" "$(has "$NOBASE_OUT" 'iced ran')"
PUSH_OUT="$( cd "$A/work" && GITHUB_EVENT_NAME=push bash tests/run.sh --ci 2>&1 )"
assert "a push runs everything else and leaves it to the nightly" \
  "$([ "$(has "$PUSH_OUT" 'tests/fp-names-nothing.test.sh')" = 0 ] && [ "$(lacks "$PUSH_OUT" 'iced ran')" = 0 ] && echo 0 || echo 1)"

echo "== the time budget: reported on every run, judged on a FULL one, and never a failure =="
assert "a run reports its harness-seconds and its slowest"    "$(grep -qE '^== [0-9]+ harness-seconds; the slowest: ' <<<"$P_OUT" && echo 0 || echo 1)"
assert "…and a run inside the budget says nothing more"       "$(lacks "$P_OUT" 'over the budget')"
printf '#!/usr/bin/env bash\nsleep 2\necho "pass=1 fail=0"\n' > "$A/work/tests/fp-slow.test.sh"
OVER_OUT="$( cd "$A/work" && SUITE_BUDGET_S=1 HARNESS_WARN_S=1 bash tests/run.sh --all 2>&1 )"; OVER_RC=$?
assert "a FULL run over the budget is warned"                 "$(has "$OVER_OUT" 'over the budget of 1')"
assert "…and the one slow harness is named"                   "$(has "$OVER_OUT" 'tests/fp-slow.test.sh took')"
assert "…and the run still passes: a budget is not a gate"    "$([ "$OVER_RC" -eq 0 ] && [ "$(has "$OVER_OUT" 'ok: all')" = 0 ] && echo 0 || echo 1)"
SEL_OUT="$( cd "$A/work" && SUITE_BUDGET_S=0 bash tests/run.sh --changed --base main 2>&1 )"
assert "a SELECTION is never judged against the full-run budget" "$(lacks "$SEL_OUT" 'over the budget')"
SUMF="$TMP/step-summary.md"; : > "$SUMF"
( cd "$A/work" && GITHUB_STEP_SUMMARY="$SUMF" bash tests/run.sh --all >/dev/null 2>&1 )
assert "under CI the slowest harnesses land in the step summary" "$(grep -qF '| `tests/fp-slow.test.sh` |' "$SUMF" && echo 0 || echo 1)"
rm -f "$A/work/tests/fp-slow.test.sh"

echo "== the gate tiers cannot spawn the claude CLI even if a harness tries =="
assert "a harness in a gate tier is told so"                  "$(has "$P_OUT" 'tier=gate')"
assert "…and 'claude' on its PATH resolves to the runner's refusing shim, not the real CLI" \
  "$(grep -qE 'tier=gate claude=.*run-shim[^ ]*/claude' <<<"$P_OUT" && echo 0 || echo 1)"

echo "== …except `plugin test` and `plugin validate`, which reach the REAL binary and spend nothing =="
# Both directions, because each half alone passes a wrong shim: a shim that lets everything
# through spends money in the gate, and one that lets nothing through leaves the mod
# harness unable to run `claude plugin test` anywhere but --deep. The "real" CLI is a
# fixture earlier on PATH that prints its arguments, so what reached it is read, not inferred.
FAKE="$TMP/fake-real-bin"; mkdir -p "$FAKE"
printf '#!/bin/sh\necho "fake-real got: $*"\n' > "$FAKE/claude"; chmod +x "$FAKE/claude"
cat > "$A/work/tests/fp-cli.test.sh" <<'FIX'
#!/usr/bin/env bash
claude plugin test ./x; echo "test rc=$?"
claude plugin validate ./x --strict; echo "validate rc=$?"
claude -p hi; echo "p rc=$?"
claude plugin eval ./x; echo "eval rc=$?"
claude plugin install x@y; echo "install rc=$?"
echo "real=[${AB_CLAUDE_REAL-unset}]"
echo "pass=1 fail=0"
FIX
CLI_OUT="$( cd "$A/work" && PATH="$FAKE:$PATH" bash tests/run.sh --all 2>&1 )"
assert "claude plugin test reaches the real binary with its arguments" "$(has "$CLI_OUT" 'fake-real got: plugin test ./x')"
assert "…and so does claude plugin validate"                           "$(has "$CLI_OUT" 'fake-real got: plugin validate ./x --strict')"
assert "…while claude -p is still refused at exit 99"                  "$(has "$CLI_OUT" 'p rc=99')"
assert "…and never reaches the real binary"                            "$(lacks "$CLI_OUT" 'fake-real got: -p')"
assert "…and claude plugin eval is refused too (it spends)"            "$(has "$CLI_OUT" 'eval rc=99')"
assert "…and claude plugin install is refused too"                     "$(has "$CLI_OUT" 'install rc=99')"
assert "…AB_CLAUDE_REAL names the real binary the shim fronts"         "$(has "$CLI_OUT" "real=[$FAKE/claude]")"
# The machine with NO claude at all — CI's runners. The two shapes are told so at a code of
# their own, and AB_CLAUDE_REAL is set and empty, which is what a harness reads to SKIP.
NOCLI_OUT="$( cd "$A/work" && PATH="/usr/bin:/bin:/usr/sbin:/sbin" bash tests/run.sh --all 2>&1 )"
assert "with no real CLI, plugin test gets exit 98, not a silent pass" "$(has "$NOCLI_OUT" 'test rc=98')"
assert "…and plugin validate the same"                                 "$(has "$NOCLI_OUT" 'validate rc=98')"
assert "…and AB_CLAUDE_REAL is set and empty"                          "$(has "$NOCLI_OUT" 'real=[]')"
assert "…while -p is still 99"                                         "$(has "$NOCLI_OUT" 'p rc=99')"
rm -f "$A/work/tests/fp-cli.test.sh"

echo "== the pool: bounded, '# serial' honoured, output replayed in FILE order =="
assert "the run says how it was split"                        "$(has "$P_OUT" 'serial,')"
assert "…with the serial harness counted as serial"           "$(has "$P_OUT" '1 serial,')"
assert "…and a pool of the size asked for"                    "$(has "$P_OUT" 'in a pool of 4')"
assert "…and every harness still ran green"                   "$(has "$P_OUT" 'ok: all')"
# Both header forms: the fixture run inherits GITHUB_ACTIONS from a CI job, and there the
# runner emits `::group::<file>` instead of `== <file>`. Matching only one reads as a
# failure of the ORDER on every CI run — measured on run 34782353871.
ORD="$(grep -oE '^(== |::group::)tests/[A-Za-z0-9_.-]*\.test\.sh' <<<"$P_OUT" | sed -E 's/^(== |::group::)//')"
assert "…and the per-harness output is replayed in file order, never completion order" \
  "$([ -n "$ORD" ] && [ "$ORD" == "$(printf '%s\n' "$ORD" | sort)" ] && echo 0 || echo 1)"
assert "…and the tally is still exact (one pass per fixture harness)" \
  "$(grep -qE '^== [0-9]+ harness\(es\) in [0-9]+s — pass=[0-9]+ fail=0 ==$' <<<"$P_OUT" && echo 0 || echo 1)"
( cd "$A/work" && bash tests/run.sh --all --jobs 0 >/dev/null 2>&1 ); J_RC=$?
assert "--jobs 0 is refused at exit 2"                        "$([ "$J_RC" -eq 2 ] && echo 0 || echo 1)"

echo "== the checkout is re-verified after EVERY harness, not once at the start =="
W="$TMP/w"; mkdir -p "$W"; build "$W"
cat > "$W/work/tests/aaa-destroys-checkout.test.sh" <<'FIX'
#!/usr/bin/env bash
rm -rf "$(cd "$(dirname "$0")/.." && pwd)/plugin"
echo "pass=53 fail=0"
FIX
W_OUT="$( cd "$W/work" && bash tests/run.sh --all 2>&1 )"; W_RC=$?
assert "a harness that destroys the checkout fails the run despite printing fail=0" \
  "$([ "$W_RC" -eq 2 ] && echo 0 || echo 1)"
assert "…naming the harness that did it"                      "$(has "$W_OUT" 'the checkout was destroyed while running')"
assert "…and never reaching the all-passed banner"            "$(lacks "$W_OUT" 'ok: all')"

summary
