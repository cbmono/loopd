#!/usr/bin/env bash
#
# pr-verdict-clearance.test.sh — the checker re-derives the criteria table, and the
# comparison of the two tables is what routes.
#
# WHAT IS PINNED. The three cases ai-bridge-next/task-013 names — identical tables pass,
# one disagreement routes and quotes BOTH rows, a checker row with no command is refused
# — plus the identity rule and the two ways the tables cannot be aligned at all.
#
# NON-VACUOUS BY CONSTRUCTION. Every refusal case is run against a fixture that differs
# from a clearing one in ONE cell, and the clearing fixture is asserted in the same block,
# so a script that stopped reading the checker's column would flip a verdict rather than
# print a different shape. Two mutants drive the two assertions a wrong answer would hide:
# one that ignores the checker's FAIL, one that skips the evidence check.
#
# THE HOST IS STUBBED. `gh` answers from $FIX so the PR-mode read is exercised without a
# network, and the stub records what it was asked for.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO/plugin/scripts/pr-verdict-clearance.sh"
[ -x "$SCRIPT" ] || { echo "pr-verdict-clearance.test: $SCRIPT is not executable" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/pr-verdict-clearance.XXXXXX")" || {
  echo "pr-verdict-clearance.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
# The mutants run from $TMP, and the script sources its sibling resolver
# (ai-bridge-v3/task-031) — without it they exit 2 before reaching their subject.
cp "$(dirname "$SCRIPT")/bundle-paths.sh" "$TMP/bundle-paths.sh"

pass=0; fail=0
ok() { # <label> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL  %s (got %s, want %s)\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
rc_of() { "$@" >/dev/null 2>&1; printf '%s' "$?"; }

# --- fixtures -----------------------------------------------------------------
mk() { local f; f="$(mktemp "$TMP/tbl.XXXXXX")"; printf '%s\n' "$@" > "$f"; printf '%s' "$f"; }

WORKER="$(mk \
  '## Description' '' 'One sentence.' '' \
  'Verified: `foo.test.sh` 40/0 on [run 12](https://example.invalid/12).' '' \
  '### Criteria (2 ✓ / 0 ✗)' '' \
  '| Criterion | ✓ | Verified by |' \
  '|---|---|---|' \
  '| the retry backs off on 429 | ✓ | `foo.test.sh` 40/0 |' \
  '| the token is never logged | ✓ | `grep -r TOKEN src/` clean |')"

AGREE="$(mk \
  '| Criterion | Verdict | Evidence |' \
  '|---|---|---|' \
  '| the retry backs off on 429 | PASS | `foo.test.sh` 40/0 |' \
  '| the token is never logged | PASS | `grep -r TOKEN src/` clean |')"

DISAGREE="$(mk \
  '| Criterion | Verdict | Evidence |' \
  '|---|---|---|' \
  '| the retry backs off on 429 | PASS | `foo.test.sh` 40/0 |' \
  '| the token is never logged | FAIL | `grep -rn TOKEN src/` hits log.ts:31 |')"

NO_COMMAND="$(mk \
  '| Criterion | Verdict | Evidence |' \
  '|---|---|---|' \
  '| the retry backs off on 429 | PASS | `foo.test.sh` 40/0 |' \
  '| the token is never logged | PASS | verified, works as expected |')"

PARTIAL="$(mk \
  '| Criterion | Verdict | Evidence |' \
  '|---|---|---|' \
  '| the retry backs off on 429 | PASS | `foo.test.sh` 40/0 |' \
  '| the token is never logged | PARTIAL | `grep -r TOKEN src/` mostly clean |')"

NO_EVIDENCE_COL="$(mk \
  '| Criterion | Verdict |' \
  '|---|---|' \
  '| the retry backs off on 429 | PASS |' \
  '| the token is never logged | PASS |')"

SHORT="$(mk \
  '| Criterion | Verdict | Evidence |' \
  '|---|---|---|' \
  '| the retry backs off on 429 | PASS | `foo.test.sh` 40/0 |')"

QUOTED="$(mk 'The checker should post a table like this:' '' '```md' \
  '| Criterion | Verdict | Evidence |' \
  '|---|---|---|' \
  '| the retry backs off on 429 | PASS | `foo.test.sh` 40/0 |' \
  '```' '' 'It has not posted one yet.')"

run() { "$SCRIPT" --body-file "$WORKER" --checker-file "$1" "${@:2}"; }

echo "== the script runs, and says so =="
ok "--self-test clears"                    "$(rc_of "$SCRIPT" --self-test)" 0
ok "…and prints its sentinel"              \
   "$("$SCRIPT" --self-test 2>/dev/null | grep -c 'self-test ok')" 1
ok "no arguments is usage, exit 2"         "$(rc_of "$SCRIPT")" 2

echo
echo "== identical tables agree =="
ok "two ✓ against two PASS clears"          "$(rc_of run "$AGREE")" 0
ok "…and says how many it compared"        \
   "$(run "$AGREE" 2>/dev/null | grep -c 'clear: 2 criteria')" 1
ok "…and says the identity rule was not applied" \
   "$(run "$AGREE" 2>&1 | grep -c 'checker != author')" 1

echo
echo "== one disagreement routes, quoting BOTH rows =="
ok "worker ✓ against checker FAIL is exit 1" "$(rc_of run "$DISAGREE")" 1
DOUT="$(run "$DISAGREE" 2>&1)"
ok "…it names the criterion by index"       "$(printf '%s' "$DOUT" | grep -c 'criterion 2')" 1
ok "…quotes the worker's row"               "$(printf '%s' "$DOUT" | grep -c '^  worker : ')" 1
ok "…quotes the checker's row"              "$(printf '%s' "$DOUT" | grep -c '^  checker: ')" 1
ok "…and the quoted rows differ"            \
   "$([ "$(printf '%s' "$DOUT" | grep '^  worker : ')" \
     = "$(printf '%s' "$DOUT" | grep '^  checker: ' | sed 's/checker:/worker :/')" ] \
     && echo same || echo differ)" differ
ok "…and it says the call is the human's"   "$(printf '%s' "$DOUT" | grep -c "human's")" 1

echo
echo "== a checker row with no command is refused =="
ok "prose in the evidence cell is exit 3"   "$(rc_of run "$NO_COMMAND")" 3
NOUT="$(run "$NO_COMMAND" 2>&1)"
ok "…it names the row"                      "$(printf '%s' "$NOUT" | grep -c 'checker row 2')" 1
ok "…and says missing evidence is FAIL"     "$(printf '%s' "$NOUT" | grep -c 'is FAIL')" 1
ok "a table with no evidence COLUMN is exit 3" "$(rc_of run "$NO_EVIDENCE_COL")" 3
ok "…for BOTH of its rows"                  \
   "$(run "$NO_EVIDENCE_COL" 2>&1 | grep -c 'LAST cell')" 2

echo
echo "== no partial credit =="
ok "PARTIAL is not a verdict — exit 3"      "$(rc_of run "$PARTIAL")" 3
ok "…and the refusal says so"               \
   "$(run "$PARTIAL" 2>&1 | grep -c 'no partial')" 1

echo
echo "== what cannot be compared is UNKNOWN, never clearance =="
ok "fewer checker rows than criteria is exit 2" "$(rc_of run "$SHORT")" 2
ok "…naming both counts"                    "$(run "$SHORT" 2>&1 | grep -c "has 2 row(s) and the checker's has 1")" 1
ok "a table only QUOTED in a fence is exit 2"   "$(rc_of run "$QUOTED")" 2
ok "a body with no criteria table is exit 2"    \
   "$(rc_of "$SCRIPT" --body-file "$QUOTED" --checker-file "$AGREE")" 2

echo
echo "== the checker is not the author (SCHEMA.md clause 8) =="
ok "distinct logins clear"                  \
   "$(rc_of run "$AGREE" --checker-login qa-bot --author-login worker-bot)" 0
ok "one login for both is exit 4"           \
   "$(rc_of run "$AGREE" --checker-login solo --author-login solo)" 4
IOUT="$(run "$AGREE" --checker-login Solo --author-login "solo[bot]" 2>&1)"
ok "…case and the [bot] suffix do not evade it" \
   "$(rc_of run "$AGREE" --checker-login Solo --author-login "solo[bot]")" 4
ok "…and the solo-bundle limit is stated, not implied" \
   "$(printf '%s' "$IOUT" | grep -c 'KNOWN LIMIT')" 1
ok "…identity is decided AFTER the disagreement" \
   "$(rc_of run "$DISAGREE" --checker-login solo --author-login solo)" 1

echo
echo "== PR mode reads the LATEST checker comment from the host =="
mkdir -p "$TMP/bin" "$TMP/fix"
export FIX="$TMP/fix"
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "view" ]; then
  printf '%s\n' "$*" >> "$FIX/calls"
  [ -f "$FIX/pr_json" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
  cat "$FIX/pr_json"; exit 0
fi
echo "stub: unhandled gh $*" >&2; exit 99
STUB
chmod +x "$TMP/bin/gh"
PATH="$TMP/bin:$PATH"; export PATH

if command -v jq >/dev/null 2>&1; then
  serve() { # <author-login> <checker-login> <checker-table-file> [<older-table-file>]
    jq -n --rawfile body "$WORKER" --rawfile new "$3" \
          --rawfile old "${4:-$AGREE}" --arg a "$1" --arg c "$2" \
      '{body:$body, author:{login:$a},
        comments:[{author:{login:$c},body:$old},{author:{login:$c},body:$new}]}' \
      > "$FIX/pr_json"
  }
  serve worker-bot qa-bot "$AGREE"
  ok "an agreeing verdict comment clears"      "$(rc_of "$SCRIPT" 42 --repo acme/widgets)" 0
  ok "…and it asked the host for the PR"       "$(grep -c 'pr view 42' "$FIX/calls")" 1
  serve worker-bot qa-bot "$DISAGREE"
  ok "the LATEST comment decides, not the first" "$(rc_of "$SCRIPT" 42 --repo acme/widgets)" 1
  serve solo solo "$AGREE"
  ok "one login for both is exit 4 here too"   "$(rc_of "$SCRIPT" 42 --repo acme/widgets)" 4

  # The same login, with the checker comment carrying the okf-verdict trailer of a
  # qa-reviewer dispatch the project-manager recorded (qa-dispatch.sh, SCHEMA.md clause 8).
  H="8f40f2ed565a31e141f5ae54a6935ad0810314c4"
  export CLAUDE_PROJECT_DIR="$TMP/bundle"; mkdir -p "$CLAUDE_PROJECT_DIR"
  printf '{}\n' > "$CLAUDE_PROJECT_DIR/instance.config.json"
  serve_qa() { # <nonce> <created_at> [head_sha in the trailer]
    { cat "$AGREE"; printf '\n— solo-qa\n\n<!-- okf-verdict v1\nverdict: pass\nhead_sha: %s\nreviewer: qa-reviewer\ndispatch: %s\n-->\n' "${3:-$H}" "$1"; } > "$TMP/qa-table"
    jq -n --rawfile body "$WORKER" --rawfile new "$TMP/qa-table" --arg h "$H" --arg t "$2" \
      '{body:$body, author:{login:"solo"}, url:"https://github.com/acme/widgets/pull/42", headRefOid:$h,
        comments:[{author:{login:"solo"},body:$new,createdAt:$t,includesCreatedEdit:false}]}' > "$FIX/pr_json"
  }
  mint() { "$REPO/plugin/scripts/qa-dispatch.sh" mint --repo acme/widgets --pr 42 --head "$H"; }
  serve_qa 0123456789abcdef0123456789abcdef 2099-01-01T00:00:00Z
  ok "same login, forged trailer + signature, no record: exit 4" "$(rc_of "$SCRIPT" 42 --repo acme/widgets)" 4
  serve_qa "$(mint)" 2099-01-01T00:00:00Z
  ok "same login, the recorded dispatch's nonce: clears"   "$(rc_of "$SCRIPT" 42 --repo acme/widgets)" 0
  serve_qa 0123456789abcdef0123456789abcdef 2099-01-01T00:00:00Z
  ok "…a record exists but the nonce is wrong: exit 4"      "$(rc_of "$SCRIPT" 42 --repo acme/widgets)" 4
  serve_qa "$(mint)" 2000-01-01T00:00:00Z
  ok "…the right nonce, posted before the record: exit 4"   "$(rc_of "$SCRIPT" 42 --repo acme/widgets)" 4
  serve_qa "$(mint)" 2099-01-01T00:00:00Z 0123456789abcdef0123456789abcdef01234567
  ok "…the trailer names another head: exit 4"              "$(rc_of "$SCRIPT" 42 --repo acme/widgets)" 4
  serve_qa "$(mint)" 2099-01-01T00:00:00Z
  jq '.comments[0].includesCreatedEdit = true' "$FIX/pr_json" > "$FIX/p2" && mv "$FIX/p2" "$FIX/pr_json"
  ok "…the verdict comment was edited: exit 4"               "$(rc_of "$SCRIPT" 42 --repo acme/widgets)" 4
  serve_qa "$(mint)" 2099-01-01T00:00:00Z
  jq '.comments = [.comments[0], .comments[0]]' "$FIX/pr_json" > "$FIX/p2" && mv "$FIX/p2" "$FIX/pr_json"
  ok "…the nonce replayed in a second comment: exit 4"      "$(rc_of "$SCRIPT" 42 --repo acme/widgets)" 4
  unset CLAUDE_PROJECT_DIR
  serve worker-bot qa-bot "$AGREE"
  ok "--checker naming nobody finds no table"  \
     "$(rc_of "$SCRIPT" 42 --repo acme/widgets --checker someone-else)" 2
  rm -f "$FIX/pr_json"
  ok "a host that cannot answer is exit 2"     "$(rc_of "$SCRIPT" 42 --repo acme/widgets)" 2
else
  echo "  FAIL  jq is required for the PR-mode block"; fail=$((fail+1))
fi

echo
echo "== the assertions are not vacuous — two mutants =="
MUT_A="$TMP/mutant-agrees.sh"; MUT_E="$TMP/mutant-no-evidence.sh"
sed 's/\[ "\$wv" = "CHK" \] \&\& \[ "\$cv" = "FAIL" \]/false/' "$SCRIPT" > "$MUT_A"
sed 's/^    has_evidence "\$cevi" ||/    true ||/' "$SCRIPT" > "$MUT_E"
chmod +x "$MUT_A" "$MUT_E"
ok "MUTANT: ignoring the checker's FAIL clears the disagreement" \
   "$(rc_of "$MUT_A" --body-file "$WORKER" --checker-file "$DISAGREE")" 0
ok "CONTROL: intact, the same fixture routes" "$(rc_of run "$DISAGREE")" 1
ok "MUTANT: skipping the evidence check clears the prose row" \
   "$(rc_of "$MUT_E" --body-file "$WORKER" --checker-file "$NO_COMMAND")" 0
ok "CONTROL: intact, the same fixture is refused" "$(rc_of run "$NO_COMMAND")" 3

echo
echo "== the rule is named where the agents read it =="
QA="$REPO/plugin/agents/qa-reviewer.md"
PM="$REPO/plugin/tick-steps/step-4-advance.md"
SCHEMA="$REPO/plugin/seed/SCHEMA.md"
ok "qa-reviewer.md forbids reading the worker's column" \
   "$(grep -c "never the worker" "$QA")" 1
ok "…and names PASS/FAIL with no partial credit"  \
   "$(grep -c 'no partial credit' "$QA")" 1
ok "project-manager.md calls the script by name"  \
   "$(grep -c 'pr-verdict-clearance.sh' "$PM")" 1
ok "…and SCHEMA.md names it as the clause-7 reader" \
   "$(grep -c 'reader for clause 7' "$SCHEMA")" 1
ok "…and states the solo-bundle limit"            \
   "$(grep -c 'KNOWN LIMIT' "$SCHEMA")" 1

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
