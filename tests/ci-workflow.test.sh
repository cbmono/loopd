#!/usr/bin/env bash
#
# ci-workflow.test.sh — the workflow that runs `tests/*.test.sh` in CI must actually
# exist, be valid YAML, and invoke the FULL suite on the events this task exists to
# cover. ai-bridge-v4/task-001's whole reason to exist is that a moved head, or a
# harness that quietly regresses, has no signal until a human happens to look — so the
# guard against THAT gap must not itself be a thing only a human happens to notice was
# deleted. Both directions are asserted, not just "present and correct": the existence
# check is proven to actually go red on an absent file, not merely green on today's.
#
# WHAT THIS DOES NOT DO. It does not re-run the suite (that is what the workflow itself
# is for), it does not require any particular CI provider beyond "a file GitHub Actions
# reads", and since ai-bridge-v3/task-028 it no longer tests the RUNNER: the selection
# and the loop live in tests/run.sh and are exercised by tests/test-runner.test.sh.
# What is left here is the workflow's own shape, plus the one thing only this file can
# see — that the workflow delegates and carries no second copy.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)" || { echo "ci-workflow.test: cannot locate self" >&2; exit 2; }
REPO="$(cd "$HERE/.." && pwd)" || { echo "ci-workflow.test: cannot locate repo root" >&2; exit 2; }
WF="$REPO/.github/workflows/tests.yml"
DECLARED="$REPO/.github/required-checks.txt"

# Single source of truth for both sides — same idiom as harness-shell-dialect.test.sh's
# SHEBANG/SCOPE_GLOB constants: the job's declared name is verified against the
# workflow's ACTUAL content below, not merely assumed to still say this.
CHECK_NAME="harness suite"

pass=0; fail=0; skip=0
assert()  { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
            else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
skipped() { printf '  SKIP  %s\n' "$1"; skip=$((skip+1)); }
summary() { echo; echo "pass=$pass fail=$fail skip=$skip"; [[ "$fail" == 0 ]] || exit 1; exit 0; }

echo "== the existence check actually discriminates, not just today's state =="
# Proves the assertion below is not vacuously true — a guard whose own regression test
# never sees it fail proves nothing (the class of bug this whole task exists to close).
# path-scan: absent — deliberately non-existent, to prove the check below discriminates
MISSING_WF="$REPO/.github/workflows/does-not-exist-$$.yml"
assert "a present file passes the existence check" \
  "$([ -f "$WF" ] && echo 0 || echo 1)"
assert "…and a missing one FAILS the identical check (the guard is not vacuous)" \
  "$([ -f "$MISSING_WF" ] && echo 1 || echo 0)"

echo "== .github/workflows/tests.yml exists and is non-empty =="
assert "$WF exists" "$([ -f "$WF" ] && echo 0 || echo 1)"
if [[ ! -f "$WF" ]]; then
  echo "ci-workflow.test: $WF is missing — cannot check its contents, stopping here" >&2
  summary
fi
assert "$WF is non-empty" "$([ -s "$WF" ] && echo 0 || echo 1)"

WF_TEXT="$(cat "$WF")"

echo "== it is valid YAML, checked against a real parser or actionlint, never a text guess =="
# PyYAML needs no second interpreter, Psych ships with the Ruby macOS and Linux CI images
# both carry. Import order, not conformance: this file asks only "does it parse", and the
# workflow carries no construct the two disagree about — deliverable-paths-vs-yaml.test.sh
# does compare their readings, and chooses between them for that reason. Where a
# repo has actionlint on PATH that is stronger still (schema-aware, not just "parses"),
# so it is preferred when present. Absent all three: SKIP, never a false FAIL — a
# missing optional tool is not a defect in the workflow.
if command -v actionlint >/dev/null 2>&1; then
  AL_OUT="$(actionlint "$WF" 2>&1)"
  AL_RC=$?
  assert "actionlint reports zero problems on $WF" "$([ "$AL_RC" -eq 0 ] && echo 0 || echo 1)"
  [[ "$AL_RC" -eq 0 ]] || printf '%s\n' "$AL_OUT" >&2
elif python3 -c 'import yaml' >/dev/null 2>&1; then
  assert "PyYAML parses $WF without error" \
    "$(python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$WF" >/dev/null 2>&1 && echo 0 || echo 1)"
elif command -v ruby >/dev/null 2>&1 && ruby -rpsych -e 'Psych::VERSION' >/dev/null 2>&1; then
  assert "Psych parses $WF without error" \
    "$(ruby -rpsych -e "Psych.load_file(ARGV[0])" "$WF" >/dev/null 2>&1 && echo 0 || echo 1)"
else
  skipped "no actionlint, PyYAML or Ruby/Psych on this machine — nothing to parse with"
fi

echo "== it triggers on pull_request and push against the default branch =="
assert "declares a pull_request trigger" \
  "$(grep -Eq '^[[:space:]]*pull_request:' <<<"$WF_TEXT" && echo 0 || echo 1)"
assert "declares a push trigger" \
  "$(grep -Eq '^[[:space:]]*push:' <<<"$WF_TEXT" && echo 0 || echo 1)"
assert "both triggers scope to the default branch (main)" \
  "$([ "$(grep -cE '^[[:space:]]*branches:[[:space:]]*\[main\]' <<<"$WF_TEXT")" -ge 2 ] && echo 0 || echo 1)"

echo "== it invokes tests/run.sh, and carries NO SECOND COPY of the selection =="
# ai-bridge-v3/task-028. The selection and the runner live in tests/run.sh so that a
# contributor can run what CI runs; the whole point is lost the moment this file grows
# its own copy, and a drifted copy is invisible until a required check goes green
# having run the wrong set. The BEHAVIOUR of that runner is tests/test-runner.test.sh —
# this section only pins that the workflow delegates to it and reimplements none of it.
#
# Read off the file with its COMMENT lines stripped: the header comment names the
# selection in prose on purpose, and prose is not a second implementation.
wf_code() { grep -v '^[[:space:]]*#' <<<"$WF_TEXT"; }

assert "a run step invokes tests/run.sh --ci" \
  "$(grep -qF 'tests/run.sh --ci' <<<"$(wf_code)" && echo 0 || echo 1)"

# Each marker is a load-bearing line of the runner — the derivation, the summary parse,
# the integrity re-check, the harness loop, the core list. Any of them here is a copy.
COPY_MARKERS=(
  'grep -lF -e "$suffix" tests/*.test.sh'
  "grep -oE 'pass=[0-9]+ fail=[0-9]+'"
  'verify_checkout'
  'for f in "${files[@]}"'
  'tests/plugin-manifest.test.sh'
)
inline_copy() { # <text> — echoes the markers it found
  local text="$1" m
  for m in "${COPY_MARKERS[@]}"; do
    grep -qF -e "$m" <<<"$text" && printf '%s\n' "$m"
  done
  return 0
}
found="$(inline_copy "$(wf_code)")"
assert "…and reimplements none of the selection or the runner${found:+ (found: $(tr '\n' ' ' <<<"$found"))}" \
  "$([ -z "$found" ] && echo 0 || echo 1)"
# Non-vacuity: the identical check must FAIL on a workflow that does carry a copy.
assert "…and that check really discriminates (a workflow with an inline copy fails it)" \
  "$([ -n "$(inline_copy "$(printf '%s\n' "$WF_TEXT" 'run: verify_checkout')")" ] && echo 0 || echo 1)"

echo "== ai-bridge-v4/task-022: the host-rendering oracle's --check runs automatically =="
# Before this task it could only be run by hand, which meant it would not be run. Pinned
# on the literal invocation, same idiom as the tests/*.test.sh glob above, and on it being
# NON-blocking — a required check must not fail on a renderer wording change this repo
# does not control (docs/conventions.md, "the host wins and it is recorded").
assert "a step invokes tests/fixtures/reviewer/record-host-rendering.sh --check" \
  "$(grep -qF 'tests/fixtures/reviewer/record-host-rendering.sh --check' <<<"$WF_TEXT" && echo 0 || echo 1)"
assert "…and that step is continue-on-error, so host drift never fails the required check" \
  "$(grep -qF 'continue-on-error: true' <<<"$(grep -B8 -F 'record-host-rendering.sh --check' <<<"$WF_TEXT")" && echo 0 || echo 1)"

echo "== the gate runs on Linux, and macOS coverage survives as the nightly job =="
# 2026-10-09: the required check moved to ubuntu-latest (2.5x faster, and the platform
# where two shipped bugs were visible — #367; the account is on the job's `runs-on`).
# Both halves are pinned, because each one can be lost silently: a `runs-on` edited back
# to macos-latest doubles the gate's wall time with no test going red, and a `macos` job
# dropped from tests-deep.yml takes bash 3.2 and the BSD tools out from under test with
# no test going red either — operators run exactly that half. Read off the code lines,
# comments stripped, since the history comment on the job names both platforms.
assert "the \"$CHECK_NAME\" job runs on ubuntu-latest" \
  "$(grep -qE '^[[:space:]]+runs-on:[[:space:]]*ubuntu-latest[[:space:]]*$' <<<"$(wf_code)" && echo 0 || echo 1)"
assert "…and on nothing else: the gate names no macos runner" \
  "$(grep -qE '^[[:space:]]+runs-on:[[:space:]]*macos' <<<"$(wf_code)" && echo 1 || echo 0)"

DEEP_WF="$REPO/.github/workflows/tests-deep.yml"
assert "$DEEP_WF exists" "$([ -f "$DEEP_WF" ] && echo 0 || echo 1)"
if [[ -f "$DEEP_WF" ]]; then
  DEEP_CODE="$(grep -v '^[[:space:]]*#' "$DEEP_WF")"
  # The job is identified by what it DOES — a macos-latest job whose run step is the gate
  # tier (`--all`: deep excluded structurally, iced skipped unless named, the shim in
  # front) — not by its display name, which is free to change. The runner line and the
  # invocation must sit inside the same job: the `deep` and `iced` jobs are macos-latest
  # too, and neither runs the gate tier, so "both strings somewhere in the file" would
  # pass a file that dropped the job.
  macos_suite_job() { # <code> — 0 when some job carries BOTH the runner and the suite call
    awk '
      /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { if (r && s) found=1; r=0; s=0 }
      /^[[:space:]]+runs-on:[[:space:]]*macos-latest[[:space:]]*$/ { r=1 }
      /tests\/run\.sh --all([[:space:]]|$)/ { s=1 }
      END { if (r && s) found=1; exit(found ? 0 : 1) }' <<<"$1"
  }
  assert "a macos-latest job in tests-deep.yml runs the gate tier (tests/run.sh --all)" \
    "$(macos_suite_job "$DEEP_CODE" && echo 0 || echo 1)"
  # Non-vacuity, both ways: the identical check fails when the runner and the call are in
  # DIFFERENT jobs, and when the macos job is absent altogether.
  SPLIT=$'jobs:\n  a:\n    runs-on: macos-latest\n    steps:\n      - run: true\n  b:\n    runs-on: ubuntu-latest\n    steps:\n      - run: tests/run.sh --all\n'
  assert "…and that check discriminates: runner and call in different jobs FAIL it" \
    "$(macos_suite_job "$SPLIT" && echo 1 || echo 0)"
  assert "…and a tests-deep.yml without the job FAILS it" \
    "$(macos_suite_job "$(grep -v 'macos-latest' <<<"$DEEP_CODE")" && echo 1 || echo 0)"
  assert "…and that job never runs the deep tier (no model call rides on the nightly macOS suite)" \
    "$(awk '
      /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { if (r && s && d) bad=1; r=0; s=0; d=0 }
      /^[[:space:]]+runs-on:[[:space:]]*macos-latest[[:space:]]*$/ { r=1 }
      /tests\/run\.sh --all([[:space:]]|$)/ { s=1 }
      /tests\/run\.sh --deep([[:space:]]|$)/ { d=1 }
      END { if (r && s && d) bad=1; exit(bad ? 1 : 0) }' <<<"$DEEP_CODE" && echo 0 || echo 1)"
fi

echo "== the check name is declared as a required check, verbatim, on both sides =="
# CHECK_NAME above is the pin; both the workflow and the declared-checks file are
# verified against it, so a rename on either side that forgets the other goes red here
# instead of silently making the required check unresolvable.
assert "the workflow's job is named exactly \"$CHECK_NAME\" (anchored, not a substring)" \
  "$(grep -qE "^[[:space:]]+name: $CHECK_NAME\$" <<<"$WF_TEXT" && echo 0 || echo 1)"
assert "$DECLARED exists" "$([ -f "$DECLARED" ] && echo 0 || echo 1)"
if [[ -f "$DECLARED" ]]; then
  DECLARED_NAMES="$(grep -v '^#' "$DECLARED" | grep -v '^$')"
  assert "$DECLARED lists that exact check name" \
    "$(grep -Fxq "$CHECK_NAME" <<<"$DECLARED_NAMES" && echo 0 || echo 1)"
fi

summary
