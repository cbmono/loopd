#!/usr/bin/env bash
#
# statusline-install.test.sh — `/<plugin>:init` puts the status line in the BUNDLE's own
# `.claude/settings.json` and never in the user's. ai-bridge-v3/task-025.
#
# WHY THE BUNDLE'S FILE. Project settings are seed content init already owns, so the
# install is scoped to the bundle and touches nothing under `${CLAUDE_CONFIG_DIR:-~/.claude}`.
# The user-settings offer the criterion originally carried would have declined itself on
# any machine that already has a `statusLine` — which is the owner's own machine.
#
# THE PROPERTIES:
#   1. A FRESH STAMP gets the key, as valid JSON, with a `refreshInterval` and a command
#      pointing at the seeded shim inside the bundle.
#   2. AN ALREADY-STAMPED BUNDLE gets it too — the seed copy is copy-if-absent, so a
#      re-stamp is the ONLY path by which an existing bundle can ever receive it.
#   3. AN EXISTING `statusLine` IS NOT REPLACED, silently or otherwise.
#   4. THE USER'S FILE IS BYTE-UNCHANGED, and when it carries a `statusLine` of its own the
#      stamp SAYS that the project key shadows it. Shadowing is not the same as clobbering,
#      and a human who is not told cannot tell the difference.
#   5. THE SHIM RESOLVES THE PLUGIN AT RUN TIME and degrades to silence when it cannot.
# Exit: 0 clean, 1 an assertion failed, 2 the fixture could not be built.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/tools/plugin-name.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/slinstall.XXXXXX")" || {
  echo "statusline-install.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}" >&2; exit 2; }
TMP="$(cd "$TMP" && pwd)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }

command -v python3 >/dev/null 2>&1 || {
  echo "statusline-install.test: python3 absent — every assertion here reads JSON." >&2
  echo "pass=0 fail=0"; exit 0; }

# A plain-directory copy of the template: init-bundle.sh reads `plugin/seed/`, and a
# harness that stamped from this checkout would stamp from a git worktree.
TPL="$TMP/tpl"; mkdir -p "$TPL"
( cd "$REPO" && git ls-files . ) | while IFS= read -r f; do
  [ -n "$f" ] || continue
  mkdir -p "$TPL/$(dirname "$f")"; cp "$REPO/$f" "$TPL/$f" 2>/dev/null || true
done
chmod +x "$TPL"/plugin/scripts/*.sh "$TPL"/plugin/seed/.claude/*.sh 2>/dev/null || true
INIT="$TPL/plugin/scripts/init-bundle.sh"
[ -f "$INIT" ] || { echo "statusline-install.test: missing $INIT" >&2; exit 2; }

STUB="$TMP/bin"; mkdir -p "$STUB"; printf '#!/bin/sh\nexit 1\n' > "$STUB/gh"; chmod +x "$STUB/gh"
HOMEDIR="$TMP/home"; mkdir -p "$HOMEDIR/.claude"
stamp() { # <instance>
  PATH="$STUB:$PATH" HOME="$HOMEDIR" XDG_CONFIG_HOME="$HOMEDIR" \
    env -u CLAUDE_CONFIG_DIR GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$HOMEDIR/none" \
    bash "$INIT" "$1" >"$TMP/out" 2>&1
}
said() { grep -qF -- "$1" "$TMP/out" && echo yes || echo no; }
SET=.claude/settings.json
jq_() { python3 - "$1" "$2" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("unreadable"); raise SystemExit(0)
cur = d
for k in sys.argv[2].split("."):
    if not isinstance(cur, dict) or k not in cur: print("-"); raise SystemExit(0)
    cur = cur[k]
print(cur)
PY
}

echo
echo "-- 1. a fresh stamp: the key lands in the BUNDLE's settings, as valid JSON"
I="$TMP/i1"; mkdir -p "$I"; stamp "$I"
ok "the bundle has project settings"        "$(yn test -f "$I/$SET")" yes
ok "…which still parse as JSON"             "$(yn python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$I/$SET")" yes
ok "statusLine.type is command"             "$(jq_ "$I/$SET" statusLine.type)" command
ok "…and the command names the seeded shim" \
   "$(jq_ "$I/$SET" statusLine.command)" "bash $I/.claude/loopd-statusline.sh"
ok "…which is really there"                 "$(yn test -f "$I/.claude/loopd-statusline.sh")" yes
ok "a refreshInterval is set"               "$(jq_ "$I/$SET" statusLine.refreshInterval)" 5000
ok "…and the permissions block survived"    "$(yn python3 -c '
import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d["permissions"]["deny"] else 1)' "$I/$SET")" yes
ok "…and the stamp said so"                 "$(said 'wrote statusLine into .claude/settings.json')" yes

echo
echo "-- 2. the command carries NO version-scoped plugin path (it would rot on upgrade)"
ok "no plugins/cache path in settings.json" "$(grep -c 'plugins/cache' "$I/$SET" | tr -d ' ')" 0
ok "…the shim is what resolves it"          \
   "$(grep -c 'plugins/cache' "$I/.claude/loopd-statusline.sh" | tr -d ' ')" 1

echo
echo "-- 3. an ALREADY-STAMPED bundle receives it — the only path there is"
I2="$TMP/i2"; mkdir -p "$I2/.claude"
python3 - "$I2/$SET" <<'PY'
import json, sys
json.dump({"permissions": {"deny": ["Bash(rm -rf /)"]}}, open(sys.argv[1], "w"), indent=2)
PY
stamp "$I2"
ok "the pre-existing settings gained the key" "$(jq_ "$I2/$SET" statusLine.type)" command
ok "…and still parse"                         "$(yn python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$I2/$SET")" yes
ok "…and kept what was already there"         "$(yn python3 -c '
import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d["permissions"]["deny"] else 1)' "$I2/$SET")" yes

echo
echo "-- 4. an EXISTING statusLine is never replaced"
I3="$TMP/i3"; mkdir -p "$I3/.claude"
python3 - "$I3/$SET" <<'PY'
import json, sys
json.dump({"statusLine": {"type": "command", "command": "/usr/local/bin/mine.sh"}},
          open(sys.argv[1], "w"), indent=2)
PY
stamp "$I3"
ok "the human's own command is untouched"   "$(jq_ "$I3/$SET" statusLine.command)" /usr/local/bin/mine.sh
ok "…and the stamp says it kept it"         "$(said 'keep  statusLine')" yes
ok "…and no second block was inserted"      "$(grep -c '"statusLine"' "$I3/$SET" | tr -d ' ')" 1

echo
echo "-- 5. the USER's settings file is never written, and shadowing is announced"
printf '%s\n' '{"statusLine": {"type": "command", "command": "~/.claude/ai-setup.sh"}}' \
  > "$HOMEDIR/.claude/settings.json"
BEFORE="$(cksum < "$HOMEDIR/.claude/settings.json")"
I4="$TMP/i4"; mkdir -p "$I4"; stamp "$I4"
ok "the user's settings.json is byte-unchanged" "$(cksum < "$HOMEDIR/.claude/settings.json")" "$BEFORE"
ok "…and the stamp NAMES the shadowing"         "$(said 'this shadows the statusLine in')" yes
ok "…and names the file it shadows"             "$(said "$HOMEDIR/.claude/settings.json")" yes
ok "…and says how to get theirs back"           "$(said 'drop the block')" yes
rm -f "$HOMEDIR/.claude/settings.json"
I5="$TMP/i5"; mkdir -p "$I5"; stamp "$I5"
ok "no user statusLine ⇒ no shadowing note"    "$(said 'this shadows the statusLine in')" no
ok "…and the key still installs"                "$(jq_ "$I5/$SET" statusLine.type)" command

echo
echo "-- 6. a settings.json shaped otherwise is REPORTED, never rewritten by a guess"
I6="$TMP/i6"; mkdir -p "$I6/.claude"
printf '{ "permissions": {} }\n' > "$I6/$SET"      # opens with `{` and content on one line
BEFORE6="$(cksum < "$I6/$SET")"
stamp "$I6"
ok "the file is left exactly as it was"     "$(cksum < "$I6/$SET")" "$BEFORE6"
ok "…and the stamp says why and how"        "$(said 'statusLine not installed')" yes
ok "…naming the key a human would paste"    "$(said '"statusLine": {"type": "command"')" yes

echo
echo "-- 7. the shim: resolves at run time, and is silent when it cannot"
SHIM="$I/.claude/loopd-statusline.sh"
EMPTY="$TMP/nohome"; mkdir -p "$EMPTY"
out="$(CLAUDE_CONFIG_DIR="$EMPTY" bash "$SHIM" </dev/null 2>&1; echo "rc=$?")"
ok "no plugin cache ⇒ no output"            "${out%rc=*}" ""
ok "…and exit 0, never a broken status line" "${out##*rc=}" 0
CACHE="$TMP/fakehome/plugins/cache/mk/${PN}"
mkdir -p "$CACHE/2.2.9/scripts" "$CACHE/2.2.10/scripts"
printf '#!/usr/bin/env bash\necho "OLD $*"\n' > "$CACHE/2.2.9/scripts/status-line.sh"
printf '#!/usr/bin/env bash\necho "NEW $*"\n' > "$CACHE/2.2.10/scripts/status-line.sh"
got="$(CLAUDE_CONFIG_DIR="$TMP/fakehome" bash "$SHIM" </dev/null 2>/dev/null)"
ok "it picks 2.2.10 over 2.2.9 (version sort, not lexical)" "${got%% *}" NEW
ok "…and hands the script THIS bundle"      "$got" "NEW --instance $I"

echo
echo "-- 8. the wiring the criterion names, in the files that carry it"
ok "the seed ships the shim"                "$(yn test -f "$REPO/plugin/seed/.claude/loopd-statusline.sh")" yes
ok "the renderer ships beside the scripts"  "$(yn test -x "$REPO/plugin/scripts/status-line.sh")" yes
ok "init writes PROJECT settings, not \$HOME" \
   "$(grep -c 'SL_SETTINGS="\$TARGET/.claude/settings.json"' "$REPO/plugin/scripts/init-bundle.sh" | tr -d ' ')" 1
ok "…and never writes the user's file"      \
   "$(sed -n '/^# 1d\./,/^# 2\. RETIRE/p' "$REPO/plugin/scripts/init-bundle.sh" | grep -c '> *"\$sl_user"\|>> *"\$sl_user"' | tr -d ' ')" 0

printf '\npass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
