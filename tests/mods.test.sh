#!/usr/bin/env bash
#
# mods.test.sh — the mods (core's `plugin/hooks/register.ts`) observe and never decide or spend.
#
# A mod is a hooks module Claude Code runs IN-PROCESS in every session on the machine that
# installs the plugin, with the user's permissions. Since 2026-10-28 the three loopd mods —
# usage, pane, signal — are ONE module in core, each a `/config` switch (`userConfig`), and
# what used to be asserted on every `plugin-mod-*/` companion is asserted on that one file.
# The two lines a loopd mod may never cross are a model call (it spends the plan) and a hook
# on the permission event (it decides what a `PreToolUse` baseline decided). Both are
# asserted TWICE: on the module's source, which runs everywhere including CI, where no claude
# CLI exists; and on what `claude plugin validate` reads out of the module, where the CLI is
# present — the vendor's analysis can see a call routed through a helper that a grep cannot.
# Where the CLI is absent that half is a SKIP by name, never a pass. `claude plugin test`
# runs the mods' own kit tests (plugin/hooks/tests/) the same way.
#
# THE ONE WIDENING, AND ITS SHAPE (2026-10-08, the pane; 2026-10-09, the signal). The third
# prohibition used to be every way out of the process — `$.process`, `$.http`, `$.fs`, `$.env`
# — in one pattern. A renderer over the board snapshot has to READ one file, and the signal
# has to read git's own worktree layout to find the bundle a worktree belongs to, so the file
# half is split in two: `$.fs.write` and `$.fs.ancestors` (which walks UP from the cwd) stay
# refused, and `$.fs.read`/`stat`/`exists`/`list` are admitted ONLY against a `## What it
# reads` section in plugin/hooks/MODS.md naming every path literal the module spells. The
# section is the declaration a reviewer reads; the grep below is what keeps it honest — a
# path the module names and the doc does not is a FAIL naming the path. A read without the
# section is refused outright, which is a mutant planted at the end. A `$.fs.list` walk names
# no file, so a module that lists must spell its walk as a quoted glob, which is then a path
# literal like any other (2026-10-15, the pane's simple mode).
#
# THE SWITCHES. Each mod is one boolean in core's `userConfig`, default true, read off
# register's `options` and nowhere else — no file, no environment — and `paneMode` is the
# pane's one choice. An off mod registers nothing (plugin/hooks/tests/switches.test.ts).
#
# WHICH `claude`. Under tests/run.sh the shim on PATH execs the real binary for exactly
# these two shapes and AB_CLAUDE_REAL names it (empty = none on this machine); by hand, PATH.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
MJ="$REPO/.claude-plugin/marketplace.json"
PLUGIN="$REPO/plugin"
MANIFEST="$PLUGIN/.claude-plugin/plugin.json"
HOOKS="$PLUGIN/hooks/hooks.json"
MOD="$PLUGIN/hooks/register.ts"
DOC="$PLUGIN/hooks/MODS.md"
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

# The doc's `## What it reads` section, up to the next `## `.
reads_section() { awk '/^## What it reads/ { p = 1; next } /^## / { p = 0 } p' "$1" 2>/dev/null; }
# Every quoted path literal a module spells, either quote style — the paths a reader can
# name: a `.json`/`.md` file, the three names of git's own worktree layout that the
# plugin's deny hook walks too (`.git`, `commondir`, the `loopd-bundle` marker), and any
# glob (a quoted string carrying `*`) — plus every quoted literal inside an fs call's own
# arguments, so `$.fs.list("secrets")` beside a declared glob still needs declaring. A
# separator-only literal (`'/'`) names nothing. A path held in a variable is not seen here.
path_literals() {
  { grep -oE "['\"][^'\"]*(\.(json|md)|\.git|commondir|loopd-bundle|\*[^'\"]*)['\"]" "$1" 2>/dev/null
    grep -oE '\$\.fs\.(read|stat|exists|list)\([^)]*\)' "$1" 2>/dev/null | grep -oE "['\"][^'\"]*['\"]"
  } | tr -d "'\"" | grep -vE '^/*$' | LC_ALL=C sort -u
}
globs() { grep -oE "['\"][^'\"]*\*[^'\"]*['\"]" "$1" 2>/dev/null | grep -c . | tr -d ' '; }
# Validator output minus the plugin-directory block (CLI 2.1.310+), which states it does not
# change the result. Only a block closed by that sentence is dropped; an unclosed one counts.
outside_directory_block() {
  awk '/^Plugin directory checks for /{printf "%s", buf; buf=""; b=1}
       b{buf=buf $0 "\n"; if ($0=="These plugin directory checks do not change the result below.") {b=0; buf=""}; next}
       {print} END{printf "%s", buf}'
}
# yes when the doc has the section AND every path literal the module names is in it.
# Prints the missing ones on stderr so a FAIL names the path rather than a count.
reads_declared() { # <module> <doc>
  local sec lit missing=0
  sec="$(reads_section "$2")"
  [ -n "$sec" ] || { echo no; return; }
  while IFS= read -r lit; do
    [ -n "$lit" ] || continue
    grep -qF -- "$lit" <<<"$sec" || { missing=$((missing+1)); printf '        NOT DECLARED IN MODS.md: %s\n' "$lit" >&2; }
  done <<<"$(path_literals "$1")"
  if [ "$missing" -eq 0 ]; then echo yes; else echo no; fi
}
# A copy of the doc with its `## What it reads` section removed (up to the next `## `).
without_reads_section() { awk '/^## What it reads/ { p = 1; next } /^## / { p = 0 } !p' "$1"; }
# The module's source minus its comment lines, for the pins that count a spelling.
code() { grep -vE '^[[:space:]]*//' "$1"; }

echo
echo "== the module ships in core, registered beside the shell hooks =="
ok "core has hooks/hooks.json"             "$(yn test -f "$HOOKS")" yes
ok "…which names ONE module"               "$(jq -r '.modules | length' "$HOOKS" 2>/dev/null)" 1
ok "…and that module is hooks/register.ts" "$(jq -r '.modules[0]' "$HOOKS" 2>/dev/null)" ./register.ts
ok "…and the module exists"                "$(yn test -f "$MOD")" yes
ok "…beside the settings hooks (both halves in one file, as a plugin's hooks/ may hold)" \
   "$(jq -r 'has("hooks") and (.hooks | length > 0)' "$HOOKS" 2>/dev/null)" true
ok "the plugin ships at least one *.test.ts for the kit" \
   "$([ "$(find "$PLUGIN/hooks/tests" -name '*.test.ts' 2>/dev/null | grep -c .)" -ge 4 ] && echo yes || echo no)" yes
# TRACKED, not present: a `--plugin-dir` session writes `.claude-plugin/types/` and a
# `tsconfig.json` that extends it into the plugin on every developer's machine (.gitignore
# covers both), so the question is what git carries, never what the disk holds.
ok "commits no generated types directory or tsconfig" \
   "$(git -C "$REPO" ls-files -- plugin/.claude-plugin/types plugin/tsconfig.json 2>/dev/null | grep -c . | tr -d ' ')" 0
ok "no mod companion directory is left (the sweep moved here)" \
   "$(find "$REPO" -maxdepth 1 -type d -name 'plugin-mod-*' | grep -c . | tr -d ' ')" 0

echo
echo "== the module never decides or spends =="
ok "the module never calls \$.model."              "$(count "$MODEL" "$MOD")" 0
ok "…never hooks the permission event"             "$(count "$CHECK" "$MOD")" 0
ok "…never spawns, fetches or reads the env"       "$(count "$REACH" "$MOD")" 0
ok "…never writes a file or walks up from the cwd" "$(count "$FSWRITE" "$MOD")" 0
ok "…reads a file, so MODS.md's 'What it reads' names every path it spells" \
   "$(reads_declared "$MOD" "$DOC")" yes
ok "…lists a directory, so it spells its walk as a quoted glob" \
   "$([ "$(globs "$MOD")" -ge 1 ] && echo yes || echo no)" yes
# The snapshot spelling is the one bundle-paths.sh exports — a renderer that spelled it by
# hand would drift the day the layout moved and read a file nobody writes.
ok "…and spells the snapshot path as bundle-paths.sh does ('$AB_SNAPSHOT')" \
   "$([ "$(count "'$AB_SNAPSHOT'" "$MOD")" -ge 1 ] && echo yes || echo no)" yes
# A message to another session is a line Claude there reads, never a prompt this mod
# submits in its place: a module that sends may not also submit.
ok "…sends a message, so it never submits a prompt" \
   "$(count '\$\.session\.send' "$MOD")/$(count '\$\.prompt\.submit' "$MOD")" 1/0
ok "…and hands at least one event on with next"    \
   "$([ "$(count 'next\(' "$MOD")" -ge 1 ] && echo yes || echo no)" yes

echo
echo "== the switches: four userConfig fields, read off register's options and nowhere else =="
for sw in usage pane signal; do
  ok "userConfig.$sw is a boolean, default true" \
     "$(jq -c --arg k "$sw" '.userConfig[$k] | [.type, .default]' "$MANIFEST" 2>/dev/null)" '["boolean",true]'
  ok "…and the module reads it as \`o.$sw !== false\` exactly once (absent is on)" \
     "$(code "$MOD" | grep -cF "o.$sw !== false")" 1
done
ok "userConfig.paneMode is a choice of operator|simple, default operator" \
   "$(jq -c '.userConfig.paneMode | [.type, .default, .options]' "$MANIFEST" 2>/dev/null)" '["string","operator",["operator","simple"]]'
ok "…and the module reads paneMode off the options exactly once" \
   "$(code "$MOD" | grep -c 'paneMode')/$(code "$MOD" | grep -cF "o.paneMode === 'simple'")" 1/1
ok "the options object is the only source: no \`mode\` read anywhere else" \
   "$(code "$MOD" | grep -cE '\.mode\b')" 0
# The form is /loopd:new-project runs: every shape the pane passes is one the skill takes.
NP="$PLUGIN/skills/new-project/SKILL.md"
hint="$(grep -m1 '^argument-hint:' "$NP")"
ok "the pane runs /loopd:new-project, whose argument-hint the check reads" \
   "$(count "'loopd:new-project'" "$MOD")/$([ -n "$hint" ] && echo hint)" 1/hint
for tok in "'submit'" "'cancel'"; do
  ok "…passes $tok, and new-project's argument-hint names it" \
     "$(grep -cF -- "$tok" "$MOD" | tr -d ' ' | sed 's/^[1-9][0-9]*$/yes/')/$(grep -cF -- "${tok//\'/}" <<<"$hint")" yes/1
done
ok "…passes <n> \"<text>\", and the argument-hint names <1-5> <text>" \
   "$(grep -cF "m[1] + ' ' + q(m[2])" "$MOD")/$(grep -cF '<1-5> <text>' <<<"$hint")" 1/1
ok "…the form's submit asks for yolo, a mode loopd-yolo's AUTONOMY.md defines" \
   "$(grep -cF '"autonomy": "yolo"' "$PLUGIN/scripts/new-project-form.sh")/$(grep -cE '^# Mode: `yolo`$' "$REPO/plugin-yolo/companion/AUTONOMY.md")" 1/1

echo
echo "== the doc: what it reads, what it never does, what it was tested with =="
ok "plugin/hooks/MODS.md exists"           "$(yn test -f "$DOC")" yes
ok "…names the Claude Code version it was tested with" \
   "$([ "$(count 'Claude Code \*{0,2}v?[0-9]+\.[0-9]+\.[0-9]+' "$DOC")" -ge 1 ] && echo yes || echo no)" yes
ok "…says what it never does"              "$([ "$(grep -ci 'never' "$DOC" 2>/dev/null | tr -d ' ')" -ge 1 ] && echo yes || echo no)" yes
ok "…names every switch"                   "$(grep -cE '^\| `(usage|pane|paneMode|signal)` \|' "$DOC")" 4
ok "the marketplace's core entry is this plugin" \
   "$(jq -r '[.plugins[] | select(.name == "loopd" and .source == "./plugin")] | length' "$MJ")" 1

if [ -n "$CLI" ]; then
  vout="$(claude plugin validate "$PLUGIN" --strict </dev/null 2>&1)"; vrc=$?
  ok "claude plugin validate --strict passes" "$vrc" 0
  [ "$vrc" -eq 0 ] || printf '%s\n' "$vout" | sed 's/^/        | /'
  ok "…with zero warnings"                     "$(outside_directory_block <<<"$vout" | grep -ci 'warning')" 0
  hooks_line="$(grep -E 'hooks:' <<<"$vout")"
  calls_line="$(grep -E 'calls:' <<<"$vout")"
  ok "…the validator saw the module's hooks"   "$([ -n "$hooks_line" ] && echo yes || echo no)" yes
  ok "…its hooks: line has no tool.check"      "$(grep -c "$CHECK" <<<"$hooks_line")" 0
  ok "…its calls: line has no \$.model."       "$(grep -c "$MODEL" <<<"$calls_line")" 0
  ok "…nor a process, http or env call"        "$(grep -cE "$REACH_CALLS" <<<"$calls_line")" 0
  ok "…nor an fs.write or fs.ancestors call"   "$(grep -cE "$FSWRITE_CALLS" <<<"$calls_line")" 0
  tout="$(cd "$PLUGIN" && claude plugin test </dev/null 2>&1)"; trc=$?
  ok "claude plugin test passes"               "$trc" 0
  [ "$trc" -eq 0 ] || printf '%s\n' "$tout" | sed 's/^/        | /'
  ok "…and ran at least one test"              "$(grep -cE '^ *[1-9][0-9]* pass' <<<"$tout")" 1
else
  echo "  SKIP  claude plugin validate --strict and claude plugin test not run — no claude CLI on this machine (AB_CLAUDE_REAL is empty); the source reads above still hold"
fi

echo
echo "== the sweep is not vacuous, and the source read bites =="
# A copy of the shipped module with each prohibition planted: the same patterns catch it.
# Planted as a top-level function so the grep is not merely matching its own comment.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/mods.XXXXXX")" || { echo "mods.test: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
ok "the shipped module is clean of all four" \
   "$(( $(count "$MODEL" "$MOD") + $(count "$CHECK" "$MOD") + $(count "$REACH" "$MOD") + $(count "$FSWRITE" "$MOD") ))" 0
{ cat "$MOD"; printf '\nasync function spend($: any) { return $.model.complete({ prompt: "x" }) }\n'; } > "$TMP/model.ts"
{ cat "$MOD"; printf '\nexport function extra(on: any) { on(%s, async ($: any, e: any, next: any) => next(e)) }\n' "'tool.check'"; } > "$TMP/check.ts"
{ cat "$MOD"; printf '\nasync function leak($: any) { return $.process.run(["ls"]) }\n'; } > "$TMP/reach.ts"
{ cat "$MOD"; printf '\nasync function env($: any) { return $.env.get("HOME") }\n'; } > "$TMP/env.ts"
{ cat "$MOD"; printf '\nasync function push($: any) { return $.prompt.submit({ text: "/loopd:dispatch" }) }\n'; } > "$TMP/submit.ts"
ok "…a planted \$.model. call is caught"          "$(count "$MODEL" "$TMP/model.ts")" 1
ok "…a planted tool.check hook is caught"         "$(count "$CHECK" "$TMP/check.ts")" 1
ok "…a planted \$.process. call is caught"        "$(count "$REACH" "$TMP/reach.ts")" 1
ok "…a planted \$.env. call is caught"            "$(count "$REACH" "$TMP/env.ts")" 1
ok "…a planted prompt submit beside the send is caught" "$(count '\$\.prompt\.submit' "$TMP/submit.ts")" 1
# A switch read from anywhere but the options is caught: a file or the environment is not it.
{ cat "$MOD"; printf '\nasync function sw($: any) { const c = JSON.parse(await $.fs.read("instance.config.json")); return c.pane.mode }\n'; } > "$TMP/switchfile.ts"
ok "…a switch read off a file (a second .mode) is caught" "$(code "$TMP/switchfile.ts" | grep -cE '\.mode\b')" 1
# The write and the walk-up are refused, declared reader or not.
{ cat "$MOD"; printf '\nasync function save2($: any) { await $.fs.write("/tmp/x.json", "{}") }\n'; } > "$TMP/write.ts"
{ cat "$MOD"; printf '\nasync function up($: any) { return $.fs.ancestors({ names: ["CLAUDE.md"] }) }\n'; } > "$TMP/ancestors.ts"
ok "…a planted \$.fs.write is caught"          "$(count "$FSWRITE" "$TMP/write.ts")" 1
ok "…a planted \$.fs.ancestors is caught"      "$(count "$FSWRITE" "$TMP/ancestors.ts")" 1
ok "…and neither is admitted by the read pattern" "$(( $(count "$FSREAD" "$TMP/write.ts") - $(count "$FSREAD" "$MOD") ))" 0
# A read of a path the doc does not name is refused, and the FAIL names the path.
{ cat "$MOD"; printf '\nasync function stray($: any) { return $.fs.read("secrets/other.json") }\n'; } > "$TMP/stray.ts"
named="$(reads_declared "$TMP/stray.ts" "$DOC" 2>&1 >/dev/null)"
ok "…a path the doc does not name is refused"  "$(reads_declared "$TMP/stray.ts" "$DOC" 2>/dev/null)" no
ok "…and the refusal names the path"           "$(grep -c 'secrets/other.json' <<<"$named")" 1
# A walk the doc does not name is refused the same way: the glob is the path.
{ cat "$MOD"; printf '\nconst STRAY = %s\nasync function walk($: any) { return $.fs.list(STRAY.split("/")[0]) }\n' "'secrets/*/keys'"; } > "$TMP/strayglob.ts"
ok "…a glob the doc does not name is refused"  "$(reads_declared "$TMP/strayglob.ts" "$DOC" 2>/dev/null)" no
# Beside the declared globs, a listing of an undeclared directory is still refused, by name.
{ cat "$MOD"; printf '\nasync function peek($: any, root: string) { return $.fs.list(%s) }\n' "'secrets'"; } > "$TMP/mixedlist.ts"
named="$(reads_declared "$TMP/mixedlist.ts" "$DOC" 2>&1 >/dev/null)"
ok "…a \$.fs.list of an undeclared directory beside a declared glob is refused" \
   "$(reads_declared "$TMP/mixedlist.ts" "$DOC" 2>/dev/null)/$(grep -c 'NOT DECLARED IN MODS.md: secrets$' <<<"$named")" no/1
# The shipped doc passes the same reader, so the refusals above are not a reader that says
# no to everything; a doc that drops the section loses the declaration.
ok "…while the shipped module and doc agree"   "$(reads_declared "$MOD" "$DOC")" yes
without_reads_section "$DOC" > "$TMP/MODS-nosection.md"
ok "…and the module against a doc without the section is refused" \
   "$(reads_declared "$MOD" "$TMP/MODS-nosection.md" 2>/dev/null)" no
ok "…a \$.fs.list in a module that spells no glob is caught" \
   "$(sed "s#'projects/\*/tasks/\*.md'#'projects/x/tasks/x.md'#; s#'projects/\*/project.md'#'projects/x/project.md'#" "$MOD" > "$TMP/unglobbed.ts"; globs "$TMP/unglobbed.ts")" 0
# The snapshot spelling check bites: a hand-spelled old root path is caught.
sed "s#'$AB_SNAPSHOT'#'SNAPSHOT.json'#" "$MOD" > "$TMP/oldpath.ts"
ok "…a module spelling the snapshot's pre-3.0 root path is caught" "$(count "'$AB_SNAPSHOT'" "$TMP/oldpath.ts")" 0
# A switch that stops being read, or is read twice, is named.
sed "s/o\.signal !== false/true/" "$MOD" > "$TMP/noswitch.ts"
ok "…a switch the module stops reading is caught" "$(code "$TMP/noswitch.ts" | grep -cF 'o.signal !== false')" 0

# Real 2.1.310 output: the zero-warnings pin drops the plugin-directory block and nothing else.
FX_BLOCK="$REPO/tests/fixtures/mods-validate/directory-block.txt"
FX_MANIFEST="$REPO/tests/fixtures/mods-validate/manifest-warning.txt"
ok "…the zero-warnings pin ignores the closed plugin-directory block" \
   "$(outside_directory_block <"$FX_BLOCK" | grep -ci 'warning')" 0
ok "…but a manifest warning beside that block survives the filter, so it fails the pin" \
   "$(outside_directory_block <"$FX_MANIFEST" | grep -cE '^⚠ Found 1 warning:$|^  ❯ description: No description provided')" 2
grep -v '^These plugin directory checks do not change the result below\.$' "$FX_BLOCK" > "$TMP/unclosed.txt"
ok "…and a block missing its closing sentence is counted" \
   "$([ "$(outside_directory_block <"$TMP/unclosed.txt" | grep -ci 'warning')" -ge 1 ] && echo yes || echo no)" yes

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
