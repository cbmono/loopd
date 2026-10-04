#!/usr/bin/env bash
#
# derived-indexes.test.sh — the `index.md` files are derived, so they are gitignored;
# `knowledge/index.md` is NOT, and that exclusion is the interesting half.
#
# WHY. Every `/pm-loop` tick rewrites the root `index.md` and each project's, from
# the documents they summarise. On a bundle shared by two humans, each running their
# own loop, that is a merge conflict on every push over a file whose every line is
# re-derivable — the same argument that made `AWAITING.md` and `SNAPSHOT.json`
# derived-and-ignored. `knowledge/index.md` is deliberately excluded: it is the KB's
# curated lookup surface, it changes only when the KB changes rather than every tick,
# and every agent is told to scan it, so a fresh clone needs it to exist.
#
# The properties asserted, in order of how easy each is to break:
#   · `knowledge/index.md` is NOT ignored — a bare `index.md` pattern would have
#     swallowed it, and the failure would be silent until an agent found nothing;
#   · a per-project `index.md` IS ignored, at the one nesting level it occurs;
#   · install.sh adds both lines — to a fresh stamp AND to an instance whose
#     .gitignore predates them — and they are deliberately NOT in seed/.gitignore,
#     which is itself an active .gitignore over the template's own seed/ directory;
#   · a .gitignore line is INERT for an already-tracked file, so the installer
#     reports the exact `git rm --cached` rather than silently doing nothing;
#   · and it stays quiet when there is nothing tracked to report.
#
# `assert()` uses exit-code semantics: 0 is a PASS, matching the other harnesses.
set -uo pipefail

TPL="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$(dirname "$0")/../plugin/scripts/bundle-paths.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/derived-indexes.XXXXXX")" || {
  echo "derived-indexes.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# install.sh refuses to run from a linked git worktree (deliberately — see its own
# header), and every role agent's checkout of this template is one (CONVENTIONS.md).
# Re-point $BRIDGE_INSTALL at a filesystem-level copy of $TPL outside any git
# repository, exactly as tests/board-renderers.test.sh does — see there for the full
# rationale and the TMPDIR-recursion guard this carries along with it. Skipped when
# $TPL is already a main tree or no repo at all, so a plain clone pays nothing extra.
# ai-bridge-v4/task-030.
BRIDGE_INSTALL="$TPL/plugin/scripts/init-bundle.sh"
if command -v git >/dev/null 2>&1; then
  _tpl_gd="$(git -C "$TPL" rev-parse --absolute-git-dir 2>/dev/null || true)"
  _tpl_gc="$(git -C "$TPL" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [ -n "$_tpl_gd" ] && [ -n "$_tpl_gc" ] && [ "$_tpl_gd" != "$_tpl_gc" ]; then
    INSTALL_SRC="$TMP/install-src"
    _tpl_res="$(cd -- "$TPL" && pwd -P)"
    _src_res="$(cd -- "$TMP" && pwd -P)"
    case "$_src_res/" in
      "$_tpl_res"/*) echo "derived-indexes.test: TMPDIR ($_src_res) is inside the template tree ($_tpl_res); the install-source copy would recurse. Point TMPDIR outside the checkout." >&2; exit 2 ;;
    esac
    mkdir -p "$INSTALL_SRC"
    cp -R "$TPL"/. "$INSTALL_SRC"/
    rm -rf "$INSTALL_SRC/.git"
    BRIDGE_INSTALL="$INSTALL_SRC/plugin/scripts/init-bundle.sh"
  fi
fi

# fixture_bundle: a cached copy of a real stamp, for the one first stamp here that is only
# setup. tests/lib.sh says when a copy will do; every other stamp below stays the real one.
. "$TPL/tests/lib.sh"
pass=0; fail=0
assert() { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
yes_if() { if "$@" >/dev/null 2>&1; then echo 0; else echo 1; fi; }
no_if()  { if "$@" >/dev/null 2>&1; then echo 1; else echo 0; fi; }
has()    { grep -q <<<"$2" -- "$1" && echo 0 || echo 1; }
hasnt()  { grep -q <<<"$2" -- "$1" && echo 1 || echo 0; }

echo "== the lines are NOT in seed/.gitignore, and that is deliberate =="
# seed/.gitignore is an ACTIVE .gitignore inside the template's own seed/ directory,
# so a `/index.md` line there matches `seed/index.md` and stops the template
# from tracking its own seed file. It broke the upgrade.sh fixture, which re-inits a
# repo over a copy of seed/. So the lines live in install.sh, and this asserts the trap
# stays closed — against git's own answer, not the pattern text.
assert "seed/.gitignore has no /index.md line" \
  "$(no_if grep -qxF '/index.md' "$TPL/plugin/seed/.gitignore")"
# Line 73 above was repointed at plugin/seed/ in #125 and this one was not. `--no-index`
# is DESIGNED to answer for a path that does not exist, so the stale `seed/index.md` still
# exited 1 and the assertion still passed — the pattern could have matched and nothing here
# would have said so. The marker below is what makes the path scanner check this one path:
# a blanket must-resolve rule over `check-ignore` targets would be wrong for that same
# reason, so the rule is opt-in per call site.
# path-scan: must-resolve — this probe is about a path that DOES exist in the seed
assert "…and the seed's own index.md is trackable" \
  "$(no_if git -C "$TPL" check-ignore --no-index -q plugin/seed/index.md)"
assert "…and it says why, so nobody 'fixes' it" \
  "$(yes_if grep -q 'ACTIVE .gitignore' "$TPL/plugin/seed/.gitignore")"
# A bare `index.md` line would match at every depth, knowledge/ included.
assert "no bare 'index.md' pattern in the seed" \
  "$(no_if grep -qx 'index.md' "$TPL/plugin/seed/.gitignore")"

echo
echo "== a live instance: git's own answer, not the pattern text =="
INST="$TMP/g/_ai-bridge-g"; mkdir -p "$INST"
bash "$BRIDGE_INSTALL" "$INST" >/dev/null 2>&1
assert "a FRESH stamp gets the root line"   "$(yes_if grep -qxF "/$AB_INDEX" "$INST/.gitignore")"
assert "…and the per-project line"          "$(yes_if grep -qxF '/projects/*/index.md' "$INST/.gitignore")"
( cd "$INST" && git init -q . && git config user.email t@e.st && git config user.name t )
mkdir -p "$INST/projects/p1" "$INST/knowledge" "$INST/$AB_DIR"
printf 'root\n'  > "$INST/$AB_INDEX"
printf 'proj\n'  > "$INST/projects/p1/index.md"
printf 'kb\n'    > "$INST/knowledge/index.md"
ignored() { ( cd "$INST" && git check-ignore -q "$1" ); }
assert "the root index.md is ignored"       "$(yes_if ignored "$AB_INDEX")"
assert "a project's index.md is ignored"    "$(yes_if ignored projects/p1/index.md)"
assert "knowledge/index.md is NOT ignored"  "$(no_if ignored knowledge/index.md)"
assert "a project's log.md is NOT ignored"  "$(no_if ignored projects/p1/log.md)"
# `git add -A` must not sweep the derived ones in — that is the property the loop
# and /new-project both rely on when they name a directory as a pathspec.
( cd "$INST" && git add -A >/dev/null 2>&1 )
STAGED="$( cd "$INST" && git diff --cached --name-only )"
assert "git add -A skips the root index"    "$(hasnt "^$AB_INDEX\$" "$STAGED")"
assert "…and the project index"             "$(hasnt 'projects/p1/index\.md' "$STAGED")"
assert "…but stages the KB index"           "$(has 'knowledge/index\.md' "$STAGED")"

echo
echo "== an instance whose .gitignore predates the lines =="
OLD="$TMP/g/_ai-bridge-old"; mkdir -p "$OLD"
fixture_bundle "$OLD"   # setup: the stamp under test is the RE-stamp below
grep -vE "^/(${AB_INDEX//./\\.}|projects/\*/index\.md)$" "$OLD/.gitignore" > "$OLD/.gi" && mv "$OLD/.gi" "$OLD/.gitignore"
assert "the lines really were removed"      "$(no_if grep -qxF "/$AB_INDEX" "$OLD/.gitignore")"
bash "$BRIDGE_INSTALL" "$OLD" >/dev/null 2>&1
assert "install.sh re-adds the root line"   "$(yes_if grep -qxF "/$AB_INDEX" "$OLD/.gitignore")"
assert "…and the per-project line"          "$(yes_if grep -qxF '/projects/*/index.md' "$OLD/.gitignore")"
bash "$BRIDGE_INSTALL" "$OLD" >/dev/null 2>&1
COUNT="$(grep -cxF "/$AB_INDEX" "$OLD/.gitignore")"
assert "a re-run does not duplicate them"   "$([[ "$COUNT" == 1 ]] && echo 0 || echo 1)"

echo
echo "== an already-TRACKED index.md: reported, never touched =="
# A .gitignore line does nothing to a file git already tracks. Silence here would be
# the whole change quietly not happening, so the installer prints the exact command.
TRK="$TMP/g/_ai-bridge-tracked"; mkdir -p "$TRK/projects/p1"
bash "$BRIDGE_INSTALL" "$TRK" >/dev/null 2>&1
mkdir -p "$TRK/$AB_DIR"
printf 'root\n' > "$TRK/$AB_INDEX"; printf 'proj\n' > "$TRK/projects/p1/index.md"
( cd "$TRK" && git init -q . && git config user.email t@e.st && git config user.name t \
  && git add -f "$AB_INDEX" projects/p1/index.md >/dev/null && git commit -qm seed )
OUT="$(bash "$BRIDGE_INSTALL" "$TRK" 2>&1)"
assert "the tracked root index is reported"  "$(has "tracked $AB_INDEX" "$OUT")"
assert "…and the tracked project index"      "$(has 'tracked projects/p1/index.md' "$OUT")"
assert "…with the exact rm --cached command" "$(has 'git rm --cached' "$OUT")"
assert "…and the file is NOT removed"        "$(yes_if grep -q 'root' "$TRK/$AB_INDEX")"
assert "…and it is still tracked afterwards" "$(yes_if bash -c "cd '$TRK' && git ls-files --error-unmatch '$AB_INDEX'")"
# Once untracked, the report must go quiet — it is a to-do, not a permanent banner.
( cd "$TRK" && git rm --cached -q -- "$AB_INDEX" 'projects/*/index.md' && git commit -qm untrack )
OUT2="$(bash "$BRIDGE_INSTALL" "$TRK" 2>&1)"
assert "after untracking, nothing is reported" "$(hasnt "tracked $AB_INDEX" "$OUT2")"
assert "…and the files survive on disk"        "$(yes_if grep -q 'root' "$TRK/$AB_INDEX")"
# An instance that is not a git repo at all must not error or report.
NOGIT="$TMP/g/_ai-bridge-nogit"; mkdir -p "$NOGIT"
RC=0; OUT3="$(bash "$BRIDGE_INSTALL" "$NOGIT" 2>&1)" || RC=$?
assert "a non-repo instance exits 0"           "$([[ $RC -eq 0 ]] && echo 0 || echo 1)"
assert "…and reports no tracked indexes"       "$(hasnt "tracked $AB_INDEX" "$OUT3")"

echo
echo "== a RETAINED project's index.md: committed, and NOT hidden by check-ignore =="
# Plain `git check-ignore` skips already-tracked paths and would hide this defect —
# these assertions use --no-index (or a fresh untracked path) throughout, per the
# task's own testing trap. A retained project (task-006) stops being rewritten by the
# tick, so its index.md becomes a permanent, hand-committed file instead of a derived
# view — it must NOT read as ignored even though the blanket per-project pattern
# still applies to every OTHER (non-retained) project.
RET="$TMP/g/_ai-bridge-retain"; mkdir -p "$RET/projects/p1" "$RET/projects/p2"
bash "$BRIDGE_INSTALL" "$RET" >/dev/null 2>&1
( cd "$RET" && git init -q . && git config user.email t@e.st && git config user.name t )
printf 'active\n'   > "$RET/projects/p1/index.md"
printf 'retained\n' > "$RET/projects/p2/index.md"
noidx() { ( cd "$RET" && git check-ignore --no-index -q "$1" ); }
assert "before retaining, p2's index also reads ignored (--no-index)" \
  "$(yes_if noidx projects/p2/index.md)"
# Retain p2: append the documented negation AFTER the blanket lines (order matters —
# git applies .gitignore patterns in file order, later wins), then track the file.
printf '!projects/p2/index.md\n' >> "$RET/.gitignore"
( cd "$RET" && git add -A >/dev/null 2>&1 && git commit -qm 'retain p2' >/dev/null )
assert "p1 (not retained) is still ignored (--no-index)" \
  "$(yes_if noidx projects/p1/index.md)"
assert "p2 (retained) is NOT ignored (--no-index)" \
  "$(no_if noidx projects/p2/index.md)"
assert "p2's index.md is actually tracked" \
  "$(yes_if bash -c "cd '$RET' && git ls-files --error-unmatch projects/p2/index.md")"
assert "p1's index.md was never staged" \
  "$(no_if bash -c "cd '$RET' && git ls-files --error-unmatch projects/p1/index.md")"

echo
echo "== …and that survives an install.sh RE-STAMP, not just the post-edit state =="
# This rule has been reversed by a re-stamp at least twice on real instances — assert
# the state AFTER re-running install.sh, not just right after the edit.
bash "$BRIDGE_INSTALL" "$RET" >/dev/null 2>&1
assert "the negation line is still present"    \
  "$(yes_if grep -qxF '!projects/p2/index.md' "$RET/.gitignore")"
assert "the blanket line is not duplicated"    \
  "$([[ "$(grep -cxF '/projects/*/index.md' "$RET/.gitignore")" == 1 ]] && echo 0 || echo 1)"
assert "post-stamp: p2 still reads NOT ignored (--no-index)" \
  "$(no_if noidx projects/p2/index.md)"
assert "post-stamp: p1 still reads ignored (--no-index)" \
  "$(yes_if noidx projects/p1/index.md)"

echo
echo "== …while a comment-only override (no negation) does NOT survive a re-stamp =="
# This is the trap the fix documents: overriding by deleting the two blanket lines and
# asserting "we track these" only in prose does not survive, because install.sh
# re-adds whichever of the two lines it finds missing and never reads the comment.
BAD="$TMP/g/_ai-bridge-bad-override"; mkdir -p "$BAD/projects/p1"
bash "$BRIDGE_INSTALL" "$BAD" >/dev/null 2>&1
grep -vE '^/(index\.md|projects/\*/index\.md)$' "$BAD/.gitignore" > "$BAD/.gi"
printf '\n# NOT ignoring the navigation indexes, deliberately — this instance tracks them.\n' >> "$BAD/.gi"
mv "$BAD/.gi" "$BAD/.gitignore"
assert "the comment-only override really is in place" \
  "$(yes_if grep -q 'NOT ignoring the navigation indexes' "$BAD/.gitignore")"
assert "…and the blanket line really is gone"          \
  "$(no_if grep -qxF '/projects/*/index.md' "$BAD/.gitignore")"
bash "$BRIDGE_INSTALL" "$BAD" >/dev/null 2>&1
assert "a re-stamp silently reverses a comment-only override" \
  "$(yes_if grep -qxF '/projects/*/index.md' "$BAD/.gitignore")"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
