#!/usr/bin/env bash
#
# reserved-scan.test.sh — plugin/scripts/reserved-scan.sh reports a reserved decision 1–3 token
# on a line a branch adds or removes in code or CI config, with file and line, and passes a
# branch that only names a token in prose. Exit 0 none · 1 hits · 2 unknown. Fixture: a bare
# origin whose default branch is `trunk`, so nothing passes by assuming `main`.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
RS="$REPO/plugin/scripts/reserved-scan.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/reservedscan.XXXXXX")" || {
  echo "reserved-scan.test: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
has() { grep -qF -- "$1" <<<"$OUT" && echo yes || echo no; }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
g() { git -C "$W" -c user.name=t -c user.email=t@example.com "$@" >/dev/null 2>&1; }
git init -q --bare -b trunk "$TMP/origin.git"
W="$TMP/w"; git clone -q "$TMP/origin.git" "$W" 2>/dev/null
mkdir -p "$W/.github/workflows" "$W/src"
cat > "$W/old.ts" <<'TS'
// @ts-ignore
const kept = 1;
// eslint-disable-next-line no-console
console.log(kept);
TS
g checkout -q -b trunk; g add -A; g commit -q -m base; g push -q origin trunk
git -C "$W" remote set-head origin trunk >/dev/null 2>&1

g checkout -q -b ci trunk
cat > "$W/.github/workflows/ci.yml" <<'YML'
jobs:
  test:
    runs-on: ubuntu-latest
    continue-on-error: true
YML
g add -A; g commit -q -m ci
OUT="$(bash "$RS" -C "$W")"; rc=$?
echo "== a branch adding continue-on-error to CI config =="
ok "exit 1 on a hit"                                    "$rc" 1
ok "default range is origin/<default>, not main"        "$(has 'in origin/trunk...HEAD')" yes
ok "hit reported with file and line"                    "$(has '.github/workflows/ci.yml:4: +continue-on-error: true')" yes

g checkout -q -b prose trunk
cat > "$W/notes.md" <<'MD'
Never add `continue-on-error: true`, `eslint-disable`, `@ts-ignore` or `it.skip(` to pass CI.
MD
g add -A; g commit -q -m prose
OUT="$(bash "$RS" -C "$W")"; rc=$?
echo "== a branch naming the tokens only in prose =="
ok "exit 0, nothing reported"                           "$rc:$(has 'reserved-scan: 0 ')" 0:yes

g checkout -q -b code trunk
sed -i.bak '3d' "$W/old.ts" && rm "$W/old.ts.bak"
cat > "$W/src/a.test.ts" <<'TS'
// eslint-disable-next-line no-console
// @ts-expect-error
it.skip("flaky", () => {});
xit("later", () => {});
const firstRest = rows.iter().skip(1);
TS
cat > "$W/src/b.sh" <<'SH'
# shellcheck disable=SC2086
echo $x
SH
cat > "$W/src/c.py" <<'PY'
@pytest.mark.skip(reason="flaky")
def test_a(): pass
PY
cat > "$W/src/d.bats" <<'BATS'
@test "a" {
  skip "flaky"
}
BATS
g add -A; g commit -q -m code
OUT="$(bash "$RS" -C "$W" trunk...code)"; rc=$?
echo "== a branch adding and removing tokens in code =="
ok "exit 1"                                             "$rc" 1
ok "count of reported lines"                            "$(awk 'NR == 1 { print $2 }' <<<"$OUT")" 8
ok "eslint-disable"                                     "$(has 'src/a.test.ts:1: +// eslint-disable-next-line')" yes
ok "@ts-expect-error"                                   "$(has 'src/a.test.ts:2: +// @ts-expect-error')" yes
ok ".skip"                                              "$(has 'src/a.test.ts:3: +it.skip(')" yes
ok "xit"                                                "$(has 'src/a.test.ts:4: +xit(')" yes
ok "a non-test .skip is not reported"                   "$(has 'iter()')" no
ok "shellcheck disable"                                 "$(has 'src/b.sh:1: +# shellcheck disable=SC2086')" yes
ok "a skip marker"                                      "$(has 'src/c.py:1: +@pytest.mark.skip(')" yes
ok "a bats skip"                                        "$(has 'src/d.bats:2: +skip "flaky"')" yes
ok "a removed token, old-side line"                     "$(has 'old.ts:3: -// eslint-disable-next-line')" yes
ok "a token on an unchanged base line is not reported"  "$(has '@ts-ignore')" no

echo "== unknown is exit 2 =="
OUT="$(bash "$RS" -C "$W" trunk...trunk)"; rc=$?
ok "an empty range reports 0, exit 0"                   "$rc:$(has 'reserved-scan: 0 ')" 0:yes
OUT="$(bash "$RS" --bogus)"; rc=$?
ok "a bad argument"                                     "$rc:$(has 'UNKNOWN')" 2:yes
OUT="$(bash "$RS" -C "$TMP/nowhere" a...b)"; rc=$?
ok "an unreadable diff"                                 "$rc:$(has 'UNKNOWN')" 2:yes
git -C "$W" remote set-head origin -d >/dev/null 2>&1
OUT="$(bash "$RS" -C "$W")"; rc=$?
ok "no origin/HEAD and no range"                        "$rc:$(has 'UNKNOWN')" 2:yes

echo
echo "reserved-scan: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
