#!/usr/bin/env bash
#
# run.sh — the ONE implementation of this repo's harness selection. CI calls it too.
#   --changed [--base <ref>]  the core harnesses plus every harness naming a changed path
#   --all                     every tests/*.test.sh (the default)
#   --ci                      the workflow entry: the fast path on a PR diff that touches
#                             only plugin/ and top-level harness files, the full suite on
#                             anything else
#   --deep                    ONLY the harnesses marked `# deep` — they spawn the claude
#                             CLI and cost money; no other mode runs them or reaches it
#   --jobs N                  harnesses in parallel (default: CPUs); `# serial` runs alone
# Each harness is bounded by HARNESS_TIMEOUT seconds (600, 1800 under --deep): one that
# never returns is killed and fails as ITSELF, and the rest of the suite still reports.
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
# gating harness is review-clearance: 311s in a pool of 3 on run 34783957083, and 455s
# standalone after #226 grew it — though that figure shared a machine with a sibling suite,
# so treat it as an upper bound. Re-measure it in CI before trimming 600. A `# deep`
# harness spawns a paid CLI call and measures ~10m.
HARNESS_TIMEOUT="${HARNESS_TIMEOUT:-600}"
HARNESS_TIMEOUT_DEEP="${HARNESS_TIMEOUT_DEEP:-1800}"

usage() { sed -n '3,14p' "$0" | sed 's/^#\{1,\} \{0,1\}//'; }

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
# `# serial` (never run beside another harness) or `# deep` (spawns the claude CLI).
declares() { head -20 "$2" 2>/dev/null | grep -qE "^# $1( |$)"; }

# bounded <harness> — the harness under a HARNESS_TIMEOUT-second wall clock, exiting 142
# when it trips. The bound has to kill the process GROUP, not the harness: a harness
# blocked in a child leaves that child holding the capture's pipe, so `out="$( )"` below
# goes on blocking past the bound (measured: 60s under a 3s bound). `perl`, not
# `timeout(1)`, because macos-latest ships the first and not the second; and the exit
# status is re-encoded because a bare `$?>>8` turns every signal death into 0.
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

# `.git` is a FILE in a linked worktree. init-bundle.sh --config refuses to run from one
# by design, so four harnesses fail there for reasons unrelated to the code under test.
[ -f "$workspace/.git" ] && echo "run.sh: this is a git WORKTREE — derived-indexes, link-repos, snapshot and board-renderers fail here by design (.claude/rules/tests.md). Verify from the main checkout or a fresh clone." >&2

case "$mode" in
  all|deep) ;;

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
      announce "changed-path selection — the ${#CORE[@]} core harnesses plus every harness that names a changed path:" "$changed"
      [ -z "$UNNAMED" ] || echo "no harness names these changed paths, so they selected nothing beyond the core — verify with --all before the PR: $UNNAMED"
    fi
    ;;

  ci)
    # PRs only; a push to main always runs everything. The verdict FAILS TOWARD THE FULL
    # SUITE at every step — empty diff, failed fetch, any path outside plugin/,
    # .claude-plugin/ and the top-level harness files, or a changed path NO harness names.
    # That last one differs from --changed on purpose: this is the merge gate, and there
    # is no --all run after it.
    #
    # A TOP-LEVEL HARNESS IN THE DIFF NO LONGER TURNS THE FAST PATH OFF. Every change here
    # carries its test, so "plugin-only" described no pull request at all: of the last 40
    # merged, 0 took the fast path and 15 touched nothing but plugin/ and tests/*.test.sh
    # (measured 2026-10-05). A changed harness selects ITSELF (select_derived), so it runs;
    # a DELETED one cannot, lands in UNNAMED, and buys the full suite. Anything else under
    # tests/ — fixtures, tools, this runner — is shared by harnesses that do not name it,
    # and still means everything runs.
    if [ "${GITHUB_EVENT_NAME:-}" = "pull_request" ] && [ -n "${GITHUB_BASE_REF:-}" ] \
       && git fetch --quiet origin "$GITHUB_BASE_REF"; then
      changed="$(git diff --name-only "origin/$GITHUB_BASE_REF...HEAD")"
      if [ -n "$changed" ] && ! printf '%s\n' "$changed" | grep -qvE '^(plugin/|\.claude-plugin/|tests/[^/]+\.test\.sh$)'; then
        kind="plugin-only"
        ! printf '%s\n' "$changed" | grep -qE '^tests/' || kind="plugin-and-harness"
        select_derived "$changed"
        if [ -n "$UNNAMED" ]; then
          echo "$kind diff, but no harness names these paths — running the FULL suite: $UNNAMED"
        else
          files_from_selection
          announce "$kind diff — running the core plugin harnesses plus every harness that names a changed path:" "$changed"
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
serial=(); par=(); kept=()
for f in "${files[@]}"; do
  if declares deep "$f"; then
    [ "$mode" = deep ] || continue
  elif [ "$mode" = deep ]; then
    continue
  fi
  kept+=("$f")
  if declares serial "$f"; then serial+=("$f"); else par+=("$f"); fi
done
files=(); [ "${#kept[@]}" -eq 0 ] || files=("${kept[@]}")

if [ "${#files[@]}" -eq 0 ]; then
  echo "nothing to run in this tier — the selection is entirely '# deep' harnesses, which only --deep runs"
  exit 0
fi

verify_checkout || { fatal "checkout is not intact before the suite even started"; exit 2; }

RUN_OUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/run-out.XXXXXX")" || { fatal "mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}"; exit 2; }
export RUN_OUT_DIR
shim=""
trap 'rm -rf "$RUN_OUT_DIR" ${shim:+"$shim"}' EXIT

# The merge gate must not be able to spend a paid `claude` run. AB_TIER tells a harness
# which tier it is in (absent, it is a by-hand run and deep), and the shim makes a spawn
# that ignores it exit 99 loudly instead of billing — the guarantee is structural.
export AB_TIER=deep
if [ "$mode" != deep ]; then
  export AB_TIER=gate
  shim="$(mktemp -d "${TMPDIR:-/tmp}/run-shim.XXXXXX")" || { fatal "mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}"; exit 2; }
  printf '#!/bin/sh\necho "run.sh: the claude CLI is --deep only; this tier does not spawn it" >&2\nexit 99\n' > "$shim/claude"
  chmod +x "$shim/claude"
  PATH="$shim:$PATH"; export PATH
fi

[ -n "$jobs" ] || jobs="$(cpus)"
case "$jobs" in ''|*[!0-9]*|0) fatal "--jobs wants a positive integer, got '$jobs'"; exit 2 ;; esac

total_pass=0
total_fail=0
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

if [ "${#bad[@]}" -gt 0 ]; then
  echo "FAILED harnesses:"
  printf '  - %s\n' "${bad[@]}"
  exit 1
fi

echo "ok: all ${#files[@]} harnesses passed — exit code AND reported fail=0 both verified for each"
