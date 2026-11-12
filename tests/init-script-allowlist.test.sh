#!/usr/bin/env bash
#
# init-script-allowlist.test.sh — plugin/scripts/init-bundle.sh writes the two
# version-wild script rules into .claude/settings.local.json, once, and fails closed on a
# shape it cannot edit. The plugin is copied to a cache-shaped path under a fixture HOME,
# because the rule is derived from where the running init lives. Reasoning: task-016.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/tools/plugin-name.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/initallow.XXXXXX")" || {
  echo "init-script-allowlist.test: mktemp -d failed" >&2; exit 2; }
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }

copy_plugin() { # <dest> — the tracked plugin/ tree as plain files
  ( cd "$REPO/plugin" && git ls-files . ) | while IFS= read -r f; do
    mkdir -p "$1/$(dirname "$f")"; cp "$REPO/plugin/$f" "$1/$f"
  done
  chmod +x "$1"/scripts/*.sh
}
MK="$TMP/home/.claude/plugins/cache/mk/${PN}"
copy_plugin "$MK/9.9.9"
copy_plugin "$TMP/checkout/plugin"

STUB="$TMP/bin"; mkdir -p "$STUB"; printf '#!/bin/sh\nexit 1\n' > "$STUB/gh"; chmod +x "$STUB/gh"
stamp() { # <plugin root> <instance> [PATH]
  PATH="${3:-$STUB:$PATH}" HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home" CLAUDE_CONFIG_DIR="$TMP/home/.claude" \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$TMP/home/none" \
    bash "$1/scripts/init-bundle.sh" "$2" </dev/null >"$TMP/out" 2>&1
}
R1="Bash($MK/*/scripts/*)"; R2="Bash(bash $MK/*/scripts/*)"
has() { grep -cF "\"$1\"" "$2" | tr -d ' '; }
json() { python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$1"; }
PY=$(command -v python3 >/dev/null 2>&1 && echo yes || echo no)

echo "== 1. a bundle with no settings.local.json gets both rules =="
I="$TMP/i1"; git init -q "$I"; stamp "$MK/9.9.9" "$I"; rc=$?
L="$I/.claude/settings.local.json"
ok "stamp exits 0" "$rc" 0
ok "settings.local.json written" "$(yn test -f "$L")" yes
ok "plain rule present once" "$(has "$R1" "$L")" 1
ok "bash-prefixed twin present once" "$(has "$R2" "$L")" 1
[ "$PY" = no ] || ok "the file parses as JSON" "$(yn json "$L")" yes
ok "the stamp says it wrote them" "$(grep -c 'wrote script allowlist' "$TMP/out" | tr -d ' ')" 1
ok "the file is gitignored in the bundle" "$(yn git -C "$I" check-ignore -q --no-index .claude/settings.local.json)" yes

echo "== 2. a second stamp adds nothing =="
cp "$L" "$TMP/before"; stamp "$MK/9.9.9" "$I"
ok "file byte-identical after re-stamp" "$(yn cmp -s "$TMP/before" "$L")" yes
ok "the stamp says keep" "$(grep -c 'keep  script allowlist' "$TMP/out" | tr -d ' ')" 1

echo "== 3. an operator's file is extended, never replaced =="
I="$TMP/i3"; mkdir -p "$I/.claude"; L="$I/.claude/settings.local.json"
cat > "$L" <<EOF
{
  "permissions": {
    "allow": [
      "Bash($MK/*/scripts/*.sh:*)",
      "Bash(git status)"
    ],
    "deny": []
  }
}
EOF
stamp "$MK/9.9.9" "$I"
ok "plain rule added" "$(has "$R1" "$L")" 1
ok "twin added" "$(has "$R2" "$L")" 1
ok "the operator's entry is kept" "$(grep -cF '"Bash(git status)"' "$L" | tr -d ' ')" 1
[ "$PY" = no ] || ok "the extended file parses as JSON" "$(yn json "$L")" yes
ok "the dead *.sh:* rule is reported" "$(grep -c 'matches nothing' "$TMP/out" | tr -d ' ')" 1

echo "== 4. a shape it cannot edit is left byte-identical and reported =="
I="$TMP/i4"; mkdir -p "$I/.claude"; L="$I/.claude/settings.local.json"
printf '{ "permissions": { "allow": [] } }\n' > "$L"; cp "$L" "$TMP/before"
stamp "$MK/9.9.9" "$I"
ok "one-line allow array untouched" "$(yn cmp -s "$TMP/before" "$L")" yes
ok "…and the rules are printed to add by hand" "$(grep -cF "$R1" "$TMP/out" | tr -d ' ')" 1
ok "no temp file left behind" "$(ls "$I/.claude" | grep -c 'allow\.' | tr -d ' ')" 0

echo "== 5. only a plugin-cache install writes a rule =="
I="$TMP/i5"; mkdir -p "$I"; stamp "$TMP/checkout/plugin" "$I"
ok "a checkout stamp writes no settings.local.json" "$(yn test -f "$I/.claude/settings.local.json")" no
ok "…and says it skipped" "$(grep -c 'skip  script allowlist' "$TMP/out" | tr -d ' ')" 1

echo "== 6. the shipped rules grant no spawn and no bypass =="
ok "no claude --bg / bypassPermissions in what init writes" \
  "$(grep -cE 'claude --bg|bypassPermissions' "$TMP/i1/.claude/settings.local.json" | tr -d ' ')" 0
ok "the version is the only wildcard besides the script" \
  "$(grep -oF "$TMP/home/.claude/plugins/cache/mk/${PN}/*/scripts/*)" "$TMP/i1/.claude/settings.local.json" | wc -l | tr -d ' ')" 2

echo "== 7. a multi-line EMPTY allow array is filled, valid, with python3 unavailable =="
# No python3 means init's JSON check is skipped, so a malformed rewrite would replace a good
# settings.local.json unchecked. That is what makes this shape a data-integrity case.
NOPY="$TMP/nopy"; mkdir -p "$NOPY"
( IFS=:; for d in $PATH; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
      n="${f##*/}"; case "$n" in python3*) continue ;; esac
      [ -x "$f" ] && [ ! -e "$NOPY/$n" ] && ln -s "$f" "$NOPY/$n"
    done
  done ) 2>/dev/null
ok "no python3 on the fixture PATH" "$( (PATH="$NOPY"; yn command -v python3) )" no
n7=0
for blank in "blank line after [" "no blank line"; do
  n7=$((n7+1)); I="$TMP/i7-$n7"; mkdir -p "$I/.claude"; L="$I/.claude/settings.local.json"
  if [ "$blank" = "no blank line" ]; then
    printf '{\n  "permissions": {\n    "allow": [\n    ],\n    "deny": []\n  }\n}\n' > "$L"
  else
    printf '{\n  "permissions": {\n    "allow": [\n\n    ]\n  }\n}\n' > "$L"
  fi
  stamp "$MK/9.9.9" "$I" "$STUB:$NOPY"; rc=$?
  ok "stamp exits 0 ($blank)" "$rc" 0
  ok "plain rule present once ($blank)" "$(has "$R1" "$L")" 1
  ok "twin present once ($blank)" "$(has "$R2" "$L")" 1
  ok "only the non-last entry keeps its comma ($blank)" "$(grep -c '",$' "$L" | tr -d ' ')" 1
  [ "$PY" = no ] || ok "the filled file parses as JSON ($blank)" "$(yn json "$L")" yes
done

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
