#!/usr/bin/env bash
#
# session-handoff.sh — stop a task's role session that only the HUMAN can move on, after
# writing down what it is waiting for. One task per call; run from the bundle root.
#
#   session-handoff.sh <task-doc> [--jobs-dir <dir>]
#
#   task `done`/`cancelled`  -> `stopped <short> <status>` after `claude stop <short>`, or
#                               `ended <short> <state>` when the session had already ended
#   any other task whose session is `blocked` with a `needs` in its job record
#                            -> `handed-off <short> do=<n> ask=<Q labels|->`: each job the
#                               `needs` names is a `do: <job>` entry and each question a
#                               numbered `Q<n>:` entry (with its `### Q<n>` block) in
#                               `open_questions`, one `needs handed off <uuid>` `# Notes`
#                               line, then `claude stop <short>`
#
# Exit 0 done · 1 not this script's case (`not-handed-off <why>`) — step 4's other rows
# apply · 2 unknown (no `claude`, an unreadable record or task) · 3 the stop did not land
# (the record is written; the next tick stops again, and writes nothing twice).
#
# Why (measured 2026-10-21, CLI 2.1.303): a round that ends listing jobs for the human —
# "review, apply and merge terraform#866; re-login SSO …" — sits `blocked` with that list
# in `needs`, and attaching shows the human nothing the string does not. The list goes to
# the task document, where AWAITING.md renders one `do` row per job, and the slot is freed.
# The text is kept as written, minus anything shaped like a credential. `claude stop` takes
# the SHORT id and is safe on a settled session; `claude rm` is never run here.
# Reasoning: docs/pm-design.md#step-4. Verified by tests/session-handoff.test.sh.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
usage() { sed -n '6,7p' "$0" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "session-handoff: python3 is required" >&2; exit 2; }

task=""; jobs="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/jobs"
while [ $# -gt 0 ]; do
  case "$1" in
    --jobs-dir) [ $# -ge 2 ] || usage; jobs="$2"; shift 2 ;;
    -h|--help)  sed -n '3,27p' "$0"; exit 0 ;;
    -*) usage ;;
    *) [ -z "$task" ] || usage; task="$1"; shift ;;
  esac
done
[ -n "$task" ] || usage
[ -f "$task" ] && [ -r "$task" ] || { echo "session-handoff: no readable task document: $task" >&2; exit 2; }

fm="$(awk 'NR==1 && $0!="---" {exit} /^---$/ {n++; if (n==2) exit; next} n==1' "$task")"
fmval() { printf '%s\n' "$fm" | sed -n "s/^$1:[[:space:]]*//p" | head -1 | sed 's/[[:space:]]#.*$//' | tr -d '"'"'"' '; }
status="$(fmval status)"; sid="$(fmval session)"
[ -n "$sid" ] || { echo "not-handed-off no-session"; exit 1; }
short="${sid%%-*}"

TERMINAL=" done gone stopped completed cancelled failed error exited "
state="$(bash "$HERE/agent-sessions.sh" state "$sid" 2>/dev/null)" || {
  echo "session-handoff: cannot read the state of session $sid" >&2; exit 2; }

stop_it() { # -> 0 the stop landed, 3 it did not
  claude stop "$short" >/dev/null 2>&1 </dev/null
  local after; after="$(bash "$HERE/agent-sessions.sh" state "$sid" 2>/dev/null)" || after=unknown
  case "$after" in stopped|done|gone) return 0 ;; esac
  echo "session-handoff: claude stop $short did not land (state: $after)" >&2
  return 3
}

# A finished task's session is the tick's to stop, whatever it is still doing.
case "$status" in
  done|cancelled)
    case "$TERMINAL" in *" $state "*) echo "ended $short $state"; exit 0 ;; esac
    stop_it || exit 3
    echo "stopped $short $status"; exit 0 ;;
esac

[ "$state" = blocked ] || { echo "not-handed-off not-blocked $state"; exit 1; }
rec="$jobs/$short/state.json"; [ -f "$rec" ] || rec="$jobs/$sid/state.json"
[ -f "$rec" ] || { echo "not-handed-off no-job-record"; exit 1; }

open="$(bash "$HERE/fold-answers.sh" --list "$task" open_questions 2>/dev/null)" || {
  echo "session-handoff: cannot read open_questions in $task" >&2; exit 2; }
answered="$(bash "$HERE/fold-answers.sh" --list "$task" answered_questions 2>/dev/null)" || answered=""

# -> JSON {uuid, entries, blocks, labels, jobs}; exit 1 no `needs`, 2 unreadable. A function,
# not a heredoc inside `$(…)`: bash 3.2 mis-reads an apostrophe in one.
plan_of() { # <record> <session> <open> <answered> <now>
  python3 - "$@" <<'PY'
import json, re, sys
rec, sid, open_q, answered, now = sys.argv[1:6]
try:
    d = json.load(open(rec, encoding="utf-8"))
    assert isinstance(d, dict)
except Exception:
    sys.exit(2)
needs = d.get("needs")
if not isinstance(needs, str) or not needs.strip():
    sys.exit(1)
uuid = d.get("sessionId") if re.fullmatch(r"[0-9a-f-]{36}", str(d.get("sessionId"))) else sid

# Free text from an agent: anything shaped like a credential goes, the rest stays verbatim.
SECRETS = [
    (r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})", "[redacted]"),
    (r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b", "[redacted]"),
    (r"\bxox[abprs]-[A-Za-z0-9-]{10,}", "[redacted]"),
    (r"\bsk-[A-Za-z0-9_-]{20,}", "[redacted]"),
    (r"(?i)\b(password|passwd|secret|token|api[_-]?key)(\s*[=:]\s*)\S+", r"\1\2[redacted]"),
    (r"-----BEGIN [A-Z ]+-----", "[redacted]"),
]
def clean(s):
    s = "".join(c if c.isprintable() else " " for c in s)
    for pat, rep in SECRETS:
        s = re.sub(pat, rep, s)
    s = re.sub(r"\s+", " ", s.replace(" --- ", " — ")).strip().rstrip(".").strip()
    return s[:300]

open_lines = [l for l in open_q.splitlines() if l.strip()]
open_labels = {m.group(1) for l in open_lines for m in [re.match(r"(Q\d+):", l)] if m}
used = {int(n) for l in open_lines + answered.splitlines() for n in re.findall(r"\bQ(\d+):", l)}
nxt = max(used or {0}) + 1
entries, blocks, labels = [], [], []
for part in re.split(r"\n+|;\s*|(?<=[.!?])\s+(?=[A-Z])", needs):
    part = clean(re.sub(r"^\s*(?:[-*•]|\(?\d+[.)])\s+", "", part))
    if not part:
        continue
    refs = {"Q" + n for n in re.findall(r"\bQ(\d+)\b", part)}
    if re.match(r"(?i)answer\b", part) and refs and refs <= open_labels:
        continue  # those questions are already on the human's queue
    if part.endswith("?") or re.match(r"(?i)(decide|choose|pick)\b", part):
        q = "Q%d" % nxt
        nxt += 1
        labels.append(q)
        entries.append("%s: %s" % (q, part))
        blocks.append("\n".join([
            "### " + q,
            "Recommendation: answer in your own words — the agent asked this without options",
            "Options:",
            "1. answer in your own words — the agent asked this without options",
            "Context:",
            "- Depth 1: This task's role session ended its round asking this, and the tick stopped it.",
            "- Depth 2: Copied from the session's job record on %s; your ` --- ` answer is carried to the next round, which resumes the same session." % now,
            "- Depth 3: Session %s. Its transcript: `claude logs %s`." % (uuid, uuid.split("-")[0]),
        ]))
    else:
        entries.append("do: " + part)
print(json.dumps({"uuid": uuid, "entries": entries, "blocks": blocks, "labels": labels,
                  "jobs": sum(e.startswith("do: ") for e in entries)}))
PY
}
plan="$(plan_of "$rec" "$sid" "$open" "$answered" "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"; rc=$?
[ $rc -eq 1 ] && { echo "not-handed-off no-needs"; exit 1; }
[ $rc -eq 0 ] || { echo "session-handoff: unreadable job record $rec" >&2; exit 2; }
get() { python3 -c 'import json, sys; v = json.loads(sys.argv[1])[sys.argv[2]]; print("\n".join(v) if isinstance(v, list) else v)' "$plan" "$1"; }
uuid="$(get uuid)"; njobs="$(get jobs)"; labels="$(get labels | paste -sd, -)"

# ONCE per session: a re-run after a stop that did not land writes nothing twice.
if ! grep -qF "needs handed off $uuid" "$task"; then
  entries=(); while IFS= read -r e; do [ -n "$e" ] && entries+=("$e"); done <<EOF
$(get entries)
EOF
  if [ ${#entries[@]} -gt 0 ]; then
    bash "$HERE/fold-answers.sh" --add "$task" "${entries[@]}" >/dev/null || {
      echo "session-handoff: could not add to open_questions in $task" >&2; exit 2; }
  fi
  python3 - "$task" "$plan" "* $(date -u +%Y-%m-%dT%H:%M:%SZ) needs handed off $uuid · do=$njobs · ask=${labels:--} · session stopped by the tick" <<'PY' || { echo "session-handoff: could not write $task" >&2; exit 2; }
import json, os, re, sys, tempfile
path, plan, note = sys.argv[1], json.loads(sys.argv[2]), sys.argv[3]
src = open(path, encoding="utf-8").read()
end = src.find("\n---", 3) + 4
head, body = src[:end], src[end:]
lines = body.split("\n")
def section_end(start):  # the next column-0 heading of level 1-2 after `start`, or EOF
    for i in range(start + 1, len(lines)):
        if re.match(r"#{1,2}\s", lines[i]):
            return i
    return len(lines)
if plan["blocks"]:
    at = next((i for i, l in enumerate(lines) if re.match(r"## Question details\s*$", l)), None)
    add = "\n\n".join(plan["blocks"]).split("\n")
    if at is None:
        while lines and not lines[-1].strip():
            lines.pop()
        lines = lines + ["", "## Question details", ""] + add + [""]
    else:
        e = section_end(at)
        while e > at + 1 and not lines[e - 1].strip():
            e -= 1
        lines[e:e] = [""] + add
at = next((i for i, l in enumerate(lines) if re.match(r"# Notes\s*$", l)), None)
if at is None:
    lines = lines + ["", "# Notes", "", note]
else:
    e = section_end(at)
    while e > at + 1 and not lines[e - 1].strip():
        e -= 1
    lines[e:e] = [note]
out = head + "\n".join(lines)
if not out.endswith("\n"):
    out += "\n"
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(path)), prefix=".session-handoff.")
with os.fdopen(fd, "w", encoding="utf-8") as fh:
    fh.write(out)
os.chmod(tmp, os.stat(path).st_mode & 0o7777)
os.replace(tmp, path)
PY
fi

stop_it || exit 3
echo "handed-off $short do=$njobs ask=${labels:--}"
