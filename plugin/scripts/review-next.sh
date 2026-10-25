#!/usr/bin/env bash
#
# review-next.sh — what the tick does next on one in-review PR. One answer on stdout:
# dispatch-qa · request-review · implementer-round · rebase-round · merge-path · hold.
#
#   Usage: review-next.sh <pr> [--repo <o>/<n>] [--head <sha>] [--record <task-doc>] [--instance <bundle>]
#          review-next.sh --decide rc=<0-8> class=<placeholder|declined|-> crr=<n> qar=<n> \
#                         crd=<n> qad=<n> qlast=<none|pass|fail|unknown> qhead=<yes|no> qrec=<yes|no>
#
# Exit 0 decided · 2 unknown input (stdout still `hold`). The same answer under gated and yolo.
# Reasoning and the table: step-4-advance.md → "What next on a PR".
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

  say() { echo "review-next: $2" >&2; echo "$1"; }
  [ "$rc" = 7 ] && { say rebase-round "the PR conflicts (exit 7)"; return 0; }
  [ "$rc" = 2 ] && { say hold "reviewer state unreadable (exit 2)"; return 0; }

  local qa=""
  if [ "$crr" -eq 0 ] && [ "$qar" -ge 1 ]; then qa="coderabbitRounds is 0"
  elif [ "$rc" = 0 ] || [ "$rc" = 6 ]; then say merge-path "CodeRabbit reviewed the head (exit $rc)"; return 0
  elif { [ "$rc" = 5 ] || { [ "$rc" = 1 ] && [ "$class" = declined ]; }; } && [ "$crd" -lt "$crr" ]; then
    qa="CodeRabbit refused after $crd of $crr round(s)"
  elif [ "$qad" -ge 1 ] || [ "$qrec" = yes ]; then qa="QA rounds already began on this PR"
  fi

  if [ -n "$qa" ]; then
    [ "$qar" -eq 0 ] && { say merge-path "$qa and qaRounds is 0"; return 0; }
    [ "$qlast" = unknown ] && { say hold "QA round $qad is inconclusive or unreadable (open threads?); surface it"; return 0; }
    if [ "$qhead" = yes ]; then
      [ "$qlast" = pass ] && { say merge-path "QA passed the head"; return 0; }
      say implementer-round "QA round $qad found problems at the head, no fix yet"; return 0
    fi
    [ "$qrec" = yes ] && { say hold "a QA round is in flight at this head"; return 0; }
    [ "$qad" -eq 0 ] && { say dispatch-qa "$qa"; return 0; }
    [ "$qlast" = pass ] && { say merge-path "QA stopped at its first pass"; return 0; }
    [ "$qad" -lt "$qar" ] && { say dispatch-qa "QA round $qad failed and a fix landed; round $((qad + 1)) of $qar"; return 0; }
    say merge-path "QA reached qaRounds ($qar)"; return 0
  fi

  case "$rc" in
    4|8) if [ "$crd" -lt "$crr" ]; then say request-review "no CodeRabbit review at this head (exit $rc)"
         else say hold "CodeRabbit is at coderabbitRounds ($crr); surface the PR"; fi ;;
    1) say hold "CodeRabbit is still processing, or refused after its last round (exit 1, $class)" ;;
    5) say hold "CodeRabbit refused after its last round (exit 5)" ;;
    *) say hold "no reviewer signal (exit $rc)" ;;
  esac
  return 0
}

if [ "${1:-}" = "--decide" ]; then shift; decide "$@"; exit $?; fi

pr=""; repo=""; head=""; record=""; inst=""
while [ $# -gt 0 ]; do
  case "$1" in
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
case "$rc" in 7|2) decide rc="$rc" crr="$crr" qar="$qar" crd=0 qad=0; exit $? ;; esac

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

decide rc="$rc" class="${class:--}" crr="$crr" qar="$qar" crd="$crd" qad="$qad" \
       qlast="$qlast" qhead="$qhead" qrec="$qrec"
exit $?
