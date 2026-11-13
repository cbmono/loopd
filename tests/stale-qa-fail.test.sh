#!/usr/bin/env bash
#
# stale-qa-fail.test.sh — a checker FAIL from an earlier head keeps its comment's createdAt in
# the clearance receipt, so a later last-round line waives it on EVERY run of
# pr-verdict-clearance.sh; a FAIL at the head, an edited comment, a table with no head_sha and
# an unproven same-login FAIL are stamped now and still refuse. `gh` is stubbed; the
# last-round line is pinned at a fixed stamp so no case depends on the wall clock.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO/plugin/scripts"
PVC="$S/pr-verdict-clearance.sh"; RCPT="$S/clearance-receipt.sh"
command -v jq >/dev/null 2>&1 || { echo "stale-qa-fail.test: jq is required" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/stale-qa-fail.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <label> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL  %s (got %s, want %s)\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
rc_of() { "$@" >/dev/null 2>&1; printf '%s' "$?"; }

mkdir -p "$TMP/bin" "$TMP/fix" "$TMP/s"
export FIX="$TMP/fix"
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = pr ] && [ "${2:-}" = view ] && [ -f "$FIX/pr_json" ] && { cat "$FIX/pr_json"; exit 0; }
echo "stub: unhandled gh $*" >&2; exit 99
STUB
chmod +x "$TMP/bin/gh"
PATH="$TMP/bin:$PATH"; export PATH

H="8f40f2ed565a31e141f5ae54a6935ad0810314c4"   # head B
A="0123456789abcdef0123456789abcdef01234567"   # the round-1 head
CREATED="2020-01-01T00:30:00Z"; LAST="2020-01-01T01:00:00Z"

cat > "$TMP/worker" <<'MD'
## Description

One sentence.

| Criterion | ✓ | Verified by |
|---|---|---|
| the retry backs off on 429 | ✓ | `foo.test.sh` 40/0 |
MD
cat > "$TMP/fail-table" <<'MD'
| Criterion | Verdict | Evidence |
|---|---|---|
| the retry backs off on 429 | FAIL | `foo.test.sh` 39/1 |
MD

fresh_bundle() {
  export CLAUDE_PROJECT_DIR="$TMP/b$1"; mkdir -p "$CLAUDE_PROJECT_DIR"
  printf '{}\n' > "$CLAUDE_PROJECT_DIR/instance.config.json"
  for s in required-checks.sh pr-body-clearance.sh; do
    "$RCPT" record "$s" --repo acme/widgets --pr 42 --head "$H"
  done
  "$RCPT" record review-next.sh --unreviewed last-round --repo acme/widgets --pr 42 --head "$H"
  f="$("$RCPT" path --repo acme/widgets --pr 42 --head "$H")"
  awk -v t="$LAST" '$1 == "last-round" { $3 = t } { print }' "$f" > "$f.t" && mv "$f.t" "$f"
}
tick() { "$RCPT" record review-next.sh --unreviewed last-round --repo acme/widgets --pr 42 --head "$H"; }
last_at() { awk '$1 == "last-round" { print $3 }' "$("$RCPT" path --repo acme/widgets --pr 42 --head "$H")"; }
serve() { # <author> <checker> <trailer head_sha or -> [nonce] [edited]
  { cat "$TMP/fail-table"
    [ "$3" = - ] || printf '\n<!-- okf-verdict v1\nverdict: changes-requested\nhead_sha: %s\nreviewer: qa-reviewer\ndispatch: %s\n-->\n' "$3" "${4:-none}"
  } > "$TMP/qa"
  jq -n --rawfile body "$TMP/worker" --rawfile c "$TMP/qa" --arg a "$1" --arg q "$2" --arg h "$H" \
        --arg t "${AT_OVERRIDE:-$CREATED}" --argjson e "${5:-false}" \
    '{body:$body, author:{login:$a}, url:"https://github.com/acme/widgets/pull/42", headRefOid:$h,
      comments:[{author:{login:$q}, body:$c, createdAt:$t, includesCreatedEdit:$e}]}' > "$FIX/pr_json"
}
verify() { rc_of "$RCPT" verify --unreviewed --repo acme/widgets --pr 42 --head "$H"; }
fail_at() { awk '$1 == "fail" && $2 == "pr-verdict-clearance.sh" { print $3 }' \
  "$("$RCPT" path --repo acme/widgets --pr 42 --head "$H")"; }

echo "== clearance-receipt.sh record --at =="
fresh_bundle at
"$RCPT" record x.sh --fail --at "$CREATED" --repo acme/widgets --pr 42 --head "$H"
ok "a well-formed --at is the stamp" "$(awk '$2 == "x.sh" { print $3 }' "$("$RCPT" path --repo acme/widgets --pr 42 --head "$H")")" "$CREATED"
"$RCPT" record x.sh --fail --at "2020-01-01 00:30" --repo acme/widgets --pr 42 --head "$H"
ok "a malformed --at is ignored for now" \
   "$(awk '$2 == "x.sh" { print ($3 > "2020-12-31T00:00:00Z") }' "$("$RCPT" path --repo acme/widgets --pr 42 --head "$H")")" 1

echo
echo "== a stale FAIL under another login is waived on every run =="
fresh_bundle stale; serve worker-bot qa-bot "$A"
ok "the disagreement is still exit 1 (clause 7)" "$(rc_of "$PVC" 42 --repo acme/widgets)" 1
ok "…the fail line keeps the comment's createdAt" "$(fail_at)" "$CREATED"
ok "…and verify --unreviewed clears after run 1" "$(verify)" 0
for n in 2 3 4; do
  "$PVC" 42 --repo acme/widgets >/dev/null 2>&1
  ok "…and after run $n" "$(verify)" 0
done

echo
echo "== the assertion is not vacuous =="
cp "$S"/*.sh "$TMP/s/"
sed 's/^  AT=(--at "\$CREATED")$/  AT=()/' "$PVC" > "$TMP/s/mutant.sh"; chmod +x "$TMP/s/mutant.sh"
ok "the mutant differs from the script" "$(cmp -s "$PVC" "$TMP/s/mutant.sh" && echo same || echo differs)" differs
fresh_bundle mut; serve worker-bot qa-bot "$A"
"$TMP/s/mutant.sh" 42 --repo acme/widgets >/dev/null 2>&1
ok "MUTANT: stamping the stale FAIL now refuses" "$(verify)" 1

echo
echo "== what is not provably stale is stamped now, and refuses =="
for c in "current:$H" "prefix:${H:0:7}" "upper:$(printf '%s' "$H" | tr '[:lower:]' '[:upper:]')" "none:-"; do
  fresh_bundle "${c%%:*}"; serve worker-bot qa-bot "${c#*:}"
  ok "${c%%:*} head_sha: exit 1" "$(rc_of "$PVC" 42 --repo acme/widgets)" 1
  ok "…stamped now"              "$([ "$(fail_at)" \> "$LAST" ] && echo now || fail_at)" now
  ok "…verify refuses"           "$(verify)" 1
done
fresh_bundle edited; serve worker-bot qa-bot "$A" "" true
"$PVC" 42 --repo acme/widgets >/dev/null 2>&1
ok "an edited checker comment: stamped now" "$([ "$(fail_at)" \> "$LAST" ] && echo now || fail_at)" now
ok "…verify refuses"                        "$(verify)" 1

echo
echo "== --at is a fail line's only, and a waiver line keeps its first stamp =="
fresh_bundle flags
ok "--at on an --unreviewed line is usage, exit 2" \
   "$(rc_of "$RCPT" record review-next.sh --unreviewed last-round --at 2099-01-01T00:00:00Z --repo acme/widgets --pr 42 --head "$H")" 2
ok "…and the pinned last-round stamp is untouched" "$(last_at)" "$LAST"
ok "--at on a pass line is usage, exit 2" \
   "$(rc_of "$RCPT" record y.sh --at "$CREATED" --repo acme/widgets --pr 42 --head "$H")" 2
ok "--at swallowing --fail is usage, not a pass" \
   "$(rc_of "$RCPT" record y.sh --at --fail --repo acme/widgets --pr 42 --head "$H")" 2
ok "…and no y.sh line was written" "$(grep -c ' y.sh ' "$("$RCPT" path --repo acme/widgets --pr 42 --head "$H")")" 0
tick; tick
ok "two later ticks keep the last-round stamp" "$(last_at)" "$LAST"

echo
echo "== a stale FAIL posted AFTER the last-round line refuses on every tick =="
fresh_bundle late; AT_OVERRIDE="2020-01-01T02:00:00Z" serve worker-bot qa-bot "$A"
for n in 1 2 3; do
  "$PVC" 42 --repo acme/widgets >/dev/null 2>&1; tick
  ok "tick $n: verify refuses" "$(verify)" 1
done
ok "…the fail line keeps its createdAt" "$(fail_at)" "2020-01-01T02:00:00Z"
sed 's/^      \[ -f "\$file" \] && awk -v r=/      false \&\& awk -v r=/' "$RCPT" > "$TMP/s/clearance-receipt.sh"
ok "the re-stamping mutant differs" "$(cmp -s "$RCPT" "$TMP/s/clearance-receipt.sh" && echo same || echo differs)" differs
fresh_bundle late-mut; AT_OVERRIDE="2020-01-01T02:00:00Z" serve worker-bot qa-bot "$A"
"$TMP/s/pr-verdict-clearance.sh" 42 --repo acme/widgets >/dev/null 2>&1
"$TMP/s/clearance-receipt.sh" record review-next.sh --unreviewed last-round --repo acme/widgets --pr 42 --head "$H"
ok "MUTANT: re-stamping last-round waives it" "$(verify)" 0
cp "$RCPT" "$TMP/s/clearance-receipt.sh"

echo
echo "== an odd createdAt is stamped now =="
fresh_bundle odd; AT_OVERRIDE="2020-01-01T00:30:00.000Z" serve worker-bot qa-bot "$A"
"$PVC" 42 --repo acme/widgets >/dev/null 2>&1
ok "fractional seconds: stamped now" "$([ "$(fail_at)" \> "$LAST" ] && echo now || fail_at)" now
ok "…verify refuses"                 "$(verify)" 1

echo
echo "== the PR author's own login: only a dispatch at the trailer head proves it (clause 8) =="
fresh_bundle solo-forged; serve solo solo "$A" 0123456789abcdef0123456789abcdef
"$PVC" 42 --repo acme/widgets >/dev/null 2>&1
ok "no dispatch record: stamped now"  "$([ "$(fail_at)" \> "$LAST" ] && echo now || fail_at)" now
ok "…verify refuses"                  "$(verify)" 1
mint_old() { # <head> — a dispatch record dated before the comment
  "$S/qa-dispatch.sh" mint --repo acme/widgets --pr 42 --head "$1"
  R="$CLAUDE_PROJECT_DIR/.loopd/.qa-dispatch/records"
  awk -F'\t' -v OFS='\t' '{ $1 = "2020-01-01T00:00:00Z"; print }' "$R" > "$R.t" && mv "$R.t" "$R"
}
fresh_bundle solo-at-head; serve solo solo "$A" "$(mint_old "$H")"
"$PVC" 42 --repo acme/widgets >/dev/null 2>&1
ok "a dispatch at the head, not the trailer's: stamped now" "$([ "$(fail_at)" \> "$LAST" ] && echo now || fail_at)" now
fresh_bundle solo-late; serve solo solo "$A" "$("$S/qa-dispatch.sh" mint --repo acme/widgets --pr 42 --head "$A")"
"$PVC" 42 --repo acme/widgets >/dev/null 2>&1
ok "a dispatch at the trailer head recorded after createdAt: stamped now" "$([ "$(fail_at)" \> "$LAST" ] && echo now || fail_at)" now
fresh_bundle solo-proved; serve solo solo "$A" "$(mint_old "$A")"
ok "a dispatch at the trailer head: exit 1" "$(rc_of "$PVC" 42 --repo acme/widgets)" 1
ok "…the fail line keeps createdAt"        "$(fail_at)" "$CREATED"
ok "…verify clears"                        "$(verify)" 0

echo
echo "== a pass line on line 1 of a long receipt is found (no SIGPIPE under pipefail) =="
fresh_bundle long
f="$("$RCPT" path --repo acme/widgets --pr 42 --head "$H")"
awk 'BEGIN { for (i = 0; i < 20000; i++) printf "pass filler-%d.sh 2020-01-01T00:00:00Z\n", i }' >> "$f"
for n in 1 2 3 4 5; do ok "run $n: verify clears" "$(verify)" 0; done
sed 's/^      grep -qxF -- "\$r" <<<"\$got" |/      printf "%s\\n" "$got" | grep -qx "$r" |/' "$RCPT" > "$TMP/s/clearance-receipt.sh"
ok "the piped mutant differs" "$(cmp -s "$RCPT" "$TMP/s/clearance-receipt.sh" && echo same || echo differs)" differs
m=0; for n in 1 2 3 4 5; do
  [ "$(rc_of "$TMP/s/clearance-receipt.sh" verify --unreviewed --repo acme/widgets --pr 42 --head "$H")" = 0 ] || m=$((m+1))
done
ok "MUTANT: the piped form refuses at least once in 5" "$([ "$m" -gt 0 ] && echo refused || echo cleared)" refused
cp "$RCPT" "$TMP/s/clearance-receipt.sh"
unset CLAUDE_PROJECT_DIR

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
