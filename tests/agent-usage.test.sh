#!/usr/bin/env bash
#
# agent-usage.test.sh — what the harness handed back, recorded on the ledger and on the
# task: `plugin/scripts/agent-usage.sh` and `tick-delta.sh record --close`.
#
# THE PROPERTIES, and each is asserted from both sides:
#   * THE OPEN LINE SURVIVES. A close is an APPEND beside it, so every tick leaves a pair
#     at one timestamp and the wall duration is derivable from the pair alone. The
#     already-closed entries of an old ledger come out byte-for-byte unchanged.
#   * A SECOND CLOSE, OR A SECOND TOTAL, IS REFUSED — never a double-write, because a
#     ledger anyone may re-run is a ledger nobody can sum.
#   * NOTHING IS MEASURED AS ZERO. Absent numbers are `usage UNKNOWN`; a task nobody
#     measured and a task that cost nothing are different facts.
#   * OFFLINE, PROVEN, NOT ASSERTED: `gh` and `git` are PATH stubs that fail loudly and
#     leave a sentinel, so a call is a failure and an absence is evidence.
#   * TOKENS, NEVER MONEY — no USD figure, price table or pricing source anywhere in the
#     feature's own files, and no transcript path either.
# Fixtures live under mktemp; no real instance is touched. ok() compares actual to
# expected, this directory's convention.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# The fixture ledgers are built from the resolver, never from a root path.
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$(dirname "$0")/../plugin/scripts/bundle-paths.sh"
AU="$REPO/plugin/scripts/agent-usage.sh"
TD="$REPO/plugin/scripts/tick-delta.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/agentusage.XXXXXX")" || {
  echo "agent-usage.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

has() { grep -qF -- "$2" "$1" && echo yes || echo no; }
count() { grep -cF -- "$2" "$1" | tr -d ' '; }

# The offline proof: a `gh`/`git` that can only ever be caught. SENTINEL survives the
# call, so "it worked" and "it never asked" are two separate assertions.
BIN="$TMP/bin"; mkdir -p "$BIN"
for t in gh git; do
  cat > "$BIN/$t" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$0" >> "$SENTINEL"
exit 99
EOS
  chmod +x "$BIN/$t"
done
SENTINEL="$TMP/network-was-touched"
OFFLINE() { SENTINEL="$SENTINEL" PATH="$BIN:$PATH" "$@"; }

# ------------------------------------------------------------------ the fixture ledger
INST="$TMP/inst"; mkdir -p "$INST/projects/proj-a/tasks" "$INST/$AB_DIR"
LOG="$INST/$AB_LEDGER"
cat > "$LOG" <<'EOF'
# Log

## 2026-08-30 — a dated section nothing here may touch

* TICK 2026-08-02T09:00:00Z close: an entry closed the OLD way, with no open line left
* TICK 2026-08-15T11:11:11Z by cbmono idle — fingerprint unchanged (tick-delta)
* TICK 2026-09-13T08:24:17Z by cbmono open: dispatch ready tasks
EOF
cp "$LOG" "$TMP/log.before"

echo "== the close is an APPEND, and the open line survives it =="
out="$("$TD" record --instance "$INST" --close "dispatched task-004; reflected task-002 merged" \
        --tokens 412345 --tools 137 --duration-ms 1084221 2>&1)"; rc=$?
ok "record --close exits 0"                      "$rc" 0
ok "…and says which entry it closed"            "$out" "closed: 2026-09-13T08:24:17Z"
ok "the open line is STILL THERE"                 "$(has "$LOG" '* TICK 2026-09-13T08:24:17Z by cbmono open: dispatch ready tasks')" yes
ok "…with a close line at the SAME timestamp"   "$(has "$LOG" '* TICK 2026-09-13T08:24:17Z by cbmono close: ')" yes
ok "…carrying the three numbers, one fixed form" "$(has "$LOG" 'close: dispatched task-004; reflected task-002 merged · usage tokens=412345 tools=137 ms=1084221')" yes
ok "…appended BESIDE the open line, adjacent"   "$(awk '/open: dispatch ready tasks/{n=NR} /close: dispatched task-004/{c=NR} END{print c-n}' "$LOG")" 1
ok "the pair is one line longer than before"      "$(( $(wc -l < "$LOG") - $(wc -l < "$TMP/log.before") ))" 1
ok "every pre-existing line is byte-identical"    "$(grep -vF 'close: dispatched task-004' "$LOG" | diff -q - "$TMP/log.before" >/dev/null && echo yes || echo no)" yes

echo "== a second close for one tick does not double-write =="
cp "$LOG" "$TMP/log.closed"
out="$("$TD" record --instance "$INST" --close "a second summary" --tokens 1 --tools 1 --duration-ms 1 2>&1)"; rc=$?
ok "a second close is refused (exit 1)"           "$rc" 1
ok "…and names why"                             "$(printf '%s' "$out" | grep -c 'not double-writing')" 1
ok "…and the ledger is untouched"               "$(diff -q "$LOG" "$TMP/log.closed" >/dev/null && echo yes || echo no)" yes
ok "exactly one close line at that timestamp"     "$(count "$LOG" '2026-09-13T08:24:17Z by cbmono close:')" 1

echo "== record WITHOUT --close behaves exactly as today =="
printf '/.tick-state\n' > "$INST/.gitignore"
printf 'type: Project\nstatus: active\n' > "$INST/projects/proj-a/project.md"
printf 'type: Task\nstatus: ready\npr: []\n' > "$INST/projects/proj-a/tasks/t1.md"
( cd "$INST" && env -u GIT_DIR git -c user.email=t@example.com -c user.name=Test \
    -c commit.gpgsign=false -c core.hooksPath=/dev/null init -q \
  && env -u GIT_DIR git add -A \
  && env -u GIT_DIR git -c user.email=t@example.com -c user.name=Test \
       -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -qm init ) >/dev/null 2>&1
cp "$LOG" "$TMP/log.plain"
"$TD" record --instance "$INST" >/dev/null 2>&1; rc=$?
ok "a bare record still exits 0"                  "$rc" 0
ok "…writes the fingerprint"                    "$([ -f "$INST/$AB_STATE_DIR" ] && echo yes || echo no)" yes
ok "…and never touches the ledger"              "$(diff -q "$LOG" "$TMP/log.plain" >/dev/null && echo yes || echo no)" yes

echo "== a tick whose notification carried no usage still closes =="
NOUSAGE="$TMP/nousage.md"
printf '* TICK 2026-09-14T07:00:00Z by cbmono open: a tick with no numbers\n' > "$NOUSAGE"
mkdir -p "$TMP/i2/$AB_DIR"; cp "$NOUSAGE" "$TMP/i2/$AB_LEDGER"
"$TD" record --instance "$TMP/i2" --close "closed with nothing to report" >/dev/null 2>&1
ok "it closes without the three flags"            "$(has "$TMP/i2/$AB_LEDGER" 'close: closed with nothing to report')" yes
ok "…and carries no usage fragment at all"      "$(count "$TMP/i2/$AB_LEDGER" 'usage ')" 0
ok "the usage flags without --close are usage (3)" "$("$TD" record --instance "$TMP/i2" --tokens 5 >/dev/null 2>&1; echo $?)" 3

echo "== no open entry, and no path under ~ on a ledger line =="
mkdir -p "$TMP/i3/$AB_DIR"; printf '* TICK 2026-09-01T00:00:00Z close: already closed\n' > "$TMP/i3/$AB_LEDGER"
ok "nothing left open is refused (exit 1)"        "$("$TD" record --instance "$TMP/i3" --close "x" >/dev/null 2>&1; echo $?)" 1
mkdir -p "$TMP/i4/$AB_DIR"; printf '* TICK 2026-09-01T00:00:00Z by cbmono open: go\n' > "$TMP/i4/$AB_LEDGER"
cp "$TMP/i4/$AB_LEDGER" "$TMP/log.tilde"
ok "a summary naming a path under ~ is refused"   "$("$TD" record --instance "$TMP/i4" --close 'read ~/.claude/projects for the numbers' >/dev/null 2>&1; echo $?)" 1
ok "…and that ledger is untouched"              "$(diff -q "$TMP/i4/$AB_LEDGER" "$TMP/log.tilde" >/dev/null && echo yes || echo no)" yes

echo "== WHICH entry a close lands on is named, never guessed =="
mkdir -p "$TMP/i8/$AB_DIR"
{ printf '* TICK 2026-09-20T01:00:00Z by cbmono open: the first loop\n'
  printf '* TICK 2026-09-20T02:00:00Z by other open: the second loop\n'
} > "$TMP/i8/$AB_LEDGER"
cp "$TMP/i8/$AB_LEDGER" "$TMP/log.two-open"
out="$("$TD" record --instance "$TMP/i8" --close "whoever I am" 2>&1)"; rc=$?
ok "two open entries and no --tick is refused"    "$rc" 1
ok "…and names the flag that disambiguates"     "$(printf '%s' "$out" | grep -c -- '--tick')" 1
ok "…leaving both entries untouched"            "$(diff -q "$TMP/i8/$AB_LEDGER" "$TMP/log.two-open" >/dev/null && echo yes || echo no)" yes
ok "a --tick naming no open entry is refused"     "$("$TD" record --instance "$TMP/i8" --close "x" --tick 2026-09-19T00:00:00Z >/dev/null 2>&1; echo $?)" 1
"$TD" record --instance "$TMP/i8" --close "the first loop, closing its own" --tick 2026-09-20T01:00:00Z >/dev/null
ok "--tick closes the entry it NAMES"             "$(awk '/01:00:00Z by cbmono open:/{n=NR} /close: the first loop/{c=NR} END{print c-n}' "$TMP/i8/$AB_LEDGER")" 1
ok "…and the other tick is still open"          "$(count "$TMP/i8/$AB_LEDGER" '2026-09-20T02:00:00Z by other close:')" 0

echo "== --close with an empty summary is a usage error, not a fingerprint =="
mkdir -p "$TMP/i9/$AB_DIR"; printf '* TICK 2026-09-21T00:00:00Z by cbmono open: go\n' > "$TMP/i9/$AB_LEDGER"
ok "an empty --close is usage (3)"                "$("$TD" record --instance "$TMP/i9" --close "" >/dev/null 2>&1; echo $?)" 3
ok "…and no .tick-state was written"            "$([ -e "$TMP/i9/.tick-state" ] && echo yes || echo no)" no

echo "== the close path is offline: gh and git are traps =="
mkdir -p "$TMP/i5/$AB_DIR"; printf '* TICK 2026-09-02T00:00:00Z by cbmono open: go\n' > "$TMP/i5/$AB_LEDGER"
rc=$(OFFLINE "$TD" record --instance "$TMP/i5" --close "offline close" --tokens 9 --tools 9 --duration-ms 9 >/dev/null 2>&1; echo $?)
ok "it closes with gh and git trapped"            "$rc" 0
ok "…and neither was called"                    "$([ -f "$SENTINEL" ] && echo called || echo no)" no

# ------------------------------------------------------------------ the task document
echo "== one line per role dispatch, inside # Notes, appended never overwritten =="
DOC="$INST/projects/proj-a/tasks/task-001.md"
cat > "$DOC" <<'EOF'
---
type: Task
status: in-progress
---

# Context

Why this task exists.

# Notes

Refined by the PM.

# Superseded criteria

kept for reference
EOF
"$AU" dispatch "$DOC" --role software-engineer --model opus --tokens 200000 --tools 80 --duration-ms 600000 >/dev/null
"$AU" dispatch "$DOC" --role software-engineer --model opus --tokens 212345 --tools 57 --duration-ms 484221 >/dev/null
ok "two dispatches leave TWO lines"               "$(grep -c '^\* DISPATCH ' "$DOC" | tr -d ' ')" 2
ok "…the first one is not overwritten"          "$(has "$DOC" 'usage tokens=200000 tools=80 ms=600000')" yes
ok "…each names its role and model"             "$(grep -c '^\* DISPATCH .* · software-engineer · model opus · usage ' "$DOC" | tr -d ' ')" 2
ok "…written INSIDE # Notes, above the next heading" \
   "$(awk '/^# Notes$/{n=NR} /^\* DISPATCH /{d=NR} /^# Superseded/{s=NR} END{print (n<d && d<s) ? "yes" : "no"}' "$DOC")" yes
ok "…and a line names no session and no path"   "$(grep -c '^\* DISPATCH [0-9T:Z-]* · [a-z-]* · model [a-z-]* · usage tokens=[0-9]* tools=[0-9]* ms=[0-9]*$' "$DOC" | tr -d ' ')" 2

echo "== the reflect-time sum equals the dispatch lines it was built from =="
PR=https://github.com/example-org/example-repo/pull/7
"$AU" total "$DOC" --pr "$PR" >/dev/null
want="usage tokens=$((200000+212345)) tools=$((80+57)) ms=$((600000+484221))"
ok "the TOTAL line carries exactly that sum"      "$(has "$DOC" "$want")" yes
ok "…with rounds = the number of dispatch lines" "$(grep -c '^\* TOTAL .* · rounds=2 · ' "$DOC" | tr -d ' ')" 1
ok "…named against the merged PR"               "$(grep -c "^\* TOTAL .* · $PR\$" "$DOC" | tr -d ' ')" 1
cp "$DOC" "$TMP/doc.totalled"
ok "a second total is refused (exit 1)"           "$("$AU" total "$DOC" --pr "$PR" >/dev/null 2>&1; echo $?)" 1
ok "…and the document is untouched"             "$(diff -q "$DOC" "$TMP/doc.totalled" >/dev/null && echo yes || echo no)" yes

echo "== an unmeasured task is UNKNOWN, never zero =="
BARE="$INST/projects/proj-a/tasks/task-002.md"
printf -- '---\ntype: Task\n---\n\n# Notes\n\nNothing was ever dispatched here.\n' > "$BARE"
"$AU" total "$BARE" --pr "$PR" >/dev/null
ok "no dispatch lines reads UNKNOWN"              "$(grep -c '^\* TOTAL .* · rounds=0 · usage UNKNOWN · ' "$BARE" | tr -d ' ')" 1
ok "…and never tokens=0"                        "$(count "$BARE" 'tokens=0')" 0
NOTES="$INST/projects/proj-a/tasks/task-003.md"
printf -- '---\ntype: Task\n---\n\n# Context\n\nNo Notes section at all.\n' > "$NOTES"
"$AU" dispatch "$NOTES" --role qa-reviewer >/dev/null
ok "a doc with no # Notes gains one"              "$(has "$NOTES" '# Notes')" yes
ok "…and a notification with no usage is UNKNOWN" "$(grep -c '^\* DISPATCH .* · qa-reviewer · model unset · usage UNKNOWN$' "$NOTES" | tr -d ' ')" 1

# ------------------------------------------------------------------ the monthly series
echo "== the series reads the ledger and the task docs, and nothing else =="
rm -f "$SENTINEL"
series="$(OFFLINE "$AU" series --instance "$INST" 2>&1)"; rc=$?
ok "series exits 0 with gh and git trapped"       "$rc" 0
ok "…and neither was called"                    "$([ -f "$SENTINEL" ] && echo called || echo no)" no
ok "a month whose ticks carry no numbers is UNKNOWN" \
   "$(printf '%s\n' "$series" | grep -c '^2026-08 · ticks 2 (0 measured) usage UNKNOWN')" 1
ok "…and the measured month carries the sum"    \
   "$(printf '%s\n' "$series" | grep -c '^2026-09 · ticks 1 (1 measured) usage tokens=412345 tools=137 ms=1084221')" 1
ok "…with the dispatch half summed apart"       \
   "$(printf '%s\n' "$series" | grep -c "· dispatches 3 (2 measured) $want\$")" 1

echo "== a month with nothing recorded is a ROW, never a gap =="
mkdir -p "$TMP/i6/$AB_DIR"
{ printf '* TICK 2026-01-05T00:00:00Z by a close: x · usage tokens=10 tools=1 ms=100\n'
  printf '* TICK 2026-04-05T00:00:00Z by a close: y · usage tokens=20 tools=2 ms=200\n'
} > "$TMP/i6/$AB_LEDGER"
gaps="$("$AU" series --instance "$TMP/i6")"
ok "every month between the two is present"       "$(printf '%s\n' "$gaps" | wc -l | tr -d ' ')" 4
ok "…and the empty ones read UNKNOWN"           "$(printf '%s\n' "$gaps" | grep -c '^2026-0[23] · ticks 0 (0 measured) usage UNKNOWN · dispatches 0 (0 measured) usage UNKNOWN$')" 2
ok "a year boundary is counted, not wrapped"      "$(printf '* TICK 2025-12-01T00:00:00Z close: a\n* TICK 2026-01-01T00:00:00Z close: b\n' > "$TMP/i6/$AB_LEDGER"; "$AU" series --instance "$TMP/i6" | wc -l | tr -d ' ')" 2
mkdir -p "$TMP/i10/$AB_DIR"
{ printf '* TICK 2026-03-01T00:00:00Z by a open: go\n'
  printf '* TICK 2026-03-01T00:00:00Z by a close: left a task open: task-004 · usage tokens=7 tools=1 ms=9\n'
} > "$TMP/i10/$AB_LEDGER"
ok 'a close summary quoting open: still counts'  "$("$AU" series --instance "$TMP/i10" | grep -c '^2026-03 · ticks 1 (1 measured) usage tokens=7 tools=1 ms=9')" 1
mkdir -p "$TMP/i7/$AB_DIR"; : > "$TMP/i7/$AB_LEDGER"
ok "an empty ledger says UNKNOWN, not nothing"    "$("$AU" series --instance "$TMP/i7" | grep -c '^UNKNOWN — no TICK or DISPATCH lines')" 1
ok "no readable log.md is exit 2"                 "$("$AU" series --instance "$TMP/i7/nope" >/dev/null 2>&1; echo $?)" 2

echo "== tokens, never money — and no transcript on this path =="
FEATURE=("$AU" "$TD" "$REPO/plugin/agents/auditor.md")
# `cost` as a word is allowed (it names the subject); a PRICE is what may not appear.
# No `\$[0-9]` arm: these files read their own positional parameters, and a pattern that
# matches `$1` measures bash, not money.
money='USD\|EUR\|price\|pricing\|per million\|per 1M\|cents'
# `grep -c` over SEVERAL files prints `file:count`, and summing `$1` of that reads every
# line as 0 — these two were green whatever the files held. The count is the LAST field.
sumc() { awk -F: '{s+=$NF} END{print s+0}'; }
ok "no price, no currency, no pricing source"     "$(grep -ic "$money" "$AU" "$TD" | sumc)" 0
# The auditor's body STATES the prohibition, so the word appears there once, on the line
# that forbids it. Any other line carrying money vocabulary is the thing being forbidden.
AUD="$REPO/plugin/agents/auditor.md"
ok "the auditor states the prohibition"            "$(grep -c 'never convert to money, and never introduce a price table' "$AUD" | tr -d ' ')" 1
ok "…and names money nowhere else"               "$(grep -iv 'never convert to money' "$AUD" | grep -ic "$money" | tr -d ' ')" 0
ok "no transcript path on the tick path"          "$(grep -c 'claude/projects\|\.jsonl' "${FEATURE[@]}" | sumc)" 0
# The mutant: the same sum over a fixture that DOES carry a price must not read 0.
printf 'costs 5 USD\n' > "$TMP/priced.txt"; : > "$TMP/clean.txt"
ok "…and the sum does count across several files"   "$(grep -ic "$money" "$TMP/priced.txt" "$TMP/clean.txt" | sumc)" 1
ok "agent-usage.sh calls no gh"                   "$(grep -c '^[^#]*[^a-z]gh ' "$AU" | tr -d ' ')" 0
ok "…and the close path calls none either"      "$(sed -n '/--- the ledger half/,/^command -v git/p' "$TD" | grep -v '^[[:space:]]*#' | grep -c '[^a-z]gh ' | tr -d ' ')" 0

echo "== the instructions that drive it say the same thing =="
PM="$REPO/plugin/agents/project-manager.md"
ok "step 8 appends beside, never rewrites"        "$(has "$PM" 'appends its `close:` line **beside** this one')" yes
ok "step 8 closes via the script"                 "$(has "$PM" 'tick-delta.sh record --close')" yes
ok "…naming the entry it closes, not guessing"   "$(has "$PM" '--tick <the ISO timestamp of the open line you wrote')" yes
ok "the numbers are the notification's"           "$(has "$PM" '`subagent_tokens`, `tool_uses`, `duration_ms`')" yes
# The dispatch and reflect steps are their own files since ai-bridge-v3/task-024; step 8
# and the Output section stayed in the core.
ok "a dispatch is recorded per role dispatch"     "$(has "$REPO/plugin/tick-steps/step-3-dispatch.md" 'agent-usage.sh dispatch <task-path>')" yes
ok "reflect sums against the merged PR"           "$(has "$REPO/plugin/tick-steps/step-5-reflect-merges.md" 'agent-usage.sh total <task-path> --pr <merged-pr-url>')" yes
ok "the report gains at most one cost line"       "$(has "$PM" 'At most ONE cost line')" yes
ok "…and none at all on an empty tick"          "$(has "$PM" 'dispatched nothing and merged nothing prints no')" yes
ok "the audit reads the ledger offline"           "$(has "$REPO/plugin/agents/auditor.md" 'agent-usage.sh series')" yes
ok "…and converts nothing to money"             "$(has "$REPO/plugin/agents/auditor.md" 'never convert to money')" yes

# THE TICK REPORT'S FOOTER (ai-bridge-v3/task-025) — the launcher's instruction, and the
# only thing about it a harness CAN fail: its caller is a model, so nothing here can go red
# when the launcher forgets to print it. Said plainly rather than pretended otherwise.
LA="$REPO/plugin/skills/dispatch/SKILL.md"
ok "the launcher ends a tick report with the one form" "$(has "$LA" 'agent-usage.sh fmt')" yes
ok "…from this tick's notification numbers"          "$(has "$LA" '--tokens <subagent_tokens> --tools <tool_uses> --duration-ms <duration_ms>')" yes
ok "…with no model name, which has no producer"      "$(has "$LA" 'There is no model name in it')" yes
ok "…and no footer at all when it is UNKNOWN"        "$(has "$LA" '`usage UNKNOWN` ⇒ print no footer at all')" yes
ok "…on the TICK report only, never a role result"   "$(has "$LA" 'The tick report ONLY')" yes

ok "both scripts ship executable"                 "$(cd "$REPO" && git ls-files -s plugin/scripts/agent-usage.sh plugin/scripts/tick-delta.sh | awk '{print $1}' | sort -u | tr '\n' ' ')" "100755 "

printf '\npass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
