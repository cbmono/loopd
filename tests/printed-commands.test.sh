#!/usr/bin/env bash
#
# printed-commands.test.sh — every command an operator-facing notice prints is ACCEPTED by
# the script it names. A printed command nobody ever executes is a defect class this repo
# had no guard for: bundle-paths.sh told operators to run `migrate-bundle.sh --layout
# --apply`, which that script's own parser refuses.
#
# DISCOVERY IS A CONVENTION, NOT A REGEX OVER PROSE. A notice emits through
# `ab_say_run <lead> <script> [arg...]` (plugin/scripts/bundle-paths.sh), so the call sites
# ARE the inventory. The one other shape is init-bundle.sh's `id_needs <key> "$v" "<flags>"`:
# a machine-read `needs` line /loopd:init appends to the command it already ran, probed as
# `init-bundle.sh <flags>`. Scraping English finds ~50 echo lines naming a `.sh`, nearly all
# of them sentences ABOUT a script.
#
# WHAT IS EXECUTED IS WHAT IS PRINTED. Each call site is rendered through the real
# ab_say_run with every variable set to a dummy, every `<slot>` a human fills is replaced by
# a dummy, and the line is split the way a shell would split it. Both tables are printed.
#
# ACCEPTED = the named script's own usage / unknown-flag line is absent from stderr. Exit
# codes cannot define it — `migrate-bundle.sh --apply` from a non-bundle directory and
# `migrate-bundle.sh --layout --apply` BOTH exit 2.
#
# PARSING NEVER RUNS THE DESTRUCTIVE HALF, because every probed script parses before its
# first write and is then refused: from a throwaway non-bundle cwd under a temp HOME and
# CLAUDE_CONFIG_DIR (knowledge/findings/a-printed-command-is-only-probe-safe-where-the-
# bundle-guard-precedes-the-first-write.md in the control panel). Two scripts have no such
# guard in their own context, so each gets a stated CONTEXT that reaches a refusal after
# the parser: init-bundle.sh runs as an installed plugin (no config/ beside it) with
# --config, and tick-lock.sh gets an --instance that does not exist. Section 3 proves no
# probe wrote. `--help` is never passed: it exits before the later arguments are read.
#
# Exit codes: 0 clean, 1 an assertion failed, 2 the tree is not readable.
# Reasoning: seed-gaps-and-worktree-cleanup/task-003, task-005.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$REPO/plugin/scripts"
[ -d "$SCRIPTS" ] || { echo "printed-commands.test: no $SCRIPTS" >&2; exit 2; }

# The checked-in inventory, as source text. It is the absence detector AND what makes
# `tests/run.sh --changed` select this file: run.sh matches literal path strings.
EXPECTED="plugin/scripts/bundle-paths.sh|migrate-bundle.sh --apply
plugin/scripts/close-project-folder.sh|close-project-folder.sh \"\$SLUG\" --apply
plugin/scripts/close-project-folder.sh|close-project-folder.sh \"\$SLUG\" --apply
plugin/scripts/commit-as.sh|kb-sync.sh commit --role \"\$role\" --message \"\\\"\$message\\\"\" -- '<path>...'
plugin/scripts/control.sh|commit-as.sh human \"\\\"chore: record halt of \$id\\\"\" -- \"\$AB_LEDGER\"
plugin/scripts/control.sh|control.sh clear \"\$id\"
plugin/scripts/control.sh|control.sh clear \"\$id\"
plugin/scripts/control.sh|control.sh clear '<agent-id>'
plugin/scripts/control.sh|control.sh clear '<agent-id>'
plugin/scripts/control.sh|control.sh clear --all
plugin/scripts/control.sh|control.sh clear --all
plugin/scripts/control.sh|control.sh halt '<agent-id>' '\"<why>\"'
plugin/scripts/init-bundle.sh|bash \"\$BIN_DIR/kb-sync.sh\" status
plugin/scripts/init-bundle.sh|init-bundle.sh '--email <commit-address>'
plugin/scripts/init-bundle.sh|init-bundle.sh '--owner <github-login>'
plugin/scripts/init-bundle.sh|init-bundle.sh '--repos-root <absolute path>'
plugin/scripts/init-bundle.sh|kb-sync.sh commit --message '\"<message>\"' -- '<path>...'
plugin/scripts/init-bundle.sh|loopd/plugin/scripts/init-bundle.sh --config
plugin/scripts/kb-sweep-due.sh|build-kb-index.sh --check
plugin/scripts/kb-sync.sh|kb-sync.sh commit --message '\"<message>\"' -- '<path>...'
plugin/scripts/kb-sync.sh|kb-sync.sh mount
plugin/scripts/migrate-bundle.sh|kb-sync.sh commit --message '\"chore: relink knowledge/\"' -- '<path>...'
plugin/scripts/migrate-bundle.sh|migrate-bundle.sh --apply
plugin/scripts/migrate-bundle.sh|validate-bundle.sh
plugin/scripts/refresh-seeds.sh|\"\$SELF\" \"'\$TARGET'\" --apply
plugin/scripts/tick-lock.sh|tick-lock.sh release
plugin/scripts/tick-lock.sh|tick-lock.sh release
plugin/scripts/tick-lock.sh|tick-lock.sh release
plugin/scripts/validate-bundle.sh|build-kb-index.sh
plugin/scripts/validate-bundle.sh|build-kb-index.sh --check"
# plugin/scripts/build-kb-index.sh is probed as a target above; named so a move selects this.

TMP="$(mktemp -d "${TMPDIR:-/tmp}/printedcmd.XXXXXX")" || {
  echo "printed-commands.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
OUTSIDE="$TMP/outside"; HOME_T="$TMP/home"; CFG_T="$TMP/cfg"; BUNDLE="$TMP/bundle"; CAP="$TMP/cap"
INSTALLED="$TMP/installed"; ABSENT="$TMP/absent"
mkdir -p "$OUTSIDE" "$HOME_T" "$CFG_T" "$BUNDLE/.ai-bridge" "$CAP" "$INSTALLED"
: > "$BUNDLE/instance.config.json"; : > "$BUNDLE/SCHEMA.md"   # a fake un-migrated bundle
# An installed plugin: the real scripts with no marketplace (so no config/) above them.
ln -s "$SCRIPTS" "$INSTALLED/scripts"; ln -s "$REPO/plugin/VERSION" "$INSTALLED/VERSION"
ln -s "$REPO/plugin/seed" "$INSTALLED/seed"

# control.sh walks UP for an instance and would arm one it found, so no ancestor may be one.
d="$OUTSIDE"; while [ "$d" != / ]; do
  [ -f "$d/instance.config.json" ] && { echo "printed-commands.test: $d is an instance; set TMPDIR elsewhere." >&2; exit 2; }
  d="$(dirname "$d")"; done

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

snap() { # <dir> — one checksum over a content manifest: equal means byte-identical
  ( cd "$1" 2>/dev/null || return 0
    find . | LC_ALL=C sort | while IFS= read -r p; do
      if [ -f "$p" ]; then printf '%s %s\n' "$p" "$(cksum <"$p")"; else printf '%s/\n' "$p"; fi
    done ) | cksum
}

echo
echo "== 1. the inventory the convention yields =="
found=""
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  f="${hit%%:*}"; rest="${hit#*:}"; n="${rest%%:*}"; code="${rest#*:}"
  case "$code" in
    *id_needs*) cmd="init-bundle.sh '$(printf '%s' "$code" | sed -E 's/.*"[[:space:]]+"([^"]*)"[[:space:]]*$/\1/')'" ;;
    *) cmd="$(printf '%s' "$code" | sed -E 's/^[[:space:]]*ab_say_run[[:space:]]+"[^"]*"[[:space:]]*//; s/[[:space:]]*(>&2|>>[[:space:]]*"[^"]*")[[:space:]]*$//')" ;;
  esac
  found="$found$f|$cmd"$'\n'
  printf '  notice  %s:%s  ->  %s\n' "$f" "$n" "$cmd"
done <<<"$( { grep -rn --include='*.sh' -E '^[[:space:]]*ab_say_run[[:space:]]+"' "$REPO/plugin"
             grep -n -E '^[[:space:]]*id_needs[[:space:]]+[A-Za-z]+[[:space:]]+"' "$SCRIPTS/init-bundle.sh" \
               | sed "s|^|$SCRIPTS/init-bundle.sh:|"; } 2>/dev/null | sed "s|^$REPO/||" | LC_ALL=C sort)"
printf '%s' "$found" | grep -v '^$' | LC_ALL=C sort > "$CAP/found"
printf '%s\n' "$EXPECTED" | LC_ALL=C sort > "$CAP/expected"
drift="$(diff "$CAP/expected" "$CAP/found" | grep '^[<>]' | sed 's/^</  missing/; s/^>/  unlisted/')"
ok "the inventory is the checked-in one" "$(printf '%s' "$drift" | grep -c .)" 0
[ -z "$drift" ] || printf '%s\n' "$drift"

echo
echo "== 2. every printed command is accepted by the script it names =="
VARS="id=probe-agent-0001
role=human
message=probe message
SLUG=probe-slug
BIN_DIR=$SCRIPTS
SELF=$SCRIPTS/refresh-seeds.sh
TARGET=$OUTSIDE"
SLOTS="<agent-id>=probe-agent-0001
<message>=probe message
<why>=probe reason
<path>...=knowledge/probe.md
<github-login>=example-user-007
<commit-address>=probe@example.com
<absolute path>=$OUTSIDE"
printf '%s\n' "$VARS"  | sed 's/^/  dummy  $/'
printf '%s\n' "$SLOTS" | sed 's/^/  dummy  /'
echo "  context  init-bundle.sh: run as an installed plugin ($INSTALLED) with --config appended"
echo "  context  tick-lock.sh:   --instance $ABSENT appended (a directory that does not exist)"

render() { # <cmd source> — the line ab_say_run prints with every variable a dummy
  ( cd "$OUTSIDE" || exit 3
    . "$SCRIPTS/bundle-paths.sh" || exit 3
    while IFS='=' read -r k v; do printf -v "$k" '%s' "$v"; done <<<"$VARS"
    set -u
    eval "ab_say_run '' $1" ) 2>/dev/null
}

before_git="$(git -C "$REPO" status --porcelain 2>/dev/null)"
b_outside="$(snap "$OUTSIDE")"; b_home="$(snap "$HOME_T")"; b_cfg="$(snap "$CFG_T")"; b_bundle="$(snap "$BUNDLE")"
total=0; probed=0; kbcommit=0
while IFS='|' read -r f cmd; do
  [ -n "${cmd:-}" ] || continue
  total=$((total+1))
  # Rendering runs `eval`, so only words go in: no substitution anywhere, no operator
  # outside quotes.
  bare="$(printf '%s' "$cmd" | sed -E "s/'[^']*'//g; s/\"([^\"\\\\]|\\\\.)*\"//g")"
  case "$cmd" in *'$('*|*'`'*) bad=yes ;; *) bad=no ;; esac
  case "$bare" in *['<>|;&']*) bad=yes ;; esac
  [ "$bad" = no ] || { ok "$f: $cmd is a plain word list" no yes; continue; }
  line="$(render "$cmd")" || { ok "$f: every variable in $cmd has a stated dummy" no yes; continue; }
  line="${line# }"
  # PARSES IS NOT USABLE: kb-sync.sh checks --message and the path tail after its bundle
  # guard, so a bare `kb-sync.sh commit` passes the parse probe below and dies on usage.
  case "$line" in *'kb-sync.sh commit'*)
    kbcommit=$((kbcommit+1))
    case "$line" in *' --message '*' -- '?*) u=yes ;; *) u=no ;; esac
    ok "$f: '$line' carries --message and a -- <path> tail" "$u" yes ;;
  esac
  while IFS='=' read -r k v; do line="${line//"$k"/$v}"; done <<<"$SLOTS"
  case "$line" in *'<'*'>'*) ok "$f: every slot in '$line' has a stated dummy" no yes; continue ;; esac
  argv=()
  while IFS= read -r w; do argv+=("$w"); done < <(printf '%s\n' "$line" | xargs printf '%s\n' 2>/dev/null)
  [ "${argv[0]:-}" = bash ] && argv=("${argv[@]:1}")
  s="$(basename "${argv[0]:-}")"
  case "$s" in
    *.sh) ;;
    *) ok "$f: '$line' names a plugin script" no yes; continue ;;
  esac
  if [ ! -r "$SCRIPTS/$s" ]; then ok "$f: '$line' names a script that exists" no yes; continue; fi
  run="$SCRIPTS/$s"; args=("${argv[@]:1}")
  case "$s" in
    init-bundle.sh) run="$INSTALLED/scripts/$s"; args+=(--config) ;;
    tick-lock.sh)   args+=(--instance "$ABSENT") ;;
  esac
  printf '  probe  %s  ->  %s' "$f" "$s"; [ "${#args[@]}" -eq 0 ] || printf ' %q' "${args[@]}"; echo
  # PYTHONDONTWRITEBYTECODE: resolve-config.sh reaches python3, which caches .pyc under
  # $HOME and would fail section 3 for a write no probed script made.
  ( cd "$OUTSIDE" && HOME="$HOME_T" CLAUDE_CONFIG_DIR="$CFG_T" PYTHONDONTWRITEBYTECODE=1 \
      GIT_CEILING_DIRECTORIES="$TMP" bash "$run" ${args[@]+"${args[@]}"} ) >"$CAP/out" 2>"$CAP/err" </dev/null
  marker="$(grep -ciE 'usage:|unknown (option|argument|flag|command|role)|unexpected argument|multiple target|needs (a value|a directory|an id)|no agent id|agent id (contains|is longer)|no such key' "$CAP/err" 2>/dev/null)"
  ok "$f: '$line' is accepted by $s" "${marker:-0}" 0
  [ "${marker:-0}" = 0 ] || sed 's/^/           stderr: /' "$CAP/err" | head -2
  probed=$((probed+1))
done <<<"$(printf '%s' "$found")"
echo
echo "  coverage  $total notices found, $probed probed"
ok "every notice found was probed" "$probed/$total" "$total/$total"
ok "a kb-sync.sh commit notice was checked for usability" "$([ "$kbcommit" -gt 0 ] && echo yes || echo no)" yes
ok "the harness probed something" "$([ "$probed" -gt 0 ] && echo yes || echo no)" yes

echo
echo "== 3. the probes wrote nothing anywhere =="
ok "the throwaway cwd is unchanged"      "$(snap "$OUTSIDE")" "$b_outside"
ok "the temp HOME is unchanged"          "$(snap "$HOME_T")"  "$b_home"
ok "the temp CLAUDE_CONFIG_DIR is same"  "$(snap "$CFG_T")"   "$b_cfg"
ok "the fake bundle is unchanged"        "$(snap "$BUNDLE")"  "$b_bundle"
ok "the absent --instance stays absent"  "$([ -e "$ABSENT" ] && echo created || echo absent)" absent
ok "the repo checkout is unchanged"      "$(git -C "$REPO" status --porcelain 2>/dev/null)" "$before_git"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
