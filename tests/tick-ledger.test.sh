#!/usr/bin/env bash
#
# tick-ledger.test.sh — plugin/scripts/lib/tick-ledger.sh, the tick ledger's monthly-shard
# reader: the shard for a timestamp, the two-month default window (across a year too), --all,
# --at <rev>, the strict shard-name filter, flat file first, the write target, the empty case and the return-2
# edges, which must never exit the caller. Reasoning: bound-loopd-dir-growth/task-001.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$REPO/plugin/scripts/lib/tick-ledger.sh"
PATHS="$REPO/plugin/scripts/bundle-paths.sh"
[ -r "$LIB" ] || { echo "tick-ledger.test: $LIB is missing" >&2; exit 2; }
# shellcheck source=../plugin/scripts/lib/tick-ledger.sh
. "$LIB" || { echo "tick-ledger.test: sourcing $LIB failed" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tick-ledger.XXXXXX")" || {
  echo "tick-ledger.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}" >&2; exit 2; }
trap 'chmod -R u+rwx "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "${2//$'\n'/ }"; pass=$((pass+1))
  else printf '  FAIL  %-66s got [%s], want [%s]\n' "$1" "${2//$'\n'/ }" "${3//$'\n'/ }"; fail=$((fail+1)); fi
}
rc() { "$@" >/dev/null 2>&1; echo $?; }
files() { tick_ledger_files "$@" | sed "s|^$D/||"; }
nl() { printf '%s\n' "$@"; }

D="$TMP/bundle"
mkdir -p "$D/.loopd/log"
shard() { printf '* TICK %s-01T00:00:00Z open: x\n' "$1" >"$D/.loopd/log/$1.md"; }
for m in 2026-10 2026-11 2026-12 2027-01; do shard "$m"; done
printf '## project p\n* TICK 2026-09-01T00:00:00Z open: f\n' >"$D/.loopd/log.md"

echo "== bundle-paths.sh: the shard directory key =="
ok "AB_LEDGER_DIR is .loopd/log"               "$("$PATHS" AB_LEDGER_DIR)" ".loopd/log"
ok "AB_LEDGER keeps its value"                 "$("$PATHS" AB_LEDGER)" ".loopd/log.md"
ok "AB_LEDGER_DIR is exported"                 "$(bash -c '. "$1"; env | grep -c "^AB_LEDGER_DIR="' _ "$PATHS")" 1
ok "AB_KEYS lists it"                          "$(bash -c '. "$1"; case " $AB_KEYS " in *" AB_LEDGER_DIR "*) echo y ;; esac' _ "$PATHS")" y
ok "bundle-paths.sh does not source the library" "$(grep -c 'tick-ledger' "$PATHS")" 0

echo "== tick_ledger_shard =="
export TICK_LEDGER_NOW=2026-11-28T00:14:25Z
ok "no timestamp: the clock's month"           "$(tick_ledger_shard "$D")" "$D/.loopd/log/2026-11.md"
ok "a timestamp: its own month"                "$(tick_ledger_shard "$D" 2026-12-31T23:59:59Z)" "$D/.loopd/log/2026-12.md"
ok "a date alone"                              "$(tick_ledger_shard "$D" 2027-01-01)" "$D/.loopd/log/2027-01.md"
ok "a non-UTC offset is refused"               "$(rc tick_ledger_shard "$D" 2026-12-01T01:00:00+02:00)" 2
ok "month 13 is refused"                       "$(rc tick_ledger_shard "$D" 2026-13-01)" 2
ok "no root is refused"                        "$(rc tick_ledger_shard "")" 2
ok "a bad clock is refused"                    "$(TICK_LEDGER_NOW=soon; rc tick_ledger_shard "$D")" 2

echo "== the default window, flat file first =="
ok "the clock's month and the one before"      "$(files "$D")" "$(nl .loopd/log.md .loopd/log/2026-10.md .loopd/log/2026-11.md)"
ok "the 1st of a month reads the previous one" "$(TICK_LEDGER_NOW=2026-12-01T00:00:00Z files "$D")" "$(nl .loopd/log.md .loopd/log/2026-11.md .loopd/log/2026-12.md)"
ok "2027-01 reads 2026-12"                     "$(TICK_LEDGER_NOW=2027-01-15 files "$D")" "$(nl .loopd/log.md .loopd/log/2026-12.md .loopd/log/2027-01.md)"
ok "an absent month is skipped"                "$(TICK_LEDGER_NOW=2027-03-01T00:00:00Z files "$D")" ".loopd/log.md"
ok "--all: every shard, oldest to newest"      "$(files "$D" --all)" "$(nl .loopd/log.md .loopd/log/2026-10.md .loopd/log/2026-11.md .loopd/log/2026-12.md .loopd/log/2027-01.md)"
ok "the read concatenates in that order"       "$(tick_ledger_read "$D" | grep "^\* TICK" | cut -c8-17)" "$(nl 2026-09-01 2026-10-01 2026-11-01)"
ok "no plain-bash-portable clock is bypassed"  "$(grep -cE 'date[^|]*-(d|v)[[:space:]]' "$LIB")" 0

echo "== only <YYYY-MM>.md names are shards =="
for n in notes.md 2026-1.md 2026-11.md.bak x2026-11.md 2026-11.txt 2026-111.md; do echo junk >"$D/.loopd/log/$n"; done
mkdir -p "$D/.loopd/log/2026-10.md.d" "$D/.loopd/log/sub" && echo junk >"$D/.loopd/log/sub/2026-11.md"
rm "$D/.loopd/log/2026-10.md"; mkdir "$D/.loopd/log/2026-10.md"
ok "other names and a shard-named directory are ignored" "$(files "$D" --all)" "$(nl .loopd/log.md .loopd/log/2026-11.md .loopd/log/2026-12.md .loopd/log/2027-01.md)"
rmdir "$D/.loopd/log/2026-10.md"; shard 2026-10

echo "== --at <rev>: the committed files =="
( cd "$D" && git init -q . && git config user.name example-user-007 && git config user.email u@example.com \
  && git add -A && git commit -qm init ) || { echo "tick-ledger.test: git fixture failed" >&2; exit 2; }
sha="$(git -C "$D" rev-parse HEAD)"; head_flat="$(cat "$D/.loopd/log.md")"; head_nov="$(cat "$D/.loopd/log/2026-11.md")"
rm "$D/.loopd/log.md"; echo '* TICK late' >>"$D/.loopd/log/2026-11.md"; shard 2025-01
ok "lists the committed files under the commit id"  "$(tick_ledger_files "$D" --at HEAD)" "$(nl "$sha:.loopd/log.md" "$sha:.loopd/log/2026-10.md" "$sha:.loopd/log/2026-11.md")"
ok "--at with --all ignores an uncommitted shard" "$(tick_ledger_files "$D" --all --at HEAD | sed -n 1,2p)" "$(nl "$sha:.loopd/log.md" "$sha:.loopd/log/2026-10.md")"
ok "reads the committed bytes"                 "$(tick_ledger_read "$D" --at HEAD | sed -n '1,2p;4p')" "$(nl "$head_flat" "$head_nov")"
ok "the worktree read sees the edit"           "$(tick_ledger_read "$D" | tail -1)" "* TICK late"
ok "a revision that is not a commit returns 2"  "$(rc tick_ledger_read "$D" --at 'HEAD^{tree}')" 2
ok "an unknown revision returns 2"             "$(rc tick_ledger_files "$D" --at no-such-rev)" 2
ok "--at with no revision returns 2"           "$(rc tick_ledger_read "$D" --at)" 2
ok "an unknown flag returns 2"                 "$(rc tick_ledger_files "$D" --every)" 2

echo "== the empty case and the unreadable directory =="
E="$TMP/empty"; mkdir -p "$E"
ok "no flat file and no shards: nothing"       "$(tick_ledger_files "$E"; echo "rc=$?")" "rc=0"
ok "the empty read returns 0"                  "$(rc tick_ledger_read "$E")" 0
mkdir -p "$E/.loopd/log"
ok "an empty shard directory: nothing"         "$(tick_ledger_files "$E" --all; echo "rc=$?")" "rc=0"
ok "a set -e caller survives a flat-only ledger" "$(echo f >"$E/.loopd/log.md"; bash -ec '. "$1"; tick_ledger_files "$2" >/dev/null; tick_ledger_read "$2" >/dev/null; echo alive' _ "$LIB" "$E")" alive
ok "an absent root returns 2"                  "$(rc tick_ledger_files "$TMP/no-such-root")" 2
if [ "$(id -u)" = 0 ]; then echo "  SKIP  root reads a 000 directory; the unreadable case is unprovable here"
else
  chmod 000 "$E/.loopd"
  ok "an unsearchable bundle directory returns 2" "$(rc tick_ledger_files "$E")" 2
  ok "…and the read returns 2, not an empty ledger" "$(rc tick_ledger_read "$E")" 2
  chmod 755 "$E/.loopd"
  chmod 000 "$E/.loopd/log"
  ok "an unreadable shard directory returns 2"  "$(rc tick_ledger_files "$E")" 2
  ok "the caller is not exited"                 "$(bash -c '. "$1"; tick_ledger_read "$2"; echo "alive rc=$?"' _ "$LIB" "$E" 2>/dev/null)" "alive rc=2"
  chmod 755 "$E/.loopd/log"
  printf 'ends in x' >"$E/.loopd/log/2026-10.md"; echo '* TICK nov' >"$E/.loopd/log/2026-11.md"; chmod 000 "$E/.loopd/log/2026-11.md"
  ok "an unreadable shard: rc 2 and no partial output" "$(tick_ledger_read "$E"; echo "rc=$?")" "rc=2"
  chmod 644 "$E/.loopd/log/2026-11.md"
  ok "the same ledger reads whole once readable" "$(tick_ledger_read "$E")" "$(printf 'f\nends in x* TICK nov')"
fi
echo "== tick_ledger_last_full: the newest open+close pair across the window's files =="
L="$TMP/lastfull"; mkdir -p "$L/.loopd/log"
ok "no ledger: nothing, rc 0"                   "$(tick_ledger_last_full "$L"; echo "rc=$?")" "rc=0"
printf '* TICK 2026-11-02T00:00:00Z by a open: x\n* TICK 2026-11-02T00:00:00Z by a close: y\n' > "$L/.loopd/log.md"
printf '* TICK 2026-10-01T00:00:00Z by a open: x\n* TICK 2026-10-01T00:00:00Z by a close: y\n* TICK 2026-12-09T00:00:00Z by a close: no open line\n' > "$L/.loopd/log/2026-10.md"
printf '* TICK 2026-12-01T00:00:00Z by a open: x\n* TICK 2026-12-01T00:00:00Z by a close: y\n' > "$L/.loopd/log/2026-12.md"
ok "mixed: a shard's pair outranks the flat one" "$(TICK_LEDGER_NOW=2026-12 tick_ledger_last_full "$L")" 2026-12-01T00:00:00Z
rm "$L/.loopd/log/2026-12.md"
ok "…the flat pair outranks an older shard's"    "$(TICK_LEDGER_NOW=2026-12 tick_ledger_last_full "$L")" 2026-11-02T00:00:00Z
ok "…and a close with no open line is never full"     "$(TICK_LEDGER_NOW=2026-11 tick_ledger_last_full "$L")" 2026-11-02T00:00:00Z
echo "== tick_ledger_target / tick_ledger_ensure: the one write rule (D9) =="
W="$TMP/write"; mkdir -p "$W/.loopd"; printf '# Log\n' > "$W/.loopd/log.md"
ok "the flat ledger while it exists"           "$(TICK_LEDGER_NOW=2026-12 tick_ledger_target "$W")" .loopd/log.md
ok "…ensure leaves it byte-identical"         "$(tick_ledger_ensure "$W" .loopd/log.md; echo "rc=$?"; cat "$W/.loopd/log.md")" "$(printf 'rc=0\n# Log')"
rm "$W/.loopd/log.md"
ok "no flat file: the clock's shard"           "$(TICK_LEDGER_NOW=2026-12-01T00:00:05Z tick_ledger_target "$W")" .loopd/log/2026-12.md
ok "…a timestamp argument outranks the clock"  "$(TICK_LEDGER_NOW=2026-12 tick_ledger_target "$W" 2026-11-30T23:59:59Z)" .loopd/log/2026-11.md
ok "ensure creates the shard bare"             "$(tick_ledger_ensure "$W" .loopd/log/2026-12.md; echo "rc=$?"; wc -c < "$W/.loopd/log/2026-12.md" | tr -d ' ')" "$(printf 'rc=0\n0')"
ok "…never the flat ledger"                   "$(rc tick_ledger_ensure "$W" .loopd/log.md):$([ -e "$W/.loopd/log.md" ] && echo yes || echo no)" 2:no
mkdir -p "$TMP/notbundle"
ok "no .loopd/: rc 2, nothing created"         "$(rc tick_ledger_ensure "$TMP/notbundle" .loopd/log/2026-12.md):$(ls -A "$TMP/notbundle" | wc -l | tr -d ' ')" 2:0
R="$TMP/race"; lost=0
for r in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do
  mkdir -p "$R/$r/.loopd"
  for i in 1 2 3 4; do ( tick_ledger_ensure "$R/$r" .loopd/log/2026-12.md || echo lost >> "$R/$r.lost" ) & done; wait
  [ -f "$R/$r.lost" ] && lost=$((lost + $(wc -l < "$R/$r.lost")))
done
ok "four writers racing on a month's first shard: none fails" "$lost" 0
mkdir -p "$W/.loopd/log.md"
ok "a flat path that is not a file: rc 2"      "$(rc tick_ledger_target "$W")" 2
ok "no script outside the library builds a shard path" \
   "$(grep -lE 'AB_LEDGER_DIR\}?/\$|log/\$\(date' "$REPO"/plugin/scripts/*.sh | wc -l | tr -d ' ')" 0
ok "the library never calls exit"              "$(grep -cE '(^|[;&|[:space:]])exit([[:space:]]|$)' "$LIB")" 0
ok "the header says the read is not chronological" "$(sed -n '1,10p' "$LIB" | grep -c 'NOT chronological')" 1

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
