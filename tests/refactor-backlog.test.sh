#!/usr/bin/env bash
# refactor-backlog.test.sh — `refactor-backlog.sh`: add appends one line, a duplicate and
# each bad field are refused, the 200-open bound refuses and `done` frees a slot, two
# concurrent adds both land in one well-formed file, a backslash keeps dedup and the printed
# id intact, racing first adds from two orgs land one, and the file validates as a Backlog.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
RB="$REPO/plugin/scripts/refactor-backlog.sh"
VB="$REPO/plugin/scripts/validate-bundle.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/refactor-backlog.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 2
echo '{ "org": "o" }' > instance.config.json
F=knowledge/backlog/widget.md

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL  %s (want %s, got %s)\n' "$1" "$3" "$2"; fail=$((fail+1)); fi; }
rc() { "$@" >/dev/null 2>&1; echo $?; }
add() { # <path> <what> [extra args]
  local p="$1" w="$2"; shift 2
  bash "$RB" add --repo Acme/Widget --path "$p" --what "$w" --why "two copies drift" --by software-engineer "$@"; }
open_lines() { grep -c '^- \[ \] ' "$F"; }

echo "== add"
ok "add exits 0"                          "$(rc add src/a.ts 'Extract the parser')" 0
ok "one open entry"                       "$(open_lines)" 1
ok "frontmatter names the repo, lowercased" "$(sed -n 3p "$F")" "repo: acme/widget"
ok "the entry has five fields"            "$(grep '^- \[ \] ' "$F" | awk -F'|' '{print NF}')" 5
ok "a file outside a bundle is refused"   "$(cd / && rc bash "$RB" count)" 2

echo "== duplicate"
ok "same key, other case and spacing, refused" "$(rc add 'src/A.ts' '  extract   THE parser ')" 1
ok "…and nothing was appended"            "$(open_lines)" 1
ok "same what on another path is new"     "$(rc add src/b.ts 'Extract the parser')" 0

echo "== refused fields"
ok "a | in a field"                       "$(rc add src/c.ts 'a | b')" 1
ok "a newline in a field"                 "$(rc add src/c.ts $'two\nlines')" 1
ok "an empty field"                       "$(rc add '  ' 'Something')" 1
ok "201 characters"                       "$(rc add src/c.ts "$(printf 'x%.0s' $(seq 201))")" 1
ok "200 characters is accepted"           "$(rc add src/c.ts "$(printf 'y%.0s' $(seq 200))")" 0
ok "a bare repo name"                     "$(rc bash "$RB" add --repo widget --path p --what w --why y --by r)" 1
ok "another org's same-named repo"        "$(rc bash "$RB" add --repo other/widget --path p --what w --why y --by r)" 1
ok "still three open entries"             "$(open_lines)" 3

echo "== close"
id="$(bash "$RB" list --repo acme/widget | awk '/src\/a.ts/ {print $1}')"
ok "done closes an entry"                 "$(rc bash "$RB" "done" --repo acme/widget "$id")" 0
ok "…which is now [x]"                    "$(grep -c '^- \[x\] .*src/a.ts' "$F")" 1
ok "closing it twice is refused"          "$(rc bash "$RB" "done" --repo acme/widget "$id")" 1
ok "an unknown id is refused"             "$(rc bash "$RB" "done" --repo acme/widget rb-1)" 1
ok "a closed entry still deduplicates"    "$(rc add src/a.ts 'Extract the parser')" 1
ok "count is the open total"              "$(bash "$RB" count)" 2

echo "== a backslash in a field"
out="$(add 'src\new\tmp.c' 'split it')"; added="$(grep -oE 'rb-[0-9]+' <<<"$out")"
ok "the add lands"                        "$(grep -c 'src.new.tmp.c' "$F")" 1
ok "the id add prints is the id list shows" \
  "$(bash "$RB" list --repo acme/widget | awk '/tmp.c/ {print $1}')" "$added"
ok "the same add again is a duplicate"    "$(rc add 'src\new\tmp.c' 'split it')" 1
ok "done closes it by the printed id"     "$(rc bash "$RB" "done" --repo acme/widget "$added")" 0

echo "== bound"
for i in $(seq 198); do printf -- '- [ ] 2026-01-01 | f%s | w | y | r\n' "$i"; done >> "$F"
ok "200 open: the add is refused"         "$(rc add src/z.ts 'One more')" 1
id="$(bash "$RB" list --repo acme/widget | awk '/ f1 / {print $1}')"
bash "$RB" "done" --repo acme/widget "$id" >/dev/null 2>&1
ok "after a close the add lands"          "$(rc add src/z.ts 'One more')" 0

echo "== concurrent adds"
rm -rf knowledge
add src/p.ts 'First' >/dev/null 2>&1 & add src/q.ts 'Second' >/dev/null 2>&1 &
add src/p.ts 'First' >/dev/null 2>&1 & wait
ok "two distinct adds, one duplicate: two entries" "$(open_lines)" 2
ok "one frontmatter block"                "$(grep -c '^type: Backlog$' "$F")" 1
ok "the lock is released"                 "$(find knowledge/backlog -name '*.lock' | grep -c .)" 0

echo "== racing first adds from two orgs"
rm -rf knowledge; mkdir -p knowledge/backlog/.web.lock
bash "$RB" add --repo acme/web --path p --what w --why y --by r >/dev/null 2>&1 &
bash "$RB" add --repo other/web --path p --what v --why y --by r >/dev/null 2>&1 &
sleep 1; rmdir knowledge/backlog/.web.lock; wait
ok "exactly one lands"                    "$(grep -c '^- \[ \] ' knowledge/backlog/web.md)" 1
rm -rf knowledge
add src/p.ts 'First' >/dev/null 2>&1; add src/q.ts 'Second' >/dev/null 2>&1

echo "== validates as a Backlog"
out="$(bash "$VB" knowledge/backlog/widget.md 2>&1)"
ok "validate-bundle.sh exits 0 on it"     "$(rc bash "$VB" knowledge/backlog/widget.md)" 0
ok "…and reports no error for it"         "$(grep -c ERROR <<<"$out")" 0
ok "…having checked it, not skipped it"   "$(grep -c 'checked 1, ' <<<"$out")" 1

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
