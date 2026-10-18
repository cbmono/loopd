#!/usr/bin/env bash
#
# answer.sh — answer one open question of one task: option n, free text, or `more`.
#
#   Usage: answer.sh [--instance DIR] <task-doc> [Q<n>] <n | more | later | --text <answer> | <answer>...>
#
# No Q<n> ⇒ the first unanswered entry. A bare integer is an option of its `### Q<n>` block.
# `later` appends `<task path>#Q<n>` to AB_ANSWER_LATER; neither it nor `more` edits a tracked file.
# Exit: 0 done · 1 refused, one sentence · 2 usage · 3 the move refused, nothing written
#       4 committed, but the commit, rebase or push failed — nothing forced · 5 `more` is past the stored depths
#       6 `more` or `later` could not save its record, nothing printed
# Reasoning: simple-board/task-002.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/bundle-paths.sh" || exit 2
usage() { sed -n '5p' "$0" >&2; exit 2; }
refuse() { echo "$*"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "answer: python3 is required" >&2; exit 2; }

inst="."; doc=""; label=""; forced=0; words=()
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) [ $# -ge 2 ] || usage; inst="$2"; shift 2 ;;
    --text)     forced=1; shift; words+=("$@"); break ;;
    -h|--help)  usage ;;
    *) if [ -z "$doc" ]; then doc="$1"
       elif [ -z "$label" ] && [ ${#words[@]} -eq 0 ] && [[ "$1" =~ ^Q[0-9]+$ ]]; then label="$1"
       else words+=("$1"); fi
       shift ;;
  esac
done
[ -n "$doc" ] && [ ${#words[@]} -gt 0 ] || usage
[ -r "$doc" ] || refuse "No task document at $doc."
reply="${words[*]}"
[ -n "${reply// /}" ] || usage
task="$(basename "$doc" .md)"

open_list="$(bash "$HERE/fold-answers.sh" --list "$doc" open_questions)" || exit 3
entry=""
while IFS= read -r e; do
  [ -n "$e" ] || continue
  case "$e" in *" --- "*) rest="${e##* --- }"; [ -n "${rest// /}" ] && continue ;; esac
  if [ -z "$label" ] || [ "${e%%:*}" = "$label" ]; then entry="$e"; break; fi
done <<<"$open_list"
if [ -z "$entry" ]; then
  [ -n "$label" ] && refuse "$label is not an open question on $task."
  refuse "$task has no open question."
fi
qlabel=""; [[ "$entry" =~ ^(Q[0-9]+): ]] && qlabel="${BASH_REMATCH[1]}"
state="$inst/$AB_ANSWER_DEPTH"
depth_file="$state/$(printf '%s\n%s' "$(cd "$(dirname "$doc")" && pwd -P)/$task" "$entry" | cksum | awk '{print $1}')"
later="$inst/$AB_ANSWER_LATER"
doc_abs="$(cd "$(dirname "$doc")" && pwd -P)/$(basename "$doc")"
inst_abs="$(cd "$inst" 2>/dev/null && pwd -P)"
key=""; [ -n "$qlabel" ] && [ -n "$inst_abs" ] && [ "${doc_abs#"$inst_abs"/}" != "$doc_abs" ] && key="${doc_abs#"$inst_abs"/}#$qlabel"
# unlater [<line>] — drop this question's key from the later file, then append <line>.
unlater() {
  [ -n "$key" ] && { [ -f "$later" ] || [ -n "${1:-}" ]; } || return 0
  mkdir -p "$(dirname "$later")" && { grep -vxF -- "$key" "$later" 2>/dev/null; [ -z "${1:-}" ] || printf '%s\n' "$1"; } > "$later.tmp" &&
    mv -f "$later.tmp" "$later"
}

# block <option|depth> <k> — prints how many are stored, then item k when it exists.
block() {
  python3 - "$doc" "$qlabel" "$1" "$2" <<'PY'
import re, sys
doc, label, kind, k = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
lines = open(doc, encoding="utf-8").read().split("\n")
start = 0
if lines and lines[0] == "---":
    start = next((i + 1 for i in range(1, len(lines)) if lines[i] == "---"), len(lines))
blk = []
for i in range(start, len(lines)):
    if label and re.match(r"###\s+%s\s*$" % re.escape(label), lines[i]):
        for l in lines[i + 1:]:
            if re.match(r"#{1,3}\s", l):
                break
            blk.append(l)
        break
items, field, cur = {}, None, None
for l in blk:
    m = re.match(r"(\w+):\s*$", l)
    if m:
        field, cur = m.group(1), None
        continue
    if kind == "option" and field == "Options":
        m = re.match(r"\s*(\d+)\.\s+(.*\S)", l)
        if m:
            items[int(m.group(1))] = m.group(2)
    elif kind == "depth" and field == "Context":
        m = re.match(r"\s*-\s*Depth\s+(\d+):\s*(.*)$", l)
        if m:
            cur = int(m.group(1))
            items[cur] = [m.group(2).strip()]
        elif cur:
            items[cur].append(l.strip())
n = 0
while n + 1 in items:
    n += 1
print(n)
if 1 <= k <= n:
    v = items[k]
    print(v if isinstance(v, str) else "\n".join(v).strip())
PY
}

if [ "$forced" -eq 0 ] && [ "$reply" = "later" ]; then
  [ -n "$qlabel" ] || refuse "Only a numbered question (Q<n>) can wait; answer this one now."
  [ -n "$key" ] || refuse "$doc is not under the bundle at $inst, so later has nowhere to record it."
  unlater "$key" 2>/dev/null || { echo "answer: could not save later under $later" >&2; exit 6; }
  echo "$qlabel on $task moved to the end."
  exit 0
fi

if [ "$forced" -eq 0 ] && [ "$reply" = "more" ]; then
  seen="$(cat "$depth_file" 2>/dev/null || echo 0)"
  out="$(block depth $((seen + 1)))"
  stored="$(head -n1 <<<"$out")"
  if [ "$((seen + 1))" -gt "$stored" ]; then
    echo "${qlabel:-This question} has no stored depth past $stored — answer it from the task in this session."
    exit 5
  fi
  { mkdir -p "$state" && { grep -qx '\*' "$state/.gitignore" 2>/dev/null || echo '*' > "$state/.gitignore"; } &&
    echo "$((seen + 1))" > "$depth_file.tmp" && mv -f "$depth_file.tmp" "$depth_file"; } 2>/dev/null ||
    { echo "answer: could not save the depth under $state, so nothing is shown" >&2; exit 6; }
  echo "Depth $((seen + 1)) of $stored · ${qlabel}"
  tail -n +2 <<<"$out"
  exit 0
fi

answer="$reply"
if [ "$forced" -eq 0 ] && [[ "$reply" =~ ^[0-9]+$ ]]; then
  [ -n "$qlabel" ] || refuse "This question has no options; to record the number itself, use --text $reply."
  out="$(block option "$reply")"
  have="$(head -n1 <<<"$out")"
  [ "$reply" -ge 1 ] && [ "$reply" -le "$have" ] ||
    refuse "$qlabel has no option $reply (it has $have); to record the number itself, use --text $reply."
  answer="$(tail -n +2 <<<"$out")"
fi

bash "$HERE/fold-answers.sh" --instance "$inst" --answer "$entry" "$answer" "$doc" >/dev/null || exit 3
rm -f "$depth_file"
unlater 2>/dev/null
echo "answered ${qlabel:-the question} on $task: $answer"

dir="$(cd "$(dirname "$doc")" && pwd -P)"
root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git work tree: nothing committed"; exit 0; }
( cd "$root" && bash "$HERE/commit-as.sh" human "docs: answer ${qlabel:-a question} on $task" --stage -- "$dir/$(basename "$doc")" >/dev/null ) ||
  { echo "answer: recorded, but the commit failed — commit it by hand" >&2; exit 4; }
bash "$HERE/push-commit.sh" "$root"
case $? in
  0) echo "committed and pushed" ;;
  3) echo "committed; no upstream, so not pushed" ;;
  *) exit 4 ;;
esac
