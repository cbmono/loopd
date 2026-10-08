#!/usr/bin/env bash
#
# run.sh — the ONE implementation of this repo's harness selection. CI calls it too.
#   --changed [--base <ref>]  the core harnesses plus every harness naming a changed path
#   --all                     every tests/*.test.sh (the default)
#   --ci                      the workflow entry: the fast path on a plugin-only PR diff,
#                             the full suite on anything else
#   --deep                    ONLY the harnesses marked `# deep` — they spawn the claude
#                             CLI and cost money; no other mode runs them or reaches it
#   --iced                    ONLY the harnesses marked `# iced` — a subject on hold; every
#                             other mode runs one only when a changed path names it
#   --jobs N                  harnesses in parallel (default: CPUs); `# serial` runs alone
# Each harness is bounded by HARNESS_TIMEOUT seconds (600, 1800 under --deep): one that
# never returns is killed and fails as ITSELF, and the rest of the suite still reports.
# A full run also reports its harness-seconds against SUITE_BUDGET_S (2000) — a warning,
# never a failure: the runner's own speed varies by a third between two runs of one tree.
# The gate runs on ubuntu-latest (since 2026-10-09) and nightly on macos-latest; the
# numbers here are the Linux ones, and the pool behaves the same on both.
# Exit: 0 all green · 1 a harness failed · 2 refused (no harnesses, or a dead checkout).
# Why, the core list and the measured numbers: .claude/rules/tests.md.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)" || { echo "run.sh: cannot locate self" >&2; exit 2; }
SELF="$HERE/${0##*/}"
workspace="$(cd "$HERE/.." && pwd)" || { echo "run.sh: cannot locate repo root" >&2; exit 2; }
cd "$workspace" || exit 2

# The eleven variables git exports into every hook and into `git rebase -x`. A harness
# inheriting them commits its own fixture into the repo under test — the incident the
# scripts-executable harness carries a refusal for. Cleared once, here, for all of them.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE \
      GIT_CONFIG GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT

# Harnesses no changed path can be expected to name, because they read plugin/ wholesale
# or reach their subject indirectly. .claude/rules/tests.md, "The core", says why each.
CORE=(
  tests/plugin-manifest.test.sh
  tests/plugin-skills.test.sh
  tests/plugin-agents.test.sh
  tests/agent-body-links.test.sh
  tests/deny-baseline.test.sh
  tests/agent-control.test.sh
  tests/commit-as-guard.test.sh
  tests/companion-plugins.test.sh
  tests/harness-read-paths.test.sh
)

# The per-harness wall-clock bound, in seconds, named once for the whole suite. The slowest
# gating harness on macOS is review-clearance: 311s in a pool of 3 on run 34783957083, and
# 455s standalone after #226 grew it — though that figure shared a machine with a sibling
# suite, so treat it as an upper bound. On the Linux gate (4 CPUs, run 37817944377) the
# slowest were session-banner 50s, welcome-command 48s and review-clearance-gates 45s, so
# 600 is now a large margin there — but the same tree still runs nightly on macos-latest,
# where welcome-command measured 184s (run 37748780764), and ONE bound serves both.
# Re-measure on macOS before trimming 600. A `# deep` harness spawns a paid CLI call and
# measures ~10m.
HARNESS_TIMEOUT="${HARNESS_TIMEOUT:-600}"
HARNESS_TIMEOUT_DEEP="${HARNESS_TIMEOUT_DEEP:-1800}"

# The budget for a FULL run, in harness-seconds (the sum of every harness's own wall time;
# divide by the pool size for minutes). The suite had none, and grew from 3,178 to 4,108
# harness-seconds in one day (2026-10-04 to -05) until a green run was cancelled at the
# job limit. It WARNS and never fails: two runs of the same tree measured 3,015 and 4,108
# on the 3-CPU macOS runner, so a failing bound would be a coin.
#
# RE-CUT 2026-10-09 for the Linux gate (was 3600 — 20 minutes on the 3-CPU macOS runner,
# which now runs the suite nightly and is not what this number is for). Measured there:
# 1,285 harness-seconds for the full tree (run 37817944377, 4 CPUs) and 935 one run
# earlier (run 37814543343, the tree before #367, nine harnesses failing) — 37% apart,
# the same variance macOS showed, so the bound stays a warning. 2000 is ~1.55x the measured
# full run: room for the next dozen harnesses at today's average (~8.5s), and a warning
# well before the job's 20-minute ceiling (2000 harness-seconds in a pool of 4 is about
# 8.5 minutes of pool). A nightly macOS run of the same tree is about 2,500 and is NOT
# judged against this: it runs under --all too, so expect the warning there and read it
# as "macOS is twice as slow", which is known, not as a regression.
# One harness over HARNESS_WARN_S is named too — half the kill bound, while there is room.
SUITE_BUDGET_S="${SUITE_BUDGET_S:-2000}"
HARNESS_WARN_S="${HARNESS_WARN_S:-300}"

usage() { sed -n '3,20p' "$0" | sed 's/^#\{1,\} \{0,1\}//'; }

mode=all
base=""
jobs=""
one=""
while [ $# -gt 0 ]; do
  case "$1" in
    --all)     mode=all ;;
    --changed) mode=changed ;;
    --ci)      mode=ci ;;
    --deep)    mode=deep ;;
    --iced)    mode=iced ;;
    --jobs)    shift; jobs="${1:-}" ;;
    --run-one) shift; one="${1:-}"; mode=run-one ;;   # internal: one harness, for the pool
    --base)    shift; base="${1:-}" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "run.sh: unknown option $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

[ "$mode" != deep ] || HARNESS_TIMEOUT="$HARNESS_TIMEOUT_DEEP"
export HARNESS_TIMEOUT   # the pool re-enters this script as --run-one, which reads it here

group()    { if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::group::$1"; else echo "== $1"; fi; }
endgroup() { if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::endgroup::"; fi; return 0; }
fatal()    { if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::error::$1"; else echo "run.sh: $1" >&2; fi; }
warn()     { if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::warning::$1"; else echo "run.sh: warning: $1"; fi; }

# A harness with a broken TMPDIR guard can rm -rf its OWN checkout while still printing a
# clean pass=N fail=0 and exiting 0 — knowledge/findings/suite-cleanup-can-delete-its-own-
# checkout.md in the control panel. `-e` on .git, not `-d`: it is a FILE in a worktree.
verify_checkout() {
  git -C "$workspace" rev-parse --verify -q HEAD >/dev/null 2>&1 \
    && [ -e "$workspace/.git" ] \
    && [ -d "$workspace/tests" ] \
    && [ -d "$workspace/plugin" ]
}

# A harness declares its tier in its own header, on a line of its own in the first 20:
# `# serial` (never run beside another harness), `# deep` (spawns the claude CLI) or
# `# iced` (its subject is on hold — see the tier filter below).
declares() { head -20 "$2" 2>/dev/null | grep -qE "^# $1( |$)"; }

# bounded <harness> — the harness under a HARNESS_TIMEOUT-second wall clock, exiting 142
# when it trips. The bound has to kill the process GROUP, not the harness: a harness
# blocked in a child leaves that child holding the capture's pipe, so `out="$( )"` below
# goes on blocking past the bound (measured: 60s under a 3s bound). `perl`, not
# `timeout(1)`: macos-latest ships the first and not the second, and although the Linux
# gate has had `timeout` since 2026-10-09 the suite still runs nightly on macOS, so one
# implementation keeps the pool's kill behaviour identical on both — a bound that fires
# through two different tools is two behaviours to measure. The exit status is re-encoded
# because a bare `$?>>8` turns every signal death into 0.
bounded() {
  command -v perl >/dev/null 2>&1 || { bash "$1"; return; }
  perl -e '$t=shift; $p=fork; exit 127 unless defined $p; if(!$p){setpgrp(0,0); exec @ARGV; exit 127} $SIG{ALRM}=sub{kill "KILL",-$p; waitpid $p,0; exit 142}; alarm $t; waitpid $p,0; $s=$?; exit(($s & 127) ? 128+($s & 127) : ($s>>8))' \
    "$HARNESS_TIMEOUT" bash "$1"
}

# run_one <harness> — writes <basename>.out and "<rc> <secs> <state>" into
# $RUN_OUT_DIR/<basename>.meta, and always exits 0: the meta file is the verdict, never
# this process. State is the checkout probe, and it has THREE values on purpose —
# `broken` means this harness saw an intact checkout and left a dead one (the suspect),
# `notrun` means the checkout was already dead so nothing was run. Under the pool that
# distinction is the only thing that still attributes the damage to one harness.
run_one() {
  local f="$1" b out rc s state
  b="${f##*/}"
  if ! verify_checkout; then
    echo "not run — the checkout was already destroyed" > "$RUN_OUT_DIR/$b.out"
    echo "0 0 notrun" > "$RUN_OUT_DIR/$b.meta"
    return 0
  fi
  s=$(date +%s)
  if out="$(bounded "$f" 2>&1)"; then rc=0; else rc=$?; fi
  [ "$rc" -ne 142 ] || out="$out"$'\n'"run.sh: KILLED at the ${HARNESS_TIMEOUT}s per-harness bound — $f never returned"
  printf '%s\n' "$out" > "$RUN_OUT_DIR/$b.out"
  if verify_checkout; then state=intact; else state=broken; fi
  s=$(( $(date +%s) - s ))
  printf '%s %s %s\n' "$rc" "$s" "$state" > "$RUN_OUT_DIR/$b.meta"
  [ -n "${GITHUB_ACTIONS:-}" ] || echo "   ran $f (${s}s)" >&2
}

if [ "$mode" = run-one ]; then
  [ -n "${RUN_OUT_DIR:-}" ] && [ -n "$one" ] || { fatal "--run-one is internal: it needs RUN_OUT_DIR and a harness"; exit 2; }
  run_one "$one"
  exit 0
fi

cpus() {
  local n=""
  command -v sysctl >/dev/null 2>&1 && n="$(sysctl -n hw.ncpu 2>/dev/null)"
  [ -n "$n" ] || { command -v nproc >/dev/null 2>&1 && n="$(nproc 2>/dev/null)"; }
  case "$n" in ''|*[!0-9]*) n=4 ;; esac
  echo "$n"
}

default_base() {
  git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main
}

# select_derived <newline-separated paths> — sets SELECTED and UNNAMED. Not a function
# that prints, because a $( ) subshell would lose UNNAMED, which is half the answer.
# A harness is selected because it NAMES a changed path, or a >=2-component suffix of one
# (so "$REPO/scripts/foo.sh" style references still match; never a bare basename, which
# would match half the suite) — never because somebody remembered to add a line. A changed
# harness also selects ITSELF, which no naming rule can reach.
select_derived() {
  local changed="$1" p suffix m hits derived=""
  UNNAMED=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    hits=""; suffix="$p"
    while : ; do
      m="$(grep -lF -e "$suffix" tests/*.test.sh 2>/dev/null || true)"
      [ -z "$m" ] || hits="${hits}${m}"$'\n'
      case "$suffix" in
        */*/*) suffix="${suffix#*/}" ;;
        *)     break ;;
      esac
    done
    # A harness is a read path of its own, and nothing in this suite names one BY PATH —
    # so without this, editing a harness selected the core and the one file you changed
    # was the one thing that did not run. (No harness NAME in this comment: the runner
    # test derives CORE by grepping this file for one.)
    case "$p" in tests/*.test.sh) [ ! -f "$p" ] || hits="${hits}$p"$'\n' ;; esac
    if [ -z "$hits" ]; then
      UNNAMED="${UNNAMED:+$UNNAMED }$p"
    else
      derived="${derived}${hits}"
    fi
  done <<<"$changed"
  SELECTED="$(printf '%s\n' "${CORE[@]}" "$derived" | grep -v '^[[:space:]]*$' | sort -u)"
}

files_from_selection() {
  narrowed=1
  files=()
  while IFS= read -r h; do
    [ -n "$h" ] && files+=("$h")
  done <<<"$SELECTED"
}

announce() { # <lead> <changed paths>
  echo "$1"
  [ -z "$2" ] || printf '%s\n' "$2" | sed 's/^/  changed: /'
  [ "${#files[@]}" -eq 0 ] || printf '%s\n' "${files[@]}" | sed 's/^/  harness: /'
}

shopt -s nullglob
files=(tests/*.test.sh)
shopt -u nullglob
narrowed=0    # 1 once a selection replaced the full list: the budget judges full runs only
thaw=""       # the harnesses a changed path names — an `# iced` one among them still runs
thaw_all=0    # 1 when the diff could not be read: fail toward running them

# `.git` is a FILE in a linked worktree. init-bundle.sh --config refuses to run from one
# by design, so four harnesses fail there for reasons unrelated to the code under test.
[ -f "$workspace/.git" ] && echo "run.sh: this is a git WORKTREE — derived-indexes, link-repos, snapshot and board-renderers fail here by design (.claude/rules/tests.md). Verify from the main checkout or a fresh clone." >&2

case "$mode" in
  all|deep|iced) ;;

  changed)
    [ -n "$base" ] || base="$(default_base)"
    # Committed, uncommitted and untracked alike: locally the change you want covered is
    # usually not committed yet, which is the whole difference from the CI diff below.
    changed="$( { git diff --name-only "$base...HEAD" 2>/dev/null
                  git diff --name-only HEAD 2>/dev/null
                  git ls-files --others --exclude-standard 2>/dev/null; } | sort -u )"
    if [ -z "$changed" ]; then
      SELECTED="$(printf '%s\n' "${CORE[@]}" | sort -u)"; UNNAMED=""
      files_from_selection
      announce "no changed paths against $base — running the ${#CORE[@]} core harnesses:" ""
    else
      select_derived "$changed"
      files_from_selection
      thaw="$SELECTED"
      announce "changed-path selection — the ${#CORE[@]} core harnesses plus every harness that names a changed path:" "$changed"
      [ -z "$UNNAMED" ] || echo "no harness names these changed paths, so they selected nothing beyond the core — verify with --all before the PR: $UNNAMED"
    fi
    ;;

  ci)
    # PRs only; a push to main always runs everything. The verdict FAILS TOWARD THE FULL
    # SUITE at every step — empty diff, failed fetch, any path outside plugin/ and
    # .claude-plugin/, or a changed path NO harness names. That last one differs from
    # --changed on purpose: this is the merge gate, and there is no --all run after it.
    #
    # DO NOT WIDEN THIS TO ADMIT tests/*.test.sh. It was tried (#324, 2026-10-05) on the
    # measurement that 0 of 40 merged PRs were plugin-ONLY, so the fast path never fired.
    # Within hours a PR adding a script and its own harness took the widened path, passed
    # 39 harnesses in three minutes, and turned main red: the harness requiring a README
    # row for every script reads plugin/scripts/ WHOLESALE and names no file, so nothing
    # selected it. About 40 harnesses enumerate the plugin tree that way and no pattern
    # lists them reliably — the one that failed was not caught by the search for them.
    # Derivation is sound for a path somebody NAMES; it is blind to a harness that asks
    # "is every file here …?". Frequency was measured; soundness was not.
    if [ "${GITHUB_EVENT_NAME:-}" = "pull_request" ]; then thaw_all=1; fi
    if [ "${GITHUB_EVENT_NAME:-}" = "pull_request" ] && [ -n "${GITHUB_BASE_REF:-}" ] \
       && git fetch --quiet origin "$GITHUB_BASE_REF"; then
      changed="$(git diff --name-only "origin/$GITHUB_BASE_REF...HEAD")"
      if [ -n "$changed" ]; then select_derived "$changed"; thaw="$SELECTED"; thaw_all=0; fi
      if [ -n "$changed" ] && ! printf '%s\n' "$changed" | grep -qvE '^(plugin/|\.claude-plugin/)'; then
        if [ -n "$UNNAMED" ]; then
          echo "plugin-only diff, but no harness names these paths — running the FULL suite: $UNNAMED"
        else
          files_from_selection
          announce "plugin-only diff — running the core plugin harnesses plus every harness that names a changed path:" "$changed"
        fi
      fi
    fi
    ;;
esac

if [ "${#files[@]}" -eq 0 ]; then
  fatal "no tests/*.test.sh files found — refusing to report a vacuous pass"
  exit 2
fi

# The tiers are disjoint: `# deep` runs under --deep and nowhere else, everything else
# runs everywhere else. Selection can pick a deep harness by derivation, so the filter
# is here rather than in the selector.
#
# `# iced` is the third tier, and it is a PAUSE, not a retirement: the subject still ships
# and its harness still exists, but nobody is changing it, so every PR was paying for a
# verdict that could not move (the board's twelve: 241 of 3,015 harness-seconds on run
# 37310865693, 2026-10-05). An iced harness runs under --iced and in the nightly workflow,
# and in a gate tier ONLY when a changed path names it or is it — the one case where its
# verdict can move, and derivation is sound for exactly that case. What it cannot see is
# an iced harness that reads a directory wholesale; the nightly run is what catches that,
# a day late, and that delay is the price accepted here. A pull request whose diff cannot
# be read runs them all. THAWING a subject is deleting the marker line, nothing else.
serial=(); par=(); kept=(); iced_skipped=0
for f in "${files[@]}"; do
  if declares deep "$f"; then
    [ "$mode" = deep ] || continue
  elif [ "$mode" = deep ]; then
    continue
  elif declares iced "$f"; then
    if [ "$mode" != iced ] && [ "$thaw_all" -ne 1 ] && ! grep -qxF -e "$f" <<<"$thaw"; then
      iced_skipped=$((iced_skipped + 1)); continue
    fi
  elif [ "$mode" = iced ]; then
    continue
  fi
  kept+=("$f")
  if declares serial "$f"; then serial+=("$f"); else par+=("$f"); fi
done
files=(); [ "${#kept[@]}" -eq 0 ] || files=("${kept[@]}")

[ "$iced_skipped" -eq 0 ] || echo "== $iced_skipped '# iced' harness(es) not run: their subject is on hold and no changed path names them — tests/run.sh --iced and the nightly workflow run them =="

if [ "${#files[@]}" -eq 0 ]; then
  echo "nothing to run in this tier — the selection is entirely '# deep' or '# iced' harnesses, which only --deep and --iced run"
  exit 0
fi

verify_checkout || { fatal "checkout is not intact before the suite even started"; exit 2; }

RUN_OUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/run-out.XXXXXX")" || { fatal "mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}"; exit 2; }
export RUN_OUT_DIR
shim=""
trap 'rm -rf "$RUN_OUT_DIR" ${shim:+"$shim"}' EXIT

# The merge gate must not be able to spend a paid `claude` run. AB_TIER tells a harness
# which tier it is in (absent, it is a by-hand run and deep), and the shim makes a spawn
# that ignores it exit 99 loudly instead of billing — the guarantee is structural. The one
# exception is `claude plugin test …` and `claude plugin validate …`, which make no session,
# no sign-in and no network and spend nothing: the shim execs the real binary for exactly
# those two argument shapes, and AB_CLAUDE_REAL names that binary — resolved BEFORE the
# shim is put on PATH, and empty where the machine has none (CI's runners), so the mod
# harness prints a SKIP by name rather than a vacuous pass.
# AB_NO_CLAUDE=1 makes the probe answer empty on a machine that HAS one: a binary that
# hangs at exec (a fresh Gatekeeper quarantine, 2026-10-08) is not usable, and the probe
# cannot tell — `command -v` finds it, the shim execs it, and the mod harness sits at the
# 600s kill bound with no summary. A SKIP by name is the honest answer, so the operator
# can say so. Not an inherited AB_CLAUDE_REAL: run.sh exports that, so a nested run (the
# test-runner harness drives this file from inside it) would read its parent's answer.
if [ -n "${AB_NO_CLAUDE:-}" ]; then export AB_CLAUDE_REAL=""
else export AB_CLAUDE_REAL="$(command -v claude 2>/dev/null || true)"; fi
export AB_TIER=deep
if [ "$mode" != deep ]; then
  export AB_TIER=gate
  shim="$(mktemp -d "${TMPDIR:-/tmp}/run-shim.XXXXXX")" || { fatal "mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}"; exit 2; }
  cat > "$shim/claude" <<SHIM
#!/bin/sh
case "\${1:-} \${2:-}" in
  "plugin test"|"plugin validate")
    [ -n "$AB_CLAUDE_REAL" ] && exec "$AB_CLAUDE_REAL" "\$@"
    echo "run.sh: no claude CLI on this machine, so plugin test/validate cannot run" >&2; exit 98 ;;
esac
echo "run.sh: the claude CLI is --deep only; this tier does not spawn it" >&2
exit 99
SHIM
  chmod +x "$shim/claude"
  PATH="$shim:$PATH"; export PATH
fi

[ -n "$jobs" ] || jobs="$(cpus)"
case "$jobs" in ''|*[!0-9]*|0) fatal "--jobs wants a positive integer, got '$jobs'"; exit 2 ;; esac

total_pass=0
total_fail=0
sum_secs=0
timings=""
bad=()
destroyed=""
first_notrun=""
start_ts=$(date +%s)

# Which bash — the harnesses are spawned as `bash "$f"`, and 3.2 leaks an fd per `< <( )`.
echo "== $(bash --version | head -1) at $(command -v bash); this runner is $BASH_VERSION =="
echo "== ${#files[@]} harness(es): ${#serial[@]} serial, ${#par[@]} in a pool of $jobs =="
if [ "${#serial[@]}" -gt 0 ]; then
  for f in "${serial[@]}"; do run_one "$f"; done
fi
if [ "${#par[@]}" -gt 0 ]; then
  printf '%s\0' "${par[@]}" | xargs -0 -P "$jobs" -n1 bash "$SELF" --run-one
fi

end_ts=$(date +%s)

# Output is replayed in FILE order, never completion order, so a parallel run reads
# exactly like a sequential one and a diff of two runs is still meaningful.
for f in "${files[@]}"; do
  b="${f##*/}"
  if [ ! -s "$RUN_OUT_DIR/$b.meta" ]; then
    fatal "$f produced no result at all — its worker died before writing one"
    bad+=("$f (no worker result)")
    continue
  fi
  read -r rc secs state < "$RUN_OUT_DIR/$b.meta"
  out="$(cat "$RUN_OUT_DIR/$b.out")"
  sum_secs=$((sum_secs + secs)); timings="${timings}${secs} ${f}"$'\n'

  group "$f"
  printf '%s\n' "$out"
  echo "-- $f took ${secs}s"
  endgroup

  case "$state" in
    broken) [ -n "$destroyed" ] || destroyed="$f" ;;
    notrun) [ -n "$first_notrun" ] || first_notrun="$f"; continue ;;
  esac

  # Two conventions are in use across tests/*.test.sh (.claude/rules/tests.md names both);
  # both are tried, and only their absence counts as "no summary".
  summary="$(printf '%s\n' "$out" | grep -oE 'pass=[0-9]+ fail=[0-9]+' | tail -n1 || true)"
  style=dense
  if [ -z "$summary" ]; then
    summary="$(printf '%s\n' "$out" | grep -oE '[0-9]+ passed, [0-9]+ failed' | tail -n1 || true)"
    style=prose
  fi
  if [ -z "$summary" ]; then
    fatal "$f exited $rc but printed no recognised pass/fail summary — the exit code alone is never trusted here"
    bad+=("$f (no summary, exit $rc)")
    continue
  fi

  if [ "$style" = dense ]; then
    f_pass="$(printf '%s' "$summary" | sed -E 's/pass=([0-9]+).*/\1/')"
    f_fail="$(printf '%s' "$summary" | sed -E 's/.*fail=([0-9]+)/\1/')"
  else
    f_pass="$(printf '%s' "$summary" | sed -E 's/^([0-9]+) passed.*/\1/')"
    f_fail="$(printf '%s' "$summary" | sed -E 's/.*, ([0-9]+) failed$/\1/')"
  fi
  total_pass=$((total_pass + f_pass))
  total_fail=$((total_fail + f_fail))

  if [ "$rc" -ne 0 ] || [ "$f_fail" -ne 0 ]; then
    fatal "$f — exit=$rc reported fail=$f_fail"
    bad+=("$f (exit $rc, fail=$f_fail)")
  fi
done

if [ -n "$destroyed" ] || [ -n "$first_notrun" ]; then
  fatal "the checkout was destroyed while running ${destroyed:-$first_notrun} — stopping immediately. See knowledge/findings/suite-cleanup-can-delete-its-own-checkout.md in the control panel."
  exit 2
fi

echo "== ${#files[@]} harness(es) in $((end_ts - start_ts))s — pass=$total_pass fail=$total_fail =="

# The time report. Printed for every run, judged for a full one only: a selection is
# small by construction and would always read as under budget.
echo "== $sum_secs harness-seconds; the slowest: $(printf '%s' "$timings" | sort -rn | head -5 | awk '{ sub(/^tests\//, "", $2); sub(/\.test\.sh$/, "", $2); printf "%s%s %ss", (NR > 1 ? ", " : ""), $2, $1 }') =="
while read -r t_secs t_f; do
  [ -n "$t_f" ] && [ "$t_secs" -gt "$HARNESS_WARN_S" ] || continue
  warn "$t_f took ${t_secs}s — over ${HARNESS_WARN_S}s, half the ${HARNESS_TIMEOUT}s kill bound. Split it or make its subject cheaper before it is killed."
done <<<"$timings"
if [ "$narrowed" -eq 0 ] && [ "$mode" != deep ] && [ "$mode" != iced ] && [ "$sum_secs" -gt "$SUITE_BUDGET_S" ]; then
  warn "the full suite took $sum_secs harness-seconds, over the budget of $SUITE_BUDGET_S. Nothing fails on this — but the next harness is a decision: say in the PR body what it costs and what it replaces (.claude/rules/tests.md, 'The time budget')."
fi
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  { echo "### harness suite — $sum_secs harness-seconds (budget $SUITE_BUDGET_S for a full run), ${#files[@]} harnesses, $((end_ts - start_ts))s wall"
    echo; echo "| harness | seconds |"; echo "|---|--:|"
    printf '%s' "$timings" | sort -rn | head -15 | awk '{ printf "| `%s` | %s |\n", $2, $1 }'
  } >> "$GITHUB_STEP_SUMMARY" 2>/dev/null || true
fi

if [ "${#bad[@]}" -gt 0 ]; then
  echo "FAILED harnesses:"
  printf '  - %s\n' "${bad[@]}"
  exit 1
fi

echo "ok: all ${#files[@]} harnesses passed — exit code AND reported fail=0 both verified for each"
