#!/usr/bin/env bash
#
# papercuts-upstream.test.sh — a papercut pass completes when its proposals target loopd
# plugin surfaces: the classifier resolves names, the writers refuse an empty edit, `pass`
# is held until each plugin surface has an upstream row, and the three sites state one rule.
#
# ok() follows this directory's convention: it compares actual to expected.
# Reasoning: kb-retrieval-and-papercut-fixes/task-001.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PC="$REPO/plugin/scripts/papercuts.sh"
VALIDATOR="$REPO/plugin/scripts/validate-bundle.sh"
SKILL="$REPO/plugin/skills/close-project/SKILL.md"
SITES="$REPO/plugin/tick-steps/step-7-knowledge-base.md
$REPO/plugin/agents/cataloguer.md $SKILL"
[ -x "$PC" ] || { echo "papercuts-upstream.test: missing or not executable: $PC" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/papercuts-up.XXXXXX")" \
  || { echo "papercuts-upstream.test: could not create a temp dir" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
export CLAUDE_PLUGIN_ROOT="$REPO/plugin"

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-60s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-60s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }
rc() { "$@" >/dev/null 2>&1; echo $?; }
up() { bash "$PC" "$@" --date 2026-09-05; }
on() { local d="$1"; shift; bash "$PC" "$@" --date "$d"; }
offshape() { awk '/^## Entries/{f=1;next} f&&NF' "$1" \
  | grep -cvE '^[0-9]{4}-[0-9]{2}-[0-9]{2} \| (skill|agent|script):[^|]+ \| (proposal|dismissed|in-progress|done) \| .+$'; }

echo "== 1. the classifier resolves the name in the installed plugin; the prefix never decides =="
for row in script:validate-bundle.sh=plugin script:deny-destructive.sh=plugin script:package.json=instance agent:project-manager=plugin \
           skill:close-project=plugin agent:no-such-agent=instance skill:no-such-skill=instance \
           script:../scripts/papercuts.sh=instance; do
  ok "${row%=*}" "$(bash "$PC" classify --surface "${row%=*}")" "${row#*=}"
done
BARE="$TMP/bare"; mkdir -p "$BARE/scripts" && cp "$REPO/plugin/VERSION" "$BARE/"
cp "$PC" "$REPO/plugin/scripts/bundle-paths.sh" "$BARE/scripts/"
ok "a plugin without the file calls the same name instance" \
  "$(CLAUDE_PLUGIN_ROOT="$BARE" bash "$BARE/scripts/papercuts.sh" classify --surface script:validate-bundle.sh)" instance

mkdir -p "$TMP/link/loopd" && ln -s "$REPO/plugin/scripts" "$TMP/link/loopd/bin"
ok "through a linked scripts dir, with no CLAUDE_PLUGIN_ROOT" \
  "$(env -u CLAUDE_PLUGIN_ROOT bash "$TMP/link/loopd/bin/papercuts.sh" classify --surface script:validate-bundle.sh)" plugin
mkdir -p "$TMP/l2" && ln -s "$TMP/link/loopd/bin" "$TMP/l2/loopd"
ok "through a two-hop link, with no CLAUDE_PLUGIN_ROOT" \
  "$(env -u CLAUDE_PLUGIN_ROOT bash "$TMP/l2/loopd/papercuts.sh" classify --surface script:validate-bundle.sh)" plugin
ok "…and with the matching CLAUDE_PLUGIN_ROOT" \
  "$(bash "$TMP/l2/loopd/papercuts.sh" classify --surface script:validate-bundle.sh)" plugin
ok "a foreign CLAUDE_PLUGIN_ROOT is refused, not read as instance" \
  "$(CLAUDE_PLUGIN_ROOT="$REPO/plugin-yolo" rc bash "$PC" classify --surface script:validate-bundle.sh)" 2
ok "a stale CLAUDE_PLUGIN_ROOT (another plugin copy) is refused" \
  "$(CLAUDE_PLUGIN_ROOT="$BARE" rc bash "$PC" classify --surface script:validate-bundle.sh)" 2
mkdir -p "$TMP/loose" && cp "$PC" "$REPO/plugin/scripts/bundle-paths.sh" "$TMP/loose/"
ok "a copy outside any plugin root is refused" \
  "$(rc env -u CLAUDE_PLUGIN_ROOT bash "$TMP/loose/papercuts.sh" classify --surface script:validate-bundle.sh)" 2

echo
echo "== 2. a fixture bundle whose proposals all target plugin surfaces =="
B="$TMP/bundle"; mkdir -p "$B/knowledge" "$B/projects" && cd "$B" || exit 2
echo '{ "org": "x", "reposRoot": "/tmp" }' > instance.config.json
REC="knowledge/papercuts.md"; UP=".loopd/upstream-proposals.md"
bash "$PC" add --task p/t-1 --surface script:validate-bundle.sh --note 'exits 0 on an unreadable file' --date 2026-09-01 >/dev/null
bash "$PC" add --task p/t-2 --surface agent:project-manager --note 'drafts nothing for a plugin surface' --date 2026-09-02 >/dev/null
printf '2026-09-02 | p/t-3 | rule:no-such-kind | a hand-written line the shape refuses\n' >> "$REC"

ok "pass under a foreign root exits 2"  "$(CLAUDE_PLUGIN_ROOT="$REPO/plugin-yolo" rc up pass)" 2
ok "pass under a stale root exits 2"    "$(CLAUDE_PLUGIN_ROOT="$BARE" rc up pass)" 2
ok "…through a copy outside a plugin"   "$(rc env -u CLAUDE_PLUGIN_ROOT bash "$TMP/loose/papercuts.sh" pass --date 2026-09-05)" 2
err="$(up pass 2>&1 >/dev/null)"; code=$?
ok "pass is refused with two pending plugin surfaces"     "$code" 1
ok "…writes no marker"                                    "$(grep -c '<!-- pass' "$REC")" 0
ok "…and names both surfaces" \
  "$(grep -c 'script:validate-bundle.sh' <<<"$err")$(grep -c 'agent:project-manager' <<<"$err")" 11
ok "report counts the malformed line on its own figure"  "$(bash "$PC" report | grep -c '2 entries · 2 surfaces · 1 malformed')" 1
ok "…and never classifies it"                             "$(bash "$PC" report | grep -c 'rule:')" 0

echo
echo "== 3. the writers refuse an empty edit, and write nothing =="
ok "propose with no --edit"                 "$(rc up propose --surface script:validate-bundle.sh)" 1
ok "propose with an empty --edit"           "$(rc up propose --surface script:validate-bundle.sh --edit '  ')" 1
ok "dismiss with no --reason"               "$(rc up dismiss --surface agent:project-manager)" 1
ok "dismiss with an empty --reason"         "$(rc up dismiss --surface agent:project-manager --reason '')" 1
ok "propose for an instance-owned surface"  "$(rc up propose --surface script:package.json --edit 'add a lint script')" 1
ok "dismiss for an instance-owned surface"  "$(rc up dismiss --surface script:package.json --reason 'not ours')" 1
ok "propose with a \"|\" in --edit"          "$(rc up propose --surface script:validate-bundle.sh --edit 'a | b')" 1
ok "propose with only a no-break space, C locale" \
  "$(LC_ALL=C rc up propose --surface script:validate-bundle.sh --edit $' \xc2\xa0 ')" 1
ok "dismiss with an impossible --date"      "$(rc bash "$PC" dismiss --surface agent:project-manager --reason x --date 2099-99-99)" 2
ok "dismiss with a future --date"           "$(rc bash "$PC" dismiss --surface agent:project-manager --reason x --date 2099-01-01)" 1
ok "propose with a future --date"           "$(rc bash "$PC" propose --surface agent:project-manager --edit x --date 2099-01-01)" 1
ok "propose under a foreign root"           "$(CLAUDE_PLUGIN_ROOT="$REPO/plugin-yolo" rc up propose --surface script:validate-bundle.sh --edit x)" 2
ok "…no refusal created the upstream file"  "$(yn test -e "$UP")" no
ok "…and pass is still refused"             "$(rc up pass)" 1

echo
echo "== 4. pass only after the write =="
ok "a proposal row is written"              "$(rc up propose --surface script:validate-bundle.sh --edit 'line 41: exit 2 when a ref is unreadable')" 0
err="$(up pass 2>&1 >/dev/null)"; code=$?
ok "…pass is still refused for the other"   "$code" 1
ok "…naming only that one" \
  "$(grep -c 'agent:project-manager' <<<"$err")$(grep -c 'script:validate-bundle.sh' <<<"$err")" 10
ok "a row dated BEFORE the entry does not count" \
  "$(bash "$PC" dismiss --surface agent:project-manager --reason 'an old dismissal' --date 2026-09-01 >/dev/null 2>&1; rc up pass)" 1
printf '2099-01-01 | agent:project-manager | dismissed | a hand-written future row\n2026-09-05 | agent:project-manager | dismissed | a CRLF row above the heading\r\n' > "$TMP/up.head"
cp "$UP" "$TMP/up.keep"; { cat "$TMP/up.head"; cat "$TMP/up.keep"; } > "$UP"
ok "rows above ## Entries do not count"     "$(rc up pass)" 1
printf '2099-01-01 | agent:project-manager | dismissed | a hand-written future row\n' >> "$UP"
ok "a row dated after the pass does not count" "$(rc up pass)" 1
cp "$TMP/up.keep" "$UP"
ok "a dismissed row is written"             "$(rc up dismiss --surface agent:project-manager --reason 'no longer reproduces on 3.12')" 0
ok "…and now pass marks the record"         "$(rc up pass)" 0
ok "the marker carries the malformed figure" \
  "$(grep -c '^<!-- pass 2026-09-05 — 2 entries, 2 surfaces, 1 malformed -->$' "$REC")" 1
ok "every upstream row has the SCHEMA shape" "$(offshape "$UP")" 0
ok "…three rows, appended" \
  "$(grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2} \|' "$UP")" 3
ok "validate-bundle.sh reports 0 errors on the bundle holding it" \
  "$(bash "$VALIDATOR" 2>&1 | grep -cE '^[[:space:]]*ERROR')" 0
ok "…and exits 0"                           "$(rc bash "$VALIDATOR")" 0

echo
echo "== 5. a malformed or instance-only record neither blocks nor needs the file =="
M="$TMP/malformed"; mkdir -p "$M/knowledge" && cd "$M" || exit 2
printf '# Papercuts\n\n## Entries\n\n2026-09-02 | p/t | rule:x | a malformed line on its own here\n' > "$REC"
ok "one malformed line: pass is not refused" "$(rc up pass)" 0
ok "…and the marker says 1 malformed"        "$(grep -c '0 entries, 0 surfaces, 1 malformed' "$REC")" 1
bash "$PC" add --task p/t --surface script:package.json --note 'an instance surface papercut' --date 2026-09-06 >/dev/null
ok "an instance-only entry: pass is not refused" "$(rc bash "$PC" pass --date 2026-09-07)" 0
ok "…and no upstream file was needed"        "$(yn test -e "$UP")" no

echo
echo "== 6. one rule, three sites — step 7 carries the tick's copy, the core prompt none =="
norm() { tr '\n' ' ' < "$1" | tr -s ' '; }
RULE='an instance-owned surface becomes a `draft` task in its owning project; a loopd plugin surface is written to `.loopd/upstream-proposals.md` instead'
SIDE='`pass` checks only the plugin side; the drafts are'
states() { local t; t="$(norm "$1")"; grep -qF "$RULE" <<<"$t" && grep -qF "$SIDE" <<<"$t"; }
for f in $SITES; do ok "${f#"$REPO"/} states the rule" "$(yn states "$f")" yes; done
ok "plugin/agents/project-manager.md leaves it to step 7 (no second copy)" \
   "$(yn states "$REPO/plugin/agents/project-manager.md")" no
sed 's/a loopd plugin surface is written/a plugin surface goes/' "$SKILL" > "$TMP/dropped.md"
ok "…and a site that drops it fails the row"   "$(yn states "$TMP/dropped.md")" no
ok "close-project names the refused-pass branch" \
  "$(norm "$SKILL" | grep -cF 'If `pass` exits 1, closeout continues without a marker')" 1
ok "…logs the refused surfaces"               "$(norm "$SKILL" | grep -cF '`papercuts pass refused: <surfaces>`')" 1
ok "…and calls the writers in the granted form" \
  "$(grep -cE '^   \$\{CLAUDE_PLUGIN_ROOT\}/scripts/papercuts\.sh (propose|dismiss) ' "$SKILL")" 2
ok "the path is one constant in bundle-paths.sh" \
  "$("$REPO/plugin/scripts/bundle-paths.sh" AB_UPSTREAM)" .loopd/upstream-proposals.md
ok "SCHEMA.md defines the four row shapes" \
  "$(grep -cE '^DATE \| KIND:NAME \| (proposal \| <concrete edit>|dismissed \| <reason>|(in-progress|done) \| <ref> \(proposed <YYYY-MM-DD>\))$' "$REPO/plugin/seed/SCHEMA.md")" 4
ok "…and names the four writers" \
  "$(norm "$REPO/plugin/seed/SCHEMA.md" | grep -cF '`papercuts.sh propose`, `dismiss`, `progress` and `resolve` are the only writers')" 1
ok "…and who runs progress and resolve" \
  "$(norm "$REPO/plugin/seed/SCHEMA.md" | grep -cF 'the human, or the session that files the fix, runs')" 1

echo
echo "== 7. progress and resolve append one row, and never touch an earlier line =="
A=script:validate-bundle.sh; G=agent:project-manager; C=skill:close-project; E=agent:cataloguer; F=script:papercuts.sh
S="$TMP/status"; mkdir -p "$S/knowledge" && cd "$S" || exit 2
echo '{ "org": "x", "reposRoot": "/tmp" }' > instance.config.json
kept() { head -c "$(wc -c < "$TMP/st.keep" | tr -d ' ')" "$UP" | cmp -s - "$TMP/st.keep"; }
sum() { cksum < "$UP"; }
ok "proposals with no file says so"         "$(bash "$PC" proposals)" "papercuts: no upstream proposals"
ok "…and exits 0"                           "$(rc bash "$PC" proposals)" 0
ok "progress with no file is refused"       "$(rc on 2026-09-02 progress --surface $A --ref 'https://example.com/pull/1')" 1
ok "…and creates none"                      "$(yn test -e "$UP")" no
on 2026-09-01 propose --surface $A --edit 'line 41: exit 2 when a ref is unreadable' >/dev/null
ok "the header names the four shapes" \
  "$(sed '/^## Entries/q' "$UP" | grep -oE '\| (proposal|dismissed|in-progress|done) \|' | sort -u | grep -c .)" 4
ok "…the four writers" \
  "$(grep -cF 'Append with `papercuts.sh propose` / `dismiss` / `progress` / `resolve`' "$UP")" 1
ok "…and who runs progress and resolve" \
  "$(grep -cF 'The human or the session that files the fix runs `progress` and `resolve`, and commits this file.' "$UP")" 1
cp "$UP" "$TMP/st.keep"
ok "progress appends"                       "$(rc on 2026-09-03 progress --surface $A --ref 'https://example.com/pull/1')" 0
ok "…the in-progress row, naming the one proposal's date" \
  "$(tail -1 "$UP")" "2026-09-03 | $A | in-progress | https://example.com/pull/1 (proposed 2026-09-01)"
ok "…earlier lines byte-identical"          "$(yn kept)" yes
cp "$UP" "$TMP/st.keep"
ok "resolve appends"                        "$(rc on 2026-09-04 resolve --surface $A --ref 'https://example.com/pull/1')" 0
ok "…the done row" \
  "$(tail -1 "$UP")" "2026-09-04 | $A | done | https://example.com/pull/1 (proposed 2026-09-01)"
ok "…earlier lines byte-identical"          "$(yn kept)" yes
on 2026-09-01 propose --surface $G --edit 'draft a row for a plugin surface' >/dev/null
ok "resolve with no progress is allowed"    "$(rc on 2026-09-02 resolve --surface $G --ref 'https://example.com/pull/2')" 0
printf '2026-09-01 | script:retired-name.sh | proposal | an edit for a surface the fix later removed\n' >> "$UP"
ok "a surface the plugin no longer holds"   "$(bash "$PC" classify --surface script:retired-name.sh)" instance
ok "…still resolves on its proposal row"    "$(rc on 2026-09-02 resolve --surface script:retired-name.sh --ref 'https://example.com/pull/3')" 0
ok "…and progress needs no plugin root"     "$(CLAUDE_PLUGIN_ROOT="$BARE" rc on 2026-09-02 progress --surface $C --ref x)" 1

echo
echo "== 8. progress and resolve refuse, and write nothing =="
on 2026-09-01 propose --surface $E --edit 'state the absence of a tool' >/dev/null
before="$(sum)"
for v in progress resolve; do
  ok "$v for a surface with no proposal row" "$(rc on 2026-09-02 $v --surface $C --ref 'https://example.com/pull/4')" 1
  ok "$v with no --ref"                      "$(rc on 2026-09-02 $v --surface $E)" 1
  ok "$v with an empty --ref"                "$(rc on 2026-09-02 $v --surface $E --ref '  ')" 1
  ok "$v with a --ref spanning lines"        "$(rc on 2026-09-02 $v --surface $E --ref $'a\nb')" 1
  ok "$v with a \"|\" in --ref"               "$(rc on 2026-09-02 $v --surface $E --ref 'a | b')" 1
  ok "$v with a future --date"               "$(rc on 2099-01-01 $v --surface $E --ref 'https://example.com/pull/4')" 1
  ok "$v dated before its proposal"          "$(rc on 2026-08-31 $v --surface $E --ref 'https://example.com/pull/4')" 1
  ok "$v after a done row"                   "$(rc on 2026-09-05 $v --surface $A --ref 'https://example.com/pull/5')" 1
  ok "$v with a malformed --proposed"        "$(rc on 2026-09-02 $v --surface $E --ref x --proposed 20260901)" 2
done
ok "…none of them wrote a byte"             "$(sum)" "$before"

echo
echo "== 9. two proposals on one surface are told apart by proposal date =="
on 2026-09-01 propose --surface $C --edit 'name the refused-pass branch' >/dev/null
on 2026-09-02 propose --surface $C --edit 'log the refused surfaces' >/dev/null
before="$(sum)"
err="$(on 2026-09-03 progress --surface $C --ref 'https://example.com/pull/6' 2>&1 >/dev/null)"; code=$?
ok "progress without --proposed is refused" "$code" 1
ok "…listing both dates"                    "$(grep -c '2026-09-01 2026-09-02' <<<"$err")" 1
err="$(on 2026-09-03 progress --surface $C --ref 'https://example.com/pull/6' --proposed 2026-09-03 2>&1 >/dev/null)"; code=$?
ok "a --proposed naming no proposal is refused" "$code" 1
ok "…listing both dates"                    "$(grep -c '2026-09-01 2026-09-02' <<<"$err")" 1
ok "…neither wrote a byte"                  "$(sum)" "$before"
ok "--proposed names which"                 "$(rc on 2026-09-03 progress --surface $C --ref 'https://example.com/pull/6' --proposed 2026-09-02)" 0
ok "…and the row carries that date" \
  "$(tail -1 "$UP")" "2026-09-03 | $C | in-progress | https://example.com/pull/6 (proposed 2026-09-02)"
ok "a backdated progress is accepted"       "$(rc on 2026-09-02 progress --surface $C --ref 'https://example.com/pull/7' --proposed 2026-09-02)" 0

echo
echo "== 10. a second same-day proposal is kept; dismiss --proposed closes a filed one =="
ok "propose accepts a first on a day"       "$(rc on 2026-09-01 propose --surface $F --edit 'the first pass edit')" 0
ok "…and a second on that surface and day"  "$(rc on 2026-09-01 propose --surface $F --edit 'the second pass edit')" 0
ok "progress then wants --proposed"         "$(rc on 2026-09-02 progress --surface $F --ref 'https://example.com/pull/8')" 1
ok "…and with it moves the later one"       "$(rc on 2026-09-02 progress --surface $F --ref 'https://example.com/pull/8' --proposed 2026-09-01)" 0
ok "dismiss --proposed with a wrong date"   "$(rc on 2026-09-03 dismiss --surface $E --reason 'declined upstream' --proposed 2026-08-01)" 1
ok "dismiss --proposed closes the proposal" "$(rc on 2026-09-03 dismiss --surface $E --reason 'declined upstream' --proposed 2026-09-01)" 0
ok "…as a dismissed row naming it" \
  "$(tail -1 "$UP")" "2026-09-03 | $E | dismissed | declined upstream (proposed 2026-09-01)"
before="$(sum)"
ok "progress after a dismissed row"         "$(rc on 2026-09-04 progress --surface $E --ref 'https://example.com/pull/9')" 1
ok "resolve after a dismissed row"          "$(rc on 2026-09-04 resolve --surface $E --ref 'https://example.com/pull/9')" 1
ok "a bare dismiss whose reason forges the marker" \
  "$(rc on 2026-09-04 dismiss --surface $E --reason 'declined (proposed 2026-09-01)')" 1
ok "…none of them wrote a byte"             "$(sum)" "$before"
ok "a bare dismiss is still written"        "$(rc on 2026-09-04 dismiss --surface $E --reason 'no longer reproduces on 3.12')" 0
ok "every row has one of the four shapes"   "$(offshape "$UP")" 0

echo
echo "== 11. proposals groups each proposal once, by its latest line in file order =="
out="$(on 2026-09-05 proposals)"
grp() { awk -v g="$1" '$0 ~ "^" g "  [(]" { f = 1; next } /^$/ { f = 0 } f' <<<"$out"; }
ok "proposals exits 0"                      "$(rc on 2026-09-05 proposals)" 0
ok "the header counts entries, surfaces and malformed" "$(head -1 <<<"$out")" "== 9 entries · 6 surfaces · 0 malformed"
ok "…and every entry is printed once"       "$(grep -c '^  ' <<<"$out")" 9
ok "pending: the earlier of two dates, and the first of a same-day pair" "$(grp pending)" \
"  $C  proposed 2026-09-01  latest 2026-09-01  name the refused-pass branch
  $F  proposed 2026-09-01  latest 2026-09-01  the first pass edit"
ok "in progress: the last appended row wins over a later date" "$(grp 'in progress')" \
"  $C  proposed 2026-09-02  latest 2026-09-02  https://example.com/pull/7
  $F  proposed 2026-09-01  latest 2026-09-02  https://example.com/pull/8"
ok "done: with and without a progress row" "$(grp done)" \
"  $A  proposed 2026-09-01  latest 2026-09-04  https://example.com/pull/1
  $G  proposed 2026-09-01  latest 2026-09-02  https://example.com/pull/2
  script:retired-name.sh  proposed 2026-09-01  latest 2026-09-02  https://example.com/pull/3"
ok "dismissed: the closed proposal, and the bare row as its own entry" "$(grp dismissed)" \
"  $E  proposed 2026-09-01  latest 2026-09-03  declined upstream
  $E  proposed -  latest 2026-09-04  no longer reproduces on 3.12"
cp "$UP" "$TMP/st.keep"
{ printf '2026-09-01 | %s | proposal | a row above the heading\n' "$G"; cat "$TMP/st.keep"
  printf '2099-01-01 | %s | proposal | a hand-written future row\n' "$G"
  printf '2026-09-02 | rule:x | proposal | not a surface kind\n'
  printf '2026-09-02 | %s | wontfix | not a row kind\n' "$G"
  printf '2026-09-02 | %s | done | a ref | with a fifth field (proposed 2026-09-01)\n' "$G"
  printf '2026-09-02 | %s | in-progress | a ref naming no proposal date\n' "$G"
  printf '2026-09-02 | %s | done | an orphan ref (proposed 2020-01-01)\n' "$G"; } > "$UP"
out="$(on 2026-09-05 proposals)"
ok "future, malformed and orphan rows are counted, rows above ## Entries are not" \
  "$(head -1 <<<"$out")" "== 9 entries · 6 surfaces · 6 malformed"
ok "…and it still exits 0"                  "$(rc on 2026-09-05 proposals)" 0
ok "…with the same nine entries"            "$(grep -c '^  ' <<<"$out")" 9
ok "a row dated after --date is malformed as of that day" \
  "$(on 2026-09-03 proposals | head -1)" "== 8 entries · 6 surfaces · 8 malformed"
printf '# Upstream proposals\n\n## Entries\n\n' > "$UP"
ok "a file with no rows"                    "$(bash "$PC" proposals)" "papercuts: no upstream proposals, 0 malformed"

echo
echo "== 12. a file written under the old header still parses, and is never rewritten =="
O="$TMP/old"; mkdir -p "$O/knowledge" "$O/.loopd" && cd "$O" || exit 2
echo '{ "org": "x", "reposRoot": "/tmp" }' > instance.config.json
printf '# Upstream proposals\n\nPapercut proposals for loopd plugin surfaces, for the plugin repo to act on.\nOne line: `DATE | KIND:NAME | proposal | <concrete edit>` or `DATE | KIND:NAME | dismissed | <reason>`.\nAppend with `papercuts.sh propose` / `dismiss`; never edit or delete a line.\n\n## Entries\n\n2026-09-01 | %s | proposal | an edit filed under the old header\n2026-09-01 | %s | dismissed | a dismissal filed under the old header\n' "$A" "$G" > "$UP"
cp "$UP" "$TMP/st.keep"
ok "progress appends to it"                 "$(rc on 2026-09-02 progress --surface $A --ref 'https://example.com/pull/1')" 0
ok "propose appends to it"                  "$(rc on 2026-09-02 propose --surface $G --edit 'a later edit')" 0
ok "…the old header and rows byte-identical" "$(yn kept)" yes
ok "…and proposals reads all three entries" \
  "$(on 2026-09-05 proposals | grep -cE '^(== 3 entries · 2 surfaces · 0 malformed|pending  \(1\)|in progress  \(1\)|dismissed  \(1\))$')" 4

echo
echo "== 13. in-progress, done and dismiss --proposed rows neither hold nor release pass =="
H="$TMP/held"; mkdir -p "$H/knowledge" && cd "$H" || exit 2
echo '{ "org": "x", "reposRoot": "/tmp" }' > instance.config.json
for s in $A $G; do
  on 2026-09-01 propose --surface $s --edit 'an edit filed before the papercut' >/dev/null
  on 2026-09-03 add --task p/t-1 --surface $s --note 'a papercut logged after the proposal' >/dev/null
done
on 2026-09-04 progress --surface $A --ref 'https://example.com/pull/1' >/dev/null
on 2026-09-04 resolve --surface $A --ref 'https://example.com/pull/1' >/dev/null
on 2026-09-04 dismiss --surface $G --reason 'declined upstream' --proposed 2026-09-01 >/dev/null
err="$(up pass 2>&1 >/dev/null)"; code=$?
ok "pass is still refused"                  "$code" 1
ok "…naming both surfaces"                  "$(grep -c "$A" <<<"$err")$(grep -c "$G" <<<"$err")" 11
on 2026-09-04 propose --surface $A --edit 'an edit for the new papercut' >/dev/null
on 2026-09-04 dismiss --surface $G --reason 'the new papercut does not reproduce' >/dev/null
ok "a proposal and a bare dismissal release it, the other rows in place" "$(rc up pass)" 0

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
