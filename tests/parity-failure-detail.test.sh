#!/usr/bin/env bash
#
# parity-failure-detail.test.sh — worktree-suite-parity.test.sh must NAME the inner
# assertion that failed, not just the harness that carried it.
#
# On 2026-09-15 two branches drew `FAIL board-renderers.test.sh … reports fail=0` 25
# minutes apart and nobody could say which of that harness's own assertions broke: the
# captured output was emitted only when no pass=/fail= summary was found. This drives the
# real parity harness over three fixture harnesses — one red, one green, one printing no
# summary — so the reporting is proven by a run rather than by reading it.
#
# ok() compares actual to expected, per this directory's convention.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
PARITY="$REPO/tests/worktree-suite-parity.test.sh"
[ -f "$PARITY" ] || { echo "parity-failure-detail.test: $PARITY is gone" >&2; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/parity-failure-detail.XXXXXX")" || {
  echo "parity-failure-detail.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

FIX="$TMP/repo"
mkdir -p "$FIX/tests" "$FIX/plugin/scripts"

# Half 1 of the parity harness stamps a bundle and re-checks the --config guard; this
# stands in for both so the only stderr the run produces comes from half 2.
cat >"$FIX/plugin/scripts/init-bundle.sh" <<'EOS'
#!/usr/bin/env bash
[ "${1:-}" = "--config" ] && { echo "refusing to link the config layer from a git worktree" >&2; exit 2; }
mkdir -p "$1" && printf '{}\n' >"$1/instance.config.json"
EOS

cat >"$FIX/tests/redfix.test.sh" <<'EOS'
#!/usr/bin/env bash
printf '  PASS  redfix quiet passing assertion\n'
printf '  FAIL  redfix names the broken assertion                 got 1, want 0\n'
printf 'pass=1 fail=1\n'
exit 1
EOS

cat >"$FIX/tests/greenfix.test.sh" <<'EOS'
#!/usr/bin/env bash
printf '  PASS  greenfix quiet passing assertion\n'
printf 'pass=2 fail=0\n'
EOS

cat >"$FIX/tests/mutefix.test.sh" <<'EOS'
#!/usr/bin/env bash
printf 'mutefix deliberate no-summary diagnostic\n'
exit 2
EOS

# The parity harness under test, its end-to-end loop aimed at the fixtures instead of the
# real harness it runs. The substitution is asserted below: a reworded loop must not
# leave this driving nothing. Since 2026-10-05 that loop is one harness, not seven, and
# the parity file's static and mutant sections read real harnesses this fixture repo
# does not carry — they go red on stdout here, which no assertion below reads: every
# one of them is about what the end-to-end loop writes to stderr.
sed -E 's/^for h in .*; do$/for h in redfix greenfix mutefix; do/' \
  "$PARITY" >"$FIX/tests/worktree-suite-parity.test.sh"
ok "the fixture list replaced the real one" \
   "$(grep -c '^for h in redfix greenfix mutefix; do$' "$FIX/tests/worktree-suite-parity.test.sh")" 1

git -C "$FIX" init -q >/dev/null 2>&1
git -C "$FIX" add -A >/dev/null 2>&1
git -C "$FIX" -c user.email=t@example.com -c user.name=t commit -qm fixture >/dev/null 2>&1
ok "the fixture repo has a commit to check out" \
   "$(git -C "$FIX" rev-parse --verify -q HEAD >/dev/null 2>&1 && echo yes || echo no)" yes

bash "$FIX/tests/worktree-suite-parity.test.sh" >"$TMP/out" 2>"$TMP/err"
ok "the harness ran the fixtures" \
   "$(grep -c 'redfix.test.sh exits 0 from a linked worktree' "$TMP/out")" 1

ok "a red harness's own FAIL line reaches stderr" \
   "$(grep -c 'redfix names the broken assertion' "$TMP/err")" 1
ok "…under a header naming the harness"          \
   "$(grep -c 'redfix.test.sh rc=1 pass=1 fail=1' "$TMP/err")" 1
ok "…and its passing lines do not"               \
   "$(grep -c 'redfix quiet passing assertion' "$TMP/err")" 0
ok "a green harness adds nothing to stderr"      \
   "$(grep -c greenfix "$TMP/err")" 0
ok "a harness with no summary still dumps everything" \
   "$(grep -c 'mutefix deliberate no-summary diagnostic' "$TMP/err")" 1

printf '\npass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
