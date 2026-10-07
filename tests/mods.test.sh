#!/usr/bin/env bash
#
# mods.test.sh — every mod companion (`plugin-mod-*/`) observes and never decides or spends.
#
# A mod is a hooks module Claude Code runs IN-PROCESS in every session on the machine that
# installs it, with the user's permissions. The two lines a loopd mod may never cross are a
# model call (it spends the plan) and a hook on the permission event (it decides what a
# `PreToolUse` baseline decided). Both are asserted TWICE: on the module's source, which
# runs everywhere including CI, where no claude CLI exists; and on what `claude plugin
# validate` reads out of the module, where the CLI is present — the vendor's analysis can
# see a call routed through a helper that a grep cannot. Where the CLI is absent that half
# is a SKIP by name, never a pass. `claude plugin test` runs the mod's own tests the same way.
#
# WHICH `claude`. Under tests/run.sh the shim on PATH execs the real binary for exactly
# these two shapes and AB_CLAUDE_REAL names it (empty = none on this machine); by hand, PATH.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
MJ="$REPO/.claude-plugin/marketplace.json"
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }
count() { grep -cE -e "$1" "$2" 2>/dev/null | tr -d ' '; }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; echo "pass=0 fail=0"; exit 0; }

if [ -n "${AB_TIER:-}" ]; then CLI="${AB_CLAUDE_REAL:-}"; else CLI="$(command -v claude 2>/dev/null || true)"; fi

# The prohibitions, as source patterns. `tool.check` is the permission event; `$.model.` is
# every model call; the third group is every way out of the process.
MODEL='\$\.model\.'
CHECK="tool\.check"
REACH='\$\.(process|http|fs|env)\.'

n=0
for d in "$REPO"/plugin-mod-*/; do
  d="${d%/}"; name="${d##*/}"; n=$((n+1))
  echo
  echo "== $name =="
  ok "$name: has a plugin manifest"      "$(yn test -f "$d/.claude-plugin/plugin.json")" yes
  ok "$name: has hooks/hooks.json"       "$(yn test -f "$d/hooks/hooks.json")" yes
  module="$(jq -r '.modules[0] // empty' "$d/hooks/hooks.json" 2>/dev/null)"
  ok "$name: hooks.json names one module" "$(jq -r '.modules | length' "$d/hooks/hooks.json" 2>/dev/null)" 1
  mod="$d/hooks/${module#./}"
  ok "$name: …and the module exists"     "$(yn test -f "$mod")" yes
  ok "$name: hooks.json carries no settings hooks (a second PreToolUse copy fires everywhere)" \
     "$(jq -r 'has("hooks")' "$d/hooks/hooks.json" 2>/dev/null)" false
  ok "$name: ships at least one *.test.ts" \
     "$([ "$(find "$d" -name '*.test.ts' 2>/dev/null | grep -c .)" -ge 1 ] && echo yes || echo no)" yes
  ok "$name: ships no agents and no skills" \
     "$([ -e "$d/agents" ] || [ -e "$d/skills" ] && echo no || echo yes)" yes
  [ -f "$mod" ] || continue
  ok "$name: the module never calls \$.model."            "$(count "$MODEL" "$mod")" 0
  ok "$name: …never hooks the permission event"           "$(count "$CHECK" "$mod")" 0
  ok "$name: …never spawns, fetches, reads env or files"  "$(count "$REACH" "$mod")" 0
  ok "$name: …and hands at least one event on with next"  \
     "$([ "$(count 'next\(' "$mod")" -ge 1 ] && echo yes || echo no)" yes
  ok "$name: README exists"              "$(yn test -f "$d/README.md")" yes
  ok "$name: …and names the Claude Code version it was tested with" \
     "$([ "$(count 'Claude Code \*{0,2}v?[0-9]+\.[0-9]+\.[0-9]+' "$d/README.md")" -ge 1 ] && echo yes || echo no)" yes
  ok "$name: …and says what it never does" "$([ "$(grep -ci 'never' "$d/README.md" 2>/dev/null | tr -d ' ')" -ge 1 ] && echo yes || echo no)" yes
  pn="$(jq -r .name "$d/.claude-plugin/plugin.json" 2>/dev/null)"
  ok "$name: is a marketplace entry under its own name" \
     "$(jq -r --arg n "$pn" '[.plugins[] | select(.name == $n and .source == "./'"$name"'")] | length' "$MJ")" 1

  if [ -n "$CLI" ]; then
    vout="$(claude plugin validate "$d" --strict </dev/null 2>&1)"; vrc=$?
    ok "$name: claude plugin validate --strict passes" "$vrc" 0
    [ "$vrc" -eq 0 ] || printf '%s\n' "$vout" | sed 's/^/        | /'
    ok "$name: …with zero warnings"                     "$(grep -ci 'warning' <<<"$vout")" 0
    hooks_line="$(grep -E 'hooks:' <<<"$vout")"
    calls_line="$(grep -E 'calls:' <<<"$vout")"
    ok "$name: …the validator saw the module's hooks"   "$([ -n "$hooks_line" ] && echo yes || echo no)" yes
    ok "$name: …its hooks: line has no tool.check"      "$(grep -c "$CHECK" <<<"$hooks_line")" 0
    ok "$name: …its calls: line has no \$.model."       "$(grep -c "$MODEL" <<<"$calls_line")" 0
    ok "$name: …nor a process, http, fs or env call"    "$(grep -cE "$REACH" <<<"$calls_line")" 0
    tout="$(cd "$d" && claude plugin test </dev/null 2>&1)"; trc=$?
    ok "$name: claude plugin test passes"               "$trc" 0
    [ "$trc" -eq 0 ] || printf '%s\n' "$tout" | sed 's/^/        | /'
    ok "$name: …and ran at least one test"              "$(grep -cE '^ *[1-9][0-9]* pass' <<<"$tout")" 1
  else
    echo "  SKIP  $name: claude plugin validate --strict and claude plugin test not run — no claude CLI on this machine (AB_CLAUDE_REAL is empty); the source reads above still hold"
  fi
done

echo
echo "== the sweep is not vacuous, and the source read bites =="
ok "at least one mod companion exists" "$([ "$n" -ge 1 ] && echo yes || echo no)" yes
# A copy of the shipped module with each prohibition planted: the same patterns catch it.
# Planted as a top-level function so the grep is not merely matching its own comment.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/mods.XXXXXX")" || { echo "mods.test: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
SRC="$REPO/plugin-mod-usage/hooks/register.ts"
ok "the shipped usage module is clean of all three" \
   "$(( $(count "$MODEL" "$SRC") + $(count "$CHECK" "$SRC") + $(count "$REACH" "$SRC") ))" 0
{ cat "$SRC"; printf '\nasync function spend($: any) { return $.model.complete({ prompt: "x" }) }\n'; } > "$TMP/model.ts"
{ cat "$SRC"; printf '\nexport function extra(on: any) { on(%s, async ($: any, e: any, next: any) => next(e)) }\n' "'tool.check'"; } > "$TMP/check.ts"
{ cat "$SRC"; printf '\nasync function leak($: any) { return $.process.run(["ls"]) }\n'; } > "$TMP/reach.ts"
ok "…a planted \$.model. call is caught"          "$(count "$MODEL" "$TMP/model.ts")" 1
ok "…a planted tool.check hook is caught"         "$(count "$CHECK" "$TMP/check.ts")" 1
ok "…a planted \$.process. call is caught"        "$(count "$REACH" "$TMP/reach.ts")" 1

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
