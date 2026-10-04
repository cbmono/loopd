#!/usr/bin/env bash
# Exercises the delegated merge gate's precondition 1 — plugin/scripts/required-checks.sh.
#
# `gh` is replaced by a stub on PATH that answers from fixture files, so the whole
# matrix runs offline: platform-required sets, the declared-list fallback, and every
# way both are supposed to REFUSE. The refusals are the point — this gate is the only
# thing standing between an autonomous loop and a merge, so the tests that matter most
# are the ones proving it fails closed.
#
# THE LAST SECTIONS COVER THE ONE GREEN CHECK THAT MEANS NOTHING. A reviewer that declines
# to review still exits successfully, so its check reports `pass` exactly as a reviewed
# PR's does — which is how two PRs merged unreviewed.
#
# AND A CHECK'S NAME NO LONGER DECIDES WHETHER ANYONE LOOKED. That used to be a table of
# vendor names inside review-clearance.sh, and a required check called `Codex Review`, or
# bare `Cursor` / `Copilot` / `Devin` / `PR Agent`, matched no row, was read as plain CI
# and settled on its green bucket with zero artifacts read. This script now asks for
# clearance on EVERY pull request it is about to clear, so `setup()` below ships a review
# that clears by default and the cases that must refuse take it away. `the name never
# settles it` drives exactly that.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/plugin/scripts/required-checks.sh"
TMP="$(mktemp -d)" || {
  echo "required-checks.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

export FIX="$TMP/fix"
mkdir -p "$TMP/bin"

# --- gh stub -----------------------------------------------------------------
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Minimal `gh` for required-checks.sh. Answers from $FIX; absent fixture = absent thing.
has() { local n="$1"; shift; for a in "$@"; do [ "$a" = "$n" ] && return 0; done; return 1; }

case "${1:-}" in
  pr)
    case "${2:-}" in
      view)
        # THREE different `pr view` calls now reach this stub: required-checks.sh asks
        # for a TSV of PR facts, review-clearance.sh asks for the PR's own facts as
        # JSON, and pr-body-clearance.sh asks for the BODY as JSON. Branch on the field
        # list, not on argument position — and not on `comments`, which
        # review-clearance.sh no longer asks `pr view` for at all. `body` and `author`
        # are each wanted by exactly one caller; all three ask for headRefOid.
        if grep -q body <<<"$(printf '%s\n' "$@")"; then
          [ -f "$FIX/pr_body_json" ] || { echo "no PR" >&2; exit 1; }
          cat "$FIX/pr_body_json"
        elif grep -q author <<<"$(printf '%s\n' "$@")"; then
          [ -f "$FIX/pr_json" ] || { echo "no PR" >&2; exit 1; }
          cat "$FIX/pr_json"
        else
          [ -f "$FIX/pr_meta" ] || { echo "no PR" >&2; exit 1; }
          cat "$FIX/pr_meta"
        fi ;;
      checks)
        if has --required "$@"; then
          if [ -f "$FIX/platform_broken" ]; then
            # A transient failure. Real gh puts errors on stderr, same as the
            # no-required message — which is exactly why the two can't be told
            # apart by stream or exit code, only by text.
            echo "error connecting to api.github.com" >&2; exit 1
          elif [ -f "$FIX/platform_garbage" ]; then
            # Some other message entirely — a reworded gh, a proxy page, anything.
            echo "could not resolve to a Repository" >&2; exit 1
          elif [ -f "$FIX/platform_empty" ]; then
            if has --jq "$@"; then :; else echo '[]'; fi
          elif [ -f "$FIX/platform_names" ]; then
            # `platform_names` holds a REAL JSON array (built by jq in `platform()` below),
            # not pre-flattened text — the classify call (no --jq) cats it verbatim, and the
            # enumerate call (--jq '.[].name') is piped through a REAL jq, exactly as real
            # `gh --jq` would flatten it. A stub that instead special-cased its own
            # hardcoded name/output here would exercise the script's two-call shape without
            # ever running the jq flattening those two gh calls actually depend on.
            if has --jq "$@"; then
              [ -f "$FIX/platform_enum_broken" ] && { echo "boom" >&2; exit 1; }
              filter=""; prev=""
              for a in "$@"; do
                [ "$prev" = "--jq" ] && { filter="$a"; break; }
                prev="$a"
              done
              jq -r "$filter" "$FIX/platform_names"
            else
              cat "$FIX/platform_names"
            fi
          else
            # Real gh: this goes to STDERR and exits 1 (verified against a live repo
            # with no protection). The script must not confuse it with a failing
            # required check, nor with a query that errored.
            echo "no required checks reported on the 'topic' branch" >&2; exit 1
          fi
        else
          cat "$FIX/checks" 2>/dev/null
          # Real gh exits 8 when anything is pending, 1 on failure.
          grep -qv '^pass	' "$FIX/checks" 2>/dev/null && exit 8
        fi ;;
      diff)
        [ -f "$FIX/diff_fails" ] && { echo "no diff" >&2; exit 1; }
        cat "$FIX/diff" 2>/dev/null; exit 0 ;;
      *) echo "stub: unhandled pr $2" >&2; exit 99 ;;
    esac ;;
  api)
    # GraphQL FIRST: review-clearance.sh reads review THREADS there (SCHEMA.md clause 9;
    # `isResolved` exists on no REST endpoint), and `gh api graphql …` would otherwise fall
    # through to the declared-list branch below and be answered with a 404 — which the
    # sibling correctly reads as unreadable thread state and refuses at exit 2, turning
    # every clearing case in this file red for a reason none of them is about. Default is
    # no threads and no further page.
    if [ "${2:-}" = "graphql" ]; then
      [ -f "$FIX/threads_json" ] || {
        printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false},"nodes":[]}}}}}\n'
        exit 0; }
      cat "$FIX/threads_json"; exit 0
    fi
    # Three endpoints reach this stub. review-clearance.sh reads the REVIEW OBJECTS
    # (the only place a review's state and commit_id exist) and the ISSUE COMMENTS —
    # separately and paginated, because `gh pr view --json comments` answers one page and
    # the artifact that must never be lost is a refusal, which is a comment.
    # required-checks.sh reads the declared list out of the repo's contents.
    case "$*" in
      */pulls/*/reviews*|*/issues/*/comments*)
        src="$FIX/reviews_json"
        case "$*" in */issues/*/comments*) src="$FIX/comments_json" ;; esac
        [ -f "$src" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
        filter=""; prev=""
        for a in "$@"; do
          [ "$prev" = "--jq" ] && { filter="$a"; break; }
          prev="$a"
        done
        if [ -n "$filter" ]; then jq -r "$filter" "$src"
        else cat "$src"; fi
        exit 0 ;;
    esac
    # Real gh prints the error BODY to stdout on a 404 and only the summary to
    # stderr — reproduce that, or the script's "did the fetch work" logic is untested.
    [ -f "$FIX/declared" ] || {
      echo '{"message":"Not Found","documentation_url":"https://docs.github.com/rest","status":"404"}'
      echo "gh: Not Found (HTTP 404)" >&2
      exit 1
    }
    cat "$FIX/declared" ;;
  *) echo "stub: unhandled $1" >&2; exit 99 ;;
esac
STUB
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"

HEAD_SHA="0c2592f7bb98d3de9a7a181d1762dfcaf80785d9"
HAVE_JQ=0; command -v jq >/dev/null 2>&1 && HAVE_JQ=1

# A cleared PR by default. Clearance is now asked for on EVERY pull request, so a fixture
# with no reviewer artifact would make every "-> clear" case below refuse for a reason
# none of them is about. `reviewer_pr` replaces it where the absent review is the point
# being tested.
#
# IT CARRIES A BODY, and that is not decoration: an empty-bodied APPROVED clears through the
# HELD route alone, so with one as the default fixture almost every positive case in this
# file exercised that one branch and neither of the two the caller actually depends on. This
# is a submitted review object at the head WITH content — route A, end to end.
reviewed_pr() {
  [ "$HAVE_JQ" = 1 ] || return 0
  jq -n --arg h "$HEAD_SHA" \
    '{url:"https://github.com/acme/widgets/pull/42", number:42, headRefOid:$h,
      author:{login:"dev"}, mergeable:"MERGEABLE", mergeStateStatus:"CLEAN"}' > "$FIX/pr_json"
  printf '[]\n' > "$FIX/comments_json"
  jq -n --arg h "$HEAD_SHA" \
    '[{user:{login:"coderabbitai"}, state:"APPROVED", commit_id:$h,
       body:"**Actionable comments posted: 0**"}]' \
    > "$FIX/reviews_json"
}

# The PR's BODY, as pr-body-clearance.sh reads it (precondition 3). The default is a
# CONFORMING one for the same reason `reviewed_pr` carries a review: clearance is asked
# for on every pull request, so a fixture with a malformed body would make every
# "-> clear" case below refuse for a reason none of them is about. `pr_body` overrides it
# where the body is the point being tested.
CONFORMING_BODY='## Description
Adds the thing, and the harness covers it.

Verified: `a.test.sh` 3/0 on [run 1](https://example.invalid/actions/runs/1).

### Criteria (1 ✓ / 0 ✗)

| Criterion | ✓ | Verified by |
|---|---|---|
| it works | ✓ | `a.test.sh` 3/0 |'

pr_body() { # <body text> — at <head>, defaulting to whatever pr_meta says
  [ "$HAVE_JQ" = 1 ] || return 0
  jq -n --arg h "${2:-$HEAD_SHA}" --arg b "$1" \
    '{url:"https://github.com/acme/widgets/pull/42", number:42, headRefOid:$h,
      body:$b}' > "$FIX/pr_body_json"
}

setup() { # start from: a readable, REVIEWED PR with a conforming body, no protection,
          # no declared list, no diff
  rm -rf "$FIX"; mkdir -p "$FIX"
  printf 'https://github.com/acme/widgets/pull/42\tmain\t%s\n' "$HEAD_SHA" > "$FIX/pr_meta"
  : > "$FIX/checks"
  reviewed_pr
  pr_body "$CONFORMING_BODY"
}

checks() { printf '%s\n' "$@" > "$FIX/checks"; }        # each arg: "bucket<TAB>name"
declared() { printf '%s\n' "$@" > "$FIX/declared"; }
platform() { jq -n --args '[$ARGS.positional[] | {name: ., bucket: "pass"}]' -- "$@" > "$FIX/platform_names"; }
diff_files() { printf '%s\n' "$@" > "$FIX/diff"; }

expect() { # <name> <expected-rc> [extra args to the script...]
  local name="$1" want="$2"; shift 2
  local out rc
  out="$("$SCRIPT" 42 "$@" 2>&1)"; rc=$?
  if [ "$rc" -eq "$want" ]; then
    printf '  PASS  %-56s (rc=%s)\n' "$name" "$rc"; pass=$((pass+1))
  else
    printf '  FAIL  %-56s expected rc=%s got rc=%s\n' "$name" "$want" "$rc"
    printf '        output: %s\n' "$(head -3 <<<"$out" | tr '\n' '|')"
    fail=$((fail+1))
  fi
  LAST_OUT="$out"
}

says() { # <name> <substring> — assert against the previous expect()'s output
  if grep -Fq "$2" <<<"$LAST_OUT"; then
    printf '  PASS  %-56s\n' "$1"; pass=$((pass+1))
  else
    printf '  FAIL  %-56s missing %s in: %s\n' "$1" "$2" "$(head -2 <<<"$LAST_OUT" | tr '\n' '|')"
    fail=$((fail+1))
  fi
}

if [ "$HAVE_JQ" != 1 ]; then
  echo "jq is required to run this test (the script's sibling needs it too)"; exit 2
fi

echo "== required-checks gate =="

# --- nothing to enforce: the authority is not exercisable --------------------
setup; checks "pass	Build"
expect "no protection, no declared list -> not exercisable" 3
says   "  ...and says which file it looked for" "$(printf '.github/required-checks.txt')"

setup; checks "pass	Build"; declared "# only a comment" "" "   "
expect "declared list empty after parsing -> not exercisable" 3

# --- declared fallback: the happy path ---------------------------------------
setup
checks "pass	Build, Lint & Format" "pass	Unit Tests (vitest)" "pass	CodeRabbit"
declared "# what must be green before an autonomous merge" "Build, Lint & Format" "" "Unit Tests (vitest)"
expect "declared list, all green -> clear" 0
says   "  ...and reports the declared source" "source: declared"
says   "  ...and says a review cleared it too" "a review clears"

# --- declared fallback: every way it must refuse -----------------------------
setup
checks "pass	Build, Lint & Format"
declared "Build, Lint & Format" "Unit Tests (vitest)"
expect "declared name never reported (renamed) -> refuse" 1
says   "  ...and names the drifted check" "Unit Tests (vitest): not reported"
says   "  ...and says what to do next, never bypass" "surface the PR to"
says   "  ...and forbids merging around it" "Do NOT merge around this gate"

setup; checks "fail	Build" "pass	Other"; declared "Build"
expect "declared check failing -> refuse" 1

setup; checks "pending	Build"; declared "Build"
expect "declared check pending -> refuse" 1

setup; checks "skipping	Build"; declared "Build"
expect "declared check skipped -> refuse (skipped is not passed)" 1

setup; checks "pass	Build" "fail	Build"; declared "Build"
expect "same name reported twice, one failing -> refuse" 1

# --- the gate cannot clear a PR that rewrites the gate -----------------------
setup
checks "pass	Build"; declared "Build"; diff_files "src/app.ts" ".github/required-checks.txt"
expect "PR edits the declared list -> human decision" 4

setup; checks "pass	Build"; declared "Build"; diff_files "src/app.ts" "README.md"
expect "PR touches unrelated files -> unaffected" 0

setup; checks "pass	Build"; declared "Build"; : > "$FIX/diff_fails"
expect "cannot list the PR's files -> refuse, not clear" 2

# --- platform protection wins, and is never confused with 'nothing required' --
setup
platform "Build" "E2E"
checks "pass	Build" "pass	E2E"
declared "A check nobody reports"          # would refuse if the fallback were used
expect "platform set present -> platform wins over declared" 0
says   "  ...and reports the platform source" "source: platform"

setup
platform "Build"
checks "fail	Build"
declared "Something that passes"           # must NOT rescue a failing platform check
expect "platform check failing -> refuse, no fallback to declared" 1

# An unreadable platform is NOT an unprotected one. Every case below has a declared
# list that would clear — the gate must refuse anyway, because falling back here
# would swap protection we failed to read for a list that may be weaker.
setup
: > "$FIX/platform_broken"
checks "pass	Build"; declared "Build"
expect "platform probe errors (no output) -> refuse, no fallback" 2

setup
: > "$FIX/platform_garbage"
checks "pass	Build"; declared "Build"
expect "platform probe answers something unrecognised -> refuse" 2
says   "  ...and shows what it got" "could not resolve to a Repository"

setup
platform "Build"; : > "$FIX/platform_enum_broken"
checks "pass	Build"; declared "Build"
expect "protection answered but names unreadable -> refuse" 2

# ...but an EMPTY required set is a real answer, not a failure: protection exists and
# requires nothing, so the declared list is allowed to speak.
setup
: > "$FIX/platform_empty"
checks "pass	Build"; declared "Build"
expect "protection requires nothing -> declared list may answer" 0
says   "  ...via the declared source" "source: declared"

# --- head pinning -------------------------------------------------------------
setup; checks "pass	Build"; declared "Build"
expect "head matches the verified SHA -> clear" 0 --head "$HEAD_SHA"

setup; checks "pass	Build"; declared "Build"
expect "head moved since verification -> refuse" 1 --head "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

# --- environment failures fail closed, not open -------------------------------
setup; rm -f "$FIX/pr_meta"; declared "Build"
expect "PR unreadable -> error, never a clearance" 2

setup; checks "pass	Build"; declared "Build"
expect "unknown option -> usage error" 2 --nope

# --- a green required set is never enough on its own --------------------------
# The failure this whole section exists for: three PRs in one tick, all three with a
# green reviewer check, one reviewed and two refused — and the two refusals merged.
FIXTURES="$(cd "$(dirname "$0")" && pwd)/fixtures/reviewer"
CR_CLEAN="$FIXTURES/clean-review.pr29.md"      # a real review, recorded verbatim
CR_REFUSAL="$FIXTURES/rate-limit-refusal.pr30.md"  # "Review limit reached", ditto
CR_HEAD="8f40f2ed565a31e141f5ae54a6935ad0810314c4"   # the head #29 was reviewed at

reviewer_pr() { # <body-file>|"" — the artifacts review-clearance.sh will read
  printf 'https://github.com/acme/widgets/pull/42\tmain\t%s\n' "$CR_HEAD" > "$FIX/pr_meta"
  printf '[]\n' > "$FIX/reviews_json"
  jq -n --arg h "$CR_HEAD" \
    '{url:"https://github.com/acme/widgets/pull/42", number:42, headRefOid:$h,
      author:{login:"dev"}, mergeable:"MERGEABLE", mergeStateStatus:"CLEAN"}' > "$FIX/pr_json"
  # It moves the head, so the PR-body fixture has to follow it or precondition 3 refuses
  # on a stale head in every case this helper sets up.
  pr_body "$CONFORMING_BODY" "$CR_HEAD"
  if [ -n "${1:-}" ]; then
    jq -n --rawfile b "$1" '[{user:{login:"coderabbitai"}, body:$b}]' > "$FIX/comments_json"
  else
    printf '[]\n' > "$FIX/comments_json"
  fi
}

setup; checks "pass	Build" "pass	CodeRabbit"; declared "Build" "CodeRabbit"
reviewer_pr "$CR_CLEAN"
expect "required reviewer check + a real review -> clear" 0

# THE OTHER WAY A GREEN CHECK AND A REAL REVIEW STILL DO NOT CLEAR: SCHEMA.md clause 9.
# The same recorded review that clears one case above, with a reviewer-authored thread left
# unresolved — the sibling answers 6, and this gate refuses. The advice is what makes 6
# worth its own code: exit 4 means ask for a review, exit 6 means DO NOT, you have one.
open_thread() { # <isResolved>
  jq -n --argjson r "$1" \
    '{data:{repository:{pullRequest:{reviewThreads:{pageInfo:{hasNextPage:false},
       nodes:[{isResolved:$r, path:"plugin/scripts/run.sh", line:42,
               comments:{nodes:[{author:{login:"coderabbitai"},
                                 url:"https://example.invalid/t/1",
                                 body:"`$dir` is unquoted here."}]}}]}}}}}' \
    > "$FIX/threads_json"
}
setup; checks "pass	Build" "pass	CodeRabbit"; declared "Build" "CodeRabbit"
reviewer_pr "$CR_CLEAN"; open_thread false
expect "a REAL review, but a reviewer thread left unresolved -> refuse" 1
says   "  ...naming the unresolved thread"            "plugin/scripts/run.sh:42"
says   "  ...and telling the caller not to re-request" "do NOT request another one"
# The control: the identical fixture with the thread resolved clears, so the case above
# is measuring thread state and not the fixture.
setup; checks "pass	Build" "pass	CodeRabbit"; declared "Build" "CodeRabbit"
reviewer_pr "$CR_CLEAN"; open_thread true
expect "...and the same fixture with the thread RESOLVED -> clear" 0

setup; checks "pass	Build" "pass	CodeRabbit"; declared "Build" "CodeRabbit"
reviewer_pr "$CR_REFUSAL"
expect "required reviewer check GREEN but the reviewer refused -> refuse" 1
says   "  ...and says a green check is not a review" "never that a review happened"
says   "  ...and quotes the refusal" "Review limit reached"
says   "  ...and names the reviewer-owned required check" "required, and reviewer-owned: CodeRabbit"

setup; checks "pass	Build" "pass	CodeRabbit"; declared "Build" "CodeRabbit"
reviewer_pr ""
expect "required reviewer check green but nothing reviewed -> refuse" 1

setup; checks "pass	Build" "pass	CodeRabbit"; declared "Build" "CodeRabbit"
reviewer_pr "$CR_CLEAN"; rm -f "$FIX/pr_json"
expect "reviewer state unreadable -> refuse as unknown, not as clear" 2

# --- the fifth round's three routes, driven to the sentence that authorises ---
# Each of these ended at `ok: N required check(s) pass` — the line a merge is taken from —
# while the reviewer's own refusal sat on the pull request, or while nobody was named as
# its author. They are driven from HERE, and not only against the clearance script, because
# this is the only place the outcome of getting it wrong is a merge.
#
# 1. AN INDENTED FENCE HID THE UNCONDITIONAL SENTINEL. The refusal side called an indented
#    ``` a fence and the clearing side did not, so a sentinel between two of them was
#    stripped out of the text the refusal tables read, while the review marker outside them
#    survived on the side that clears.
hidden_refusal="$TMP/refusal-behind-an-indented-fence.md"
{ printf '<!-- walkthrough_start -->\n'
  printf 'Reviewed %s.\n' "$CR_HEAD"
  printf '    ```\n    rate limited by coderabbit.ai\n    ```\n'; } > "$hidden_refusal"
setup; checks "pass	Build" "pass	CodeRabbit"; declared "Build" "CodeRabbit"
reviewer_pr "$hidden_refusal"
expect "a refusal behind an INDENTED fence -> refuse, never 'ok'" 1
says   "  ...quoting the sentinel a human can plainly read" "rate limited by coderabbit.ai"
# The control: the same indented block with no refusal in it still clears, so the case above
# fails for the refusal and not because indented text stopped being read at all.
harmless_block="$TMP/review-with-an-indented-block.md"
{ printf '<!-- walkthrough_start -->\n'
  printf 'Reviewed %s.\n' "$CR_HEAD"
  printf '    ```\n    make test\n    ```\n'; } > "$harmless_block"
setup; checks "pass	Build" "pass	CodeRabbit"; declared "Build" "CodeRabbit"
reviewer_pr "$harmless_block"
expect "…while the same block with no refusal in it clears" 0

# 2. AN EMPTY REVIEW OBJECT AT THE HEAD outranked the recorded refusal at that same head.
#    Review objects are streamed before comments, so it exited 0 before the refusal was
#    read at all.
setup; checks "pass	Build" "pass	CodeRabbit"; declared "Build" "CodeRabbit"
reviewer_pr "$CR_REFUSAL"
jq -n --arg c "$CR_HEAD" \
  '[{user:{login:"coderabbitai"}, state:"COMMENTED", commit_id:$c, body:""}]' \
  > "$FIX/reviews_json"
expect "an EMPTY review object at the head -> refuse, never 'ok'" 1
says   "  ...still quoting the refusal" "Review limit reached"
# The control: the same object at the same head WITH a body is a review, and clears.
setup; checks "pass	Build" "pass	CodeRabbit"; declared "Build" "CodeRabbit"
reviewer_pr "$CR_REFUSAL"
jq -n --arg c "$CR_HEAD" \
  '[{user:{login:"coderabbitai"}, state:"COMMENTED", commit_id:$c,
     body:"**Actionable comments posted: 1**"}]' > "$FIX/reviews_json"
expect "…while the same object carrying a body clears" 0

# 3. A MISSING AUTHOR LOGIN switched SCHEMA.md clause 8 off, so the reviewer account could
#    clear a pull request it had authored itself.
setup; checks "pass	Build" "pass	CodeRabbit"; declared "Build" "CodeRabbit"
reviewer_pr "$CR_CLEAN"
jq '.author = null' "$FIX/pr_json" > "$FIX/pr_json.n" && mv "$FIX/pr_json.n" "$FIX/pr_json"
expect "a PR with no author login -> refuse as unknown state" 2

# --- the sixth round's routes, driven to the same sentence --------------------
# 4. THE FENCE RULE DID NOT MATCH THE HOST. A fence opened inside a blockquote was closed
#    by a line outside it, and that is the reviewer's own idiom rather than a construction:
#    its notices arrive inside a `> [!WARNING]` blockquote. The RECORDED refusal, unaltered,
#    inside such a pair.
quoted_fence="$TMP/refusal-behind-a-quote-opened-fence.md"
{ printf '<!-- walkthrough_start -->\n'
  printf 'Reviewed %s.\n' "$CR_HEAD"
  printf '> ```\n'; cat "$CR_REFUSAL"; printf '```\n'; } > "$quoted_fence"
setup; checks "pass	Build" "pass	CodeRabbit"; declared "Build" "CodeRabbit"
reviewer_pr "$quoted_fence"
expect "a refusal behind a QUOTE-OPENED fence -> refuse, never 'ok'" 1
says   "  ...quoting the reviewer's own words" "Review limit reached"
# The control: both markers at one depth are a real fence, so that body is a review
# QUOTING a refusal and clears — the case above is the containment, not the fence.
same_depth="$TMP/review-quoting-a-refusal.md"
{ printf '<!-- walkthrough_start -->\n'
  printf 'Reviewed %s.\n' "$CR_HEAD"
  printf '```\n'; cat "$CR_REFUSAL"; printf '```\n'; } > "$same_depth"
setup; checks "pass	Build" "pass	CodeRabbit"; declared "Build" "CodeRabbit"
reviewer_pr "$same_depth"
expect "…while both markers at one depth ARE a pair, so that clears" 0

# 5. A REVIEW OBJECT WHOSE BODY RENDERS NOTHING counted as a claim, because "content" was
#    any non-whitespace byte: one zero-width space restored route 2 above exactly.
setup; checks "pass	Build" "pass	CodeRabbit"; declared "Build" "CodeRabbit"
reviewer_pr "$CR_REFUSAL"
jq -n --arg c "$CR_HEAD" --arg b "$(printf '\342\200\213')" \
  '[{user:{login:"coderabbitai"}, state:"COMMENTED", commit_id:$c, body:$b}]' \
  > "$FIX/reviews_json"
expect "a review object holding one zero-width space -> refuse" 1
says   "  ...still quoting the refusal" "Review limit reached"

# --- the seventh round's routes, driven to the same sentence ------------------
# 7. A RAW-HTML BLOCK CHANGES WHAT ``` MEANS, and the machine modelled no containers. The
#    RECORDED refusal inside the vendor's own `<details>` idiom: the host renders its
#    content as HTML, so the backticks are three characters on the page and the refusal
#    with them, while a fence machine that has never heard of an HTML block strips it.
html_block="$TMP/refusal-inside-an-html-block.md"
{ printf '<!-- walkthrough_start -->\n'
  printf 'Reviewed %s.\n\n' "$CR_HEAD"
  printf '<details>\n<summary>d</summary>\n```\n'; cat "$CR_REFUSAL"
  printf '```\n</details>\n'; } > "$html_block"
setup; checks "pass	Build" "pass	CodeRabbit"; declared "Build" "CodeRabbit"
reviewer_pr "$html_block"
expect "a refusal inside a <details> block -> refuse, never 'ok'" 1
says   "  ...quoting the reviewer's own words" "Review limit reached"
# The control: the same fence with no HTML block around it is a quotation and clears, so
# the case above is about the container and not about fences having stopped working.
setup; checks "pass	Build" "pass	CodeRabbit"; declared "Build" "CodeRabbit"
reviewer_pr "$same_depth"
expect "…while the same fence outside one is still a quotation" 0

# 8. A FENCE DIES WITH THE LIST ITEM THAT HOLDS IT, so the paragraph after the item is on
#    the page — and carrying the fence past it also turned an odd marker count even.
list_fence="$TMP/refusal-after-a-list-item-ends.md"
{ printf '<!-- walkthrough_start -->\n'
  printf 'Reviewed %s.\n\n' "$CR_HEAD"
  printf -- '- item\n  ```\n  x\n\nrate limited by coderabbit.ai\n\n  ```\n'; } > "$list_fence"
setup; checks "pass	Build" "pass	CodeRabbit"; declared "Build" "CodeRabbit"
reviewer_pr "$list_fence"
expect "a refusal after a list item ENDS the fence -> refuse, never 'ok'" 1
says   "  ...quoting the sentinel a human can plainly read" "rate limited by coderabbit.ai"

# 9. THE EVIDENCE HALF WAS REACHABLE FROM PROSE. Spelled inside an inline code span the
#    vendor's marker renders as visible characters, so a comment merely DESCRIBING it
#    cleared the pull request — which is what this round's own review ran into.
span_marker="$TMP/prose-quoting-the-marker.md"
{ printf 'The vendor emits `<!-- walkthrough_start -->` around its walkthrough.\n'
  printf 'Reviewed %s.\n' "$CR_HEAD"; } > "$span_marker"
setup; checks "pass	Build" "pass	CodeRabbit"; declared "Build" "CodeRabbit"
reviewer_pr "$span_marker"
expect "prose quoting the marker in a code span -> refuse, never 'ok'" 1

# 10. "CONTENT" WAS A LIST OF INVISIBLE CHARACTERS, and three constructs no character list
#     reaches went through it. Each is a review object at the head over the recorded
#     refusal at that head, and each must lose to it.
for blank in '&#8203;' '[//]: # ()' '<div></div>'; do
  setup; checks "pass	Build" "pass	CodeRabbit"; declared "Build" "CodeRabbit"
  reviewer_pr "$CR_REFUSAL"
  jq -n --arg c "$CR_HEAD" --arg b "$blank" \
    '[{user:{login:"coderabbitai"}, state:"COMMENTED", commit_id:$c, body:$b}]' \
    > "$FIX/reviews_json"
  expect "a review object whose body is '$blank' -> refuse" 1
done

# 6. AN ARTIFACT NOBODY CAN ATTRIBUTE was skipped before the refusal tables read it, so a
#    refusal published by one was never weighed.
setup; checks "pass	Build" "pass	CodeRabbit"; declared "Build" "CodeRabbit"
reviewer_pr "$CR_CLEAN"
jq '. + [{user:null, body:"anything"}]' "$FIX/comments_json" > "$FIX/comments_json.n" \
  && mv "$FIX/comments_json.n" "$FIX/comments_json"
expect "an artifact with no author login -> refuse as unknown state" 2

# The default fixture above now clears through route A WITH a body, so the held route — an
# empty APPROVED at the head, which is a claim the state makes rather than the body — is
# asserted here explicitly instead of being what every positive case happened to exercise.
setup; checks "pass	Build" "pass	CodeRabbit"; declared "Build" "CodeRabbit"
jq -n --arg h "$HEAD_SHA" \
  '[{user:{login:"coderabbitai"}, state:"APPROVED", commit_id:$h, body:""}]' \
  > "$FIX/reviews_json"
expect "an EMPTY APPROVED at the head, with nothing refusing, still clears" 0

echo
echo "== the name never settles it =="
# ROUTE 1 OF THE FOURTH REVIEW ROUND, and it is the original incident with a 2026 vendor's
# name on it. `Cursor Bugbot`, `Codex Review` and bare `Cursor` / `Copilot` / `Devin` /
# `PR Agent` are shipping code reviewers whose checks are green whether or not they
# reviewed. A table of names classified them as plain CI and settled them on that bucket
# with zero artifacts read; a table of names cannot be finished, so the name is not asked.
for reviewerish in "Cursor Bugbot" "Codex Review" "Cursor" "Copilot" "Devin" "PR Agent" \
                   "Korbit AI" "CodeAnt AI"; do
  setup; checks "pass	Build" "pass	$reviewerish"; declared "Build" "$reviewerish"
  reviewer_pr ""
  expect "'$reviewerish' green, nothing reviewed -> refuse" 1
done
# ...and the identical set with a real review clears, so the refusals above are the absent
# review and not the check's name having become a refusal of its own.
for reviewerish in "Cursor Bugbot" "Codex Review" "PR Agent"; do
  setup; checks "pass	Build" "pass	$reviewerish"; declared "Build" "$reviewerish"
  reviewer_pr "$CR_CLEAN"
  expect "…while '$reviewerish' with a real review clears" 0
done

# The same rule where no required name reads like a reviewer at all. A repo whose reviewer
# posts no check — or posts one called `Build` — is exactly where "which required check is
# a reviewer's" had no answer to give.
setup; checks "pass	Build"; declared "Build"; reviewer_pr ""
expect "plain CI names only, and nothing reviewed -> refuse" 1
says   "  ...saying no review clears the head" "no independent review clears PR"
setup; checks "pass	Build"; declared "Build"; reviewer_pr "$CR_CLEAN"
expect "…and the same set with a real review clears" 0

# Unknown reviewer state, with no reviewer-named check anywhere in the required set. This
# used to be exit 0 — the required names were all "CI", so nothing consulted the reviewer.
setup; checks "pass	Build"; declared "Build"; rm -f "$FIX/pr_json"
expect "reviewer state unreadable, no reviewer-named check -> refuse" 2

echo
echo "== one vendor's review may not clear another vendor's check =="
# Two reviewers required, one rate-limited. A single unscoped clearance call answers
# "is there a review on this PR" and the vendor that DID review clears the vendor that
# refused — the same substitution as the green check, one level in. Each reviewer-owned
# name is cleared against the reviewer that owns it.
two_vendors() { # <coderabbit-body> <sourcery-body>
  printf 'https://github.com/acme/widgets/pull/42\tmain\t%s\n' "$CR_HEAD" > "$FIX/pr_meta"
  printf '[]\n' > "$FIX/reviews_json"
  jq -n --arg h "$CR_HEAD" \
    '{url:"https://github.com/acme/widgets/pull/42", number:42, headRefOid:$h,
      author:{login:"dev"}, mergeable:"MERGEABLE", mergeStateStatus:"CLEAN"}' > "$FIX/pr_json"
  jq -n --rawfile a "$1" --rawfile b "$2" \
    '[{user:{login:"coderabbitai"}, body:$a},
      {user:{login:"sourcery-ai"},  body:$b}]' > "$FIX/comments_json"
  # Same reason as reviewer_pr: this helper moves the head, so the PR-body fixture has to
  # follow it or precondition 3 refuses on a stale head rather than on anything this
  # section is about.
  pr_body "$CONFORMING_BODY" "$CR_HEAD"
}

setup; checks "pass	Build" "pass	CodeRabbit" "pass	Sourcery review"
declared "Build" "CodeRabbit" "Sourcery review"
two_vendors "$CR_REFUSAL" "$CR_CLEAN"
expect "one vendor reviewed, the other refused -> refuse" 1
says   "  ...naming the check whose reviewer refused" "required check 'CodeRabbit'"

setup; checks "pass	Build" "pass	CodeRabbit" "pass	Sourcery review"
declared "Build" "CodeRabbit" "Sourcery review"
two_vendors "$CR_CLEAN" "$CR_CLEAN"
expect "both vendors reviewed this head -> clear" 0

# --- the sibling has to be there AND have to run -----------------------------
# The two scripts ship as one unit. Without the sibling, this one cannot ask whether a
# review happened at all — an unknown reviewer state, which must refuse.
#
# AND A PRESENT-BUT-BROKEN SIBLING IS THE WORSE CASE, which is what the rest of this
# section is. `[ -x ]` tests a mode bit: every variant below carries it and none of them
# runs, so every call fails, and a caller that read those failures as "then no reviewer is
# involved" would report `ok` on an unreviewed PR. The gate does not fail — it silently is
# not there. Each case therefore asserts BOTH the exit code and that the output is the
# sibling complaint, so a pass here cannot come from some unrelated refusal.
echo
sibling_case() { # <name> <what to write into review-clearance.sh> <expected message>
  local name="$1" writer="$2" want="$3"
  local dir="$TMP/sib.$((sib_n = ${sib_n:-0} + 1))"; mkdir -p "$dir"
  cp "$SCRIPT" "$dir/required-checks.sh"
  cp "$(dirname "$SCRIPT")/bundle-paths.sh" "$dir/bundle-paths.sh"
  eval "$writer" > "$dir/review-clearance.sh"
  chmod +x "$dir/review-clearance.sh"           # the mode bit `[ -x ]` would be happy with
  setup; checks "pass	Build"; declared "Build"
  local out rc
  out="$("$dir/required-checks.sh" 42 2>&1)"; rc=$?
  if [ "$rc" -eq 2 ] && grep -Fq "$want" <<<"$out"; then
    printf '  PASS  %-56s (rc=%s)\n' "$name" "$rc"; pass=$((pass+1))
  else
    printf '  FAIL  %-56s expected rc=2 + %s, got rc=%s: %s\n' \
      "$name" "$want" "$rc" "$(head -2 <<<"$out" | tr '\n' '|')"
    fail=$((fail+1))
  fi
}

LONELY="$TMP/lonely"; mkdir -p "$LONELY"
cp "$SCRIPT" "$LONELY/required-checks.sh"
cp "$(dirname "$SCRIPT")/bundle-paths.sh" "$LONELY/bundle-paths.sh"
setup; checks "pass	Build"; declared "Build"
out="$("$LONELY/required-checks.sh" 42 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && grep -Fq "review-clearance.sh not found" <<<"$out"; then
  printf '  PASS  %-56s (rc=%s)\n' "review-clearance.sh missing -> refuse, never clear" "$rc"; pass=$((pass+1))
else
  printf '  FAIL  %-56s expected rc=2 got rc=%s\n' "review-clearance.sh missing -> refuse, never clear" "$rc"
  fail=$((fail+1))
fi

BROKEN="is present but does not run"
sibling_case "zero-byte sibling -> refuse, never clear" \
  'printf ""' "$BROKEN"
sibling_case "dead shebang -> refuse, never clear" \
  'printf "#!/nonexistent/interpreter\nexit 0\n"' "$BROKEN"
sibling_case "syntax error -> refuse, never clear" \
  'printf "#!/usr/bin/env bash\nif [ 1 ; then\n"' "$BROKEN"
sibling_case "truncated in its header comment -> refuse, never clear" \
  'head -c 400 "$(dirname "$SCRIPT")/review-clearance.sh"' "$BROKEN"

# THE TRUNCATION THAT ACTUALLY GETS THROUGH, and the case above cannot show it: a cut at
# 400 bytes lands inside the sibling's header comment, so the file has no --self-test at
# all and fails for that. The dangerous cut is BELOW the self-test block — the file still
# parses, still answers the self-test, and has lost the tables and the classifier the
# answer was vouching for. Swept over the version before the sentinel, 109 such cuts went
# on to clear an unreviewed PR through this script. These four walk that range end to end.
SIB_SRC="$(dirname "$SCRIPT")/review-clearance.sh"
SIB_SELFTEST="$(head -1 <<<"$(grep -n -- '--self-test" \]; then' "$SIB_SRC")" | cut -d: -f1)"
SIB_LINES="$(wc -l < "$SIB_SRC" | tr -d ' ')"
# Loudly, not vacuously: if the block can no longer be located, every case below would
# degenerate into the zero-byte case and pass for the wrong reason.
if [ -n "$SIB_SELFTEST" ] && [ "$SIB_SELFTEST" -lt "$SIB_LINES" ]; then
  printf '  PASS  %-56s (line %s of %s)\n' "the sibling's self-test block is located" \
    "$SIB_SELFTEST" "$SIB_LINES"; pass=$((pass+1))
else
  printf '  FAIL  %-56s\n' "the sibling's self-test block could not be located"
  fail=$((fail+1)); SIB_SELFTEST=1
fi
for frac in 5 33 66 99; do
  cut_line=$(( SIB_SELFTEST + (SIB_LINES - SIB_SELFTEST) * frac / 100 ))
  sibling_case "cut ${frac}% past the self-test -> refuse, never clear" \
    "head -n $cut_line \"\$SIB_SRC\"" "$BROKEN"
done
# Version skew, which is the likely way this happens in a live instance rather than a
# corrupted file: a sibling from before the self-test contract answers a usage error to
# `--self-test` and works perfectly otherwise. Refuse anyway — "I cannot confirm this
# runs" is the same unknown state whether the cause is corruption or an old copy, and
# the repair (`install.sh`) is the same one.
sibling_case "a sibling too old to self-test -> refuse until relinked" \
  'printf "#!/usr/bin/env bash\n[ \"\$1\" = --match-check ] && exit 1\nexit 2\n"' \
  "$BROKEN"
# A liar is deliberately NOT tested here. A sibling that fakes the sentinel and then
# answers whatever it likes is not a failure mode this gate can detect — it is the gate,
# and anyone who can rewrite it can rewrite this file beside it. The self-test's job is
# the accidental break (truncation, syntax error, skew), which is the one that happens.
# Any answer outside {0,1} means the sibling is doing something this script has no reading
# for. Unknown, so refuse — rather than treating "not 0" as "no reviewer owns it".
sibling_case "--match-check answers an unknown code -> refuse" \
  'printf "#!/usr/bin/env bash\n[ \"\$1\" = --self-test ] && { echo \"review-clearance: self-test ok\"; exit 0; }\n[ \"\$1\" = --match-check ] && exit 7\nexit 0\n"' \
  "which is not one of"
sibling_case "…including the deleted third answer -> refuse" \
  'printf "#!/usr/bin/env bash\n[ \"\$1\" = --self-test ] && { echo \"review-clearance: self-test ok\"; exit 0; }\n[ \"\$1\" = --match-check ] && exit 3\nexit 0\n"' \
  "which is not one of"

# The passing control for the whole section: the REAL sibling, same fixture, clears. So
# the refusals above are the sibling being broken and not the fixture being unclearable.
REALSIB="$TMP/realsib"; mkdir -p "$REALSIB"
cp "$SCRIPT" "$REALSIB/required-checks.sh"
cp "$(dirname "$SCRIPT")/bundle-paths.sh" "$REALSIB/bundle-paths.sh"
cp "$(dirname "$SCRIPT")/review-clearance.sh" "$REALSIB/review-clearance.sh"
# Precondition 3's sibling travels with the other two: this control asserts that an
# INTACT install clears, so a copy missing one of the three would make it pass for the
# wrong reason (or, as here, fail for one).
cp "$(dirname "$SCRIPT")/pr-body-clearance.sh" "$REALSIB/pr-body-clearance.sh"
setup; checks "pass	Build"; declared "Build"
out="$("$REALSIB/required-checks.sh" 42 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
  printf '  PASS  %-56s (rc=%s)\n' "…and an intact sibling clears the same fixture" "$rc"; pass=$((pass+1))
else
  printf '  FAIL  %-56s expected rc=0 got rc=%s: %s\n' "…and an intact sibling clears the same fixture" \
    "$rc" "$(head -2 <<<"$out" | tr '\n' '|')"
  fail=$((fail+1))
fi

echo
echo "== a CONFLICTING PR never clears the merge gate, however green it is =="
# 2026-09-13: three PRs read "merge — verified, CLEAN" with a review at head and every
# check green, while the host reported them CONFLICTING/DIRTY. The gate has one job here
# and it is to say no; the advice is what tells the caller a review would not help.
conflicting() { # <mergeable> <mergeStateStatus>
  jq -n --arg h "$HEAD_SHA" --arg m "$1" --arg s "$2" \
    '{url:"https://github.com/acme/widgets/pull/42", number:42, headRefOid:$h,
      author:{login:"dev"}, mergeable:$m, mergeStateStatus:$s}' > "$FIX/pr_json"
}
setup; checks "pass	Build"; declared "Build"; conflicting CONFLICTING DIRTY
expect "every check green but the PR conflicts -> refuse" 1
says   "  ...quoting the sibling's own code"       "review-clearance.sh exit 7"
says   "  ...and sending the caller to a rebase"   "CONFLICTS with its base"
says   "  ...not to a reviewer"                    "do NOT request a review"

setup; checks "pass	Build"; declared "Build"; conflicting UNKNOWN UNKNOWN
# 2, not 1: an UNKNOWN mergeability is unreadable state, and this file already keeps that
# apart from a reviewer that answered and declined. A hold, either way — never a clearance.
expect "an UNKNOWN mergeability holds the gate too -> unknown" 2
says   "  ...as unknown state, not as a conflict"  "review-clearance.sh exit 2"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
