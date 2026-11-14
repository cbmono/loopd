#!/usr/bin/env bash
#
# refresh-state.sh — Stop, SubagentStop and UserPromptSubmit hook (loopd machinery).
# Starts ${CLAUDE_PLUGIN_ROOT}/scripts/refresh-state.sh for this session's bundle, detached,
# and returns at once — no output, exit 0 — so /pane's two files follow the turn, not the tick.
# The bundle: CLAUDE_PROJECT_DIR, or what a linked worktree's `loopd-bundle` marker names (the
# instance-root guard, copied from deny-destructive.sh). Anything else ⇒ silent. No network.
set -uo pipefail

INSTANCE_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
INSTANCE_ROOT="$(cd "$INSTANCE_ROOT" 2>/dev/null && pwd -P || printf '%s' "$INSTANCE_ROOT")"
if [ ! -f "$INSTANCE_ROOT/instance.config.json" ] && [ -f "$INSTANCE_ROOT/.git" ]; then
  _gd=""; IFS= read -r _gd < "$INSTANCE_ROOT/.git" 2>/dev/null || _gd=""
  _gd="${_gd#gitdir:}"; _gd="${_gd# }"
  case "$_gd" in ""|/*) ;; *) _gd="$INSTANCE_ROOT/$_gd" ;; esac
  _cd="$_gd"
  if [ -n "$_gd" ] && [ -f "$_gd/commondir" ]; then
    _c=""; IFS= read -r _c < "$_gd/commondir" 2>/dev/null || _c=""
    case "$_c" in "") ;; /*) _cd="$_c" ;; *) _cd="$_gd/$_c" ;; esac
  fi
  if [ -n "$_cd" ] && [ -f "$_cd/loopd-bundle" ]; then
    _b=""; IFS= read -r _b < "$_cd/loopd-bundle" 2>/dev/null || _b=""
    if [ -n "$_b" ] && [ -f "$_b/instance.config.json" ]; then
      INSTANCE_ROOT="$(cd "$_b" 2>/dev/null && pwd -P || printf '%s' "$_b")"
    fi
  fi
  unset _gd _cd _c _b
fi
[ -f "$INSTANCE_ROOT/instance.config.json" ] || exit 0

self="${BASH_SOURCE[0]:-$0}"; case "$self" in /*) ;; *) self="$PWD/$self" ;; esac
worker="${CLAUDE_PLUGIN_ROOT:-${self%/hooks/*}}/scripts/refresh-state.sh"
[ -f "$worker" ] || exit 0
# All three streams closed: the hook returns now and the session never waits on the write.
nohup bash "$worker" "$INSTANCE_ROOT" </dev/null >/dev/null 2>&1 &
exit 0
