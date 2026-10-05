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
# WHAT CHANGED ON 2026-10-05, AND WHY. Until then half 2 proved its point by RE-RUNNING all
# seven listed harnesses inside the worktree: 229 s in CI for 27 assertions, 5.6% of a
# suite that had grown to 23 minutes (~4,100 harness-seconds on the 3-CPU runner), and
# every one of the seven already runs once in that same suite. Read side by side, the
# seven cope in ONE way: each binds `BRIDGE_INSTALL="$TPL/plugin/scripts/init-bundle.sh"`,
# then a block — `if command -v git …` down to its `fi` — asks git the installer guard's
# own question of $TPL (`--absolute-git-dir` against `--git-common-dir`) and, in a linked
# worktree, re-points the variable at a filesystem copy of the checkout with `.git`
# removed; every stamp then goes through "$BRIDGE_INSTALL". The block is PASTED into each
# file, not sourced from a helper, so "they share a mechanism" is true of the text and
# has to be proven of each copy. Hence three proofs where there was one:
#   a. STATIC, per harness — every path to init-bundle.sh is that one variable, the block
#      is there, and nothing stamps before it or re-binds the default after it. A new
#      unconditional `bash "$TPL/plugin/scripts/init-bundle.sh"` fails here.
#   b. EXECUTED, per harness — the harness's OWN copy of the block is cut out and run with
#      TPL = this worktree, and the installer it settles on must exist outside every
#      linked worktree; run again from a plain directory it must copy nothing. This is
#      what a text match cannot give: a pasted copy whose comparison is wrong reads fine.
#      About a quarter of a second each — the block's whole cost is one `cp -R`.
#   c. END TO END, for ONE harness — link-repos, the fastest when they were measured for
#      this change (5 s, against 15 to 31 s for five others; board-renderers, the
#      longest file of the seven, was not timed) — still runs whole in the worktree, so
#      the chain from routing block to a green summary line is still proven by a run.
# And section 3 MUTATES a listed harness four ways and asserts (a) or (b) flags each one,
# because a check that has never been seen to fail is the vacuity this file exists
# against.
#
# WHAT THAT GIVES UP, STATED RATHER THAN HIDDEN. The six harnesses no longer re-run here
# are proven to route their STAMP correctly, which is the defect this file was written
# for. They are no longer proven free of any OTHER dependence on the checkout being a
# main tree — a future `git -C "$TPL" …` that answers differently in a worktree would
# have turned the old half 2 red and will not turn this one red. Nothing of that kind
# exists in the seven today; if one appears, move that harness into the end-to-end loop,
# which is a one-word edit.
#
# WHAT THIS PINS, TOGETHER, SO NO PART OF THE FIX CAN REGRESS ALONE:
#   1. install.sh ITSELF still refuses to run from that same worktree — the guard this
#      family of tasks was told not to weaken. A fix that made the guard permissive
#      instead of teaching each harness to route around it would flip this half red.
#   2. Each of the seven harnesses below copes when ITS checkout is a FRESH LINKED
#      WORKTREE of this very checkout — (a), (b) and (c) above.
#   3. The checks in 2 can fail.
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

# --- half 2: none of the seven below still depends on install.sh having run from a
# location the guard above would refuse ---------------------------------------
# One list, so an eighth harness found later is a one-word addition here rather than an
# eighth copy of this file (that is the "one pin file, not N copies" this test exists to
# be). Listing a harness here is a claim that it stamps through the routing block; 2a
# fails a listed file that does not.
ROUTED="board-renderers awaiting-queue commit-as-identity link-repos derived-indexes snapshot banner-board-line"

# The routing block's line span in <file>, as `<first> <last>`; nothing when there is no
# such block. It is recognised by the question it asks, not by its variable names (which
# differ between the copies): an `if command -v git` whose very next line reads the
# checkout's absolute git dir, down to the first `fi` in column 0.
routing_span() { # <file>
  awk '
    inb  { if ($0 == "fi") { print first, NR; exit } next }
    held { held = 0; if ($0 ~ /rev-parse --absolute-git-dir/) { inb = 1; next } }
    /^if command -v git >\/dev\/null 2>&1; then$/ { held = 1; first = NR }
  ' "$1" 2>/dev/null
}

# 2a. Every way <file> can fail to route its stamp, one word per line; nothing when it
# is clean. Comment lines are not code and are skipped throughout.
routing_defects() { # <file>
  local f="$1" span first last
  [ -f "$f" ] || { echo missing-file; return; }
  span="$(routing_span "$f")"
  if [ -z "$span" ]; then echo no-routing-block; first=0; last=0
  else first="${span% *}"; last="${span#* }"; fi
  awk -v first="$first" -v last="$last" '
    /^[[:space:]]*#/ { next }
    # the default binding: the ONE place the installer of the checkout itself may be named
    /^[[:space:]]*BRIDGE_INSTALL="[$]TPL\/plugin\/scripts\/init-bundle\.sh"[[:space:]]*$/ {
      bound = 1
      if (last && NR > last) print "default-rebound-after-route"
      next
    }
    # the re-point, inside the block, at a copy that is by construction not $TPL
    /^[[:space:]]*BRIDGE_INSTALL="[$][A-Za-z_]+\/[^"]*init-bundle\.sh"[[:space:]]*$/ {
      if (NR < first || NR > last) print "rebound-outside-route"
      next
    }
    # any other path to the installer is a call the block never routed
    /\/init-bundle\.sh/ { print "unrouted-installer-path"; next }
    /[$][{]?BRIDGE_INSTALL/ {
      if (NR > last) used = 1
      else if (/(^|[^[:alnum:]_])(bash|sh|exec|source|\.)[[:space:]]/) print "stamp-before-route"
    }
    END {
      if (!bound) print "no-default-binding"
      if (!used)  print "never-stamps"
    }
  ' "$f" 2>/dev/null | sort -u
}

# Is <dir> inside a LINKED worktree — the installer guard's own question, asked the way
# the guard asks it.
in_linked_worktree() { # <dir>
  local gd gc
  gd="$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null || true)"
  gc="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  [ -n "$gd" ] && [ -n "$gc" ] && [ "$gd" != "$gc" ]
}

# 2b. Run <file>'s OWN routing block with <tpl> as the checkout and print the installer
# it settles on. Only the block runs — the default binding is supplied here exactly as
# 2a has just proven the file spells it — so this costs one `cp -R`, not a harness run.
route_from() { # <file> <tpl> <scratch-dir>
  local span block
  span="$(routing_span "$1")"; [ -n "$span" ] || return 1
  block="$(sed -n "${span% *},${span#* }p" "$1")"
  mkdir -p "$3" || return 1
  TPL="$2" TMP="$3" ROUTING_BLOCK="$block" bash -c '
    set -uo pipefail
    BRIDGE_INSTALL="$TPL/plugin/scripts/init-bundle.sh"
    eval "$ROUTING_BLOCK"
    printf "%s\n" "$BRIDGE_INSTALL"' 2>/dev/null
}

# yes when <file>'s block, run from this worktree, lands on an installer that exists, is
# not the worktree's own, and sits where the guard has no linked worktree to refuse.
routes_clear_of_worktree() { # <file> <scratch-dir>
  local got
  got="$(route_from "$1" "$WT" "$2")" || { echo no; return; }
  if [ -n "$got" ] && [ -f "$got" ] && [ "$got" != "$WT/plugin/scripts/init-bundle.sh" ] \
     && ! in_linked_worktree "$(dirname "$got")"; then echo yes; else echo no; fi
}

# The other direction, or 2b would pass a block that copies the tree everywhere: from a
# directory that is no linked worktree the default stands and nothing is copied.
PLAIN="$TMP/plain"; mkdir -p "$PLAIN/plugin/scripts"
routes_nowhere_from_plain_tree() { # <file> <scratch-dir>
  local got
  got="$(route_from "$1" "$PLAIN" "$2")" || { echo no; return; }
  if [ "$got" = "$PLAIN/plugin/scripts/init-bundle.sh" ] && [ -z "$(ls -A "$2" 2>/dev/null)" ]; then echo yes; else echo no; fi
}

for routed in $ROUTED; do
  rf="$WT/tests/$routed.test.sh"
  ok "$routed stamps only through its routing block" "$(routing_defects "$rf" | tr '\n' ' ')" ""
  ok "…whose own block routes clear of this worktree" "$(routes_clear_of_worktree "$rf" "$TMP/route/$routed")" yes
  ok "…and copies nothing from a plain tree"          "$(routes_nowhere_from_plain_tree "$rf" "$TMP/plain-route/$routed")" yes
done

# 2c. One function, run over the harness that still runs WHOLE in the worktree. Moving a
# name from $ROUTED's proof into this loop is how a harness with a worktree dependence of
# some OTHER kind gets pinned; tests/parity-failure-detail.test.sh drives this same loop
# over fixtures to prove its reporting.
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

for h in link-repos; do
  check_harness_parity "$h"
done

# --- 3: the mutants — 2a and 2b can fail ------------------------------------
# One listed harness, copied out and broken four ways. Each mutation is checked to have
# LANDED before its verdict is read: a `sed` that matched nothing would leave a clean
# copy, and "the clean copy is clean" proves nothing about the check.
MUT_SRC="$WT/tests/link-repos.test.sh"
MUT="$TMP/mutants"; mkdir -p "$MUT"
mut_span="$(routing_span "$MUT_SRC")"; mut_first="${mut_span% *}"; mut_last="${mut_span#* }"
landed()  { if [ -s "$1" ] && ! cmp -s "$1" "$MUT_SRC"; then echo yes; else echo no; fi; }
flagged() { if routing_defects "$1" | grep -qx "$2"; then echo yes; else echo no; fi; }

# The defect this file was written for: a stamp handed the checkout's own installer.
awk 'done != 1 && /^bash "\$BRIDGE_INSTALL" / { sub(/"\$BRIDGE_INSTALL"/, "\"$TPL/plugin/scripts/init-bundle.sh\""); done = 1 } { print }' \
  "$MUT_SRC" >"$MUT/unconditional.test.sh" 2>/dev/null
ok "mutant: an unconditional stamp call is back"      "$(landed "$MUT/unconditional.test.sh")" yes
ok "…and 2a flags it"                                 "$(flagged "$MUT/unconditional.test.sh" unrouted-installer-path)" yes

# The block deleted outright, the calls still spelled "$BRIDGE_INSTALL".
if [ -n "$mut_span" ]; then sed "${mut_first},${mut_last}d" "$MUT_SRC" >"$MUT/no-block.test.sh" 2>/dev/null; fi
ok "mutant: the routing block is gone"                "$(landed "$MUT/no-block.test.sh")" yes
ok "…and 2a flags it"                                 "$(flagged "$MUT/no-block.test.sh" no-routing-block)" yes

# The block intact and then undone: the default bound again below it.
awk -v last="${mut_last:-0}" '{ print } NR == last { print "BRIDGE_INSTALL=\"$TPL/plugin/scripts/init-bundle.sh\"" }' \
  "$MUT_SRC" >"$MUT/rebound.test.sh" 2>/dev/null
ok "mutant: the default is re-bound after the block"  "$(landed "$MUT/rebound.test.sh")" yes
ok "…and 2a flags it"                                 "$(flagged "$MUT/rebound.test.sh" default-rebound-after-route)" yes

# The one 2a cannot see, and the reason 2b runs the block instead of reading it: the
# comparison inverted, so the copy is taken everywhere EXCEPT in a linked worktree.
awk -v first="${mut_first:-0}" -v last="${mut_last:-0}" \
  'NR >= first && NR <= last { sub(/"\$_tpl_gd" != "\$_tpl_gc"/, "\"$_tpl_gd\" = \"$_tpl_gc\"") } { print }' \
  "$MUT_SRC" >"$MUT/inverted.test.sh" 2>/dev/null
ok "mutant: the block's comparison is inverted"       "$(landed "$MUT/inverted.test.sh")" yes
ok "…2a reads it as clean, as text must"              "$(routing_defects "$MUT/inverted.test.sh" | tr '\n' ' ')" ""
ok "…and 2b, which runs it, does not"                 "$(routes_clear_of_worktree "$MUT/inverted.test.sh" "$TMP/route/mutant-inverted")" no

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
