#!/usr/bin/env bash
#
# cli-theme.sh — THE one place a plugin surface's SGR escapes are spelled. Sourced:
# `ab_theme <0|1> [auto|truecolor|ansi256|basic]` sets T_OFF T_BOLD T_BLUE T_PINK T_GREEN
# T_INK T_MUTED T_DIM T_DIMI, all empty when colour is off. The CALLER decides colour at all
# (`--color`/`--format`/`NO_COLOR`), so COLORTERM and `tput` are asked only when it is on;
# `auto` picks the tier, `basic` probes nothing. Callers pair `. cli-theme.sh 2>/dev/null`
# with `command -v ab_theme || ab_theme() { :; }` and read `${T_…:-}`: no theme, no colour,
# never a blank banner or status line.
# Codes are COPIED from cli-theme.json (GREEN: theme-palette.txt's #76d6a4), never composed;
# `basic` keeps the banner's own 94/95/92/93. BLUE is the machine, PINK waits on a human,
# GREEN is sent, saved and finished, and also running agents on the status line, by the
# owner's decision of 2026-10-18; no other machine-progress surface turns green. Ink is
# weight, muted is body, dim is chrome, dim italic (SGR 3 on dim) is a status line.

# shellcheck disable=SC2034  # every T_* below is set FOR the caller, by design
ab_theme() {
  local on="${1:-0}" tier="${2:-auto}" esc tc
  T_OFF=""; T_BOLD=""; T_BLUE=""; T_PINK=""; T_GREEN=""; T_INK=""; T_MUTED=""; T_DIM=""; T_DIMI=""
  [ "$on" = 1 ] || return 0
  # printf, not a typed ESC (invisible in a diff); `${esc}[` braced (SC1087).
  esc="$(printf '\033')"
  if [ "$tier" = auto ]; then
    tc=0
    if command -v tput >/dev/null 2>&1; then tc="$(tput colors 2>/dev/null || echo 0)"; fi
    case "$tc" in ''|*[!0-9]*) tc=0 ;; esac
    case "${COLORTERM:-}" in
      truecolor|24bit) tier=truecolor ;;
      *) if [ "$tc" -ge 256 ]; then tier=ansi256; else tier=basic; fi ;;
    esac
  fi
  T_OFF="${esc}[0m"; T_BOLD="${esc}[1m"
  case "$tier" in
    truecolor)
      T_BLUE="${esc}[38;2;94;162;255m";   T_PINK="${esc}[38;2;255;122;194m"
      T_GREEN="${esc}[38;2;118;214;164m"
      T_INK="${esc}[1;38;2;233;237;244m"; T_MUTED="${esc}[38;2;154;164;181m"
      T_DIM="${esc}[38;2;108;116;136m" ;;
    ansi256)
      T_BLUE="${esc}[38;5;75m";   T_PINK="${esc}[38;5;212m"
      T_GREEN="${esc}[38;5;115m"
      T_INK="${esc}[1;38;5;255m"; T_MUTED="${esc}[38;5;248m"
      T_DIM="${esc}[38;5;243m" ;;
    *)
      T_BLUE="${esc}[94m"; T_PINK="${esc}[95m"; T_GREEN="${esc}[92m"
      T_INK="${esc}[1;93m"; T_MUTED=""; T_DIM="${esc}[2m" ;;
  esac
  # Dim italic rides on the dim code, so the two can never disagree: `[2m` -> `[3;2m`.
  T_DIMI="${esc}[3;${T_DIM#"${esc}["}"
}
