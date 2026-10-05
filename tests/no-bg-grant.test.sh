#!/usr/bin/env bash
#
# no-bg-grant.test.sh — no code path in the plugin writes a `claude --bg` grant.
# plugin/scripts/init-bundle.sh prints a NOTICE naming the rule and leaves writing it to the
# operator; no shipped settings template, manifest or script carries one. A plugin must not
# grant itself a permissions bypass (owner, 2026-09-25 and 2026-09-30). Reasoning: task-019,
# and docs/operations.md -> "The supported shape" (plugin/tick-steps/step-3-dispatch.md).
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/tools/plugin-name.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/nobggrant.XXXXXX")" || {
  echo "no-bg-grant.test: mktemp -d failed" >&2; exit 2; }
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }
cnt() { grep -c "$@" 2>/dev/null | tr -d ' '; }

copy_plugin() {
  ( cd "$REPO/plugin" && git ls-files . ) | while IFS= read -r f; do
    mkdir -p "$1/$(dirname "$f")"; cp "$REPO/plugin/$f" "$1/$f"
  done
  chmod +x "$1"/scripts/*.sh
}
MK="$TMP/home/.claude/plugins/cache/mk/${PN}/9.9.9"
copy_plugin "$MK"; copy_plugin "$TMP/checkout/plugin"
STUB="$TMP/bin"; mkdir -p "$STUB"; printf '#!/bin/sh\nexit 1\n' > "$STUB/gh"; chmod +x "$STUB/gh"
stamp() { # <plugin root> <instance>
  PATH="$STUB:$PATH" HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home" \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$TMP/home/none" \
    bash "$1/scripts/init-bundle.sh" "$2" </dev/null >"$TMP/out" 2>&1
}
RULE="Bash(claude --bg * --agent ${PN}:* --permission-mode auto --add-dir *)"
OLD_RULE="Bash(claude --bg * --agent ${PN}:* --permission-mode bypassPermissions --add-dir *)"
INERT="Bash(claude --bg ' *)"
grants() { # <instance> -> count of claude allow entries across every settings file it has
  cat "$1"/.claude/*.json 2>/dev/null | grep -cE '"Bash\(claude[ :]' | tr -d ' '
}

echo "== 1. a fresh stamp writes no grant, and says whose it is =="
I="$TMP/i1"; git init -q "$I"; stamp "$MK" "$I"; rc=$?
ok "stamp exits 0" "$rc" 0
ok "no claude allow entry in any .claude/*.json" "$(grants "$I")" 0
ok "the notice names the narrowest measured rule" "$(cnt -F "$RULE" "$TMP/out")" 1
ok "the notice says init writes none" "$(cnt -F 'init writes no `claude --bg` grant' "$TMP/out")" 1
ok "the notice says writing it is the operator's" "$(cnt -F "is yours, not the plugin's" "$TMP/out")" 1

echo "== 2. the inert single-quote rule is reported, left alone, and not 'fixed' =="
I="$TMP/i2"; mkdir -p "$I/.claude"; L="$I/.claude/settings.local.json"
printf '{\n  "permissions": {\n    "allow": [\n      "%s"\n    ]\n  }\n}\n' "$INERT" > "$L"
stamp "$MK" "$I"
ok "the operator's rule is kept, once" "$(cnt -F "\"$INERT\"" "$L")" 1
ok "no other claude allow entry was added" "$(grants "$I")" 1
ok "it is reported as matching no measured spawn form" "$(cnt -F 'matches no spawn form measured' "$TMP/out")" 1

echo "== 3. an operator's own working rule is not second-guessed =="
I="$TMP/i3"; mkdir -p "$I/.claude"; L="$I/.claude/settings.local.json"
printf '{\n  "permissions": {\n    "allow": [\n      "%s"\n    ]\n  }\n}\n' "$RULE" > "$L"
stamp "$MK" "$I"
ok "still exactly one claude allow entry" "$(grants "$I")" 1
ok "no notice printed" "$(cnt -F 'claude --bg' "$TMP/out")" 0

echo "== 3b. a grant from before 3.3 names bypassPermissions: reported as matching nothing, left alone =="
I="$TMP/i3b"; mkdir -p "$I/.claude"; L="$I/.claude/settings.local.json"
printf '{\n  "permissions": {\n    "allow": [\n      "%s"\n    ]\n  }\n}\n' "$OLD_RULE" > "$L"
stamp "$MK" "$I"
ok "the operator's old rule is kept, once" "$(cnt -F "\"$OLD_RULE\"" "$L")" 1
ok "no other claude allow entry was added" "$(grants "$I")" 1
ok "it is told the tick spawns in auto mode now" "$(cnt -F 'the tick spawns in auto mode now' "$TMP/out")" 1
ok "…and shown the rule that matches" "$(cnt -F "$RULE" "$TMP/out")" 1

echo "== 4. a checkout stamp writes no grant either =="
I="$TMP/i4"; mkdir -p "$I"; stamp "$TMP/checkout/plugin" "$I"
ok "no claude allow entry" "$(grants "$I")" 0
ok "the notice still prints" "$(cnt -F "$RULE" "$TMP/out")" 1

echo "== 5. no shipped surface carries a claude grant =="
cd "$REPO" || exit 2
SURF="$(git ls-files plugin 'plugin-*' config install.sh upgrade.sh)"
json_hits=0
if command -v python3 >/dev/null 2>&1; then
  json_hits="$(printf '%s\n' "$SURF" | grep '\.json$' | python3 -c '
import json, sys
hits = 0
def walk(v, under):
    global hits
    if isinstance(v, dict):
        for k, x in v.items(): walk(x, under or k in ("allow", "autoMode"))
    elif isinstance(v, list):
        for x in v: walk(x, under)
    elif isinstance(v, str) and under and "claude" in v.lower() and v.startswith("Bash("):
        hits += 1
for p in sys.stdin.read().split():
    walk(json.load(open(p)), False)
print(hits)')"
fi
ok "no shipped JSON allows a claude command" "$json_hits" 0
# Outside markdown, `Bash(claude` may only appear in a line that prints it.
code_hits="$(printf '%s\n' "$SURF" | grep -v '\.md$' | while IFS= read -r f; do
  grep -nF 'Bash(claude' "$f" | grep -vE '^[0-9]+:[[:space:]]*(echo|printf|#|BG_RULE=|BG_INERT=|BG_OLD=)' | sed "s|^|$f:|"
done)"
[ -z "$code_hits" ] || printf '%s\n' "$code_hits" | sed 's/^/        /'
ok "no script line writes a claude rule" "$(printf '%s' "$code_hits" | grep -c . | tr -d ' ')" 0

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
