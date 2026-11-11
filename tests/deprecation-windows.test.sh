#!/usr/bin/env bash
#
# deprecation-windows.test.sh — every deprecation window the scanner covers (plugin/,
# README.md, .claude/rules/, docs/operations.md, docs/conventions.md) names its end
# version (`until <x.y.z>`) on the same line, and VERSION has not reached it. The scanner
# and the version comparator are one helper, plugin/scripts/deprecation-windows.sh, which
# release-bump.sh also calls: a PR carries no version bump, so the bump refuses to cross an
# open `until` and this harness never turns main red on its own.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DW="$REPO/plugin/scripts/deprecation-windows.sh"
[ -f "$DW" ] || { echo "deprecation-windows.test: missing $DW" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/deprecation-windows.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-60s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-60s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
rc() { bash "$DW" "$@" >/dev/null 2>&1; echo $?; }
scanrc() { { bash "$DW" "$@"; echo "rc=$?"; } 2>&1 | tr '\n' ' ' | sed 's/ $//'; }
fixture() { # <dir> <version> <line> — a root whose plugin/ carries one line
  mkdir -p "$1/plugin" "$1/docs"
  printf '%s\n' "$2" > "$1/VERSION"
  printf 'intro\n%s\n' "$3" > "$1/plugin/doc.md"
}

echo "== the comparator is per field and numeric =="
ok "4.10.0 > 4.9.1"                  "$(bash "$DW" --cmp 4.10.0 4.9.1)" gt
ok "1.2.3 < 1.10.0"                  "$(bash "$DW" --cmp 1.2.3 1.10.0)" lt
ok "4.9.1 = 4.9.1"                   "$(bash "$DW" --cmp 4.9.1 4.9.1)" eq
ok "a non-version is a usage error"  "$(rc --cmp 4.9 4.9.1)" 2

echo "== a bare window fails =="
fixture "$TMP/bare" 4.9.1 'The flag is accepted for one release.'
ok "a bare 'for one release' exits 1"  "$(rc --root "$TMP/bare")" 1
ok "…naming file:line"                 "$(bash "$DW" --root "$TMP/bare" | grep -c '^BARE plugin/doc.md:2$')" 1
fixture "$TMP/next" 4.9.1 'Required from the next release.'
ok "'next release' is bare too"        "$(rc --root "$TMP/next")" 1
fixture "$TMP/ops" 4.9.1 'nothing here'
printf 'It clears for one more release.\n' > "$TMP/ops/docs/operations.md"
ok "docs/operations.md is scanned"     "$(rc --root "$TMP/ops")" 1
printf 'It clears for one more release.\n' > "$TMP/ops/docs/other.md"
rm "$TMP/ops/docs/operations.md"
ok "…and another docs/ file is not"    "$(rc --root "$TMP/ops")" 0

echo "== the version wording is a window too, and bare 'one version' is not =="
fixture "$TMP/fov" 4.9.1 'It shipped for one version as this stub.'
ok "a bare 'for one version' is BARE, exit 1" "$(scanrc --root "$TMP/fov")" "BARE plugin/doc.md:2 rc=1"
fixture "$TMP/nv" 4.9.1 'Delete it at the next version.'
ok "a bare 'next version' is BARE, exit 1" "$(scanrc --root "$TMP/nv")" "BARE plugin/doc.md:2 rc=1"
fixture "$TMP/omv" 4.9.1 'Accepted for one more version.'
ok "a bare 'one more version' is BARE, exit 1" "$(scanrc --root "$TMP/omv")" "BARE plugin/doc.md:2 rc=1"
fixture "$TMP/fovu" 4.9.1 'Kept for one version, until 4.10.0.'
ok "…and with an until still ahead, 0" "$(rc --root "$TMP/fovu")" 0
fixture "$TMP/ov" 4.9.1 'One version, in FOUR files, and they move together.'
ok "bare 'one version' is not a window" "$(rc --root "$TMP/ov")" 0
for p in README.md .claude/rules/r.md docs/conventions.md; do
  d="$TMP/scope-$(printf '%s' "$p" | tr '/.' '__')"; fixture "$d" 4.9.1 'nothing here'
  mkdir -p "$d/$(dirname "$p")"; printf 'Accepted for one version.\n' > "$d/$p"
  ok "$p is scanned"                   "$(scanrc --root "$d")" "BARE $p:1 rc=1"
done

echo "== an until the version has reached fails, one ahead of it passes =="
fixture "$TMP/eq" 4.9.1 'Accepted for one release, until 4.9.1.'
ok "VERSION = until exits 1"           "$(rc --root "$TMP/eq")" 1
ok "…naming file:line"                 "$(bash "$DW" --root "$TMP/eq" | grep -c '^EXPIRED plugin/doc.md:2 until 4.9.1')" 1
fixture "$TMP/gt" 4.10.0 'Kept until `4.9.2`.'
ok "VERSION > until exits 1 (4.10.0 vs 4.9.2)" "$(rc --root "$TMP/gt")" 1
fixture "$TMP/open" 4.9.1 'Accepted for one release, until 4.10.0.'
ok "an until still ahead exits 0"      "$(rc --root "$TMP/open")" 0
ok "--version overrides VERSION"       "$(rc --root "$TMP/open" --version 4.10.0)" 1

echo "== the repo itself =="
ok "the repo at HEAD carries no bare or expired window" "$(rc --root "$REPO")" 0
[ "$(rc --root "$REPO")" = 0 ] || bash "$DW" --root "$REPO" | sed 's/^/        /'

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
