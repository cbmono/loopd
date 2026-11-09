#!/usr/bin/env bash
#
# retire-machinery.test.sh — `/<plugin>:init` removes a machinery symlink into a template
# checkout, and nothing else.
#
# WHY. Removing a capability from `symlink/` (the /todo feature was the first) left every
# already-stamped bundle with a symlink into a path that no longer existed. That is worse
# than an absent file: a dangling command still registers, and a SessionStart hook whose
# script has vanished exits 127 on every launch.
#
# WHAT THE SWEEP BECAME (ai-bridge-v2/task-013). Machinery ships in the PLUGIN now, so
# there is nothing left to retire ONE file at a time: the whole `symlink/` design is what
# is retired, and the sweep removes EVERY machinery link a bundle carries — dangling or
# live. A live one is the quieter half of the same defect, because it resolves into a
# clone `claude plugin update` never touches. The old per-file cases are therefore one
# case now, and the historical retirements are asserted as a set against it.
#
# The negative properties are the point, and they are what this file mostly asserts:
#   · a real file is never removed, however dead it looks;
#   · a symlink pointing somewhere OTHER than a template checkout is never removed, even
#     when it dangles — it is not ours to judge;
#   · a bundle path containing glob metacharacters is handled (SC2295);
#   · seed content is never removed. A `todos.md` surviving a retired feature is the
#     human's own writing — that half is unchanged and is the last section of this file.
#
# assert(): 0 is a PASS, matching the other harnesses here.
set -uo pipefail

TPLSRC="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/retire-fixture.XXXXXX")" || {
  echo "retire-machinery.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
# PHYSICAL path: on macOS $TMPDIR lives under /var -> /private/var, and the installer
# resolves its own location with cd+pwd, so an unresolved path would not compare equal to
# what it prints back.
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
assert() { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
yes_if() { if "$@" >/dev/null 2>&1; then echo 0; else echo 1; fi; }
no_if()  { if "$@" >/dev/null 2>&1; then echo 1; else echo 0; fi; }
has()    { grep -q <<<"$2" -- "$1" && echo 0 || echo 1; }
hasnt()  { grep -q <<<"$2" -- "$1" && echo 1 || echo 0; }

# A copy of the template, so mutilating it cannot touch the real one.
TPL="$TMP/tpl"; mkdir -p "$TPL"
( cd "$TPLSRC" && git ls-files . ) | while IFS= read -r f; do
  [ -n "$f" ] || continue
  mkdir -p "$TPL/$(dirname "$f")"; cp "$TPLSRC/$f" "$TPL/$f" 2>/dev/null || true
done
chmod +x "$TPL"/plugin/scripts/*.sh "$TPL"/plugin/hooks/*.sh 2>/dev/null || true

# A SECOND checkout, standing in for the template a symlink-era bundle was stamped from.
# It is a real template as far as the sweep is concerned — `seed/` and `VERSION` at its
# root — which is exactly what makes a link into it recognisable as machinery.
OLDTPL="$TMP/oldtpl"; mkdir -p "$OLDTPL/seed" "$OLDTPL/symlink/scripts" "$OLDTPL/symlink/.claude/hooks"
printf '0.20.0\n' > "$OLDTPL/VERSION"; printf '{}\n' > "$OLDTPL/seed/instance.config.json"

INST="$TMP/group/_ai-bridge-group"; mkdir -p "$INST"
bash "$TPL/plugin/scripts/init-bundle.sh" "$INST" >"$TMP/out1" 2>&1
assert "a fresh bundle stamps"              "$(yes_if test -f "$INST/instance.config.json")"
assert "…carrying no symlink at all"        "$([ -z "$(find "$INST" -type l 2>/dev/null)" ] && echo 0 || echo 1)"

# `objectives/` is an OPTIONAL layer (SCHEMA.md -> type: Objective), so the seed ships none
# and a plain stamp must create none. The opt-in flag is the only thing that makes it, and
# it is idempotent — an existing objectives/ is DATA, so it is kept, never re-seeded.
assert "a plain stamp creates no objectives/" "$(no_if test -d "$INST/objectives")"
bash "$TPL/plugin/scripts/init-bundle.sh" --with-objectives "$INST" >"$TMP/out-obj" 2>&1
assert "--with-objectives creates it"        "$(yes_if test -d "$INST/objectives")"
assert "…and says so"                        "$(yes_if grep -q 'seed  objectives/' "$TMP/out-obj")"
printf -- '---\ntype: Objective\ntitle: O\nstatus: active\n---\n' > "$INST/objectives/mine.md"
bash "$TPL/plugin/scripts/init-bundle.sh" --with-objectives "$INST" >"$TMP/out-obj2" 2>&1
assert "a second run keeps it, never re-seeds" "$(yes_if grep -q 'keep  objectives/ (exists)' "$TMP/out-obj2")"
assert "…and the human's objective survives"   "$(yes_if grep -q 'type: Objective' "$INST/objectives/mine.md")"

# --- the sweep, and the three decoys that must survive it.
mkdir -p "$INST/scripts"
printf '#!/usr/bin/env bash\nexit 0\n' > "$OLDTPL/symlink/scripts/doomed.sh"
ln -s "$OLDTPL/symlink/scripts/doomed.sh" "$INST/scripts/doomed.sh"        # ours, RESOLVES
ln -s "$OLDTPL/symlink/scripts/gone.sh"   "$INST/scripts/dead.sh"          # ours, DANGLES
printf 'my own notes\n' > "$INST/scripts/mine.sh"                          # a real file
ln -s "$TMP/nowhere-at-all"  "$INST/scripts/foreign-dangling"              # dangles, NOT ours
mkdir -p "$TMP/elsewhere"; ln -sfn "$TMP/elsewhere" "$INST/my-own-link"    # theirs, resolves

RC=0; bash "$TPL/plugin/scripts/init-bundle.sh" "$INST" >"$TMP/out3" 2>&1 || RC=$?
assert "the stamp still exits 0"            "$([[ $RC -eq 0 ]] && echo 0 || echo 1)"
assert "a LIVE machinery link is removed"   "$(no_if test -L "$INST/scripts/doomed.sh")"
assert "…and reported with its reason"      "$(yes_if grep -q 'retire scripts/doomed.sh — machinery link into a template checkout' "$TMP/out3")"
assert "a DANGLING machinery link too"      "$(no_if test -L "$INST/scripts/dead.sh")"
assert "…reported as dangling, with its old target" "$(yes_if grep -q 'retire scripts/dead.sh — dangling (was -> ' "$TMP/out3")"
assert "a real file is NOT removed"         "$(yes_if grep -q 'my own notes' "$INST/scripts/mine.sh")"
assert "a foreign dangling link is removed" "$(no_if test -L "$INST/scripts/foreign-dangling")"
assert "…because a dangling link in a bundle has one meaning" \
  "$(yes_if grep -q 'retire scripts/foreign-dangling — dangling' "$TMP/out3")"
# …EXCEPT INSIDE THE DATA DIRECTORIES, where it has the opposite meaning. No installer
# ever stamped machinery under projects/, knowledge/ or objectives/, so a symlink there is
# the human's — a linked spec, a shared notes folder, one they have not fixed yet — and
# "data untouched" has to hold for a broken link as much as for a file.
mkdir -p "$INST/projects/demo" "$INST/knowledge/findings" "$INST/objectives"
ln -s "$TMP/nowhere-at-all" "$INST/projects/demo/spec.md"
ln -s "$TMP/nowhere-at-all" "$INST/knowledge/findings/linked.md"
ln -s "$TMP/nowhere-at-all" "$INST/objectives/linked.md"
bash "$TPL/plugin/scripts/init-bundle.sh" "$INST" >"$TMP/out-data" 2>&1
assert "a dangling link under projects/ survives"   "$(yes_if test -L "$INST/projects/demo/spec.md")"
assert "…under knowledge/ too"                      "$(yes_if test -L "$INST/knowledge/findings/linked.md")"
assert "…and under objectives/"                     "$(yes_if test -L "$INST/objectives/linked.md")"
assert "…and none of the three is even mentioned"   "$(no_if grep -qE 'projects/demo/spec.md|knowledge/findings/linked.md|objectives/linked.md' "$TMP/out-data")"
assert "a resolving link of the human's OWN survives" "$(yes_if test -L "$INST/my-own-link")"
assert "…and is reported as kept, not removed" "$(yes_if grep -q 'keep  my-own-link' "$TMP/out3")"
# Idempotent: a second sweep with nothing to do says nothing and still exits 0.
bash "$TPL/plugin/scripts/init-bundle.sh" "$INST" >"$TMP/out4" 2>&1
assert "a repeat run retires nothing"       "$(no_if grep -q 'retire ' "$TMP/out4")"

# --- EVERY historical retirement, as ONE set, because the failure that matters is partial.
# Seven swept and one left is indistinguishable from a clean run in any assertion that
# looks at a single name — and a surviving `.claude/agents/<role>.md` link does not dangle
# harmlessly, it SHADOWS the plugin's copy and silently wins. These are the real paths:
# the retired renderer, the two enforcement hooks the plugin absorbed, the renamed agent,
# the eight commands and the eight role agents.
LEGACY="scripts/build-artifact-board.sh .claude/hooks/deny-destructive.sh
.claude/hooks/agent-control.sh .claude/agents/oncall-guide.md
.claude/commands/ai-bridge.md .claude/commands/answer.md .claude/commands/audit.md
.claude/commands/fanout.md .claude/commands/pr-review-request.md
.claude/commands/new-project.md .claude/commands/close-project.md
.claude/commands/pm-loop.md
.claude/agents/advisor.md .claude/agents/auditor.md .claude/agents/cataloguer.md
.claude/agents/devops-engineer.md .claude/agents/failure-analyst.md
.claude/agents/project-manager.md .claude/agents/qa-reviewer.md
.claude/agents/software-engineer.md
SCHEMA.md CONVENTIONS.md agents/index.md .claude/settings.json"
LEG="$TMP/group/_ai-bridge-legacy"; mkdir -p "$LEG"
cp "$TPL/plugin/seed/instance.config.json" "$LEG/instance.config.json"
n_legacy=0
for rel in $LEGACY; do
  mkdir -p "$LEG/$(dirname "$rel")" "$OLDTPL/symlink/$(dirname "$rel")"
  printf 'fixture\n' > "$OLDTPL/symlink/$rel"
  ln -s "$OLDTPL/symlink/$rel" "$LEG/$rel"
  n_legacy=$((n_legacy+1))
done
assert "the legacy fixture really carries them all" \
  "$([ "$(find "$LEG" -type l | wc -l | tr -d ' ')" = "$n_legacy" ] && echo 0 || echo 1)"
bash "$TPL/plugin/scripts/init-bundle.sh" "$LEG" >"$TMP/out-legacy" 2>&1
left=0; unreported=0
for rel in $LEGACY; do
  [ -L "$LEG/$rel" ] && left=$((left+1))
  grep -qF "retire $rel" "$TMP/out-legacy" || unreported=$((unreported+1))
done
assert "…and one conversion leaves none of them"   "$([ "$left" -eq 0 ] && echo 0 || echo 1)"
assert "…each reported by name, all of them"       "$([ "$unreported" -eq 0 ] && echo 0 || echo 1)"
# GENERIC ON PURPOSE, and this is criterion 3's "no installer edit" stated as a test: the
# sweep must not carry a list of what it retires, or the next retirement needs an edit
# nobody will make. (Role NAMES are exempt — the installer seeds `roleTiers` and
# legitimately names `software-engineer`, `qa-reviewer` and `cataloguer`.)
assert "the installer names no retired path" \
  "$(no_if grep -qE 'build-artifact-board|deny-destructive|agent-control|oncall-guide|pm-loop|pr-review-request' "$TPL/plugin/scripts/init-bundle.sh")"
# And the template really ships none of them any more — the assertions above would pass
# just as well against a repo that still had them, because they plant their own fixtures.
assert "the template ships no symlink/ directory at all" \
  "$(no_if test -e "$TPL/symlink")"

# --- a bundle path containing glob metacharacters (SC2295).
# `${dst#$TARGET/}` expands TARGET as a PATTERN, so a `[` in the path strips nothing, the
# relative path stays absolute, and the dead link is silently kept. Quoting it fixes that,
# and only this fixture can tell the difference.
ODD="$TMP/od[d]group/_ai-bridge-odd"; mkdir -p "$ODD"
bash "$TPL/plugin/scripts/init-bundle.sh" "$ODD" >"$TMP/out8" 2>&1
printf 'doomed again\n' > "$OLDTPL/symlink/DOOMED-TWICE.md"
ln -s "$OLDTPL/symlink/DOOMED-TWICE.md" "$ODD/DOOMED-TWICE.md"
assert "glob-y path: the fixture link exists" "$(yes_if test -L "$ODD/DOOMED-TWICE.md")"
bash "$TPL/plugin/scripts/init-bundle.sh" "$ODD" >"$TMP/out10" 2>&1
assert "glob-y path: the link is swept"     "$(no_if test -L "$ODD/DOOMED-TWICE.md")"
assert "…and reported with its relative path" "$(yes_if grep -q 'retire DOOMED-TWICE.md' "$TMP/out10")"

# --- retired SEED content: reported with an rm, never removed.
# The asymmetry with the machinery sweep above is the whole point. A symlink into this
# template whose target is gone has one possible meaning; a seed file the human has owned
# since it was copied does not — `todos.md` is literally their notes. install.sh's safety
# property is that it only links and seeds-if-absent, so it may report and must not delete.
SEEDY="$TMP/group/_ai-bridge-seedy"; mkdir -p "$SEEDY"
bash "$TPL/plugin/scripts/init-bundle.sh" "$SEEDY" >/dev/null 2>&1
printf 'my private notes\n' > "$SEEDY/retired-thing.md"
printf 'retired-thing.md\tthe X feature was removed\n' > "$TPL/plugin/RETIRED"
OUT="$(bash "$TPL/plugin/scripts/init-bundle.sh" "$SEEDY" 2>&1)"
assert "retired seed content is reported"    "$(has 'stale retired-thing.md' "$OUT")"
assert "…with its reason"                    "$(has 'the X feature was removed' "$OUT")"
assert "…and the exact rm command"           "$(has 'rm .*_ai-bridge-seedy/retired-thing.md' "$OUT")"
assert "…and is NOT deleted"                 "$(yes_if grep -q 'my private notes' "$SEEDY/retired-thing.md")"
# A manifest entry for a file the instance does not have must stay quiet — most entries
# will be irrelevant to most instances, forever.
assert "an absent entry says nothing" \
  "$(hasnt '^  stale ' "$(bash "$TPL/plugin/scripts/init-bundle.sh" "$INST" 2>&1)")"
# Comments, blanks and a reason-less line must all parse without noise.
printf '# a comment\n\nretired-thing.md\n' > "$TPL/plugin/RETIRED"
OUT2="$(bash "$TPL/plugin/scripts/init-bundle.sh" "$SEEDY" 2>&1)"
assert "a reason-less entry still reports"   "$(has 'stale retired-thing.md' "$OUT2")"
assert "…with a default reason"              "$(has 'no longer shipped by the template' "$OUT2")"
assert "…and comments are not reported"      "$(hasnt 'stale # a comment' "$OUT2")"
# Absence of the manifest is silence, not an error — the AUTONOMY.md convention.
rm -f "$TPL/plugin/RETIRED"
RC=0; OUT3="$(bash "$TPL/plugin/scripts/init-bundle.sh" "$SEEDY" 2>&1)" || RC=$?
assert "no manifest: exits 0"                "$([[ $RC -eq 0 ]] && echo 0 || echo 1)"
assert "no manifest: reports nothing"        "$(hasnt '^  stale ' "$OUT3")"
assert "no manifest: file still there"       "$(yes_if grep -q 'my private notes' "$SEEDY/retired-thing.md")"
# A dangling SYMLINK at a manifested path belongs to the sweep, not to this list.
: > "$TPL/plugin/RETIRED"; printf 'linky.md\tretired\n' >> "$TPL/plugin/RETIRED"
ln -sfn "$TMP/gone-forever" "$SEEDY/linky.md"
OUT4="$(bash "$TPL/plugin/scripts/init-bundle.sh" "$SEEDY" 2>&1)"
assert "a symlink is not reported as stale"  "$(hasnt 'stale linky.md' "$OUT4")"

# --- a manifest entry that escapes the instance root is refused, not reported.
# `../victim.md` would make the printed `rm` operate OUTSIDE the instance, and a human
# pasting a command this script handed them has every reason to trust it.
printf 'escapee\n' > "$TMP/group/victim.md"
printf '../victim.md\tretired\n' > "$TPL/plugin/RETIRED"
OUT5="$(bash "$TPL/plugin/scripts/init-bundle.sh" "$SEEDY" 2>&1)"
assert "an escaping entry is not reported"   "$(hasnt 'stale \.\./victim.md' "$OUT5")"
assert "…no rm command is printed for it"    "$(hasnt 'rm .*victim.md' "$OUT5")"
assert "…it is warned about instead"         "$(has 'escapes the instance root' "$OUT5")"
assert "…and the outside file is untouched"  "$(yes_if grep -q 'escapee' "$TMP/group/victim.md")"
printf '/etc/passwd\tretired\n' > "$TPL/plugin/RETIRED"
OUT6="$(bash "$TPL/plugin/scripts/init-bundle.sh" "$SEEDY" 2>&1)"
assert "an absolute entry is refused"        "$(has 'not instance-relative' "$OUT6")"
assert "…and prints no rm"                   "$(hasnt 'rm /etc/passwd' "$OUT6")"
# A path merely CONTAINING dots is fine — only a `..` component escapes.
printf 'my..notes.md\tretired\n' > "$TPL/plugin/RETIRED"
printf 'dotty\n' > "$SEEDY/my..notes.md"
OUT7="$(bash "$TPL/plugin/scripts/init-bundle.sh" "$SEEDY" 2>&1)"
assert "a dotted filename is NOT refused"    "$(has 'stale my\.\.notes.md' "$OUT7")"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
