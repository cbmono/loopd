#!/usr/bin/env bash
#
# qa-disagreement.sh — file a QA disagreement as ONE `Q<n>:` entry on the task doc, which
# AWAITING.md renders from disk, and clear it once it no longer describes the head.
#
#   Usage: qa-disagreement.sh open  <task-doc> --pr <url> --head <sha> --checker <sha|-> --criteria <n[,n]>
#          qa-disagreement.sh clear <task-doc> [--pr <url> --head <sha>]
#
# open: 0 written or already open (`written|exists Q<n>`) · 1 not written: the task is not
# in-review or the checker's commit is not the head · 2 usage or unreadable · 3 write failed.
# clear: 0 (`cleared: <n>`) · 2 · 3. Reasoning: step-4-advance.md, "Compare the two tables".
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
usage() { sed -n '6,7p' "$0" | sed 's/^# *//' >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "qa-disagreement: python3 is required" >&2; exit 2; }

cmd="${1:-}"; [ $# -gt 0 ] && shift
case "$cmd" in open|clear) ;; *) usage ;; esac
task="${1:-}"; [ -n "$task" ] && [ -r "$task" ] || usage; shift
pr=""; head=""; checker=""; criteria=""
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] && [ -n "$2" ] || usage
  case "$1" in
    --pr) pr="$2" ;; --head) head="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')" ;;
    --checker) checker="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')" ;;
    --criteria) criteria="$2" ;; *) usage ;;
  esac
  shift 2
done

status="$(awk 'NR==1&&$0!="---"{exit} /^---$/{n++; if(n==2)exit; next} n==1&&/^status:/{sub(/^status:[[:space:]]*/,""); print $1; exit}' "$task")"
open_q="$(bash "$HERE/fold-answers.sh" --list "$task" open_questions)" || {
  echo "qa-disagreement: cannot read open_questions in $task" >&2; exit 2; }

if [ "$cmd" = clear ]; then
  { [ -z "$pr" ] && [ -z "$head" ]; } || { [ -n "$pr" ] && [ -n "$head" ]; } || usage
  n=0
  while IFS= read -r e; do
    [[ "$e" =~ ^Q[0-9]+:\ QA\ disagreement\ on\ ([^[:space:]]+)\ at\ ([0-9a-f]{12}): ]] || continue
    [[ "$e" == *' --- '* ]] && continue
    if [ "$status" != in-review ]; then note="cleared: task left in-review"
    elif [ "${BASH_REMATCH[1]}" = "$pr" ] && [ "${head:0:12}" != "${BASH_REMATCH[2]}" ]; then
      note="cleared: head moved past ${BASH_REMATCH[2]}"
    else continue; fi
    bash "$HERE/fold-answers.sh" --clear "$e" "$note" "$task" >/dev/null || {
      echo "qa-disagreement: could not clear an entry in $task" >&2; exit 3; }
    n=$((n + 1))
  done <<EOF
$open_q
EOF
  echo "cleared: $n"; exit 0
fi

[ -n "$pr" ] && [ -n "$head" ] && [ -n "$checker" ] && [[ "$criteria" =~ ^[0-9]+(,[0-9]+)*$ ]] || usage
[[ "$head" =~ ^[0-9a-f]{40}$ ]] || usage
[ "$status" = in-review ] || { echo "not-written: the task is ${status:-unreadable}, not in-review"; exit 1; }
[ "$checker" = "$head" ] || { echo "not-written: the checker's table is at $checker, the head is $head"; exit 1; }

key="QA disagreement on $pr at ${head:0:12}:"
q="$(printf '%s\n' "$open_q" | grep -F -- "$key" | grep -oE '^Q[0-9]+' | head -1)"
[ -z "$q" ] || { echo "exists: $q"; exit 0; }

# The highest number in use anywhere, as session-handoff.sh numbers a hand-off.
qn="$( { printf '%s\n' "$open_q"; bash "$HERE/fold-answers.sh" --list "$task" answered_questions
         sed -n 's/^### \(Q[0-9][0-9]*\)[[:space:]]*$/\1:/p' "$task"; } 2>/dev/null \
      | grep -oE '(^|[^A-Za-z0-9])Q[0-9]+:' | grep -oE '[0-9]+' | sort -n | tail -1)"
q="Q$(( ${qn:-0} + 1 ))"
crit="$(printf '%s' "$criteria" | sed 's/,/, /g')"
entry="$q: $key criteria $crit — the PR body marks ✓, QA's table FAILs. What next?"
tmp="$(dirname "$task")/.qa-disagreement.$$.md"
cp -p "$task" "$tmp" && bash "$HERE/fold-answers.sh" --add "$tmp" "$entry" >/dev/null || {
  rm -f "$tmp"; echo "qa-disagreement: could not write $task" >&2; exit 3; }
python3 - "$tmp" "$q" "$crit" "${head:0:12}" "$pr" <<'PY' || { rm -f "$tmp"; echo "qa-disagreement: could not write $task" >&2; exit 3; }
import re, sys
path, q, crit, sha, pr = sys.argv[1:6]
src = open(path, encoding="utf-8").read()
end = src.find("\n---", 3) + 4
head, lines = src[:end], src[end:].split("\n")
block = ["", "### " + q,
    "Recommendation: send it back for a fix round",
    "Options:",
    "1. send it back for a fix round",
    "2. the checker is wrong: re-run QA at this head",
    "3. the worker's ✓ stands: merge it yourself",
    "Context:",
    "- Depth 1: QA's table FAILs criteria %s that the PR body marks ✓, at head %s." % (crit, sha),
    "- Depth 2: `pr-verdict-clearance.sh` on %s prints both rows; the merge receipt refuses this head, and the tick resumes the implementer when `review-next.sh` answers `implementer-round`." % pr,
    "- Depth 3: The tick clears this entry once the head moves past %s or the task leaves in-review." % sha]
at = next((i for i, l in enumerate(lines) if re.match(r"## Question details\s*$", l)), None)
if at is None:
    while lines and not lines[-1].strip():
        lines.pop()
    lines += ["", "## Question details"] + block + [""]
else:
    e = next((i for i in range(at + 1, len(lines)) if re.match(r"#{1,2}\s", lines[i])), len(lines))
    while e > at + 1 and not lines[e - 1].strip():
        e -= 1
    lines[e:e] = block
out = head + "\n".join(lines)
open(path, "w", encoding="utf-8").write(out if out.endswith("\n") else out + "\n")
PY
[ "$(bash "$HERE/fold-answers.sh" --list "$tmp" open_questions 2>/dev/null | grep -cF -- "$key")" = 1 ] \
  && [ "$(grep -cx "### $q" "$tmp")" = 1 ] && mv -f "$tmp" "$task" || {
  rm -f "$tmp"; echo "qa-disagreement: the write did not read back; $task unchanged" >&2; exit 3; }
echo "written: $q"
