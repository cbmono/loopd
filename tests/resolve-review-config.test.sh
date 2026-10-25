#!/usr/bin/env bash
#
# resolve-review-config.test.sh — the three review-round keys: defaults, 0, and every bad
# value refused by name; plus `/loopd:welcome check` warning on one. Exit 0 = all pass.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SH="$REPO/plugin/scripts/resolve-review-config.sh"
WELCOME="$REPO/plugin/scripts/welcome.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/resolve-review-config.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
command -v jq >/dev/null 2>&1 || { echo "resolve-review-config.test: jq is required" >&2; exit 2; }
pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
res() { local o rc; o="$(bash "$SH" --instance "$TMP/i" "$@" 2>"$TMP/err")"; rc=$?
        printf '%s rc=%s' "$(printf '%s' "$o" | tr '\n' ' ')" "$rc"; }
cfg() { mkdir -p "$TMP/i"; printf '%s\n' "$1" > "$TMP/i/instance.config.json"; }

echo "== defaults =="
rm -rf "$TMP/i"; mkdir -p "$TMP/i"
ok "no instance.config.json: all three defaults" "$(res)" "coderabbitRounds 1 qaRounds 1 reviewFixMaxLines 300 rc=0"
cfg '{"org": "x"}'
ok "absent coderabbitRounds => 1"   "$(res coderabbitRounds)"  "1 rc=0"
ok "absent qaRounds => 1"           "$(res qaRounds)"          "1 rc=0"
ok "absent reviewFixMaxLines => 300" "$(res reviewFixMaxLines)" "300 rc=0"
cfg '{"coderabbitRounds": null}'
ok "null is absence => 1"            "$(res coderabbitRounds)"  "1 rc=0"
ok "resolve-config.sh still exits 1 on an absent key" \
   "$(bash "$REPO/plugin/scripts/resolve-config.sh" --instance "$TMP/i" qaRounds >/dev/null 2>&1; echo $?)" 1

echo "== integers >= 0, 0 included =="
cfg '{"coderabbitRounds": 0, "qaRounds": 3, "reviewFixMaxLines": 0}'
ok "0 / 3 / 0 resolve as written" "$(res)" "coderabbitRounds 0 qaRounds 3 reviewFixMaxLines 0 rc=0"

echo "== bad values: refused, the key named on stderr =="
for k in coderabbitRounds qaRounds reviewFixMaxLines; do
  for bad in true '"1"' -1 1.0; do
    cfg "{\"$k\": $bad}"
    out="$(res "$k")"
    ok "$k $bad: non-zero, no value" "$out" " rc=1"
    ok "…stderr names $k" "$(grep -c "$k" "$TMP/err" | tr -d ' ')" 1
  done
done
cfg '{"reviewFixMaxLines": 999999999}'
ok "9 digits resolve" "$(res reviewFixMaxLines)" "999999999 rc=0"
cfg '{"reviewFixMaxLines": 99999999999999999999}'
ok "20 digits are refused (they overflow the callers' test)" "$(res reviewFixMaxLines)" " rc=1"
cfg '{"qaRounds": true}'
ok "one bad key fails the all-keys form too" "$(res)" " rc=1"

echo "== /loopd:welcome check: one warning line naming the bad key =="
W="$TMP/w"; mkdir -p "$W"
for k in coderabbitRounds qaRounds reviewFixMaxLines; do
  printf '{"org": "x", "%s": -1}\n' "$k" > "$W/instance.config.json"
  out="$(bash "$WELCOME" check --instance "$W" 2>&1)"
  ok "$k -1 warns once, by name" \
     "$(printf '%s\n' "$out" | grep -c "^⚠.*review-round config not an integer >= 0: $k" | tr -d ' ')" 1
done
printf '{"org": "x", "qaRounds": 2}\n' > "$W/instance.config.json"
out="$(bash "$WELCOME" check --instance "$W" 2>&1)"
ok "a good value: no warning, a healthy line" \
   "$(printf '%s\n' "$out" | grep -c 'review rounds: coderabbitRounds, qaRounds and reviewFixMaxLines resolve' | tr -d ' ')" 1
ok "welcome lists the row as ambiguous (fix never touches config)" \
   "$(bash "$WELCOME" check --list | awk -F'\t' '$1=="review-config"{print $2}')" ambiguous

echo "== seeded, documented, and not overridable per machine =="
SEED="$REPO/plugin/seed/instance.config.json"; SCHEMA="$REPO/plugin/seed/SCHEMA.md"
ok "the seed carries 1 / 1 / 300" \
   "$(jq -c '[.coderabbitRounds, .qaRounds, .reviewFixMaxLines]' "$SEED")" "[1,1,300]"
for k in coderabbitRounds qaRounds reviewFixMaxLines; do
  ok "\$$k note present" "$(jq -r --arg k "\$$k" '.[$k] | type' "$SEED")" string
  ok "SCHEMA row marks $k not overridable" \
     "$(grep -c "^| \`$k\` | \*\*no\*\* — a merge policy both clones must agree on" "$SCHEMA" | tr -d ' ')" 1
  N="$TMP/n-$k"; mkdir -p "$N"; printf '{"org": "x"}\n' > "$N/instance.config.json"
  printf '{"%s": 2}\n' "$k" > "$N/instance.config.local.json"
  ok "…and a local $k is MISPLACED" \
     "$(bash "$REPO/plugin/scripts/normalise-config.sh" "$N" 2>&1 | grep -c "MISPLACED.*$k" | tr -d ' ')" 1
done

printf '\npass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
