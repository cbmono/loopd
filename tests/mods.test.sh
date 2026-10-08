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
# THE ONE WIDENING, AND ITS SHAPE (2026-10-08, loopd-mod-pane; 2026-10-09, loopd-mod-signal).
# The third prohibition used to be every way out of the process — `$.process`, `$.http`,
# `$.fs`, `$.env` — in one pattern. A renderer over the board snapshot has to READ one file,
# and the signal mod has to read git's own worktree layout to find the bundle a worktree
# belongs to, so the file half is now split in two: `$.fs.write` and `$.fs.ancestors` (which
# walks UP from the cwd) stay refused for every mod, and `$.fs.read`/`stat`/`exists`/`list`
# are admitted ONLY for a mod whose README carries a `## What it reads` section naming every
# path literal the module spells. The section is the declaration a reviewer reads; the grep
# below is what keeps it honest — a path the module names and the README does not is a FAIL
# naming the path. A read without the section is refused outright, which is the mutant
# planted at the end. The mutants run against EVERY declared reader shipped, so the sweep
# is not vacuous for whichever of them this checkout carries.
#
# WHICH `claude`. Under tests/run.sh the shim on PATH execs the real binary for exactly
# these two shapes and AB_CLAUDE_REAL names it (empty = none on this machine); by hand, PATH.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
MJ="$REPO/.claude-plugin/marketplace.json"
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$REPO/plugin/scripts/bundle-paths.sh"
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }
count() { grep -cE -e "$1" "$2" 2>/dev/null | tr -d ' '; }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; echo "pass=0 fail=0"; exit 0; }

if [ -n "${AB_TIER:-}" ]; then CLI="${AB_CLAUDE_REAL:-}"; else CLI="$(command -v claude 2>/dev/null || true)"; fi

# The prohibitions, as source patterns. `tool.check` is the permission event; `$.model.` is
# every model call; REACH is every way out of the process that is not a file; FSWRITE is the
# two file calls no mod may make; FSREAD is the four a declared reader may.
MODEL='\$\.model\.'
CHECK="tool\.check"
REACH='\$\.(process|http|env)\.'
FSWRITE='\$\.fs\.(write|ancestors)'
FSREAD='\$\.fs\.(read|stat|exists|list)'
# The same three on a `claude plugin validate` calls: line, where the `$.` prefix may or may
# not be printed — prefix-optional, so an absent prefix cannot turn the check vacuous.
REACH_CALLS='(^|[^A-Za-z0-9_])(process|http|env)\.'
FSWRITE_CALLS='(^|[^A-Za-z0-9_])fs\.(write|ancestors)'

# The README's `## What it reads` section, up to the next `## `.
reads_section() { awk '/^## What it reads/ { p = 1; next } /^## / { p = 0 } p' "$1" 2>/dev/null; }
# Every quoted path literal a module spells, either quote style — the paths a reader can
# name: a `.json`/`.md` file, and the three names of git's own worktree layout that the
# plugin's deny hook walks too (`.git`, `commondir`, the `loopd-bundle` marker).
path_literals() { grep -oE "['\"][^'\"]*(\.(json|md)|\.git|commondir|loopd-bundle)['\"]" "$1" 2>/dev/null | tr -d "'\"" | LC_ALL=C sort -u; }
# yes when the README has the section AND every path literal the module names is in it.
# Prints the missing ones on stderr so a FAIL names the path rather than a count.
reads_declared() { # <module> <readme>
  local sec lit missing=0
  sec="$(reads_section "$2")"
  [ -n "$sec" ] || { echo no; return; }
  while IFS= read -r lit; do
    [ -n "$lit" ] || continue
    grep -qF -- "$lit" <<<"$sec" || { missing=$((missing+1)); printf '        NOT DECLARED IN README: %s\n' "$lit" >&2; }
  done <<<"$(path_literals "$1")"
  if [ "$missing" -eq 0 ]; then echo yes; else echo no; fi
}
# A copy of a README with its `## What it reads` section removed (up to the next `## `).
without_reads_section() { awk '/^## What it reads/ { p = 1; next } /^## / { p = 0 } !p' "$1"; }

n=0
READERS=""   # the declared readers, "<module>|<readme>" per line, for the mutants below
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
  # TRACKED, not present: a `--plugin-dir` session writes `.claude-plugin/types/` and a
  # `tsconfig.json` that extends it into the mod directory on every developer's machine
  # (.gitignore covers both), so the question is what git carries, never what the disk holds.
  ok "$name: commits no generated types directory or tsconfig" \
     "$(git -C "$REPO" ls-files -- "$d/.claude-plugin/types" "$d/tsconfig.json" 2>/dev/null | grep -c . | tr -d ' ')" 0
  [ -f "$mod" ] || continue
  ok "$name: the module never calls \$.model."            "$(count "$MODEL" "$mod")" 0
  ok "$name: …never hooks the permission event"           "$(count "$CHECK" "$mod")" 0
  ok "$name: …never spawns, fetches or reads the env"     "$(count "$REACH" "$mod")" 0
  ok "$name: …never writes a file or walks up from the cwd" "$(count "$FSWRITE" "$mod")" 0
  if [ "$(count "$FSREAD" "$mod")" -gt 0 ]; then
    # A reader: admitted only against its own declaration. The snapshot spelling is the
    # one bundle-paths.sh exports — a renderer that spelled it by hand would drift the
    # day the layout moved and read a file nobody writes.
    ok "$name: …reads a file, so its README's 'What it reads' names every path it spells" \
       "$(reads_declared "$mod" "$d/README.md")" yes
    if grep -q 'SNAPSHOT.json' "$mod"; then
      ok "$name: …and spells the snapshot path as bundle-paths.sh does ('$AB_SNAPSHOT')" \
         "$([ "$(count "'$AB_SNAPSHOT'" "$mod")" -ge 1 ] && echo yes || echo no)" yes
    fi
    READERS="$READERS$mod|$d/README.md
"
  else
    ok "$name: …reads no file"                            "$(count '\$\.fs\.' "$mod")" 0
  fi
  # A message to another session is a line Claude there reads, never a prompt this mod
  # submits in its place: a mod that sends may not also submit.
  if [ "$(count '\$\.session\.send' "$mod")" -gt 0 ]; then
    ok "$name: …sends a message, so it never submits a prompt" "$(count '\$\.prompt\.submit' "$mod")" 0
  fi
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
    ok "$name: …nor a process, http or env call"        "$(grep -cE "$REACH_CALLS" <<<"$calls_line")" 0
    ok "$name: …nor an fs.write or fs.ancestors call"   "$(grep -cE "$FSWRITE_CALLS" <<<"$calls_line")" 0
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
ok "the shipped usage module is clean of all four, and reads nothing" \
   "$(( $(count "$MODEL" "$SRC") + $(count "$CHECK" "$SRC") + $(count "$REACH" "$SRC") + $(count "$FSWRITE" "$SRC") + $(count "$FSREAD" "$SRC") ))" 0
{ cat "$SRC"; printf '\nasync function spend($: any) { return $.model.complete({ prompt: "x" }) }\n'; } > "$TMP/model.ts"
{ cat "$SRC"; printf '\nexport function extra(on: any) { on(%s, async ($: any, e: any, next: any) => next(e)) }\n' "'tool.check'"; } > "$TMP/check.ts"
{ cat "$SRC"; printf '\nasync function leak($: any) { return $.process.run(["ls"]) }\n'; } > "$TMP/reach.ts"
{ cat "$SRC"; printf '\nasync function env($: any) { return $.env.get("HOME") }\n'; } > "$TMP/env.ts"
{ cat "$SRC"; printf '\nasync function push($: any) { await $.session.send({ to: "x", text: "y" }); return $.prompt.submit({ text: "/loopd:dispatch" }) }\n'; } > "$TMP/submit.ts"
ok "…a planted \$.model. call is caught"          "$(count "$MODEL" "$TMP/model.ts")" 1
ok "…a planted tool.check hook is caught"         "$(count "$CHECK" "$TMP/check.ts")" 1
ok "…a planted \$.process. call is caught"        "$(count "$REACH" "$TMP/reach.ts")" 1
ok "…a planted \$.env. call is caught"            "$(count "$REACH" "$TMP/env.ts")" 1
ok "…a planted send-then-submit is caught"        "$(( $(count '\$\.session\.send' "$TMP/submit.ts") > 0 ? $(count '\$\.prompt\.submit' "$TMP/submit.ts") : 0 ))" 1
# A read in a mod whose README has no `## What it reads` is refused (the usage mod's README).
{ cat "$SRC"; printf '\nasync function peek($: any) { return $.fs.read("instance.config.json") }\n'; } > "$TMP/undeclared.ts"
ok "…a \$.fs.read in a mod with no 'What it reads' section is refused" \
   "$(reads_declared "$TMP/undeclared.ts" "$REPO/plugin-mod-usage/README.md" 2>/dev/null)" no

echo
echo "== the fs widening is read-only and declared — the mutants that must stay red, per declared reader =="
ok "at least one declared reader ships, so the mutants below run against something" \
   "$([ -n "$READERS" ] && echo yes || echo no)" yes
while IFS='|' read -r RSRC RREADME; do
  [ -n "$RSRC" ] || continue
  rname="$(basename "$(dirname "$(dirname "$RSRC")")")"
  ok "$rname: is clean of the other four"                "$(( $(count "$MODEL" "$RSRC") + $(count "$CHECK" "$RSRC") + $(count "$REACH" "$RSRC") + $(count "$FSWRITE" "$RSRC") ))" 0
  # The write and the walk-up are refused for EVERY mod, declared reader or not.
  { cat "$RSRC"; printf '\nasync function save($: any) { await $.fs.write("/tmp/x.json", "{}") }\n'; } > "$TMP/write.ts"
  { cat "$RSRC"; printf '\nasync function up($: any) { return $.fs.ancestors({ names: ["CLAUDE.md"] }) }\n'; } > "$TMP/ancestors.ts"
  ok "$rname: …a planted \$.fs.write is caught"          "$(count "$FSWRITE" "$TMP/write.ts")" 1
  ok "$rname: …a planted \$.fs.ancestors is caught"      "$(count "$FSWRITE" "$TMP/ancestors.ts")" 1
  ok "$rname: …and neither is admitted by the read pattern" "$(( $(count "$FSREAD" "$TMP/write.ts") - $(count "$FSREAD" "$RSRC") ))" 0
  # A read of a path the README does not name is refused, and the FAIL names the path.
  { cat "$RSRC"; printf '\nasync function stray($: any) { return $.fs.read("secrets/other.json") }\n'; } > "$TMP/stray.ts"
  named="$(reads_declared "$TMP/stray.ts" "$RREADME" 2>&1 >/dev/null)"
  ok "$rname: …a path the README does not name is refused" "$(reads_declared "$TMP/stray.ts" "$RREADME" 2>/dev/null)" no
  ok "$rname: …and the refusal names the path"           "$(grep -c 'secrets/other.json' <<<"$named")" 1
  # The shipped README passes the same reader, so the refusals above are not a reader that
  # says no to everything.
  ok "$rname: …while the shipped module and README agree" "$(reads_declared "$RSRC" "$RREADME")" yes
  # A README that drops the section loses the declaration.
  without_reads_section "$RREADME" > "$TMP/README-nosection.md"
  ok "$rname: …and the module against a README without the section is refused" \
     "$(reads_declared "$RSRC" "$TMP/README-nosection.md" 2>/dev/null)" no
  # The snapshot spelling check bites: a hand-spelled old root path is caught.
  if grep -q 'SNAPSHOT.json' "$RSRC"; then
    sed "s#'$AB_SNAPSHOT'#'SNAPSHOT.json'#" "$RSRC" > "$TMP/oldpath.ts"
    ok "$rname: …a module spelling the snapshot's pre-3.0 root path is caught" \
       "$(count "'$AB_SNAPSHOT'" "$TMP/oldpath.ts")" 0
  fi
done <<<"$READERS"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
