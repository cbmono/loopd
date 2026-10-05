#!/usr/bin/env bash
#
# report-clearance.sh — refuse a report that is not the three-part shape: what happened,
# what is blocking (only when something is), and a numbered `Needs you:` list. The spec,
# and what each detector does NOT catch: agents/project-manager.md → "Output".
#
#   Usage: report-clearance.sh --body-file <path|->
#          report-clearance.sh --self-test
#
#   0 clear · 1 refused (one `REFUSED <rule>: …` line each, on stdout) · 2 usage or IO
# Caller: hooks/report-shape.sh, on SubagentStop. Reasoning: dispatch-reporting-defects/task-006.
set -uo pipefail

SELFTEST_OK="report-clearance: self-test ok"
EOF_SENTINEL="#EOF: report-clearance.sh is complete to here"

usage() {
  echo "Usage: $(basename "$0") --body-file <path|->" >&2
  echo "       $(basename "$0") --self-test" >&2
  exit 2
}

check() {
  LC_ALL=C awk -v DASH="$(printf '\342\200\224')" '
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
function bare(s) {
  gsub(/\*\*|__/, "", s); s = trim(s); sub(/^#+[ \t]*/, "", s)
  while (s != "" && substr(s, 1, 1) !~ /[A-Za-z0-9]/) s = substr(s, 2)
  return tolower(s)
}
function shown(s) { gsub(/\]\([^)]*\)/, "]", s); gsub(/https?:\/\/[^ \t)]+/, "URL", s); gsub(/\*\*/, "", s); return s }
function refuse(rule, msg) { printf "REFUSED %s: %s\n", rule, msg; n_refused++ }
function sentences(s,   c, t) {
  s = shown(s); gsub(/`[^`]*`/, "CODE", s); gsub(/(e\.g|i\.e|etc|vs)\./, "x", s)
  c = 0; t = s
  while (match(t, /[.!?]+([ \t]|$)/)) { c++; t = substr(t, RSTART + RLENGTH) }
  if (trim(t) != "") c++
  return c
}
function stems(s,   n, w, i, out) {
  s = tolower(shown(s)); gsub(/[^a-z0-9]+/, " ", s); n = split(s, w, " "); out = " "
  for (i = 1; i <= n; i++)
    if (length(w[i]) >= 4 && !(w[i] in STOP)) out = out substr(w[i], 1, 5) " "
  return out
}
function overlap(a, b,   n, w, i) {
  n = split(a, w, " ")
  for (i = 1; i <= n; i++) if (index(b, " " w[i] " ")) return w[i]
  return ""
}
function referent(s, word,   t) {
  if (!match(s, "(^|[^a-z])" word "[ \t]+")) return ""
  t = substr(s, RSTART + RLENGTH)
  sub("([.,;:!?]|" DASH ").*$", "", t)
  return t
}
BEGIN {
  split("first befor after once then that this with from into your have been will when what which there their they them should would could also just only still item items step steps", sw, " ")
  for (i in sw) STOP[sw[i]] = 1
  sec = "out"; items = 0; trail = 0
}
{
  raw = $0; line = trim(raw); b = bare(line)
  if (line == "") next
  if (line ~ /^(BOARD|COST):[ \t]/) { trail = 1; next }
  if (trail) { refuse("outside", "line after the BOARD:/COST: trailer: " substr(line, 1, 60)); next }
  if (line ~ /^```/) { refuse("outside", "a code fence — a report carries no code or logs"); next }
  if (b ~ /^(blocking|blocked|blockers?)[ \t]*:/) {
    if (sec != "out") refuse("order", "Blocking: must come right after what happened, once")
    sec = "block"; blockseen = 1; rest = line; sub(/^[^:]*:[ \t]*/, "", rest); gsub(/^\*+[ \t]*/, "", rest)
    if (rest != "") block = block " " rest
    next
  }
  if (b ~ /^(needs you|what i need from you)[ \t]*:/) {
    if (sec == "needs") refuse("order", "a second Needs you: list")
    sec = "needs"; rest = b; sub(/^[^:]*:[ \t]*/, "", rest)
    if (rest != "") refuse("shape", "Needs you: carries text on its own line — put each request in a numbered item")
    next
  }
  if (sec == "needs") {
    if (match(line, /^[0-9]+\.[ \t]+/) && raw !~ /^    /) {
      num = substr(line, 1, index(line, ".") - 1) + 0
      items++
      if (num != items) refuse("shape", "Needs you item " num " where " items " was due — number the list 1, 2, 3")
      item[items] = substr(line, RLENGTH + 1)
      next
    }
    if (raw ~ /^[ \t][ \t]/ && items > 0) { item[items] = item[items] " " line; next }
    refuse("outside", "text in the Needs you list that is not a numbered item: " substr(line, 1, 60)); next
  }
  if (line ~ /^([-*+]|[0-9]+[.)])[ \t]/ || line ~ /^(#|\||>)/) {
    refuse("outside", "a list, heading, table or quote outside the Needs you list: " substr(line, 1, 60)); next
  }
  if (sec == "out") outcome = outcome " " line; else block = block " " line
}
END {
  outcome = trim(outcome); block = trim(block)
  narr = "(^|[^a-z])(i|we) (tried|considered|checked|investigated|looked|decided|chose|rejected|first)([^a-z]|$)|instead of|alternatives?([^a-z]|$)|steps taken|my reasoning|then i "
  if (outcome == "") refuse("shape", "no what-happened line before the rest")
  if (sentences(outcome) > 2 || length(shown(outcome)) > 400)
    refuse("reasoning", "what happened runs " sentences(outcome) " sentences / " length(shown(outcome)) " chars — say the outcome in at most 2 sentences and 400 chars")
  if (tolower(outcome) ~ narr) refuse("reasoning", "what happened narrates steps or alternatives")
  if (blockseen && block == "") refuse("shape", "Blocking: is empty")
  lb = tolower(block); sub(/[. ]+$/, "", lb)
  if (block != "" && lb ~ /^(nothing|none|n\/?a|-|no blockers?|nothing is blocking|not blocked|no)$/)
    refuse("shape", "Blocking: says nothing is — omit the section when nothing blocks")
  if (block != "" && (sentences(block) > 2 || length(shown(block)) > 400))
    refuse("reasoning", "Blocking: runs past 2 sentences / 400 chars")
  if (tolower(block) ~ narr) refuse("reasoning", "Blocking: narrates steps or alternatives")
  if (sec == "needs" && items == 0) refuse("shape", "Needs you: with no numbered item — omit it when nothing is needed")
  for (n = 1; n <= items; n++) {
    t = item[n]; d = shown(t); dl = tolower(d)
    if (t !~ /\]\([^) \t]+\)/ && t !~ /https?:\/\// && t !~ /`[^`]*\/[^`]*`/ && t !~ /(^|[ \t(])~?\/[A-Za-z0-9._-]/)
      refuse("item", "item " n " links no URL or path inline")
    w = d; gsub(/\*\*|__/, "", w); w = trim(w)
    while (w != "" && substr(w, 1, 1) !~ /[A-Za-z0-9`\[]/) w = substr(w, 2)
    w = tolower(w); sub(/[ \t].*$/, "", w); sub(/[,:;.]$/, "", w)
    if (w !~ /^[a-z][a-z-]*$/ || w ~ /^(the|a|an|this|that|these|those|it|its|there|here|pr|prs|task|tasks|i|we|you|your|my|our|nothing|no|none|needs|is|are|was|were|has|have|still|maybe|perhaps|optionally)$/ || (length(w) > 5 && w ~ /ing$/) || (length(w) > 5 && w ~ /ed$/ && w !~ /eed$/))
      refuse("item", "item " n " does not open with an imperative verb (\"" w "\")")
    act = dl; if ((p = index(act, " " DASH " ")) > 0) act = substr(act, 1, p); if ((p = index(act, " -- ")) > 0) act = substr(act, 1, p)
    if (act ~ /(^|[^a-z])then([^a-z]|$)/) refuse("item", "item " n " chains a second action (\"then\") — one action per item")
    if (index(d, " " DASH " ") == 0 && index(d, " -- ") == 0 && dl !~ /(^|[^a-z])(because|so that)([^a-z]|$)/)
      refuse("item", "item " n " gives no why — add one clause after \" " DASH " \"")
    if (dl ~ /(^|[^a-z])(whether|either)([^a-z]|$)|or not|up to you|your call/)
      refuse("item", "item " n " offers a choice, not a recommendation — say which and why")
    S[n] = stems(t)
  }
  for (n = 1; n <= items; n++) {
    dl = tolower(shown(item[n])); h = dl; gsub(/\*\*|__/, "", h); h = trim(h)
    while (h != "" && substr(h, 1, 1) !~ /[a-z]/) h = substr(h, 2)
    if (n > 1 && (h ~ /^first([^a-z]|$)/ || match(dl, "(^|[^a-z])first[ \t]*([.,;:!)]|" DASH "|$)")))
      refuse("precedence", "item " n " says \"first\" but sits below item " (n - 1) " — move it up")
    x = referent(dl, "before")
    if (x != "") for (m = 1; m < n; m++) if ((hit = overlap(stems(x), S[m])) != "")
      refuse("precedence", "item " n " runs \"before\" item " m " (\"" hit "\") but sits below it — move it up")
    for (k = 1; k <= 2; k++) {
      x = referent(dl, k == 1 ? "once" : "after")
      if (x != "") for (m = n + 1; m <= items; m++) if ((hit = overlap(stems(x), S[m])) != "")
        refuse("precedence", "item " n " waits on item " m " (\"" hit "\") but sits above it — move it down")
    }
  }
  exit (n_refused > 0 ? 1 : 0)
}'
}

if [ "${1:-}" = "--self-test" ]; then
  [ "$(tail -n 1 "$0")" = "$EOF_SENTINEL" ] || { echo "self-test: $0 is truncated — refusing" >&2; exit 2; }
  good=$'Merged two PRs.\n\nNeeds you:\n1. Merge [r#1](https://example.com/1) \342\200\224 CI is green.'
  bad=$'Did things.\n\nNeeds you:\n1. Restart Claude at `~/x` \342\200\224 it reloads.\n2. Stop the agents at `~/y` first \342\200\224 they hold locks.'
  printf '%s\n' "$good" | check >/dev/null || { echo "self-test: a clean report was refused" >&2; exit 2; }
  printf '%s\n' "$bad" | check >/dev/null && { echo "self-test: an inverted list cleared" >&2; exit 2; }
  echo "$SELFTEST_OK"; exit 0
fi

[ "${1:-}" = "--body-file" ] && [ $# -eq 2 ] || usage
if [ "$2" = "-" ]; then body="$(cat)"; else
  [ -r "$2" ] || { echo "report-clearance: cannot read '$2'" >&2; exit 2; }
  body="$(cat "$2")"
fi
printf '%s\n' "$body" | check
rc=$?
[ "$rc" -le 1 ] || { echo "report-clearance: the checker itself failed (awk exit $rc)" >&2; exit 2; }
[ "$rc" -eq 0 ] && echo "CLEAR"
exit "$rc"

#EOF: report-clearance.sh is complete to here
