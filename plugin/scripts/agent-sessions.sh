#!/usr/bin/env bash
#
# agent-sessions.sh — what a dispatched BACKGROUND role-agent session is doing.
#
#   agent-sessions.sh state <session-id>      -> the raw state `claude agents` reports
#                                                (working|blocked|done|gone, …) on stdout
#   agent-sessions.sh resolve <session-id>    -> the full session UUID `--resume` needs;
#                                                exit 1 when none or more than one matches
#   agent-sessions.sh stalled <session-id> [--projects-dir <dir>]
#                                             -> exit 0 `stalled <uuid>`: blocked, no
#                                                `waitingFor`, and no assistant turn since
#                                                it started; 1 not
#   agent-sessions.sh in-flight <bundle-root> -> how many recorded sessions still hold a
#                                                slot, on stdout; one line per recorded
#                                                session on stderr
#   agent-sessions.sh view <bundle-root> [--summary]
#                                             -> this bundle's background sessions, one
#                                                row each: task, state, process, age, id;
#                                                `--summary` prints `<running> <no-process>`
#
# Exit 0 answered · 2 unknown (no `claude`, no `python3`, unreadable JSON) — and unknown is
# never a zero, because "nothing is running" is what a broken read and an idle loop both
# look like. Reasoning: docs/pm-design.md#step-3-background.
# Verified by tests/background-dispatch.test.sh, tests/agent-view.test.sh and
# tests/resume-full-id.test.sh.
set -uo pipefail

usage() { sed -n '3,19p' "$0" >&2; exit 2; }
[ $# -ge 1 ] || usage

command -v python3 >/dev/null 2>&1 || {
  echo "agent-sessions: python3 is required to read \`claude agents --json\`" >&2; exit 2; }

# `--all` keeps a COMPLETED session in the listing, which is what makes `done` and `gone`
# two different answers: without it a finished agent is indistinguishable from one that
# never started, and the tick would read a clean exit as a dispatch that vanished.
sessions_json() {
  command -v claude >/dev/null 2>&1 || return 1
  claude agents --json --all 2>/dev/null </dev/null
}

# The short id `--bg` prints is the first field of `sessionId`, so one recorded value
# matches either spelling.
state_of() { # <session-id> <json>
  python3 -c '
import json, sys
want = sys.argv[1]
try:
    rows = json.loads(sys.argv[2])
except Exception:
    sys.exit(2)
for r in rows:
    sid = r.get("sessionId") or ""
    if want == r.get("id") or want == sid or sid.split("-")[0] == want:
        print(r.get("state") or r.get("status") or "working")
        sys.exit(0)
print("gone")
' "$1" "$2"
}

# `--resume` reads a short id as a picker SEARCH TERM, and a `--bg` session parks on the
# picker — so this counts matches rather than taking the first, as `state_of` does.
match_of() { # <session-id> <json> -> the one matching row as JSON; 1 none/several, 2 unreadable
  python3 -c '
import json, re, sys
want = sys.argv[1]
try:
    rows = json.loads(sys.argv[2])
    assert isinstance(rows, list)
except Exception:
    sys.exit(2)
hits = {}
for r in rows:
    if not isinstance(r, dict):
        continue
    sid = r.get("sessionId") or ""
    if want == r.get("id") or want == sid or sid.split("-")[0] == want:
        hits[sid] = r
if len(hits) != 1:
    print("agent-sessions: %d sessions match %s, not resolving" % (len(hits), want), file=sys.stderr)
    sys.exit(1)
sid, r = hits.popitem()
if not re.fullmatch(r"[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}", sid):
    print("agent-sessions: %s has no full session id" % want, file=sys.stderr)
    sys.exit(2)
print(json.dumps(r))
' "$1" "$2"
}

# Only an explicitly terminal value frees a slot. Anything else holds one — `idle`
# included, since a waiting session still holds work and counting it free dispatches past
# the cap — and a value outside the known vocabulary is named, so a change in what
# `claude agents --json` emits is a visible line rather than a silent wedge.
TERMINAL="done gone stopped completed cancelled failed error exited"
holds_slot() { # <state> <session-id> -> 0 holds a slot, 1 frees it
  local t
  for t in $TERMINAL; do [ "$1" = "$t" ] && return 1; done
  case "$1" in
    working|blocked) ;;
    *) echo "agent-sessions: unrecognised state '$1' for session $2 — counted live" >&2 ;;
  esac
  return 0
}

case "$1" in
  state)
    [ $# -eq 2 ] || usage
    json="$(sessions_json)" || { echo "agent-sessions: no \`claude\` on PATH" >&2; exit 2; }
    state_of "$2" "$json" || { echo "agent-sessions: could not read the session list" >&2; exit 2; }
    ;;

  resolve)
    [ $# -eq 2 ] || usage
    json="$(sessions_json)" || { echo "agent-sessions: no \`claude\` on PATH" >&2; exit 2; }
    row="$(match_of "$2" "$json")" || exit $?
    python3 -c 'import json, sys; print(json.loads(sys.argv[1])["sessionId"])' "$row"
    ;;

  stalled)
    [ $# -eq 2 ] || [ $# -eq 4 ] || usage
    projects="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
    if [ $# -eq 4 ]; then [ "$3" = "--projects-dir" ] || usage; projects="$4"; fi
    json="$(sessions_json)" || { echo "agent-sessions: no \`claude\` on PATH" >&2; exit 2; }
    row="$(match_of "$2" "$json" 2>/dev/null)"; rc=$?
    [ $rc -eq 1 ] && { echo "not-stalled unresolved"; exit 1; }
    [ $rc -eq 0 ] || exit 2
    # Every resume mints a new id (measured on CLI 2.1.295), so `startedAt` IS the resume.
    python3 - "$row" "$projects" <<'PY'
import glob, json, os, sys
from datetime import datetime
r, projects = json.loads(sys.argv[1]), sys.argv[2]
sid, started = r["sessionId"], r.get("startedAt")
state = str(r.get("state") or r.get("status") or "")
if state != "blocked":
    print("not-stalled " + (state or "unknown"))
    sys.exit(1)
# A login or other live prompt parks a fresh round too, so it stays the human's.
if r.get("waitingFor"):
    print("not-stalled waiting-for")
    sys.exit(1)
if not isinstance(started, (int, float)) or isinstance(started, bool):
    sys.exit(2)
found = glob.glob(os.path.join(glob.escape(projects), "*", sid + ".jsonl"))
if len(found) > 1:
    sys.exit(2)
try:
    lines = open(found[0], encoding="utf-8").read().splitlines() if found else []
except (OSError, UnicodeDecodeError):
    sys.exit(2)
for i, line in enumerate(lines):
    try:
        e = json.loads(line)
    except ValueError:
        # Only a half-written LAST line is expected; any other could be hiding a turn.
        if i == len(lines) - 1:
            continue
        sys.exit(2)
    if not isinstance(e, dict) or e.get("type") != "assistant":
        continue
    try:
        t = datetime.fromisoformat(str(e.get("timestamp")).replace("Z", "+00:00")).timestamp()
    except ValueError:
        sys.exit(2)
    if t * 1000 >= started:
        print("not-stalled took-a-turn")
        sys.exit(1)
print("stalled " + sid)
PY
    ;;

  in-flight)
    [ $# -eq 2 ] || usage
    root="$2"
    [ -d "$root" ] || { echo "agent-sessions: no such bundle root: $root" >&2; exit 2; }
    json="$(sessions_json)" || { echo "agent-sessions: no \`claude\` on PATH" >&2; exit 2; }

    live=0
    for task in "$root"/projects/*/tasks/*.md; do
      [ -f "$task" ] || continue
      fm="$(awk 'NR==1 && $0!="---" {exit} /^---$/ {n++; if (n==2) exit; next} n==1' "$task")"
      # Terminal tasks only are skipped, never "not in-progress": a `qa-reviewer` on an
      # `in-review` task and a rolled-back `ready` task whose spawn actually survived both
      # hold a real slot, and the SESSION's own state is what decides — not the document's.
      case "$(printf '%s\n' "$fm" | sed -n 's/^status:[[:space:]]*//p' | head -1)" in
        done|cancelled) continue ;;
      esac
      sid="$(printf '%s\n' "$fm" | sed -n 's/^session:[[:space:]]*//p' | head -1 \
             | tr -d '"'"'"' ' | sed 's/#.*$//')"
      [ -n "$sid" ] || continue
      st="$(state_of "$sid" "$json")" || { echo "agent-sessions: could not read the session list" >&2; exit 2; }
      holds_slot "$st" "$sid" && live=$((live+1))
      printf '%-8s %s  %s\n' "$st" "$sid" "$task" >&2
    done
    printf '%s\n' "$live"
    ;;

  view)
    [ $# -ge 2 ] && [ $# -le 3 ] || usage
    root="$2"; summary=0
    if [ $# -eq 3 ]; then [ "$3" = "--summary" ] || usage; summary=1; fi
    [ -d "$root" ] || { echo "agent-sessions: no such bundle root: $root" >&2; exit 2; }
    json="$(sessions_json)" || { echo "agent-sessions: no \`claude\` on PATH" >&2; exit 2; }
    here="$(dirname "${BASH_SOURCE[0]:-$0}")"
    wtroot="$(bash "$here/resolve-config.sh" --instance "$root" worktreeRoot 2>/dev/null)" || wtroot=""
    if [ -z "$wtroot" ]; then
      rr="$(bash "$here/resolve-config.sh" --instance "$root" reposRoot 2>/dev/null)" || rr=""
      [ -n "$rr" ] && wtroot="$rr/_wt"
    fi
    # `<worktree> TAB <task file>` per task that recorded one, terminal tasks included: a
    # merged task's lingering session is still THAT task's session.
    set -- "$root"/projects/*/tasks/*.md
    tasks=""
    [ -e "$1" ] && tasks="$(awk '
      FNR == 1 { fm = 0; hit = 0; if ($0 == "---") { fm = 1; next } }
      fm && $0 == "---" { fm = 0; next }
      fm && !hit && /^worktree:/ {
        hit = 1; v = $0
        sub(/^worktree:[[:space:]]*/, "", v); sub(/[[:space:]]+#.*$/, "", v); gsub(/["\047]/, "", v)
        if (v != "") print v "\t" FILENAME
      }' "$@" 2>/dev/null)"
    python3 - "$json" "$root" "$wtroot" "$TERMINAL" "$summary" "$tasks" <<'PY' || {
import json, os, re, sys, time, unicodedata
raw, root, wtroot, terminal, summary, tasks = sys.argv[1:7]
try:
    rows = json.loads(raw)
except Exception:
    sys.exit(2)
if not isinstance(rows, list):
    sys.exit(2)
terminal = set(terminal.split())
def canon(p):
    return os.path.realpath(os.path.expanduser(p)) if p else ""
def under(p, d):
    return bool(p and d) and (p == d or p.startswith(d.rstrip("/") + "/"))
by_wt = []
for line in tasks.splitlines():
    wt, _, path = line.partition("\t")
    if wt and path:
        stem = os.path.basename(path)[:-3]
        m = re.match(r"(task-[0-9]+)-", stem)
        label = os.path.basename(os.path.dirname(os.path.dirname(path))) + "/" + (m.group(1) if m else stem)
        by_wt.append((canon(wt), label))
scope = [canon(root), canon(wtroot)] + [w for w, _ in by_wt]

# A PROCESS, not the registry's word for one: a session the registry still lists as
# `blocked` after its agent died carries no live pid, and `state` cannot tell the two apart.
# EPERM means the process EXISTS; only ESRCH may be rendered as "no process".
def alive(pid):
    if not isinstance(pid, int) or isinstance(pid, bool) or pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except PermissionError:
        return True
    except OSError:
        return False
    return True

# Display only — classification above reads the raw value, as `in-flight` does.
# Every printed field comes from JSON or a file name, so no control character reaches a terminal.
def clean(v):
    return "".join(ch for ch in str(v) if unicodedata.category(ch)[0] != "C")

def age(ms):
    if not isinstance(ms, (int, float)) or isinstance(ms, bool):
        return "?"
    s = max(0, int(time.time() - ms / 1000))
    for unit, n in (("d", 86400), ("h", 3600), ("m", 60)):
        if s >= n:
            return "%d%s" % (s // n, unit)
    return "%ds" % s

out, running, ghost, ended = [], 0, 0, 0
for r in rows:
    if not isinstance(r, dict) or r.get("kind", "background") != "background":
        continue
    cwd = r.get("cwd") if isinstance(r.get("cwd"), str) else ""
    c = canon(cwd)
    # Another bundle's session is out of scope; a row with no cwd cannot be placed, so it
    # is shown as unattributed rather than assumed to be someone else's.
    if c and not any(under(c, d) for d in scope):
        continue
    labels = sorted({l for w, l in by_wt if under(c, w)})
    task = clean(",".join(labels) if labels else "unattributed")
    state = str(r.get("state") or r.get("status") or "?")
    pid = r.get("pid")
    if alive(pid):
        proc, rank = "pid %d" % pid, 0
        running += 1
    elif state in terminal:
        ended += 1
        continue
    else:
        proc, rank = "none", 1
        ghost += 1
    sid = clean(r.get("id") or str(r.get("sessionId") or "?").split("-")[0])
    where = "" if labels else "  " + clean(cwd or "(no cwd)")
    out.append((rank, task, clean(state), proc, age(r.get("startedAt")), sid + where))

if summary == "1":
    print(running, ghost)
    sys.exit(0)
w = max([len("TASK")] + [len(o[1]) for o in out])
fmt = "%-" + str(w) + "s  %-9s %-10s %-5s %s"
print(fmt % ("TASK", "STATE", "PROCESS", "AGE", "SESSION"))
for o in sorted(out):
    print(fmt % o[1:])
print("%d running · %d no process · %d ended, not listed" % (running, ghost, ended))
PY
      echo "agent-sessions: could not read the session list" >&2; exit 2; }
    ;;

  -h|--help) sed -n '3,19p' "$0"; exit 0 ;;
  *) usage ;;
esac
