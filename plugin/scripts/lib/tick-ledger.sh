# tick-ledger.sh — sourced, never run: the tick ledger's files, the flat $AB_LEDGER and the
# monthly UTC shards $AB_LEDGER_DIR/<YYYY-MM>.md. Not the KB's per-item ledger.sh.
# Default window: the clock's month and the one before it; --all reads every shard; --at <rev>
# reads the one commit <rev> names, printed as its id. The clock is TICK_LEDGER_NOW, else the UTC clock.
# The concatenated read is NOT chronological — project sections sit at the flat file's head —
# so a caller matches lines and never relies on their order.
# Every function returns, never exits: 0 ok (an empty ledger included), 2 a bad argument, an
# unreadable shard directory, revision or file. Reasoning: bound-loopd-dir-growth/task-001.
. "$(dirname "${BASH_SOURCE[0]}")/../bundle-paths.sh" || return 2

_tick_ledger_month() { # [<ISO ts>]
  local t="${1:-${TICK_LEDGER_NOW:-}}"
  [ -n "$t" ] || t="$(date -u +%Y-%m)"
  case "$t" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9] | [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] | \
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T*Z) ;;
    *) return 2 ;;
  esac
  case "${t:5:2}" in 0[1-9] | 1[0-2]) printf '%s\n' "${t:0:7}" ;; *) return 2 ;; esac
}

_tick_ledger_prev() { # <YYYY-MM>
  local y=$((10#${1%-*})) m=$((10#${1#*-} - 1))
  if [ "$m" -eq 0 ]; then m=12; y=$((y - 1)); fi
  printf '%04d-%02d\n' "$y" "$m"
}

_tick_ledger_opts() { # <root> [--all] [--at <rev>]
  local root="$1"
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --all) all=1 ;;
      --at) [ -n "${2:-}" ] || return 2; at="$2"; shift ;;
      *) return 2 ;;
    esac
    shift
  done
  if [ -n "$at" ]; then at="$(git -C "$root" rev-parse --verify --quiet "$at^{commit}" 2>/dev/null)" || return 2; fi
}

_tick_ledger_names() { # <root> <all> <at>
  local root="$1" all="$2" at="$3" now prev listing n flat="" shards="" d="$1/$AB_LEDGER_DIR"
  now="$(_tick_ledger_month)" || return 2
  prev="$(_tick_ledger_prev "$now")"
  if [ -n "$at" ]; then
    listing="$(git -C "$root" ls-tree "$at" -- "$AB_LEDGER" "$AB_LEDGER_DIR/" 2>/dev/null)" || return 2
    listing="$(printf '%s\n' "$listing" | awk -F'\t' '$1 ~ / blob / { print $2 }')"
  else
    [ -d "$root" ] && [ -x "$root" ] || return 2
    if [ -e "$root/$AB_DIR" ] || [ -L "$root/$AB_DIR" ]; then
      [ -d "$root/$AB_DIR" ] && [ -x "$root/$AB_DIR" ] || return 2
    fi
    if [ -e "$d" ] || [ -L "$d" ]; then
      [ -d "$d" ] && [ -r "$d" ] && [ -x "$d" ] || return 2
    fi
    if [ -f "$root/$AB_LEDGER" ]; then listing="$AB_LEDGER"; fi
    for n in "$d"/[0-9][0-9][0-9][0-9]-[0-9][0-9].md; do
      if [ -f "$n" ]; then listing="${listing:+$listing$'\n'}$AB_LEDGER_DIR/${n##*/}"; fi
    done
  fi
  while IFS= read -r n; do
    case "$n" in
      "$AB_LEDGER") flat=1 ;;
      "$AB_LEDGER_DIR"/[0-9][0-9][0-9][0-9]-[0-9][0-9].md)
        if [ -n "$all" ] || [ "$n" = "$AB_LEDGER_DIR/$now.md" ] || [ "$n" = "$AB_LEDGER_DIR/$prev.md" ]; then
          shards="$shards$n"$'\n'
        fi ;;
    esac
  done <<<"${listing:-}"
  if [ -n "$flat" ]; then printf '%s\n' "$AB_LEDGER"; fi
  if [ -n "$shards" ]; then printf '%s' "$shards" | LC_ALL=C sort; fi
}

tick_ledger_shard() { # <root> [<ISO ts>]
  local m
  [ -n "${1:-}" ] || return 2
  m="$(_tick_ledger_month "${2:-}")" || return 2
  printf '%s/%s/%s.md\n' "$1" "$AB_LEDGER_DIR" "$m"
}

tick_ledger_files() { # <root> [--all] [--at <rev>]
  local root="${1:-}" all="" at="" names n
  [ -n "$root" ] || return 2
  shift
  _tick_ledger_opts "$root" "$@" || return 2
  names="$(_tick_ledger_names "$root" "$all" "$at")" || return 2
  [ -n "$names" ] || return 0
  while IFS= read -r n; do
    if [ -n "$at" ]; then printf '%s:%s\n' "$at" "$n"; else printf '%s/%s\n' "$root" "$n"; fi
  done <<<"$names"
}

_tick_ledger_cat() { # <root> <at> <names>
  local n
  while IFS= read -r n; do
    if [ -n "$2" ]; then git -C "$1" show "$2:$n" 2>/dev/null || return 2
    else cat "$1/$n" 2>/dev/null || return 2; fi
  done <<<"$3"
}

tick_ledger_read() { # <root> [--all] [--at <rev>]
  local root="${1:-}" all="" at="" names out
  [ -n "$root" ] || return 2
  shift
  _tick_ledger_opts "$root" "$@" || return 2
  names="$(_tick_ledger_names "$root" "$all" "$at")" || return 2
  [ -n "$names" ] || return 0
  out="$(_tick_ledger_cat "$root" "$at" "$names" && printf x)" || return 2
  printf '%s' "${out%x}"
}
