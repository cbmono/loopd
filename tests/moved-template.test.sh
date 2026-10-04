#!/usr/bin/env bash
#
# moved-template.test.sh — a bundle that still carries machinery symlinks must be
# DETECTED, and converting it must not touch the data.
#
# WHY. On 2026-08-23 this checkout was moved with a plain `mv`. 185 symlinks dangled across
# three instances plus the ~/.claude config layer — every script, every role agent, every
# command, SCHEMA.md, settings.json — and nothing noticed. A dangling symlink is invisible
# until something executes it, which for a /pm-loop tick means mid-dispatch with agents
# already briefed.
#
# WHAT CHANGED (ai-bridge-v2/task-013), AND WHY THIS FILE STILL EXISTS. The design that
# made that incident possible is gone: machinery ships in the PLUGIN, and a bundle
# `/<plugin>:init` stamps carries no link into any checkout. So the question is no longer
# "did a link die?" but "is anything still linked at all?" — and the answer must be the
# same alarm, because a LIVE machinery link is the quieter half of the same defect: it
# resolves into a clone that `claude plugin update` never touches, so the bundle runs
# machinery frozen at whatever that clone last pulled, forever, with nothing saying so.
#
# Two halves, and the negative properties are most of the file:
#
#   session-banner.sh (SessionStart hook — the MACHINERY section of it)
#     · names the links, where they point, and the exact repair command;
#     · that section is ABSENT and exit 0 in a converted bundle; in a non-bridge project
#       that inherits the hook the whole banner is silent, which is the reason it is safe
#       to ship user-wide as a plugin hook;
#     · does not identify a bundle by SCHEMA.md. That is the trap: an unconverted bundle
#       carries SCHEMA.md as a symlink, `[ -f ]` on a dangling one is FALSE, and the
#       obvious guard (push-state.sh's pair) would therefore silence the hook in exactly
#       the case it exists for. Asserted directly, because it is invisible in review;
#     · an ABSENT probe path, and a REAL FILE at one, are both left alone.
#
#   init-bundle.sh (the conversion)
#     · removes every machinery link, dangling or live, and says which and why;
#     · leaves a symlink of the human's own, and every real file, alone;
#     · leaves the bundle's DATA byte-identical;
#     · is idempotent — a second run retires nothing.
#
# assert(): 0 is a PASS, matching the other harnesses here.
set -uo pipefail
. "$(dirname "$0")/tools/plugin-name.sh"

TPLSRC="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$(dirname "$0")/../plugin/scripts/bundle-paths.sh"
# GUARDED, because the canonicalisation below is destructive over an empty TMP: when
# $TMPDIR names a directory that does not exist, `mktemp -d` fails, this substitution is
# EMPTY, `cd ""` SUCCEEDS WITHOUT MOVING, `pwd -P` returns this script's own cwd — the
# checkout — and the EXIT trap below deletes it. tests/harness-temp-safety.test.sh fails
# on that shape anywhere in tests/, and it is what caught this file.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/moved-tpl.XXXXXX")" || {
  echo "moved-template.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
# PHYSICAL path, before anything is built under it. On macOS $TMPDIR lives under /var,
# which is a symlink to /private/var, and the installer derives its own location with
# cd+pwd — so a path it prints back is the RESOLVED one, and an assertion built from the
# unresolved $TMPDIR would compare "/private/var/…" against "/var/…" and fail for a reason
# that has nothing to do with the behaviour.
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
assert() { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
yes_if() { if "$@" >/dev/null 2>&1; then echo 0; else echo 1; fi; }
no_if()  { if "$@" >/dev/null 2>&1; then echo 1; else echo 0; fi; }
has()    { grep -qF <<<"$2" -- "$1" && echo 0 || echo 1; }
hasnt()  { grep -qF <<<"$2" -- "$1" && echo 1 || echo 0; }

HOOK_SRC="$TPLSRC/plugin/hooks/session-banner.sh"
# The one string that only the machinery section ever prints.
WARN="MACHINERY SYMLINKS"

echo "== the hook is wired up at all =="
assert "session-banner.sh ships"         "$(yes_if test -f "$HOOK_SRC")"
assert "…and is executable"              "$(yes_if test -x "$HOOK_SRC")"
assert "…and parses"                     "$(yes_if bash -n "$HOOK_SRC")"
# A hook nothing registers is a file. The PLUGIN manifest is the only thing that runs it
# now — it used to be the bundle's own settings.json, symlinked in from the template, so
# the hook reached only bundles somebody had re-stamped.
SET="$TPLSRC/plugin/hooks/hooks.json"
assert "hooks.json registers it at SessionStart" \
  "$(yes_if grep -q 'session-banner.sh' <<<"$(awk '/"SessionStart"/,0' "$SET")")"
# The consolidation, stated from this side too: the hook it replaced must not still be
# registered beside it. A manifest naming both would run the machinery probe twice.
assert "…and check-machinery.sh is NOT registered any more" \
  "$(no_if grep -q 'check-machinery.sh' "$SET")"
# And the bundle's own seeded settings.json must register NONE of them, or a converted
# bundle would run the banner twice — once from the plugin, once from itself.
assert "…and the seeded settings.json registers no hook" \
  "$(no_if grep -q '"hooks"' "$TPLSRC/plugin/seed/.claude/settings.json")"

echo "== every probe path is a path the OLD installer really stamped =="
# The probe list is five literal paths naming the symlink-era layout. It fails CLOSED — a
# path that is not a symlink here is simply not counted — so a stale entry costs a missed
# report rather than a false alarm, which means nothing else would ever notice it going
# stale. This is what notices: each one must still be a file this repo ships, under the
# plugin or the seed, or the probe is aimed at nothing.
PROBES="$(sed -n 's/^PROBES="\(.*\)"$/\1/p' "$HOOK_SRC")"
assert "the probe list is readable from the hook"  "$([ -n "$PROBES" ] && echo 0 || echo 1)"
for rel in $PROBES; do
  base="$(basename "$rel")"
  assert "probe names something this repo ships: $rel" \
    "$(yes_if bash -c "test -f '$TPLSRC/plugin/seed/$rel' || test -f '$TPLSRC/plugin/scripts/$base' || test -f '$TPLSRC/plugin/hooks/$base' || test -f '$TPLSRC/plugin/seed/.claude/$base'")"
done

# A copy of the template, so moving or mutilating it cannot touch the real one. Same
# git-ls-files shape as retire-machinery.test.sh (which is why this harness needs a git
# checkout and not a `git archive` export).
TPL="$TMP/here/tpl"; mkdir -p "$TPL"
( cd "$TPLSRC" && git ls-files . ) | while IFS= read -r f; do
  [ -n "$f" ] || continue
  mkdir -p "$TPL/$(dirname "$f")"; cp "$TPLSRC/$f" "$TPL/$f" 2>/dev/null || true
done
chmod +x "$TPL"/plugin/scripts/*.sh "$TPL"/plugin/hooks/*.sh 2>/dev/null || true

INST="$TMP/group/_ai-bridge-group"; mkdir -p "$INST"
bash "$TPL/plugin/scripts/init-bundle.sh" "$INST" >"$TMP/stamp" 2>&1
assert "a fresh bundle stamps"           "$(yes_if test -f "$INST/instance.config.json")"
assert "…carrying no symlink at all"     "$([ -z "$(find "$INST" -type l 2>/dev/null)" ] && echo 0 || echo 1)"
# The seed ships no objectives/ — it is an optional layer, opted into per bundle.
assert "…and no objectives/ directory"   "$(no_if test -d "$INST/objectives")"

echo "== converted bundle: silent, exit 0 =="
RC=0; OUT="$(CLAUDE_PROJECT_DIR="$INST" bash "$HOOK_SRC" 2>&1)" || RC=$?
assert "exit 0"                          "$([[ $RC -eq 0 ]] && echo 0 || echo 1)"
assert "…and raises no machinery warning" "$(hasnt "$WARN" "$OUT")"

echo "== a non-bridge project that inherits the hook: silent, exit 0 =="
# THE REALISTIC SHAPE, and it is sharper now than it was: the hook is a PLUGIN hook, so it
# fires in EVERY project on the machine, not only in one that copied a .claude directory.
# It must not print, and it must not care that it is not a bundle.
PLAIN="$TMP/plain-repo"; mkdir -p "$PLAIN/.claude/agents"
RC=0; OUT="$(CLAUDE_PROJECT_DIR="$PLAIN" bash "$HOOK_SRC" 2>&1)" || RC=$?
assert "exit 0"                          "$([[ $RC -eq 0 ]] && echo 0 || echo 1)"
assert "…and prints NOTHING"             "$([ -z "$OUT" ] && echo 0 || echo 1)"
# The guard is ONE marker. `.claude/agents` was its second half until the name swap
# retired that directory — the eight role agents ship in the `loopd` plugin — so a
# config file with no agents directory beside it is an ORDINARY bundle, and the banner is
# required to print in it. Requiring silence here would be requiring silence everywhere.
BARE="$TMP/bare-repo"; mkdir -p "$BARE"; printf '{}\n' > "$BARE/instance.config.json"
OUT="$(CLAUDE_PROJECT_DIR="$BARE" bash "$HOOK_SRC" 2>&1)"
assert "config file, no .claude/agents: prints" "$([ -n "$OUT" ] && echo 0 || echo 1)"

echo "== an absent, or real, probe path is not an unconverted one =="
# Absent means the bundle never had it. A real file is the CONVERTED state — the thing
# this migration produces — so complaining about it would be crying wolf on every start.
rm -f "$INST/SCHEMA.md"
OUT="$(CLAUDE_PROJECT_DIR="$INST" bash "$HOOK_SRC" 2>&1)"
assert "an absent probe path says nothing"  "$(hasnt "$WARN" "$OUT")"
printf 'my own SCHEMA\n' > "$INST/SCHEMA.md"
OUT="$(CLAUDE_PROJECT_DIR="$INST" bash "$HOOK_SRC" 2>&1)"
assert "a REAL file at a probe path too"    "$(hasnt "$WARN" "$OUT")"
rm -f "$INST/SCHEMA.md"

echo "== one machinery link is enough, and a dangling SCHEMA.md must not silence the hook =="
# The trap this asserts: push-state.sh's bundle test includes `[ -f SCHEMA.md ]`, which is
# FALSE for a dangling symlink. Reusing that pair here would have made the hook mute in the
# one situation it is for. Reproduced with a single link, not a whole move, so the
# assertion is about the guard and nothing else.
ln -s "$TPL/symlink/SCHEMA.md" "$INST/SCHEMA.md"
OUT="$(CLAUDE_PROJECT_DIR="$INST" bash "$HOOK_SRC" 2>&1)"
assert "a dangling SCHEMA.md is reported"   "$(has 'SCHEMA.md' "$OUT")"
assert "…and counted as 1 of 5"             "$(has '1 of 5' "$OUT")"
assert "…and as already dead"               "$(has '1 of them are already dead' "$OUT")"
assert "…and the repair is /${PN}:init" "$(has "/${PN}:init $INST" "$OUT")"

echo "== the whole symlink-era bundle, against a template that MOVED =="
# The real incident, in the shape it takes today: a bundle stamped by the old install.sh,
# whose template has since been moved. Every machinery link dangles at once. The hook still
# resolves because it runs from the PLUGIN, which is exactly the property this migration
# bought — under the old design the hook was itself one of the dead links.
LEG="$TMP/group/_ai-bridge-legacy"
mkdir -p "$LEG/scripts" "$LEG/.claude/hooks" "$LEG/agents" "$LEG/projects/demo/tasks" "$LEG/knowledge/findings"
cp "$TPL/plugin/seed/instance.config.json" "$LEG/instance.config.json"
printf 'a decision only this bundle holds\n' > "$LEG/projects/demo/index.md"
printf -- '---\ntype: Task\ntitle: t\nstatus: draft\n---\n' > "$LEG/projects/demo/tasks/task-001-x.md"
printf 'a finding\n' > "$LEG/knowledge/findings/f.md"
DATA_BEFORE="$(cat "$LEG/projects/demo/index.md" "$LEG/knowledge/findings/f.md")"
for p in SCHEMA.md CONVENTIONS.md AUTONOMY.md; do ln -s "$TPL/symlink/$p" "$LEG/$p"; done
ln -s "$TPL/symlink/agents/index.md" "$LEG/agents/index.md"
ln -s "$TPL/symlink/scripts/commit-as.sh" "$LEG/scripts/commit-as.sh"
ln -s "$TPL/symlink/.claude/hooks/push-state.sh" "$LEG/.claude/hooks/push-state.sh"
ln -s "$TPL/symlink/.claude/settings.json" "$LEG/.claude/settings.json"
mkdir -p "$TMP/mynotes"; ln -s "$TMP/mynotes" "$LEG/mynotes"
cat > "$LEG/.gitignore" <<'GI'
.DS_Store
my-own-rule/

# >>> ai-bridge machinery (symlinked) >>>
/SCHEMA.md
/CONVENTIONS.md
/scripts/commit-as.sh
# <<< ai-bridge machinery <<<
GI
mv "$TMP/here" "$TMP/there"
TPL2="$TMP/there/tpl"

RC=0; OUT="$(CLAUDE_PROJECT_DIR="$LEG" bash "$TPL2/plugin/hooks/session-banner.sh" 2>&1)" || RC=$?
assert "exit 0 even when reporting"      "$([[ $RC -eq 0 ]] && echo 0 || echo 1)"
assert "all five probes are named"       "$(has '5 of 5' "$OUT")"
assert "…the linked paths are listed"    "$(has 'scripts/commit-as.sh' "$OUT")"
assert "…the OLD location is named"      "$(has "$TPL" "$OUT")"
assert "…and the repair is /${PN}:init" "$(has "/${PN}:init $LEG" "$OUT")"
# It names the repair; it must not BE the repair. A hook that silently converted a bundle
# at session start would leave a migration with no trace at all.
assert "nothing was repaired"            "$(yes_if test -L "$LEG/SCHEMA.md")"

echo "== the conversion: links out, data untouched =="
RC=0; bash "$TPL2/plugin/scripts/init-bundle.sh" "$LEG" >"$TMP/convert" 2>&1 || RC=$?
assert "the conversion exits 0"          "$([[ $RC -eq 0 ]] && echo 0 || echo 1)"
assert "…and says what it retired"       "$(yes_if grep -q '^  retire SCHEMA.md' "$TMP/convert")"
assert "…naming the reason for a live link" "$(yes_if grep -q 'machinery link into a template checkout\|dangling' "$TMP/convert")"
assert "…and counts them"                "$(yes_if grep -q 'machinery link(s) removed' "$TMP/convert")"
assert "no symlink is left outside repos/" \
  "$([ -z "$(find "$LEG" -type l -not -path "$LEG/repos/*" -not -name mynotes 2>/dev/null)" ] && echo 0 || echo 1)"
assert "a symlink of the human's own survives" "$(yes_if test -L "$LEG/mynotes")"
assert "SCHEMA.md is a real file now"    "$(yes_if bash -c "test -f '$LEG/$AB_SCHEMA' && ! test -L '$LEG/$AB_SCHEMA'")"
assert "CONVENTIONS.md too"              "$(yes_if bash -c "test -f '$LEG/$AB_CONVENTIONS' && ! test -L '$LEG/$AB_CONVENTIONS'")"
# AUTONOMY.md is the deliberate exception: it is the deletable delegated-authority
# capability, so it is NOT replaced — absence means ask-first, the safe end — and the
# removal is reported loudly with the command to put it back.
assert "AUTONOMY.md is NOT put back"     "$(no_if test -e "$LEG/AUTONOMY.md")"
assert "…and the loss is reported"       "$(yes_if grep -q 'back to' "$TMP/convert")"
assert "…with the install that opts back in" "$(yes_if grep -q 'loopd-yolo@loopd' "$TMP/convert")"
assert "the bundle's DATA is byte-identical" \
  "$([ "$DATA_BEFORE" = "$(cat "$LEG/projects/demo/index.md" "$LEG/knowledge/findings/f.md")" ] && echo 0 || echo 1)"
assert "the task document is still there" "$(yes_if test -f "$LEG/projects/demo/tasks/task-001-x.md")"
assert "the machinery .gitignore block is retired" \
  "$(no_if grep -q 'ai-bridge machinery' "$LEG/.gitignore")"
assert "…while the human's own rules survive" "$(yes_if grep -qx 'my-own-rule/' "$LEG/.gitignore")"
assert "the bundle is healthy afterwards" \
  "$(hasnt "$WARN" "$(CLAUDE_PROJECT_DIR="$LEG" bash "$TPL2/plugin/hooks/session-banner.sh" 2>&1)")"

echo "== idempotent =="
bash "$TPL2/plugin/scripts/init-bundle.sh" "$LEG" >"$TMP/again" 2>&1
assert "a second run retires nothing"    "$(no_if grep -q '^  retire ' "$TMP/again")"
assert "…and the human's link is still there" "$(yes_if test -L "$LEG/mynotes")"

echo "== uninstall removes the derived views and nothing else =="
bash "$TPL2/plugin/scripts/init-bundle.sh" --uninstall "$LEG" >"$TMP/uninst" 2>&1
assert "uninstall exits 0"               "$(yes_if grep -q 'Done.' "$TMP/uninst")"
assert "…and leaves the seed content"    "$(yes_if test -f "$LEG/$AB_SCHEMA")"
assert "…and the data"                   "$(yes_if test -f "$LEG/projects/demo/tasks/task-001-x.md")"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
