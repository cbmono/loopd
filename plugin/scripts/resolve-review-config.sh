#!/usr/bin/env bash
#
# resolve-review-config.sh — the review-round budgets this bundle runs under.
#
#   Usage: resolve-review-config.sh [--instance DIR] [coderabbitRounds|qaRounds|reviewFixMaxLines]
#
# No key prints `<key> <value>` for all three; a key prints its value alone. Absent (or no
# instance.config.json) is the default: 1, 1, 300. Exit 0 resolved · 1 a value that is not
# an unquoted integer >= 0, each bad key named on stderr · 2 usage, or the config unreadable.
# Defaults and meaning: SCHEMA.md → "Per-machine config overrides".
set -uo pipefail

KEYS="coderabbitRounds qaRounds reviewFixMaxLines"
default_of() { case "$1" in reviewFixMaxLines) echo 300 ;; *) echo 1 ;; esac; }

inst="."; want=""
while [ $# -gt 0 ]; do
  case "$1" in
    --instance)
      [ $# -ge 2 ] || { echo "resolve-review-config: --instance needs a directory" >&2; exit 2; }
      inst="$2"; shift 2 ;;
    -h|--help) sed -n '3,5p' "$0"; exit 0 ;;
    coderabbitRounds|qaRounds|reviewFixMaxLines)
      [ -z "$want" ] || { echo "resolve-review-config: one key at most" >&2; exit 2; }
      want="$1"; shift ;;
    *) echo "resolve-review-config: unexpected argument $1" >&2; exit 2 ;;
  esac
done

self="${BASH_SOURCE[0]:-$0}"
[ -L "$self" ] && self="$(readlink "$self" 2>/dev/null || printf '%s' "$self")"
here="$(cd "$(dirname "$self")" 2>/dev/null && pwd)" || here=""
resolver="$here/resolve-config.sh"
[ -n "$here" ] && [ -f "$resolver" ] || {
  echo "resolve-review-config: resolve-config.sh not found beside this script" >&2; exit 2; }

out=""; bad=0
for k in $KEYS; do
  [ -z "$want" ] || [ "$want" = "$k" ] || continue
  # `--json` keeps a quoted "1" distinguishable from 1, so the type check below sees it.
  v="$(bash "$resolver" --instance "$inst" --json "$k" 2>/dev/null)"; rc=$?
  case "$rc" in
    0) ;;
    1) v="$(default_of "$k")" ;;
    *) echo "resolve-review-config: could not read $k (resolve-config.sh exit $rc)" >&2; exit 2 ;;
  esac
  case "$v" in
    ""|*[!0-9]*)
      echo "resolve-review-config: $k must be an unquoted integer >= 0" >&2
      bad=1; continue ;;
  esac
  if [ -n "$want" ]; then out="$v"; else out="$out$k $v
"; fi
done
[ "$bad" -eq 0 ] || exit 1
printf '%s\n' "${out%
}"
