#!/usr/bin/env bash
#
# worktree-suite-parity.test.sh — the suite gives the SAME result from a linked git
# worktree as from the repository's main tree. Pins ai-bridge-v4/task-029 and its
# follow-up, task-030.
#
# WHY THIS EXISTS. install.sh refuses, by design, to run from a linked worktree (see its
# own header and tests/installer-worktree-guard.test.sh, which owns that guard). Calls in
# several harnesses used to hand it $TPL/plugin/scripts/init-bundle.sh unconditionally, so whenever $TPL
# itself was a worktree — which is EVERY role agent's working copy, per CONVENTIONS.md —
# the guard fired, those calls silently stamped nothing, and every downstream assertion
# that depended on the stamp failed for a reason that had nothing to do with whatever the
# agent actually changed. task-029 fixed the first file found this way
# (board-renderers.test.sh, 9 assertions); task-030 found and fixed four more measured the
# same evening — awaiting-queue (1), commit-as-identity (3), link-repos (3), and
# derived-indexes, the worst of the five at 19 of its 38 assertions. An agent that learns
# "some failures are always there" is an agent that waves the next real one through — the
# same shape as the vacuous self-skipping assertion tests/board-renderers.test.sh carried
# until task-024, and the rate-limited-review-behind-a-green-check defect from task-010.
#
# task-031 added a sixth: snapshot.test.sh carried the same dependency but under its own
# `set -e`, so the guard's exit 2 killed the whole script mid-run and it printed no
# summary line at all — worse than the other five, which at least printed fail=N. Same
# fix, same loop; see its own comment there for why $TPL routinely IS a worktree.
#
# WHAT THIS PINS, TOGETHER, SO NO PART OF THE FIX CAN REGRESS ALONE:
#   1. Each of the six harnesses below reports fail=0 when run from a FRESH LINKED
#      WORKTREE of this very checkout — not by reasoning about why it should, by
#      actually running it there and reading its own summary line.
#   2. install.sh ITSELF still refuses to run from that same worktree — the guard this
#      family of tasks was told not to weaken. A fix that made the guard permissive
#      instead of teaching each harness to route around it would flip this half red.
#
# HOW. `git worktree add` only ever checks out committed content, so this necessarily
# tests HEAD, not uncommitted edits — the same limitation every git-worktree fixture in
# this suite accepts (see installer-worktree-guard.test.sh's make_template, which commits
# before adding a worktree). That is the right tradeoff here too: CI always runs from a
# commit, never from someone's dirty tree.
#
# ok() compares actual to expected, per this directory's convention.
set -uo pipefail

# The repo root is handed to `cd` as an ALREADY-RESOLVED variable, never as a nested
# substitution: this path is named in the EXIT trap below, and tests/harness-temp-safety.sh
# refuses `cd "$(...)"` for any trap-referenced path (its NESTED-CD class). Splitting the
# assignment is the shape that file asks for -- "the canonicalising cd must be handed a
# variable already known good" -- not a way around it.
REPO_REL="$(dirname "$0")/.."
[ -d "$REPO_REL" ] || { echo "worktree-suite-parity.test: cannot locate repo root from $0" >&2; exit 2; }
REPO="$(cd -- "$REPO_REL" && pwd)"
[ -n "$REPO" ] && [ -d "$REPO" ] || { echo "worktree-suite-parity.test: repo root did not resolve" >&2; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/worktree-suite-parity.XXXXXX")" || {
  echo "worktree-suite-parity.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
WT="$TMP/wt"
trap 'git -C "$REPO" worktree remove --force "$WT" 2>/dev/null; rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

git -C "$REPO" worktree add -q --detach "$WT" HEAD >/dev/null 2>&1 || {
  echo "worktree-suite-parity.test: could not create a worktree from $REPO at HEAD." >&2; exit 2; }

# --- half 1: the guard, in the shape task-013 left it ----------------------
# IT NARROWED, AND BOTH DIRECTIONS ARE PINNED HERE. The refusal covered a BUNDLE STAMP too,
# because a stamp wrote 37 absolute symlinks into the source checkout — which is the very
# reason this parity file exists: every harness had to copy the template out of the
# worktree first. A bundle carries no machinery now, so the stamp writes no such link and
# the refusal is gone with the hazard. `--config` still links into
# ${CLAUDE_CONFIG_DIR:-~/.claude} by absolute path, so for that half nothing changed.
# A PARENT OF ITS OWN, because the stamp derives reposRoot from the bundle's parent
# directory (init-bundle.sh 4c): stamped directly in $TMP it would find the worktree
# beside it and legitimately link `repos/wt`, which is the repos VIEW and not the
# machinery link this half is about.
mkdir -p "$TMP/apart"
stamp_out="$(bash "$WT/plugin/scripts/init-bundle.sh" "$TMP/apart/stamped-from-wt" 2>&1)"; stamp_rc=$?
ok "a BUNDLE stamp from this worktree is allowed"        "$stamp_rc" 0
ok "…and it really stamped"                              "$([ -f "$TMP/apart/stamped-from-wt/instance.config.json" ] && echo yes || echo no)" yes
ok "…leaving no symlink behind"                          "$(find "$TMP/apart/stamped-from-wt" -type l 2>/dev/null | wc -l | tr -d ' ')" 0
cfg_dest="$TMP/cfgdest"; mkdir -p "$cfg_dest"
guard_out="$(CLAUDE_CONFIG_DIR="$cfg_dest" bash "$WT/plugin/scripts/init-bundle.sh" --config 2>&1)"; guard_rc=$?
ok "--config still refuses to run from this worktree"    "$guard_rc" 2
ok "…still says why"                                     "$(grep -qi 'refusing to link the config layer from a git worktree' <<<"$guard_out" && echo yes || echo no)" yes
ok "…still linked nothing"                               "$(find "$cfg_dest" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')" 0

# --- half 2: none of the six below still depends on install.sh having run from a
# location the guard above would refuse ---------------------------------------
# One function, run over every harness known to carry the $TPL/plugin/scripts/init-bundle.sh dependency,
# so a sixth one found later is a one-line addition here rather than a sixth copy of
# this whole block (that is the "one pin file, not N copies" this test exists to be).
check_harness_parity() { # <test-file-basename, without .test.sh>
  local name="$1" out rc summary p f
  out="$(bash "$WT/tests/$name.test.sh" 2>&1)"; rc=$?
  summary="$(printf '%s\n' "$out" | grep -oE 'pass=[0-9]+ fail=[0-9]+' | tail -n1)"
  if [ -z "$summary" ]; then
    # No silent skip (task-030 criterion 4, and the vacuity task-024 removed from this
    # same file): a harness that prints no summary at all is reported as a failure,
    # with the reason on stderr, never quietly passed over.
    echo "worktree-suite-parity.test: $name.test.sh printed no pass=/fail= summary:" >&2
    printf '%s\n' "$out" >&2
    fail=$((fail+1))
    return
  fi
  p="$(printf '%s' "$summary" | sed -E 's/pass=([0-9]+).*/\1/')"
  f="$(printf '%s' "$summary" | sed -E 's/.*fail=([0-9]+)/\1/')"
  if [ "$rc" -ne 0 ] || [ "$f" -ne 0 ]; then
    # The inner harness's own FAIL lines. Without them a red run names the harness and
    # never the assertion, which cost a full diagnosis round on 2026-09-15; the fallback
    # covers a harness whose failures are not marked `FAIL`.
    echo "worktree-suite-parity.test: $name.test.sh rc=$rc $summary — its own failures:" >&2
    printf '%s\n' "$out" | grep -E '^[[:space:]]*FAIL([[:space:]]|$)' >&2 || printf '%s\n' "$out" >&2
  fi
  ok "$name.test.sh exits 0 from a linked worktree" "$rc" 0
  ok "…and reports fail=0"                          "$f" 0
  # A vacuous pass (0 assertions run) would satisfy "fail=0" too — reject it explicitly,
  # the same shape task-024 found in this exact file.
  ok "…having actually run some assertions, not zero" "$([ "$p" -gt 0 ] && echo yes || echo no)" yes
}

for h in board-renderers awaiting-queue commit-as-identity link-repos derived-indexes snapshot banner-board-line; do
  check_harness_parity "$h"
done

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
