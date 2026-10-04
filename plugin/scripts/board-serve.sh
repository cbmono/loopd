#!/usr/bin/env bash
#
# board-serve.sh — ONE local board server per bundle. Renders SNAPSHOT.json into
# $AB_BOARD_DIR and serves that directory on 127.0.0.1:<boardPort>, re-rendering
# whenever the snapshot changes. No LLM, no network, nothing published.
#
#   Usage: board-serve.sh [--port N] [--interval SECS] [--out DIR] [--print-port]
#
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
for f in "$BOARD" "$WRITER" "$HERE/fold-answers.sh"; do
  [[ -f "$f" ]] || { echo "board-serve: missing $f" >&2; exit 2; }
done
command -v python3 >/dev/null 2>&1 || {
  echo "board-serve: needs python3 (standard library only) — build-board.sh already does." >&2; exit 2; }

mkdir -p "$OUT_DIR"
OUT_ABS="$(cd "$OUT_DIR" && pwd)"

BOARD_ROOT="$ROOT" BOARD_OUT="$OUT_ABS" BOARD_PORT="$PORT" BOARD_INTERVAL="$INTERVAL" \
BOARD_RENDER="$BOARD" BOARD_WRITER="$WRITER" \
exec python3 - <<'PY'
import errno, html, http.server, os, re, signal, socketserver, subprocess, sys, threading, time, urllib.parse, urllib.request

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


# THE QUESTION TEXT ENTERS HERE AND NOWHERE ELSE: in the HTTP response, never in a file.
# build-board.sh marks a question item's paragraph with `data-q="<slug>/<task id>"`; this
# swaps that paragraph for the task document's own `open_questions`, read fresh per
# request. The snapshot and the rendered file stay text-free, so nothing that copies,
# commits or publishes them can carry it. html.escape here is the page's SECOND escape
# point (build-board.sh's e() is the first), pinned by tests/board-serve.test.sh.
SEAM = re.compile(r'<p data-q="([^"<>]*)">[^<]*</p>')
SEG = re.compile(r"\w[\w.+-]*")
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


# fold-answers.sh's --list is the one parser that round-trips these lists; a refusal
# leaves the count paragraph, never a half-parsed question. An entry carrying ` --- ` is
# answered and awaiting the fold, so it is skipped exactly as build-awaiting.sh skips it.
def open_questions(path):
    try:
        r = subprocess.run(["bash", FOLD, "--list", path, "open_questions"],
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=30)
    except Exception:
        return []
    if r.returncode != 0:
        return []
    return [q for q in r.stdout.decode("utf-8", "replace").splitlines()
            if q.strip() and " --- " not in q]


def fill(m):
    ref = m.group(1).split("/")
    if len(ref) != 2 or not all(SEG.fullmatch(x) for x in ref):
        return m.group(0)
    hits = [f for f in (os.path.join(d, "projects", ref[0], "tasks", ref[1] + ".md")
                        for d in INSTANCES) if os.path.isfile(f)]
    qs = open_questions(hits[0]) if len(hits) == 1 else []
    if not qs:
        return m.group(0)
    return '<p data-q="%s">%s</p>' % (m.group(1), "<br>".join(html.escape(q, quote=True)
                                                               for q in qs))


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
            body = SEAM.sub(fill, body.decode("utf-8", "replace")).encode() + RELOAD.encode()
        return self._send(200, body, ctype)

    do_HEAD = do_GET

    def do_POST(self):
        self._send(405, b"method not allowed\n")

    do_PUT = do_DELETE = do_PATCH = do_POST


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
