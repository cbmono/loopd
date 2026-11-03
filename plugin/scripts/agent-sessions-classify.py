# agent-sessions-classify.py — the one classifier behind `agent-sessions.sh view|working|dead-ids|
# stop-ids`: reads one `claude agents --json --all` listing and prints that mode's rows.
#   python3 agent-sessions-classify.py <listing-json> <root> <wtroot> <terminal> <summary> <tasks>
#                                      <skip> <recs> <self-ids> <bounds> <projects-dir>
# Exit 0 answered · 2 unreadable listing, or no row carries a pid (dead-ids, stop-ids).
# Reasoning: docs/pm-design.md#step-3-background.
import glob, json, os, re, sys, time, unicodedata
from datetime import datetime
from pid_alive import alive
raw, root, wtroot, terminal, summary, tasks, skip, recs, self_ids, bounds, projects = sys.argv[1:12]
try:
    rows = json.loads(raw)
except Exception:
    sys.exit(2)
if not isinstance(rows, list):
    sys.exit(2)
dead, stop, skip, self_ids = summary in ("dead", "stop"), summary == "stop", set(skip.split()), set(self_ids.split())
# With no pid anywhere, every row would read dead — a CLI that stopped emitting it.
if dead and rows and not any(isinstance(r, dict) and "pid" in r for r in rows):
    print("agent-sessions: no row carries a pid — liveness unknown", file=sys.stderr)
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
scope = [canon(root), canon(wtroot) if not dead else ""] + [w for w, _ in by_wt]
rec = {}
for line in recs.splitlines():
    s_, st_, path = (line.split("\t") + ["", ""])[:3]
    if s_ and path:
        rec[s_] = (st_, path)

def bound(v):
    return int(v) * 60 if re.fullmatch(r"[0-9]+", v) and int(v) > 0 else None
idle_s, busy_s = (bound(v) for v in (bounds.split() + ["", ""])[:2])

def user_text(e):
    c = (e.get("message") or {}).get("content") if isinstance(e.get("message"), dict) else None
    if isinstance(c, str):
        return True
    return (isinstance(c, list) and any(isinstance(b, dict) and b.get("type") == "text" for b in c)
            and not any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c))

# The transcript is the only clock for a turn (D7): `startedAt` counts idle days as busy ones.
def last_entry(sid, want):
    found = glob.glob(os.path.join(glob.escape(projects), "*", sid + ".jsonl"))
    if len(found) != 1:
        return None
    t = None
    try:
        for line in open(found[0], encoding="utf-8"):
            try:
                e = json.loads(line)
            except ValueError:
                continue
            if isinstance(e, dict) and e.get("type") == want and (want != "user" or user_text(e)):
                t = e.get("timestamp")
        return datetime.fromisoformat(str(t).replace("Z", "+00:00")).timestamp() if t else None
    except (OSError, UnicodeDecodeError, ValueError):
        return None
    return True

# Display only — classification above reads the raw value, as `in-flight` does.
# Every printed field comes from JSON or a file name, so no control character reaches a terminal.
def clean(v):
    return "".join(ch for ch in str(v) if unicodedata.category(ch)[0] != "C")

def secs(ms):
    if not isinstance(ms, (int, float)) or isinstance(ms, bool):
        return None
    return max(0, int(time.time() - ms / 1000))

def age(ms):
    s = secs(ms)
    if s is None:
        return "?"
    for unit, n in (("d", 86400), ("h", 3600), ("m", 60)):
        if s >= n:
            return "%d%s" % (s // n, unit)
    return "%ds" % s

out, working, idle, ghost, ended, cands, busy = [], 0, 0, 0, 0, [], []
for r in rows:
    if not isinstance(r, dict) or r.get("kind", "background" if not dead else None) != "background":
        continue
    if dead and not r.get("state"):
        continue
    if stop:
        sid, state, s = str(r.get("sessionId") or ""), str(r.get("state")), secs(r.get("startedAt"))
        hit = rec.get(sid) or rec.get(sid.split("-")[0])
        cls = None
        if (not re.fullmatch(r"[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}", sid)
                or self_ids & {sid, sid.split("-")[0]} or not alive(r.get("pid"))):
            pass
        elif hit is None and state in terminal:
            c = canon(r.get("cwd") if isinstance(r.get("cwd"), str) else "")
            if (under(c, canon(root)) and not under(c, canon(wtroot))
                    and not any(under(c, w) for w, _ in by_wt)):
                cls = "finished"
        elif hit and hit[0] not in ("done", "cancelled") and state not in terminal and state != "blocked":
            st, now = r.get("status"), time.time()
            if st == "idle" and idle_s:
                t = last_entry(sid, "assistant")
                cls = "idle" if t is not None and now - t >= idle_s else None
            elif st == "busy" and busy_s:
                t = last_entry(sid, "user")
                cls = "busy" if t is not None and now - t >= busy_s else None
        if cls:
            cands.append((-(s or 0), sid, age(r.get("startedAt")), cls, hit[1] if hit else "-"))
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
        st = r.get("status")
        if st == "busy" or (st is None and state == "working"):
            working += 1
            busy.append(str(r.get("sessionId") or ""))
        else:
            idle += 1
    elif state in terminal:
        ended += 1
        continue
    else:
        proc, rank = "none", 1
        ghost += 1
    if dead:
        sid, s = str(r.get("sessionId") or ""), secs(r.get("startedAt"))
        if (proc == "none" and not labels and c and s is not None
                and s >= (86400 if state == "blocked" else 600)
                and re.fullmatch(r"[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}", sid)
                and not skip & {sid, sid.split("-")[0]}):
            cands.append((-s, sid, age(r.get("startedAt")), "dead", "-"))
        continue
    sid = clean(r.get("id") or str(r.get("sessionId") or "?").split("-")[0])
    where = "" if labels else "  " + clean(cwd or "(no cwd)")
    out.append((rank, task, clean(state), proc, age(r.get("startedAt")), sid + where))

if dead:
    for _, sid, a, cls, task in sorted(cands):
        print(sid, sid.split("-")[0], a, *((cls, task) if stop else ()))
    sys.exit(0)
if summary == "1":
    print(working, idle, ghost)
    sys.exit(0)
if summary == "working":
    open_rec = {}
    for line in recs.splitlines():
        s_, st_, p_ = (line.split("\t") + ["", ""])[:3]
        if s_ and p_ and st_ not in ("done", "cancelled"):
            open_rec.setdefault(s_, os.path.basename(p_)[:-3])
    for sid in busy:
        short = sid.split("-")[0]
        print(clean(short or "?"), clean(open_rec.get(sid) or open_rec.get(short) or "unrecorded"))
    sys.exit(0)
w = max([len("TASK")] + [len(o[1]) for o in out])
fmt = "%-" + str(w) + "s  %-9s %-10s %-5s %s"
print(fmt % ("TASK", "STATE", "PROCESS", "AGE", "SESSION"))
for o in sorted(out):
    print(fmt % o[1:])
print("%d working · %d idle · %d dead · %d ended, not listed" % (working, idle, ghost, ended))
