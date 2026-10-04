#!/usr/bin/env bash
#
# pr-comment-clearance.test.sh — exercises plugin/scripts/pr-comment-clearance.sh, the
# reader for a PR COMMENT.
#
# WHAT IT HAS TO PROVE, AND WHY EACH HALF IS HERE.
#
# `tests/pr-body-shape.test.sh` asserts that the reply and comment rules ARE NAMED in
# `CONVENTIONS.md`. That is a reader for the documentation, and it is doing its job. It is
# not a reader for the thing the rule governs, which is why a reply saying "both findings
# are valid, neither is fixed here, and why" ran to 2,986 characters over 20 lines while
# the rule was present, reachable and referenced. `pr-body-clearance.sh` did not cover it
# either: it reads a pull request's BODY and never a comment. This file covers the reader
# that takes an actual comment and answers.
#
# THE ANTI-TOTAL-CAP CASE IS THE ONE THAT MUST NOT REGRESS, and it is pinned three ways,
# because a total character limit is the obvious implementation of "stop the long replies"
# and it is the wrong one: it refuses the reply that honestly addresses eleven findings and
# clears the short self-defending one.
#
#   * BEHAVIOURALLY, ON REAL SHAPES — a reply LONGER than the 2,986-character incident,
#     whose content is twelve per-finding verdicts, CLEARS. And a SMALLER reply (one
#     700-byte entry) is refused while that larger one clears, which is the budget scaling
#     with N rather than with a number.
#   * AS THE DOCUMENT'S OWN EXAMPLE — the `md` block shipped in `CONVENTIONS.md` is
#     extracted from the file and driven through the gate. A rule whose own example its
#     reader would refuse is a rule nobody can follow, and this catches that pair drifting.
#   * STATICALLY — the character count is computed, printed and never compared. No line
#     mentioning the count variable contains a test, and the only magnitude comparison in
#     the shell is on `$#`. "Does not gate on length" is not checkable; "no threshold on
#     the total exists in the code" is, and this is it.
#
# NON-VACUITY IN BOTH DIRECTIONS, BECAUSE ONE DIRECTION IS NOT ENOUGH. Six vacuous
# assertions were found in this repo on 2026-08-30 alone, two of them inside harnesses
# written hours earlier. A ceiling proved only by a mutant that RAISES it can still be dead
# code at the low end, so both mutants run: raised, the measured case must stop being
# refused; lowered, the well-shaped long reply must stop clearing. `mutate()` refuses to
# invent a mutant whose anchor it cannot find — it prints SKIP and the suite goes red,
# because a mutant that never applied is not a mutant that was caught.
#
# `gh` is replaced by a stub on PATH, so the whole matrix runs offline. The stub RECORDS
# the API paths it was asked for, which is how the "it reads a COMMENT, not a body" claim
# is asserted rather than assumed.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO/plugin/scripts/pr-comment-clearance.sh"
CONV="$REPO/plugin/seed/CONVENTIONS.md"
SELFTEST_OK="pr-comment-clearance: self-test ok"
[ -r "$SCRIPT" ] || { echo "pr-comment-clearance.test: missing $SCRIPT" >&2; exit 2; }
[ -r "$CONV" ]   || { echo "pr-comment-clearance.test: missing $CONV" >&2; exit 2; }

# --- the numbers, and where each one came from --------------------------------
# THESE ARE FIXTURES, NOT A LIVE READ. They were measured on 2026-08-31 in bytes under
# `LC_ALL=C` over the fence-stripped rendering of every comment this repo's own agents
# wrote on `cbmono/loopd` pull requests 60-84 — 13 PR-thread comments and 3 inline
# review comments, 16 replies, 65 elements — plus the `alteos-gmbh/monorepo#3260` comment
# that motivated the task. A live comment is not a fixture (anyone can edit one), so the
# boundary values live here and this harness never asks the host for them.
CEILING=618                 # midpoint of the empty band 531-705, the corpus gap
LARGEST_ELEMENT=530         # largest element measured anywhere    -> must CLEAR
BEST_SHAPED_WORST=503       # worst element of the best-shaped reply -> must CLEAR
SECOND_BEST_WORST=496       # worst element of the runner-up         -> must CLEAR
SMALLEST_BLOAT=706          # smallest element the brief calls bloat -> must REFUSE
MOTIVATING_ENTRY1=1841      # the measured reply's first entry       -> must REFUSE
MOTIVATING_CHARS=2986       # the measured reply's own length. A cap at or below this
                            # number turns the `a longer well-shaped reply` case red.

TMP="$(mktemp -d "${TMPDIR:-/tmp}/pr-comment-clearance.XXXXXX")" || {
  echo "pr-comment-clearance.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
# The mutants run from $TMP, and the script sources its sibling resolver
# (ai-bridge-v3/task-031) — without it they exit 2 before reaching their subject.
cp "$(dirname "$SCRIPT")/bundle-paths.sh" "$TMP/bundle-paths.sh"

pass=0; fail=0; skipped=0
command -v jq >/dev/null 2>&1 || { echo "jq is required to run this test"; exit 2; }
REAL_JQ="$(command -v jq)"
export FIX="$TMP/fix"
mkdir -p "$TMP/bin" "$FIX"

# --- stubs --------------------------------------------------------------------
# The `gh` stub answers from $FIX and APPENDS every path it was asked for to
# $FIX/api_calls, so this file can assert WHICH host object the script read.
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "api "*|"api")
    printf '%s\n' "${2:-}" >> "$FIX/api_calls"
    [ -f "$FIX/gh_broken" ] && { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
    case "${2:-}" in
      repos/*/issues/comments/*) src="$FIX/comment_json" ;;
      repos/*/pulls/comments/*)  src="$FIX/comment_json" ;;
      *) echo "stub: unhandled api path '${2:-}'" >&2; exit 99 ;;
    esac
    [ -f "$src" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
    cat "$src"; exit 0 ;;
  "repo view")
    printf '%s\n' "repo view" >> "$FIX/api_calls"
    [ -f "$FIX/no_repo" ] && { echo "gh: no git remote found" >&2; exit 1; }
    echo "acme/widgets"; exit 0 ;;
esac
echo "stub: unhandled gh $*" >&2; exit 99
STUB
cat > "$TMP/bin/jq" <<STUB
#!/usr/bin/env bash
# The real jq, unless a case asks for a reader that cannot answer.
[ -f "\$FIX/jq_broken" ] && { echo "jq: broken pipe of a parser" >&2; exit 5; }
exec "$REAL_JQ" "\$@"
STUB
chmod +x "$TMP/bin/gh" "$TMP/bin/jq"
export PATH="$TMP/bin:$PATH"

# --- fixtures -----------------------------------------------------------------
reply_file() { # <lines...> -> a file holding them
  local f; f="$(mktemp "$TMP/reply.XXXXXX")"; printf '%s\n' "$@" > "$f"; printf '%s' "$f"
}

serve() { # <reply-file> — publish it as the comment the script will read
  rm -f "$FIX/gh_broken" "$FIX/jq_broken" "$FIX/no_repo" "$FIX/api_calls"
  "$REAL_JQ" -n --rawfile b "$1" \
    '{html_url:"https://github.com/acme/widgets/pull/42#issuecomment-4242", id:4242, body:$b}' \
    > "$FIX/comment_json"
}

chars() { "$REAL_JQ" -Rs 'length' < "$1"; }   # code points, as the host counts them
pad()   { printf '%*s' "$1" '' | tr ' ' 'x'; }

# An entry of EXACTLY <n> bytes: `- fixed: ` is 9 ASCII bytes, so the pad lands the element
# on the boundary rather than near it.
entry() { printf -- '- fixed: %s' "$(pad "$(( $1 - 9 ))")"; }

# A conforming reply carrying one entry per argument, each of that many bytes.
entries_reply() {
  local -a lines
  lines=('Round 1 addressed in `a1b2c3d`.' '')
  local n
  for n in "$@"; do lines+=("$(entry "$n")"); done
  lines+=('' 'Evidence: `foo.test.sh` 41/0.')
  reply_file "${lines[@]}"
}

# --- assertions ---------------------------------------------------------------
expect() { # <name> <expected-rc> [args...]
  local name="$1" want="$2"; shift 2
  local out rc
  out="$("$SCRIPT" "$@" 2>&1)"; rc=$?
  if [ "$rc" -eq "$want" ]; then
    printf '  PASS  %-62s (rc=%s)\n' "$name" "$rc"; pass=$((pass+1))
  else
    printf '  FAIL  %-62s expected rc=%s got rc=%s\n' "$name" "$want" "$rc"
    printf '        output: %s\n' "$(head -3 <<<"$out" | tr '\n' '|')"
    fail=$((fail+1))
  fi
  LAST_OUT="$out"
}

says() { # <name> <substring> — against the previous expect()'s output
  if grep -Fq "$2" <<<"$LAST_OUT"; then
    printf '  PASS  %-62s\n' "$1"; pass=$((pass+1))
  else
    printf '  FAIL  %-62s missing %s in: %s\n' "$1" "$2" "$(head -4 <<<"$LAST_OUT" | tr '\n' '|')"
    fail=$((fail+1))
  fi
}

says_not() { # <name> <substring>
  if grep -Fq "$2" <<<"$LAST_OUT"; then
    printf '  FAIL  %-62s unexpectedly said %s\n' "$1" "$2"; fail=$((fail+1))
  else
    printf '  PASS  %-62s\n' "$1"; pass=$((pass+1))
  fi
}

ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

echo "== the script runs, and proves it =="
out="$("$SCRIPT" --self-test 2>&1)"; rc=$?
ok "--self-test exits 0"                  "$rc" 0
ok "--self-test prints its contract"      "$out" "$SELFTEST_OK"

# The sibling's lesson, taken whole: "IT RUNS" IS NOT "IT IS COMPLETE". A copy cut off
# below the self-test block still reaches that block, still passes it, and still prints the
# sentinel — with the parser below the cut simply gone. Only "exit 0 AND the contract
# string" separates a working script from a file of nothing but comments.
selftest_contract() { # <path> -> yes if it exits 0 AND prints the contract string
  local o r
  o="$("$1" --self-test 2>/dev/null)"; r=$?
  if [ "$r" -eq 0 ] && [ "$o" = "$SELFTEST_OK" ]; then echo yes; else echo no; fi
}
CUT="$TMP/cut.sh"
head -c 6000 "$SCRIPT" > "$CUT"; chmod +x "$CUT"
ok "a copy cut inside the header does not vouch for itself" "$(selftest_contract "$CUT")" no
TOTAL_LINES="$(grep -c '' "$SCRIPT")"
ST_LINE="$(grep -n '^if \[ "\${1:-}" = "--self-test" \]' "$SCRIPT" | cut -d: -f1)"
ok "the self-test block is located" "$([ -n "$ST_LINE" ] && echo yes || echo no)" yes
for pct in 5 33 66 99; do
  n=$(( ST_LINE + ( (TOTAL_LINES - ST_LINE) * pct / 100 ) ))
  head -n "$n" "$SCRIPT" > "$CUT"; chmod +x "$CUT"
  ok "cut ${pct}% past the self-test -> refuses to vouch for itself" \
     "$(selftest_contract "$CUT")" no
done
ok "…while the intact file does vouch for itself" "$(selftest_contract "$SCRIPT")" yes

echo
echo "== it reads a COMMENT from the host, which is the gap #75 left =="
# `pr-body-clearance.sh` reads `gh pr view --json body`. This reads a comment object, and
# the stub records the path so that claim is asserted rather than believed.
serve "$(entries_reply 120 140)"
expect "a PR-thread comment by id -> clear" 0 --comment 4242 --repo acme/widgets
ok "…and it asked the host for an ISSUE COMMENT" \
   "$(grep -c '^repos/acme/widgets/issues/comments/4242$' "$FIX/api_calls" || true)" 1
serve "$(entries_reply 120 140)"
expect "an inline review comment by id -> clear" 0 --review-comment 99 --repo acme/widgets
ok "…and it asked the host for a REVIEW COMMENT" \
   "$(grep -c '^repos/acme/widgets/pulls/comments/99$' "$FIX/api_calls" || true)" 1
ok "…and it never asked for a pull request BODY" \
   "$(grep -c 'pr view' "$FIX/api_calls" || true)" 0
ok "the script contains no 'gh pr view' call at all" \
   "$(grep -c 'gh pr view' "$SCRIPT" || true)" 0
serve "$(entries_reply 120)"
expect "no --repo: the current repository is resolved" 0 --comment 4242
ok "…via gh repo view" "$(grep -c '^repo view$' "$FIX/api_calls" || true)" 1

echo
echo "== STRUCTURAL, never a total cap =="
# A reply LONGER than the incident, whose content is twelve per-finding verdicts, clears.
# Twelve entries at 250 bytes each is 3,000 bytes of entries alone.
LONG="$(entries_reply 250 250 250 250 250 250 250 250 250 250 250 250)"
LONG_CHARS="$(chars "$LONG")"
ok "the well-shaped fixture is longer than the incident" \
   "$([ "$LONG_CHARS" -ge "$MOTIVATING_CHARS" ] && echo yes || echo no)" yes
serve "$LONG"
expect "a ${MOTIVATING_CHARS}+-character reply of twelve verdicts -> CLEAR" 0 --comment 4242
says   "  ...reporting the count as information" "characters (information"
says   "  ...saying plainly that no exit code comes from it" \
       "no exit code in this script is derived from that"

# Forty entries at the ceiling is ~25,000 bytes and clears, because nothing sums them.
# shellcheck disable=SC2046
serve "$(entries_reply $(for _ in $(seq 40); do printf '%s ' "$CEILING"; done))"
expect "forty entries each AT the ceiling -> clear" 0 --comment 4242

echo
echo "== the budget SCALES WITH N, so a SMALLER reply can be the refused one =="
# The scaling claim, made as a pair rather than as prose: one 700-byte entry is refused at a
# total of ~760 characters, while twelve 250-byte entries clear at four times that.
ONE_BIG="$(entries_reply 700)"
serve "$ONE_BIG"
expect "ONE entry of 700 bytes ($(chars "$ONE_BIG") chars total) -> refuse" 3 --comment 4242
ok "…and the reply that CLEARED is the longer one" \
   "$([ "$LONG_CHARS" -gt "$(chars "$ONE_BIG")" ] && echo yes || echo no)" yes
# The same content, split one entry per finding, clears — which is the advice the refusal
# gives, driven rather than asserted.
serve "$(entries_reply 240 240 240)"
expect "the same ~720 bytes SPLIT into three entries -> clear" 0 --comment 4242

echo
echo "== the ceiling, ON the measured boundaries =="
serve "$(entries_reply "$LARGEST_ELEMENT")"
expect "the largest element in the corpus ($LARGEST_ELEMENT) -> clear" 0 --comment 4242
serve "$(entries_reply "$BEST_SHAPED_WORST")"
expect "the best-shaped reply's worst element ($BEST_SHAPED_WORST) -> clear" 0 --comment 4242
serve "$(entries_reply "$SECOND_BEST_WORST")"
expect "the runner-up's worst element ($SECOND_BEST_WORST) -> clear" 0 --comment 4242
serve "$(entries_reply "$CEILING")"
expect "exactly the ceiling ($CEILING) -> clear" 0 --comment 4242
serve "$(entries_reply "$(( CEILING + 1 ))")"
expect "one byte over the ceiling -> refuse" 3 --comment 4242
serve "$(entries_reply "$SMALLEST_BLOAT")"
expect "the smallest element the brief calls bloat ($SMALLEST_BLOAT) -> refuse" 3 --comment 4242
says   "  ...naming it by index and size" "ENTRY 1 at $SMALLEST_BLOAT bytes"
serve "$(entries_reply "$MOTIVATING_ENTRY1")"
expect "the measured reply's own first entry ($MOTIVATING_ENTRY1) -> refuse" 3 --comment 4242
says   "  ...at the size the incident measured" "ENTRY 1 at $MOTIVATING_ENTRY1 bytes"
says   "  ...and where the detail goes instead" "belong in the commit message and the task"
says   "  ...and that this is not a reply-length cap" "This bounds ONE ELEMENT, never the reply"
ok "the ceiling in the script is the measured one" \
   "$(grep -c "^REPLY_ELEMENT_CEILING=$CEILING\$" "$SCRIPT" || true)" 1

echo
echo "== the LEAD and the CLOSING block are bounded too =="
# In the corpus the bloat sat in the lead as often as in an entry: two real replies carried
# leads of 1,135 and 1,759 bytes above a correctly shaped list.
serve "$(reply_file "All five valid. $(pad 1135)" '' "$(entry 120)" '' 'Evidence: 41/0.')"
expect "a 1,151-byte LEAD above a correct list -> refuse" 3 --comment 4242
says   "  ...naming the lead, not the entry" "the LEAD at"
says_not "  ...and not blaming the entry, which is fine" "ENTRY 1 at"
serve "$(reply_file 'All five valid.' '' "$(entry 120)" '' "Evidence: $(pad 966)")"
expect "a 976-byte CLOSING block -> refuse" 3 --comment 4242
says   "  ...naming the closing block" "the CLOSING BLOCK at"

echo
echo "== the self-defending shape is caught, and its twin at the same length is not =="
# The measured reply's shape, reproduced: ~250 characters of decision per finding wrapped in
# twelve times its own weight of argument about the author rather than the code. Built to
# EXACTLY the incident's 2,986 characters, so a fixture that drifts shorter cannot quietly
# stop being the case under test.
DEF="$TMP/self-defending.md"
{
  printf '%s\n\n' 'Thanks — both findings verified, both valid, and neither is fixed in this PR.'
  printf '%s\n\n' '### 1. `directory.ts:207-223` — bound the total time, not only the page count · **already a logged, deferred item**'
  printf '%s\n\n' 'Confirmed at the source rather than taken on trust: the client defaults to a per-attempt timeout and three retries, so the page cap bounds requests and nothing bounds elapsed time. The arithmetic in the finding is right.'
  printf '%s' 'Worth saying plainly: this is the third time an independent reviewer has converged on one of the deferred items from a different call site. That is signal, and it raises the item priority rather than arguing against the deferral. '
  # The pad lands INSIDE the first entry, which is where the measured reply carried its own
  # excess (1,841 bytes), and it makes the fixture exactly the incident's length.
  printf '%s\n\n' '__PAD__'
  printf '%s\n\n' '### 2. `directory.test.ts:242-264` — no test for a 200 with no token · **valid gap, recorded as a follow-up**'
  printf '%s\n\n' 'Also correct: the module throws on a mint that returns no token, and no test drives it. It is a fail-closed branch on an upstream-controlled payload, which is exactly the class this task cares about.'
  printf '%s\n\n' 'For the record, the branch is not untested — the sibling rejection path is covered, and what is missing is specifically the 200-with-no-token shape. Not added here because the slice is a mechanical copy rather than new authoring, and editing the file forfeits the byte-identity property that is the only reason the earlier review transfers.'
  printf '%s\n' 'Evidence: `directory.test.ts` 18/0.'
} > "$DEF.tpl"
short_by=$(( MOTIVATING_CHARS - $(chars "$DEF.tpl") + 7 ))
sed -e "s/__PAD__/$(pad "$short_by")/" "$DEF.tpl" > "$DEF"
ok "the self-defending fixture is exactly the incident's length" "$(chars "$DEF")" "$MOTIVATING_CHARS"
serve "$DEF"
expect "the ${MOTIVATING_CHARS}-character self-defending reply -> REFUSE" 3 --comment 4242
says   "  ...naming which entry is over, by index and size" "ENTRY 1 at"
says   "  ...and the second one too" "ENTRY 2 at"
# THE OTHER DIRECTION, AND IT IS THE POINT. A gate that cannot tell these apart at equal
# length has found the size, not the defect.
serve "$LONG"
expect "…while ${LONG_CHARS} characters of per-finding verdicts -> CLEAR" 0 --comment 4242

echo
echo "== an entry with no VERDICT is a different refusal, with a different code =="
serve "$(reply_file 'Round 1 addressed.' '' '- `run.sh:42` is quoted now, and the null case is covered.')"
expect "an entry that never says what the verdict was -> refuse" 1 --comment 4242
says   "  ...naming the entry by index" "entry 1"
says   "  ...and the vocabulary to use" "valid, fixed, declined, already"
for v in fixed valid declined 'already deferred' confirmed 'not taking' 'out of scope' 'no change'; do
  serve "$(reply_file 'Round 1 addressed.' '' "- \`run.sh:42\` — $v: the path is quoted now.")"
  expect "the verdict '$v' -> clear" 0 --comment 4242
done
# A SECTION HEADING above the list is read as an entry and refused for carrying no verdict.
# That is a decision, not an accident: recognising a heading as an entry is what catches the
# measured comment, whose findings WERE `###` headings. Pinned so a future edit that
# "fixes" it has to argue with this assertion.
serve "$(reply_file '### Round 1 replies' '' '- fixed: the path is quoted now.')"
expect "a section heading above the list -> refuse, naming itself" 1 --comment 4242
says   "  ...quoting the heading, so the fix is one line" '"### Round 1 replies"'

# `already` on its own is an ordinary adverb — nine uses of it in the corpus are not
# verdicts — so it must not buy a clearance.
serve "$(reply_file 'Round 1 addressed.' '' '- `run.sh:42` — already covered by the harness.')"
expect "a bare 'already' is not a verdict -> refuse" 1 --comment 4242

echo
echo "== 'correct' is a verdict only where it STANDS as one, never as an adjective =="
# THE REFUSE HALF. Measured on 1.1.x: `correct` shipped as a bare token, so an entry
# DESCRIBING a fix it had not made cleared — every other token in the table is a
# past-tense verdict and this was the one adjective. The probe is the measured one: entry
# 1 states no verdict and says outright the fix was not done, and the pre-fix reader named
# only entry 2.
ADJ="$(reply_file 'Round 1 addressed.' '' \
  '- Finding 1 — the correct fix would be to quote the path, but I have not done it.' \
  '- Finding 2 — I think the reviewer is wrong about the timeout.')"
serve "$ADJ"
expect "the measured probe: two verdict-less entries -> refuse" 1 --comment 4242
says   "  ...naming the ADJECTIVAL entry, which used to clear" "entry 1"
says   "  ...and the plainly verdict-less one" "entry 2"
# Its own control: the same reply with a verdict on entry 1 clears, so the refusal above is
# about the missing verdict and not about the fixture.
serve "$(reply_file 'Round 1 addressed.' '' \
  '- Finding 1 — fixed: the path is quoted now.' \
  '- Finding 2 — declined: the timeout is per attempt by design.')"
expect "…the same two findings WITH verdicts -> clear" 0 --comment 4242
# The adjective in its other ordinary shapes, each alone in a reply so nothing else can be
# answering for the refusal.
for adj in 'the correct approach is a retry, and I have not written one' \
           'a correct implementation would bound the loop' \
           'this is the correct reading of the spec, but nothing changed here'; do
  serve "$(reply_file 'Round 1 addressed.' '' "- \`run.sh:42\` — $adj.")"
  expect "adjectival: '${adj:0:34}…' -> refuse" 1 --comment 4242
done

# THE ALLOW HALF — the entries CONVENTIONS.md's own worked examples use. All four in one
# reply, which is the shape the document ships, and then one per reply so a single clearing
# verdict cannot carry the other three.
serve "$(reply_file 'Round 1 addressed in `a1b2c3d`.' '' \
  '1. **`run.sh:42` unquoted `$dir`** — fixed: quoted it, `harness-temp-safety.test.sh` 12/0.' \
  '2. **`http.ts` timeout is per attempt** — already deferred: item 3 on the task list.' \
  '3. **no test for a 200 with no token** — declined: unreachable until slice 4.' \
  '4. **the null case is real** — valid: recorded as a follow-up.' '' \
  'Evidence: `foo.test.sh` 41/0.')"
expect "the four worked-example verdicts in one reply -> clear" 0 --comment 4242
for v in fixed declined 'already deferred' valid; do
  serve "$(reply_file 'Round 1 addressed.' '' "- \`run.sh:42\` — $v: the path is quoted now.")"
  expect "worked example '$v' alone -> still clears" 0 --comment 4242
done
# …and `correct` where it IS the verdict: nothing but punctuation or the end of the entry
# follows it, which is the whole of the narrowing.
for c in 'correct: the path is quoted now' \
         'the reviewer is correct. Quoted now' \
         'correct, and quoted now' \
         'correct'; do
  serve "$(reply_file 'Round 1 addressed.' '' "- \`run.sh:42\` — $c")"
  expect "standing verdict '${c:0:26}…' -> clear" 0 --comment 4242
done

echo
echo "== a reply with no entries is ONE element =="
# `@coderabbitai review` and "round 2 clean" are legitimate replies with no findings to
# address; refusing them would be nonsense. A wall of prose where a list belonged is the
# same shape at a different size, and that is what the ceiling catches.
serve "$(reply_file '@coderabbitai review')"
expect "a 20-character bot command -> clear" 0 --comment 4242
serve "$(reply_file 'Round 2 clean — nothing further, and no re-review requested.')"
expect "a one-line acknowledgement -> clear" 0 --comment 4242
serve "$(reply_file "All three are valid and none is fixed here. $(pad 900)")"
expect "a 940-byte wall of prose with no entries -> refuse" 3 --comment 4242
says   "  ...naming it as one block" "the WHOLE REPLY at"
says   "  ...and telling the author to give each finding an entry" "Give each finding its own entry"

echo
echo "== the carve-outs are honoured: three things are never trimmed =="
# THE ONE MATCH IN THE SCRIPT THAT FAILS OPEN, so it is driven in both directions: the
# claim clears an oversized reply, and the SAME text without the claim does not.
for claim in '**Security** — the mint token is logged in plaintext at `directory.ts:146`.' \
             '**Error report** — the tick aborted before the lock was released.' \
             '**Destructive** — this would `git push --force` over the shared branch.'; do
  serve "$(reply_file "$claim" "$(pad 900)")"
  expect "a carve-out claim clears at 940 bytes: ${claim:0:26}…" 0 --comment 4242
  says   "  ...saying it was exempt, and quoting the claim" "claims a CARVE-OUT"
  says   "  ...and that no size was measured" "No element size was measured"
done
# THE CARVE-OUT EXEMPTS THE CEILING AND NOTHING ELSE. A reply shaped as a list of findings
# still owes a verdict on each of them, whatever it is reporting — the first cut of the
# script read the claim BEFORE the shape and exempted both.
serve "$(reply_file '**Security** — the mint token is logged in plaintext.' '' \
                    '- `directory.ts:146` logs the token at info level.')"
expect "a carve-out with a verdict-less entry -> still refuse" 1 --comment 4242
says   "  ...on the shape, not the size" "the VERDICT is missing on"
serve "$(reply_file '**Security** — the mint token is logged in plaintext.' '' \
                    "- fixed: it is redacted now. $(pad 900)")"
expect "…and with a verdict, the oversized entry is exempt" 0 --comment 4242

# The control: strip the claim, keep the size, and the same reply is refused. Without this
# the three cases above would pass for a gate that cleared everything.
serve "$(reply_file "The mint token is logged in plaintext at \`directory.ts:146\`." "$(pad 900)")"
expect "…the same reply with no claim -> refuse" 3 --comment 4242
# And a mid-sentence mention buys nothing: the claim must lead a line's own content.
serve "$(reply_file "Nothing here is a security problem, for the record. $(pad 900)")"
expect "a mid-sentence mention of security -> refuse" 3 --comment 4242
says   "  ...and the refusal still names the carve-outs" "are never trimmed"

echo
echo "== unreadable is never clearance, and it is its own exit code =="
serve "$(entries_reply 120)"
: > "$FIX/gh_broken"
expect "the comment cannot be fetched -> unknown, not clear" 2 --comment 4242 --repo acme/widgets
says   "  ...saying unknown is never clearance" "unknown is never clearance"
serve "$(entries_reply 120)"
rm -f "$FIX/comment_json"
expect "no such comment -> unknown, not clear" 2 --comment 4242 --repo acme/widgets
# A body field the host did not send is not an empty comment: one is a read that did not
# answer, the other is a comment somebody left blank, and only the second is the author's.
"$REAL_JQ" -n '{html_url:"https://github.com/acme/widgets/pull/42#issuecomment-4242", id:4242}' \
  > "$FIX/comment_json"
expect "no body FIELD -> unknown, not an empty comment" 2 --comment 4242 --repo acme/widgets
says   "  ...saying so in those words" "so its text is unknown"
serve "$(entries_reply 120)"
: > "$FIX/jq_broken"
expect "the JSON reader cannot answer -> unknown, not clear" 2 --comment 4242 --repo acme/widgets
rm -f "$FIX/jq_broken"
serve "$(entries_reply 120)"
: > "$FIX/no_repo"
expect "no repo to resolve -> unknown, not clear" 2 --comment 4242
serve "$(reply_file '')"
expect "an EMPTY comment -> refuse (readable, not unknown)" 1 --comment 4242
says   "  ...and it says the reply is empty" "is empty"
# The four codes are documented in the file, not only implemented.
for code in 0 1 2 3; do
  ok "exit $code is documented in the header" \
     "$(grep -cE "^#   $code  " "$SCRIPT" || true)" 1
done
ok "…and the fetch failure is documented as never clearance" \
   "$(grep -c 'NEVER 0' "$SCRIPT" || true)" 1

echo
echo "== usage, and the draft route =="
GOOD="$(entries_reply 120 140)"
expect "a conforming draft -> clear" 0 --comment-file "$GOOD"
says   "  ...and reports its length too" "characters (information"
expect "a draft over the ceiling -> refuse" 3 --comment-file "$(entries_reply 900)"
expect "a draft that does not exist -> unknown, not clear" 2 --comment-file "$TMP/nope.md"
expect "--comment-file with a comment id too -> usage error" 2 --comment-file "$GOOD" --comment 4242
rc=0; "$SCRIPT" >/dev/null 2>&1 || rc=$?
ok "no arguments -> usage error" "$rc" 2
expect "an unknown option -> usage error" 2 --nope

echo
echo "== the count is INFORMATION, and the code says so structurally =="
# "Does not gate on length" is not checkable. "No threshold on the total exists" is.
marked="$(grep -n 'reply_chars' "$SCRIPT" | grep -cE '(-gt|-lt|-ge|-le|-eq|-ne)|\(\(|\[\[|\[ ' || true)"
ok "no line mentioning the count contains a test" "$marked" 0
mags="$(grep -nE -- '-gt|-lt|-ge|-le' "$SCRIPT" | grep -vc '"\$#"' || true)"
ok "the only shell magnitude comparison is on \$#" "$mags" 0
# The awk side: exactly ONE comparison reads a measured element against the ceiling, and
# the parser never sees the reply's own count at all — a stronger statement than "it is not
# compared", since a total cap can only be built from a number the comparing code reaches.
ok "exactly one comparison is against the ceiling" \
   "$(grep -cE '\$4 > c' "$SCRIPT" || true)" 1
ok "…and the parser never sees the reply's count" \
   "$(sed -n '/^scan_reply() {/,/^}/p' "$SCRIPT" | grep -c 'reply_chars' || true)" 0

echo
echo "== the pattern tables carry no backslash escapes, because awk -v eats them =="
# MEASURED WHILE WRITING THIS: a row spelled `\*\*` arrives at awk as `**` — `-v` processes
# escape sequences before the value is ever used as a regex — and awk then dies on the
# first comment it reads. `validate_tables` compiles every row through the same `-v` path
# for that reason; the first cut compiled them with `grep -E`, which accepted what awk
# could not read. This is the static half of the same guard.
table_rows() { sed -n "/^$1='/,/^'\$/p" "$SCRIPT" | grep -v "^$1='" | grep -v "^'\$" | grep -v '^#' | grep -v '^$'; }
ok "the verdict table has rows"    "$([ -n "$(table_rows VERDICTS)" ] && echo yes || echo no)" yes
ok "the carve-out table has rows"  "$([ -n "$(table_rows CARVE_OUTS)" ] && echo yes || echo no)" yes
ok "no backslash in any verdict row"   "$(table_rows VERDICTS   | grep -c '\\' || true)" 0
ok "no backslash in any carve-out row" "$(table_rows CARVE_OUTS | grep -c '\\' || true)" 0
# GNU-only escapes are the same class of trap in the other direction: they compile, and
# then mean something different on BSD awk.
ok "no GNU-only escape in the tables" \
   "$( { table_rows VERDICTS; table_rows CARVE_OUTS; } | grep -cE '\\(d|s|w|b|<|>)' || true)" 0
ok "validate_tables compiles rows through awk -v, not grep" \
   "$(sed -n '/^validate_tables() {/,/^}/p' "$SCRIPT" | grep -c 'awk -v p=' || true)" 1

# Every pattern in the script uses a brace interval, and an awk that reads `{1,6}` as
# literal braces compiles them happily and matches nothing — so `validate_tables` probes the
# SEMANTICS, in both directions, and refuses at exit 2 when the engine disagrees.
ok "validate_tables probes interval semantics, not just compilation" \
   "$(sed -n '/^validate_tables() {/,/^}/p' "$SCRIPT" | grep -c '"###" ~ /\^#{1,6}\$/' || true)" 1
cat > "$TMP/bin/awk" <<'STUB'
#!/usr/bin/env bash
# An awk that cannot answer at all. The script must refuse, never clear.
exit 1
STUB
chmod +x "$TMP/bin/awk"
serve "$(entries_reply 120)"
expect "an awk that cannot answer -> unknown, not clear" 2 --comment 4242
says   "  ...naming the interval support it needs" "POSIX interval expressions"
rm -f "$TMP/bin/awk"
serve "$(entries_reply 120)"
expect "…and with a working awk back, the same reply clears" 0 --comment 4242

echo
echo "== the rule is in CONVENTIONS.md, and it NAMES this reader =="
# `pr-body-shape.test.sh` asserts the reply and comment rules are named. This asserts the
# rule that has a reader names it — the [[a-rule-with-no-reader-is-not-a-rule]] pattern this
# whole change is an instance of. Flattened first: the document wraps its bullets, so a
# sentence spanning two lines is not greppable as written.
flatten() { tr '\n' ' ' < "$1" | tr -s ' '; }
CONV_FLAT="$(flatten "$CONV")"
saw() { if grep -Fq "$2" <<<"$1"; then echo yes; else echo no; fi; }
ok "the rule is there"                "$(saw "$CONV_FLAT" 'A reply to review findings has a shape, and now it has a reader.')" yes
ok "the reader is NAMED, with its flag" "$(saw "$CONV_FLAT" '`scripts/pr-comment-clearance.sh --comment <id>` is the reader')" yes
ok "the draft route is named too"     "$(saw "$CONV_FLAT" '`--comment-file <draft>` decides before you post')" yes
ok "the per-entry verdict is required" "$(saw "$CONV_FLAT" '**Each entry carries a VERDICT**')" yes
ok "one element, never the reply"     "$(saw "$CONV_FLAT" '**It bounds ONE ELEMENT, never the reply.**')" yes
ok "N findings buy N entries"         "$(saw "$CONV_FLAT" '**N findings buy N entries**')" yes
ok "the number is stated"             "$(saw "$CONV_FLAT" 'any element over **618 bytes** at **exit 3**')" yes
ok "…and so is its derivation"        "$(saw "$CONV_FLAT" 'the midpoint of the empty band **531–705**')" yes
ok "…and what re-measuring means"     "$(saw "$CONV_FLAT" '**Moving it means re-measuring**')" yes
ok "the exits are documented"         "$(saw "$CONV_FLAT" 'is **exit 2**, which is unknown and never clearance')" yes
ok "WHERE the detail goes is stated"  "$(saw "$CONV_FLAT" '**The detail is relocated, never deleted**')" yes
ok "…naming the three durable places" "$(saw "$CONV_FLAT" 'it goes in the **task doc**, the **commit message** or a **`Finding`**')" yes
ok "…and requiring the entry to LINK" "$(saw "$CONV_FLAT" '**the short entry links to it**')" yes
ok "…consistent with the durable line" "$(saw "$CONV_FLAT" 'as "reasoning belongs where it is durable" says')" yes
ok "the three carve-outs are stated"  "$(saw "$CONV_FLAT" '**Three things are NEVER trimmed, and the reader honours them:**')" yes
ok "…an error report"                 "$(saw "$CONV_FLAT" 'an **error report**')" yes
ok "…a security finding"              "$(saw "$CONV_FLAT" 'a **security finding**')" yes
ok "…a destructive-action confirmation" "$(saw "$CONV_FLAT" 'a **destructive-action confirmation**')" yes
ok "the harness is named as the pin"  "$(saw "$CONV_FLAT" '`tests/pr-comment-clearance.test.sh` pins the boundary values')" yes

# MUTATION: cut the bullet, and every assertion above flips. `strip_bullet` deletes from the
# `- ` bullet containing the marker to the next `- ` bullet — what "just trim this section"
# would actually delete.
strip_bullet() { # <file> <marker>
  awk -v m="$2" '
    index($0, m) && /^- / { skip=1; next }
    skip && /^- /          { skip=0 }
    !skip                  { print }
  ' "$1"
}
strip_bullet "$CONV" '**A reply to review findings has a shape' > "$TMP/conv-cut.md"
MUT_FLAT="$(flatten "$TMP/conv-cut.md")"
ok "the mutation removed something" \
   "$([ "$(wc -c < "$TMP/conv-cut.md")" -lt "$(wc -c < "$CONV")" ] && echo yes || echo no)" yes
ok "CONTROL: the neighbouring comment rule survives" \
   "$(saw "$MUT_FLAT" '**A GitHub comment is about 280 characters — roughly a tweet.**')" yes
ok "CONTROL: the two-round cap survives" "$(saw "$MUT_FLAT" '**TWO ROUNDS, THEN THE HUMAN DECIDES.')" yes
ok "mutant: the rule is gone"            "$(saw "$MUT_FLAT" 'A reply to review findings has a shape, and now it has a reader.')" no
ok "mutant: the named reader is gone"    "$(saw "$MUT_FLAT" '`scripts/pr-comment-clearance.sh --comment <id>` is the reader')" no
ok "mutant: the number is gone"          "$(saw "$MUT_FLAT" 'the midpoint of the empty band **531–705**')" no
ok "mutant: the carve-outs are gone"     "$(saw "$MUT_FLAT" '**Three things are NEVER trimmed, and the reader honours them:**')" no
ok "mutant: where-the-detail-goes is gone" "$(saw "$MUT_FLAT" '**The detail is relocated, never deleted**')" no

echo
echo "== the document's own example clears its own reader =="
# A rule whose shipped example its own gate would refuse is a rule nobody can follow, and
# the two drifting apart is invisible in review. The `md` block is extracted from
# CONVENTIONS.md, dedented, and driven through the gate. It is also the whole of criterion
# 9: the accepted form is ordinary prose a person would write, and this is that form.
example_of() { # <file> <bullet-marker> -> the first fenced block after the bullet, dedented
  awk -v m="$2" '
    index($0, m) && /^- / { seen=1 }
    seen && !inb && /^[[:space:]]*```/ { inb=1; next }
    inb && /^[[:space:]]*```/ { exit }
    inb { sub(/^  /, ""); print }
  ' "$1"
}
EX="$TMP/example.md"
example_of "$CONV" '**A reply to review findings has a shape' > "$EX"
ok "the example was extracted" "$([ -s "$EX" ] && echo yes || echo no)" yes
ok "…and it carries three entries" "$(grep -cE '^[0-9]+\. ' "$EX" || true)" 3
serve "$EX"
expect "CONVENTIONS.md's own reply example -> CLEAR" 0 --comment 4242
# …and it is a real test of the gate, not of leniency: drop the verdicts out of the example
# and the same text is refused.
sed -e 's/ — fixed:/:/' -e 's/ — already deferred:/:/' -e 's/ — declined:/:/' "$EX" > "$TMP/example-noverdict.md"
ok "the de-verdicted copy really differs" \
   "$([ "$(wc -c < "$TMP/example-noverdict.md")" -lt "$(wc -c < "$EX")" ] && echo yes || echo no)" yes
serve "$TMP/example-noverdict.md"
expect "…the same example with its verdicts removed -> refuse" 1 --comment 4242

echo
echo "== NON-VACUITY: a mutant that RAISES the ceiling, and one that LOWERS it =="
# Both directions, because one is not enough: a ceiling proved only by raising it can still
# be dead code at the low end. Each mutant is built from the file that just passed, so it
# differs in exactly one respect and nothing else can be answering for it.
#
# AND A MUTANT WHOSE ANCHOR IS ABSENT IS *SKIPPED*, NOT COUNTED AS CAUGHT — the suite goes
# red on a skip, because "the mutant did not apply" and "the mutant was caught" are
# indistinguishable at the assertion and only one of them is evidence.
# IT RETURNS ITS PATH IN A VARIABLE, NOT ON STDOUT, AND THAT IS THE FIX FOR A REAL DEFECT
# (ai-bridge#85 round 1). The first cut was called as `MUT="$(mutate …)"`, which runs the
# whole function in a SUBSHELL: the SKIP line went into `$MUT` instead of the log, the
# `skipped` increment was lost with the subshell, and the caller then tried to EXECUTE the
# skip message. A driver whose skip cannot be counted is exactly the vacuity this group
# exists to prevent, so the report and the counter now happen in the parent.
MUT_PATH=""
mutate() { # <name> <file> <sed-expression> -> 0 and sets MUT_PATH, or 1 having reported SKIP
  local name="$1" file="$2" expr="$3" anchors
  MUT_PATH=""
  anchors="$(grep -cE "^REPLY_ELEMENT_CEILING=[0-9]+\$" "$file" || true)"
  if [ "$anchors" != 1 ]; then
    printf '  SKIP  %-62s (anchor matched %s times, not once)\n' "$name" "$anchors"
    skipped=$((skipped+1)); return 1
  fi
  MUT_PATH="$TMP/mutant-$RANDOM.sh"
  sed -e "$expr" "$file" > "$MUT_PATH"; chmod +x "$MUT_PATH"
  return 0
}

# THE SKIP PATH IS ITSELF DRIVEN, because a skip branch nobody runs is untested code inside
# the guard against untested code. It runs against a copy with the constant DELETED, in a
# subshell so the real counters stay untouched — and the assertion reads the counter's value
# out of that subshell, which is what the defect above made impossible.
grep -v '^REPLY_ELEMENT_CEILING=' "$SCRIPT" > "$TMP/no-anchor.sh"
probe="$( skipped=0
          mutate "probe: an absent anchor" "$TMP/no-anchor.sh" 's/a/b/' >/dev/null 2>&1
          printf 'rc=%s skipped=%s\n' "$?" "$skipped" )"
ok "an absent anchor returns 1 AND counts a skip" "$probe" "rc=1 skipped=1"
probe_out="$( skipped=0; mutate "probe: an absent anchor" "$TMP/no-anchor.sh" 's/a/b/' 2>&1 )"
ok "…and the SKIP line goes to the log, not into a variable" \
   "$(printf '%s' "$probe_out" | grep -c '^  SKIP  probe: an absent anchor')" 1
ok "…and the intact script does have exactly one anchor" \
   "$(grep -cE '^REPLY_ELEMENT_CEILING=[0-9]+$' "$SCRIPT" || true)" 1

MUT_HIGH=""
mutate "mutant: the ceiling raised to 100000" "$SCRIPT" \
  's/^REPLY_ELEMENT_CEILING=[0-9]*$/REPLY_ELEMENT_CEILING=100000/' && MUT_HIGH="$MUT_PATH"
if [ -n "$MUT_HIGH" ]; then
  ok "the raised mutant really changed the constant" \
     "$(grep -c '^REPLY_ELEMENT_CEILING=100000$' "$MUT_HIGH" || true)" 1
  "$MUT_HIGH" --comment-file "$DEF" >/dev/null 2>&1; rc=$?
  ok "RAISED: the ${MOTIVATING_CHARS}-character reply stops being refused" "$rc" 0
  "$MUT_HIGH" --comment-file "$(entries_reply "$SMALLEST_BLOAT")" >/dev/null 2>&1; rc=$?
  ok "RAISED: the 706-byte entry stops being refused too" "$rc" 0
fi

MUT_LOW=""
mutate "mutant: the ceiling lowered to 100" "$SCRIPT" \
  's/^REPLY_ELEMENT_CEILING=[0-9]*$/REPLY_ELEMENT_CEILING=100/' && MUT_LOW="$MUT_PATH"
if [ -n "$MUT_LOW" ]; then
  ok "the lowered mutant really changed the constant" \
     "$(grep -c '^REPLY_ELEMENT_CEILING=100$' "$MUT_LOW" || true)" 1
  "$MUT_LOW" --comment-file "$LONG" >/dev/null 2>&1; rc=$?
  ok "LOWERED: the well-shaped ${LONG_CHARS}-character reply stops clearing" "$rc" 3
  "$MUT_LOW" --comment-file "$(entries_reply "$LARGEST_ELEMENT")" >/dev/null 2>&1; rc=$?
  ok "LOWERED: the 530-byte honest element stops clearing" "$rc" 3
  # …and the CONTROL for both mutants: the intact script answers the opposite way on the
  # same four inputs, which is what makes the four assertions above about the constant.
  "$SCRIPT" --comment-file "$DEF" >/dev/null 2>&1; rc=$?
  ok "CONTROL: intact, the self-defending reply is refused" "$rc" 3
  "$SCRIPT" --comment-file "$LONG" >/dev/null 2>&1; rc=$?
  ok "CONTROL: intact, the well-shaped long reply clears" "$rc" 0
fi

# The verdict requirement gets the same treatment: delete the row that matches `fixed` and
# the conforming reply must go red, which proves the table is what cleared it.
VROW='(^|[^[:alnum:]])fixed([^[:alnum:]]|$)'
vanchors="$(grep -cF "$VROW" "$SCRIPT" || true)"
if [ "$vanchors" != 1 ]; then
  printf '  SKIP  %-62s (verdict row matched %s times, not once)\n' \
    "mutant: the 'fixed' verdict row deleted" "$vanchors"
  skipped=$((skipped+1))
else
  MUT_V="$TMP/mutant-verdict.sh"
  grep -vF "$VROW" "$SCRIPT" > "$MUT_V"; chmod +x "$MUT_V"
  "$MUT_V" --comment-file "$(entries_reply 120)" >/dev/null 2>&1; rc=$?
  ok "VERDICT ROW DELETED: a '- fixed: …' entry stops clearing" "$rc" 1
  "$SCRIPT" --comment-file "$(entries_reply 120)" >/dev/null 2>&1; rc=$?
  ok "CONTROL: intact, the same entry clears" "$rc" 0
fi

# And the narrowing gets it too, in the direction that matters: put the BARE token back —
# the row exactly as it shipped on 1.1.x — and the measured probe must stop being refused.
# This is the "assert it fails before the fix" case, kept as a mutant rather than as a
# one-off run, so the defect cannot come back quietly.
CROW='(^|[^[:alnum:]])correct([[:space:]]*[^[:alnum:][:space:]]|[[:space:]]*$)'
canchors="$(grep -cF "$CROW" "$SCRIPT" || true)"
if [ "$canchors" != 1 ]; then
  printf '  SKIP  %-62s (narrowed row matched %s times, not once)\n' \
    "mutant: the bare 'correct' token restored" "$canchors"
  skipped=$((skipped+1))
else
  MUT_C="$TMP/mutant-correct.sh"
  awk -v old="$CROW" -v new='(^|[^[:alnum:]])correct([^[:alnum:]]|$)' \
      'index($0, old) { print new; next } { print }' "$SCRIPT" > "$MUT_C"
  chmod +x "$MUT_C"
  ok "the mutant really restored the bare token" \
     "$(grep -cF '(^|[^[:alnum:]])correct([^[:alnum:]]|$)' "$MUT_C" || true)" 1
  ADJ_ONE="$(reply_file 'Round 1 addressed.' '' \
     '- Finding 1 — the correct fix would be to quote the path, but I have not done it.')"
  "$MUT_C" --comment-file "$ADJ_ONE" >/dev/null 2>&1; rc=$?
  ok "BARE TOKEN: the adjectival entry CLEARS — the 1.1.x defect, reproduced" "$rc" 0
  "$SCRIPT" --comment-file "$ADJ_ONE" >/dev/null 2>&1; rc=$?
  ok "CONTROL: intact, the same entry is refused" "$rc" 1
  # On the two-entry probe the mutant still refuses — for entry 2 only, which is exactly
  # what the measurement reported and why the defect was invisible behind a non-zero exit.
  mout="$("$MUT_C" --comment-file "$ADJ" 2>&1)"
  ok "BARE TOKEN: it names entry 2…" "$(printf '%s' "$mout" | grep -c 'entry 2 ' || true)" 1
  ok "…and NOT entry 1"              "$(printf '%s' "$mout" | grep -c 'entry 1 ' || true)" 0
  "$SCRIPT" --comment-file "$(reply_file 'Round 1 addressed.' '' \
     '- `run.sh:42` — correct: the path is quoted now.')" >/dev/null 2>&1; rc=$?
  ok "CONTROL: intact, the STANDING verdict still clears" "$rc" 0
fi

echo
printf 'pass=%d fail=%d skipped=%d\n' "$pass" "$fail" "$skipped"
# A SKIP is as red as a failure here: it means a mutant never applied, and a mutant that
# never applied proves nothing about the assertion it was written to protect.
[ "$fail" -eq 0 ] && [ "$skipped" -eq 0 ]
