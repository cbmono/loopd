#!/usr/bin/env bash
#
# review-next.sh — what the tick does next on one in-review PR. One answer on stdout:
# dispatch-qa · request-review · implementer-round · rebase-round · merge-path · hold.
#
#   Usage: review-next.sh <pr> [--repo <o>/<n>] [--head <sha>] [--record <task-doc>] [--instance <bundle>] [--clear]
#          review-next.sh --decide rc=<0-8> class=<placeholder|declined|-> crr=<n> qar=<n> \
#                         crd=<n> qad=<n> qlast=<none|pass|fail|unknown> qhead=<yes|no> qrec=<yes|no>
#
# Exit 0 decided · 2 unknown input (stdout still `hold`). The same answer under gated and yolo.
# `--clear` (required-checks.sh): may this head merge with no review at it? 0 yes — prints and
# records last-round|qa-zero|zero-zero — · 1 hold, the reason on stderr · 2 unknown.
# Reasoning and the table: step-4-advance.md → "What next on a PR"; AUTONOMY.md → "Merge after the last round".
set -uo pipefail

decide() {
  local rc="" class="-" crr="" qar="" crd="" qad="" qlast="none" qhead="no" qrec="no" kv
  for kv in "$@"; do
    case "$kv" in
      rc=*) rc="${kv#*=}" ;; class=*) class="${kv#*=}" ;; crr=*) crr="${kv#*=}" ;;
      qar=*) qar="${kv#*=}" ;; crd=*) crd="${kv#*=}" ;; qad=*) qad="${kv#*=}" ;;
      qlast=*) qlast="${kv#*=}" ;; qhead=*) qhead="${kv#*=}" ;; qrec=*) qrec="${kv#*=}" ;;
      *) echo "review-next: unknown fact '$kv'" >&2; echo hold; return 2 ;;
    esac
  done
  case "$rc" in [0-8]) ;; *) echo "review-next: rc must be 0-8" >&2; echo hold; return 2 ;; esac
  local n
  for n in "$crr" "$qar" "$crd" "$qad"; do
    case "$n" in ''|*[!0-9]*) echo "review-next: crr, qar, crd and qad must be integers" >&2; echo hold; return 2 ;; esac
  done

  # NEXT_KIND is the merge-path kind --clear acts on: review (at the head), last-round-coderabbit,
  # last-round-qa, qa-zero or zero-zero.
  say() { echo "review-next: $2" >&2; echo "$1"; NEXT_ANSWER="$1"; NEXT_KIND="${3:-}"; }
  [ "$rc" = 7 ] && { say rebase-round "the PR conflicts (exit 7)"; return 0; }
  [ "$rc" = 2 ] && { say hold "reviewer state unreadable (exit 2)"; return 0; }
  [ "$rc" = 6 ] && { say implementer-round "CodeRabbit's threads are open at the head (exit 6): address them, then merge"; return 0; }
  [ "$crr" -eq 0 ] && [ "$qar" -eq 0 ] && { say merge-path "coderabbitRounds and qaRounds are both 0" zero-zero; return 0; }

  local qa=""
  if [ "$crr" -eq 0 ] && [ "$qar" -ge 1 ]; then qa="coderabbitRounds is 0"
  elif [ "$rc" = 0 ]; then say merge-path "CodeRabbit reviewed the head (exit 0)" review; return 0
  elif { [ "$rc" = 5 ] || { [ "$rc" = 1 ] && [ "$class" = declined ]; }; } && [ "$crd" -lt "$crr" ]; then
    qa="CodeRabbit refused after $crd of $crr round(s)"
  elif [ "$qad" -ge 1 ] || [ "$qrec" = yes ]; then qa="QA rounds already began on this PR"
  fi

  if [ -n "$qa" ]; then
    [ "$qar" -eq 0 ] && { say merge-path "$qa and qaRounds is 0" qa-zero; return 0; }
    [ "$qlast" = unknown ] && { say hold "QA round $qad is inconclusive or unreadable (open threads?); surface it"; return 0; }
    if [ "$qhead" = yes ]; then
      [ "$qlast" = pass ] && { say merge-path "QA passed the head" last-round-qa; return 0; }
      say implementer-round "QA round $qad found problems at the head, no fix yet"; return 0
    fi
    [ "$qrec" = yes ] && { say hold "a QA round is in flight at this head"; return 0; }
    [ "$qad" -eq 0 ] && { say dispatch-qa "$qa"; return 0; }
    [ "$qlast" = pass ] && { say merge-path "QA stopped at its first pass" last-round-qa; return 0; }
    [ "$qad" -lt "$qar" ] && { say dispatch-qa "QA round $qad failed and a fix landed; round $((qad + 1)) of $qar"; return 0; }
    say merge-path "QA reached qaRounds ($qar)" last-round-qa; return 0
  fi

  case "$rc" in
    4|8) if [ "$crd" -lt "$crr" ]; then say request-review "no CodeRabbit review at this head (exit $rc)"
         else say merge-path "past CodeRabbit's last round ($crd of $crr)" last-round-coderabbit; fi ;;
    1) if [ "$class" = declined ] && [ "$crd" -ge 1 ]; then
         say merge-path "CodeRabbit refused after its last round ($crd of $crr)" last-round-coderabbit
       else say hold "CodeRabbit is still processing (exit 1, $class)"; fi ;;
    5) say merge-path "CodeRabbit refused after its last round ($crd of $crr)" last-round-coderabbit ;;
    *) say hold "no reviewer signal (exit $rc)" ;;
  esac
  return 0
}

if [ "${1:-}" = "--decide" ]; then shift; decide "$@"; exit $?; fi

pr=""; repo=""; head=""; record=""; inst=""; clear=""
while [ $# -gt 0 ]; do
  case "$1" in
    --clear) clear=yes; shift ;;
    --repo|--head|--record|--instance)
      [ $# -ge 2 ] && [ -n "$2" ] || { sed -n '6,8p' "$0" >&2; exit 2; }
      case "$1" in --repo) repo="$2" ;; --head) head="$2" ;; --record) record="$2" ;; --instance) inst="$2" ;; esac
      shift 2 ;;
    -*) sed -n '6,8p' "$0" >&2; exit 2 ;;
    *) [ -z "$pr" ] || { sed -n '6,8p' "$0" >&2; exit 2; }; pr="$1"; shift ;;
  esac
done
[ -n "$pr" ] || { sed -n '6,8p' "$0" >&2; exit 2; }
unknown() { echo "review-next: $1 — holding" >&2; echo hold; exit 2; }
hold() { echo "review-next: hold for the human: $1" >&2; exit 1; }

if [ -z "$inst" ]; then
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$CLAUDE_PROJECT_DIR/instance.config.json" ]; then inst="$CLAUDE_PROJECT_DIR"
  else inst="$PWD"; while [ "$inst" != / ] && [ ! -f "$inst/instance.config.json" ]; do inst="$(dirname "$inst")"; done; fi
fi
D="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
R=(); [ -n "$repo" ] && R=(--repo "$repo")

meta="$(gh pr view "$pr" ${R[@]+"${R[@]}"} --json url,number,headRefOid \
        --jq '[.url, (.number|tostring), .headRefOid] | @tsv' 2>/dev/null)" || unknown "PR $pr is unreadable"
url="$(printf '%s' "$meta" | cut -f1)"; num="$(printf '%s' "$meta" | cut -f2)"
[ -n "$head" ] || head="$(printf '%s' "$meta" | cut -f3)"
nwo="$(printf '%s' "$url" | sed -E 's#^https?://[^/]+/([^/]+/[^/]+)/pull/[0-9]+.*#\1#')"
[ -n "$num" ] && [ -n "$head" ] && [ "$nwo" != "$url" ] || unknown "PR $pr is unreadable"

crr="$(bash "$D/resolve-review-config.sh" --instance "$inst" coderabbitRounds)" || unknown "coderabbitRounds unreadable"
qar="$(bash "$D/resolve-review-config.sh" --instance "$inst" qaRounds)" || unknown "qaRounds unreadable"

REC=(); [ -n "$record" ] && REC=(--record "$record")
out="$("$D/review-clearance.sh" "$num" --repo "$nwo" --head "$head" ${REC[@]+"${REC[@]}"} 2>/dev/null)"; rc=$?
class="$(printf '%s\n' "$out" | sed -n 's/^class: //p' | head -n 1)"
case "$rc" in 7|2) [ -z "$clear" ] || hold "review-clearance.sh exit $rc at the head"
  decide rc="$rc" crr="$crr" qar="$qar" crd=0 qad=0; exit $? ;; esac

crd="$("$D/review-rounds.sh" "$num" --for coderabbit --repo "$nwo" --instance "$inst" 2>/dev/null)"
[ $? -le 1 ] || unknown "CodeRabbit round count unreadable"
qv="$("$D/review-rounds.sh" "$num" --for qa --verdicts --repo "$nwo" --instance "$inst" 2>/dev/null)"
[ $? -le 1 ] || unknown "QA round count unreadable"
qad="$(printf '%s' "$qv" | grep -c .)"
last="$(printf '%s\n' "$qv" | tail -n 1)"
qlast=none; qhead=no
if [ -n "$last" ]; then
  case "${last#* }" in pass) qlast=pass ;; changes-requested) qlast=fail ;; *) qlast=unknown ;; esac
  [ "${last%% *}" = "$head" ] && qhead=yes
fi
"$D/qa-dispatch.sh" check --repo "$nwo" --pr "$num" --head "$head" --instance "$inst" >/dev/null 2>&1
case $? in 0) qrec=yes ;; 1) qrec=no ;; *) unknown "QA dispatch records unreadable" ;; esac

facts=(rc="$rc" class="${class:--}" crr="$crr" qar="$qar" crd="$crd" qad="$qad" \
       qlast="$qlast" qhead="$qhead" qrec="$qrec")
[ -n "$clear" ] || { decide "${facts[@]}"; exit $?; }

# --- --clear: the merge gate's question, asked only where review-clearance.sh refused --------
NEXT_ANSWER=""; NEXT_KIND=""
decide "${facts[@]}" >/dev/null || unknown "the review state is unreadable"
[ "$NEXT_ANSWER" = merge-path ] || hold "the review loop is not finished ($NEXT_ANSWER)"
kind="$NEXT_KIND"
case "$kind" in
  qa-zero|zero-zero) ;;
  last-round-coderabbit|last-round-qa)
    who="${kind#last-round-}"
    reviewed="$("$D/review-rounds.sh" "$num" --for "$who" --last --repo "$nwo" --instance "$inst" 2>/dev/null)"
    [ $? -le 1 ] || unknown "the last $who round is unreadable"
    printf '%s' "$reviewed" | grep -Eqx '[0-9a-f]{40}' || hold "no reviewed commit for the last $who round"
    # Route C pins by comment text the vendor edits, so only a review object's commit_id opens this.
    if [ "$who" = coderabbit ]; then
      logins="$(gh api "/repos/$nwo/pulls/$num/reviews?per_page=100" --paginate \
        --jq ".[] | select(.commit_id == \"$reviewed\") | .user.login // empty" 2>/dev/null)" \
        || unknown "the review objects are unreadable"
      pinned=""
      for l in $logins; do
        "$D/review-clearance.sh" --match-reviewer "$l" >/dev/null 2>&1 && pinned=yes
      done
      [ -n "$pinned" ] || hold "the last CodeRabbit round ($reviewed) has no review object, only its edited summary comment"
    fi
    cmp="$(gh api "/repos/$nwo/compare/$reviewed...$head" 2>/dev/null)" || unknown "compare $reviewed...$head is unreadable"
    st="$(printf '%s' "$cmp" | jq -r '.status // ""' 2>/dev/null)"
    case "$st" in
      ahead|identical) ;;
      diverged|behind) hold "a rebase or force-push after the last round orphaned the reviewed commit $reviewed (compare: $st)" ;;
      *) unknown "compare $reviewed...$head answered no status" ;;
    esac
    nf="$(printf '%s' "$cmp" | jq '.files // [] | length' 2>/dev/null)" || unknown "compare files unreadable"
    [ "${nf:-0}" -lt 300 ] || hold "the compare lists $nf files, past what the host counts"
    odd="$(printf '%s' "$cmp" | jq -r '.files // [] | .[]
      | select((.status | IN("renamed","copied","changed")) or ((.patch // "") == "")
               or (((.additions // 0) + (.deletions // 0)) == 0)
               or ((.patch // "") | test("^[-+]Subproject commit "; "m")))
      | "\(.status) \(.filename)"' 2>/dev/null)" || unknown "compare files unreadable"
    [ -z "$odd" ] || hold "files with no countable lines (binary, rename, mode-only or submodule): $(printf '%s' "$odd" | tr '\n' ',' | sed 's/,$//')"
    lines="$(printf '%s' "$cmp" | jq '[.files // [] | .[] | (.additions // 0) + (.deletions // 0)] | add // 0' 2>/dev/null)"
    case "$lines" in ''|*[!0-9]*) unknown "compare line counts unreadable" ;; esac
    max="$(bash "$D/resolve-review-config.sh" --instance "$inst" reviewFixMaxLines)" || unknown "reviewFixMaxLines unreadable"
    if [ "$lines" -gt "$max" ]; then
      merges="$(printf '%s' "$cmp" | jq '[.commits // [] | .[] | select((.parents // []) | length > 1)] | length' 2>/dev/null)"
      what="the fix"; [ "${merges:-0}" -gt 0 ] && what="a merge from the base branch"
      hold "$what after the last round changes $lines lines since $reviewed, over reviewFixMaxLines ($max)"
    fi
    echo "review-next: $lines of $max lines since the last reviewed commit $reviewed" >&2
    kind="last-round" ;;
  *) hold "nothing to waive: a review at the head decides (${kind:-none})" ;;
esac
"$D/clearance-receipt.sh" record review-next.sh --unreviewed "$kind" \
  --repo "$nwo" --pr "$num" --head "$head" >/dev/null 2>&1 || true
echo "$kind"
exit 0
