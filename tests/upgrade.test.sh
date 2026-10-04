#!/usr/bin/env bash
#
# Exercises refresh-seeds.sh — what `upgrade.sh` became when the bundle stopped carrying
# machinery (ai-bridge-v2/task-013). Three of its four stages went with that design:
# stage 1 was `install.sh`'s symlink pass, and stages 2 and 3 ran the bundle's own
# `validate-bundle.sh` and `migrate-bundle.sh` through symlinks that no longer exist (both
# ship in the plugin and are reachable directly, and `/<plugin>:welcome check` is the one
# command that surveys a bundle). What was left is the stage nothing else can do: the
# 3-way seed merge, reachable as `/<plugin>:welcome fix` and `/<plugin>:init
# --refresh-seeds`.
#
# The properties that matter are the negative ones, in this order:
#   · a default run writes NOTHING (the whole instance is checksummed before and after,
#     symlink targets included) — it only reports;
#   · a HAND-DIVERGED seed file is reported as a conflict and left byte-identical, in
#     report mode AND under --apply. An instance's edits are the only copy of a decision
#     somebody made, and no merge this script can compute is worth losing them;
#   · a claimed port is verified on disk, so PORTED can never be printed for a write that
#     did not land (the bug migrate-bundle.sh once shipped);
#   · a non-instance directory is refused, non-zero, rather than stamped;
#   · run from an INSTALLED plugin — a cache copy with no `.git`, which is where people
#     actually run it — a merge base is still found, and the run SAYS which source gave
#     it: the marketplace clone, else the bundle's stamped-seed record, else UNKNOWN. Each
#     is proved by taking the source away and watching the same run go back to UNKNOWN;
#   · a SHALLOW marketplace clone is deepened, or reported and refused the one inference
#     it cannot support ("this seed never changed"), which is the quiet failure again.
#
# The `log.md` and `CLAUDE.md` cases together are a regression test, not decoration: the seed
# file's CURRENT blob is in its git history too, and while it was allowed as a merge-base
# candidate it was often the blob closest to what an instance holds — making the merge a
# no-op and reporting a genuinely hand-diverged file as "nothing to port". `log.md` must stay
# silent (its seed never changed) while `CLAUDE.md` must conflict (its seed did).
#
# The fixture builds its own template in a temp git repo — including its own controlled
# `seed/` content, so these assertions do not move when the real seed files are edited —
# stamps an instance from seed v1, hand-diverges one file, then commits seed v2. That is
# exactly the shape of the problem: the instance's copy is frozen at v1, and only git
# history knows whether v1 is what it still has.
#
# assert() follows the convention of the other harnesses here: 0 is a PASS.
set -euo pipefail

# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$(dirname "$0")/../plugin/scripts/bundle-paths.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$(dirname "$0")/tools/plugin-name.sh"
TPL_SRC="$HERE/.."
[[ -f "$TPL_SRC/plugin/scripts/refresh-seeds.sh" ]] || { echo "upgrade.test: not found at $TPL_SRC/plugin/scripts/refresh-seeds.sh" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/upgrade-fixture.XXXXXX")" || {
  echo "upgrade.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
assert() { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
yes_if() { if "$@" >/dev/null 2>&1; then echo 0; else echo 1; fi; }
has()    { grep -q <<<"$2" -- "$1" && echo 0 || echo 1; }
hasnt()  { grep -q <<<"$2" -- "$1" && echo 1 || echo 0; }

# Everything in the instance that a mutation could touch: file contents AND symlink
# targets. .git is excluded — reading history legitimately touches git's own bookkeeping.
snapshot() {
  ( cd "$1" && find . -not -path './.git/*' \( -type f -o -type l \) | sort | while IFS= read -r f; do
      if [[ -L "$f" ]]; then printf 'L %s -> %s\n' "$f" "$(readlink "$f")"
      else printf 'F %s %s\n' "$f" "$(shasum "$f" | awk '{print $1}')"; fi
    done )
}

gc() { git -c user.email=a@b -c user.name=a commit -qm "$1"; }

# ---------------------------------------------------------------- the template, seed v1
TPL="$TMP/tpl"
mkdir -p "$TPL"
mkdir -p "$TPL/plugin/scripts"
cp -R "$TPL_SRC/plugin/scripts/init-bundle.sh" "$TPL_SRC/plugin/scripts/refresh-seeds.sh" \
      "$TPL_SRC/plugin/scripts/validate-bundle.sh" "$TPL_SRC/plugin/scripts/bundle-paths.sh" \
      "$TPL/plugin/scripts/"
cp -R "$TPL_SRC/plugin/seed" "$TPL/plugin/seed"
# VERSION lives INSIDE plugin/ for the root derivation; the root copy is the mirror the
# repo keeps for its docs and for check-template-version.sh.
cp "$TPL_SRC/VERSION" "$TPL/plugin/VERSION"
cp "$TPL_SRC/VERSION" "$TPL/VERSION"

# Controlled seed content, so the assertions below describe this test's edits rather than
# whatever the real seed files happen to say today.
printf '# Index\nline A\nline B\nline C\nline D\n' > "$TPL/plugin/seed/index.md"
printf '# Todos\nt1\nt2\nt3\nt4\nt5\nt6\nt7\nt8\n'  > "$TPL/plugin/seed/todos.md"
printf '# Panel\nintro line\ntail line\n'           > "$TPL/plugin/seed/CLAUDE.md"
printf '# Log\n'                                    > "$TPL/plugin/seed/log.md"
# No `# Instance additions` heading in seed v1 — that is a bundle stamped before the slot
# existed, so the stamp has to create it (2x/task-008).
printf 'node_modules/\ntmp/\n'                     > "$TPL/plugin/seed/.gitignore"
( cd "$TPL" && git init -q -b main . && git add -A && gc "template, seed v1" )

# Every run below goes through the FIXTURE's copy of the script: `upgrade.sh` derives its
# template — and therefore the seed/ and the git history it judges drift against — from
# its OWN location. Running the repo's copy against the fixture instance silently compares
# it to the real seed files, which is how the first version of this harness lied.
UPGRADE="$TPL/plugin/scripts/refresh-seeds.sh"

# ---------------------------------------------------------------- an instance, stamped
INST="$TMP/group/_ai-bridge-fixture"
mkdir -p "$INST"
bash "$TPL/plugin/scripts/init-bundle.sh" "$INST" > "$TMP/install1.out" 2>&1

# Documents for steps 2 and 3: one mechanical repair, one that needs a human.
mkdir -p "$INST/knowledge/findings"
printf -- '---\ntype: Finding\ntitle: F1\nstatus: open\ntimestamp: 2026-01-01T00:00:00Z\n---\nbody\n' \
  > "$INST/knowledge/findings/mechanical.md"
printf -- '---\ntype: Finding\ntitle: F2\nstatus: wibble\ntimestamp: 2026-01-01T00:00:00Z\n---\nbody\n' \
  > "$INST/knowledge/findings/needs-human.md"
( cd "$INST" && git init -q -b main . && git add -A && gc "instance init" )

# The instance's own edits, three shapes:
#   CLAUDE.md — the SAME line the seed is about to change  ⇒ must conflict
#   todos.md  — a line far from the seed's change          ⇒ must merge cleanly
#   log.md    — grown past a seed the template never edits ⇒ nothing to port, stay quiet
#   index.md  — untouched, i.e. the seed verbatim          ⇒ portable exactly
sed 's/^intro line$/intro line — HOUSE EDIT/' "$INST/CLAUDE.md" > "$TMP/c" && mv "$TMP/c" "$INST/CLAUDE.md"
printf 'INSTANCE TODO\n' >> "$INST/todos.md"
printf 'an entry the instance wrote\n' >> "$INST/$AB_LEDGER"
# And the config, which every bundle edits: it must be REPORTED and never merged.
printf '{\n  "org": "this-group"\n}\n' > "$INST/instance.config.json"
cp "$INST/instance.config.json" "$TMP/config.pristine"
cp "$INST/CLAUDE.md" "$TMP/claude.pristine"

# ---------------------------------------------------------------- the template, seed v2
printf 'line E (new in seed v2)\n' >> "$TPL/plugin/seed/index.md"
sed 's/^# Todos$/# Todos\nTOP LINE FROM SEED V2/' "$TPL/plugin/seed/todos.md" > "$TMP/t" && mv "$TMP/t" "$TPL/plugin/seed/todos.md"
sed 's/^intro line$/intro line — TEMPLATE V2/'    "$TPL/plugin/seed/CLAUDE.md" > "$TMP/c" && mv "$TMP/c" "$TPL/plugin/seed/CLAUDE.md"
( cd "$TPL" && git add -A && gc "template, seed v2" )

echo "== refusing anything that is not an instance root =="
mkdir -p "$TMP/stranger"
set +e; bash "$UPGRADE" "$TMP/stranger" > "$TMP/refuse.out" 2>&1; RC=$?; set -e
assert "exits 2 on a directory that is not an instance" "$([[ $RC -eq 2 ]] && echo 0 || echo 1)"
assert "says what it expected to find"    "$(has 'instance.config.json' "$(cat "$TMP/refuse.out")")"
assert "points at /${PN}:init for a NEW bundle" "$(has ''"${PN}:"'init' "$(cat "$TMP/refuse.out")")"
assert "it did not stamp the stranger"    "$(yes_if test ! -e "$TMP/stranger/$AB_SCHEMA")"
set +e; bash "$UPGRADE" "$TMP/no-such-dir" >/dev/null 2>&1; RC=$?; set -e
assert "exits 2 on a directory that does not exist" "$([[ $RC -eq 2 ]] && echo 0 || echo 1)"

echo "== a default run reports, and writes nothing =="
# NOTHING TO SETTLE ANY MORE. The first run used to link machinery (install.sh's documented
# job ran as stage 1), so the no-write property could only be measured from the second run
# on. This script writes nothing on ANY run without --apply, so the snapshot is taken cold.
BEFORE="$(snapshot "$INST")"
REPORT="$(bash "$UPGRADE" "$INST" 2>&1)"
AFTER="$(snapshot "$INST")"
assert "no file or symlink in the instance changed" "$([[ "$BEFORE" == "$AFTER" ]] && echo 0 || echo 1)"
assert "the mode is stated as report only"  "$(has 'REPORT ONLY' "$REPORT")"
assert "it says nothing was written"        "$(has 'report only — nothing was written' "$REPORT")"
assert "…and the mode line says so too"    "$(has 'REPORT ONLY — nothing is written' "$REPORT")"
assert "no PORTED label in report mode"     "$(hasnt 'PORTED' "$REPORT")"
assert "the schema migration is NOT run from here any more" "$(hasnt 'WOULD FIX' "$REPORT")"
assert "…so a document needing repair is untouched on disk" \
  "$(yes_if grep -q '^status: open' "$INST/knowledge/findings/mechanical.md")"

echo "== each seed file is classified on evidence, not on guesswork =="
assert "an untouched seed copy is PORTABLE"         "$(has 'PORTABLE  index.md' "$REPORT")"
assert "…and says it is the seed verbatim"          "$(has 'seed verbatim' "$REPORT")"
assert "a hand edit far from the seed's is PORTABLE" "$(has 'PORTABLE  todos.md' "$REPORT")"
assert "…and says it merges onto the instance's edits" "$(has 'merges cleanly onto' "$REPORT")"
assert "an edit to the same line is a CONFLICT"     "$(has 'CONFLICT  CLAUDE.md' "$REPORT")"
assert "the conflict prints the seed's diff"        "$(has 'TEMPLATE V2' "$REPORT")"
assert "…and hands it to the human"                 "$(has 'port it by hand' "$REPORT")"
assert "a seed the template never edited is silent"  "$(hasnt 'log.md' "$REPORT")"
assert "a file identical to the seed is silent"      "$(hasnt 'README.md' "$REPORT")"
assert "the per-instance workspace file is never treated as drift" \
  "$(hasnt 'code-workspace' "$REPORT")"
assert "the numbered next-steps list offers --apply" "$(has -- '--apply' "$REPORT")"
assert "…and names the conflict as the human's work" "$(has 'port the seed change into CLAUDE.md' "$REPORT")"
# CONFIG IS NEVER MERGED — a ship-blocker, not an omission. `instance.config.json` is the
# one seed file whose purpose is to diverge, and `/<plugin>:welcome` already refuses to
# repair an uncommitted config for exactly that reason; a merge here would be the same
# write arriving by another door.
assert "instance.config.json is reported, never merged" "$(has 'CONFIG    instance.config.json' "$REPORT")"
assert "…and is never PORTABLE"                      "$(hasnt 'PORTABLE  instance.config.json' "$REPORT")"

echo "== --apply writes the safe changes, and only those =="
APPLY_RC=0
APPLY="$(bash "$UPGRADE" "$INST" --apply 2>&1)" || APPLY_RC=$?
assert "--apply exits 0 when every write landed" "$([[ $APPLY_RC -eq 0 ]] && echo 0 || echo 1)"
assert "the mode is stated as apply"      "$(has 'mode:     APPLY' "$APPLY")"
assert "index.md is reported PORTED"      "$(has 'PORTED    index.md' "$APPLY")"
assert "index.md is now byte-identical to the current seed" \
  "$(yes_if cmp -s "$TPL/plugin/seed/index.md" "$INST/$AB_INDEX")"
assert "todos.md is reported PORTED"      "$(has 'PORTED    todos.md' "$APPLY")"
assert "todos.md gained the seed's new line"  "$(yes_if grep -q '^TOP LINE FROM SEED V2$' "$INST/todos.md")"
assert "todos.md KEPT the instance's own line" "$(yes_if grep -q '^INSTANCE TODO$' "$INST/todos.md")"
# EVERY COPY THIS SCRIPT KEEPS GOES UNDER .ai-bridge/refresh/, never beside the file:
# a `.bak` in the bundle tree is one more thing the human has to notice and delete, and
# one carrying conflict markers is worse.
assert "a merged file's old copy is kept under .ai-bridge/refresh/" \
  "$(yes_if sh -c 'ls "$1"/todos.md.* >/dev/null 2>&1' _ "$INST/.ai-bridge/refresh")"
assert "a verbatim-seed file needs no copy kept" \
  "$(sh -c 'ls "$1"/index.md.* >/dev/null 2>&1' _ "$INST/.ai-bridge/refresh" && echo 1 || echo 0)"
assert "the conflicted merge is kept there too" \
  "$(yes_if sh -c 'ls "$1"/CLAUDE.md.* >/dev/null 2>&1' _ "$INST/.ai-bridge/refresh")"
assert "…and it carries the conflict markers" \
  "$(yes_if sh -c 'grep -qE "^(<<<<<<< |>>>>>>> )" "$1"/CLAUDE.md.*' _ "$INST/.ai-bridge/refresh")"
assert "…and no .bak file was written into the bundle tree at all" \
  "$(grep -q . <<<"$(find "$INST" -name '*.bak.*' -not -path '*/.ai-bridge/*')" && echo 1 || echo 0)"
assert "the report names the path it kept the conflicted merge at" \
  "$(has '.ai-bridge/refresh/CLAUDE.md' "$APPLY")"
assert "instance.config.json was NOT written"        "$(hasnt 'PORTED    instance.config.json' "$APPLY")"
assert "…and is byte-identical after --apply"        "$(yes_if cmp -s "$TMP/config.pristine" "$INST/instance.config.json")"

echo "== a hand-diverged file is never resolved by force =="
assert "CLAUDE.md is still reported CONFLICT under --apply" "$(has 'CONFLICT  CLAUDE.md' "$APPLY")"
assert "CLAUDE.md is byte-identical to before the run" \
  "$(yes_if cmp -s "$TMP/claude.pristine" "$INST/CLAUDE.md")"
assert "no conflict markers were written into it" \
  "$(grep -qE '^(<<<<<<< |>>>>>>> )' "$INST/CLAUDE.md" && echo 1 || echo 0)"
assert "the instance's own wording survived"  "$(yes_if grep -q 'HOUSE EDIT' "$INST/CLAUDE.md")"
assert "no PORTED label was printed for it" \
  "$(grep -q 'PORTED' <<<"$(printf '%s\n' "$APPLY" | grep -B2 'CLAUDE.md')" && echo 1 || echo 0)"
assert "it is still listed as work for the human" "$(has 'port the seed change into CLAUDE.md' "$APPLY")"
assert "no temp file was left behind" \
  "$(grep -q . <<<"$(find "$INST" -name '.upgrade.*')" && echo 1 || echo 0)"

echo "== idempotence =="
SECOND="$(bash "$UPGRADE" "$INST" 2>&1)"
assert "nothing is portable any more"   "$(has '0 portable' "$SECOND")"
assert "nothing was ported"             "$(has '0 ported' "$SECOND")"
BEFORE2="$(snapshot "$INST")"
bash "$UPGRADE" "$INST" >/dev/null 2>&1
assert "a repeated report run still writes nothing" \
  "$([[ "$BEFORE2" == "$(snapshot "$INST")" ]] && echo 0 || echo 1)"
THIRD="$(bash "$UPGRADE" "$INST" --apply 2>&1)"
assert "a repeated --apply writes nothing either" \
  "$([[ "$BEFORE2" == "$(snapshot "$INST")" ]] && echo 0 || echo 1)"
assert "…and reports 0 ported"          "$(has '0 ported' "$THIRD")"
assert "the conflict is still reported, not forgotten" "$(has 'CONFLICT  CLAUDE.md' "$THIRD")"

echo "== a template with no git history falls back to the bundle's stamped-seed record =="
# The bundle carries `.ai-bridge/seed-base/` — what the stamp copied — so a template with
# no history of its own can still judge the drift. Report-only here: the write path is
# covered above, and what is under test is which SOURCE answered.
NOGIT="$TMP/tpl-nogit"
cp -R "$TPL" "$NOGIT" && rm -rf "$NOGIT/.git"
printf 'a further seed change\n' >> "$NOGIT/plugin/seed/index.md"
assert "the stamp recorded what it seeded"  "$(yes_if test -f "$INST/.ai-bridge/seed-base/index.md")"
assert "…and the plugin version it stamped with" \
  "$(yes_if test "$(cat "$INST/.ai-bridge/seed-base/VERSION" 2>/dev/null)" = "$(cat "$TPL/plugin/VERSION")")"
NOGIT_OUT="$(bash "$NOGIT/plugin/scripts/refresh-seeds.sh" "$INST" 2>&1)"
assert "the run names the record as its source" "$(has "history:  this bundle's stamped-seed record" "$NOGIT_OUT")"
assert "…and the drifted file is judged, not UNKNOWN" "$(hasnt 'UNKNOWN   index.md' "$NOGIT_OUT")"
assert "…and the seed change is portable on that base" "$(has 'PORTABLE  index.md' "$NOGIT_OUT")"
assert "…and a report run still wrote nothing"  \
  "$(yes_if cmp -s "$TPL/plugin/seed/index.md" "$INST/$AB_INDEX")"

echo "== no history AND no record: UNKNOWN, naming the fix rather than the symptom =="
NOREC="$TMP/group/_ai-bridge-norecord"
cp -R "$INST" "$NOREC" && rm -rf "$NOREC/$AB_DIR/seed-base" "$NOREC/$AB_DIR/refresh"
NOREC_OUT="$(bash "$NOGIT/plugin/scripts/refresh-seeds.sh" "$NOREC" --apply 2>&1)"
assert "the history line says there is none"   "$(has 'history:  none' "$NOREC_OUT")"
assert "a drifted file with no merge base is UNKNOWN" "$(has 'UNKNOWN   index.md' "$NOREC_OUT")"
assert "…and is not ported"            "$(hasnt 'PORTED    index.md' "$NOREC_OUT")"
assert "…and index.md was not written" \
  "$(yes_if cmp -s "$TPL/plugin/seed/index.md" "$NOREC/$AB_INDEX")"
# Criterion 5: the explanation has to be actionable, not just true.
assert "…and the UNKNOWN names the marketplace clone as a fix" \
  "$(has 'marketplace clone' "$NOREC_OUT")"
assert "…and names the re-stamp that records a base"  "$(has ''"${PN}:"'init' "$NOREC_OUT")"

echo "== the four review findings, as refusals =="

# 1. A directory where a seeded FILE belongs. `-e` is true for it, so the old code fell
#    through to `git hash-object`, whose failure inside an assignment's command
#    substitution aborts the whole run under `set -e` — losing the report for every
#    remaining file. It must classify this one and carry on.
DIRCASE="$TMP/group/_ai-bridge-dircase"
cp -R "$INST" "$DIRCASE"
rm -f "$DIRCASE/$AB_INDEX" && mkdir -p "$DIRCASE/$AB_INDEX/somebody-made-this-a-folder"
DIR_RC=0
DIR_OUT="$(bash "$TPL/plugin/scripts/refresh-seeds.sh" "$DIRCASE" --apply 2>&1)" || DIR_RC=$?
assert "a directory at a seeded path is UNKNOWN" "$(has 'UNKNOWN   index.md' "$DIR_OUT")"
assert "…and is not ported"                      "$(hasnt 'PORTED    index.md' "$DIR_OUT")"
assert "…and the directory is untouched"         "$(yes_if test -d "$DIRCASE/$AB_INDEX/somebody-made-this-a-folder")"
# The whole point of the guard: one odd path must not cost the report for the others.
# These assert on work that happens strictly AFTER the loop reaches index.md: the per-stage
# `summary:` tally is printed once the loop has classified all nine seed files, and
# "what's left for you" is the last thing the script prints. Asserting on CLAUDE.md or on
# the "4/4" stage HEADER would pass either way, since both come first — that weaker pair
# was in the first draft of this block and hid the abort completely.
assert "…and every other file is still counted"  "$(has 'summary: [0-9]* in sync' "$DIR_OUT")"
assert "…and the run reaches its final summary"  "$(has "what.s left for you" "$DIR_OUT")"
assert "…and the run still exits 0"              "$([[ $DIR_RC -eq 0 ]] && echo 0 || echo 1)"

# 2. Report-only used not to be able to claim "nothing changes", because stage 1 was
#    install.sh and it restored an ABSENT seed file by design. That stage is gone, so the
#    claim is now literally true — and it is asserted as such rather than assumed.
REPORT_OUT="$(bash "$TPL/plugin/scripts/refresh-seeds.sh" "$INST" 2>&1)"
assert "report mode states that nothing is written" \
  "$(has 'REPORT ONLY — nothing is written' "$REPORT_OUT")"
# And the claim it DOES make has to hold: a hand-diverged file stays byte-identical.
assert "report mode leaves diverged content alone" \
  "$(yes_if cmp -s "$TMP/claude.pristine" "$INST/CLAUDE.md")"

# 3. AUTONOMY.md is the deletable delegated-autonomy capability. It used to live under
#    `symlink/`, so install.sh re-linked it unconditionally and a per-bundle `rm` was
#    silently undone — fail-OPEN on the capability that lets agents merge without asking,
#    which is why upgrade.sh had to warn about it every run. That hazard is gone with the
#    design: this repo does not seed AUTONOMY.md at all, so a bundle without one stays
#    without one, and the safe state is the default rather than something to defend.
AUT="$TMP/group/_ai-bridge-autonomy"
cp -R "$INST" "$AUT"
rm -f "$AUT/AUTONOMY.md"
bash "$TPL/plugin/scripts/init-bundle.sh" "$AUT" >/dev/null 2>&1
assert "a stamp does NOT restore AUTONOMY.md"   "$(yes_if test ! -e "$AUT/AUTONOMY.md")"
assert "…and the seed ships none to restore"    "$(yes_if test ! -e "$TPL/plugin/seed/AUTONOMY.md")"
AUT_OUT="$(bash "$TPL/plugin/scripts/refresh-seeds.sh" "$AUT" 2>&1)"
assert "…so the refresh has nothing to warn about" "$(hasnt 'AUTONOMY' "$AUT_OUT")"

echo "== the seed PATH MOVED, and the base is still found across the rename =="
# ai-bridge-v2/task-024. #125 did `git mv seed plugin/seed`, and a by-path history lookup
# sees only the commits at the NEW path — which, for a file whose last change was the move
# itself, is one commit whose blob IS the current seed. `prior` then comes back empty, and
# the script reads that as "this seed file has only ever held its current content, so the
# difference is entirely the bundle's own" and stays SILENT. Nothing is reported, nothing
# is wrong on the face of the report, and the seed change simply never reaches a bundle
# stamped before the move — the worst shape a drift report has, because it looks clean.
# So the assertions below are on the VERDICT. The unknown count is asserted too, because
# 0 is what a moved seed must still produce and it is the number the bug was reported as.
MTPL="$TMP/tpl-moved"
mkdir -p "$MTPL/plugin/scripts"
cp -R "$TPL_SRC/plugin/seed" "$MTPL/seed"
cp "$TPL_SRC/plugin/scripts/init-bundle.sh" "$TPL_SRC/plugin/scripts/refresh-seeds.sh" \
   "$TPL_SRC/plugin/scripts/validate-bundle.sh" "$TPL_SRC/plugin/scripts/bundle-paths.sh" \
   "$MTPL/plugin/scripts/"
cp "$TPL_SRC/VERSION" "$MTPL/plugin/VERSION"
cp "$TPL_SRC/VERSION" "$MTPL/VERSION"
printf '# Index\nline A\nline B\n'        > "$MTPL/seed/index.md"
printf '# Panel\nintro line\ntail line\n' > "$MTPL/seed/CLAUDE.md"
( cd "$MTPL" && git init -q -b main . && git add -A && gc "template, seed at seed/ (pre-move)" )

# A bundle stamped from the PRE-MOVE seed. The stamp reads <plugin>/seed, so the seed is
# copied there for the stamp and removed again — the tracked seed is still at seed/, which
# is the state every real bundle was stamped in before #125.
MINST="$TMP/group/_ai-bridge-moved"
mkdir -p "$MINST"
cp -R "$MTPL/seed" "$MTPL/plugin/seed"
bash "$MTPL/plugin/scripts/init-bundle.sh" "$MINST" > "$TMP/moved-stamp.out" 2>&1
rm -rf "$MTPL/plugin/seed"
sed 's/^intro line$/intro line — HOUSE EDIT/' "$MINST/CLAUDE.md" > "$TMP/mc" && mv "$TMP/mc" "$MINST/CLAUDE.md"

# The seed changes, still at the old path…
printf 'line C (new in seed v2)\n' >> "$MTPL/seed/index.md"
sed 's/^intro line$/intro line — TEMPLATE V2/' "$MTPL/seed/CLAUDE.md" > "$TMP/mc" && mv "$TMP/mc" "$MTPL/seed/CLAUDE.md"
( cd "$MTPL" && git add -A && gc "seed v2, still at seed/" )
# …and only THEN moves, so the newest commit at the new path is the rename itself.
( cd "$MTPL" && git mv seed plugin/seed && gc "move seed/ under plugin/ — the #125 shape" )

MOVED="$(bash "$MTPL/plugin/scripts/refresh-seeds.sh" "$MINST" 2>&1)"
assert "a moved seed still reports 0 unknown"  "$(has 'summary: .* 0 unknown' "$MOVED")"
assert "a copy stamped before the move is PORTABLE" "$(has 'PORTABLE  index.md' "$MOVED")"
assert "…on a base found at the OLD path, verbatim" "$(has 'seed verbatim' "$MOVED")"
assert "a hand-diverged copy still CONFLICTS"       "$(has 'CONFLICT  CLAUDE.md' "$MOVED")"
assert "…and the conflict shows the seed change to port" "$(has 'TEMPLATE V2' "$MOVED")"
MAPPLY="$(bash "$MTPL/plugin/scripts/refresh-seeds.sh" "$MINST" --apply 2>&1)"
assert "--apply delivers the pre-move seed change"  "$(has 'PORTED    index.md' "$MAPPLY")"
assert "…so the bundle now matches the moved seed" \
  "$(yes_if cmp -s "$MTPL/plugin/seed/index.md" "$MINST/$AB_INDEX")"
assert "…and the hand-diverged file was not forced" "$(yes_if grep -q 'HOUSE EDIT' "$MINST/CLAUDE.md")"

echo "== the INSTALL layout: a cache copy with no .git, beside the marketplace clone =="
# ai-bridge-v2/task-035. The fixture is shaped like the INSTALL and not like the repo —
# `source: ./plugin` means an installed plugin is the CONTENTS of `plugin/`, so the cache
# carries `scripts/ seed/ VERSION` at its top and no `.git` at all. A fixture shaped like
# the checkout cannot see this bug: the checkout has history and the install has none.
CTPL="$TMP/tpl-cache-src"
mkdir -p "$CTPL/plugin/scripts"
cp -R "$TPL_SRC/plugin/seed" "$CTPL/plugin/seed"
cp "$TPL_SRC/plugin/scripts/init-bundle.sh" "$TPL_SRC/plugin/scripts/refresh-seeds.sh" \
   "$TPL_SRC/plugin/scripts/validate-bundle.sh" "$TPL_SRC/plugin/scripts/bundle-paths.sh" \
   "$CTPL/plugin/scripts/"
cp "$TPL_SRC/VERSION" "$CTPL/plugin/VERSION"
cp "$TPL_SRC/VERSION" "$CTPL/VERSION"
printf '# Index\nline A\nline B\n'        > "$CTPL/plugin/seed/index.md"
printf '# Panel\nintro line\ntail line\n' > "$CTPL/plugin/seed/CLAUDE.md"
( cd "$CTPL" && git init -q -b main . && git add -A && gc "cache fixture, seed v1" )

CINST="$TMP/group/_ai-bridge-cache"
mkdir -p "$CINST"
bash "$CTPL/plugin/scripts/init-bundle.sh" "$CINST" > "$TMP/cache-stamp.out" 2>&1
sed 's/^intro line$/intro line — HOUSE EDIT/' "$CINST/CLAUDE.md" > "$TMP/cc" && mv "$TMP/cc" "$CINST/CLAUDE.md"

printf 'line C (new in seed v2)\n' >> "$CTPL/plugin/seed/index.md"
sed 's/^intro line$/intro line — TEMPLATE V2/' "$CTPL/plugin/seed/CLAUDE.md" > "$TMP/cc" && mv "$TMP/cc" "$CTPL/plugin/seed/CLAUDE.md"
( cd "$CTPL" && git add -A && gc "cache fixture, seed v2" )

# <home>/plugins/cache/<marketplace>/<plugin>/<version>/  +  <home>/plugins/marketplaces/<marketplace>/
HOMEP="$TMP/claude-home/plugins"
CACHE="$HOMEP/cache/fixture-market/${PN}/9.9.9"
mkdir -p "$CACHE" "$HOMEP/marketplaces"
cp -R "$CTPL/plugin/." "$CACHE/"
git clone -q "$CTPL" "$HOMEP/marketplaces/fixture-market"
# ASSERT THE FIXTURE'S SHAPE BEFORE ASSERTING ON THE BEHAVIOUR. A cache that accidentally
# carried a .git would make every assertion below pass for the wrong reason.
assert "the fixture cache is a plain copy with no .git" "$(yes_if test ! -e "$CACHE/.git")"
assert "…and carries the contents of plugin/ (seed + VERSION beside scripts/)" \
  "$(yes_if test -f "$CACHE/seed/index.md")"
assert "…and the marketplace clone beside it is a real git repo" \
  "$(yes_if git -C "$HOMEP/marketplaces/fixture-market" rev-parse HEAD)"

# The bundle's own stamped record would answer too, so remove it: this block measures the
# marketplace path and nothing else.
rm -rf "$CINST/$AB_DIR/seed-base" "$CINST/$AB_DIR/refresh"
CACHE_OUT="$(bash "$CACHE/scripts/refresh-seeds.sh" "$CINST" 2>&1)"
assert "the run names the marketplace clone as its source" "$(has 'history:  marketplace clone' "$CACHE_OUT")"
assert "…and a diverged seed file reports 0 unknown"  "$(has 'summary: .* 0 unknown' "$CACHE_OUT")"
assert "…the copy stamped from v1 is PORTABLE"        "$(has 'PORTABLE  index.md' "$CACHE_OUT")"
assert "…on a base the clone supplied, verbatim"      "$(has 'seed verbatim' "$CACHE_OUT")"
assert "…and the hand-diverged copy CONFLICTS"        "$(has 'CONFLICT  CLAUDE.md' "$CACHE_OUT")"
assert "…and the report still wrote nothing"          "$(yes_if grep -q 'HOUSE EDIT' "$CINST/CLAUDE.md")"

# NON-VACUITY: take the clone away and the same run must go back to UNKNOWN.
mv "$HOMEP/marketplaces/fixture-market" "$HOMEP/marketplaces/somebody-elses-market"
NOMKT_OUT="$(bash "$CACHE/scripts/refresh-seeds.sh" "$CINST" 2>&1)"
assert "without the clone the same run is UNKNOWN again" "$(has 'UNKNOWN   index.md' "$NOMKT_OUT")"
assert "…and another marketplace's clone is not adopted" "$(has 'history:  none' "$NOMKT_OUT")"
mv "$HOMEP/marketplaces/somebody-elses-market" "$HOMEP/marketplaces/fixture-market"

# …and a clone that has MOVED ON is a stranger's history, so it is refused with a reason.
( cd "$HOMEP/marketplaces/fixture-market" && printf 'a clone-only seed edit\n' >> plugin/seed/index.md \
  && git add -A && gc "the clone moves past the installed copy" )
DRIFT_OUT="$(bash "$CACHE/scripts/refresh-seeds.sh" "$CINST" 2>&1)"
assert "a clone whose seed tree differs at HEAD is refused" "$(has 'history:  none' "$DRIFT_OUT")"
assert "…and the reason is printed, not swallowed"         "$(has 'different seed tree at HEAD' "$DRIFT_OUT")"
git -C "$HOMEP/marketplaces/fixture-market" reset -q --hard HEAD~1

echo "== a shallow marketplace clone is never silently treated as full history =="
# `claude` clones a marketplace shallow (measured on this machine: 26 commits). A
# truncated walk fails QUIETLY — the older seed versions are simply absent, so "this seed
# never changed" reads true and real drift is reported as in sync.
SHOME="$TMP/claude-home-shallow/plugins"
SCACHE="$SHOME/cache/fixture-market/${PN}/9.9.9"
mkdir -p "$SCACHE" "$SHOME/marketplaces"
cp -R "$CTPL/plugin/." "$SCACHE/"
# `file://` because git ignores --depth on a plain local clone.
git clone -q --depth 1 "file://$CTPL" "$SHOME/marketplaces/fixture-market"
assert "the fixture clone really is shallow (.git/shallow)" \
  "$(yes_if test -f "$SHOME/marketplaces/fixture-market/.git/shallow")"
SHALLOW_OUT="$(bash "$SCACHE/scripts/refresh-seeds.sh" "$CINST" --no-deepen 2>&1)"
assert "--no-deepen reports the shallow clone"      "$(has 'SHALLOW clone' "$SHALLOW_OUT")"
assert "…and prints the command that deepens it"    "$(has 'fetch --unshallow' "$SHALLOW_OUT")"
assert "…and a file it cannot judge is UNKNOWN, not silently in sync" \
  "$(has 'UNKNOWN   index.md' "$SHALLOW_OUT")"
assert "…naming shallowness as the reason"          "$(has 'SHALLOW clone' "$SHALLOW_OUT")"
assert "…and it stayed shallow"                     "$(yes_if test -f "$SHOME/marketplaces/fixture-market/.git/shallow")"
DEEP_OUT="$(bash "$SCACHE/scripts/refresh-seeds.sh" "$CINST" 2>&1)"
assert "a default run deepens it instead"           "$(has 'deepened with git fetch --unshallow' "$DEEP_OUT")"
assert "…and the clone is no longer shallow on disk" \
  "$(test ! -f "$SHOME/marketplaces/fixture-market/.git/shallow" && echo 0 || echo 1)"
assert "…so the same file is judged on a real base" "$(has 'PORTABLE  index.md' "$DEEP_OUT")"
assert "…and the run reports 0 unknown"             "$(has 'summary: .* 0 unknown' "$DEEP_OUT")"

echo "== .gitignore's instance-additions block is the bundle's own (2x/task-008) =="
# The one file every bundle customises was the one file that could never read clean: the
# seed's lines were all present, in seed order, and the trailing block of bundle patterns
# made every run a CONFLICT. The block — the `# Instance additions` heading through EOF,
# plus the managed marker block init puts directly above it — is split off both sides
# before the merge and re-appended verbatim after it.
GI_HEAD='# Instance additions (kept across seed refreshes)'
gi_line()  { head -1 <<<"$(grep -nxF "$2" "$1")" | cut -d: -f1 || true; }
gi_where() { # <file> <pattern> <before|after> the heading
  local h p; h="$(gi_line "$1" "$GI_HEAD")"; p="$(gi_line "$1" "$2")"
  [[ -n "$h" && -n "$p" ]] || { echo 1; return; }
  if [[ "$3" == before ]]; then [[ "$p" -lt "$h" ]] && echo 0 || echo 1
  else [[ "$p" -gt "$h" ]] && echo 0 || echo 1; fi
}
gi_labels() { printf '%s\n' "$1" | awk '$1 ~ /^[A-Z]+$/ && $2 == ".gitignore" { print $1 }' | tr '\n' ' '; }

assert "the shipped seed .gitignore ends with the empty slot" \
  "$(yes_if grep -qxF "$GI_HEAD" "$TPL_SRC/plugin/seed/.gitignore")"
assert "…and no pattern line follows it in the seed" \
  "$(awk -v h="$GI_HEAD" '$0==h{f=1;next} f && $0 !~ /^[[:space:]]*(#.*)?$/{n++} END{exit n>0}' \
       "$TPL_SRC/plugin/seed/.gitignore" && echo 0 || echo 1)"

GINST="$TMP/group/_ai-bridge-gitignore"
mkdir -p "$GINST"
bash "$TPL/plugin/scripts/init-bundle.sh" "$GINST" > "$TMP/gi-stamp.out" 2>&1
assert "the stamp gives a bundle without the slot one"  "$(yes_if grep -qxF "$GI_HEAD" "$GINST/.gitignore")"
assert "…and writes its own patterns INTO that block"   "$(gi_where "$GINST/.gitignore" "/$AB_STATE_DIR" after)"
assert "…with the managed index markers ahead of it"    "$(gi_where "$GINST/.gitignore" '# >>> ai-bridge index ignore >>>' before)"
assert "…so the instance block is last"                 "$(gi_where "$GINST/.gitignore" '# <<< ai-bridge index ignore <<<' before)"

# IN SYNC WITH ADDITIONS: a bundle pattern in the block, the seed unchanged.
printf '/MY-OWN-PATTERN\n' >> "$GINST/.gitignore"
GI_REPORT="$(bash "$UPGRADE" "$GINST" 2>&1)"
assert "a bundle pattern in the block leaves .gitignore IN SYNC" \
  "$([[ -z "$(gi_labels "$GI_REPORT")" ]] && echo 0 || echo 1)"

# PORTED WITH ADDITIONS: now the seed changes, above its own heading.
printf 'SEED-V3-ONLY\n' >> "$TPL/plugin/seed/.gitignore"
( cd "$TPL" && git add -A && gc "template, seed v3 — a new .gitignore line" )
GI_REPORT="$(bash "$UPGRADE" "$GINST" 2>&1)"
assert "a seed .gitignore change is PORTABLE, not a CONFLICT" "$(has 'PORTABLE  .gitignore' "$GI_REPORT")"
GI_APPLY="$(bash "$UPGRADE" "$GINST" --apply 2>&1)"
assert "--apply ports it"                        "$(has 'PORTED    .gitignore' "$GI_APPLY")"
assert "…the seed's new line landed"             "$(yes_if grep -qxF 'SEED-V3-ONLY' "$GINST/.gitignore")"
assert "…above the instance block"               "$(gi_where "$GINST/.gitignore" 'SEED-V3-ONLY' before)"
assert "…the bundle's own pattern survived"      "$(yes_if grep -qxF '/MY-OWN-PATTERN' "$GINST/.gitignore")"
assert "…still inside the block"                 "$(gi_where "$GINST/.gitignore" '/MY-OWN-PATTERN' after)"
assert "…and no conflict marker was written"     "$(hasnt '<<<<<<<' "$(cat "$GINST/.gitignore")")"
GI_REPORT="$(bash "$UPGRADE" "$GINST" 2>&1)"
assert "the ported bundle reads IN SYNC again" \
  "$([[ -z "$(gi_labels "$GI_REPORT")" ]] && echo 0 || echo 1)"

echo "== CLAUDE.md's instance-additions block is the bundle's own too =="
# Same mechanism, second spelling: `.gitignore` opens the block with a comment, CLAUDE.md
# with a markdown heading carrying a parenthetical. The two bundles below diverge from the
# seed in IDENTICAL bytes except for that heading line, so the pair is the whole claim.
MD_HEAD='## Instance additions (kept across seed refreshes)'
md_line()   { head -1 <<<"$(grep -nxF -e "$2" -- "$1")" | cut -d: -f1 || true; }
md_where()  { # <file> <heading> <pattern> <before|after>
  local h p; h="$(md_line "$1" "$2")"; p="$(md_line "$1" "$3")"
  [[ -n "$h" && -n "$p" ]] || { echo 1; return; }
  if [[ "$4" == before ]]; then [[ "$p" -lt "$h" ]] && echo 0 || echo 1
  else [[ "$p" -gt "$h" ]] && echo 0 || echo 1; fi
}
md_labels() { printf '%s\n' "$1" | awk '$1 ~ /^[A-Z]+$/ && $2 == "CLAUDE.md" { print $1 }' | tr '\n' ' '; }

md_bundle() { # <dir> <heading-or-empty> — stamp, edit the BODY, append a trailing block
  mkdir -p "$1"
  bash "$TPL/plugin/scripts/init-bundle.sh" "$1" > "$TMP/md-stamp.out" 2>&1
  sed 's/^intro line — TEMPLATE V2$/intro line — HOUSE EDIT/' "$1/CLAUDE.md" > "$TMP/m"
  mv "$TMP/m" "$1/CLAUDE.md"
  { echo; [[ -z "$2" ]] || { echo "$2"; echo; }; echo '- a house rule nobody upstream knows'; } >> "$1/CLAUDE.md"
}
MDI="$TMP/group/_ai-bridge-claude"; md_bundle "$MDI" "$MD_HEAD"
MDN="$TMP/group/_ai-bridge-claude-noblock"; md_bundle "$MDN" ""
assert "the stamped body is the seed's, so the hand edit is real drift" \
  "$(yes_if grep -qxF 'intro line — HOUSE EDIT' "$MDI/CLAUDE.md")"
md_block() { awk -v h="$MD_HEAD" 'index($0, h) == 1 { f = 1 } f' "$1"; }
md_block "$MDI/CLAUDE.md" > "$TMP/md-block.before"

# The seed grows a new TRAILING section — exactly where a bundle's EOF append sits.
printf '\n## A section new in seed v4\nseed tail line\n' >> "$TPL/plugin/seed/CLAUDE.md"
( cd "$TPL" && git add -A && gc "template, seed v4 — a new trailing CLAUDE.md section" )

MD_REPORT="$(bash "$UPGRADE" "$MDI" 2>&1)"
assert "a seed tail change is PORTABLE, not a CONFLICT"  "$(has 'PORTABLE  CLAUDE.md' "$MD_REPORT")"
assert "…and never silently IN SYNC — the drift is named" \
  "$([[ "$(md_labels "$MD_REPORT")" == "PORTABLE " ]] && echo 0 || echo 1)"
MD_APPLY="$(bash "$UPGRADE" "$MDI" --apply 2>&1)"
assert "--apply ports it"                        "$(has 'PORTED    CLAUDE.md' "$MD_APPLY")"
assert "…the seed's new section landed"          "$(yes_if grep -qxF '## A section new in seed v4' "$MDI/CLAUDE.md")"
assert "…above the instance block"               "$(md_where "$MDI/CLAUDE.md" "$MD_HEAD" '## A section new in seed v4' before)"
assert "…the bundle's block survived, below the heading" "$(md_where "$MDI/CLAUDE.md" "$MD_HEAD" '- a house rule nobody upstream knows' after)"
md_block "$MDI/CLAUDE.md" > "$TMP/md-block.after"
assert "…and came back BYTE-IDENTICAL"           "$(yes_if cmp -s "$TMP/md-block.before" "$TMP/md-block.after")"
assert "…and the body's own hand edit survived"  "$(yes_if grep -qxF 'intro line — HOUSE EDIT' "$MDI/CLAUDE.md")"
assert "…with no conflict marker written"        "$(hasnt '<<<<<<<' "$(cat "$MDI/CLAUDE.md")")"
assert "the ported bundle reads IN SYNC again"   "$([[ -z "$(md_labels "$(bash "$UPGRADE" "$MDI" 2>&1)")" ]] && echo 0 || echo 1)"

# The other direction: no heading ⇒ the whole file is body and the plain 3-way merge runs,
# so the same seed append collides with the bundle's — today's behaviour, unchanged.
MDN_REPORT="$(bash "$UPGRADE" "$MDN" 2>&1)"
assert "no heading ⇒ the trailing text is body, and it CONFLICTS" \
  "$(has 'CONFLICT  CLAUDE.md' "$MDN_REPORT")"
assert "…and report mode left that file untouched" \
  "$(hasnt '## A section new in seed v4' "$(cat "$MDN/CLAUDE.md")")"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
