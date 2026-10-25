#!/usr/bin/env bash
#
# qa-dispatch.sh — the project-manager's record that it sent loopd:qa-reviewer to a PR at a head.
#
#   Usage: qa-dispatch.sh mint  --repo <o>/<n> --pr <n> --head <sha> [--instance <bundle>]
#          qa-dispatch.sh check --repo <o>/<n> --pr <n> --head <sha> [--nonce <hex>] [--after <ISO>] [--instance <bundle>]
#
# mint prints a fresh nonce for the qa-reviewer's brief and records only its sha256.
# check: 0 a record matches (with --nonce — 32 lowercase hex — its hash; with --after, a record
# older than that time) · 1 none, or no bundle · 2 usage or unreadable. Threat model: SCHEMA.md → clause 8.
set -uo pipefail

ROLE="loopd:qa-reviewer"
usage() { sed -n '5,6p' "$0" | sed 's/^# *//' >&2; exit 2; }

cmd="${1:-}"; [ $# -gt 0 ] && shift
repo=""; pr=""; head=""; nonce=""; after=""; inst=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo|--pr|--head|--nonce|--after|--instance)
      [ $# -ge 2 ] && [ -n "$2" ] || usage
      case "$1" in
        --repo) repo="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')" ;;
        --pr) pr="$2" ;; --head) head="$2" ;; --nonce) nonce="$2" ;;
        --after) after="$2" ;; --instance) inst="$2" ;;
      esac
      shift 2 ;;
    *) usage ;;
  esac
done
case "$cmd" in mint|check) ;; *) usage ;; esac
printf '%s' "$repo" | grep -Eqx '[a-z0-9._-]+/[a-z0-9._-]+' || usage
printf '%s' "$pr" | grep -Eqx '[0-9]+' || usage
printf '%s' "$head" | grep -Eqx '[0-9a-f]{40}' || usage

if [ -z "$inst" ]; then
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$CLAUDE_PROJECT_DIR/instance.config.json" ]; then
    inst="$CLAUDE_PROJECT_DIR"
  else
    inst="$PWD"
    while [ "$inst" != / ] && [ ! -f "$inst/instance.config.json" ]; do inst="$(dirname "$inst")"; done
  fi
fi
if [ ! -f "$inst/instance.config.json" ]; then
  [ "$cmd" = check ] && exit 1
  echo "qa-dispatch: no bundle (instance.config.json) found" >&2; exit 2
fi
dir="$inst/.loopd/.qa-dispatch"; log="$dir/records"

sha256() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1
  else sha256sum | cut -d' ' -f1; fi
}

if [ "$cmd" = mint ]; then
  n="$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
  [ "${#n}" -eq 32 ] || { echo "qa-dispatch: could not generate a nonce" >&2; exit 2; }
  h="$(printf '%s' "$n" | sha256)"
  [ "${#h}" -eq 64 ] || { echo "qa-dispatch: could not hash the nonce" >&2; exit 2; }
  if ! mkdir -p "$dir" || ! { [ -e "$dir/.gitignore" ] || printf '*\n' > "$dir/.gitignore"; }; then
    echo "qa-dispatch: cannot write $dir" >&2; exit 2
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$repo" "$pr" "$head" "$ROLE" "$h" \
    >> "$log" || { echo "qa-dispatch: cannot append to $log" >&2; exit 2; }
  printf '%s\n' "$n"
  exit 0
fi

digits() { printf '%s' "$1" | grep -Eqx '[0-9]{4}(-[0-9]{2}){2}T([0-9]{2}:){2}[0-9]{2}Z' && printf '%s' "$1" | tr -cd '0-9'; }
want_h=""
if [ -n "$nonce" ]; then
  printf '%s' "$nonce" | grep -Eqx '[0-9a-f]{32}' || exit 1
  want_h="$(printf '%s' "$nonce" | sha256)"
fi
after_d=""; if [ -n "$after" ]; then after_d="$(digits "$after")" || exit 1; fi
[ -e "$log" ] || exit 1
[ -r "$log" ] || { echo "qa-dispatch: $log is unreadable" >&2; exit 2; }
while IFS=$'\t' read -r at r p h role hash; do
  [ "$r" = "$repo" ] && [ "$p" = "$pr" ] && [ "$h" = "$head" ] && [ "$role" = "$ROLE" ] || continue
  [ -z "$want_h" ] || [ "$hash" = "$want_h" ] || continue
  if [ -n "$after_d" ]; then
    at_d="$(digits "$at")" || continue
    [ "$after_d" -gt "$at_d" ] || continue
  fi
  exit 0
done < "$log"
exit 1
