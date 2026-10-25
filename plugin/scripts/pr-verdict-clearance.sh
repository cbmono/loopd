#!/usr/bin/env bash
#
# pr-verdict-clearance.sh — compare the WORKER's criteria table (the PR body) with the
# CHECKER's re-derived one (a PR comment), and answer whether they agree.
#
#   Usage: pr-verdict-clearance.sh <pr> [--repo <owner>/<name>] [--checker <login>]
#          pr-verdict-clearance.sh --body-file <f> --checker-file <f>
#                                  [--checker-login <l>] [--author-login <l>]
#          pr-verdict-clearance.sh --self-test
#
#   0 agree · 1 disagree (worker ✓, checker FAIL) · 2 unknown · 3 checker table
#   malformed · 4 the checker posted under the PR author's own login, with no trailer
#   matching a recorded qa-reviewer dispatch (qa-dispatch.sh) at this head
#
# Reasoning: ai-bridge-next/task-013. The gate it feeds is SCHEMA.md clause 7.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]:-$0}")/bundle-paths.sh" || exit 2

# A checker row's evidence cell must carry one of these — a command, a path, a link, a
# run. Anything else is an assertion, and an assertion is not evidence.
# shellcheck disable=SC2016  # EREs, never shell expansions
EVIDENCE_MARKERS='
`[^`]+`
\]\([^)[:space:]]+\)
https?://[^[:space:]<>]+
(run|job|build|check|workflow)[[:space:]]+#?[0-9]+
'
MARK_VERIFIED='✓'
MARK_UNVERIFIED='✗'
SELFTEST_OK="pr-verdict-clearance: self-test ok"
EOF_SENTINEL="#EOF: pr-verdict-clearance.sh is complete to here"

usage() {
  echo "Usage: $(basename "$0") <pr> [--repo <owner>/<name>] [--checker <login>]" >&2
  echo "       $(basename "$0") --body-file <f> --checker-file <f>" >&2
  echo "       $(basename "$0") --self-test" >&2
  exit 2
}

rows() { printf '%s\n' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
                                | grep -v '^#' | grep -v '^$'; }

# A table that will not compile matches NOTHING, which here would refuse every honest
# row for a reason that is not about the row. Compile it up front instead.
validate_tables() {
  local bad="" r
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    printf '' | grep -Eq "$r" 2>/dev/null || [ $? -eq 1 ] || bad="$bad          $r
"
  done <<EOF
$(rows "$EVIDENCE_MARKERS")
EOF
  [ -z "$bad" ] || {
    echo "error: these rows are not valid POSIX EREs, so the table matches nothing." >&2
    printf '%s' "$bad" >&2
    return 2
  }
  return 0
}

# Which lines would a reader see as content? Fenced blocks go, so a document QUOTING a
# criteria table never clears on the quotation. Same closing rule as the siblings.
render() { # <src> <dst>
  tr -d '\r' < "$1" | awk '
    {
      if (fence == 0) {
        if (match($0, /^[[:space:]]{0,3}(`{3,}|~{3,})/)) {
          opener = substr($0, RSTART, RLENGTH); sub(/^[[:space:]]+/, "", opener)
          fchar = substr(opener, 1, 1); fwidth = length(opener); fence = 1; next
        }
        print; next
      }
      if (match($0, /^[[:space:]]{0,3}(`{3,}|~{3,})[[:space:]]*$/)) {
        closer = substr($0, RSTART, RLENGTH); gsub(/[[:space:]]/, "", closer)
        if (substr(closer, 1, 1) == fchar && length(closer) >= fwidth) fence = 0
      }
      next
    }' > "$2"
}

# One TSV line per data row of the FIRST table carrying <kind>'s verdicts:
#   <verdict> <TAB> <verdict-is-in-the-last-column> <TAB> <evidence cell> <TAB> <row>
# kind=worker reads the ✓/✗ column, kind=checker reads PASS/FAIL. NONE is a row nobody
# can classify and every caller refuses it. No field is ever empty: `read` with IFS=tab
# collapses a run of tabs, so an empty field would shift every field after it.
scan() { # <rendered> <kind>
  LC_ALL=C awk -v kind="$2" -v mchk="$MARK_VERIFIED" -v mcrs="$MARK_UNVERIFIED" '
    function bare(c) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", c); gsub(/[*_`~]/, "", c)
                       gsub(/^[[:space:]]+|[[:space:]]+$/, "", c); return c }
    function verdict_of(c,   t) {
      t = bare(c)
      if (t == "") return ""
      if (kind == "checker") {
        if (toupper(t) == "PASS") return "PASS"
        if (toupper(t) == "FAIL") return "FAIL"
        return ""
      }
      if (length(t) <= 3 && index(t, mchk) > 0) return "CHK"
      if (length(t) <= 3 && index(t, mcrs) > 0) return "CRS"
      return ""
    }
    function cells(s,   n) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); gsub(/\\\|/, "\002", s)
      sub(/^\|/, "", s); sub(/\|$/, "", s)
      return split(s, C, "|")
    }
    function is_delim(s,   n, i, c) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      if (index(s, "|") == 0) return 0
      sub(/^\|/, "", s); sub(/\|$/, "", s)
      n = split(s, D, "|")
      if (n < 1) return 0
      for (i = 1; i <= n; i++) { c = D[i]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", c)
        if (c !~ /^:?-+:?$/) return 0 }
      return 1
    }
    # Untrusted text leaves here: control bytes go, and the length is bounded, so a
    # document cannot print itself through this gate.
    function clean(s) { gsub(/\002/, "|", s); gsub(/[^[:print:]]/, ".", s)
                        if (length(s) > 200) s = substr(s, 1, 197) "..."
                        return s }
    { L[NR] = $0 }
    END {
      for (i = 2; i <= NR; i++) {
        if (!is_delim(L[i])) continue
        if (index(L[i-1], "|") == 0) continue
        hn = cells(L[i-1]); if (hn < 2 || hn != cells(L[i])) continue
        out = ""; found = 0
        for (j = i + 1; j <= NR; j++) {
          if (index(L[j], "|") == 0) break
          if (L[j] ~ /^[[:space:]]*$/) break
          n = cells(L[j]); v = ""; vk = 0
          for (k = 1; k <= n; k++) { v = verdict_of(C[k]); if (v != "") { vk = k; break } }
          if (v == "") { out = out sprintf("NONE\t0\t-\t%s\n", clean(L[j])); continue }
          found = 1
          evi = C[n]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", evi)
          evi = clean(evi); if (evi == "") evi = "-"
          out = out sprintf("%s\t%d\t%s\t%s\n", v, (vk == n ? 1 : 0), evi,
                            clean(L[j]))
        }
        if (found) { printf "%s", out; exit }
      }
    }' "$1"
}

has_evidence() { # <cell>
  local pat rc
  while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    printf '%s' "$1" | grep -Eq "$pat" 2>/dev/null; rc=$?
    [ "$rc" -eq 0 ] && return 0
    [ "$rc" -eq 1 ] || return 2
  done <<EOF
$(rows "$EVIDENCE_MARKERS")
EOF
  return 1
}

norm() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/\[bot\]$//'; }

# A login is host-supplied text, so it is reduced before it is printed back.
safe() { LC_ALL=C printf '%s' "$1" | tr -c 'A-Za-z0-9._[]-' '.' | cut -c1-40; }

nlines() { [ -n "$1" ] && printf '%s' "$1" | grep -c '^' || echo 0; }

# --- the decision ------------------------------------------------------------
# Order: unknown, the checker's own shape, the disagreement, then identity. Shape comes
# before the comparison because a malformed checker row cannot be compared with
# anything; identity comes last because it is the one refusal that survives agreement.
decide() { # <worker-scan> <checker-scan> <checker-login> <author-login> [dispatch-matched]
  local ws="$1" cs="$2" clogin="$3" alogin="$4" dispatched="${5:-}"
  local wn cn i wv cv cml cevi crow wrow bad=0

  wn="$(nlines "$ws")"; cn="$(nlines "$cs")"

  [ "$cn" -gt 0 ] || {
    echo "unknown: no checker table found — a criteria table whose verdict column is" >&2
    echo "         PASS or FAIL. Nothing to compare." >&2
    return 2; }
  [ "$wn" -gt 0 ] || {
    echo "unknown: no worker table found in the PR body — the ✓/✗ acceptance-criteria" >&2
    echo "         table $AB_CONVENTIONS requires. Nothing to compare." >&2
    return 2; }

  i=0
  while IFS=$'\t' read -r cv cml cevi crow; do
    i=$((i+1))
    [ "$cv" != NONE ] || {
      echo "refuse: checker row $i carries no PASS/FAIL verdict, and there is no partial" >&2
      echo "        credit — a criterion is PASS or it is FAIL: $crow" >&2
      bad=1; continue; }
    [ "$cml" = 0 ] || {
      echo "refuse: checker row $i ends on its verdict, so it has no evidence column." >&2
      echo "        Put the command or artifact in the LAST cell: $crow" >&2
      bad=1; continue; }
    has_evidence "$cevi" || {
      echo "refuse: checker row $i names no command or artifact, so nobody can re-run it." >&2
      echo "        Missing evidence is FAIL, never a pass: $crow" >&2
      bad=1; }
  done <<EOF
$cs
EOF
  [ "$bad" -eq 0 ] || return 3

  [ "$wn" -eq "$cn" ] || {
    echo "unknown: the worker's table has $wn row(s) and the checker's has $cn — they" >&2
    echo "         cannot be aligned criterion by criterion. Re-derive against the task." >&2
    return 2; }

  i=0; bad=0
  while IFS=$'\t' read -r cv cml cevi crow; do
    i=$((i+1))
    wrow="$(printf '%s\n' "$ws" | sed -n "${i}p")"
    wv="$(printf '%s' "$wrow" | cut -f1)"
    wrow="$(printf '%s' "$wrow" | cut -f4)"
    if [ "$wv" = "CHK" ] && [ "$cv" = "FAIL" ]; then
      echo "DISAGREEMENT on criterion $i — the worker passed itself, the checker did not:" >&2
      echo "  worker : $wrow" >&2
      echo "  checker: $crow" >&2
      bad=1
    elif [ "$wv" = "CRS" ] && [ "$cv" = "PASS" ]; then
      echo "note: criterion $i is ✗ for the worker and PASS for the checker — not a route," >&2
      echo "      but the body's ✗ still blocks clearance until the worker updates it." >&2
    fi
  done <<EOF
$cs
EOF
  [ "$bad" -eq 0 ] || {
    echo "refuse: $cn criteria compared, at least one disagreement. This is the human's." >&2
    return 1; }

  if [ -n "$clogin" ] && [ -n "$alogin" ] && [ -z "$dispatched" ] \
     && [ "$(norm "$clogin")" = "$(norm "$alogin")" ]; then
    echo "refuse: the checker posted under $(safe "$clogin"), the PR author's own login," >&2
    echo "        so nothing here shows a second principal ($AB_SCHEMA clause 8)." >&2
    echo "        KNOWN LIMIT: on a solo bundle every agent shares one gh login, so this" >&2
    echo "        is the standing answer there unless the comment's okf-verdict trailer carries" >&2
    echo "        the nonce of a recorded qa-reviewer dispatch at this head (qa-dispatch.sh)." >&2
    return 4
  fi
  [ -z "$dispatched" ] || echo "note: the checker shares the author's login; accepted against a recorded qa-reviewer dispatch." >&2
  [ -n "$clogin" ] && [ -n "$alogin" ] \
    || echo "note: no logins given, so the checker != author rule was not applied." >&2
  echo "clear: $cn criteria, both tables agree."
  return 0
}

# --- --self-test: no network, no PR ------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  [ -r "$0" ] || { echo "self-test: cannot read '$0' — refusing" >&2; exit 2; }
  [ "$(tail -n 1 "$0")" = "$EOF_SENTINEL" ] || {
    echo "self-test: this file does not end with its completeness sentinel, so a" >&2
    echo "           truncated copy cannot be told from a whole one. Refusing." >&2
    exit 2; }
  validate_tables || exit 2
  T="$(mktemp -d "${TMPDIR:-/tmp}/pr-verdict-selftest.XXXXXX")" || {
    echo "self-test: could not create a temp dir — refusing" >&2; exit 2; }
  trap 'rm -rf "$T"' EXIT
  cat > "$T/body" <<'MD'
| Criterion | ✓ | Verified by |
|---|---|---|
| the retry backs off | ✓ | `foo.test.sh` 40/0 |
MD
  cat > "$T/pass" <<'MD'
| Criterion | Verdict | Evidence |
|---|---|---|
| the retry backs off | PASS | `foo.test.sh` 40/0 |
MD
  cat > "$T/fail" <<'MD'
| Criterion | Verdict | Evidence |
|---|---|---|
| the retry backs off | FAIL | `foo.test.sh` 39/1 |
MD
  render "$T/body" "$T/rb"; render "$T/pass" "$T/rp"; render "$T/fail" "$T/rf"
  decide "$(scan "$T/rb" worker)" "$(scan "$T/rp" checker)" "" "" >/dev/null 2>&1 || {
    echo "self-test: identical tables did not clear — refusing" >&2; exit 2; }
  decide "$(scan "$T/rb" worker)" "$(scan "$T/rf" checker)" "" "" >/dev/null 2>&1
  [ $? -eq 1 ] || {
    echo "self-test: a disagreement did not answer 1 — refusing" >&2; exit 2; }
  echo "$SELFTEST_OK"
  exit 0
fi

validate_tables || exit 2

PR=""; REPO=""; CHECKER=""; BODY_FILE=""; CHK_FILE=""; CLOGIN=""; ALOGIN=""; CREATED=""; EDITED=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)          REPO="${2:-}"; shift 2 || usage ;;
    --checker)       CHECKER="${2:-}"; shift 2 || usage ;;
    --body-file)     BODY_FILE="${2:-}"; shift 2 || usage ;;
    --checker-file)  CHK_FILE="${2:-}"; shift 2 || usage ;;
    --checker-login) CLOGIN="${2:-}"; shift 2 || usage ;;
    --author-login)  ALOGIN="${2:-}"; shift 2 || usage ;;
    -h|--help)       usage ;;
    -*)              usage ;;
    *)               [ -z "$PR" ] || usage; PR="$1"; shift ;;
  esac
done

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/pr-verdict.XXXXXX")" || {
  echo "error: could not create a temp dir — refusing" >&2; exit 2; }
trap 'rm -rf "$TMPD"' EXIT

if [ -n "$BODY_FILE" ] || [ -n "$CHK_FILE" ]; then
  # Draft/fixture mode. It decides before anything is posted; the gate is the host mode
  # below, which reads the artifacts the reviewer actually served.
  [ -n "$BODY_FILE" ] && [ -n "$CHK_FILE" ] || usage
  [ -r "$BODY_FILE" ] && [ -r "$CHK_FILE" ] || {
    echo "error: cannot read one of the given files — refusing" >&2; exit 2; }
  cp "$BODY_FILE" "$TMPD/body"; cp "$CHK_FILE" "$TMPD/chk"
else
  [ -n "$PR" ] || usage
  command -v gh >/dev/null 2>&1 || {
    echo "error: gh is not installed, so no artifact can be read — unknown." >&2; exit 2; }
  command -v jq >/dev/null 2>&1 || {
    echo "error: jq is not installed, so the comment list cannot be read — unknown." >&2
    exit 2; }
  # shellcheck disable=SC2054  # --json takes ONE comma-separated argument
  ARGS=(pr view "$PR" --json body,author,comments,url,headRefOid)
  [ -n "$REPO" ] && ARGS+=(--repo "$REPO")
  META="$(gh "${ARGS[@]}" 2>/dev/null)" || {
    echo "error: gh could not read PR $PR — unknown, never clearance." >&2; exit 2; }
  printf '%s' "$META" | jq -r '.body // ""' > "$TMPD/body" 2>/dev/null || {
    echo "error: PR $PR served a body jq could not read — unknown." >&2; exit 2; }
  ALOGIN="$(printf '%s' "$META" | jq -r '.author.login // ""')"
  [ -n "$ALOGIN" ] || {
    echo "error: PR $PR reports no author login, so the checker != author rule cannot" >&2
    echo "       be applied. Unknown, never clearance." >&2; exit 2; }
  N="$(printf '%s' "$META" | jq -r '.comments | length' 2>/dev/null)" || N=0
  case "$N" in ''|*[!0-9]*) N=0 ;; esac
  : > "$TMPD/chk"
  # The LATEST comment carrying a PASS/FAIL table is the current verdict; an earlier one
  # is a superseded round and must not decide anything.
  i=$((N - 1))
  while [ "$i" -ge 0 ]; do
    L="$(printf '%s' "$META" | jq -r --argjson i "$i" '.comments[$i].author.login // ""')"
    if [ -z "$CHECKER" ] || [ "$(norm "$L")" = "$(norm "$CHECKER")" ]; then
      printf '%s' "$META" | jq -r --argjson i "$i" '.comments[$i].body // ""' > "$TMPD/one"
      render "$TMPD/one" "$TMPD/rone"
      if [ -n "$(scan "$TMPD/rone" checker)" ]; then
        # An artifact the host attributes to nobody cannot be weighed against clause 8.
        [ -n "$L" ] || {
          echo "error: the checker comment on PR $PR has no author login, so the" >&2
          echo "       checker != author rule cannot be applied. Unknown." >&2; exit 2; }
        cp "$TMPD/one" "$TMPD/chk"; CLOGIN="$L"
        CREATED="$(printf '%s' "$META" | jq -r --argjson i "$i" '.comments[$i].createdAt // ""')"
        EDITED="$(printf '%s' "$META" | jq -r --argjson i "$i" 'if .comments[$i].includesCreatedEdit == false then "false" else "true" end')"
        break
      fi
    fi
    i=$((i - 1))
  done
fi

render "$TMPD/body" "$TMPD/rbody"
render "$TMPD/chk" "$TMPD/rchk"

# SCHEMA.md clause 8 on a solo bundle: a same-login checker counts only when its unedited
# comment's trailer names this head and carries the nonce of a dispatch recorded before it.
DISPATCHED=""
HEAD_SHA="$(printf '%s' "${META:-}" | jq -r '.headRefOid // ""' 2>/dev/null)" || HEAD_SHA=""
URL="$(printf '%s' "${META:-}" | jq -r '.url // ""' 2>/dev/null)" || URL=""
if [ -n "$CLOGIN" ] && [ -n "$HEAD_SHA" ] && [ "$(norm "$CLOGIN")" = "$(norm "$ALOGIN")" ]; then
  T="$(awk '/^[[:space:]]*<!--[[:space:]]*okf-verdict[[:space:]]+v1[[:space:]]*$/ { b = 1; s = "-"; n = "-"; next }
            b && /-->/ { b = 0; print s, n; next }
            b && /^[[:space:]]*head_sha:/ { s = $2 }
            b && /^[[:space:]]*dispatch:/ { n = $2 }' "$TMPD/rchk" | tail -n 1)"
  T_SHA="${T%% *}"; T_NONCE="${T#* }"
  # The nonce is public once posted: only one unedited comment from that login may carry it.
  CARRIERS="$(printf '%s' "$META" | jq -r --arg l "$CLOGIN" --arg n "${T_NONCE:-}" \
              '[.comments[] | select(.author.login == $l and ((.body // "") | contains($n)))] | length' 2>/dev/null)"
  if [ -n "$T" ] && [ "$T_SHA" = "$HEAD_SHA" ] && [ "$T_NONCE" != - ] \
     && [ "${EDITED:-true}" = false ] && [ "${CARRIERS:-0}" = 1 ] \
     && "$(dirname "${BASH_SOURCE[0]:-$0}")/qa-dispatch.sh" check \
          --repo "$(printf '%s' "$URL" | sed -E 's#^https?://[^/]+/([^/]+/[^/]+)/pull/[0-9]+.*#\1#')" \
          --pr "$(printf '%s' "$URL" | sed -E 's#^https?://[^/]+/[^/]+/[^/]+/pull/([0-9]+).*#\1#')" \
          --head "$HEAD_SHA" --nonce "$T_NONCE" --after "${CREATED:-}" >/dev/null 2>&1; then
    DISPATCHED=yes
  fi
fi
decide "$(scan "$TMPD/rbody" worker)" "$(scan "$TMPD/rchk" checker)" "$CLOGIN" "$ALOGIN" "$DISPATCHED"; DRC=$?

# The clearance record the PreToolUse hook reads offline (ai-bridge-v3/task-044). Host mode
# only — a draft comparison says nothing about any pull request — and silent on any failure.
# A disagreement (1) is recorded too, replacing an earlier pass: it refuses the merge even
# where an external review means no pass from here is required.
if { [ "$DRC" -eq 0 ] || [ "$DRC" -eq 1 ]; } && [ -n "$HEAD_SHA" ] && [ -n "$URL" ]; then
  FAIL_FLAG=(); [ "$DRC" -eq 1 ] && FAIL_FLAG=(--fail)
  "$(dirname "${BASH_SOURCE[0]:-$0}")/clearance-receipt.sh" record pr-verdict-clearance.sh ${FAIL_FLAG[@]+"${FAIL_FLAG[@]}"} \
    --repo "$(printf '%s' "$URL" | sed -E 's#^https?://[^/]+/([^/]+/[^/]+)/pull/[0-9]+.*#\1#')" \
    --pr "$(printf '%s' "$URL" | sed -E 's#^https?://[^/]+/[^/]+/[^/]+/pull/([0-9]+).*#\1#')" --head "$HEAD_SHA" >/dev/null 2>&1 || true
fi
exit $DRC

#EOF: pr-verdict-clearance.sh is complete to here
