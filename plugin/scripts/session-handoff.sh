#!/usr/bin/env bash
#
# session-handoff.sh — stop a task's role session that only the HUMAN can move on, after
# filing what it waits for; and say when the round after that is owed. Run from the bundle
# root, one task per call.
#
#   session-handoff.sh <task-doc> [--jobs-dir <dir>]
#     task `done`/`cancelled` -> `stopped <short> <status>` (a pending `needs` is filed
#                                first), or `ended <short> <state>` when nothing was running
#     any other task, its session `blocked` with a `needs` and no live prompt
#                             -> `handed-off <short> <id> Q<n>`, then `claude stop <short>`
#   session-handoff.sh --owed <task-doc>
#                             -> `owed <uuid> <id>` then `answer: <text>`: the human answered
#                                the latest hand-off of the task's current session, nothing
#                                resumed it since, and the session has ended — resume it
#
# A HAND-OFF writes the agent's `needs` VERBATIM (whitespace folded) to the per-clone,
# ignored `$AB_HANDOFFS/<id>.txt`, which AWAITING.md renders — and the task gets only fixed
# text the tick wrote: ONE `Q<n>: do: …hand-off <id>…` entry in `open_questions`, its
# `### Q<n>` block, and a `needs handed off <uuid> · hand-off <id> · Q<n>` `# Notes` line, in
# one atomic write. `<id>` is `<short>-<8 hex>` over the session, its `startedAt` and the
# text, so a retry writes nothing twice and the next round's hand-off is a new entry.
#
# Exit 0 done · 1 not this script's case (`not-handed-off <why>`, `not-owed <why>`) · 2
# unknown (no `claude`, an unreadable record or task) · 3 the stop did not land (the record
# is written; the next tick stops again). Never `claude rm`.
#
# Why (measured 2026-10-21, CLI 2.1.301-2.1.304): a round that ends listing jobs for the
# human sits `blocked` with that list in `needs`, and `claude attach` showed nothing the
# string did not. Reasoning: docs/pm-design.md#step-4. Verified by tests/session-handoff.test.sh.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/bundle-paths.sh" || exit 2
usage() { sed -n '7,15p' "$0" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "session-handoff: python3 is required" >&2; exit 2; }

task=""; jobs="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/jobs"; owed=0
while [ $# -gt 0 ]; do
  case "$1" in
    --jobs-dir) [ $# -ge 2 ] || usage; jobs="$2"; shift 2 ;;
    --owed)     owed=1; shift ;;
    -h|--help)  sed -n '3,30p' "$0"; exit 0 ;;
    -*) usage ;;
    *) [ -z "$task" ] || usage; task="$1"; shift ;;
  esac
done
[ -n "$task" ] || usage
[ -f "$task" ] && [ -r "$task" ] || { echo "session-handoff: no readable task document: $task" >&2; exit 2; }

fm="$(awk 'NR==1 && $0!="---" {exit} /^---$/ {n++; if (n==2) exit; next} n==1' "$task")"
fmval() { printf '%s\n' "$fm" | sed -n "s/^$1:[[:space:]]*//p" | head -1 | sed 's/[[:space:]]#.*$//' | tr -d '"'"'"' '; }
status="$(fmval status)"; sid="$(fmval session)"
# The store is the BUNDLE's (`<root>/projects/<slug>/tasks/<doc>`), wherever this runs from.
tdir="$(dirname "$task")"; root="$(cd "$tdir/../../.." 2>/dev/null && pwd)"
[ -n "$root" ] && [ -f "$root/instance.config.json" ] || root="$PWD"
store="$root/$AB_HANDOFFS"
[ -n "$sid" ] || { echo "not-handed-off no-session"; exit 1; }
short="${sid%%-*}"
TERMINAL=" done gone stopped completed cancelled failed error exited "

# --- the owed round ---------------------------------------------------------------
if [ "$owed" = 1 ]; then
  case "$status" in done|cancelled) echo "not-owed task-$status"; exit 1 ;; esac
  state="$(bash "$HERE/agent-sessions.sh" state "$sid" 2>/dev/null)" || exit 2
  case "$state" in stopped|done) ;; *) echo "not-owed session-$state"; exit 1 ;; esac
  open="$(bash "$HERE/fold-answers.sh" --list "$task" open_questions 2>/dev/null)" || exit 2
  answered="$(bash "$HERE/fold-answers.sh" --list "$task" answered_questions 2>/dev/null)" || exit 2
  python3 - "$task" "$sid" "$open" "$answered" <<'PY'
import re, sys
path, sid, open_q, answered = sys.argv[1:5]
notes, last = open(path, encoding="utf-8").read().split("\n"), None
for i, l in enumerate(notes):
    m = re.search(r"needs handed off ([0-9a-f-]+) · hand-off ([0-9a-f]{8}-[0-9a-f]{8}) · (Q\d+)", l)
    if m:
        last = (i, m.group(1), m.group(2), m.group(3))
if not last:
    print("not-owed no-hand-off"); sys.exit(1)
i, uuid, hid, q = last
if not (uuid == sid or uuid.split("-")[0] == sid.split("-")[0]):
    print("not-owed session-replaced"); sys.exit(1)
# Step 4 writes `woke`/`resumed <uuid>` after a resume, or `resume launched; …` when it
# could not read the id back — every one of them means this hand-off was resumed.
if any(re.search(r"\b(woke|resumed) [0-9a-f]{8}|\bresume launched\b", l) for l in notes[i + 1:]):
    print("not-owed already-resumed"); sys.exit(1)
for e in answered.splitlines() + open_q.splitlines():
    body = re.sub(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z by [^\n]*? · ", "", e, count=1)
    if body.startswith(q + ": do: ") and hid in body:
        head, sep, ans = body.rpartition(" --- ")
        if sep and ans.strip():
            print("owed %s %s" % (uuid, hid)); print("answer: " + ans.strip()); sys.exit(0)
print("not-owed unanswered"); sys.exit(1)
PY
  exit $?
fi

# --- the hand-off and the stop ------------------------------------------------------
row="$(bash "$HERE/agent-sessions.sh" row "$sid" 2>/dev/null)"; rc=$?
case $rc in 0) ;; 3) row='{"state":"gone"}' ;; *) echo "session-handoff: cannot read session $sid" >&2; exit 2 ;; esac
rec="$jobs/$short/state.json"; [ -f "$rec" ] || rec="$jobs/$sid/state.json"
# -> `<state> <id|-> <uuid>` then the folded needs text; exit 2 unreadable.
read_needs() { # <row> <record> <session>
  python3 - "$@" <<'PY'
import hashlib, json, os, re, sys
row, rec, sid = json.loads(sys.argv[1]), sys.argv[2], sys.argv[3]
state = str(row.get("state") or row.get("status") or "working")
d = {}
if os.path.exists(rec):
    try:
        d = json.load(open(rec, encoding="utf-8"))
        assert isinstance(d, dict)
    except Exception:
        sys.exit(2)
uuid = row.get("sessionId") or d.get("sessionId") or sid
needs = d.get("needs") if isinstance(d.get("needs"), str) else ""
needs = re.sub(r"\s+", " ", "".join(c if c.isprintable() else " " for c in needs)).strip()
# A live prompt is answered in the session, never filed: a fresh round would park on it.
if not needs or row.get("waitingFor") or d.get("waitingFor"):
    hid = "-"
else:
    h = hashlib.sha256("\n".join([uuid, str(row.get("startedAt")), needs]).encode()).hexdigest()[:8]
    hid = "%s-%s" % (uuid.split("-")[0], h)
print(state, hid, uuid, "waiting" if (row.get("waitingFor") or d.get("waitingFor")) else "-")
print(needs)
PY
}
info="$(read_needs "$row" "$rec" "$sid")" || { echo "session-handoff: unreadable job record $rec" >&2; exit 2; }
read -r state hid uuid waiting <<EOF
$info
EOF
needs="$(printf '%s\n' "$info" | sed -n '2,$p')"

stop_it() { # -> 0 the stop landed, 3 it did not
  claude stop "$short" >/dev/null 2>&1 </dev/null
  local after; after="$(bash "$HERE/agent-sessions.sh" state "$sid" 2>/dev/null)" || after=unknown
  case "$after" in stopped|done|gone) return 0 ;; esac
  echo "session-handoff: claude stop $short did not land (state: $after)" >&2
  return 3
}

# ONE atomic write: the entry, its block and the note land together or not at all, on a
# copy beside the task that replaces it only after it reads back.
file_it() { # -> prints Q<n>
  mkdir -p "$store" && { [ -f "$store/.gitignore" ] || printf '*\n' > "$store/.gitignore"; } \
    && printf '%s\n' "$needs" > "$store/$hid.txt" || return 2
  local qn n entry tmp="$(dirname "$task")/.session-handoff.$$.md"
  # The highest number in use ANYWHERE: an `advisor: Q1:` entry and a `### Q1` heading
  # both hold their number, and a second `### Q1` would answer the wrong block.
  qn="$( { bash "$HERE/fold-answers.sh" --list "$task" open_questions; bash "$HERE/fold-answers.sh" --list "$task" answered_questions
           sed -n 's/^### \(Q[0-9][0-9]*\)[[:space:]]*$/\1:/p' "$task"; } 2>/dev/null \
        | grep -oE '(^|[^A-Za-z0-9])Q[0-9]+:' | grep -oE '[0-9]+' | sort -n | tail -1)"
  n="Q$(( ${qn:-0} + 1 ))"
  entry="$n: do: finish the agent's hand-off $hid — its jobs are in AWAITING.md; answer done, or with what its next round should know"
  cp -p "$task" "$tmp" || return 2
  bash "$HERE/fold-answers.sh" --add "$tmp" "$entry" >/dev/null || { rm -f "$tmp"; return 2; }
  python3 - "$tmp" "$n" "$hid" "$uuid" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$AB_HANDOFFS" <<'PY' || { rm -f "$tmp"; return 2; }
import re, sys
path, q, hid, uuid, now, store = sys.argv[1:7]
src = open(path, encoding="utf-8").read()
end = src.find("\n---", 3) + 4
head, lines = src[:end], src[end:].split("\n")
def section_end(start):
    for i in range(start + 1, len(lines)):
        if re.match(r"#{1,2}\s", lines[i]):
            return i
    return len(lines)
def append_to(heading, add):
    global lines
    at = next((i for i, l in enumerate(lines) if re.match(re.escape(heading) + r"\s*$", l)), None)
    if at is None:
        while lines and not lines[-1].strip():
            lines.pop()
        lines += ["", heading, ""] + add + [""]
        return
    e = section_end(at)
    while e > at + 1 and not lines[e - 1].strip():
        e -= 1
    lines[e:e] = add
append_to("## Question details", ["", "### " + q,
    "Recommendation: done",
    "Options:",
    "1. done",
    "Context:",
    "- Depth 1: A role session ended its round (hand-off %s) with jobs only you can do, and the tick stopped it." % hid,
    "- Depth 2: The jobs are in AWAITING.md; the full text is `%s/%s.txt` on the clone that filed it, and `claude logs %s` shows the session." % (store, hid, uuid.split("-")[0]),
    "- Depth 3: Your answer is the resumed session's next message — `done`, or anything it should know first."])
append_to("# Notes", ["* %s needs handed off %s · hand-off %s · %s · session stopped by the tick" % (now, uuid, hid, q)])
out = head + "\n".join(lines)
open(path, "w", encoding="utf-8").write(out if out.endswith("\n") else out + "\n")
PY
  # Read it back before it replaces the task: the entry once, the note once.
  [ "$(bash "$HERE/fold-answers.sh" --list "$tmp" open_questions 2>/dev/null | grep -cF "hand-off $hid ")" = 1 ] \
    && [ "$(grep -cF "· hand-off $hid ·" "$tmp")" = 1 ] && mv -f "$tmp" "$task" || { rm -f "$tmp"; return 2; }
  printf '%s' "$n"
}

handoff() { # -> 0 filed (or already filed), 2 a write failed; sets q
  q="$(grep -oE "· hand-off $hid · Q[0-9]+" "$task" | head -1 | grep -oE 'Q[0-9]+$')"
  [ -n "$q" ] && return 0
  q="$(file_it)" || { echo "session-handoff: could not file the hand-off in $task" >&2; return 2; }
}

case "$status" in
  done|cancelled)
    # Jobs left for after the merge are filed first: the done path never discards them.
    if [ "$state" = blocked ] && [ "$hid" != - ]; then handoff || exit 2; fi
    case "$TERMINAL" in *" $state "*) echo "ended $short $state"; exit 0 ;; esac
    stop_it || exit 3
    echo "stopped $short $status"; exit 0 ;;
esac

[ "$state" = blocked ] || { echo "not-handed-off not-blocked $state"; exit 1; }
[ "$waiting" = - ] || { echo "not-handed-off waiting-for"; exit 1; }
[ "$hid" != - ] || { echo "not-handed-off no-needs"; exit 1; }
handoff || exit 2
stop_it || exit 3
echo "handed-off $short $hid $q"
