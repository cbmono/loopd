#!/usr/bin/env bash
# script-classes.sh <read-only|writing> [<list>] — the scripts plugin/data/script-classes.txt
# gives that class, one per line. Exit: 0 printed · 2 usage or an unreadable list.
set -uo pipefail

case "${1:-}" in read-only|writing) ;; *) echo "usage: script-classes.sh <read-only|writing> [<list>]" >&2; exit 2 ;; esac
list="${2:-$(dirname "${BASH_SOURCE[0]:-$0}")/../data/script-classes.txt}"
[ -r "$list" ] || { echo "script-classes.sh: cannot read $list" >&2; exit 2; }
awk -v c="$1" '$2 == c { print $1 }' "$list"
