#!/usr/bin/env bash
#
# unblock.sh — return one `blocked` task to `ready`, carrying the person's decision.
#
#   Usage: unblock.sh [--instance DIR] <task-doc> [--decision <words>...]
#
# No --decision: print last_blocker and the escalation note, write nothing. With one: a
# `# Notes` line stamped `by <login>`, stall_count 0, status ready, committed as the human.
# Exit: 0 done · 1 refused, one sentence · 2 usage · 3 a write failed · 4 committed, but the
#       commit or push failed — nothing forced. Reasoning: interactive-board/task-003.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
usage() { sed -n '5p' "$0" >&2; exit 2; }
refuse() { echo "$*"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "unblock: python3 is required" >&2; exit 2; }

inst="."; doc=""; decided=0; words=()
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) [ $# -ge 2 ] || usage; inst="$2"; shift 2 ;;
    --decision) decided=1; shift; words+=("$@"); break ;;
    -h|--help)  usage ;;
    *) [ -z "$doc" ] || usage; doc="$1"; shift ;;
  esac
done
[ -n "$doc" ] || usage
[ -r "$doc" ] || refuse "No task document at $doc."
task="$(basename "$doc" .md)"

# fm <key> — the first frontmatter value of <key>, one level of quotes removed.
fm() {
  python3 - "$doc" "$1" <<'PY'
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
if not lines or lines[0] != "---":
    sys.exit(0)
for l in lines[1:]:
    if l == "---":
        break
    m = re.match(r"%s:\s*(.*?)\s*$" % re.escape(sys.argv[2]), l)
    if m:
        v = m.group(1)
        if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
            v = v[1:-1].replace('\\"', '"').replace("\\\\", "\\")
        print(v)
        break
PY
}

status="$(fm status)"
[ "$status" = blocked ] || refuse "$task is ${status:-without a status}, not blocked — there is nothing to unblock."

if [ "$decided" -eq 0 ]; then
  echo "$task is blocked."
  echo "Last blocker: $(fm last_blocker)"
  note="$(grep -E '^- \*\*Stalled [0-9]+/[0-9]+ rounds' "$doc" | tail -n1)"
  echo "Escalation: ${note:-none recorded}"
  exit 0
fi
decision="$(printf '%s ' "${words[@]}" | tr '\n\t\r' '   ' | sed 's/  */ /g; s/^ //; s/ $//')"
[ -n "$decision" ] || usage

login="$(bash "$HERE/decision-stamp.sh" --instance "$inst" --self 2>/dev/null)"
[ -n "$login" ] || login="<unknown>"
line="- $(date -u +%Y-%m-%dT%H:%M:%SZ) by $login: unblocked — $decision"

# Retry-safe: the counter reset is idempotent, and the note and `status: ready` land in ONE
# atomic replace, so a failure leaves the task blocked with no note and a retry writes it once.
bash "$HERE/stall-counter.sh" reset "$doc" >/dev/null || { echo "unblock: could not reset the stall counter" >&2; exit 3; }
python3 - "$doc" "$line" <<'PY' || { echo "unblock: could not write the decision and status: ready" >&2; exit 3; }
import os, re, shutil, sys, tempfile
path, note = sys.argv[1], sys.argv[2]
lines = open(path, encoding="utf-8").read().rstrip("\n").split("\n")
close = next((i for i in range(1, len(lines)) if lines[i] == "---"), 0)
st = next((i for i in range(1, close) if re.match(r"status:", lines[i])), None)
if st is None:
    sys.exit(1)
lines[st] = "status: ready"
at = next((i for i, l in enumerate(lines) if l.rstrip() == "# Notes"), None)
if at is None:
    lines += ["", "# Notes", "", note]
else:
    end = next((i for i in range(at + 1, len(lines)) if lines[i].startswith("# ")), len(lines))
    while end > at + 1 and not lines[end - 1].strip():
        end -= 1
    lines[end:end] = (["", note] if end == at + 1 else [note]) + ([""] if end < len(lines) and lines[end].startswith("# ") else [])
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(path)), prefix=".unblock.")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    shutil.copymode(path, tmp)
    os.replace(tmp, path)
except BaseException:
    if os.path.exists(tmp):
        os.unlink(tmp)
    raise
PY
echo "unblocked $task: back to ready with your decision — the next tick dispatches it."

dir="$(cd "$(dirname "$doc")" && pwd -P)"
root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git work tree: nothing committed"; exit 0; }
( cd "$root" && bash "$HERE/commit-as.sh" human "docs: unblock $task" --stage -- "$dir/$(basename "$doc")" >/dev/null ) ||
  { echo "unblock: recorded, but the commit failed — commit it by hand" >&2; exit 4; }
bash "$HERE/push-commit.sh" "$root"
case $? in
  0) echo "committed and pushed" ;;
  3) echo "committed; no upstream, so not pushed" ;;
  *) exit 4 ;;
esac
