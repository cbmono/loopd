#!/usr/bin/env bash
#
# refresh-state.sh — Stop, SubagentStop and UserPromptSubmit hook (loopd machinery).
# Starts ${CLAUDE_PLUGIN_ROOT}/scripts/refresh-state.sh for this session's bundle, detached,
# and returns at once — no output, exit 0 — so /pane's two files follow the turn, not the tick.
# The bundle is CLAUDE_PROJECT_DIR, or — in a linked worktree — what `<common dir>/loopd-bundle`
# names, trusted only when that bundle links this repo back (a `repos/*` resolving to the main
# clone, as link-repos.sh made it). Either way ab_board_root must pass: canonical, absolute,
# config + .loopd/ + SNAPSHOT.json. Unlike deny-destructive.sh this one WRITES, so a marker
# naming any other folder starts nothing. No network.
set -uo pipefail

self="${BASH_SOURCE[0]:-$0}"; case "$self" in /*) ;; *) self="$PWD/$self" ;; esac
plug="${CLAUDE_PLUGIN_ROOT:-${self%/hooks/*}}"
[ -f "$plug/scripts/refresh-state.sh" ] || exit 0
# Sourced only once a candidate exists: every session on the machine runs this hook.
load() { . "$plug/scripts/bundle-paths.sh" 2>/dev/null; }

dir="$(cd -P -- "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null && pwd -P)" || exit 0
root=""
if [ -f "$dir/instance.config.json" ]; then
  root="$dir"
elif [ -f "$dir/.git" ]; then
  gd=""; IFS= read -r gd < "$dir/.git" 2>/dev/null || gd=""
  gd="${gd#gitdir:}"; gd="${gd# }"
  case "$gd" in ""|/*) ;; *) gd="$dir/$gd" ;; esac
  cd_="$gd"
  if [ -n "$gd" ] && [ -f "$gd/commondir" ]; then
    c=""; IFS= read -r c < "$gd/commondir" 2>/dev/null || c=""
    case "$c" in "") ;; /*) cd_="$c" ;; *) cd_="$gd/$c" ;; esac
  fi
  b=""; [ -n "$cd_" ] && [ -f "$cd_/loopd-bundle" ] && { IFS= read -r b < "$cd_/loopd-bundle" 2>/dev/null || b=""; }
  [ -n "$b" ] && load || exit 0
  clone="$(cd -P -- "$cd_/.." 2>/dev/null && pwd -P)" || clone=""
  b="$(ab_board_root "$b")" || b=""
  if [ -n "$b" ] && [ -n "$clone" ]; then
    for l in "$b"/repos/*; do
      [ -L "$l" ] && [ "$(cd -P -- "$l" 2>/dev/null && pwd -P)" = "$clone" ] && { root="$b"; break; }
    done
  fi
fi
[ -n "$root" ] && load && root="$(ab_board_root "$root")" || exit 0
# All three streams closed: the hook returns now and the session never waits on the write.
nohup bash "$plug/scripts/refresh-state.sh" "$root" </dev/null >/dev/null 2>&1 &
exit 0
