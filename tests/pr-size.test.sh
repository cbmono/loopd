#!/usr/bin/env bash
#
# pr-size.test.sh — plugin/scripts/pr-size.sh reports a diff past maxPrLoc, maxPrFiles or
# ~150 harness lines whose body has no `⚠️` line naming the figure, is silent when it has
# one, reads thresholds from --instance or the repo's .git/loopd-bundle marker (500/100
# when absent), and exits 0 or 2, never anything else. Fixture: a bare origin whose
# default branch is `trunk`, so nothing passes by assuming `main`.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PS="$REPO/plugin/scripts/pr-size.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/prsize.XXXXXX")" || { echo "pr-size.test: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
run() { OUT="$(bash "$PS" "$@" 2>&1)"; RC=$?; }
has() { grep -qF -- "$1" <<<"$OUT" && echo yes || echo no; }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
g() { git -C "$W" -c user.name=t -c user.email=t@example.com "$@" >/dev/null 2>&1; }
git init -q --bare -b trunk "$TMP/origin.git"
W="$TMP/w"; git clone -q "$TMP/origin.git" "$W" 2>/dev/null
echo base > "$W/README"; g checkout -q -b trunk; g add -A; g commit -q -m base; g push -q origin trunk
git -C "$W" remote set-head origin trunk >/dev/null 2>&1
g checkout -q -b feat
seq 1 60 > "$W/big.txt"; g add -A; g commit -q -m big

I="$TMP/inst"; mkdir -p "$I"; echo '{"maxPrLoc": 50, "maxPrFiles": 2}' > "$I/instance.config.json"
NO="$TMP/no.md"; printf '## Description\nA change.\n' > "$NO"
YES="$TMP/yes.md"; printf '## Description\nA change.\n⚠️ 60 lines past maxPrLoc; split: none.\n' > "$YES"
OTHER="$TMP/other.md"; printf '## Description\n⚠️ 61 lines, split by layer.\n' > "$OTHER"

echo "== maxPrLoc =="
run --body-file "$NO" -C "$W" --instance "$I"
ok "past maxPrLoc, no ⚠️ line: reported" "$(has 'lines changed 60 is past maxPrLoc 50')" yes
ok "  exits 0" "$RC" 0
run --body-file "$YES" -C "$W" --instance "$I"
ok "past maxPrLoc, ⚠️ line names 60: silent" "$OUT" ""
ok "  exits 0" "$RC" 0
run --body-file "$OTHER" -C "$W" --instance "$I"
ok "⚠️ line naming another figure (61) does not count" "$(has 'lines changed 60')" yes
run --body-file "$NO" -C "$W"
ok "no instance, no marker: 500 applies, 60 lines silent" "$OUT" ""
printf '%s\n' "$I" > "$W/.git/loopd-bundle"
run --body-file "$NO" -C "$W"
ok "the repo's loopd-bundle marker supplies maxPrLoc" "$(has 'past maxPrLoc 50')" yes
rm -f "$W/.git/loopd-bundle"

echo "== maxPrFiles =="
touch "$W/a" "$W/b"; g add -A; g commit -q -m files
run --body-file "$YES" -C "$W" --instance "$I"
ok "3 files past maxPrFiles 2: reported" "$(has 'files changed 3 is past maxPrFiles 2')" yes
ok "  the ⚠️'d loc figure stays silent" "$(has 'lines changed')" no

echo "== harness growth =="
mkdir -p "$W/plugin/scripts"; seq 1 1200 | sed 's/^/echo /' > "$W/plugin/scripts/x.sh"; g add -A; g commit -q -m harness
run --body-file "$NO" -C "$W"
ok "1200 added plugin/**/*.sh lines, no ⚠️ line: reported" "$(has 'harness lines added 1200 is past ~150')" yes
ok "  exits 0" "$RC" 0
printf '⚠️ Needs your call: harness growth 1,200 lines; lines changed 1,260.\n' > "$TMP/h.md"
run --body-file "$TMP/h.md" -C "$W"
ok "⚠️ line naming 1,200 (with a comma) and 1,260: silent" "$OUT" ""

echo "== unknown is exit 2, never a refusal =="
run -C "$W"
ok "no --body-file: exit 2" "$RC" 2
run --body-file "$TMP/missing.md" -C "$W"
ok "unreadable body: exit 2" "$RC" 2
run --body-file "$NO" -C "$W" --bogus x
ok "unknown flag: exit 2" "$RC" 2
git -C "$W" remote set-head origin -d >/dev/null 2>&1
run --body-file "$NO" -C "$W"
ok "origin/HEAD unset: exit 2 UNKNOWN" "$RC:$(has UNKNOWN)" "2:yes"
run --body-file "$NO" -C "$W" --base nosuchref
ok "unresolvable --base: exit 2" "$RC" 2
run --body-file "$NO" -C "$W" --base origin/trunk --instance "$I"
ok "--base names the default explicitly" "$(has 'lines changed')" yes

echo; echo "pr-size.test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
