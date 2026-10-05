#!/usr/bin/env bash
#
# review-clearance.lib.sh — the shared setup of the three harnesses that exercise
# plugin/scripts/review-clearance.sh: tests/review-clearance.test.sh (the recorded
# evidence), tests/review-clearance-bodies.test.sh (how a body is read, and how artifacts
# rank) and tests/review-clearance-gates.test.sh (the modes, the tables and the gates
# around the classifier). SOURCED, never run: it is not a `*.test.sh`, so tests/run.sh
# does not execute it, and `$0` below is the harness that sourced it.
#
# ONE FILE BECAME THREE BECAUSE OF A CLOCK, NOT A THEME. As one harness this was 538 s of
# a 600 s per-harness kill limit in CI (558 assertions, nearly each one a launch of the
# script) — one slow runner from being killed, and a killed harness replays nothing. The
# stubs, the fixture builders and the assertion helpers moved here verbatim so the three
# cannot drift apart on what a PR looks like.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/plugin/scripts/review-clearance.sh"
SCRIPTS="$(cd "$(dirname "$0")/.." && pwd)/plugin/scripts"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$(cd "$(dirname "$0")" && pwd)/fixtures/reviewer"
CLEAN="$FIXTURES/clean-review.pr29.md"
REFUSAL="$FIXTURES/rate-limit-refusal.pr30.md"
ACK="$FIXTURES/ack-invocation.pr227.md"
ACK_PROSE="$FIXTURES/ack-prose.quoted-in-a-review.md"
SKIP="$FIXTURES/skip-notice.pr229.md"
SKIP_REVIEWED="$FIXTURES/skip-beside-review.pr215.md"
SKIP_REVIEWED_HEAD="3e83817779c0cc00b0e7e8f7cc352bd120670444"
CLEAN_HEAD="8f40f2ed565a31e141f5ae54a6935ad0810314c4"
REFUSAL_HEAD="88c106a8dd2b9ae14e001918022d4909e5357460"
OTHER_SHA="0123456789abcdef0123456789abcdef01234567"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/review-clearance.XXXXXX")" || {
  echo "review-clearance.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
# The mutants run from $TMP, and the script sources its sibling resolver
# (ai-bridge-v3/task-031) — without it they exit 2 before reaching their subject.
cp "$(dirname "$SCRIPT")/bundle-paths.sh" "$TMP/bundle-paths.sh"
pass=0; fail=0

command -v jq >/dev/null 2>&1 || { echo "jq is required to run this test"; exit 2; }
REAL_JQ="$(command -v jq)"
export FIX="$TMP/fix"
mkdir -p "$TMP/bin"

# --- stubs -------------------------------------------------------------------
cat > "$TMP/bin/gh" <<STUB
#!/usr/bin/env bash
REAL_JQ="$REAL_JQ"
STUB
cat >> "$TMP/bin/gh" <<'STUB'
# Minimal `gh` for review-clearance.sh. THREE sources, because the script reads three:
# the PR's own facts from $FIX/pr_json (`gh pr view`), the REVIEW OBJECTS from
# $FIX/reviews_json (only that endpoint carries a review's state AND its commit_id), and
# the ISSUE COMMENTS from $FIX/comments_json. The comments used to ride along inside
# `gh pr view --json comments`, which answers ONE page: a PR with more comments than that
# loses the refusal, and a lost refusal is a clearance. Both lists are paginated now, so
# both arrive through `gh api` and the stub has to tell them apart by path.
case "${1:-} ${2:-}" in
  "pr view")
    [ -f "$FIX/gh_broken" ] && { echo "could not resolve to a PullRequest" >&2; exit 1; }
    [ -f "$FIX/pr_json" ] || { echo "could not resolve to a PullRequest" >&2; exit 1; }
    cat "$FIX/pr_json"; exit 0 ;;
esac
# THE FOURTH SOURCE: review THREADS, which exist only in GraphQL. `isResolved` is on no
# REST endpoint — not a review, not a review comment, not the PR — so SCHEMA.md clause 9
# has to come through here. Routed FIRST, because `gh api graphql ...` also matches the
# `api` arm below and would otherwise be answered with the review list: valid JSON of the
# wrong shape, which the script reads as unreadable thread state and refuses at exit 2 —
# every clearing case in this file going red for a reason none of them is about.
if [ "${1:-} ${2:-}" = "api graphql" ]; then
  [ -f "$FIX/threads_broken" ] && { echo "gh: Bad gateway (HTTP 502)" >&2; exit 1; }
  [ -f "$FIX/threads_json" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
  cat "$FIX/threads_json"; exit 0
fi
if [ "${1:-}" = "api" ]; then
  src="$FIX/reviews_json"; broken="$FIX/reviews_broken"
  case "${2:-}" in
    */issues/*/comments*) src="$FIX/comments_json"; broken="$FIX/comments_broken" ;;
  esac
  [ -f "$broken" ] && { echo "gh: Bad gateway (HTTP 502)" >&2; exit 1; }
  [ -f "$src" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
  filter=""; prev=""
  for a in "$@"; do
    [ "$prev" = "--jq" ] && { filter="$a"; break; }
    prev="$a"
  done
  if [ -n "$filter" ]; then "$REAL_JQ" -r "$filter" "$src"
  else cat "$src"; fi
  exit 0
fi
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

# --- fixture builders ---------------------------------------------------------
HEAD=""; AUTHOR=""; REVIEWS=""; COMMENTS=""; THREADS=""; THREADS_MORE=""
MERGEABLE=""; MERGE_STATE=""; HEAD_DATE=""

setup() { # start from: a readable PR at <head> [pushed at <date>], authored by "dev"
  rm -rf "$FIX"; mkdir -p "$FIX"
  HEAD="${1:-$CLEAN_HEAD}"; AUTHOR="dev"; REVIEWS='[]'; COMMENTS='[]'
  # No commit date by default — the PR's commit list is read only to bound the exit-8 ask,
  # so every case written before that bound existed asks exactly what it was written to ask.
  HEAD_DATE="${2:-}"
  # A MERGEABLE/CLEAN PR is the default, so every case written before the mergeability
  # check existed keeps asking exactly the question it was written to ask. UNKNOWN holds
  # at exit 2, so a fixture that simply omitted these would refuse the whole file.
  MERGEABLE="MERGEABLE"; MERGE_STATE="CLEAN"
  # NO THREADS AND NO FURTHER PAGE is the default, so every case written before clause 9
  # existed keeps asking exactly the question it was written to ask.
  THREADS='[]'; THREADS_MORE=false
}

body_file() { # <text...> -> a file holding it, so every artifact arrives the same way
  local f; f="$(mktemp "$TMP/body.XXXXXX")"; printf '%s\n' "$@" > "$f"; printf '%s' "$f"
}

add_comment() { # <login> <body-file>
  COMMENTS="$("$REAL_JQ" --arg l "$1" --rawfile b "$2" \
              '. + [{user:{login:$l}, body:$b}]' <<<"$COMMENTS")"
}

# The same comment, with the host's own `created_at` on it — which is what says whether it
# was written at the current head when its body names no commit.
add_comment_at() { # <login> <created_at> <body-file>
  COMMENTS="$("$REAL_JQ" --arg l "$1" --arg t "$2" --rawfile b "$3" \
              '. + [{user:{login:$l}, body:$b, created_at:$t}]' <<<"$COMMENTS")"
}

# The host reports no author at all for an artifact from a deleted account, and `gh` passes
# that through as `null`. It is not a login the script can compare against anything.
add_null_comment() { # <body-file>
  COMMENTS="$("$REAL_JQ" --rawfile b "$1" '. + [{user:null, body:$b}]' <<<"$COMMENTS")"
}

# A review object as the REST API publishes one: a state, a commit_id and a body. The
# first two are what clears it now; the body is read only for a refusal.
add_review() { # <login> <state> <commit_id> <body-file>
  REVIEWS="$("$REAL_JQ" --arg l "$1" --arg s "$2" --arg c "$3" --rawfile b "$4" \
             '. + [{user:{login:$l}, state:$s, commit_id:$c, body:$b}]' <<<"$REVIEWS")"
}

# A review thread as GraphQL publishes one. `line` is a number or null (a file-level
# thread), `author` may be null (a deleted account) — both shapes are real and both are
# driven below.
add_thread() { # <isResolved> <path> <line|null> <login|null> <url> <first-line-of-body>
  THREADS="$("$REAL_JQ" --argjson r "$1" --arg p "$2" --argjson l "$3" \
             --arg who "$4" --arg u "$5" --arg b "$6" \
    '. + [{ isResolved:$r, path:$p, line:$l,
            comments:{nodes:[{ author:(if $who=="" then null else {login:$who} end),
                               url:$u, body:$b }]} }]' <<<"$THREADS")"
}

write_pr() {
  "$REAL_JQ" -n --arg h "$HEAD" --arg a "$AUTHOR" \
              --arg m "$MERGEABLE" --arg s "$MERGE_STATE" --arg hd "$HEAD_DATE" \
    '{url:"https://github.com/acme/widgets/pull/42", number:42, headRefOid:$h,
      author:{login:$a}, mergeable:$m, mergeStateStatus:$s,
      commits:(if $hd == "" then [] else [{oid:$h, committedDate:$hd}] end)}' > "$FIX/pr_json"
  printf '%s' "$REVIEWS"  > "$FIX/reviews_json"
  printf '%s' "$COMMENTS" > "$FIX/comments_json"
  "$REAL_JQ" -n --argjson t "$THREADS" --argjson more "$THREADS_MORE" \
    '{data:{repository:{pullRequest:{reviewThreads:
       {pageInfo:{hasNextPage:$more}, nodes:$t}}}}}' > "$FIX/threads_json"
}

# A WHOLE PR AS THE HOST SERVED IT, rather than assembled from the builders above: the
# three endpoints come out of one recorded file (tests/fixtures/reviewer/*.api.json). No
# threads, because clause 9 is asked only on the clearing path and these do not clear.
load_recorded() { # <fixture.api.json>
  rm -rf "$FIX"; mkdir -p "$FIX"
  "$REAL_JQ" '.pr'       "$1" > "$FIX/pr_json"
  "$REAL_JQ" '.reviews'  "$1" > "$FIX/reviews_json"
  "$REAL_JQ" '.comments' "$1" > "$FIX/comments_json"
  "$REAL_JQ" -n '{data:{repository:{pullRequest:{reviewThreads:
                  {pageInfo:{hasNextPage:false}, nodes:[]}}}}}' > "$FIX/threads_json"
}

# --- assertions ---------------------------------------------------------------
expect() { # <name> <expected-rc> [args to the script...]
  write_pr
  local name="$1" want="$2"; shift 2
  local out rc
  out="$("$SCRIPT" 42 "$@" 2>&1)"; rc=$?
  if [ "$rc" -eq "$want" ]; then
    printf '  PASS  %-58s (rc=%s)\n' "$name" "$rc"; pass=$((pass+1))
  else
    printf '  FAIL  %-58s expected rc=%s got rc=%s\n' "$name" "$want" "$rc"
    printf '        output: %s\n' "$(head -3 <<<"$out" | tr '\n' '|')"
    fail=$((fail+1))
  fi
  LAST_OUT="$out"
}

# The same assertion over a load_recorded() fixture: no write_pr, and the PR's own number.
expect_recorded() { # <name> <expected-rc> <pr-number> [args to the script...]
  local name="$1" want="$2" num="$3"; shift 3
  local out rc
  out="$("$SCRIPT" "$num" "$@" 2>&1)"; rc=$?
  if [ "$rc" -eq "$want" ]; then
    printf '  PASS  %-58s (rc=%s)\n' "$name" "$rc"; pass=$((pass+1))
  else
    printf '  FAIL  %-58s expected rc=%s got rc=%s\n' "$name" "$want" "$rc"
    printf '        output: %s\n' "$(head -3 <<<"$out" | tr '\n' '|')"
    fail=$((fail+1))
  fi
  LAST_OUT="$out"
}

says() { # <name> <substring> — against the previous expect()'s output
  if grep -Fq "$2" <<<"$LAST_OUT"; then
    printf '  PASS  %-58s\n' "$1"; pass=$((pass+1))
  else
    printf '  FAIL  %-58s missing %s in: %s\n' "$1" "$2" "$(head -2 <<<"$LAST_OUT" | tr '\n' '|')"
    fail=$((fail+1))
  fi
}

assert() { # <name> <rc-of-a-condition>
  if [ "$2" = 0 ]; then printf '  PASS  %-58s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL  %-58s\n' "$1"; fail=$((fail+1)); fi
}
yes_if() { if "$@" >/dev/null 2>&1; then echo 0; else echo 1; fi; }

EMPTY_BODY="$(body_file '')"
