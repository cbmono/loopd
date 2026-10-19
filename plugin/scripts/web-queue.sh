#!/usr/bin/env bash
#
# web-queue.sh — the web board's answer queue: its one writer, its one consumer, its ledger.
#
#   Usage: web-queue.sh append --from <login> [--instance DIR]   # entry JSON on stdin (board-serve.sh)
#          web-queue.sh consume [--instance DIR] [--window HOURS] # the tick, under its lock
#          web-queue.sh pending|status [--instance DIR]           # unconsumed count | {"consumed":{id:verdict}}
#
# consume prints `<id> <verdict>` per entry and never an entry's text. Exit: 0 ok · 1 refused,
# one line · 2 usage or I/O · 3 another consumer holds the queue · 4 no tick lock held.
# Reasoning: interactive-board/task-006 (docs/operations.md → "The answer queue: Sent, then Saved").
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/bundle-paths.sh" || exit 2
usage() { sed -n '5,7p' "$0" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "web-queue: python3 is required" >&2; exit 2; }

cmd="${1:-}"; [ $# -gt 0 ] && shift
case "$cmd" in append|consume|pending|status) ;; *) usage ;; esac
inst="."; from=""; window=24
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) [ $# -ge 2 ] || usage; inst="$2"; shift 2 ;;
    --from)     [ $# -ge 2 ] || usage; from="$2"; shift 2 ;;
    --window)   [ $# -ge 2 ] && [[ "$2" =~ ^[1-9][0-9]{0,3}$ ]] || usage; window="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[ -f "$inst/instance.config.json" ] || { echo "web-queue: not a loopd bundle: $inst" >&2; exit 2; }
inst="$(cd "$inst" && pwd -P)"
WQ_BODY=""; [ "$cmd" = append ] && WQ_BODY="$(head -c 16385)"
export WQ_BODY

exec python3 - "$cmd" "$inst" "$from" "$window" "$HERE" "$AB_QUEUE" "$AB_QUEUE_LEDGER" "$AB_LOCK" <<'PY'
import datetime, fcntl, json, os, re, subprocess, sys, tempfile
cmd, inst, frm, window, here, qrel, lrel, lockrel = sys.argv[1:9]
QUEUE, LEDGER = os.path.join(inst, qrel), os.path.join(inst, lrel)
QDIR = os.path.dirname(QUEUE)

ID = re.compile(r"[A-Za-z0-9_-]{8,64}")
TASK = re.compile(r"\w[\w.+-]*/\w[\w.+-]*")
QN = re.compile(r"Q[1-9][0-9]{0,2}")
REPO = re.compile(r"[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)?")
LOGIN = re.compile(r"[A-Za-z0-9]+(-[A-Za-z0-9]+)*")
SCHEMA = {"answer": ({"type", "id", "task", "q"}, {"option", "text", "change"}),
          "more": ({"type", "id", "task", "q"}, set()),
          "new-project": ({"type", "id", "title", "what", "who", "doneWhen", "repo"}, set())}
LIMIT = {"text": 2000, "title": 120, "what": 600, "who": 300, "doneWhen": 600, "repo": 100}
DEFERRED = {"unblock": "unblock is not queued in v1: it re-dispatches agent work on the page's text",
            "board": "board is not queued in v1: no command turns the board on"}
FINAL = {"saved", "already-answered", "replaced", "not-yours", "expired", "invalid", "refused",
         "no-more", "failed", "interrupted"}


def say(msg, code=1):
    print(msg)
    sys.exit(code)


def text(v, k):
    if not isinstance(v, str):
        return None, "%s must be text" % k
    v = " ".join(v.split())
    if not v:
        return None, "%s is empty" % k
    if len(v) > LIMIT[k]:
        return None, "%s is longer than %d characters" % (k, LIMIT[k])
    if any(ord(c) < 32 or ord(c) == 127 for c in v):
        return None, "%s carries a control character" % k
    return v, None


def validate(d):
    if not isinstance(d, dict):
        return None, "an entry is one JSON object"
    t = d.get("type")
    if t in DEFERRED:
        return None, DEFERRED[t]
    if t not in SCHEMA:
        return None, "unknown type"
    req, opt = SCHEMA[t]
    extra = sorted(set(d) - req - opt)
    if extra:
        return None, "unknown key: %s" % extra[0]
    if req - set(d):
        return None, "missing key: %s" % sorted(req - set(d))[0]
    if not (isinstance(d["id"], str) and ID.fullmatch(d["id"])):
        return None, "id must be 8-64 letters, digits, - or _"
    out = {"id": d["id"], "type": t}
    if t in ("answer", "more"):
        if not (isinstance(d["task"], str) and TASK.fullmatch(d["task"])):
            return None, "task must be <project>/<task-id>"
        if not (isinstance(d["q"], str) and QN.fullmatch(d["q"])):
            return None, "q must be Q<n>"
        out.update(task=d["task"], q=d["q"])
    if t == "answer":
        if ("option" in d) == ("text" in d):
            return None, "an answer carries exactly one of option or text"
        if "option" in d:
            o = d["option"]
            if type(o) is not int or not 1 <= o <= 99:
                return None, "option must be a whole number from 1 to 99"
            out["option"] = o
        else:
            v, err = text(d["text"], "text")
            if err:
                return None, err
            out["text"] = v
        if "change" in d:
            if type(d["change"]) is not bool:
                return None, "change must be true or false"
            out["change"] = d["change"]
    if t == "new-project":
        for k in ("title", "what", "who", "doneWhen", "repo"):
            v, err = text(d[k], k)
            if err:
                return None, err
            out[k] = v
        if not REPO.fullmatch(out["repo"]):
            return None, "repo must be owner/name"
    return out, None


def ensure_dir():
    os.makedirs(QDIR, exist_ok=True)
    ig = os.path.join(QDIR, ".gitignore")
    if not os.path.exists(ig):
        with open(ig, "w") as fh:
            fh.write("*\n")


def lock(name, block):
    ensure_dir()
    fh = open(os.path.join(QDIR, name), "w")
    try:
        fcntl.flock(fh, fcntl.LOCK_EX | (0 if block else fcntl.LOCK_NB))
    except BlockingIOError:
        say("web-queue: another consumer holds the queue", 3)
    return fh


def lines(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return [l for l in fh.read().split("\n") if l.strip()]
    except FileNotFoundError:
        return []


def ledger():
    seen = {}
    for l in lines(LEDGER):
        try:
            r = json.loads(l)
            seen[r["id"]] = r["verdict"]
        except (ValueError, KeyError, TypeError):
            continue
    return seen


def append_line(path, rec):
    fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
    try:
        os.write(fd, (json.dumps(rec, ensure_ascii=False, sort_keys=True) + "\n").encode())
        os.fsync(fd)
    finally:
        os.close(fd)


def now():
    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0)


def iso(t):
    return t.strftime("%Y-%m-%dT%H:%M:%SZ")


def ident(line):
    try:
        d = json.loads(line)
    except ValueError:
        return None, None
    if isinstance(d, dict) and isinstance(d.get("id"), str) and ID.fullmatch(d["id"]):
        return d["id"], d
    return None, None


def entries():
    return [d for i, d in map(ident, lines(QUEUE)) if i]


if cmd == "append":
    if not (LOGIN.fullmatch(frm) or frm == "<unknown>"):
        say("web-queue: --from takes this clone's login", 2)
    try:
        d = json.loads(os.environ["WQ_BODY"])
    except ValueError:
        say("refused: the body is not JSON")
    e, err = validate(d)
    if err:
        say("refused: " + err)
    with lock(".write.lock", True):
        if e["id"] in ledger() or any(x["id"] == e["id"] for x in entries()):
            say("refused: that id is already queued")
        e.update(ts=iso(now()), **{"from": frm})
        append_line(QUEUE, e)
    print(json.dumps({"id": e["id"], "ts": e["ts"]}))
    sys.exit(0)

if cmd == "pending":
    done = ledger()
    print(sum(1 for e in entries() if e["id"] not in done))
    sys.exit(0)

if cmd == "status":
    done = {k: v for k, v in ledger().items() if v in FINAL}
    print(json.dumps({"consumed": dict(list(done.items())[-1000:])}, sort_keys=True))
    sys.exit(0)

# ---- consume -------------------------------------------------------------------------
if not os.path.exists(os.path.join(inst, lockrel)):
    say("web-queue: consume runs inside a dispatch tick, under its lock", 4)


def run(args, **kw):
    try:
        return subprocess.run(["bash"] + args, cwd=inst, stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL, timeout=300, **kw).returncode
    except Exception:
        return 99


def data_file(payload):
    fd, path = tempfile.mkstemp(dir=QDIR, prefix=".entry-")
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(payload)
    return path


def is_open(doc, q):
    try:
        r = subprocess.run(["bash", os.path.join(here, "fold-answers.sh"), "--list", doc, "open_questions"],
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=60)
    except Exception:
        return None
    if r.returncode != 0:
        return None
    for e in r.stdout.decode("utf-8", "replace").split("\n"):
        if e.split(":", 1)[0] == q:
            return not (" --- " in e and e.rsplit(" --- ", 1)[1].strip())
    return False


def handle(e, frm):
    t = e["type"]
    if t == "new-project":
        f = data_file(json.dumps(dict(e, **{"from": frm}), ensure_ascii=False))
        try:
            rc = run([os.path.join(here, "new-project-file.sh"), "--instance", inst, f])
        finally:
            os.remove(f)
        return {0: "saved", 4: "saved", 1: "refused"}.get(rc, "failed")
    slug, tid = e["task"].split("/")
    rel = os.path.join("projects", slug, "tasks", tid + ".md")
    doc = os.path.join(inst, rel)
    if not os.path.isfile(doc):
        return "refused"
    if run([os.path.join(here, "task-owner.sh"), rel]) != 0:
        return "not-yours"
    state = is_open(doc, e["q"])
    if state is None:
        return "failed"
    if not state:
        return "already-answered"
    answer = [os.path.join(here, "answer.sh"), "--instance", inst, doc, e["q"]]
    if t == "more":
        return {0: "saved", 5: "no-more"}.get(run(answer + ["more"]), "failed")
    if "option" in e:
        rc = run(answer + [str(e["option"])])
    else:
        f = data_file(e["text"])
        try:
            rc = run(answer + ["--text-file", f])
        finally:
            os.remove(f)
    return {0: "saved", 4: "saved", 1: "refused"}.get(rc, "failed")


def classify(raw, t0, win):
    e, err = validate({k: v for k, v in raw.items() if k not in ("ts", "from")})
    try:
        ts = datetime.datetime.strptime(raw.get("ts", ""), "%Y-%m-%dT%H:%M:%SZ").replace(
            tzinfo=datetime.timezone.utc)
    except (ValueError, TypeError):
        ts = None
    if err or ts is None:
        return None, "invalid"
    if t0 - ts > win or ts - t0 > datetime.timedelta(minutes=5):
        return None, "expired"
    return e, None


with lock(".consume.lock", False):
    done = ledger()
    # A claim with no verdict is an entry a killed consumer may have half-run: it is closed
    # as interrupted, never re-run — the page offers to send it again, and the task
    # document refuses what already landed.
    for i, v in list(done.items()):
        if v == "claimed":
            append_line(LEDGER, {"id": i, "verdict": "interrupted", "at": iso(now())})
            done[i] = "interrupted"
            print("%s interrupted" % i)
    t0, win = now(), datetime.timedelta(hours=int(window))
    plan, ids = [], set()
    for raw in entries():
        if raw["id"] not in done and raw["id"] not in ids:
            ids.add(raw["id"])
            plan.append((raw,) + classify(raw, t0, win))
    # A change is last-wins at consume, so the append-only file is never rewritten under a
    # concurrent POST: an earlier runnable answer to the same question is `replaced`.
    last = {(e["task"], e["q"]): e["id"] for _r, e, _v in plan if e and e["type"] == "answer"}
    for raw, e, verdict in plan:
        if e and e["type"] == "answer" and last[(e["task"], e["q"])] != e["id"]:
            verdict = "replaced"
        if not verdict:
            append_line(LEDGER, {"id": e["id"], "verdict": "claimed", "at": iso(now())})
            verdict = handle(e, raw.get("from", ""))
        append_line(LEDGER, {"id": raw["id"], "verdict": verdict, "at": iso(now())})
        done[raw["id"]] = verdict
        print("%s %s" % (raw["id"], verdict))
    if os.path.exists(QUEUE):
        with lock(".write.lock", True):
            keep = [l for l in lines(QUEUE) if (ident(l)[0] or "") not in done and ident(l)[0]]
            tmp = QUEUE + ".tmp"
            with open(tmp, "w", encoding="utf-8") as fh:
                fh.write("".join(l + "\n" for l in keep))
            os.chmod(tmp, 0o600)
            os.replace(tmp, QUEUE)
PY
