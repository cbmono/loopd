#!/usr/bin/env bash
#
# init-script-allowlist.test.sh — plugin/scripts/init-bundle.sh writes the two
# version-wild script rules into .claude/settings.local.json, once, and fails closed on a
# shape it cannot edit; from a plugin root with whitespace, one exact-version rule per
# read-only script on the space-free real path instead (§8-§14). The plugin is copied to a
# cache-shaped path under a fixture HOME, because the rule is derived from where the running
# init lives. Reasoning: task-016.
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

SPD="$TMP/home/Library/Application Support/profile"; mkdir -p "$SPD"
ln -s "$TMP/home/.claude/plugins" "$SPD/plugins"
SP="$SPD/plugins/cache/mk/${PN}"
LIST="$MK/9.9.9/data/script-classes.txt"
RO="$(awk '$2 == "read-only" { print $1 }' "$LIST")"; WR="$(awk '$2 == "writing" { print $1 }' "$LIST")"
rule() { printf 'Bash(%s/%s/scripts/%s *)' "$MK" "$1" "$2"; }
allow() { python3 -c 'import json,sys; [print(a) for a in json.load(open(sys.argv[1]))["permissions"]["allow"]]' "$1"; }
mkfile() { # <file> <rule>... -> a settings.local.json allowing exactly those rules
  mkdir -p "$(dirname "$1")"; f="$1"; shift
  python3 -c 'import json,sys; json.dump({"permissions": {"allow": sys.argv[2:]}}, open(sys.argv[1], "w"), indent=2)' "$f" "$@"
}
HAND1='Bash(git status)'; HAND2="Bash($MK/9.9.8/scripts/bundle-paths.sh)"
HAND3="Bash($TMP/home/.claude/plugins/cache/other/${PN}/*/scripts/*)"
OLD_SP1="Bash($SP/*/scripts/*)"; OLD_SP2="Bash(bash $SP/*/scripts/*)"
OLD_MK2="Bash(bash $MK/*/scripts/*)"; OLD_V="$(rule 9.9.8 bundle-paths.sh)"; OLD_W="$(rule 9.9.8 commit-as.sh)"

if [ "$PY" = no ]; then echo "  SKIP  §8-§14 need python3 to read the fixture JSON"; else
echo "== 8. a whitespace root writes one exact-version rule per read-only script =="
ok "the fixture root holds a space and links to the cache" "$(cd "$SP/9.9.9" && pwd -P)" "$MK/9.9.9"
I="$TMP/i8"; git init -q "$I"; stamp "$SP/9.9.9" "$I"; rc=$?; L="$I/.claude/settings.local.json"
ok "stamp exits 0" "$rc" 0
ok "the file parses as JSON" "$(yn json "$L")" yes
ok "one rule per read-only entry, nothing else" "$(allow "$L" | sort | cksum)" \
  "$(printf '%s\n' "$RO" | while read -r n; do rule 9.9.9 "$n"; echo; done | sort | cksum)"
ok "…and the list has read-only entries to write" "$([ "$(printf '%s\n' "$RO" | grep -c .)" -gt 10 ] && echo yes)" yes
ok "merge-queue.sh gets the literal measured rule" "$(allow "$L" | grep -cxF "Bash($MK/9.9.9/scripts/merge-queue.sh *)")" 1
ok "no rule names the spaced path" "$(grep -cF "$SPD" "$L" | tr -d ' ')" 0
ok "no bash-prefixed twin and no wildcard version" "$(allow "$L" | grep -cE '^Bash\(bash |/\*/scripts/')" 0
ok "0 rules for any writing entry" "$(printf '%s\n' "$WR" | while read -r n; do allow "$L" | grep -F "/scripts/$n " ; done | grep -c .)" 0
for n in commit-as.sh reclaim-worktree.sh release-bump.sh; do
  ok "$n is classed writing and has no rule" "$(grep -c "^$n writing" "$LIST")/$(allow "$L" | grep -cF "/$n")" 1/0
done

echo "== 9. a second stamp is a no-op =="
cp "$L" "$TMP/before"; stamp "$SP/9.9.9" "$I"
ok "file byte-identical" "$(yn cmp -s "$TMP/before" "$L")" yes
ok "the stamp says keep" "$(grep -c 'keep  script allowlist' "$TMP/out" | tr -d ' ')" 1

echo "== 10. a re-stamp removes only the rules this writer wrote =="
I="$TMP/i10"; L="$I/.claude/settings.local.json"
mkfile "$L" "$HAND1" "$OLD_SP1" "$OLD_SP2" "$R1" "$OLD_MK2" "$OLD_V" "$HAND2" "$HAND3" "$OLD_W"
stamp "$SP/9.9.9" "$I"
for r in "$OLD_SP1" "$OLD_SP2" "$R1" "$OLD_MK2" "$OLD_V" "$OLD_W"; do
  ok "removed: ${r#"$TMP"}" "$(allow "$L" | grep -cxF -- "$r")" 0
done
for r in "$HAND1" "$HAND2" "$HAND3"; do
  ok "kept byte-identical: ${r#"$TMP"}" "$(grep -cF "\"$r\"" "$L" | tr -d ' ')" 1
done
ok "every read-only rule written" "$(allow "$L" | grep -cF "$MK/9.9.9/scripts/")" "$(printf '%s\n' "$RO" | grep -c .)"
ok "the stamp names each removal" "$(grep -c '^  removed ' "$TMP/out" | tr -d ' ')" 6

echo "== 11. a stamp from an older plugin root never replaces newer rules =="
I="$TMP/i11"; L="$I/.claude/settings.local.json"
mkfile "$L" "$(rule 9.10.0 merge-queue.sh)" "$OLD_SP1"; cp "$L" "$TMP/before"
stamp "$SP/9.9.9" "$I"
ok "9.10.0 is newer than 9.9.9: file byte-identical" "$(yn cmp -s "$TMP/before" "$L")" yes
mkfile "$L" "$(rule 9.10.0 commit-as.sh)" "$OLD_SP1"; cp "$L" "$TMP/before"
stamp "$SP/9.9.9" "$I"
ok "…a newer rule for any script name holds it too" "$(yn cmp -s "$TMP/before" "$L")" yes
ok "…and the stamp says why" "$(grep -c 'names a newer' "$TMP/out" | tr -d ' ')" 1

echo "== 12. neither python3 nor jq: skip with a warning =="
NOPJ="$TMP/nopj"; mkdir -p "$NOPJ"
for f in "$NOPY"/*; do [ "${f##*/}" = jq ] || ln -s "$(readlink "$f")" "$NOPJ/${f##*/}"; done
I="$TMP/i12"; L="$I/.claude/settings.local.json"; mkfile "$L" "$OLD_SP1" "$OLD_SP2"; cp "$L" "$TMP/before"
stamp "$SP/9.9.9" "$I" "$STUB:$NOPJ"
ok "no python3 or jq on the fixture PATH" "$( (PATH="$NOPJ"; command -v python3 jq | grep -c .) )" 0
ok "file byte-identical" "$(yn cmp -s "$TMP/before" "$L")" yes
ok "…and a warning names the missing tools" "$(grep -c 'needs python3 or jq' "$TMP/out" | tr -d ' ')" 1

echo "== 13. a bad list keeps the old rules and warns =="
cp "$LIST" "$TMP/list"
n13=0
for bad in missing empty unparseable "names a missing script"; do
  n13=$((n13+1)); cp "$TMP/list" "$LIST"
  case "$bad" in
    missing) rm "$LIST" ;;
    empty) : > "$LIST" ;;
    unparseable) printf 'bundle-paths.sh maybe\n' >> "$LIST" ;;
    *) printf 'gone.sh read-only\n' >> "$LIST" ;;
  esac
  I="$TMP/i13-$n13"; L="$I/.claude/settings.local.json"; mkfile "$L" "$OLD_SP1" "$OLD_SP2"; cp "$L" "$TMP/before"
  stamp "$SP/9.9.9" "$I"
  ok "list $bad: old rules kept, file byte-identical" "$(yn cmp -s "$TMP/before" "$L")" yes
  ok "list $bad: a warning is printed" "$(grep -c 'script-classes.txt is missing, empty' "$TMP/out" | tr -d ' ')" 1
done
cp "$TMP/list" "$LIST"

echo "== 14. a real path that needs quoting or holds a rule wildcard writes no rule and names it =="
n14=0
NL="$(printf '\nx')"; NL="${NL%x}"
for d in "sp ace" 'do$llar' "apo'strophe" 'amp&ersand' 'semi;colon' 'ha#sh' "$(printf 'ta\tb')" "new${NL}line" \
         'st*ar' 'qu?ery' 'br[ack]et'; do
  n14=$((n14+1)); R="$TMP/m$n14/$d/plugins/cache/mk/${PN}/9.9.9"; mkdir -p "${R%/*}"; cp -R "$MK/9.9.9" "$R"
  ln -s "$R" "$TMP/m$n14/Application Support"
  I="$TMP/i14-$n14"; mkdir -p "$I"; stamp "$TMP/m$n14/Application Support" "$I"
  ok "real path with ${d%%[[:space:]]*}…: no settings.local.json" "$(yn test -f "$I/.claude/settings.local.json")" no
  ok "real path with ${d%%[[:space:]]*}…: the warning names it" "$(grep -cF -- "\`${R%%"$NL"*}" "$TMP/out" | tr -d ' ')/$(grep -c 'holds whitespace, a shell metacharacter or a rule wildcard' "$TMP/out" | tr -d ' ')" 1/1
done

echo "== 15. a settings file that cannot be read is never replaced =="
for via in "python3" "jq only"; do
  if [ "$via" = "jq only" ] && ! (PATH="$STUB:$NOPY"; command -v jq >/dev/null 2>&1); then
    echo "  SKIP  no jq on this machine"; continue; fi
  I="$TMP/i15-${via% *}"; L="$I/.claude/settings.local.json"; mkfile "$L" "$OLD_SP1" "$HAND1"; cp "$L" "$TMP/before"
  chmod 000 "$L"
  if cat "$L" >/dev/null 2>&1; then chmod 644 "$L"; echo "  SKIP  a mode-000 file is readable here (root)"; continue; fi
  if [ "$via" = python3 ]; then stamp "$SP/9.9.9" "$I"; else stamp "$SP/9.9.9" "$I" "$STUB:$NOPY"; fi
  chmod 644 "$L"
  ok "unreadable, $via: file byte-identical" "$(yn cmp -s "$TMP/before" "$L")" yes
  ok "unreadable, $via: the stamp warns" "$(grep -c 'script allowlist not written: no safe edit' "$TMP/out" | tr -d ' ')" 1
done
fi

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
