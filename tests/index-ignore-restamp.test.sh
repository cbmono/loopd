#!/usr/bin/env bash
#
# index-ignore-restamp.test.sh — the derived-index .gitignore block is idempotently
# RE-APPLIABLE, not append-once, and a re-stamp cannot corrupt what is around it.
#
# WHY. install.sh used to guard this block with "append only if the two literal rule
# lines (`/index.md`, `/projects/*/index.md`) are missing". Once an instance was stamped
# a single time, both lines existed forever, so the guard short-circuited on every later
# run — a corrected comment, or a new rule added to the block, reached only fresh
# installs. Confirmed against real instances twice within an hour (this bundle and the
# Alteos instance both stayed stale through a re-stamp). ai-bridge-v4/task-009.
#
# The fix mirrors the machinery block: a marker pair (`# >>> loopd index ignore >>>`
# / `# <<< loopd index ignore <<<`), fully rewritten between the markers on every
# run. A SINGLE stamp cannot exercise this class of bug — the guard's failure mode only
# shows up on the SECOND run — so every positive assertion here stamps a fixture twice
# with genuinely different template content between the runs (the same shape task-008
# used). The negative properties matter just as much:
#
#   · a local .gitignore line OUTSIDE the marker block survives a re-stamp BYTE FOR
#     BYTE — this is what makes the fix safe rather than merely correct: a block-
#     replacing stamp that eats local edits is the exact defect the Alteos instance's
#     own ".gitignore" already documents having paid for once;
#   · a RETAINED project's negation escape hatch (`!projects/<slug>/index.md`, added by
#     hand after the block, task-008 / #29) still wins after a re-stamp — checked with
#     `git check-ignore`, not by grepping for the pattern string, because the ordering
#     is the mechanism, not the presence of a line;
#   · a comment line that merely RESEMBLES the marker text is not mistaken for it, and
#     does not stop the block from being applied.
#
# assert(): 0 is a PASS, matching the other harnesses here.
set -uo pipefail

# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$(dirname "$0")/../plugin/scripts/bundle-paths.sh"

# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$(dirname "$0")/../plugin/scripts/bundle-paths.sh"

TPLSRC="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/index-ignore-fixture.XXXXXX")" || {
  echo "index-ignore-restamp.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
assert() { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
yes_if() { if "$@" >/dev/null 2>&1; then echo 0; else echo 1; fi; }
no_if()  { if "$@" >/dev/null 2>&1; then echo 1; else echo 0; fi; }

# A copy of the template, so mutating its install.sh between runs cannot touch the real
# one, and so install.sh's own worktree-refusal guard never fires (it inspects its own
# dirname's .git, and this copy has none).
TPL="$TMP/tpl"; mkdir -p "$TPL"
( cd "$TPLSRC" && git ls-files . ) | while IFS= read -r f; do
  [ -n "$f" ] || continue
  mkdir -p "$TPL/$(dirname "$f")"; cp "$TPLSRC/$f" "$TPL/$f" 2>/dev/null || true
done
chmod +x "$TPL/plugin/scripts/init-bundle.sh" "$TPL"/plugin/scripts/*.sh 2>/dev/null || true

git_check_ignore() { # $1 = instance dir, $2 = path relative to it -> 0 if ignored
  ( cd "$1" && git init -q . >/dev/null 2>&1 || true; git check-ignore -q "$2" )
}

# ---------------------------------------------------------------------------------
# 1. A fresh stamp gets a marker-wrapped block at all (baseline — not the interesting
#    case, but a broken marker emission would fail every assertion below for the
#    wrong reason).
# ---------------------------------------------------------------------------------
INST="$TMP/inst"; mkdir -p "$INST"
bash "$TPL/plugin/scripts/init-bundle.sh" "$INST" >"$TMP/out1" 2>&1
assert "a fresh instance stamps"                    "$(yes_if test -f "$INST/instance.config.json")"
assert "…and gets the index-ignore BEGIN marker"    "$(yes_if grep -qxF '# >>> loopd index ignore >>>' "$INST/.gitignore")"
assert "…and the END marker"                        "$(yes_if grep -qxF '# <<< loopd index ignore <<<' "$INST/.gitignore")"
assert "…and the derived index is actually ignored" "$(yes_if git_check_ignore "$INST" "$AB_INDEX")"
assert "…and a project's index.md is ignored too"   "$(yes_if git_check_ignore "$INST" projects/demo/index.md)"
assert "…and the KB mount's gitdir, from the seed"   "$(yes_if git_check_ignore "$INST" "$AB_DIR/kb.git/HEAD")"

# ---------------------------------------------------------------------------------
# 2. THE BUG'S OWN SHAPE: an instance stamped by the OLD, unmarked, guard-based
#    install.sh — the two rule lines present and adjacent, with no marker pair, an
#    older comment, a local hand-edit elsewhere in the file, and a retained project's
#    negation placed (per the OLD comment's own instructions) right after the two
#    rule lines. This is deliberately built by hand rather than by running an old
#    install.sh, because the whole point is that instances in exactly this shape exist
#    right now and must never be corrected by simulating them away.
# ---------------------------------------------------------------------------------
LEGACY="$TMP/legacy"; mkdir -p "$LEGACY/projects/retained-example" "$LEGACY/projects/other-project"
bash "$TPL/plugin/scripts/init-bundle.sh" "$LEGACY" >"$TMP/outL1" 2>&1
cat > "$LEGACY/.gitignore" <<'GI'
# LOCAL EDIT: restored 2026-08-23 after an install.sh run reversed it
.DS_Store
*.log

# Derived navigation indexes — the root one and each project's, rewritten by every
# /pm-loop tick from the documents they summarise. A view, not source.
# `knowledge/index.md` is deliberately NOT ignored: it is the KB's curated lookup
# surface, changes only when the KB changes, and a fresh clone needs it present.
/index.md
/projects/*/index.md
!projects/retained-example/index.md

# The local live board page (scripts/watch-board.sh). Derived output.
/.board-live/
GI
cp "$LEGACY/.gitignore" "$TMP/legacy.before"

bash "$TPL/plugin/scripts/init-bundle.sh" "$LEGACY" >"$TMP/outL2" 2>&1
RC=$?
assert "install.sh exits 0 on a legacy (unmarked) instance"  "$([[ $RC -eq 0 ]] && echo 0 || echo 1)"
assert "the legacy block gets migrated to the marker pair"   "$(yes_if grep -qxF '# >>> loopd index ignore >>>' "$LEGACY/.gitignore")"
assert "…comment text is the CURRENT wording, not the old"   "$(yes_if grep -q 'shared by more than one human it would otherwise conflict' "$LEGACY/.gitignore")"
assert "…the stale one-line-shorter old comment is gone"     "$(no_if grep -qxF '# /pm-loop tick from the documents they summarise. A view, not source.' "$LEGACY/.gitignore")"
assert "a local edit BEFORE the block survives byte-for-byte" "$(yes_if grep -qxF '# LOCAL EDIT: restored 2026-08-23 after an install.sh run reversed it' "$LEGACY/.gitignore")"
assert "…and unrelated lines are untouched"                   "$(yes_if grep -qxF '.DS_Store' "$LEGACY/.gitignore")"
assert "a retained project's negation still wins (check-ignore)" "$(no_if git_check_ignore "$LEGACY" projects/retained-example/index.md)"
assert "…while an ordinary project is still ignored"          "$(yes_if git_check_ignore "$LEGACY" projects/other-project/index.md)"
assert "…the derived index is still ignored"                  "$(yes_if git_check_ignore "$LEGACY" "$AB_INDEX")"
assert "…and a bundle stamped before the KB mount ignores its gitdirs" \
  "$(yes_if sh -c 'cd "$1" && git check-ignore -q "$2/kb.git/HEAD" && git check-ignore -q "$2/kb-src/x.git/HEAD"' _ "$LEGACY" "$AB_DIR")"
# Order is the mechanism: the negation line must still appear strictly AFTER the two
# blanket rule lines (i.e. after the block's END marker), not before or inside it.
neg_line="$(head -1 <<<"$(grep -nxF '!projects/retained-example/index.md' "$LEGACY/.gitignore")" | cut -d: -f1)"
end_line="$(head -1 <<<"$(grep -nxF '# <<< loopd index ignore <<<' "$LEGACY/.gitignore")" | cut -d: -f1)"
assert "…and the negation line sits after the block's END marker" \
  "$([[ -n "$neg_line" && -n "$end_line" && "$neg_line" -gt "$end_line" ]] && echo 0 || echo 1)"

# ---------------------------------------------------------------------------------
# 3. THE CLASS OF BUG ITSELF: stamp a fixture TWICE with DIFFERENT template content
#    between the runs, and assert the SECOND stamp actually took — both a changed
#    comment and a new rule line, the two halves the old guard swallowed. A single
#    stamp cannot distinguish "works" from "only ever worked once".
# ---------------------------------------------------------------------------------
INST2="$TMP/inst2"; mkdir -p "$INST2"
bash "$TPL/plugin/scripts/init-bundle.sh" "$INST2" >"$TMP/out2a" 2>&1
before="$(sed -n '/# >>> loopd index ignore >>>/,/# <<< loopd index ignore <<</p' "$INST2/.gitignore")"

# Mutate the TEMPLATE's install.sh between runs — a new comment sentence AND a new
# rule line, the way a future loopd PR would extend this block.
perl -0pi -e "s/surface, changes only when the KB changes, and a fresh clone needs it present\\.\n/surface, changes only when the KB changes, and a fresh clone needs it present.\n# UPDATED WORDING for the second-stamp test.\n/" "$TPL/plugin/scripts/init-bundle.sh"
perl -0pi -e 's{^/projects/\*/index\.md\n(GI\n)}{/projects/*/index.md\n/.a-new-derived-index.json\n$1}m' "$TPL/plugin/scripts/init-bundle.sh"

bash "$TPL/plugin/scripts/init-bundle.sh" "$INST2" >"$TMP/out2b" 2>&1
after="$(sed -n '/# >>> loopd index ignore >>>/,/# <<< loopd index ignore <<</p' "$INST2/.gitignore")"

assert "a second stamp changes the block's content at all"   "$([[ "$before" != "$after" ]] && echo 0 || echo 1)"
assert "…delivers the CHANGED comment text"                   "$(yes_if grep -qxF '# UPDATED WORDING for the second-stamp test.' "$INST2/.gitignore")"
assert "…delivers the NEW rule line"                           "$(yes_if grep -qxF '/.a-new-derived-index.json' "$INST2/.gitignore")"
assert "…and the new line is actually ignored, not just present" \
  "$(yes_if git_check_ignore "$INST2" .a-new-derived-index.json)"
assert "…a THIRD stamp with no template change is a no-op on this block" \
  "$(bash "$TPL/plugin/scripts/init-bundle.sh" "$INST2" >"$TMP/out2c" 2>&1; cmp -s <(sed -n '/# >>> loopd index ignore >>>/,/# <<< loopd index ignore <<</p' "$INST2/.gitignore") <(printf '%s\n' "$after") && echo 0 || echo 1)"

# ---------------------------------------------------------------------------------
# 4. A line that merely RESEMBLES the marker must not be mistaken for it (would
#    otherwise make the outer `grep` gate report "already migrated" via a substring
#    match, silently skipping the block on an instance that was never actually
#    migrated) — and must not itself be corrupted.
# ---------------------------------------------------------------------------------
INST3="$TMP/inst3"; mkdir -p "$INST3/projects/demo"
bash "$TPL/plugin/scripts/init-bundle.sh" "$INST3" >"$TMP/out3a" 2>&1
# Strip the real block back out (so the file has NO real marker pair)…
awk '/# >>> loopd index ignore >>>/{skip=1} /# <<< loopd index ignore <<</{skip=0; next} !skip' \
  "$INST3/.gitignore" > "$INST3/.gitignore.tmp" && mv "$INST3/.gitignore.tmp" "$INST3/.gitignore"
printf '\n/index.md\n/projects/*/index.md\n' >> "$INST3/.gitignore"
# …and add a DECOY line that contains the exact marker text as a mere substring —
# not a real marker, just prose about it.
printf '# a note that mentions "# >>> loopd index ignore >>>" for documentation, not a real marker\n' >> "$INST3/.gitignore"
cp "$INST3/.gitignore" "$TMP/inst3.before"

bash "$TPL/plugin/scripts/init-bundle.sh" "$INST3" >"$TMP/out3b" 2>&1
assert "a decoy resembling the marker does not block migration" \
  "$(yes_if grep -qxF '# >>> loopd index ignore >>>' "$INST3/.gitignore")"
assert "…the derived index is ignored after migrating past the decoy" \
  "$(yes_if git_check_ignore "$INST3" "$AB_INDEX")"
assert "…the decoy line itself survives untouched"  \
  "$(yes_if grep -qF 'a note that mentions' "$INST3/.gitignore")"

# ---------------------------------------------------------------------------------
# 5. NON-GREEDY pairing: a stray, exact copy of the END marker text sitting further
#    down the file (e.g. quoted in an unrelated comment) must close the block at the
#    FIRST end marker, not swallow everything up to whichever one comes last.
# ---------------------------------------------------------------------------------
INST4="$TMP/inst4"; mkdir -p "$INST4"
bash "$TPL/plugin/scripts/init-bundle.sh" "$INST4" >"$TMP/out4a" 2>&1
{
  printf '\n# a later, unrelated section quoting the same text a second time:\n'
  printf '# <<< loopd index ignore <<<\n'
  printf '# — should stay right here, untouched, and not re-open or re-close anything.\n'
} >> "$INST4/.gitignore"
cp "$INST4/.gitignore" "$TMP/inst4.before"

bash "$TPL/plugin/scripts/init-bundle.sh" "$INST4" >"$TMP/out4b" 2>&1
between_markers="$(head -1 <<<"$(sed -n '/# >>> loopd index ignore >>>/,/# <<< loopd index ignore <<</p' "$INST4/.gitignore")")"
assert "the block still closes at its OWN (first) END marker" \
  "$([[ -n "$between_markers" ]] && echo 0 || echo 1)"
assert "…exactly ONE real block, not content swallowed to the stray END" \
  "$([[ "$(grep -cxF '# >>> loopd index ignore >>>' "$INST4/.gitignore")" -eq 1 ]] && echo 0 || echo 1)"
# An exact END line outside every block is an ORPHAN, and the rewrite drops it alone: it
# carries no rule, and kept it is a marker a later BEGIN could pair with by accident.
assert "…the orphan END further down is dropped, the block's own kept" \
  "$([[ "$(grep -cxF '# <<< loopd index ignore <<<' "$INST4/.gitignore")" -eq 1 ]] && echo 0 || echo 1)"
assert "…the line after the orphan END survives untouched" \
  "$(yes_if grep -qxF '# — should stay right here, untouched, and not re-open or re-close anything.' "$INST4/.gitignore")"
assert "…and the unrelated comment line above it survives untouched" \
  "$(yes_if grep -qxF '# a later, unrelated section quoting the same text a second time:' "$INST4/.gitignore")"

# ---------------------------------------------------------------------------------
# 6. BEGIN without a matching END must NOT be rewritten — CodeRabbit round 1 on #51.
#    The old code gated the "already migrated" branch on BEGIN's presence alone; the
#    awk's `!inblock { print }` only resumes once it sees an EXACT END line, so a file
#    with BEGIN and no END (an interrupted stamp, or a hand-edit that dropped the END
#    line) had every line after BEGIN silently dropped by the rewrite, and `mv` wrote
#    that truncated file back over the real one. Assert byte-for-byte NO CHANGE and
#    that the run reports the problem.
# ---------------------------------------------------------------------------------
INST5="$TMP/inst5"; mkdir -p "$INST5"
bash "$TPL/plugin/scripts/init-bundle.sh" "$INST5" >"$TMP/out5a" 2>&1
# Append a distinctive trailer AFTER the natural stamp — deliberately, so there is real
# content sitting after the block regardless of where a fresh stamp happens to place it
# (a bare "the block was already the last thing in the file" fixture would let a
# truncating implementation pass this test vacuously, the same trap `.claude/rules/
# tests.md` warns about).
printf '\n# TRAILER: unrelated content that must survive a re-stamp untouched.\n/some/trailer/rule\n' >> "$INST5/.gitignore"
# Drop the END marker line, leaving BEGIN, the trailer, and everything else intact but
# unclosed.
awk '$0 == "# <<< loopd index ignore <<<" { next } { print }' "$INST5/.gitignore" \
  > "$INST5/.gitignore.tmp" && mv "$INST5/.gitignore.tmp" "$INST5/.gitignore"
cp "$INST5/.gitignore" "$TMP/inst5.before"
assert "the fixture really has BEGIN with no END (sanity check on the fixture itself)" \
  "$([[ "$(grep -cxF '# >>> loopd index ignore >>>' "$INST5/.gitignore")" -eq 1 \
     && "$(grep -cxF '# <<< loopd index ignore <<<' "$INST5/.gitignore")" -eq 0 ]] && echo 0 || echo 1)"
assert "…and the trailer really does sit AFTER the dangling BEGIN (sanity check)" \
  "$([[ "$(grep -nxF '# >>> loopd index ignore >>>' "$INST5/.gitignore" | cut -d: -f1)" \
        -lt "$(grep -nxF '/some/trailer/rule' "$INST5/.gitignore" | cut -d: -f1)" ]] && echo 0 || echo 1)"

err5="$(bash "$TPL/plugin/scripts/init-bundle.sh" "$INST5" 2>&1 1>/dev/null)"
rc5=$?
assert "install.sh still exits 0 on a BEGIN-without-END .gitignore" \
  "$([[ $rc5 -eq 0 ]] && echo 0 || echo 1)"
assert "the malformed file is left BYTE-FOR-BYTE unchanged, not truncated" \
  "$(cmp -s "$TMP/inst5.before" "$INST5/.gitignore" && echo 0 || echo 1)"
assert "…the trailer AFTER the dangling BEGIN specifically survives" \
  "$(yes_if grep -qxF '/some/trailer/rule' "$INST5/.gitignore")"
assert "…and the run reports the malformed marker pair" \
  "$(grep -qi 'no.*matching END marker\|END marker' <<<"$err5" && echo 0 || echo 1)"

# ---------------------------------------------------------------------------------
# 7. An EARLIER, unrelated standalone `/index.md` line must not steal the adjacency
#    match — CodeRabbit round 1 on #51. The old code used only the FIRST exact `/index.md`
#    line in the file (`grep -nxF` + `head -1`); if THAT one wasn't followed by
#    `/projects/*/index.md`, it fell through to the fresh-instance append path and
#    appended the blanket block at EOF — AFTER an existing retained-project negation,
#    silently reversing task-008's criterion 4. Note the decoy must be an EXACT,
#    standalone `/index.md` line (not merely a path ending in `index.md`, which `-x`
#    would never match in the first place) to actually exercise this — confirmed by
#    replaying this exact fixture against the pre-fix install.sh, where it reproduces
#    the bug. Assert with `git check-ignore`, not by grepping for the pattern.
# ---------------------------------------------------------------------------------
INST6="$TMP/inst6"; mkdir -p "$INST6/projects/retained-example" "$INST6/projects/other-project"
bash "$TPL/plugin/scripts/init-bundle.sh" "$INST6" >"$TMP/out6a" 2>&1
cat > "$INST6/.gitignore" <<'GI'
.DS_Store

# A hand-written, unrelated /index.md rule some human added earlier in the file for
# their own reasons — an EXACT duplicate of the real rule's text, but not adjacent to
# /projects/*/index.md, so it must not be the one the adjacency scan latches onto.
/index.md

# Derived navigation indexes — the root one and each project's, rewritten by every
# /pm-loop tick from the documents they summarise. A view, not source.
/index.md
/projects/*/index.md
!projects/retained-example/index.md

# The local live board page (scripts/watch-board.sh). Derived output.
/.board-live/
GI

bash "$TPL/plugin/scripts/init-bundle.sh" "$INST6" >"$TMP/out6b" 2>&1
assert "install.sh exits 0 with an earlier unrelated /index.md line present" \
  "$([[ $? -eq 0 ]] && echo 0 || echo 1)"
assert "the REAL index-ignore pair is migrated to the marker pair (not the decoy)" \
  "$(yes_if grep -qxF '# >>> loopd index ignore >>>' "$INST6/.gitignore")"
# ONE since the block's own rule line is `/.loopd/index.md`: the decoy is the only
# `/index.md` left, which is exactly the line that had to survive.
assert "the earlier unrelated /index.md rule is untouched" \
  "$([[ "$(grep -cxF '/index.md' "$INST6/.gitignore")" -eq 1 ]] && echo 0 || echo 1)"
assert "…exactly ONE index-ignore block was created, not a duplicate at EOF" \
  "$([[ "$(grep -cxF '# >>> loopd index ignore >>>' "$INST6/.gitignore")" -eq 1 ]] && echo 0 || echo 1)"
assert "a retained project's negation still wins (check-ignore) despite the decoy" \
  "$(no_if git_check_ignore "$INST6" projects/retained-example/index.md)"
assert "…an ordinary project is still ignored" \
  "$(yes_if git_check_ignore "$INST6" projects/other-project/index.md)"
assert "…root index.md is still ignored" \
  "$(yes_if git_check_ignore "$INST6" index.md)"
neg_line6="$(head -1 <<<"$(grep -nxF '!projects/retained-example/index.md' "$INST6/.gitignore")" | cut -d: -f1)"
end_line6="$(head -1 <<<"$(grep -nxF '# <<< loopd index ignore <<<' "$INST6/.gitignore")" | cut -d: -f1)"
assert "…and the negation still sits after the block's END marker" \
  "$([[ -n "$neg_line6" && -n "$end_line6" && "$neg_line6" -gt "$end_line6" ]] && echo 0 || echo 1)"

# ---------------------------------------------------------------------------------
# 8. THE OLD-BRAND PAIR IS RENAMED IN PLACE, ONCE. Every bundle stamped before the rename
#    sweep carries `# >>> ai-bridge index ignore >>>` / `# <<< ai-bridge index ignore <<<`.
#    A re-stamp must leave exactly one `loopd` pair where the old one was — no second block
#    appended, the negation after it still winning — and the run after that must not
#    change a byte. Three shapes measured on real bundles: the plain old pair, the old
#    pair followed by an orphan loopd END (migrate-bundle.sh's comment rewrite and a stamp
#    between them left one), and an old block beside a loopd one.
# ---------------------------------------------------------------------------------
OLD_B='# >>> ai-bridge index ignore >>>'; OLD_E='# <<< ai-bridge index ignore <<<'
NEW_B='# >>> loopd index ignore >>>';     NEW_E='# <<< loopd index ignore <<<'
cnt() { grep -cxF -- "$1" "$2" | tr -d ' '; }
pair_counts() { printf '%s/%s/%s/%s' "$(cnt "$OLD_B" "$1")" "$(cnt "$OLD_E" "$1")" "$(cnt "$NEW_B" "$1")" "$(cnt "$NEW_E" "$1")"; }
to_old() { # <file> — the fixture: the stamped pair spelled the pre-rename way
  awk -v nb="$NEW_B" -v ne="$NEW_E" -v ob="$OLD_B" -v oe="$OLD_E" \
    '$0==nb {print ob; next} $0==ne {print oe; next} {print}' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

INST8="$TMP/inst8"; mkdir -p "$INST8/projects/kept" "$INST8/projects/other"
bash "$TPL/plugin/scripts/init-bundle.sh" "$INST8" >"$TMP/out8a" 2>&1
to_old "$INST8/.gitignore"
awk -v e="$OLD_E" '{print} $0==e {print "!projects/kept/index.md"}' "$INST8/.gitignore" > "$INST8/.gitignore.tmp" \
  && mv "$INST8/.gitignore.tmp" "$INST8/.gitignore"
assert "8a fixture: one old pair, no loopd pair" "$([[ "$(pair_counts "$INST8/.gitignore")" == 1/1/0/0 ]] && echo 0 || echo 1)"
old_at="$(grep -nxF "$OLD_B" "$INST8/.gitignore" | cut -d: -f1)"
bash "$TPL/plugin/scripts/init-bundle.sh" "$INST8" >"$TMP/out8b" 2>&1
assert "8a the old pair becomes exactly one loopd pair" "$([[ "$(pair_counts "$INST8/.gitignore")" == 0/0/1/1 ]] && echo 0 || echo 1)"
assert "…on the line the old BEGIN held — renamed in place, not appended" \
  "$([[ "$(grep -nxF "$NEW_B" "$INST8/.gitignore" | cut -d: -f1)" == "$old_at" ]] && echo 0 || echo 1)"
assert "…and the run says it renamed the pair"  "$(yes_if grep -q 'renamed the index-ignore marker pair' "$TMP/out8b")"
assert "…a negation after the old END still wins" "$(no_if git_check_ignore "$INST8" projects/kept/index.md)"
assert "…while an ordinary project is still ignored" "$(yes_if git_check_ignore "$INST8" projects/other/index.md)"
cp "$INST8/.gitignore" "$TMP/inst8.after1"
bash "$TPL/plugin/scripts/init-bundle.sh" "$INST8" >"$TMP/out8c" 2>&1
assert "…and a second stamp changes not a byte" "$(cmp -s "$TMP/inst8.after1" "$INST8/.gitignore" && echo 0 || echo 1)"
assert "…nor claims to rename anything"         "$(no_if grep -q 'renamed the index-ignore marker pair' "$TMP/out8c")"

INST9="$TMP/inst9"; mkdir -p "$INST9"
bash "$TPL/plugin/scripts/init-bundle.sh" "$INST9" >"$TMP/out9a" 2>&1
to_old "$INST9/.gitignore"
awk -v e="$OLD_E" -v ne="$NEW_E" '{print} $0==e {print ne}' "$INST9/.gitignore" > "$INST9/.gitignore.tmp" \
  && mv "$INST9/.gitignore.tmp" "$INST9/.gitignore"
assert "8b fixture: the old pair plus an orphan loopd END" "$([[ "$(pair_counts "$INST9/.gitignore")" == 1/1/0/1 ]] && echo 0 || echo 1)"
bash "$TPL/plugin/scripts/init-bundle.sh" "$INST9" >"$TMP/out9b" 2>&1
assert "8b one loopd pair, the orphan gone"      "$([[ "$(pair_counts "$INST9/.gitignore")" == 0/0/1/1 ]] && echo 0 || echo 1)"
assert "…and the derived index is still ignored" "$(yes_if git_check_ignore "$INST9" "$AB_INDEX")"
cp "$INST9/.gitignore" "$TMP/inst9.after1"
bash "$TPL/plugin/scripts/init-bundle.sh" "$INST9" >"$TMP/out9c" 2>&1
assert "…and a second stamp changes not a byte"  "$(cmp -s "$TMP/inst9.after1" "$INST9/.gitignore" && echo 0 || echo 1)"

INST10="$TMP/inst10"; mkdir -p "$INST10"
bash "$TPL/plugin/scripts/init-bundle.sh" "$INST10" >"$TMP/out10a" 2>&1
sed -n "/^$NEW_B\$/,/^$NEW_E\$/p" "$INST10/.gitignore" > "$TMP/block10"
to_old "$INST10/.gitignore"
{ printf '
# a hand-ported copy, already spelled the new way
'; cat "$TMP/block10"; printf '/after/the/copy
'; } >> "$INST10/.gitignore"
assert "8c fixture: an old block AND a loopd block" "$([[ "$(pair_counts "$INST10/.gitignore")" == 1/1/1/1 ]] && echo 0 || echo 1)"
bash "$TPL/plugin/scripts/init-bundle.sh" "$INST10" >"$TMP/out10b" 2>&1
assert "8c the two collapse to one loopd block"  "$([[ "$(pair_counts "$INST10/.gitignore")" == 0/0/1/1 ]] && echo 0 || echo 1)"
assert "…and only the duplicate went: the line after it stays" "$(yes_if grep -qxF '/after/the/copy' "$INST10/.gitignore")"
cp "$INST10/.gitignore" "$TMP/inst10.after1"
bash "$TPL/plugin/scripts/init-bundle.sh" "$INST10" >"$TMP/out10c" 2>&1
assert "…and a second stamp changes not a byte"  "$(cmp -s "$TMP/inst10.after1" "$INST10/.gitignore" && echo 0 || echo 1)"

INST11="$TMP/inst11"; mkdir -p "$INST11"
bash "$TPL/plugin/scripts/init-bundle.sh" "$INST11" >"$TMP/out11a" 2>&1
awk -v nb="$NEW_B" '$0!=nb' "$INST11/.gitignore" > "$INST11/.gitignore.tmp" && mv "$INST11/.gitignore.tmp" "$INST11/.gitignore"
assert "8d fixture: a loopd END with no BEGIN anywhere" "$([[ "$(pair_counts "$INST11/.gitignore")" == 0/0/0/1 ]] && echo 0 || echo 1)"
bash "$TPL/plugin/scripts/init-bundle.sh" "$INST11" >"$TMP/out11b" 2>&1
assert "8d the orphan END is not paired by accident: one well-formed block" \
  "$([[ "$(pair_counts "$INST11/.gitignore")" == 0/0/1/1 \
        && "$(grep -nxF "$NEW_B" "$INST11/.gitignore" | cut -d: -f1)" -lt "$(grep -nxF "$NEW_E" "$INST11/.gitignore" | cut -d: -f1)" ]] && echo 0 || echo 1)"
cp "$INST11/.gitignore" "$TMP/inst11.after1"
bash "$TPL/plugin/scripts/init-bundle.sh" "$INST11" >"$TMP/out11c" 2>&1
assert "…and a second stamp changes not a byte"  "$(cmp -s "$TMP/inst11.after1" "$INST11/.gitignore" && echo 0 || echo 1)"

# 8e. AN OLD BEGIN THE RENAME REFUSES is said out loud, like a dangling loopd BEGIN: a
#     stray beside a complete loopd pair stays where it is, and every stamp warns.
INST12="$TMP/inst12"; mkdir -p "$INST12"
bash "$TPL/plugin/scripts/init-bundle.sh" "$INST12" >"$TMP/out12a" 2>&1
printf '\n%s\n' "$OLD_B" >> "$INST12/.gitignore"; cp "$INST12/.gitignore" "$TMP/inst12.before"
err12="$(bash "$TPL/plugin/scripts/init-bundle.sh" "$INST12" 2>&1 1>/dev/null)"
assert "8e a stray old BEGIN beside a loopd pair is warned about" \
  "$(grep -q 'old-spelling index-ignore marker' <<<"$err12" && echo 0 || echo 1)"
assert "…and left exactly as found"            "$(cmp -s "$TMP/inst12.before" "$INST12/.gitignore" && echo 0 || echo 1)"

# 8f. An old BEGIN with NO END above the two rule lines is absorbed by the legacy splice —
#     one loopd pair, nothing left to warn about.
INST13="$TMP/inst13"; mkdir -p "$INST13"
bash "$TPL/plugin/scripts/init-bundle.sh" "$INST13" >"$TMP/out13a" 2>&1
to_old "$INST13/.gitignore"
awk -v oe="$OLD_E" '$0!=oe' "$INST13/.gitignore" > "$INST13/.gitignore.tmp" && mv "$INST13/.gitignore.tmp" "$INST13/.gitignore"
err13="$(bash "$TPL/plugin/scripts/init-bundle.sh" "$INST13" 2>&1 1>/dev/null)"
assert "8f a dangling old BEGIN becomes one loopd pair" "$([[ "$(pair_counts "$INST13/.gitignore")" == 0/0/1/1 ]] && echo 0 || echo 1)"
assert "…with no warning, since nothing was left behind" \
  "$(grep -q 'old-spelling index-ignore marker' <<<"$err13" && echo 1 || echo 0)"

echo "index-ignore-restamp.test.sh: pass=$pass fail=$fail"
[[ $fail -eq 0 ]]
