#!/usr/bin/env bash
# do-not-repeat.sh — what an earlier round of THIS task already tried, so the next agent
# does not retry it. `append <task> --line <text>` adds one entry to the task's
# `do_not_repeat:` (whitespace folded, 200 chars, deduped, capped at 10); `brief <task>`
# prints the block the PM pastes into the next dispatch verbatim, under a fixed heading,
# and prints nothing when there is nothing. Exit: 0 done, 1 at the cap (fold the oldest
# into `# Notes`, then retry), 2 cannot answer, 3 write failed or did not read back as
# intended (checked in a temp file first, so nothing written). Reasoning:
# ai-bridge-next/task-012, the qualitative half of stall-counter.sh — that counts rounds,
# this says what not to try again.
set -uo pipefail

FIELD=do_not_repeat
MAX_ENTRIES=10
MAX_CHARS=200
# THE ONE COPY OF THE HEADING. project-manager.md quotes it and tests/do-not-repeat.test.sh
# pins both against this line, so a rename cannot land in one place only.
HEADING='## Do not repeat (earlier rounds of this task)'
TRAILER='Each line is an approach an earlier round already tried and the evidence it failed on. Do not retry one; if you must, say why in your report.'

usage() { sed -n '2,8p' "$0" >&2; exit 2; }

# The frontmatter block. Exit 3 when the file does not open with `---`, exit 4 when it
# opens but never closes — the same reader stall-counter.sh and check-dispatch.sh use.
fm_block() {
  awk '
    NR==1 && $0!="---" { bad=3; exit }
    /^---$/ { n++; if (n==2) { closed=1; exit } ; next }
    n==1 { print }
    END { if (bad) exit bad; if (!closed) exit 4 }
  ' "$1"
}

# One unescaped entry per line, flow or block form. Exit 5 on a shape it cannot read
# verbatim (unterminated quote, non-item line in a block): the writer would drop it.
read_entries() { # <frontmatter>
  printf '%s\n' "$1" | DNR_KEY="$FIELD" awk '
    function quoted(t, i,   n, c, q, buf) { # from the quote at t[i]; sets QEND past it
      q = substr(t, i, 1); n = length(t); buf = ""
      for (i++; i <= n; i++) {
        c = substr(t, i, 1)
        if (q == "\"" && c == "\\") { i++; buf = buf substr(t, i, 1); continue }
        if (c == q) { if (q == SQ && substr(t, i + 1, 1) == q) { buf = buf q; i++; continue }
                      QEND = i + 1; return buf }
        buf = buf c
      }
      bad = 1; QEND = n + 1; return ""
    }
    function flow(body,   n, i, a, c) {
      sub(/^\[/, "", body); sub(/\][[:space:]]*(#.*)?$/, "", body)
      if (index(body, "\"") == 0 && index(body, SQ) == 0) {
        n = split(body, a, ",")
        for (i = 1; i <= n; i++) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", a[i]); if (a[i] != "") print a[i] }
        return
      }
      n = length(body)
      for (i = 1; i <= n; i++) {
        c = substr(body, i, 1)
        if (c == "\"" || c == SQ) { print quoted(body, i); i = QEND - 1 }
      }
    }
    function item(t,   c) {
      sub(/^[[:space:]]+-[[:space:]]*/, "", t)
      c = substr(t, 1, 1); if (c == "\"" || c == SQ) { print quoted(t, 1); return }
      sub(/[[:space:]]+#.*$/, "", t); gsub(/^[[:space:]]+|[[:space:]]+$/, "", t)
      if (t != "") print t
    }
    BEGIN { key = ENVIRON["DNR_KEY"]; SQ = sprintf("%c", 39) }
    done { next }
    !inblock && index($0, key ":") == 1 {
      rest = substr($0, length(key) + 2); gsub(/^[[:space:]]+|[[:space:]]+$/, "", rest)
      if (rest == "" || rest ~ /^#/) { inblock = 1; next }
      if (rest !~ /\]/) bad = 1; else flow(rest)
      done = 1; next
    }
    inblock && /^[[:space:]]+-([[:space:]]|$)/ { item($0); next }
    inblock && /^[[:space:]]*$/ { next }
    inblock && /^[^[:space:]]/ { done = 1; next }
    inblock { bad = 1; done = 1 }
    END { if (bad) exit 5 }'
}

field_form() { # <frontmatter> -> flow | block | absent; only the FIRST occurrence counts
  printf '%s\n' "$1" | awk -v key="$FIELD" '
    index($0, key ":") == 1 {
      v = substr($0, length(key) + 2); gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      print ((v == "" || v ~ /^#/) ? "block" : "flow"); f = 1; exit
    }
    END { if (!f) print "absent" }'
}

# Text to a double-quoted scalar: whitespace folded to one line and truncated, because an
# entry is read by a human in the task document and pasted into a brief — a line, never a
# pasted log. Folding also makes the dedupe comparison stable across rounds.
yaml_quote() { # <text>
  printf '"%s"' "$(printf '%s' "$1" \
    | tr '\n\t\r' '   ' \
    | sed 's/  */ /g; s/^ //; s/ $//' \
    | cut -c "1-$MAX_CHARS" \
    | sed 's/\\/\\\\/g; s/"/\\"/g')"
}
normalise() { # <text> — exactly what an appended entry becomes
  printf '%s' "$1" | tr '\n\t\r' '   ' | sed 's/  */ /g; s/^ //; s/ $//' | cut -c "1-$MAX_CHARS"
}

# Rereads the temp file through read_entries before replacing the document; returns 4,
# document untouched, when it does not read back as <entries>.
set_field() { # <task-doc> <form> <entries, one per line>
  local tmp val e rc=0
  if [ "$2" = block ]; then
    val=""
    while IFS= read -r e; do val="${val}
  - $(yaml_quote "$e")"; done <<EOF
$3
EOF
  else
    val=" ["
    while IFS= read -r e; do val="${val} $(yaml_quote "$e"),"; done <<EOF
$3
EOF
    val="${val%,} ]"
  fi
  tmp="$(mktemp "${TMPDIR:-/tmp}/do-not-repeat.XXXXXX")" || return 3
  # The value travels in the ENVIRONMENT, never through `awk -v`: -v applies escape
  # processing, so a stored `\"` would arrive as a bare quote and corrupt the scalar.
  DNR_KEY="$FIELD" DNR_VAL="$val" DNR_FORM="$2" awk '
    BEGIN { k = ENVIRON["DNR_KEY"]; v = ENVIRON["DNR_VAL"]; blk = ENVIRON["DNR_FORM"] == "block" }
    span && /^[[:space:]]*$/ { held = held $0 "\n"; next }
    span && /^[[:space:]]/ { held = ""; next }
    span { span = 0; printf "%s", held }
    NR == 1 && $0 == "---" { n = 1; print; next }
    n == 1 && $0 == "---" { if (!done) { print k ":" v; done = 1 } n = 2; print; next }
    n == 1 && !done && index($0, k ":") == 1 { print k ":" v; done = 1; span = blk; next }
    { print }
  ' "$1" > "$tmp" || rc=3
  if [ "$rc" -eq 0 ]; then
    local back
    back="$(read_entries "$(fm_block "$tmp")")" && [ "$back" = "$3" ] || rc=4
  fi
  [ "$rc" -eq 0 ] || { rm -f "$tmp"; return "$rc"; }
  cat "$tmp" > "$1" || rc=3            # rewrite in place: keeps the inode and the mode
  rm -f "$tmp"
  return "$rc"
}

CMD="${1:-}"; shift 2>/dev/null || true
case "$CMD" in append|brief) ;; -h|--help|'') usage ;; *) echo "do-not-repeat: unknown command '$CMD'" >&2; usage ;; esac

TASK="${1:-}"; [ -n "$TASK" ] || usage; shift
[ -f "$TASK" ] || { echo "do-not-repeat: no such task document: $TASK" >&2; exit 2; }

LINE=""; HAVE_LINE=no
while [ $# -gt 0 ]; do
  case "$1" in
    --line) [ $# -ge 2 ] || { echo "do-not-repeat: --line needs a value" >&2; exit 2; }
            LINE="$2"; HAVE_LINE=yes; shift 2 ;;
    *) echo "do-not-repeat: unexpected argument '$1'" >&2; usage ;;
  esac
done

FM=""; fm_rc=0
FM="$(fm_block "$TASK")" || fm_rc=$?
[ "$fm_rc" -eq 0 ] || {
  echo "do-not-repeat: $TASK has no readable YAML frontmatter — refusing rather than" >&2
  echo "               writing into a document whose shape is unknown." >&2
  exit 2
}

rd_rc=0
ENTRIES="$(read_entries "$FM")" || rd_rc=$?
[ "$rd_rc" -eq 0 ] || {
  echo "do-not-repeat: $TASK carries a $FIELD this script cannot read verbatim (an" >&2
  echo "               unterminated quote, or a non-item line in the block) — fix it by hand." >&2
  exit 2
}
COUNT=0
[ -n "$ENTRIES" ] && COUNT="$(printf '%s\n' "$ENTRIES" | grep -c '')"

case "$CMD" in
  brief)
    [ "$COUNT" -gt 0 ] || exit 0
    printf '%s\n\n' "$HEADING"
    printf '%s\n' "$ENTRIES" | sed 's/^/- /'
    printf '\n%s\n' "$TRAILER"
    exit 0
    ;;

  append)
    [ "$HAVE_LINE" = yes ] || { echo "do-not-repeat: append needs --line <text>" >&2; exit 2; }
    NEW="$(normalise "$LINE")"
    [ -n "$NEW" ] || { echo "do-not-repeat: --line is empty after folding — nothing to record" >&2; exit 2; }
    # An identical entry is a no-op rather than a second copy: a re-run of the same round
    # must not spend one of the ten slots on a line already there.
    if [ -n "$ENTRIES" ] && printf '%s\n' "$ENTRIES" | grep -qxF -- "$NEW"; then
      printf 'KEPT      %s/%s — already recorded\n' "$COUNT" "$MAX_ENTRIES"
      exit 0
    fi
    if [ "$COUNT" -ge "$MAX_ENTRIES" ]; then
      echo "do-not-repeat: $TASK is at the cap of $MAX_ENTRIES $FIELD entries. Fold the" >&2
      echo "               oldest into '# Notes' and re-run; nothing was written." >&2
      exit 1
    fi
    WANT="$NEW"; [ -z "$ENTRIES" ] || WANT="$ENTRIES
$NEW"
    w_rc=0; set_field "$TASK" "$(field_form "$FM")" "$WANT" || w_rc=$?
    case "$w_rc" in
      0) ;;
      4) echo "do-not-repeat: the rewritten $FIELD did not read back as intended (an existing" >&2
         echo "               entry over $MAX_CHARS chars or with doubled spaces?); nothing written." >&2
         exit 3 ;;
      *) echo "do-not-repeat: could not write $FIELD" >&2; exit 3 ;;
    esac
    printf 'RECORDED  %s/%s — %s\n' "$((COUNT + 1))" "$MAX_ENTRIES" "$NEW"
    exit 0
    ;;
esac
