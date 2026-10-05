#!/usr/bin/env bash
#
# review-clearance-bodies.test.sh — plugin/scripts/review-clearance.sh against HAND-BUILT
# bodies: what counts as a fence, a container, a code span or a commit token; that prose
# clears nothing; which artifact outranks which; and that the verdict trailer is parsed.
#
# ONE OF THREE. tests/review-clearance.test.sh holds the recorded evidence and the header
# that says what all three exist to pin; tests/review-clearance-gates.test.sh holds the
# modes, the tables and the gates around the classifier. The stubs, the fixture builders
# and the assertion helpers are sourced from tests/review-clearance.lib.sh.
. "$(dirname "$0")/review-clearance.lib.sh"

echo "== an UNBALANCED fence must fail closed, not blank the body =="
# The bypass this section pins: strip_fences used to toggle on every marker with no END
# check, so an ODD count left everything after the marker "inside a fence" and the
# stripped body came back empty — no refusal matched, and the raw text still named the
# head, so the recorded refusal CLEARED. One character, typed into a comment.
#
# The control is the assertion above this line: with BALANCED fences the strip still
# happens, so these cases fail for the unbalance and not because fencing stopped working.
fenced_refusal="$TMP/refusal-one-fence.md"
{ printf '```\n'; cat "$REFUSAL"; } > "$fenced_refusal"
assert "the fenced copy still names the head verbatim (so it COULD clear)" \
  "$(yes_if grep -Fq "$REFUSAL_HEAD" "$fenced_refusal")"
assert "…and carries exactly one fence marker" \
  "$([ "$(grep -c '^```' "$fenced_refusal")" -eq 1 ] && echo 0 || echo 1)"
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$fenced_refusal"
expect "one prepended fence on the recorded refusal -> still refuses" 1
says   "  ...still quoting the reviewer's own words" "Review limit reached"

trailing_refusal="$TMP/refusal-trailing-fence.md"
{ cat "$REFUSAL"; printf '```\n'; } > "$trailing_refusal"
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$trailing_refusal"
expect "an unclosed fence AFTER the refusal -> still refuses" 1

setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file '~~~' 'Review limit reached.' "at $REFUSAL_HEAD")"
expect "an unbalanced tilde fence refuses just the same" 1

# The opening marker's type is carried, so a backtick fence inside a tilde block is
# content rather than a close — otherwise a nested pair drifts the count odd and the case
# above fires on an ordinary review that quotes one fence style inside another.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file \
  "Reviewed $CLEAN_HEAD." \
  '<!-- walkthrough_start -->' \
  '~~~' \
  '```' \
  'review limit reached' \
  '```' \
  '~~~' \
  'No further comments.')"
expect "a backtick pair nested in a tilde block stays balanced -> review" 0
# The same rule where getting it wrong is visible: with the UNCONDITIONAL sentinel between
# the nested markers, a ``` that closed a ~~~ would leave the sentinel outside every block
# (rc=1). The case above cannot show that, because the prose tier it uses is outranked by
# the review marker in the same body whichever side of the fence it lands on.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file \
  "Reviewed $CLEAN_HEAD." \
  '<!-- walkthrough_start -->' \
  '~~~' \
  '```' \
  'rate limited by coderabbit.ai' \
  '```' \
  '~~~')"
expect "…and the opener's TYPE is what closes it, so the sentinel stays quoted" 0

# ...and the CLEARING side of an unbalanced body is not "read it raw", which is what the
# refusal side does. A body whose fences do not balance cannot be rendered, so it
# evidences nothing: the strict rendering is empty and the marker in it is unreachable.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '```' '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD.")"
expect "an unbalanced fence around a review marker -> evidences nothing" 4
# ...and with the marker BEFORE the stray fence, which is the case a stripper that merely
# drops the unterminated tail still clears. "Empty" is the answer, not "everything outside
# the fence": a body that cannot be rendered is a body nothing can be read out of.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." '```' 'and then nothing closes it')"
expect "…and with the marker BEFORE the stray fence, still nothing" 4

echo
echo "== the two renderings must agree on what a FENCE is =="
# A FOURTH DOOR INTO THE SAME BYPASS, and this one needed no unbalanced anything.
# `strip_fences` (the refusal side) stripped any leading whitespace before testing for a
# fence; `strict_body` (the clearing side) treated a line indented four spaces or a tab as
# an INDENTED CODE BLOCK and therefore not a fence. So an INDENTED ``` opened a fence on
# one side and nothing on the other: the unconditional rate-limit sentinel between two such
# markers disappeared from the text the refusal tables read, while the review marker outside
# them survived on the side that clears — and the file's own stated asymmetry (strict is a
# SUBSET of stripped) ran backwards.
#
# The host renders `    ``` ` as three literal backticks, not as a fence, so a human reading
# these bodies SEES the refusal. Each case below hides the sentinel from the refusal tables
# in exactly that way and leaves a review marker in the clear; each was rc=0 before.
marker_and_head=( '<!-- walkthrough_start -->' )
hidden_sentinel() { # <indent-prefix> — the sentinel wrapped in a fence indented by it
  local p="$1"
  body_file "${marker_and_head[@]}" "Reviewed $CLEAN_HEAD." \
    "$p"'```' "$p"'rate limited by coderabbit.ai' "$p"'```'
}
setup "$CLEAN_HEAD"; add_comment coderabbitai "$(hidden_sentinel '    ')"
expect "a FOUR-SPACE indented fence cannot hide the sentinel" 1
says   "  ...and it is the unconditional tier that fired" "DECLINED to review"
setup "$CLEAN_HEAD"; add_comment coderabbitai "$(hidden_sentinel "$(printf '\t')")"
expect "…nor a TAB-indented one" 1
setup "$CLEAN_HEAD"; add_comment coderabbitai "$(hidden_sentinel '>     ')"
expect "…nor a BLOCKQUOTED one indented inside the quote" 1
# The NOT_YET tier is unconditional for the same reason and was reachable the same way.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  '    ```' '    Currently processing new changes in this PR.' '    ```')"
expect "…and an indented fence cannot hide the placeholder either" 1

# THE CONTROL, and it is what stops the four above from passing on a script that simply
# stopped stripping fences: the same indentation, with NO refusal in it, still clears.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  '    ```' '    make test' '    ```')"
expect "…while the same indented block with no refusal in it still clears" 0

# THE BOUNDARY, asserted rather than left to be rediscovered as a bug. Up to THREE spaces
# is a real fence to the host, and a fenced refusal has always been read here as a
# DISCUSSION of one (the fenced-refusal case above) — so these two stay rc=0 by design,
# and they are the reason the fix is "agree with the renderer", not "never strip".
setup "$CLEAN_HEAD"; add_comment coderabbitai "$(hidden_sentinel '   ')"
expect "a THREE-space fence is a real fence, so its content is quotation" 0
setup "$CLEAN_HEAD"; add_comment coderabbitai "$(hidden_sentinel '  > ')"
expect "…as is a fence inside a blockquote indented at most three" 0

echo
echo "== …and agreeing with each other is not agreeing with the HOST =="
# THE ROUND AFTER THE ONE ABOVE. The two renderings were made to agree, and the rule they
# agreed on still was not the host's, three ways — each of which strips text a human can
# read, and each of which therefore fails OPEN. Every case here was rc=0 before.
TAB="$(printf '\t')"

# 1. BLOCKQUOTE CONTAINMENT. A fence opens inside the blockquote it is written in, and the
# host closes it where that quote ends: an opener at depth 1 is not paired with a closer at
# depth 0. This is the reviewer's NATIVE IDIOM rather than a construction — its notices
# arrive inside a `> [!WARNING]` blockquote — so the payload is the RECORDED refusal,
# unaltered, and the only edit is the wrapper.
quoted_fence_refusal="$TMP/refusal-quote-opened-fence.md"
{ printf '<!-- walkthrough_start -->\nReviewed %s.\n> ```\n' "$REFUSAL_HEAD"
  cat "$REFUSAL"; printf '```\n'; } > "$quoted_fence_refusal"
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$quoted_fence_refusal"
expect "a fence OPENED inside a blockquote does not close outside it" 1
says   "  ...quoting the reviewer's own words" "Review limit reached"
# THE CONTROL: the identical body with both markers at the same depth is a real fence, so
# its content is quotation and the marker outside it clears — the boundary above, again.
same_depth_fence="$TMP/refusal-depth0-fence.md"
{ printf '<!-- walkthrough_start -->\nReviewed %s.\n```\n' "$REFUSAL_HEAD"
  cat "$REFUSAL"; printf '```\n'; } > "$same_depth_fence"
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$same_depth_fence"
expect "…while both markers at the same depth ARE a pair, so that clears" 0
# The other half of the same rule, and the half the case above cannot see: the block ENDS
# where the quote ends, so what follows is ordinary text rather than swallowed. Without
# that, this body has an unclosed fence and evidences nothing (rc=4).
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '> ```' '> make test' \
  '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD.")"
expect "…and the quote ending ENDS the block, rather than swallowing the rest" 0
# The third direction of the same rule, and the only one that shows the depths being
# COMPARED rather than just ordered: inside a code block there is no block structure at
# all, so a `> ```' DEEPER than the opener is literal content and closes nothing. Read as
# a close, the real closer below it opens a new block, the body is unbalanced, and the
# sentinel this one quotes leaves the fence.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  '```' 'rate limited by coderabbit.ai' '> ```' '```')"
expect "…and a closer DEEPER than its opener is content, not a close" 0

# 2. TABS ARE COLUMNS. The host expands a tab to the next four-column stop, so 1-3 spaces
# then a tab is indented code. This one reaches ROUTE B, which outranks every refusal
# tier: a comment that merely QUOTES the trailer format validated as a real verdict.
quoted_trailer() { # <indent> — the verdict trailer, indented by it
  body_file 'Quoting the format for the docs:' \
    "$1"'<!-- okf-verdict v1' "$1"'verdict: pass' "$1"'reviewer: qa' \
    "$1""head_sha: $CLEAN_HEAD" "$1"'-->'
}
setup "$CLEAN_HEAD"; add_comment some-new-reviewer "$(quoted_trailer "   $TAB")"
expect "3 spaces + a TAB is column 4, so a quoted trailer stays quoted" 4 \
  --reviewer some-new-reviewer
setup "$CLEAN_HEAD"; add_comment some-new-reviewer "$(quoted_trailer '    ')"
expect "…the four-space control, which was already literal" 4 --reviewer some-new-reviewer
# THE CONTROL that keeps this about INDENTATION: unindented, the same block validates.
setup "$CLEAN_HEAD"; add_comment some-new-reviewer "$(quoted_trailer '')"
expect "…while the same trailer unindented is a real verdict" 0 --reviewer some-new-reviewer
# And the tab that the blockquote marker eats: one column of it belongs to the marker, so
# `>` TAB SPACE is three columns of indentation (a fence) and `>` TAB SPACE SPACE is four
# (literal text, and the sentinel in it must be read).
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  ">$TAB "'```' ">$TAB "'rate limited by coderabbit.ai' ">$TAB "'```')"
expect "a blockquote marker eats ONE column of the tab after it" 0
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  ">$TAB  "'```' ">$TAB  "'rate limited by coderabbit.ai' ">$TAB  "'```')"
expect "…so one more space is column 4, and the sentinel is literal text" 1
# The other consumer of the same measurement: four columns in, a `>` is not a quote marker
# at all, it is a literal `>` inside an indented code block — so a review marker written
# there is quoted text and evidences nothing.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '    > <!-- walkthrough_start -->' \
  "    > Reviewed $CLEAN_HEAD.")"
expect "a > four columns in is literal text, not a blockquote marker" 4
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '> <!-- walkthrough_start -->' \
  "> Reviewed $CLEAN_HEAD.")"
expect "…while the same lines merely QUOTED are a review, and clear" 0

# 3. THE CLOSING MARKER IS NOT JUST A MARKER. A closer may be no shorter than its opener
# and may carry no info string; reading either as a close also turns an odd number of
# markers into an even one, which is how it slipped past the unbalanced-fence net too.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  '````' 'rate limited by coderabbit.ai' '```')"
expect "a four-backtick fence is not closed by three" 1
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  '```' 'rate limited by coderabbit.ai' '```js')"
expect "…nor by a closing fence carrying an info string" 1
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  '```a`b' 'rate limited by coderabbit.ai' '```')"
expect "…and a backtick opener whose info string holds a backtick opens nothing" 1
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  '``' 'rate limited by coderabbit.ai' '``')"
expect "…and two backticks are not a fence at all" 1
# THE CONTROLS, so none of the four passes on a script that stopped pairing fences: a
# longer closer, and an opener that legitimately carries an info string, both still pair.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  '````' 'rate limited by coderabbit.ai' '`````')"
expect "…while a LONGER closer does close it, so that stays quotation" 0
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  '```js' 'rate limited by coderabbit.ai' '```')"
expect "…as does an OPENER carrying an info string, which is legal" 0

echo
echo "== the CONTAINERS a fence lives in, which the machine did not model =="
# THE SAME DEFECT A SIXTH TIME, and this is the round it stopped being a list. The fence
# rules were exact for what they modelled and modelled no CONTAINERS, so a construct that
# changes what ``` MEANS put the recorded refusal back behind a fence the host does not
# see. Inside a raw-HTML block the content is HTML: ``` is three backticks a reader can
# see, and the refusal between them is on the page. `<details>`/`<summary>` is the shape
# the recorded fixture is itself built from, so this is the vendor's idiom, not a
# construction. Each case is answered by the SECOND reading of the block structure, and
# the refusal side takes the union of the two.
for tag in details pre div table section blockquote-ish-unknown-tag; do
  setup "$CLEAN_HEAD"
  add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' \
    "Reviewed $CLEAN_HEAD." '' "<$tag>" '```' 'rate limited by coderabbit.ai' '```' "</$tag>")"
  expect "a refusal inside a <$tag> block -> refuse, it is on the page" 1
done
says   "  ...and it is the unconditional tier that fired" "DECLINED to review"
# …and the whole recorded refusal, unaltered, inside the vendor's own <details> idiom.
setup "$REFUSAL_HEAD"
{ printf '<!-- walkthrough_start -->\nReviewed %s.\n\n<details>\n<summary>d</summary>\n```\n' \
    "$REFUSAL_HEAD"; cat "$REFUSAL"; printf '```\n</details>\n'; } > "$TMP/details.md"
add_comment coderabbitai "$TMP/details.md"
expect "the RECORDED refusal inside <details> -> refuse" 1
says   "  ...quoting the reviewer's own words" "Review limit reached"
# THE CONTROL, and it is the one that keeps this from being "never strip a fence": with no
# HTML block around it the same three lines ARE a fenced quotation and still clear.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  '' '```' 'rate limited by coderabbit.ai' '```')"
expect "…while the same fence with no HTML block around it is quotation" 0
# …and a raw-HTML block ends at a blank line, so a fence after one is a fence again.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  '' '<div>' 'x' '' '```' 'rate limited by coderabbit.ai' '```')"
expect "…and a blank line ends the HTML block, so the next fence quotes again" 0

# A LIST ITEM IS A CONTAINER TOO: the fence dies with the item. The host closes the block
# at the end of the item, so the text after it is a paragraph a human reads; a machine that
# carries the fence past the item's end pairs it with a LATER marker and swallows that
# paragraph — and an odd number of markers becomes even, which slips the unbalanced net.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  '' '- item' '  ```' '  x' '' 'rate limited by coderabbit.ai' '' '  ```')"
expect "a fence closed by the END of its list item -> refuse" 1
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  '' '- item' '  ```' '  rate limited by coderabbit.ai' '  ```')"
expect "…while a fence that opens and closes INSIDE the item is quotation" 0
# The opener may be behind the marker itself, which used to be no fence at all — so a
# review marker inside a block the host renders as CODE was read as the vendor's claim.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '- ```' '  <!-- walkthrough_start -->' \
  "  Reviewed $CLEAN_HEAD." '  ```')"
expect "a marker inside a fence opened BEHIND a list marker -> not evidence" 4
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '1. ```' '   <!-- walkthrough_start -->' \
  "   Reviewed $CLEAN_HEAD." '   ```')"
expect "…and behind an ORDERED list marker too" 4

echo
echo "== an inline code SPAN is text a human reads, so it is not evidence =="
# THIS ROUND'S REVIEW DEMONSTRATED IT ON ITS OWN DRAFT: spelling the vendor's marker
# between backticks to describe it cleared route C, and the verdict had to be mangled
# before it could be posted. Two things stop it, because one construct is invisible to
# each: the table rows are anchored to a WHOLE line, which a span inside a line breaks;
# and the strict rendering drops lines inside a span that opened on an earlier line, which
# an anchor cannot see.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file 'The marker `<!-- walkthrough_start -->` is emitted' \
  "by the vendor. Reviewed $CLEAN_HEAD.")"
expect "the marker inside a span, in a sentence -> not evidence" 4
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '`<!-- walkthrough_start -->`' "Reviewed $CLEAN_HEAD.")"
expect "…nor a span holding nothing else, alone on its line" 4
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file 'the marker is `' '<!-- walkthrough_start -->' \
  '` as emitted' "Reviewed $CLEAN_HEAD.")"
expect "…nor a marker on its own line inside a MULTI-LINE span" 4
# THE CONTROLS: the marker as the vendor actually emits it, alone on its line, still
# clears — including inside the blockquote its notices arrive in.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD.")"
expect "…while the marker alone on its line IS the vendor's claim" 0
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '> <!-- walkthrough_start -->' "> Reviewed $CLEAN_HEAD.")"
expect "…and so is one inside the blockquote its notices arrive in" 0

echo
echo "== the six branches a per-branch mutant sweep found unguarded =="
# EACH OF THESE WAS A MUTANT THAT SURVIVED, and a survivor is the sweep working: removing
# the branch left both suites green, so nothing here was asserting it. Two are gaps that
# would clear an unreviewed PR, two are OVER-correction guards (the refusal side may not
# start eating quotations), and two are the union/intersection halves themselves.
#
# 1. A LIST MARKER'S WIDTH. `1.` and `1)` are two columns, so a fence behind one opens at a
#    different container column than a fence behind `-`. Spelled with TILDES on purpose: a
#    backtick version is caught by the code-span parity rule instead, which would make this
#    a test of the wrong branch.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '1. ~~~' '   <!-- walkthrough_start -->' \
  "   Reviewed $CLEAN_HEAD." '1. ~~~')"
expect "an ORDERED marker is as wide as it is written -> not evidence" 4

# 2. A LIST MARKER IS NOT A QUOTE LEVEL. Counting it as one would close a fence at the first
#    line that is not itself a marker — so a fenced quotation inside one item would leak its
#    contents to the refusal tables. An OVER-correction guard: this body must still clear.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '- ```' '  rate limited by coderabbit.ai' '  ```' \
  '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD.")"
expect "a fence opened BEHIND a marker and closed in the item is quotation" 0

# 3. A LIST ITEM ENDS. If it never did, every later top-level fence would be treated as
#    living in the last item seen and closed by the first line at column 0 — turning a
#    perfectly ordinary quotation back into a refusal. The other OVER-correction guard.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '- item' '' '<!-- walkthrough_start -->' \
  "Reviewed $CLEAN_HEAD." '' '```' 'rate limited by coderabbit.ai' '```')"
expect "a quotation AFTER a list ends is still a quotation" 0

# 4. A CLOSING TAG OPENS A RAW-HTML BLOCK TOO — CommonMark counts `</x>` as a block start,
#    and reading it as ordinary text puts the refusal back behind a fence the host does not
#    render as one.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  '' '</div>' '```' 'rate limited by coderabbit.ai' '```')"
expect "a CLOSING tag opens a raw-HTML block -> refuse" 1

# 5. EITHER READING BEING UNBALANCED IS ENOUGH. Reading B closes the fence at the end of the
#    list item, which leaves its closing marker to open a block nothing closes — so B cannot
#    read this body even though A can. An unreadable body clears NOTHING; taking only A's
#    word for it clears this one.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  '' '- item' '  ```' '  x' 'y' '  ```')"
expect "reading B unbalanced, reading A not -> clears nothing" 4

# 6. THE CLEARING SIDE IS THE INTERSECTION, and this is the shape that proves it is not just
#    reading A with extra steps. Two raw-HTML blocks each swallow one fence marker, so the
#    two readings PAIR THE REMAINING MARKERS DIFFERENTLY: the marker and the head sit
#    OUTSIDE every block in reading A and INSIDE one in reading B. The host agrees with B —
#    the first block ends at its blank line, so the next ``` really does open a fence and
#    the marker under it is literal text a human reads.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<div>' '```' '' '```' '<!-- walkthrough_start -->' \
  "Reviewed $CLEAN_HEAD." '```' '<div>' '```' '' '```' 'z' '```')"
expect "a marker only reading A calls markup -> not evidence" 4

echo
echo "== CRLF: the host does not see the carriage return, and neither may this =="
# A BODY FROM A WINDOWS CLIENT ARRIVES WITH \r ON EVERY LINE, and awk's record is split on
# \n alone, so the \r is the last character of every line the machine reads. Two rules
# nearly regressed on it in this round's rewrite, both toward FALSE REFUSALS rather than
# false clearances — an over-correction is still a defect, and this is where it hides.
# `\r` is whitespace to a POSIX character class and is not `[ \t]`, which is the difference.
crlf() { local f; f="$(mktemp "$TMP/crlf.XXXXXX")"; printf "$1" > "$f"; printf '%s' "$f"; }
setup "$CLEAN_HEAD"
add_comment coderabbitai \
  "$(crlf "<!-- walkthrough_start -->\r\nReviewed $CLEAN_HEAD.\r\n\r\n\`\`\`\r\nrate limited by coderabbit.ai\r\n\`\`\`\r\n")"
expect "a CRLF fence PAIRS, so its refusal is quotation" 0
setup "$CLEAN_HEAD"
add_comment coderabbitai \
  "$(crlf "<!-- walkthrough_start -->\r\nReviewed $CLEAN_HEAD.\r\n\r\n<div>\r\nx\r\n\r\n\`\`\`\r\nrate limited by coderabbit.ai\r\n\`\`\`\r\n")"
expect "…and a CRLF blank line ENDS a raw-HTML block" 0
# The other direction is unchanged: CRLF does not weaken any of it.
setup "$CLEAN_HEAD"
add_comment coderabbitai \
  "$(crlf "<!-- walkthrough_start -->\r\nReviewed $CLEAN_HEAD.\r\n\r\n<details>\r\n\`\`\`\r\nrate limited by coderabbit.ai\r\n\`\`\`\r\n</details>\r\n")"
expect "…while a CRLF refusal inside <details> still refuses" 1
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(crlf "<!-- walkthrough_start -->\r\nReviewed $CLEAN_HEAD.\r\n")"
expect "…and a CRLF clean review still clears" 0

echo
echo "== the union is an AND-gate, and both readings were wrong the same way =="
# THE ROUTE THAT FALSIFIED THE WHOLE CONSTRUCTION. The refusal side keeps a line either
# reading keeps, which was argued to make a crude reading cost at most a FALSE refusal.
# It does not: the readings can be wrong together, and then their union is wrong too.
#
#     - ```
#     - Review limit reached...
#     - ```
#
# Reading A does not model list items at all, so its fence stays open. Reading B did model
# them but ended an item only on a DEDENT, and a sibling marker does not dedent — so B
# agreed, the union agreed, and the refusal was gone. GitHub closes the fence at the end of
# the item and renders the middle line as an ordinary bullet, which `host-rendering.txt`
# records. Every bullet spelling and both ways an item ends:
SIB_REFUSAL='Review limit reached. Next included review available in 44 minutes.'
for m in '-:a dash' '*:a star' '+:a plus' '1.:an ordered marker' '10.:a two-digit marker'; do
  setup "$REFUSAL_HEAD"
  add_comment coderabbitai "$(body_file "${m%%:*} \`\`\`" "${m%%:*} $SIB_REFUSAL" "${m%%:*} \`\`\`")"
  expect "a refusal in sibling list items -> refusal (${m#*:})" 1
done
# …and the same shape reaching a CLEARANCE, which is what it cost: the refusal vanished, so
# a contentless approval at that head had nothing to lose to.
setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file '- ```' "- $SIB_REFUSAL" '- ```')"
add_review coderabbitai APPROVED "$REFUSAL_HEAD" "$EMPTY_BODY"
expect "…so a held approval no longer clears past it" 1
# The list item also ends by DEDENT, which is the branch that was already there — asserted
# so removing either one is red, not just the new one.
setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file '- ```' '  quoted' "$SIB_REFUSAL")"
expect "…and a dedent out of the item ends it too" 1
# A blank line does not end a list, so the fence still dies at the next marker.
setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file '- ```' '' "- $SIB_REFUSAL" '- ```')"
expect "…and a blank line between the bullets changes nothing" 1
# THE TWO OVER-CORRECTION CONTROLS, because a rule that ends every list item ends the ones
# the host does not. A DEEPER marker opens a nested item and ends nothing, and a plain
# continuation line is still inside the fence — the host quotes both, so this file reads
# both as a discussion of a refusal rather than as one.
setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file '- ```' "  - $SIB_REFUSAL" '  ```')"
expect "a DEEPER marker nests rather than ending the item -> quoted" 4
setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file '- ```' "  $SIB_REFUSAL" '  ```')"
expect "…and a continuation line is still inside the fence -> quoted" 4
# …and the top-level fence this file has always read as a quotation is untouched.
setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file '```' "$SIB_REFUSAL" '```')"
expect "…and a plain fenced refusal is still a discussion of one" 4

echo
echo "== a raw-HTML block ends where its container does =="
# The other block that outlives its container. `<details>` inside a blockquote opened a
# raw-HTML block that ended only at a blank line, so it ran to the end of the body — and a
# raw-HTML block is the one state in reading B that makes it KEEP a line reading A drops,
# which is the direction that lets something clear.
setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file '> <details>' '- ```' "- $SIB_REFUSAL" '- ```')"
expect "an HTML block opened in a quote does not outlive the quote" 1
setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file '- <details>' '- ```' "- $SIB_REFUSAL" '- ```')"
expect "…nor one opened in a list item outlive the item" 1
# The control: with no container to leave, it still ends at a blank line and nowhere else.
setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file '<details>' '```' "$SIB_REFUSAL" '```' '</details>')"
expect "…and inside one that never ends, the fence is still literal HTML" 1

echo
echo "== the over-correction guards: a container the host does NOT end =="
# EVERY RULE ADDED THIS ROUND ENDS SOMETHING EARLIER, and a rule that ends a container the
# host keeps open turns a quotation into a refusal. That is not a merge, so the battery
# above does not assert on it — which is exactly why these cases are here by name. Each
# body is one the host puts in a code block (recorded in `host-rendering.txt` as `quoted`),
# so the answer must be 4, "an artifact carrying no evidence", and not 1.
#
# THEY ARE ALSO WHAT READING B'S TIGHTENING RULES BUY, and the honest accounting is worth
# stating: reading B keeping a line only reaches the CLEARING side when reading A keeps it
# too, and A already reads every fence these rules reveal. So bounding a raw-HTML block
# closes no route — it removes false refusals, and these assert that it does.
setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file '- ```' '' "  $SIB_REFUSAL" '  ```')"
expect "a blank line does not end a list item -> still quoted" 4
setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file '> <details>' '```' "$SIB_REFUSAL" '```')"
expect "…leaving the quote ends its HTML block, so the fence is a fence" 4
setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file '- <details>' '- ```' "  $SIB_REFUSAL" '  ```')"
expect "…and leaving the list item ends its HTML block too" 4
# The control for all three: the same HTML block with nothing to leave still swallows the
# fence, so the words really are on the page and this is a refusal.
setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file '<details>' '```' "$SIB_REFUSAL" '```')"
expect "…while an HTML block nobody leaves still makes the fence literal" 1

echo
echo "== what RENDERS is the host's answer, including where it surprises =="
# Three constructs where the rule "remove the markup, require a letter" needs the host to
# say where markup ends, and got a different answer than the specification would give.
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$REFUSAL"
add_review coderabbitai COMMENTED "$REFUSAL_HEAD" "$(body_file '<https://example.com/a>')"
expect "an autolink is a claim: the page shows the URL" 0
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$REFUSAL"
add_review coderabbitai COMMENTED "$REFUSAL_HEAD" "$(body_file '<![CDATA[a > b]]>')"
expect "…and so is what the host leaves after a CDATA it does not honour" 0
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$REFUSAL"
add_review coderabbitai COMMENTED "$REFUSAL_HEAD" "$(body_file '<!-- a > b -->')"
expect "…while a comment really does run to its own terminator" 1
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$REFUSAL"
add_review coderabbitai COMMENTED "$REFUSAL_HEAD" "$(body_file '[][r]' '' '[r]: /x')"
expect "…and a reference link with an empty label draws nothing" 1
# A reference definition is SKIPPED, scanner state and all, and reasoning says that is a
# bug: the line could also open a multi-line construct, which would then never close. The
# host says otherwise — given `   [a]: /b<!--` the destination swallows the opener and the
# following lines are VISIBLE — so skipping is what the host does, and preserving the state
# would read a body the host draws as a blank page. Recorded as `c-link-ref-def-swallows-open`.
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$REFUSAL"
add_review coderabbitai COMMENTED "$REFUSAL_HEAD" \
  "$(body_file '   [a]: /b<!--' 'lgtm' '-->')"
expect "…and the destination swallows an opener, as it does on the host" 0

echo "== a run of hex is not a commit unless the whole token is one =="
# `refusal_concerns_head` demotes a refusal that names some OTHER commit, so that a PR
# refused once can recover. It read any 7-40 character hex run as a commit — and the
# reviewer stamps its own refusals with a UUID run id, whose fields are hex runs of 8 and
# 12. The recorded fixture carries one. So any refusal with a run id read as being about
# another commit and was dropped before it was weighed.
UUID_LINE='**Run ID**: `f4981ca2-1bc7-4edf-9bb4-fd2f74e3693a`'
setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file 'Currently processing new changes in this PR.' '' "$UUID_LINE")"
add_review coderabbitai APPROVED "$REFUSAL_HEAD" "$EMPTY_BODY"
expect "a UUID does not make a refusal be about another commit" 1
setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file 'Review limit reached.' '' "$UUID_LINE")"
add_review coderabbitai APPROVED "$REFUSAL_HEAD" "$EMPTY_BODY"
expect "…for the declined tier as well as the placeholder" 1
# THE CONTROL, and it is the property the demotion exists for: a refusal that really does
# name another commit still loses to an approval at this head, so a PR can recover.
setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file 'Review limit reached.' "Reviewing $OTHER_SHA." )"
add_review coderabbitai APPROVED "$REFUSAL_HEAD" "$EMPTY_BODY"
expect "…while a refusal naming a REAL other commit still loses" 0
# …and the same tokenisation is route C's pin, where losing a token costs a clearance and
# never grants one. A head spelled as one field of a longer identifier is not the head.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "run-$CLEAN_HEAD-2")"
expect "…and a head embedded in a longer identifier does not pin route C" 4
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "reviewed $CLEAN_HEAD.")"
expect "…while the head as a token of its own still does" 0

echo "== prose no longer clears anything =="
# ROUTE 3 OF THE FOURTH REVIEW ROUND. The evidence table used to hold PROSE, matched as an
# unanchored substring: `i (have )?reviewed`, `(lgtm|looks good to me)`,
# `(changes requested|requesting changes)`, `(no )?actionable comments`. That is the exact
# defect this same file had already fixed for the verdict trailer. Quoted approvals
# cleared, NEGATED sentences matched, and because refusal prose lost to it, a quota
# refusal carrying one such phrase cleared. Every row of prose is gone; what is left is
# the vendor's own machine-emitted HTML marker.
while IFS= read -r prose; do
  [ -n "$prose" ] || continue
  setup "$CLEAN_HEAD"; add_comment coderabbitai "$(body_file "$prose")"
  expect "prose: '$(printf '%.32s' "$prose")…' -> not evidence" 4
done <<PROSE
I have reviewed $CLEAN_HEAD and it is fine.
LGTM — looks good to me, $CLEAN_HEAD.
Approved this pull request at $CLEAN_HEAD.
Reviewed $CLEAN_HEAD — nothing to flag.
No actionable comments were generated in the review of $CLEAN_HEAD.
Changes requested on $CLEAN_HEAD.
Review complete for $CLEAN_HEAD.
> Approved. Reviewed $CLEAN_HEAD.
Unreviewed $CLEAN_HEAD — nobody has looked at this.
No changes requested, because nothing was read ($CLEAN_HEAD).
PROSE
# THE CONTROL for all ten: the same account, the same head, the reviewer's own marker.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD.")"
expect "…while the reviewer's own machine marker clears" 0

# Every row of the marker table, one at a time. Three of the nine prose rows it replaced
# were ever exercised, which is how the negated sentences above went unnoticed.
for marker in walkthrough_start recent_review_start final_review_risk_start; do
  setup "$CLEAN_HEAD"
  add_comment coderabbitai "$(body_file "<!-- $marker -->" "between 6fca618a and $CLEAN_HEAD")"
  expect "the '$marker' marker is a review" 0
done

# THE FOURTH ROW IS GONE, AND THIS IS WHAT KEEPS IT GONE. `review_stack_entry_start` wraps
# a "Review Change Stack" image and a utm_campaign link — a PROMOTIONAL BANNER the vendor
# emits around a review rather than evidence that one happened, which is precisely what
# this table's own admission rule excludes ("nothing that a placeholder or a banner could
# carry"). Measured over all 35 PRs here, removing the row changed 0 outcomes.
assert "the banner marker really is in the recorded clean review" \
  "$(yes_if grep -Fq '<!-- review_stack_entry_start -->' "$CLEAN")"
assert "…and what it wraps really is a promotion, not a review section" \
  "$(yes_if grep -q 'utm_campaign' <<<"$(grep -A3 -F '<!-- review_stack_entry_start -->' "$CLEAN")")"
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- review_stack_entry_start -->' \
  "between 6fca618a and $CLEAN_HEAD")"
expect "the vendor's BANNER marker alone is not a review" 4
# ...and the control, which is why deleting the row cost nothing: the recorded review that
# carries that banner carries three real markers as well, and still clears.
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
expect "…while the recorded review carrying it still clears on the others" 0
# ...and a marker the vendor does not emit is not one, so the table is not a catch-all.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_end -->' "at $CLEAN_HEAD")"
expect "a closing marker is not a review marker" 4
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- pre_merge_checks_walkthrough_start -->' "at $CLEAN_HEAD")"
expect "a different marker ending the same way is not one" 4

echo
echo "== a marker is not a pin: route C still has to name THIS head =="
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $OTHER_SHA.")"
expect "the reviewer's marker naming another commit -> stale" 4
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' 'Looks fine to me.')"
expect "the reviewer's marker naming no commit -> unpinnable" 4

# A SHA inside a URL is a link, not the artifact claiming to have read that commit. It
# used to pin, which is how an artifact quoting a compare range passed.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' \
  "See https://github.com/acme/widgets/commit/$CLEAN_HEAD for context.")"
expect "the head appearing only inside a URL does not pin" 4
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' \
  "See https://github.com/acme/widgets/commit/$CLEAN_HEAD — reviewed $CLEAN_HEAD.")"
expect "…while the same SHA as a bare token does" 0

echo
echo "== shape 2b: an artifact that is NEITHER a review nor a refusal clears nothing =="
# THE DEFAULT-ALLOW THIS SECTION EXISTS TO PIN, and it needed no attacker: positive review
# evidence was never REQUIRED, so the classifier asked only "is this a refusal" and cleared
# everything else that named the head. The reviewer publishes exactly such an artifact on
# essentially every PR, minutes before it has read anything.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file \
  '<!-- This is an auto-generated comment: summarize by coderabbit.ai -->' \
  '> [!NOTE]' \
  '> Currently processing new changes in this PR. This may take a few minutes, please wait...' \
  '>' \
  "> Reviewing files that changed from the base of the PR and between 6fca618a and $CLEAN_HEAD.")"
expect "the 'currently processing' placeholder -> NOT a review" 1
says   "  ...and says the reviewer has not finished" "has NOT FINISHED reviewing"

setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file "I have not reviewed $CLEAN_HEAD yet.")"
expect "a bot saying it has not reviewed it yet -> NOT a review" 1

setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file "Thanks for the ping — $CLEAN_HEAD is on my list. 🐰")"
expect "a reviewer artifact with no evidence of a review -> refuse" 4
says   "  ...saying what is missing, not that nothing is there" "no evidence"

setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file "Thanks for the ping — $CLEAN_HEAD is on my list." \
  '<!-- walkthrough_start -->')"
expect "…and the same artifact WITH the review marker still clears" 0

# "I am still working" is a claim about COMPLETION, so it outranks a marker sitting
# elsewhere in the same body rather than losing to it — unlike refusal PROSE, which loses
# (the section on the auto-incremental notice, below).
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file "Currently processing new changes in this PR." \
  '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD.")"
expect "…but a placeholder outranks a review marker beside it" 1

echo
echo "== shape 3: no reviewer signal at all =="
setup "$CLEAN_HEAD"
expect "nothing on the PR -> no review, and no clearance" 3
says   "  ...and says an absent review is not a pass" "NOT a pass"

setup "$CLEAN_HEAD"; add_comment teammate "$(body_file "lgtm, ship it $CLEAN_HEAD")"
expect "only a bystander's approval -> no review" 3

setup "$CLEAN_HEAD"; AUTHOR="coderabbitai"; add_comment coderabbitai "$CLEAN"
expect "the PR's own author cannot review it" 3

setup "$CLEAN_HEAD"; AUTHOR="coderabbitai"
add_review coderabbitai APPROVED "$CLEAN_HEAD" "$EMPTY_BODY"
expect "…nor by approving its own PR through the API" 3

setup "$CLEAN_HEAD"; add_comment dev "$CLEAN"
expect "the implementing author's own artifact -> not independent" 3

# AND A MISSING AUTHOR LOGIN MUST NOT SILENTLY SWITCH THAT RULE OFF. The meta guard
# required url / head_sha / pr_number and not the author, so an absent or empty login left
# both author comparisons testing against "" — which no login equals, so the two `continue`s
# that enforce SCHEMA.md clause 8 never fired and the reviewer cleared its own PR. A PR
# always has an author; not being told who it is is unknown state, not a green light.
setup "$CLEAN_HEAD"; AUTHOR=""; add_comment coderabbitai "$CLEAN"
expect "an EMPTY author login -> refuse, never clearance" 2
says   "  ...naming the rule it cannot apply" "SCHEMA.md, clause 8"
setup "$CLEAN_HEAD"; AUTHOR=""; add_review coderabbitai APPROVED "$CLEAN_HEAD" "$EMPTY_BODY"
expect "…and the same through the API route" 2
# The author field absent altogether (a deleted account), not merely empty.
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"; write_pr
"$REAL_JQ" '.author = null' "$FIX/pr_json" > "$FIX/pr_json.n" && mv "$FIX/pr_json.n" "$FIX/pr_json"
LAST_OUT="$("$SCRIPT" 42 2>&1)"; rc=$?
assert "a null author object -> refuse, never clearance" \
  "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"
# THE CONTROL: the identical fixture with an author who is not the reviewer clears, so the
# three above fail for the missing login and not because the fixture stopped working.
setup "$CLEAN_HEAD"; AUTHOR="dev"; add_comment coderabbitai "$CLEAN"
expect "…while the same PR with a real author clears" 0

echo
echo "== the REVIEWERS login column, which had no assertions at all =="
# Column 1 used to hold `greptile.*` and `(qodo|codium).*` — matched whole-string, but
# ending in `.*`, so any login STARTING with the vendor's name passed as the vendor. The
# column is now a list of exact logins, and these cases are what says so: each stranger
# below publishes a review object that would otherwise clear outright.
for stranger in greptile-evil qodo-attacker codiumsquatter coderabbitai-evil \
                sourcery-ai-not random-person; do
  setup "$CLEAN_HEAD"; add_review "$stranger" APPROVED "$CLEAN_HEAD" "$EMPTY_BODY"
  expect "a stranger's account ('$stranger') is not the vendor" 3
done
# THE CONTROL: every login the table really does carry, same fixture, clears. Without
# this, the six above would pass just as well if the table matched nobody at all.
for vendor in coderabbitai sourcery-ai greptile-apps qodo-merge-pro \
              codiumai-pr-agent-pro ellipsis-dev; do
  setup "$CLEAN_HEAD"; add_review "$vendor" APPROVED "$CLEAN_HEAD" "$EMPTY_BODY"
  expect "…while '$vendor' is a reviewer this table knows" 0
done
# The host's "[bot]" suffix is the same account under a different endpoint's spelling.
setup "$CLEAN_HEAD"; add_review 'coderabbitai[bot]' APPROVED "$CLEAN_HEAD" "$EMPTY_BODY"
expect "…and the [bot] spelling is the same account" 0

echo
echo "== a review must be pinned to the CURRENT head =="
setup "0000000000000000000000000000000000000000"; add_comment coderabbitai "$CLEAN"
expect "a review of an earlier commit -> stale, not clear" 4

setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
expect "the caller's verified head still matches -> clear" 0 --head "$CLEAN_HEAD"
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
expect "the head moved since verification -> refuse" 4 --head "0000000000000000000000000000000000000000"
says   "  ...and says the head moved" "head moved"

# An abbreviated SHA is how a reviewer often names the commit; it must pin just as well,
# and a DIFFERENT commit that merely shares no prefix must not.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' \
  "Reviewed ${CLEAN_HEAD:0:8} — nothing to flag.")"
expect "an abbreviated head SHA still pins" 0
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' \
  "Reviewed deadbeefdeadbeef — nothing to flag.")"
expect "some other commit does not pin" 4

echo
echo "== a later real review outranks an earlier refusal =="
# The quota resets and the reviewer comes back. Both artifacts sit on the PR; the review
# is the one that decides, or a PR could never recover from having been skipped once.
setup "$CLEAN_HEAD"; add_comment coderabbitai "$REFUSAL"; add_comment coderabbitai "$CLEAN"
expect "refusal then review -> clear" 0
setup "$CLEAN_HEAD"; add_comment coderabbitai "$REFUSAL"
add_review coderabbitai APPROVED "$CLEAN_HEAD" "$EMPTY_BODY"
expect "…and a later review OBJECT outranks it too" 0
# The boundary of that rule is the section on empty review objects above: a refusal naming
# THIS head is not an old refusal, and nothing contentless outranks it.

echo
echo "== a refusal must be WEIGHED, not dropped before anything reads it =="
# THE RANKING IS ONLY AS GOOD AS THE SET OF REFUSALS THAT REACH IT. Three ways a refusal
# never reached it, each ending in the same rc=0 over a contentless approval at the head.
#
# 1. THE REFUSAL THAT NAMES NO COMMIT. Deciding "does this refusal concern the head" by
# whether it NAMES the head reads a refusal that pins to nothing as a refusal of some other
# commit. The reviewer's own placeholder is exactly that: it says it is still working and,
# in its shortest form, names nothing at all.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file 'Currently processing new changes in this PR.')"
add_review coderabbitai APPROVED "$CLEAN_HEAD" "$EMPTY_BODY"
expect "a placeholder naming no commit is not an OLD refusal" 1
says   "  ...and it is the not-yet tier that fired" "NOT FINISHED"
# THE CONTROL, and it is the recovery property this whole ordering exists for: a refusal
# that names a DIFFERENT commit still loses to the empty approval at this head.
setup "$CLEAN_HEAD"; add_comment coderabbitai "$REFUSAL"
add_review coderabbitai APPROVED "$CLEAN_HEAD" "$EMPTY_BODY"
expect "…while a refusal naming ANOTHER commit still loses to it" 0

# 2. THE REFUSAL PUBLISHED IN A STATE THAT CANNOT CLEAR. The submitted-state filter ran
# BEFORE the refusal tables, so a refusal filed as a `DISMISSED` or `PENDING` review object
# was discarded unread. A state that cannot CLEAR is not a state that cannot REFUSE.
for st in DISMISSED PENDING pending; do
  setup "$REFUSAL_HEAD"; add_review coderabbitai "$st" "$REFUSAL_HEAD" "$REFUSAL"
  add_review coderabbitai APPROVED "$REFUSAL_HEAD" "$EMPTY_BODY"
  expect "a refusal filed as a '$st' review object is still a refusal" 1
done
# THE CONTROL: the same non-submitted state carrying a REAL review body still evidences
# nothing, which is the rule that section pins — it must not have become a clearing state.
setup "$CLEAN_HEAD"; add_review coderabbitai DISMISSED "$CLEAN_HEAD" "$CLEAN"
expect "…while a DISMISSED review object still clears nothing" 3

# 3. THE ARTIFACT NOBODY CAN ATTRIBUTE. An artifact whose author the API reported as `null`
# was skipped before TEST 1, so a refusal posted by one was never weighed — and "skip it"
# is also the wrong answer for the question the login decides, which is both whether it
# counts AND whether clause 8 excludes it. Unreadable state, not irrelevant state.
setup "$CLEAN_HEAD"; add_null_comment "$REFUSAL"
add_review coderabbitai APPROVED "$CLEAN_HEAD" "$EMPTY_BODY"
expect "an artifact with no author login is unreadable state" 2
says   "  ...saying what could not be answered about it" "no author login"
# THE CONTROL: the identical body from a named account that is NOT the reviewer is merely
# ignored, so this is about the missing field and not about the body.
setup "$CLEAN_HEAD"; add_comment teammate "$REFUSAL"
add_review coderabbitai APPROVED "$CLEAN_HEAD" "$EMPTY_BODY"
expect "…while the same body from a named stranger is just ignored" 0

echo
echo "== nothing clears until every artifact has been read =="
# WHY THERE IS NO `exit 0` IN THE CLASSIFIER LOOP. Ranking inside it ranked by the order
# the host streamed the artifacts in — review objects, then comments — so the file's claim
# that a refusal is weighed before a clearance held only for the shapes that were read last.
# Both orders of the same two artifacts must give the same answer.
setup "$REFUSAL_HEAD"
add_review coderabbitai COMMENTED "$REFUSAL_HEAD" "$REFUSAL"
add_review coderabbitai APPROVED  "$REFUSAL_HEAD" "$EMPTY_BODY"
expect "refusal first, then the empty approval -> refuse" 1
setup "$REFUSAL_HEAD"
add_review coderabbitai APPROVED  "$REFUSAL_HEAD" "$EMPTY_BODY"
add_review coderabbitai COMMENTED "$REFUSAL_HEAD" "$REFUSAL"
expect "…and the same two in the other order -> the same answer" 1
# The sharper form of the same property: a clearance streamed BEFORE something this script
# cannot read used to exit 0 without ever reaching it.
setup "$CLEAN_HEAD"
add_review coderabbitai COMMENTED "$CLEAN_HEAD" "$CLEAN"
add_null_comment "$(body_file 'anything at all')"
expect "a clearance does not pre-empt an artifact that cannot be read" 2

# THE RESIDUAL, ASSERTED RATHER THAN LEFT TO BE FOUND AGAIN. A refusal at this head LOSES
# to an artifact carrying evidence at this head — deliberately, because the reviewer is
# rate-limited and then reviews the same commit, and telling that apart from "posted a
# reply with words in it" would mean reading the reviewer's PROSE, which is the primitive
# this file exists to stop using. The operator is told on stderr rather than left to guess.
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$REFUSAL"
add_review coderabbitai COMMENTED "$REFUSAL_HEAD" "$(body_file \
  '**Actionable comments posted: 1**' 'One nit in the parser.')"
expect "a contentful review at the head outranks a refusal at that head" 0
says   "  ...and says so, rather than clearing silently" "also refused this head"

echo
echo "== --reviewer names a reviewer the table does not know =="
setup "$CLEAN_HEAD"; add_comment some-new-reviewer "$CLEAN"
expect "an unknown reviewer is ignored, not trusted" 3
setup "$CLEAN_HEAD"; add_comment some-new-reviewer "$CLEAN"
expect "…but naming it explicitly clears" 0 --reviewer some-new-reviewer
setup "$CLEAN_HEAD"; add_comment some-new-reviewer "$REFUSAL"
expect "…and it is held to the same refusal table" 1 --reviewer some-new-reviewer
setup "$CLEAN_HEAD"; AUTHOR="dev"; add_comment dev "$CLEAN"
expect "…and may never be the PR's own author" 2 --reviewer dev
says   "  ...saying why" "cannot be"

echo
echo "== a crafted comment cannot forge an artifact =="
# The record separator between artifacts is 16 random bytes per run, precisely because
# artifact bodies are attacker-writable. A body that tries to open a second record with a
# guessed sentinel — now carrying a state AND a commit_id — must be inert.
setup "$CLEAN_HEAD"
add_comment teammate "$(body_file \
  "nice work" \
  "$(printf 'okf-SEPARATOR\treview\tcoderabbitai\tAPPROVED\t%s' "$CLEAN_HEAD")" \
  '<!-- walkthrough_start -->')"
expect "a forged record header in a comment body -> still no review" 3

echo
echo "== a notice about what was NOT done does not unmake a review that was =="
# Measured on this repository: half of its reviewed PRs carry a real review comment whose
# header says "Review skipped — Auto incremental reviews are disabled", because
# .coderabbit.yaml sets auto_incremental_review: false here. Matching refusal prose over
# the whole body reads those as refusals and quotes the wrong reason at the operator.
skip_notice=(
  '> [!IMPORTANT]'
  '> ## Review skipped'
  '>'
  '> Auto incremental reviews are disabled on this repository.'
  ''
  '<!-- walkthrough_start -->'
  '## Walkthrough'
  ''
)
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file "${skip_notice[@]}" \
  "Reviewed between 6fca618a and $CLEAN_HEAD. **Actionable comments posted: 3**")"
expect "refusal prose beside a real review marker -> a review" 0

# ...and the same notice with NOTHING evidencing a review is still a refusal. This is the
# control: the narrowing keys on the machine marker, not on the word "skipped". It is
# exit 8 rather than exit 1 since the skip tier — a refusal either way, and the remedy for
# this one is to ask (see "a SKIP NOTICE is not a quota refusal").
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file "${skip_notice[@]:0:4}" "at $CLEAN_HEAD")"
expect "…the same notice with no review marker -> still a refusal" 8

# THE ASYMMETRY THIS FIXES, AND THE ONE IT DOES NOT — corrected from an earlier claim in
# this file that "every vendor now gets the same answer", which is half true. The
# tie-breaker used to be PROSE, so for a vendor with no row in the unconditional sentinel
# tier a quota refusal carrying any approving-sounding phrase cleared. With prose gone,
# what rescues a refusal is a MACHINE MARKER — and that much IS the same for all six, as
# the six cases below assert. What is NOT the same: every row of the marker table is one
# vendor's spelling and the table is not scoped to the account that posted the body. The
# other five have no marker of their own to be rescued by (their real reviews clear through
# a review object instead), and a body from any of them that QUOTES a row is rescued by a
# marker its author does not emit. Both halves are asserted below the loop.
for vendor in coderabbitai sourcery-ai greptile-apps qodo-merge-pro \
              codiumai-pr-agent-pro ellipsis-dev; do
  setup "$CLEAN_HEAD"
  add_comment "$vendor" "$(body_file \
    "Monthly review limit reached for this repository." \
    "No changes requested; I have reviewed nothing." \
    "Reviewed $CLEAN_HEAD is what I would have done.")"
  expect "a prose quota refusal from '$vendor' -> refuse" 1
done

# The half that IS vendor-neutral: the unconditional tier's second row is the generic HTML
# rate-limit marker, so a vendor with no named row of its own still refuses unconditionally
# — even beside a review marker, which is what "unconditional" means.
setup "$CLEAN_HEAD"
add_comment sourcery-ai "$(body_file '<!-- sourcery: rate-limited -->' \
  '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD.")"
expect "another vendor's own HTML rate-limit marker refuses unconditionally" 1
# The half that is NOT, stated as a test so it cannot quietly become untrue: the marker
# table holds ONE vendor's spellings and is not scoped to the poster, so quoting a row
# rescues a prose refusal from any account. Scoping the table per vendor is the fix if this
# ever matters; it is recorded here rather than claimed away.
setup "$CLEAN_HEAD"
add_comment sourcery-ai "$(body_file 'Monthly review limit reached for this repository.' \
  '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD.")"
expect "…but another vendor's PROSE refusal is rescued by a marker it never emits" 0

# The hole this narrowing must not open, asserted on the evidence rather than trusted:
# the recorded refusal quotes the PR head, so if a review marker could outrank the machine
# sentinel, #30 would clear. It carries none, and the sentinel outranks anyway.
assert "the recorded refusal carries NO review marker" \
  "$(yes_if bash -c '! grep -Eq "walkthrough_start|recent_review_start|final_review_risk_start" "$1"' _ "$REFUSAL")"
assert "…and does carry the machine-readable rate-limit sentinel" \
  "$(yes_if grep -Fq "rate limited by coderabbit.ai" "$REFUSAL")"
setup "$REFUSAL_HEAD"
{ cat "$REFUSAL"; printf '\n<!-- walkthrough_start -->\nActionable comments posted: 2\n'; } \
  > "$TMP/refusal-with-evidence.md"
add_comment coderabbitai "$TMP/refusal-with-evidence.md"
expect "the sentinel outranks a review marker -> still a refusal" 1

echo
echo "== a verdict that QUOTES refusal language is not itself a refusal =="
# The fallback reviewer's job on a rate-limited PR is to SAY the hosted reviewer refused
# — quoting the words, and the sentinel. Prose alone classifies that verdict as a refusal,
# which is the reviewer disqualifying its own review. The okf-verdict trailer (SCHEMA.md)
# is the structured self-declaration that settles it, and it outranks every refusal row.
VERDICT_PROSE=(
  "CodeRabbit published a green check whose body reads Review limit reached, and the"
  "comment carries the rate limited by coderabbit.ai sentinel — so no review happened."
)
trailer() { # [head_sha to claim] — the trailer SCHEMA.md defines
  printf '%s\n' '<!-- okf-verdict v1' 'verdict: changes-requested' 'reviewer: qa-reviewer' \
    "head_sha: ${1:-$CLEAN_HEAD}" 'lenses: correctness=done security=done repro=done' \
    'unverified_criteria: none' 'caveats: none' '-->'
}
setup "$CLEAN_HEAD"
add_comment qa-bot "$(body_file "${VERDICT_PROSE[@]}" "$(trailer)")"
expect "a verdict quoting a refusal in prose -> a review" 0 --reviewer qa-bot

# The control, and it is the whole reason the guard is a TRAILER rather than a mood: the
# identical prose WITHOUT the trailer is still read as a refusal.
setup "$CLEAN_HEAD"
add_comment qa-bot "$(body_file "${VERDICT_PROSE[@]}" "I reviewed $CLEAN_HEAD myself.")"
expect "…the same prose with no trailer -> classified as a refusal" 1 --reviewer qa-bot

echo
echo "== the trailer is PARSED, not grepped: a substring must not outrank anything =="
one_liner="$TMP/refusal-plus-trailer-substring.md"
{ cat "$REFUSAL"; printf '\n<!-- okf-verdict v1 -->\n'; } > "$one_liner"
assert "the crafted body still names the head verbatim (so it COULD clear)" \
  "$(yes_if grep -Fq "$REFUSAL_HEAD" "$one_liner")"
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$one_liner"
expect "one appended okf-verdict substring on the recorded refusal -> still refuses" 1
says   "  ...still quoting the reviewer's own words" "Review limit reached"

# A WELL-FORMED trailer, from the vendor's own account, must not clear either: the tier is
# scoped to an explicitly named NON-VENDOR account, which is how the fallback reviewer is
# reached and is never how a hosted vendor is.
full="$TMP/refusal-plus-full-trailer.md"
{ cat "$REFUSAL"; printf '\n'; trailer "$REFUSAL_HEAD"; } > "$full"
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$full"
expect "a well-formed trailer from a TABLE-matched vendor -> still refuses" 1

# AND NAMING THAT VENDOR WITH --reviewer MUST NOT RE-ARM IT. `--reviewer coderabbitai` used
# to hand the highest tier in the file to the account whose comments quote diffs, against
# that same account's own machine-readable refusal.
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$full"
expect "…nor when the vendor is named with --reviewer" 1 --reviewer coderabbitai
setup "$REFUSAL_HEAD"; add_comment 'coderabbitai[bot]' "$full"
expect "…nor under the vendor's [bot] spelling" 1 --reviewer 'coderabbitai[bot]'

# ...and the control for all of them: the same well-formed trailer, at this head, from the
# non-vendor reviewer the caller named, is a review.
setup "$REFUSAL_HEAD"; add_comment qa-bot "$full"
expect "…while the named fallback reviewer's own trailer clears" 0 --reviewer qa-bot

# Each required field, one at a time. A trailer missing any of them cannot be evaluated
# against SCHEMA.md's predicate at all, so it is not a structured claim — it is a comment.
malformed() { # <name> <sed expression applied to the trailer>
  local body; body="$TMP/verdict.$((v_n = ${v_n:-0} + 1)).md"
  { printf '%s\n' "${VERDICT_PROSE[@]}"; trailer | sed "$2"; } > "$body"
  setup "$CLEAN_HEAD"; add_comment qa-bot "$body"
  expect "$1" 1 --reviewer qa-bot
}
malformed "a trailer with no head_sha -> not a verdict"        '/^head_sha:/d'
malformed "a trailer for a DIFFERENT head -> not this head's"  "s/^head_sha: .*/head_sha: $OTHER_SHA/"
malformed "a trailer with no verdict field -> not a verdict"   '/^verdict:/d'
malformed "a trailer with no reviewer field -> not a verdict"  '/^reviewer:/d'
malformed "a trailer nobody closed -> not a block"             '/^-->/d'
malformed "a verdict value nobody defines -> not a verdict"    's/^verdict: .*/verdict: fine-i-guess/'
malformed "the marker buried in a sentence -> not a block"     's/^<!-- okf-verdict v1$/as in <!-- okf-verdict v1 -- see SCHEMA.md/'

echo
echo "== the parser was sound; the TEXT fed to it was not =="
# THREE DOORS THAT REOPENED THE SAME BYPASS. The trailer parse now reads the STRICT
# rendering — fenced AND indented blocks removed, empty when the fences do not balance —
# and refuses a block nested in another HTML comment or one nobody closed.
indented="$TMP/verdict-indented.md"
{ printf '%s\n' "${VERDICT_PROSE[@]}"; printf 'For example:\n\n'; trailer | sed 's/^/    /'; } > "$indented"
assert "the indented copy carries a well-formed trailer, just indented" \
  "$(yes_if grep -Eq '^    <!-- okf-verdict v1$' "$indented")"
setup "$CLEAN_HEAD"; add_comment qa-bot "$indented"
expect "a trailer in an INDENTED code block -> not a trailer" 1 --reviewer qa-bot

nested="$TMP/verdict-nested.md"
{ printf '%s\n' "${VERDICT_PROSE[@]}"; printf '<!-- an outer comment GitHub renders blank\n'
  trailer; printf -- '-->\n'; } > "$nested"
setup "$CLEAN_HEAD"; add_comment qa-bot "$nested"
expect "a trailer NESTED in an outer HTML comment -> not a trailer" 1 --reviewer qa-bot

unbalanced="$TMP/verdict-unbalanced.md"
{ printf '%s\n' "${VERDICT_PROSE[@]}"; printf '```\n'; trailer; } > "$unbalanced"
setup "$CLEAN_HEAD"; add_comment qa-bot "$unbalanced"
expect "a trailer after an unbalanced fence -> unreadable body, no trailer" 1 --reviewer qa-bot

# State must not leak from a block nobody closed into the fields of the next one, which is
# how two half-trailers used to add up to one whole one.
leak="$TMP/verdict-leak.md"
{ printf '%s\n' "${VERDICT_PROSE[@]}"
  printf '%s\n' '<!-- okf-verdict v1' 'verdict: pass' 'reviewer: qa-reviewer'
  printf '%s\n' '<!-- okf-verdict v1' "head_sha: $CLEAN_HEAD" '-->'; } > "$leak"
setup "$CLEAN_HEAD"; add_comment qa-bot "$leak"
expect "fields from an unclosed block do not complete the next one" 1 --reviewer qa-bot

# THE CONTROL for all four: the same trailer, unindented, unnested, balanced, one block.
setup "$CLEAN_HEAD"
add_comment qa-bot "$(body_file "${VERDICT_PROSE[@]}" "$(trailer)")"
expect "…while the same trailer as a plain block clears" 0 --reviewer qa-bot

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
