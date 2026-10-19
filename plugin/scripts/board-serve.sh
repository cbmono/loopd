#!/usr/bin/env bash
#
# board-serve.sh — ONE local board server per bundle. Renders SNAPSHOT.json into
# $AB_BOARD_DIR and serves that directory on 127.0.0.1:<boardPort>, re-rendering
# whenever the snapshot changes. No LLM, no network, nothing published.
#
#   Usage: board-serve.sh [--port N] [--interval SECS] [--out DIR] [--print-port]
#
#   POST /__queue appends one web-board entry through web-queue.sh, behind a per-launch token.
#   Exits 0 (served until Ctrl-C, or this bundle's port was already served),
#   2 (bad flag), 3 (the port is held by something that is not this board).
#   Why it is shaped this way: docs/operations.md § 5.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]:-$0}")/bundle-paths.sh" || exit 2

PORT=""
INTERVAL=1
OUT_DIR="$AB_BOARD_DIR"
PRINT_PORT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) shift; [[ $# -gt 0 ]] || { echo "board-serve: --port needs a number" >&2; exit 2; }; PORT="$1" ;;
    --port=*) PORT="${1#--port=}" ;;
    --interval) shift; [[ $# -gt 0 ]] || { echo "board-serve: --interval needs a number" >&2; exit 2; }; INTERVAL="$1" ;;
    --interval=*) INTERVAL="${1#--interval=}" ;;
    --out) shift; [[ $# -gt 0 ]] || { echo "board-serve: --out needs a path" >&2; exit 2; }; OUT_DIR="$1" ;;
    --out=*) OUT_DIR="${1#--out=}" ;;
    --print-port) PRINT_PORT=1 ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
    *) echo "board-serve: unknown argument '$1'" >&2; exit 2 ;;
  esac
  shift
done
case "$INTERVAL" in ''|*[!0-9]*|0) echo "board-serve: --interval takes a positive integer" >&2; exit 2 ;; esac
[[ -n "$OUT_DIR" ]] || { echo "board-serve: --out needs a path" >&2; exit 2; }

# Self-detecting and silent when it does not apply, exactly as watch-board.sh is: this
# ships into every bundle and will be run from the wrong directory.
ab_is_bundle . || exit 0

# The PHYSICAL path, so a bundle reached through a symlink (or a `//` in TMPDIR) derives
# ONE port rather than one per route.
ROOT="$(pwd -P)"

# THE PORT IS DERIVED FROM THE BUNDLE PATH, so two bundles on one machine never collide
# and the same bundle answers on the same port across reboots. 4xxxx is above the
# ephemeral range on macOS (49152) only in part, so the band stops at 49999 and the
# collision path below is what covers the rest. `cksum` is POSIX and gives the same
# number on macOS and Linux.
derive_port() { # <absolute path> -> 40000..49999
  local sum
  sum="$(printf '%s' "$1" | cksum | awk '{print $1}')"
  printf '%s' "$(( 40000 + sum % 10000 ))"
}

# `boardPort` is per-machine — a port is a property of this laptop, never of the bundle
# everyone clones — so only instance.config.local.json is read. Flattened first, because
# JSON may put a key and its value on two lines.
config_port() {
  [[ -f "$ROOT/instance.config.local.json" ]] || return 0
  tr '\n' ' ' < "$ROOT/instance.config.local.json" 2>/dev/null \
    | sed -n 's/.*"boardPort"[[:space:]]*:[[:space:]]*\([0-9]\{1,5\}\).*/\1/p' | head -1
}

if [[ -z "$PORT" ]]; then
  PORT="$(config_port || true)"
fi
[[ -n "$PORT" ]] || PORT="$(derive_port "$ROOT")"
case "$PORT" in ''|*[!0-9]*) echo "board-serve: boardPort must be a number, got '$PORT'" >&2; exit 2 ;; esac
if [[ "$PORT" -lt 1024 || "$PORT" -gt 65535 ]]; then
  echo "board-serve: boardPort $PORT is outside 1024-65535" >&2; exit 2
fi

if [[ $PRINT_PORT -eq 1 ]]; then
  echo "$PORT"
  exit 0
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
BOARD="$HERE/build-board.sh"
WRITER="$HERE/write-snapshot.sh"
for f in "$BOARD" "$WRITER" "$HERE/fold-answers.sh" "$HERE/web-queue.sh"; do
  [[ -f "$f" ]] || { echo "board-serve: missing $f" >&2; exit 2; }
done
command -v python3 >/dev/null 2>&1 || {
  echo "board-serve: needs python3 (standard library only) — build-board.sh already does." >&2; exit 2; }

mkdir -p "$OUT_DIR"
OUT_ABS="$(cd "$OUT_DIR" && pwd)"

BOARD_ROOT="$ROOT" BOARD_OUT="$OUT_ABS" BOARD_PORT="$PORT" BOARD_INTERVAL="$INTERVAL" \
BOARD_RENDER="$BOARD" BOARD_WRITER="$WRITER" \
BOARD_FROM="$(bash "$HERE/decision-stamp.sh" --self 2>/dev/null)" \
exec python3 - <<'PY'
import errno, hmac, html, http.server, json, os, re, secrets, signal, socketserver, subprocess, sys, threading, time, urllib.parse, urllib.request

ROOT     = os.environ["BOARD_ROOT"]
OUT      = os.path.realpath(os.environ["BOARD_OUT"])
PORT     = int(os.environ["BOARD_PORT"])
INTERVAL = int(os.environ["BOARD_INTERVAL"])
RENDER   = os.environ["BOARD_RENDER"]
WRITER   = os.environ["BOARD_WRITER"]
FOLD     = os.path.join(os.path.dirname(WRITER), "fold-answers.sh")
PAGE     = os.path.join(OUT, "board.html")
SNAP     = os.path.join(ROOT, os.environ["AB_SNAPSHOT"])
STATE    = os.path.join(OUT, ".serve")
URL      = "http://localhost:%d" % PORT
QUEUE    = os.path.join(os.path.dirname(WRITER), "web-queue.sh")
FROM     = os.environ.get("BOARD_FROM") or "<unknown>"
# Per launch, in memory only: it reaches the page in the HTTP response and is in no file.
TOKEN    = secrets.token_urlsafe(32)
HOSTS    = ("127.0.0.1:%d" % PORT, "localhost:%d" % PORT)

# The auto-reload: poll a revision endpoint, reload only when the page actually changed.
# A `<meta refresh>` would reload on a timer and collapse every expanded project card
# while a human was reading it, which is the one thing this page is for.
PENDING = ("<!doctype html><meta charset=utf-8><meta http-equiv=refresh content=2>"
           "<title>rendering</title><p>Rendering the board&hellip;</p>")
RELOAD = ("<script>(function(){var r=null;setInterval(function(){"
          "fetch('/__rev').then(function(x){return x.text()}).then(function(t){"
          "if(r!==null&&t!==r){location.reload()}r=t})},1000)})()</script>")


def refresh():
    if not os.path.exists(SNAP):
        return
    try:
        subprocess.run(["bash", WRITER, "--quiet"], cwd=ROOT,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
    except Exception:
        pass


# NO TRAILING `.`, deliberately, and this is the one place that choice is safe: the page
# never leaves this machine, so a render covering `boardInstances` is a feature here where
# it is a governance breach on anything committed or published.
def render():
    try:
        rc = subprocess.run(["bash", RENDER, "--standalone", "--out", PAGE], cwd=ROOT,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
        if rc.returncode != 0:
            sys.stderr.write("board-serve: build-board failed — the page was not updated.\n")
    except Exception:
        sys.stderr.write("board-serve: build-board could not be run — the page was not updated.\n")


# THE FILLED TEXT ENTERS HERE AND NOWHERE ELSE: in the HTTP response, never in a file.
# build-board.sh emits the named seams docs/operations.md lists ("The serve-time fill");
# this fills them from the task and project documents, read fresh per request, so the
# snapshot and the rendered file stay text-free. html.escape here is the page's SECOND
# escape point (build-board.sh's e() is the first), pinned by tests/board-serve.test.sh.
LEAF = re.compile(r'<(div|ol) data-fill="(q-text|q-options|q-depths|p-need|p-success)" '
                  r'data-ref="([^"<>]*)"></\1>')
QOPEN = re.compile(r'<div class="qfill" data-fill="question" data-ref="([^"<>]*)"')
SEG = re.compile(r"\w[\w.+-]*")
# The label rule of write-snapshot.sh's question_labels(), so a seam's code finds its entry.
QCODE = re.compile(r"(?i)\s*(?:advisor:\s*)?(?:[^·]{0,40}·\s*)?(?:advisor:\s*)?"
                   r"q0*(\d{1,3})(?![0-9a-z_])\s*[:.)]?\s*")
ISO = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?")
INSTANCES = [ROOT]


def list_instances():
    global INSTANCES
    try:
        r = subprocess.run(["bash", RENDER, "--list-instances"], cwd=ROOT,
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=60)
        found = [os.path.join(ROOT, x) for x in r.stdout.decode().splitlines() if x]
        if r.returncode == 0 and found:
            INSTANCES = found
    except Exception:
        pass


def fold(*args):
    try:
        r = subprocess.run(["bash", FOLD] + list(args),
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=30)
    except Exception:
        return None
    return r.stdout.decode("utf-8", "replace") if r.returncode == 0 else None


# A task's document for its questions, a project's for need and success_criteria (which
# conventions 11b keeps out of the snapshot) — the only two paths built into the bundle.
def find_doc(slug, tid=None):
    if not SEG.fullmatch(slug) or not (tid is None or SEG.fullmatch(tid)):
        return None
    if tid is None:
        hits = [os.path.join(d, "projects", slug, "project.md") for d in INSTANCES]
    else:
        hits = [os.path.join(d, "projects", slug, "tasks", tid + ".md") for d in INSTANCES]
    hits = [f for f in hits if os.path.isfile(f)]
    return hits[0] if len(hits) == 1 else None


def scalar(path, key):
    try:
        text = open(path, encoding="utf-8").read()
    except (OSError, UnicodeDecodeError):
        return ""
    end = text.find("\n---", 3)
    if not text.startswith("---\n") or end < 0:
        return ""
    m = re.search(r"(?m)^%s:[ \t]*(.*)$" % re.escape(key), text[4:end])
    v = m.group(1).strip() if m else ""
    if v.startswith('"'):
        try:
            v = json.JSONDecoder().raw_decode(v)[0]
        except ValueError:
            return ""
        return v if isinstance(v, str) else ""
    if v.startswith("'"):
        return v[1:v.rfind("'")].replace("''", "'") if v.count("'") > 1 else ""
    return re.split(r"[ \t]#", v, 1)[0].strip()


def paras(text):
    return "".join("<p>%s</p>" % html.escape(" ".join(x.split()), quote=True)
                   for x in re.split(r"\n\s*\n", text) if x.strip())


class Fill:
    """One request's fill: every document is read at most once per page served."""

    def __init__(self):
        self.memo, self.open = {}, set()

    def once(self, key, fn):
        if key not in self.memo:
            self.memo[key] = fn()
        return self.memo[key]

    # fold-answers.sh's --list is the one parser that round-trips these lists. An entry
    # carrying ` --- ` is answered and awaiting the fold, so it is skipped exactly as
    # build-awaiting.sh skips it.
    def questions(self, doc):
        def read():
            out = fold("--list", doc, "open_questions") or ""
            return [q for q in out.splitlines() if q.strip() and " --- " not in q]
        return self.once(("q", doc), read)

    def block(self, doc, code):
        def read():
            try:
                return json.loads(fold("--block", code, doc) or "null")
            except ValueError:
                return None
        return self.once(("b", doc, code), read)

    def question(self, ref):
        parts = ref.split("/")
        if len(parts) not in (2, 3) or (len(parts) == 3 and not re.fullmatch(r"Q\d+", parts[2])):
            return None, None, []
        doc = find_doc(parts[0], parts[1])
        if doc is None:
            return None, None, []
        code = parts[2] if len(parts) == 3 else ""
        texts = []
        for q in self.questions(doc):
            m = QCODE.match(q)
            if ("Q%d" % int(m.group(1)) if m else "") == code:
                texts.append(q[m.end():] if m else q)
        return doc, code, texts

    def leaf(self, m):
        tag, kind, ref = m.groups()
        inner = ""
        if kind.startswith("p-"):
            doc = find_doc(ref)
            if doc and kind == "p-need":
                inner = paras(scalar(doc, "need"))
            elif doc:
                inner = "".join("<li>%s</li>" % html.escape(x, quote=True) for x in
                                (fold("--list", doc, "success_criteria") or "").splitlines() if x)
        else:
            doc, code, texts = self.question(ref)
            if texts and kind == "q-text":
                self.open.add(ref)
                inner = "".join("<p>%s</p>" % html.escape(x, quote=True) for x in texts)
            elif texts and code:
                b = self.block(doc, code) or {}
                if kind == "q-options":
                    opts = [o for o in b.get("options", []) if isinstance(o, list) and len(o) == 2]
                    rec = [o for o in opts if o[1] == b.get("recommendation")][:1]
                    inner = "".join('<li data-n="%d"%s>%s</li>' % (int(n), " data-rec" if [n, t] in rec
                                                                   else "", html.escape(str(t), quote=True))
                                    for n, t in rec + [o for o in opts if o not in rec])
                else:
                    inner = "".join('<li data-depth="%d">%s</li>' % (i + 1, paras(str(d)))
                                    for i, d in enumerate(b.get("depths", [])[:3]))
        if not inner:
            return m.group(0)
        return '<%s data-fill="%s" data-ref="%s">%s</%s>' % (tag, kind, ref, inner, tag)

    # ONE ORDER RULE (docs/operations.md): oldest task first by its `timestamp:`, then Q
    # number; no timestamp sorts last; slug and task id break ties so a refresh is stable.
    def rank(self, page):
        def key(ref):
            parts = ref.split("/")
            doc = find_doc(parts[0], parts[1])
            ts = ISO.match(self.once(("t", doc), lambda: scalar(doc, "timestamp")) or "")
            return (0 if ts else 1, ts.group(0) if ts else "", parts[0], parts[1],
                    int(parts[2][1:]) if len(parts) == 3 else 1 << 30)
        order = {r: i + 1 for i, r in enumerate(sorted(self.open, key=key))}
        return QOPEN.sub(lambda m: m.group(0) + (' data-rank="%d"' % order[m.group(1)]
                                                 if m.group(1) in order else ""), page)

    def page(self, body):
        return self.rank(LEAF.sub(self.leaf, body))


def snap_mtime():
    try:
        return os.stat(SNAP).st_mtime_ns
    except OSError:
        return 0


def watch():
    last = snap_mtime()
    use_fswatch = False
    for d in os.environ.get("PATH", "").split(os.pathsep):
        if d and os.access(os.path.join(d, "fswatch"), os.X_OK):
            use_fswatch = True
            break
    while True:
        if use_fswatch:
            try:
                subprocess.run(["fswatch", "--one-event", ROOT], cwd=ROOT,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
            except Exception:
                time.sleep(INTERVAL)
        else:
            time.sleep(INTERVAL)
        now = snap_mtime()
        if now != last:
            last = now
            render()


# EVERYTHING SERVED IS UNDER $AB_BOARD_DIR, AND THAT IS ENFORCED HERE RATHER THAN BY A
# LIBRARY DEFAULT. The request path is decoded, joined, realpath'd — which also resolves a
# symlink planted inside the directory — and refused unless it lands inside OUT.
def resolve(path):
    rel = urllib.parse.unquote(path).lstrip("/")
    if not rel or "\x00" in rel:
        return None
    full = os.path.realpath(os.path.join(OUT, rel))
    if full != OUT and not full.startswith(OUT + os.sep):
        return None
    if not os.path.isfile(full):
        return None
    return full


TYPES = {".html": "text/html; charset=utf-8", ".css": "text/css; charset=utf-8",
         ".js": "text/javascript; charset=utf-8", ".json": "application/json",
         ".svg": "image/svg+xml", ".png": "image/png"}


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "ai-bridge-board"
    protocol_version = "HTTP/1.1"

    def log_message(self, *_a):
        pass

    def _send(self, code, body, ctype="text/plain; charset=utf-8"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def do_GET(self):
        path = urllib.parse.urlsplit(self.path).path
        # `/__bundle` is how a second start tells "this bundle's board is already
        # serving" from "something else has the port". It answers the root only.
        if path == "/__bundle":
            return self._send(200, ROOT.encode())
        if path == "/__rev":
            try:
                rev = str(os.stat(PAGE).st_mtime_ns)
            except OSError:
                rev = "0"
            return self._send(200, rev.encode())
        if path == "/__queue":
            if not self._allowed(False):
                return self._send(403, b"forbidden\n")
            out = self._queue(["status"])
            return self._send(200 if out[0] == 0 else 500, out[1], "application/json")
        if path in ("/", "/index.html"):
            path = "/board.html"
        full = resolve(path)
        if full is None:
            # Not yet rendered is not "not found": the placeholder reloads itself.
            if path == "/board.html":
                return self._send(200, PENDING.encode(), "text/html; charset=utf-8")
            return self._send(404, b"not found\n")
        try:
            with open(full, "rb") as fh:
                body = fh.read()
        except OSError:
            if full == PAGE:
                return self._send(200, PENDING.encode(), "text/html; charset=utf-8")
            return self._send(404, b"not found\n")
        ctype = TYPES.get(os.path.splitext(full)[1], "application/octet-stream")
        if full == PAGE:
            page = body.decode("utf-8", "replace")
            try:
                page = Fill().page(page)
            except Exception:
                sys.stderr.write("board-serve: the fill failed — served the page unfilled.\n")
            meta = '<meta name="loopd-queue" content="%s">' % TOKEN
            page = page.replace("</head>", meta + "</head>", 1) if "</head>" in page else meta + page
            body = page.encode() + RELOAD.encode()
        return self._send(200, body, ctype)

    do_HEAD = do_GET

    # A POST is the page asking the next tick to run one entry. The token keeps other web
    # pages out, Host and Origin keep a rebound DNS name out; a process on this machine can
    # read the token from GET /, and can equally edit the task document itself.
    def _allowed(self, post):
        host = self.headers.get("Host", "")
        if host not in HOSTS:
            return False
        if post and self.headers.get("Origin") != "http://" + host:
            return False
        return hmac.compare_digest(self.headers.get("X-Loopd-Token", ""), TOKEN)

    def _queue(self, args, body=b""):
        try:
            r = subprocess.run(["bash", QUEUE] + args + ["--instance", ROOT], input=body,
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=30)
            return r.returncode, r.stdout
        except Exception:
            return 2, b""

    def do_POST(self):
        if urllib.parse.urlsplit(self.path).path != "/__queue":
            return self._send(405, b"method not allowed\n")
        if not self._allowed(True):
            return self._send(403, b"forbidden\n")
        if self.headers.get("Content-Type", "").split(";")[0].strip().lower() != "application/json":
            return self._send(415, b"application/json only\n")
        try:
            n = int(self.headers.get("Content-Length", ""))
        except ValueError:
            return self._send(411, b"length required\n")
        if not 0 < n <= 16384:
            return self._send(413, b"too large\n")
        rc, out = self._queue(["append", "--from", FROM], self.rfile.read(n))
        if rc == 1:
            msg = out.decode("utf-8", "replace").strip()
            return self._send(400, json.dumps({"error": msg}).encode(), "application/json")
        return self._send(202 if rc == 0 else 500, out, "application/json")

    def do_PUT(self):
        self._send(405, b"method not allowed\n")

    do_DELETE = do_PATCH = do_PUT


def already_ours():
    try:
        with urllib.request.urlopen("http://127.0.0.1:%d/__bundle" % PORT, timeout=2) as r:
            return r.read().decode().strip() == ROOT
    except Exception:
        return False


# ThreadingHTTPServer's own server_bind does a REVERSE DNS lookup to fill in a
# `server_name` nothing here reads — between bind() and listen(), so a runner whose PTR
# query stalls leaves the port taken and answering nothing (measured: ~20 s on CI).
class Server(http.server.ThreadingHTTPServer):
    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]


try:
    httpd = Server(("127.0.0.1", PORT), Handler)
except OSError as exc:
    if exc.errno not in (errno.EADDRINUSE, errno.EACCES):
        raise
    if already_ours():
        print("board-serve: already served — %s" % URL, flush=True)
        sys.exit(0)
    sys.stderr.write("board-serve: port %d is in use by something that is not this board"
                     " — set \"boardPort\" in instance.config.local.json\n" % PORT)
    sys.exit(3)

# SIGTERM has to unwind rather than kill, or the state file below outlives the server and
# the banner reads a dead port as a live one.
signal.signal(signal.SIGTERM, lambda *_a: sys.exit(0))
with open(STATE, "w") as fh:
    fh.write("%d\n%d\n%s\n" % (PORT, os.getpid(), ROOT))
# The port answers at once; the first render runs beside it (it can take tens of seconds
# on a cold machine) and the page shows "rendering" until it lands.
def first_render():
    list_instances()
    refresh()
    render()
threading.Thread(target=first_render, daemon=True).start()
threading.Thread(target=watch, daemon=True).start()
print("board-serve: serving %s from %s — Ctrl-C to stop." % (URL, OUT), flush=True)
try:
    httpd.serve_forever()
except (KeyboardInterrupt, SystemExit):
    pass
finally:
    try:
        os.remove(STATE)
    except OSError:
        pass
    print("board-serve: stopped.", flush=True)
PY
