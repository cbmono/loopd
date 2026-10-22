#!/usr/bin/env bash
# reflect-deploy.sh — step 5's write for a `done` task whose merge shipped nothing: where
# deploy-mode.sh says `manual`, ONE atomic write adds a `merged, not deployed` `# Notes`
# line, a `Q<n>: do: deploy <repo> …` entry naming the merged PR(s), and its `### Q<n>` block.
#   reflect-deploy.sh <task-doc> [--instance <bundle>]
# `UNKNOWN` fails toward manual: the same write, worded `deploy UNKNOWN`, so it is never lost.
# The human's ` --- done` answer, folded into answered_questions, is the deploy's record.
# Exit: 0 written (`deploy-owed Q<n>`) · 1 nothing to write (`auto`, `n/a`, `already Q<n>`)
# · 2 usage, not `done`, no `pr:`, or a write failed (file untouched) · 3 `deploy-unknown Q<n>`.
# Reasoning: kb-retrieval-and-papercut-fixes/task-008.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
usage() { sed -n '2,10p' "$0" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "reflect-deploy: python3 is required" >&2; exit 2; }
TASK=""; INSTANCE=()
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) [ $# -ge 2 ] || usage; INSTANCE=(--instance "$2"); shift 2 ;;
    -h|--help|-*) usage ;;
    *) [ -z "$TASK" ] || usage; TASK="$1"; shift ;;
  esac
done
[ -n "$TASK" ] && [ -f "$TASK" ] && [ -r "$TASK" ] || usage

fm="$(awk 'NR == 1 { if ($0 != "---") exit; next } $0 == "---" { exit } { print }' "$TASK")"
st="$(printf '%s\n' "$fm" | sed -n 's/^status:[[:space:]]*\([A-Za-z-]*\).*/\1/p' | head -n 1)"
[ "$st" = done ] || { echo "reflect-deploy: $TASK is not done" >&2; exit 2; }

mode="$(bash "$HERE/deploy-mode.sh" "$TASK" ${INSTANCE[@]+"${INSTANCE[@]}"})"
case "$mode" in
  manual) state="not deployed"; why="merged, not deployed" ;;
  auto|n/a) echo "$mode"; exit 1 ;;
  *) mode=UNKNOWN; state="deploy UNKNOWN"; why="merged, deploy state UNKNOWN (deploy-mode.sh on this task says why)" ;;
esac
q="$(grep -oE '· merged, (not deployed|deploy UNKNOWN) · .* · Q[0-9]+$' "$TASK" | head -n 1 | grep -oE 'Q[0-9]+$')"
[ -n "$q" ] && { echo "already $q"; exit 1; }

prs="$(printf '%s\n' "$fm" | awk '/^pr:/ { on = 1 } on && /^[A-Za-z_]+:/ && !/^pr:/ { exit } on' |
       grep -oE 'https://[^]"[:space:],]+/pull/[0-9]+' | tr '\n' ' ' | sed 's/ $//')"
[ -n "$prs" ] || { echo "reflect-deploy: no merged PR in pr: of $TASK" >&2; exit 2; }
repo="$(bash "$HERE/service-doc.sh" --repo "$TASK" 2>/dev/null)" || {
  [ "$mode" = UNKNOWN ] || exit 2; repo="(no target_repo)"; }

# The highest Q number in use anywhere, as session-handoff.sh allocates it.
qn="$( { bash "$HERE/fold-answers.sh" --list "$TASK" open_questions; bash "$HERE/fold-answers.sh" --list "$TASK" answered_questions
         sed -n 's/^### \(Q[0-9][0-9]*\)[[:space:]]*$/\1:/p' "$TASK"; } 2>/dev/null \
      | grep -oE '(^|[^A-Za-z0-9])Q[0-9]+:' | grep -oE '[0-9]+' | sort -n | tail -n 1)"
q="Q$(( ${qn:-0} + 1 ))"
entry="$q: do: deploy $repo — $prs $why; answer done once it is live"
tmp="$(dirname "$TASK")/.reflect-deploy.$$.md"
cp -p "$TASK" "$tmp" || exit 2
bash "$HERE/fold-answers.sh" --add "$tmp" "$entry" >/dev/null || { rm -f "$tmp"; exit 2; }
python3 - "$tmp" "$q" "$repo" "$prs" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$state" <<'PY' || { rm -f "$tmp"; exit 2; }
import re, sys
path, q, repo, prs, now, state = sys.argv[1:7]
src = open(path, encoding="utf-8").read()
end = src.find("\n---", 3) + 4
head, lines = src[:end], src[end:].split("\n")
def append_to(heading, add):
    at = next((i for i, l in enumerate(lines) if re.match(re.escape(heading) + r"\s*$", l)), None)
    if at is None:
        while lines and not lines[-1].strip():
            lines.pop()
        lines.extend(["", heading, ""] + add + [""])
        return
    e = next((i for i in range(at + 1, len(lines)) if re.match(r"#{1,2}\s", lines[i])), len(lines))
    while e > at + 1 and not lines[e - 1].strip():
        e -= 1
    lines[e:e] = add
append_to("## Question details", ["", "### " + q, "Recommendation: done", "Options:", "1. done", "Context:",
    ("- Depth 1: %s deploys by hand (`deploy: manual`), so merging %s shipped nothing yet." % (repo, prs) if state == "not deployed"
     else "- Depth 1: Whether merging %s deployed %s could not be read, so it is treated as not deployed." % (prs, repo)),
    "- Depth 2: Deploy it, then answer done; the answer, folded into answered_questions, is the deploy's record.",
    "- Depth 3: `deploy:` is read from this task, else from the Service doc for %s (SCHEMA.md → Service)." % repo])
append_to("# Notes", ["* %s · merged, %s · %s · %s · %s" % (now, state, repo, prs, q)])
out = head + "\n".join(lines)
open(path, "w", encoding="utf-8").write(out if out.endswith("\n") else out + "\n")
PY
[ "$(bash "$HERE/fold-answers.sh" --list "$tmp" open_questions 2>/dev/null | grep -cF "$q: do: deploy ")" = 1 ] \
  && [ "$(grep -cF "· merged, $state ·" "$tmp")" = 1 ] && mv -f "$tmp" "$TASK" || { rm -f "$tmp"; exit 2; }
[ "$mode" = UNKNOWN ] && { echo "deploy-unknown $q"; exit 3; }
echo "deploy-owed $q"
