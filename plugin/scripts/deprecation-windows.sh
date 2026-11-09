#!/usr/bin/env bash
# deprecation-windows.sh — every deprecation window names its end version, and none is past it.
#
#   deprecation-windows.sh [--root DIR] [--version X.Y.Z]   scan; VERSION defaults to DIR/VERSION
#   deprecation-windows.sh --cmp A B                         print lt|eq|gt, per field, numerically
#
# Scans plugin/ and docs/operations.md under DIR (the repo root by default) and prints:
#   BARE <file>:<line>     a release-relative window with no `until <x.y.z>` on the same line
#   EXPIRED <file>:<line>  an `until <x.y.z>` the version has reached (version >= until)
# Exit: 0 none · 1 at least one · 2 usage or unreadable.
# Callers: tests/deprecation-windows.test.sh (VERSION) and release-bump.sh (the version it would mint).
set -uo pipefail

usage() { sed -n '2,10p' "$0" >&2; exit 2; }
is_ver() { printf '%s' "$1" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; }

vcmp() { # <a> <b> -> lt|eq|gt
  local a b i x y
  IFS=. read -r -a a <<<"$1"; IFS=. read -r -a b <<<"$2"
  for i in 0 1 2; do
    x=$((10#${a[$i]})); y=$((10#${b[$i]}))
    [ "$x" -lt "$y" ] && { echo lt; return; }
    [ "$x" -gt "$y" ] && { echo gt; return; }
  done
  echo eq
}

# Spelled with [[:space:]] so this file never matches the phrases it looks for.
WINDOW='one[[:space:]]+release|next[[:space:]]+release|one[[:space:]]+more[[:space:]]+release'
UNTIL='until[[:space:]]+`?v?[0-9]+\.[0-9]+\.[0-9]+'
PATHS=(plugin docs/operations.md)

ROOT=""; VER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --cmp)
      [ $# -eq 3 ] && is_ver "$2" && is_ver "$3" || usage
      vcmp "$2" "$3"; exit 0 ;;
    --root)    [ $# -ge 2 ] || usage; ROOT="$2"; shift 2 ;;
    --version) [ $# -ge 2 ] || usage; VER="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

if [ -z "$ROOT" ]; then
  _d="$(dirname "$0")"; if [ -L "$_d" ] && [ ! -f "$(dirname "$_d")/VERSION" ]; then _t="$(readlink "$_d")"; case "$_t" in /*) _d="$_t" ;; *) _d="$(dirname "$_d")/$_t" ;; esac; fi
  ROOT="$(cd "$_d/../.." && pwd)"
fi
[ -d "$ROOT/plugin" ] || { echo "deprecation-windows: no plugin/ under $ROOT" >&2; exit 2; }
[ -n "$VER" ] || VER="$(head -n 1 "$ROOT/VERSION" 2>/dev/null | tr -d '[:space:]')"
is_ver "$VER" || { echo "deprecation-windows: version is not MAJOR.MINOR.PATCH: '$VER'" >&2; exit 2; }

found=0
existing=()
for p in "${PATHS[@]}"; do [ -e "$ROOT/$p" ] && existing+=("$p"); done
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  loc="${hit%%:*}:$(printf '%s' "${hit#*:}" | cut -d: -f1)"
  text="${hit#*:*:}"
  if printf '%s' "$text" | grep -qiE "$WINDOW" && ! printf '%s' "$text" | grep -qiE "$UNTIL"; then
    echo "BARE $loc"; found=1
  fi
  for u in $(printf '%s' "$text" | grep -oiE "$UNTIL" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'); do
    [ "$(vcmp "$VER" "$u")" = lt ] || { echo "EXPIRED $loc until $u (version $VER)"; found=1; }
  done
done <<EOF
$(cd "$ROOT" && grep -rnIiE "$WINDOW|$UNTIL" "${existing[@]}" 2>/dev/null)
EOF
exit "$found"
