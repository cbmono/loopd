#!/usr/bin/env bash
#
# script-classes.sh — the plugin scripts plugin/data/script-classes.txt gives one class.
#
#   Usage: script-classes.sh <read-only|writing> [<list>]   one name per line, in list order
#
# A list line is `<name> read-only` or `<name> writing <what it writes>`; the class is by
# effect and transitive. Exit: 0 printed · 2 usage or an unreadable list.
# Verified by tests/script-classes.test.sh.
set -uo pipefail

case "${1:-}" in read-only|writing) ;; *) echo "usage: script-classes.sh <read-only|writing> [<list>]" >&2; exit 2 ;; esac
list="${2:-$(dirname "${BASH_SOURCE[0]:-$0}")/../data/script-classes.txt}"
[ -r "$list" ] || { echo "script-classes.sh: cannot read $list" >&2; exit 2; }
awk -v c="$1" '$2 == c { print $1 }' "$list"
