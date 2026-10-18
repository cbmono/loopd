#!/usr/bin/env bash
#
# no-bg-grant.test.sh — the `claude --bg` grant is written by exactly one path, a human's
# yes, and by nothing else in the plugin.
#
# Two halves, and the first is the one that used to be the whole file. A plugin must not
# grant itself a permissions bypass (owner, 2026-09-25 and 2026-09-30), so no shipped
# settings template, manifest or script carries a grant, and a stamp with no terminal
# writes none: it prints the rule. The second half is the owner's decision of 2026-10-09
# ("let loopd:init ask during installation with Y as default"), after the second human on
# a shared bundle edited this JSON by hand with two stale grants already in it: at a
# terminal the stamp ASKS, Enter is yes, `n` leaves the file alone, the stale shapes are
# named and replaced on that same yes, an existing rule is never duplicated, and a
# workspace-trust key is still never written anywhere. Reasoning: task-019 and
# docs/operations.md -> "The supported shape" (plugin/tick-steps/step-3-dispatch.md).
#
# BG_GRANT_STDIN=1 is how a piped answer reaches a prompt that is otherwise TTY-only — the
# role TEAM_SETUP_STDIN plays for the roster in team-setup.test.sh, reused exactly.
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
stamp() { # <plugin root> <instance> [flags…] — stdin is /dev/null: no terminal
  local p="$1" i="$2"; shift 2
  PATH="$STUB:$PATH" HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home" \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$TMP/home/none" \
    bash "$p/scripts/init-bundle.sh" "$i" "$@" </dev/null >"$TMP/out" 2>&1
}
tty_stamp() { # <answer> <instance> — the answer piped, the TTY test forced open
  PATH="$STUB:$PATH" HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home" \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$TMP/home/none" BG_GRANT_STDIN=1 \
    bash "$MK/scripts/init-bundle.sh" "$2" <<<"$1" >"$TMP/out" 2>&1
}
ROLES="software-engineer devops-engineer qa-reviewer cataloguer"
rules() { # <instance> -> the spawn rule for each role, one per line
  for r in $ROLES; do printf 'Bash(claude --bg --agent %s:%s --permission-mode auto --add-dir %s --model *)\n' "$PN" "$r" "$1"; done
}
set_rules() { # <instance> -> RULES (array), RULE (the first) and PROMPT, for that bundle
  RULES=(); while IFS= read -r l; do RULES+=("$l"); done < <(rules "$1"); RULE="${RULES[0]}"
  PROMPT="Write $(printf '"%s" and ' "${RULES[@]}" "$RESUME")\"$STOP\" to .claude/settings.local.json so the tick can start and stop role agents without a prompt? [Y/n]"
}
N=6   # four spawn rules, the resume rule and the stop rule
AUTO_RULE="Bash(claude --bg * --agent ${PN}:* --permission-mode auto --add-dir *)"
NEAR_RULE="Bash(claude --bg * --agent ${PN}:* --permission-mode auto --add-dir /*)"
OLD_RULE="Bash(claude --bg * --agent ${PN}:* --permission-mode bypassPermissions --add-dir *)"
BROAD="Bash(claude --bg *)"
NS_RULE="Bash(claude --bg * --agent old-plugin:* --permission-mode auto --add-dir *)"
INERT="Bash(claude --bg ' *)"
RESUME="Bash(claude --bg --resume *)"
STOP="Bash(claude stop *)"
REST_PROMPT="Write \"$RESUME\" and \"$STOP\" to .claude/settings.local.json so the tick can start and stop role agents without a prompt? [Y/n]"
grants() { # <instance> -> count of claude allow entries across every settings file it has
  cat "$1"/.claude/*.json 2>/dev/null | grep -cE '"Bash\(claude[ :]' | tr -d ' '
}
with_rules() { # <instance> <rule>… -> a settings.local.json holding exactly those
  local i="$1"; shift; mkdir -p "$i/.claude"
  { printf '{\n  "permissions": {\n    "allow": [\n'
    local first=1; for r in "$@"; do [ "$first" = 1 ] || printf ',\n'; printf '      "%s"' "$r"; first=0; done
    printf '\n    ]\n  }\n}\n'; } > "$i/.claude/settings.local.json"
}
# A trust key lives in ~/.claude.json under projects.<path>; none may appear anywhere.
trust_written() { grep -rl 'hasTrustDialogAccepted' "$TMP/home" "$1" 2>/dev/null | grep -c . | tr -d ' '; }

echo "== 1. no terminal: a fresh stamp writes no grant, and says how to say yes =="
I="$TMP/i1"; git init -q "$I"; set_rules "$I"; stamp "$MK" "$I"; rc=$?
ok "stamp exits 0" "$rc" 0
ok "no claude allow entry in any .claude/*.json" "$(grants "$I")" 0
ok "the notice names one spawn rule per role" "$(rules "$I" | grep -cxF -f - <(sed 's/^ *//' "$TMP/out"))" 4
ok "…and the stop rule" "$(cnt -F "          $STOP" "$TMP/out")" 1
ok "the notice says init writes none without a yes" "$(cnt -F 'init writes no `claude --bg` grant without your yes' "$TMP/out")" 1
ok "…and names both ways to give one" "$(cnt -F 'answer Y when a terminal stamp asks, or re-run with --spawn-grant' "$TMP/out")" 1
ok "no question was printed" "$(cnt -F "$PROMPT" "$TMP/out")" 0
ok "no trust key anywhere" "$(trust_written "$I")" 0
# A piped `y` with the TTY test NOT forced is still "no terminal": nothing asked, nothing written.
I="$TMP/i1b"; mkdir -p "$I"; set_rules "$I"
PATH="$STUB:$PATH" HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$TMP/home/none" \
  bash "$MK/scripts/init-bundle.sh" "$I" <<<"y" >"$TMP/out" 2>&1
ok "a piped y with no terminal writes nothing" "$(grants "$I")" 0
ok "…and asks nothing" "$(cnt -F "$PROMPT" "$TMP/out")" 0

echo "== 2. the inert single-quote rule is reported, left alone, and not 'fixed' =="
I="$TMP/i2"; with_rules "$I" "$INERT"; L="$I/.claude/settings.local.json"
stamp "$MK" "$I"
ok "the operator's rule is kept, once" "$(cnt -F "\"$INERT\"" "$L")" 1
ok "no other claude allow entry was added" "$(grants "$I")" 1
ok "it is reported as matching no measured spawn form" "$(cnt -F 'matches no spawn form measured' "$TMP/out")" 1

echo "== 3. an operator's own working rules are not second-guessed =="
I="$TMP/i3"; set_rules "$I"; with_rules "$I" "${RULES[@]}" "$RESUME" "$STOP"; L="$I/.claude/settings.local.json"
stamp "$MK" "$I"
ok "still exactly the six claude allow entries" "$(grants "$I")" "$N"
ok "no notice printed" "$(cnt -F 'claude --bg' "$TMP/out")" 0
BEFORE="$(cat "$L")"   # after the first stamp: step 1e's script allowlist has landed by now
tty_stamp "" "$I"
ok "…and a terminal stamp asks nothing either" "$(cnt -F "$PROMPT" "$TMP/out")" 0
ok "…leaving the file byte-identical" "$([ "$(cat "$L")" = "$BEFORE" ] && echo yes || echo no)" yes

echo "== 3a. a bundle holding only the spawn rule is asked for the stop rule alone =="
I="$TMP/i3a"; set_rules "$I"; with_rules "$I" "${RULES[@]}"; L="$I/.claude/settings.local.json"
tty_stamp "" "$I"
ok "the question names only the resume and stop rules" "$(cnt -F "$REST_PROMPT" "$TMP/out")" 1
ok "six claude allow entries after the yes" "$(grants "$I")" "$N"
ok "…the spawn rule still once" "$(cnt -F "\"$RULE\"" "$L")" 1
ok "…and the stop rule once" "$(cnt -F "\"$STOP\"" "$L")" 1
tty_stamp "" "$I"
ok "a second stamp asks nothing" "$(cnt -F 'Write "' "$TMP/out")" 0

echo "== 3d. a rule under permissions.deny is never read as a grant, and is reported =="
I="$TMP/i3d"; set_rules "$I"; mkdir -p "$I/.claude"; L="$I/.claude/settings.local.json"
printf '{ "permissions": { "allow": [ %s ], "deny": [ "%s" ] } }\n' "$(printf '"%s",' "${RULES[@]}" | sed 's/,$//')" "$STOP" > "$L"
stamp "$MK" "$I"
ok "the denied stop rule is still missing: the notice names it" "$(cnt -F "          $STOP" "$TMP/out")" 1
ok "…and the conflicting deny is reported" "$(cnt -F "lists \`$STOP\` under permissions.deny" "$TMP/out")" 1
ok "…without a yes, nothing is written" "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["permissions"]["allow"]))' "$L")" 4
tty_stamp "" "$I"
ok "at a terminal it asks for the resume and stop rules" "$(cnt -F "$REST_PROMPT" "$TMP/out")" 1
ok "…the yes lands it under allow, once" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["permissions"]["allow"].count(sys.argv[2]))' "$L" "$STOP")" 1
ok "…leaves the human's deny alone" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["permissions"]["deny"].count(sys.argv[2]))' "$L" "$STOP")" 1
ok "…and still reports it" "$(cnt -F "lists \`$STOP\` under permissions.deny" "$TMP/out")" 1
ok "…no refusal" "$(cnt -F 'spawn grant not written' "$TMP/out")" 0
I="$TMP/i3e"; set_rules "$I"; mkdir -p "$I/.claude"
printf '{ "permissions": { "deny": [ %s, "%s" ] } }\n' "$(printf '"%s",' "${RULES[@]}" | sed 's/,$//')" "$STOP" > "$I/.claude/settings.local.json"
stamp "$MK" "$I"
ok "all denied: all still asked for" "$(cnt -E "^          Bash\(claude (--bg|stop) " "$TMP/out")" "$N"

echo "== 3b. the stale shapes are NAMED, each with why, and left alone without a yes =="
I="$TMP/i3b"; set_rules "$I"; with_rules "$I" "$OLD_RULE" "$BROAD" "$NS_RULE" "$AUTO_RULE" "Bash(ls:*)"; L="$I/.claude/settings.local.json"
stamp "$MK" "$I"
ok "every rule is kept" "$(grants "$I")" 4
ok "bypassPermissions: told the tick spawns in auto mode now" "$(cnt -F "has \`$OLD_RULE\` — stale: the tick spawns in auto mode now" "$TMP/out")" 1
ok "the bare wildcard: told it is over-broad" "$(cnt -F "has \`$BROAD\` — over-broad" "$TMP/out")" 1
ok "the old namespace: told it is retired" "$(cnt -F "has \`$NS_RULE\` — stale: names the retired old-plugin: namespace" "$TMP/out")" 1
ok "the pre-reorder rule: told its mid-rule wildcard approves inserted flags" "$(cnt -F "has \`$AUTO_RULE\` — stale: its * after --bg also approves any flag inserted there" "$TMP/out")" 1
ok "each with the same remove instruction" "$(cnt -F 'Remove it: re-run with --spawn-grant, or edit the file.' "$TMP/out")" 4
ok "…and shown the rule that matches" "$(cnt -F "$RULE" "$TMP/out")" 1

echo "== 4. a checkout stamp writes no grant either =="
I="$TMP/i4"; mkdir -p "$I"; set_rules "$I"; stamp "$TMP/checkout/plugin" "$I"
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
# Outside markdown, `Bash(claude` may only appear in a line that prints it or in one of the
# named constants — the writer reaches the rule through $BG_RULE and nowhere else.
code_hits="$(printf '%s\n' "$SURF" | grep -v '\.md$' | while IFS= read -r f; do
  grep -nF 'Bash(claude' "$f" | grep -vE '^[0-9]+:[[:space:]]*(echo|printf|#|BG_OLD=|BG_INERT=|BG_BROAD=|RESUME_RULE=|STOP_RULE=)' | sed "s|^|$f:|"
done)"
[ -z "$code_hits" ] || printf '%s\n' "$code_hits" | sed 's/^/        /'
ok "no script line spells a claude rule outside the constants" "$(printf '%s' "$code_hits" | grep -c . | tr -d ' ')" 0

echo "== 6. at a terminal, n writes nothing =="
I="$TMP/i6"; mkdir -p "$I"; set_rules "$I"; tty_stamp "n" "$I"; rc=$?
ok "exits 0" "$rc" 0
ok "the question is asked, verbatim" "$(cnt -F "$PROMPT" "$TMP/out")" 1
ok "no claude allow entry" "$(grants "$I")" 0
ok "…and the rule is printed for the human" "$(cnt -F "          $RULE" "$TMP/out")" 1
ok "no trust key anywhere" "$(trust_written "$I")" 0

echo "== 7. at a terminal, Enter is yes: exactly those six rules, and nothing else =="
I="$TMP/i7"; mkdir -p "$I"; set_rules "$I"; tty_stamp "" "$I"; rc=$?
L="$I/.claude/settings.local.json"
ok "exits 0" "$rc" 0
ok "the question is asked, verbatim" "$(cnt -F "$PROMPT" "$TMP/out")" 1
ok "it says what it wrote" "$(cnt -F 'wrote spawn grant into .claude/settings.local.json' "$TMP/out")" 1
ok "exactly six claude allow entries" "$(grants "$I")" "$N"
ok "…one spawn rule per role" "$(rules "$I" | sed 's/.*/"&"/' | grep -cF -f - "$L")" 4
ok "…the resume rule" "$(cnt -F "\"$RESUME\"" "$L")" 1
ok "…and the stop rule" "$(cnt -F "\"$STOP\"" "$L")" 1
ok "each claude rule has one *, at its end, and no quote" "$(python3 -c '
import json,sys
a=[r for r in json.load(open(sys.argv[1]))["permissions"]["allow"] if r.startswith("Bash(claude")]
print(sum(r.count("*")==1 and r.endswith(" *)") and not set("\x27\"`") & set(r) for r in a))' "$L")" "$N"
ok "the file parses as JSON" "$(yn python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$L")" yes
ok "the script allowlist written beside it survives" "$(cnt -F '/scripts/*)"' "$L")" 2
ok "no trust key anywhere" "$(trust_written "$I")" 0
BEFORE="$(cat "$L")"
tty_stamp "" "$I"
ok "a second terminal stamp asks nothing" "$(cnt -F "$PROMPT" "$TMP/out")" 0
ok "…and never duplicates a rule" "$(grants "$I")" "$N"
ok "…byte-identical" "$([ "$(cat "$L")" = "$BEFORE" ] && echo yes || echo no)" yes
I="$TMP/i7y"; mkdir -p "$I"; tty_stamp "y" "$I"
ok "a typed y is the same yes" "$(grants "$I")" "$N"
I="$TMP/i7e"; mkdir -p "$I"; set_rules "$I"; tty_stamp "" "$I"
ok "…and the write lands as the ONLY claude entry on a bare dir" "$(cnt -F "\"$RULE\"" "$I/.claude/settings.local.json")" 1

echo "== 8. the same yes replaces the stale shapes, and keeps everything else =="
I="$TMP/i8"; set_rules "$I"; with_rules "$I" "$OLD_RULE" "$BROAD" "$NS_RULE" "$AUTO_RULE" "$NEAR_RULE" "Bash(ls:*)"; L="$I/.claude/settings.local.json"
tty_stamp "" "$I"
ok "the question listed what would be removed" "$(cnt -F 'would be REMOVED' "$TMP/out")" 1
ok "…naming all four" "$(cnt -E "^    - Bash\(claude --bg .*\((over-broad|stale)" "$TMP/out")" 4
ok "the six rules and the near-miss remain" "$(grants "$I")" $((N + 1))
ok "…the measured rule" "$(cnt -F "\"$RULE\"" "$L")" 1
ok "the bypass rule is gone" "$(cnt -F "\"$OLD_RULE\"" "$L")" 0
ok "the bare wildcard is gone" "$(cnt -F "\"$BROAD\"" "$L")" 0
ok "the old namespace is gone" "$(cnt -F "\"$NS_RULE\"" "$L")" 0
ok "the pre-reorder auto rule is gone" "$(cnt -F "\"$AUTO_RULE\"" "$L")" 0
ok "…a rule one character away from it is kept" "$(cnt -F "\"$NEAR_RULE\"" "$L")" 1
ok "the unrelated rule is kept" "$(cnt -F '"Bash(ls:*)"' "$L")" 1
ok "each removal is reported" "$(cnt -E '^  removed Bash\(claude --bg ' "$TMP/out")" 4
ok "the file parses as JSON" "$(yn python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$L")" yes

echo "== 9. --spawn-grant is the yes a session relays: no terminal, no question, one write =="
I="$TMP/i9"; set_rules "$I"; with_rules "$I" "$BROAD"; L="$I/.claude/settings.local.json"
stamp "$MK" "$I" --spawn-grant; rc=$?
ok "exits 0" "$rc" 0
ok "no question was printed" "$(cnt -F "$PROMPT" "$TMP/out")" 0
ok "exactly six claude allow entries" "$(grants "$I")" "$N"
ok "…the measured rule" "$(cnt -F "\"$RULE\"" "$L")" 1
ok "…and the over-broad one was removed" "$(cnt -F "\"$BROAD\"" "$L")" 0
bash "$MK/scripts/init-bundle.sh" --help >"$TMP/help" 2>&1
ok "the flag is in --help" "$(yn grep -q -- '--spawn-grant' "$TMP/help")" yes
ok "…which is still not truncated" "$(yn grep -q 'Backs up any conflicting real file' "$TMP/help")" yes

echo "== 10. a file this cannot read safely is never rewritten =="
I="$TMP/i10"; set_rules "$I"; mkdir -p "$I/.claude"; L="$I/.claude/settings.local.json"
printf '{ "permissions": { "allow": [ "Bash(ls:*)", ] }\n' > "$L"   # a trailing comma: not JSON
BEFORE="$(cat "$L")"
tty_stamp "" "$I"
ok "the broken file is byte-identical" "$([ "$(cat "$L")" = "$BEFORE" ] && echo yes || echo no)" yes
ok "…and the refusal is named" "$(cnt -F 'spawn grant not written: no safe edit' "$TMP/out")" 1
ok "…with the rule to add by hand" "$(cnt -F "Add to permissions.allow by hand: $RULE" "$TMP/out")" 1

echo "== 11. a bundle path a rule cannot spell gets no spawn rule, and one note why =="
for I in "$TMP/i 11" "$TMP/i'11"; do
  mkdir -p "$I"; stamp "$MK" "$I" --spawn-grant
  ok "[$(basename "$I")] the note says why, once" "$(cnt -F 'needs shell quoting, and a rule cannot carry a quote character' "$TMP/out")" 1
  ok "[$(basename "$I")] only the resume and stop rules are written" "$(grants "$I")" 2
done

echo "== 12. a stamp through a symlink names the physical bundle path =="
I="$TMP/i12"; mkdir -p "$I"; ln -s "$I" "$TMP/link12"; set_rules "$I"
stamp "$MK" "$TMP/link12" --spawn-grant
ok "the rules name the physical path" "$(cnt -F "\"$RULE\"" "$I/.claude/settings.local.json")" 1
ok "…and never the link" "$(cnt -F -- "--add-dir $TMP/link12 " "$I/.claude/settings.local.json")" 0

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
