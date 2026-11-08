#!/usr/bin/env bash
#
# pr-comment-clearance.sh — assert that a PULL-REQUEST COMMENT carries the required SHAPE
# of a reply to review findings: a lead, one ENTRY per finding with an explicit verdict on
# it, and the closing evidence — each of those elements inside one measured ceiling.
#
#   Usage: pr-comment-clearance.sh --comment <id> [--repo <owner>/<name>]
#          pr-comment-clearance.sh --review-comment <id> [--repo <owner>/<name>]
#          pr-comment-clearance.sh --comment-file <path>  (decide before posting)
#          pr-comment-clearance.sh --self-test            (prove this script RUNS)
#
# WHY THIS EXISTS, AND WHY THE SIBLING DID NOT COVER IT. `pr-body-clearance.sh` reads a
# pull request's BODY. It does not look at comments at all. So the house style for a reply
# — `CONVENTIONS.md`, "The reply is a list, not a letter" and "A GitHub comment is about
# 280 characters" — was governed by prose alone on the one surface nothing read, and on
# 2026-08-31 a reply whose whole content was *"both findings are valid, neither is fixed in
# this PR, and here is why"* ran to **2,986 characters over 20 lines**: roughly 250
# characters of decision wrapped in twelve times its own weight. That is
# [[a-rule-with-no-reader-is-not-a-rule]] inside the machinery built to end that pattern.
# This file is the reader for the comment.
#
# IT IS STRUCTURAL, AND NO EXIT CODE HERE IS DERIVED FROM A TOTAL CHARACTER COUNT.
# A total cap is the obvious implementation and the wrong one, for the reason the sibling
# states in its own error text: it refuses the legitimately detailed reply and clears the
# short self-defending one. A reply that addresses eleven findings honestly needs eleven
# times the words of one that addresses one. So the budget is derived from the reply's own
# structure — a reply to review findings addresses N findings, so it has N entries — and
# the ceiling below is applied PER ELEMENT. Total budget therefore grows with N, and a
# well-structured reply of any length clears: `tests/pr-comment-clearance.test.sh` drives
# a reply LONGER than the measured incident and asserts it clears. The reply's own
# character count is printed once as information and never read again: NO THRESHOLD, NO
# CONSTANT AND NO COMPARISON ON IT EXISTS ANYWHERE BELOW, and the harness asserts that
# statically as well as behaviourally.
#
# THE ELEMENTS, AND HOW EACH IS FOUND.
#
#   1. THE ENTRIES — one per finding. Found structurally, not by text: a list item
#      (`- `, `* `, `+ `, `1. `, `1) `), an ATX heading, or a TABLE DATA ROW. All three are
#      in the real corpus below, and the table form is there because our best-shaped
#      measured reply used `| finding | verdict | fix |` — a reader that only knew about
#      bullets would have refused the one reply that got it right. A line indented two
#      spaces or more is a CONTINUATION of the entry above it, never a new entry: reading
#      a nested bullet as its own entry would divide one element's bytes among several and
#      make the ceiling more lenient, which is the wrong direction for a mistake.
#
#      KNOWN LIMIT, STATED RATHER THAN IMPLIED: a SECTION heading above the list (`###
#      Round 1 replies`) is read as an entry, and refused at exit 1 for carrying no
#      verdict, naming itself in the message. The failure direction is a refusal and a
#      glance, the fix is deleting one line, and the house style already puts what round
#      it is in the LEAD. Recognising a heading is what catches the measured comment,
#      whose findings were `###` headings, so this is the cost of that and not an
#      oversight.
#
#   2. THE VERDICT ON EACH ENTRY — the identifying property, and the analogue of the
#      `✓`/`✗` column the sibling requires of a criteria table. It is what tells a reply to
#      review findings from any other list, and it is the one thing the reviewer on the
#      other end actually needs: *valid / fixed / declined / already deferred*. An entry
#      with no verdict is refused at exit 1, by index. Table 2 below is the vocabulary,
#      matched case-insensitively; it is deliberately wider than the three words
#      `CONVENTIONS.md` uses, because a gate that refuses `confirmed` or `not taking` would
#      be refusing correct work, and a gate that refuses correct work gets switched off.
#
#   3. THE LEAD AND THE CLOSING EVIDENCE. Everything before the first entry is the LEAD;
#      the last blank-line-separated block after the last entry is the TAIL (the evidence
#      line the house style asks for). Both are bounded exactly as an entry is — because
#      in the measured corpus the bloat sat in the LEAD as often as in an entry (two real
#      replies carried leads of 1,135 and 1,759 bytes above a correctly-shaped list), and a
#      ceiling that watched only the entries would have cleared both.
#
#   4. A REPLY WITH NO ENTRIES IS ONE ELEMENT. `@coderabbitai review` (20 bytes) and
#      "Round 2 clean, nothing further" are legitimate replies, and refusing them for
#      having no findings to address would be nonsense. So a reply with no entry marker is
#      measured as a single element against the same ceiling — which is also what catches
#      the other real defect in the corpus: two replies of 897 and 1,078 bytes, and one of
#      3,796, that were one wall of prose where a per-finding list belonged. The refusal
#      says to give each finding its own entry.
#
# THE CEILING IS 618 BYTES PER ELEMENT, AND HERE IS THE CORPUS IT CAME FROM.
# Measured 2026-08-31, bytes under `LC_ALL=C`, over the fence-stripped rendering: every
# comment written by this repo's own agents on `cbmono/loopd` pull requests 60-84 (13
# PR-thread comments + 3 inline review comments = 16 replies, 36 entries), plus the
# `alteos-gmbh/monorepo#3260` comment that motivated the task.
#
#     element kind     values measured                          n
#     lead             0, 0, 59, 74, 96, 99, 157, 167, 278,     12
#                      925, 1135, 1759
#     entry            60 .. 530 (30 of them), then 706, 779,   36
#                      849, 867, 959, 1841, 2318
#     tail             27, 45, 56, 84, 107, 161, 168, 174,      12
#                      204, 222, 271, 966
#     single element   20, 20, 20, 897, 1078                     5
#
# 618 IS THE MIDPOINT OF THE EMPTY BAND 531-705, and both sides of that band are named:
#
#   * BELOW IT, the largest element measured anywhere in the corpus is 530, and the two
#     replies whose shape is exactly what `CONVENTIONS.md` asks for — one entry per
#     finding, a verdict, the fix or the reason, nothing else — top out at 503 and 496.
#     Those two are 2,149 and 1,744 CHARACTERS in total — the count the host reports, and
#     the one this script prints — both far past "roughly a tweet", and both clear here.
#     That is the anti-total-cap property demonstrated on real data rather than asserted.
#   * ABOVE IT, 706 is the smallest element the task's own design brief calls bloat: an
#     entry that argues its own case (*"this PR in reverse, on the path nobody looks
#     at"*), and above that 1,841 and 2,318 — the self-defending paragraphs.
#
# So the ceiling sits 88 bytes clear of the largest honest element and 88 short of the
# smallest offending one, which is symmetric by measurement and not by rounding.
#
# WHAT IT FAILS, COUNTED. The ceiling refuses 13 of the 65 elements and so 11 OF THE 17
# REPLIES (10 of the 16 real loopd ones, plus the motivating comment). The VERDICT
# requirement refuses one further reply — `r-3890408025`, three short entries whose third
# reads *"Not the same defect as the red harness"*, which is a verdict this vocabulary does
# not know. So 12 of 17 are refused and 5 clear. That is a high rate and it is the honest
# one: this is a PRE-RULE corpus, written while the 280-character style had no reader at
# all, and 618 bytes per ELEMENT is already more than twice that whole-comment target. The
# one arguable false refusal costs its author one word. `tests/pr-comment-clearance.test.sh`
# pins the boundary values as FIXTURES (530 and 503 clear, 706 and 1841 refuse), so moving
# the number means re-measuring rather than editing a constant.
#
# WHAT IT DOES NOT DO, STATED RATHER THAN IMPLIED. There is deliberately NO FLOOR. The
# sibling has one because an evidence cell reading `ok` is a claim with no evidence; here
# the equivalent entry, `- Finding 3 — fixed: a1b2c3d.`, is 30 bytes and complete, so a
# floor derived from anything in the corpus would refuse correct replies. This reader
# therefore requires the VERDICT and bounds the CEILING, and it does not judge whether the
# reason behind a verdict is adequate — that is a human's read, and narrowing the promise
# beats extending a text scan until it is unfalsifiable
# ([[narrow-the-promise-instead-of-extending-a-text-scan-forever]]). Nor does it decide
# whether a comment IS a reply to review findings: it answers "does this carry the shape a
# reply must have", and the caller invokes it on a reply.
#
# THE CARVE-OUTS FAIL OPEN, AND THEY SAY SO OUT LOUD. `CONVENTIONS.md` has always exempted
# three things from every brevity rule — an ERROR REPORT, a SECURITY FINDING, and a
# DESTRUCTIVE-ACTION CONFIRMATION — because the failure mode of a terseness gate is
# trimming the one thing the reader needed to act safely. Table 3 is that exemption, and it
# is the only match in this file whose false positive WEAKENS the gate. Three things keep
# it honest: it must LEAD a line's own content (a mid-sentence mention of "security" does
# not claim it), the clearance message quotes the line that claimed it, so an abuse is
# visible in the log rather than silent, and the vocabulary is small and written down here
# and in `CONVENTIONS.md` rather than inferred. AND IT EXEMPTS THE CEILING ONLY: it is read
# AFTER the verdict check, so a reply shaped as a list of findings still owes a verdict on
# each of them whatever it is reporting — which is what the rule in `CONVENTIONS.md` says,
# and the first cut of this file exempted both.
#
# GENERIC PLUGIN FILE — ships inside the `loopd` plugin; nothing to edit per
# instance. It takes no org, repo or vendor identity: those come from the arguments.
#
# Exit codes — 0 is the ONLY clearance; every other code is a refusal:
#
#   0  the reply carries the shape, every element is inside the ceiling, at whatever total
#      length — or a carve-out is claimed, in which case the reason is printed
#   1  the reply is readable and the SHAPE is missing: it is empty, or an entry carries no
#      verdict. stderr names every entry it means, by index
#   2  usage error, or the environment cannot answer (no `gh`/`jq`, an unreadable comment,
#      an unreadable file, a pattern table that will not compile) — UNKNOWN, and unknown is
#      never clearance. A COMMENT THAT CANNOT BE FETCHED OR READ IS THIS CODE, NEVER 0:
#      reading a transient 5xx as "an empty comment" would be a refusal today and a
#      clearance the moment anything downstream treated one of these codes as benign
#   3  the shape is all there, and at least one ELEMENT is over the ceiling. stderr names
#      every one — which element, its index, its measured size — because a bare exit code
#      leaves an author diffing their own reply against a number they have to go and read
#
# WHAT IT PRINTS IS UNTRUSTED TEXT. The comment comes from a pull request, which anyone
# able to comment can write. Nothing from it is echoed except a bounded EXCERPT of an
# offending element, reduced to printable ASCII (every other byte becomes `.`, which under
# `LC_ALL=C` also removes every control byte and so every terminal escape) and truncated
# to 60 bytes.
#
# AND A TRUNCATED COPY OF THIS FILE IS UNKNOWN STATE TOO — the sibling's lesson, taken
# whole: `--self-test` proves this file RUNS, which is not proving it is COMPLETE. A copy
# cut off below the self-test block still runs and still prints the sentinel. The last line
# of this file is therefore a completeness sentinel, asserted by `--self-test`, which no
# cut short of the end can satisfy.
#
# No `set -e`: a `grep` that finds nothing is an ANSWER here, not a fault, and under `-e`
# the first such test would exit the script with a success-looking code. Every failure path
# below is explicit.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]:-$0}")/bundle-paths.sh" || exit 2

# --- table 1: the verdict vocabulary ------------------------------------------
# One POSIX ERE per line, matched case-insensitively against an entry's own text. Blank
# lines and whole-line `#` comments are ignored; a pattern may not carry a trailing
# comment, because the whole line is the pattern. Every row is compiled up front by
# `validate_tables`, because a table that will not compile is not a table that matches
# less, it is a table that matches NOTHING — and here that turns every reply into a
# refusal for a reason that is not about the reply.
#
# NO BACKSLASH ESCAPES IN EITHER TABLE. Both travel into `awk` through `-v`, which
# processes escape sequences in the value BEFORE the string is ever used as a regex: a row
# written `\*\*` arrives as `**`, which is not a valid ERE, and awk then dies on the first
# comment it reads rather than matching less. Spell a literal with a bracket expression
# (`[*]`, `[.]`) instead. `validate_tables` compiles every row THROUGH THE SAME `-v` PATH
# for exactly this reason — a check that compiled them with `grep -E` passed while awk
# could not read them, which is a guard testing something other than what runs.
#
# WIDER THAN THE THREE WORDS THE RULE USES, ON PURPOSE. `CONVENTIONS.md` writes *valid /
# declined / already deferred*; the measured corpus also says `fixed` (24 times),
# `confirmed`, `correct`, `addressed`, `agreed`, `not taking`, `not changed`, `out of
# scope` and `duplicate`. Refusing those would refuse correct work. `already` is NOT a
# verdict on its own — the corpus has nine uses of it as an ordinary adverb ("already
# landed", "already rare") — so it only counts in the fixed phrases below.
#
# AND `correct` IS NARROWED FOR THE SAME REASON, ONE CLASS DOWN. It shipped as a bare
# token, and it is the only ADJECTIVE in this table — every other row is a past-tense
# verdict (`fixed`, `declined`, `deferred`, `applied`), which is a word an entry cannot
# carry by accident. Measured on 1.1.x: "the correct fix would be to quote the path, but I
# have not done it" CLEARED — an entry describing a fix it explicitly had not made, which
# makes the verdict optional exactly where a reader needs it most. So `correct` counts only
# where it STANDS as the verdict: nothing but punctuation or the end of the element may
# follow it (`correct:`, `correct.`, `— correct`, `correct` last). The corpus use is the
# colon form, so the narrowing keeps it. KNOWN LIMIT, stated rather than implied: an
# adjective followed by punctuation ("the correct — and only — fix") still matches; the
# common shape is `correct` + noun, and that is the one this refuses.
VERDICTS='
(^|[^[:alnum:]])(in)?valid([^[:alnum:]]|$)
(^|[^[:alnum:]])fixed([^[:alnum:]]|$)
(^|[^[:alnum:]])confirmed([^[:alnum:]]|$)
(^|[^[:alnum:]])correct([[:space:]]*[^[:alnum:][:space:]]|[[:space:]]*$)
(^|[^[:alnum:]])addressed([^[:alnum:]]|$)
(^|[^[:alnum:]])agreed([^[:alnum:]]|$)
(^|[^[:alnum:]])applied([^[:alnum:]]|$)
(^|[^[:alnum:]])declined([^[:alnum:]]|$)
(^|[^[:alnum:]])deferred([^[:alnum:]]|$)
(^|[^[:alnum:]])duplicate([^[:alnum:]]|$)
(^|[^[:alnum:]])not (taking|taken|doing|fixing|changed|changing)([^[:alnum:]]|$)
(^|[^[:alnum:]])(wont|won.t) fix([^[:alnum:]]|$)
(^|[^[:alnum:]])no change( needed| required)?([^[:alnum:]]|$)
(^|[^[:alnum:]])out of scope([^[:alnum:]]|$)
(^|[^[:alnum:]])already (fixed|deferred|logged|recorded|handled|addressed|done|open)([^[:alnum:]]|$)
'

# --- table 2: the carve-outs ---------------------------------------------------
# THE ONE MATCH IN THIS FILE THAT FAILS OPEN. See the header: an error report, a security
# finding and a destructive-action confirmation are never trimmed, so a reply that claims
# one clears at any element size — and the clearance says which pattern claimed it.
#
# EVERY ROW IS ANCHORED AT THE START OF A LINE and must lead that line's own content
# (optionally behind a heading marker, a list marker or an emphasis run), so a sentence
# that merely mentions security does not buy an exemption. Matched case-insensitively.
CARVE_OUTS='
^[[:space:]]{0,3}([-*+][[:space:]]+|#{1,6}[[:space:]]+)?([*]|_)*(security|vulnerability|cve-[0-9])
^[[:space:]]{0,3}([-*+][[:space:]]+|#{1,6}[[:space:]]+)?([*]|_)*(error report|traceback|stack trace|panic:)
^[[:space:]]{0,3}([-*+][[:space:]]+|#{1,6}[[:space:]]+)?([*]|_)*(destructive|irreversible|data loss|confirm before)
'

# --- table 3: the one bound in this file ---------------------------------------
# Bytes, under `LC_ALL=C`, PER ELEMENT. The midpoint of the measured empty band 531-705 —
# see the corpus in the header for the arithmetic and for both sides of the band.
#
# THIS IS NOT A REPLY LENGTH AND MUST NEVER BECOME ONE. Nothing below sums these, and
# nothing below compares them to `reply_chars`. `tests/pr-comment-clearance.test.sh` pins
# this value and drives both mutants of it — raised and lowered — so a change made without
# re-measuring goes red rather than through.
REPLY_ELEMENT_CEILING=618

usage() {
  echo "Usage: $(basename "$0") --comment <id> [--repo <owner>/<name>]" >&2
  echo "       $(basename "$0") --review-comment <id> [--repo <owner>/<name>]" >&2
  echo "       $(basename "$0") --comment-file <path>  (decide before posting)" >&2
  echo "       $(basename "$0") --self-test            (prove this script RUNS)" >&2
  exit 2
}

# `rows <table>` strips comments and blank lines; every table is read through it, so a
# malformed row is inert rather than silently matching everything.
rows() { printf '%s\n' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
                                  | grep -v '^#' | grep -v '^$'; }

# Compile every ERE row before anything is classified with it. Checked here (up front) and
# again in --self-test, so a caller refuses a copy carrying a broken table.
validate_tables() {
  local bad="" r
  # AND awk MUST HONOUR AN INTERVAL, NOT MERELY COMPILE ONE. Every pattern here and in
  # `render_reply`/`is_listy` uses `{0,3}`, `{1,6}` or `{3,}`, and an awk without interval
  # support treats those braces as LITERAL characters: nothing fails to compile, the
  # carve-outs stop matching, fences stop being stripped and an ATX heading stops being an
  # entry. So this probe asserts the semantics in both directions — an interval that must
  # match and one that must not — and refuses at exit 2 if the engine disagrees, because a
  # verdict from a regex engine that reads these patterns differently is unknown state.
  LC_ALL=C awk 'BEGIN { if ("###" ~ /^#{1,6}$/ && "#" !~ /^#{2,3}$/) exit 0; exit 1 }' \
    >/dev/null 2>&1 || {
    echo "error: this awk does not honour POSIX interval expressions ({1,6}), so every" >&2
    echo "       pattern in this script would read its braces as literal characters and" >&2
    echo "       match nothing. That is unknown state, not a verdict. Refusing." >&2
    return 2
  }
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    LC_ALL=C awk -v p="$r" 'BEGIN { if ("" ~ p) x = 1; exit 0 }' >/dev/null 2>&1 \
      || bad="$bad          $r
"
  done <<EOF
$(rows "$VERDICTS")
$(rows "$CARVE_OUTS")
EOF
  [ -z "$bad" ] || {
    echo "error: these rows in this script's pattern tables are not valid POSIX EREs, so" >&2
    echo "       the table matches nothing and every reply would be refused for a reason" >&2
    echo "       that is not about its text. Refusing (fail closed):" >&2
    printf '%s' "$bad" >&2
    return 2
  }
  return 0
}

# --- the rendering every test reads -------------------------------------------
# ONE question: which lines of this reply would a reader see as prose? Fenced blocks
# (``` and ~~~, at up to three spaces of indent, closed or left open to EOF) are removed —
# a fenced block is evidence a reader acts on (a command and its output, a diff), no
# measured element of the corpus was one, and charging it to the entry around it would
# refuse the one reply that pasted the shellcheck output it was asked for. KNOWN LIMIT,
# stated rather than implied: bloat inside a fence is therefore not measured here. Carriage
# returns go too — the host stores CRLF for text typed in the web editor, and a stray \r
# defeats an anchored match for no reason a human could see.
#
# THE STRIPPER IS A TOGGLE, so an unbalanced fence blanks the rest of the reply. Here that
# empties the reply, which refuses at exit 1 — the correct answer to a comment the host
# will render as one long code block anyway.
render_reply() { # <src> <dst>
  tr -d '\r' < "$1" | awk '
    {
      line = $0
      if (fence == 0) {
        if (match(line, /^[[:space:]]{0,3}(`{3,}|~{3,})/)) {
          opener = substr(line, RSTART, RLENGTH)
          sub(/^[[:space:]]+/, "", opener)
          fchar = substr(opener, 1, 1)
          fwidth = length(opener)
          fence = 1
          next
        }
        print line
        next
      }
      # CommonMark closes a fence ONLY on a run of the SAME character at least as long,
      # with nothing but whitespace after it. A toggle that closed on any fence line would
      # read a ``` nested inside a ````md block as the closer and expose the quoted content
      # below it — which is exactly the content that must not clear a gate.
      if (match(line, /^[[:space:]]{0,3}(`{3,}|~{3,})[[:space:]]*$/)) {
        closer = substr(line, RSTART, RLENGTH)
        gsub(/[[:space:]]/, "", closer)
        if (substr(closer, 1, 1) == fchar && length(closer) >= fwidth) fence = 0
      }
      next
    }
  ' > "$2"
}

# --- the scan: elements, verdicts, carve-outs, all in one pass ----------------
# ONE PARSER, ON PURPOSE. "Where does an entry begin" is asked by the verdict check, by the
# ceiling and by the lead/tail split; three parsers would give this repo three answers to
# one question, which is the defect the sibling's header warns about one level up.
#
# Output is TAB-separated, state first:
#   state<TAB>entries<TAB><n>   at least one entry marker was found
#   state<TAB>single<TAB>0      no entry marker at all: the reply is one element
#   state<TAB>empty<TAB>0       nothing readable survived the rendering
#   carve<TAB><excerpt>         a carve-out leads a line: the reply is exempt (0 or 1 line)
#   elem<TAB><kind><TAB><n><TAB><bytes><TAB><verdict>><TAB><excerpt>
#                               one line per element. <kind> is lead|entry|tail|single,
#                               <verdict> is yes|no for an entry and na for the rest.
#
# `LC_ALL=C` PINS THE UNIT: `length()` counts characters in some awks and bytes in others,
# and a threshold that moves with the machine is not a threshold. The corpus above was
# measured the same way.
scan_reply() { # <rendered-reply>
  # awk's `-v` cannot carry a literal newline, so each table travels as one 0x1e-separated
  # field and is split back below. A record separator cannot occur in a comment the host
  # serves as JSON text, so nothing an author writes can add a row.
  LC_ALL=C awk -v verdicts="$(rows "$VERDICTS" | tr '\n' '\036')" \
       -v carveouts="$(rows "$CARVE_OUTS" | tr '\n' '\036')" '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    # A GFM delimiter row: every cell is a run of dashes with optional colons. Asking only
    # whether the line is made of pipes, dashes and colons is a weaker question — `|---|:|`
    # passes that and GitHub renders no table at all.
    function is_delim(s,   arr, n, i, c) {
      s = trim(s)
      if (index(s, "|") == 0) return 0
      sub(/^\|/, "", s); sub(/\|$/, "", s)
      n = split(s, arr, "|")
      if (n < 1) return 0
      for (i = 1; i <= n; i++) { c = trim(arr[i]); if (c !~ /^:?-+:?$/) return 0 }
      return 1
    }
    function is_row(s) { return (trim(s) ~ /^\|/) }
    # A list item, an ordered item or an ATX heading, at NO MORE THAN ONE space of indent.
    # Two spaces or more is a continuation of the entry above — see the header for why that
    # direction is the safe one.
    function is_listy(s) {
      if (s ~ /^[[:space:]]?[-*+][[:space:]]/)        return 1
      if (s ~ /^[[:space:]]?[0-9]+[.)][[:space:]]/)   return 1
      if (s ~ /^[[:space:]]?#{1,6}[[:space:]]/)       return 1
      return 0
    }
    function matches_any(s, table,   i, n, p, arr) {
      n = split(table, arr, "\036")
      for (i = 1; i <= n; i++) {
        p = arr[i]
        if (p == "") continue
        if (tolower(s) ~ p) return i
      }
      return 0
    }
    # UNTRUSTED TEXT LEAVES HERE. Under LC_ALL=C `[:print:]` is ASCII 0x20-0x7e, so this
    # strips control bytes (and so every terminal escape) and the trailing half of a
    # multi-byte character the truncation could otherwise cut in two. Then a fixed 60
    # bytes, because an excerpt that identifies the element is the whole job and a comment
    # must not be able to print itself through this gate.
    function excerpt(s) {
      s = trim(s)
      gsub(/[^[:print:]]/, ".", s)
      if (length(s) > 60) s = substr(s, 1, 57) "..."
      return (s == "" ? "(no text)" : s)
    }
    { lines[NR] = $0 }
    END {
      # A table HEADER and its delimiter row are the table frame, not content: dropped, so
      # the column titles are charged to nobody.
      for (i = 1; i <= NR; i++) frame[i] = 0
      for (i = 1; i <= NR; i++)
        if (is_delim(lines[i])) {
          frame[i] = 1
          if (i > 1 && is_row(lines[i-1])) frame[i-1] = 1
        }

      body = ""
      for (i = 1; i <= NR; i++) if (!frame[i]) body = body lines[i] "\n"
      if (trim(body) == "") { printf "state\tempty\t0\n"; exit }

      # The carve-out is looked for on every line, anchored — see the header.
      for (i = 1; i <= NR; i++) {
        if (frame[i]) continue
        if (matches_any(lines[i], carveouts)) {
          printf "carve\t%s\n", excerpt(lines[i])
          break
        }
      }

      n = 0
      for (i = 1; i <= NR; i++) {
        if (frame[i]) continue
        if (is_listy(lines[i]) || is_row(lines[i])) mk[++n] = i
      }

      if (n == 0) {
        printf "state\tsingle\t0\n"
        printf "elem\tsingle\t1\t%d\tna\t%s\n", length(trim(body)), excerpt(body)
        exit
      }
      printf "state\tentries\t%d\n", n

      # The TAIL is the LAST blank-line-separated block after the last entry — the closing
      # evidence line. Everything between the last entry and it belongs to that entry, so
      # an author cannot park three paragraphs after their last finding and have them
      # charged to nothing.
      tailstart = 0
      for (i = mk[n] + 1; i <= NR; i++) {
        if (lines[i] ~ /^[[:space:]]*$/) continue
        if (i > mk[n] + 1 && lines[i-1] ~ /^[[:space:]]*$/) tailstart = i
      }

      lead = ""
      for (i = 1; i < mk[1]; i++) if (!frame[i]) lead = lead lines[i] "\n"
      if (trim(lead) != "")
        printf "elem\tlead\t1\t%d\tna\t%s\n", length(trim(lead)), excerpt(lead)

      for (k = 1; k <= n; k++) {
        from = mk[k]
        to   = (k < n ? mk[k+1] - 1 : (tailstart ? tailstart - 1 : NR))
        e = ""
        for (i = from; i <= to; i++) if (!frame[i]) e = e lines[i] "\n"
        printf "elem\tentry\t%d\t%d\t%s\t%s\n", k, length(trim(e)), \
               (matches_any(e, verdicts) ? "yes" : "no"), excerpt(e)
      }

      if (tailstart) {
        t = ""
        for (i = tailstart; i <= NR; i++) if (!frame[i]) t = t lines[i] "\n"
        printf "elem\ttail\t1\t%d\tna\t%s\n", length(trim(t)), excerpt(t)
      }
    }
  ' "$1"
}

# --- the verdict, over a reply already on disk ---------------------------------
# The ONE place a reply becomes an exit code, so every call site — a fetched comment and a
# local draft — answers identically. <label> only names the subject in the messages.
decide() { # <rendered> <label> -> 0 clear, 1 shape missing, 2 unknown, 3 an element is over
  local rendered="$1" label="$2" scan state carve tab
  tab="$(printf '\t')"
  scan="$(scan_reply "$rendered")" || return 2
  state="$(printf '%s\n' "$scan" | awk -F'\t' '$1 == "state" { print $2; exit }')"
  case "$state" in entries|single|empty) : ;; *) return 2 ;; esac

  if [ "$state" = empty ]; then
    echo "refuse: $label is empty — a reply with no readable text tells the reviewer" >&2
    echo "        nothing. One line per finding, each with its verdict. See" >&2
    echo "        $AB_CONVENTIONS → \"A reply to review findings has a shape\"." >&2
    return 1
  fi

  # STRUCTURE BEFORE SIZE, and that order is the point: exit 1 says a required part of the
  # shape is missing, exit 3 says it is all there and one element is too big. Telling an
  # author to shorten entries whose verdicts are missing would be advice about the wrong
  # problem.
  local noverdict n
  noverdict="$(printf '%s\n' "$scan" \
    | awk -F'\t' '$1 == "elem" && $2 == "entry" && $5 == "no" { print }')"
  [ -z "$noverdict" ] || {
    n="$(printf '%s\n' "$noverdict" | grep -c '^')"
    echo "refuse: $label is shaped as a list, but the VERDICT is missing on $n of its" >&2
    echo "        entries — so the reviewer cannot tell what was fixed from what was" >&2
    echo "        declined:" >&2
    while IFS="$tab" read -r _ _ idx len _ text; do
      [ -n "${idx:-}" ] || continue
      echo "        entry $idx (${len:-?} bytes): \"${text:-}\"" >&2
    done <<EOF
$noverdict
EOF
    echo "        Say it in one word per entry — valid, fixed, declined, already" >&2
    echo "        deferred — then the fix or the reason. See" >&2
    echo "        $AB_CONVENTIONS → \"A reply to review findings has a shape\"." >&2
    return 1
  }

  # THE CARVE-OUT EXEMPTS THE CEILING, AND NOTHING ELSE — so it is read HERE, after the
  # shape, not before it. An error report, a security finding and a destructive-action
  # confirmation are never trimmed; a reply that is shaped as a list of findings still owes
  # a verdict on each one, whatever it is reporting. The line that claimed the exemption is
  # quoted, so the exemption is visible in the log rather than silent.
  carve="$(printf '%s\n' "$scan" | awk -F'\t' '$1 == "carve" { print $2; exit }')"
  [ -z "$carve" ] || {
    echo "ok: $label claims a CARVE-OUT and is exempt from the element ceiling:" >&2
    echo "      \"$carve\"" >&2
    echo "    An error report, a security finding and a destructive-action confirmation" >&2
    echo "    are never trimmed ($AB_CONVENTIONS). No element size was measured." >&2
    return 0
  }

  local over
  over="$(printf '%s\n' "$scan" \
    | awk -F'\t' -v c="$REPLY_ELEMENT_CEILING" '$1 == "elem" && $4 > c { print }')"
  [ -n "$over" ] || {
    echo "ok: $label carries one entry per finding, a verdict on each, and every" >&2
    echo "    element inside $REPLY_ELEMENT_CEILING bytes." >&2
    return 0
  }

  n="$(printf '%s\n' "$over" | grep -c '^')"
  echo "refuse: $label has $n element(s) over the $REPLY_ELEMENT_CEILING-byte ceiling" >&2
  echo "        $AB_CONVENTIONS puts on ONE element of a reply:" >&2
  # `set -u` is on and a short line would leave a field unset, so every field is read
  # through a default: a refusal that aborted on an unset variable would be a gate that
  # stopped reporting half-way.
  local kind idx len text
  while IFS="$tab" read -r _ kind idx len _ text; do
    kind="${kind:-}"; idx="${idx:-?}"; len="${len:-?}"; text="${text:-}"
    [ -n "$kind" ] || continue
    case "$kind" in
      entry)
        echo "        ENTRY $idx at $len bytes: \"$text\"" >&2
        echo "          Cut it to the verdict and the fix or the reason. Why the" >&2
        echo "          approach is right, what an earlier reviewer said and what the" >&2
        echo "          branch does prove belong in the commit message and the task" >&2
        echo "          doc, and the short entry LINKS to them." >&2 ;;
      lead)
        echo "        the LEAD at $len bytes: \"$text\"" >&2
        echo "          One line before the entries — what round this is, and where the" >&2
        echo "          fixes landed. The argument goes in the task doc." >&2 ;;
      tail)
        echo "        the CLOSING BLOCK at $len bytes: \"$text\"" >&2
        echo "          Evidence as a short list, not prose: the test file and its" >&2
        echo "          tally, the command, the CI run, the URL." >&2 ;;
      *)
        echo "        the WHOLE REPLY at $len bytes, as ONE block: \"$text\"" >&2
        echo "          It addresses findings in prose. Give each finding its own entry" >&2
        echo "          with a verdict on it — then this ceiling applies per entry and" >&2
        echo "          the reply may be as long as the findings need." >&2 ;;
    esac
  done <<EOF
$over
EOF
  echo "        This bounds ONE ELEMENT, never the reply: N findings buy N entries, so a" >&2
  echo "        longer reply that is well shaped clears here and its character count is" >&2
  echo "        reported as information only. An error report, a security finding and a" >&2
  echo "        destructive-action confirmation are never trimmed." >&2
  return 3
}

# --- --self-test: no network, no comment --------------------------------------
#
# It PROVES THIS SCRIPT RUNS, which `[ -x ]` does not. A dead shebang, a syntax error, a
# zero-byte file and a copy truncated half-way through an install all carry the executable
# bit and then fail every invocation — which in a caller that treats a non-zero code as
# "refuse" looks like a gate working perfectly while it read nothing at all.
#
# THE CONTROLS ARE THE POINT — a banner would pass for any stub that prints one. This
# drives the real decision function in every direction it can answer in (clear, missing
# verdict, over the ceiling, carve-out), and the ceiling probe sits ON the measured
# boundary rather than at a comfortable distance from it, so a copy whose constant moved by
# a little fails as surely as one that deleted it.
#
# AND "IT RUNS" IS NOT "IT IS COMPLETE": this block sits near the TOP, so a copy truncated
# below it would still reach this exit. The last line of the file is asserted here.
SELFTEST_OK="pr-comment-clearance: self-test ok"
EOF_SENTINEL="#EOF: pr-comment-clearance.sh is complete to here"
if [ "${1:-}" = "--self-test" ]; then
  [ "$#" -eq 1 ] || usage
  [ -r "$0" ] || {
    echo "self-test: cannot read '$0' to prove it is complete — refusing" >&2; exit 2; }
  [ "$(tail -n 1 "$0")" = "$EOF_SENTINEL" ] || {
    echo "self-test: this file does not end with its completeness sentinel, so it is" >&2
    echo "           truncated or was cut short — the tables and the parser below this" >&2
    echo "           line cannot be assumed to be here. Refusing." >&2; exit 2; }
  TMPD="$(mktemp -d)" || {
    echo "self-test: could not create a temp dir — refusing" >&2; exit 2; }
  trap 'rm -rf "$TMPD"' EXIT
  validate_tables || exit 2

  st_probe() { # <expected-rc> <name> <lines...>
    local want="$1" name="$2"; shift 2
    printf '%s\n' "$@" > "$TMPD/raw"
    render_reply "$TMPD/raw" "$TMPD/rendered"
    decide "$TMPD/rendered" "self-test reply" >/dev/null 2>&1
    [ "$?" -eq "$want" ] || {
      echo "self-test: $name did not answer $want — refusing" >&2; exit 2; }
  }
  # A run of <n> bytes, so a probe sits ON a boundary rather than near it.
  st_pad() { printf '%*s' "$1" '' | tr ' ' 'x'; }

  # The backticks in the probes below are content, not expansions.
  # shellcheck disable=SC2016
  st_probe 0 "a conforming reply" \
    'Round 1 addressed in a1b2c3d.' '' \
    '- Finding 1 — fixed: the path is quoted now.' \
    '- Finding 2 — declined: the dir is mktemp-owned.' '' \
    'Evidence: `foo.test.sh` 41/0.'
  st_probe 1 "an entry with no verdict" \
    'Round 1 addressed in a1b2c3d.' '' \
    '- Finding 1 — the path is quoted now.'
  st_probe 1 "an empty reply" ''
  # `- fixed: ` is 9 ASCII bytes, so the pad puts the entry ON the boundary exactly.
  st_probe 0 "an entry at exactly the ceiling" "- fixed: $(st_pad 609)"
  st_probe 3 "an entry one byte over it"       "- fixed: $(st_pad 610)"
  st_probe 3 "a wall of prose with no entries" "It is all valid. $(st_pad 700)"
  st_probe 0 "a carve-out is never trimmed" \
    "**Security** — the token is logged in plaintext. $(st_pad 900)"

  printf '%s\n' "$SELFTEST_OK"
  exit 0
fi

# --- argument parsing ---------------------------------------------------------
comment=""; kind=""; repo=""; file=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --comment)        comment="${2:-}"; kind="issue";  [ -n "$comment" ] || usage; shift 2 ;;
    --review-comment) comment="${2:-}"; kind="review"; [ -n "$comment" ] || usage; shift 2 ;;
    --repo)           repo="${2:-}";    [ -n "$repo" ] || usage; shift 2 ;;
    --comment-file)   file="${2:-}";    [ -n "$file" ] || usage; shift 2 ;;
    -h|--help)        usage ;;
    *) echo "error: unexpected argument '$1'" >&2; usage ;;
  esac
done

validate_tables || exit 2

TMPD="$(mktemp -d)" || {
  echo "error: could not create a temp dir — refusing (fail closed)" >&2
  exit 2
}
trap 'rm -rf "$TMPD"' EXIT

# --- route 1: a draft on disk, so an author can check before posting -----------
# The cheapest moment to catch a malformed reply is before it is published: an edited
# comment still notifies everyone who was watching, and the reviewer has already read it.
if [ -n "$file" ]; then
  [ -z "$comment" ] && [ -z "$repo" ] || {
    echo "error: --comment-file decides on a local file; it takes no comment id or repo." >&2
    usage
  }
  [ -r "$file" ] || {
    echo "error: cannot read '$file' — a reply this script cannot read is unknown state," >&2
    echo "       and unknown is never clearance. Refusing." >&2
    exit 2
  }
  command -v jq >/dev/null 2>&1 || {
    echo "error: jq not found — the character count cannot be taken. Refusing." >&2
    exit 2
  }
  # `jq -Rs length` counts CODE POINTS, which is what the host reports as a comment's
  # length. INFORMATION ONLY — see the header; nothing below reads it.
  reply_chars="$(jq -Rs 'length' < "$file" 2>/dev/null)" || reply_chars="unknown"
  echo "pr-comment-clearance: $file is $reply_chars characters (information only — no" >&2
  echo "                      exit code in this script is derived from that number)" >&2
  render_reply "$file" "$TMPD/rendered"
  decide "$TMPD/rendered" "'$file'"
  exit $?
fi

# --- route 2: the actual comment, from the host -------------------------------
[ -n "$comment" ] || usage

for tool in gh jq; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "error: $tool not found — the comment cannot be read, so this refuses" >&2
    exit 2
  }
done

if [ -z "$repo" ]; then
  repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" || repo=""
  [ -n "$repo" ] || {
    echo "error: no --repo given and this directory names no repository, so the comment" >&2
    echo "       cannot be identified. Refusing (fail closed)." >&2
    exit 2
  }
fi

case "$kind" in
  issue)  path="repos/$repo/issues/comments/$comment" ;;
  review) path="repos/$repo/pulls/comments/$comment" ;;
  *)      usage ;;
esac

# A FETCH THAT ERRORS IS NOT AN EMPTY COMMENT. Reading a transient 5xx as "no text" is a
# refusal today and would be a clearance the moment anything downstream treated one of
# these codes as benign, so this refuses at exit 2 instead of classifying an empty string.
raw="$(gh api "$path" 2>/dev/null)" || {
  echo "error: could not read comment $comment in $repo — its text is unknown, and" >&2
  echo "       unknown is never clearance. Refusing (fail closed)." >&2
  exit 2
}

url="$(printf '%s' "$raw" | jq -r '.html_url // ""' 2>/dev/null)" || url=""
[ -n "$url" ] || {
  echo "error: could not resolve the URL of comment $comment — the answer would be about" >&2
  echo "       a comment this script cannot identify. Refusing (fail closed)." >&2
  exit 2
}

# An ABSENT body field is a read that did not answer; an EMPTY one is a comment somebody
# left blank. Both refuse, and not with the same code — a blank comment is a real, readable
# one, and telling its author that is more useful than "unknown".
printf '%s' "$raw" | jq -e 'has("body")' >/dev/null 2>&1 || {
  echo "error: comment $comment reports no body field at all, so its text is unknown" >&2
  echo "       rather than empty. Unknown is never clearance. Refusing (fail closed)." >&2
  exit 2
}
printf '%s' "$raw" | jq -r '.body // ""' > "$TMPD/body" 2>/dev/null || {
  echo "error: the text of comment $comment could not be extracted — refusing" >&2
  exit 2
}

# INFORMATION ONLY. Taken from the JSON string's own length, so it is the host's count of
# characters rather than a byte count of a file. Nothing below reads it; see the header.
reply_chars="$(printf '%s' "$raw" | jq -r '(.body // "") | length' 2>/dev/null)" \
  || reply_chars="unknown"
echo "pr-comment-clearance: comment $comment is $reply_chars characters (information" >&2
echo "                      only — no exit code in this script is derived from that" >&2
echo "                      number)" >&2

render_reply "$TMPD/body" "$TMPD/rendered"
decide "$TMPD/rendered" "comment $comment ($url)"
exit $?

# --- completeness sentinel — THIS MUST REMAIN THE LAST LINE OF THIS FILE -------
# `--self-test` asserts that the last line of this file is exactly the line below, which is
# how a truncated copy is told from a complete one. See the header.
#EOF: pr-comment-clearance.sh is complete to here
