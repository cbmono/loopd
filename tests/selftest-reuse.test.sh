#!/usr/bin/env bash
#
# selftest-reuse.test.sh — a sibling's `--self-test` verdict is reused while that sibling's
# bytes are unchanged, and never otherwise: `plugin/scripts/review-rounds.sh` and
# `plugin/scripts/required-checks.sh` (`selftest_ok`).
#
# WHY IT EXISTS. Both scripts self-test `review-clearance.sh` (and required-checks.sh also
# `pr-body-clearance.sh`) before trusting it, because a present-but-broken sibling makes the
# gate disappear rather than fail. That rule stays. What changed is that the self-test is
# no longer re-run for bytes it has already passed: `pr-body-clearance.sh`'s takes 2-4 s,
# and it ran on every gate evaluation (measured 2026-10-05: 100 s of one harness, 52 s after).
#
# THE PROPERTIES, each from both sides — a reuse that could not be defeated would be the
# gate disappearing by another route:
#   * the SAME bytes are self-tested once, not once per call;
#   * ANY change to the bytes (edited, truncated, swapped) is self-tested again;
#   * a FAILING self-test is never recorded — it refuses every time and is re-run every time;
#   * a record that does not carry the expected line is not a pass;
#   * an unwritable record directory changes nothing but the saving;
#   * the two copies of the function are identical.
# The vehicle is review-rounds.sh with a counting stand-in for its sibling: the caller is
# the real script, so what is proven is the caller's behaviour, not a copy of the function.
# Fixtures live under mktemp; ok() compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
RR="$REPO/plugin/scripts/review-rounds.sh"
RC="$REPO/plugin/scripts/required-checks.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/selftestreuse.XXXXXX")" || {
  echo "selftest-reuse.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}." >&2; exit 2; }
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed (review-rounds.sh requires it)"; exit 0; }

# A `gh` that fails: review-rounds.sh reaches its self-test before it asks gh anything, and
# what it does afterwards is not this harness's subject.
BIN="$TMP/bin"; mkdir -p "$BIN"; printf '#!/bin/sh\nexit 1\n' > "$BIN/gh"; chmod +x "$BIN/gh"

# The stand-in sibling: counts every --self-test it is asked for, then answers <line>.
sibling() { # <dir> <line-it-prints> [extra trailing comment]
  cat > "$1/review-clearance.sh" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "--self-test" ]; then echo x >> "$1/selftests.count"; echo "$2"; exit 0; fi
exit 2
${3:-}
EOF
  chmod +x "$1/review-clearance.sh"
}
count() { [ -f "$1/selftests.count" ] && wc -l < "$1/selftests.count" | tr -d ' ' || echo 0; }
lab() { # <name> -> a dir holding the REAL caller beside a stand-in sibling
  mkdir -p "$TMP/$1" "$TMP/$1.cache"
  # The caller sources its layout resolver from beside itself before anything else.
  cp "$RR" "$REPO/plugin/scripts/bundle-paths.sh" "$REPO/plugin/scripts/plugin-name.sh" "$TMP/$1/"
  printf '%s' "$TMP/$1"
}
call() { # <lab dir> -> runs the real caller once; prints its exit code
  PATH="$BIN:$PATH" TMPDIR="$1.cache" bash "$1/review-rounds.sh" 1 >/dev/null 2>"$1/err"; printf '%s' "$?"
}
OKLINE="review-clearance: self-test ok"

echo "== the same bytes are self-tested once =="
L="$(lab same)"; sibling "$L" "$OKLINE"
call "$L" >/dev/null
ok "the first call runs the self-test"              "$(count "$L")" 1
call "$L" >/dev/null; call "$L" >/dev/null
ok "two more calls do not run it again"             "$(count "$L")" 1
ok "…and the caller did not refuse on the sibling"  "$(grep -c 'does not run' "$L/err")" 0
ok "a record was written, private to the user"      "$(find "$L.cache" -type d -name 'loopd-selftest.*' -perm 700 | wc -l | tr -d ' ')" 1

echo "== any change to the bytes is self-tested again =="
sibling "$L" "$OKLINE" "# one byte more"
call "$L" >/dev/null
ok "an edited sibling is self-tested again"         "$(count "$L")" 2
call "$L" >/dev/null
ok "…and then reused in its turn"                   "$(count "$L")" 2
printf '#!/usr/bin/env bash\necho x >> "%s/selftests.count"; exit 1\n' "$L" > "$L/review-clearance.sh"
ok "a TRUNCATED sibling is refused (exit 2)"        "$(call "$L")" 2
ok "…having been asked, not waved through"          "$(count "$L")" 3
ok "…with the caller's own fail-closed message"     "$(grep -c 'is present but does not run' "$L/err")" 1

echo "== a failing self-test is never recorded =="
F="$(lab failing)"; sibling "$F" "something else entirely"
ok "a sibling answering the wrong line is refused"  "$(call "$F")" 2
ok "…and again on the second call"                  "$(call "$F")" 2
ok "…self-tested BOTH times: nothing was reused"    "$(count "$F")" 2
ok "…and no record exists for it"                   "$(find "$F.cache" -type f | wc -l | tr -d ' ')" 0

echo "== a record that does not carry the expected line is not a pass =="
P="$(lab planted)"; sibling "$P" "$OKLINE"
call "$P" >/dev/null
rec="$(find "$P.cache" -type f)"   # exactly one: the labs share nothing
ok "the record holds exactly the expected line"     "$(cat "$rec")" "$OKLINE"
printf 'ok\n' > "$rec"
call "$P" >/dev/null
ok "a record saying something else is ignored"      "$(count "$P")" 2
: > "$rec"
call "$P" >/dev/null
ok "…and so is an empty one"                        "$(count "$P")" 3

echo "== an unwritable record directory changes nothing but the saving =="
U="$(lab unwritable)"; sibling "$U" "$OKLINE"; chmod 500 "$U.cache"
ok "the caller still gets past its self-test"       "$(call "$U" >/dev/null; grep -c 'does not run' "$U/err")" 0
call "$U" >/dev/null
ok "…running it every call, as it always did"       "$(count "$U")" 2
chmod 700 "$U.cache"

echo "== the real siblings, and the two copies =="
fn() { awk '/^selftest_ok\(\) \{/ { p = 1 } p { print } p && /^\}/ { exit }' "$1"; }
ok "review-rounds.sh and required-checks.sh carry the same function" \
   "$([ -n "$(fn "$RR")" ] && [ "$(fn "$RR")" = "$(fn "$RC")" ] && echo same || echo DIFFER)" same
ok "neither calls a sibling's --self-test outside it" \
   "$(cat "$RR" "$RC" | grep -v '^[[:space:]]*#' | grep -c -- '--self-test 2>/dev/null')" 2
R="$(lab real)"; cp "$REPO/plugin/scripts/review-clearance.sh" "$R/"
PATH="$BIN:$PATH" TMPDIR="$R.cache" bash "$R/review-rounds.sh" 1 >/dev/null 2>"$R/err"
ok "the REAL review-clearance.sh passes and is recorded" "$(find "$R.cache" -type f -name 'review-clearance.sh.*' | wc -l | tr -d ' ')" 1
ok "…under a key that is its checksum and byte count"    "$(basename "$(find "$R.cache" -type f)")" "review-clearance.sh.$(cksum < "$R/review-clearance.sh" | tr ' ' '-')"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
