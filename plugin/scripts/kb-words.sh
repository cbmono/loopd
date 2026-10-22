#!/usr/bin/env bash
# kb-words.sh — sourced, never run: the one content-word key a task and a Finding are matched
# on. KB_WORDS_AWK defines the awk function `words(s, set)` (kb-compare.sh, kb-select.sh);
# kb_task_text <task-doc> prints the task's title, description and acceptance_criteria on one
# line (kb-select.sh, service-doc.sh). Reasoning: kb-retrieval-and-papercut-fixes/task-003.

# Wording is normalised away (case, punctuation, order, articles, plurals); every other word is
# content, so an interpreter, a harness or a calling context that differs is a different key.
# shellcheck disable=SC2034  # read by the scripts that source this file
KB_WORDS_AWK='
function words(s, set,   n, i, w, p, list) {
  if (!KB_STOP_SET) {
    n = split("a an the and of to is are was were be been being it its this that these those as", p, " ")
    for (i = 1; i <= n; i++) STOP[p[i]] = 1
    KB_STOP_SET = 1
  }
  s = tolower(s); gsub(/[^a-z0-9._-]/, " ", s); n = split(s, p, " "); list = ""
  for (i = 1; i <= n; i++) {
    w = p[i]; sub(/^[._-]+/, "", w); sub(/[._-]+$/, "", w)
    if (w == "" || (w in STOP)) continue
    if (length(w) > 4 && w ~ /ies$/) w = substr(w, 1, length(w) - 3) "y"
    else if (length(w) > 3 && w ~ /s$/ && w !~ /ss$/) w = substr(w, 1, length(w) - 1)
    if (!(w in set)) { set[w] = 1; list = list " " w }
  }
  return substr(list, 2)
}
'

kb_task_text() { # <task-doc>
  awk '
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    /^[A-Za-z_][A-Za-z0-9_]*:/ {
      k = $0; sub(/:.*/, "", k); take = (k == "title" || k == "description" || k == "acceptance_criteria")
      if (take) { v = $0; sub(/^[^:]*:/, "", v); out = out " " v }
      next
    }
    take && /^[ \t]/ { out = out " " $0 }
    END { gsub(/[ \t]+/, " ", out); sub(/^ /, "", out); print out }' "$1"
}
