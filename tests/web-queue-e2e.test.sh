#!/usr/bin/env bash
# iced — the board is on hold (owner's decision, 2026-10-05). `run.sh --iced`, the nightly
# workflow and any PR whose diff names this file's subject still run it. Thaw: delete these lines.
#
# web-queue-e2e.test.sh — the web board's answer queue in a real browser: headless Chrome
# over the DevTools protocol (node's own WebSocket), against tests/fixtures/simple-board on
# a test port served by plugin/scripts/board-serve.sh, never a live board. Send answer and
# Start the project show Sent and the `{n} waiting to be saved` chip; after
# plugin/scripts/web-queue.sh consume the page shows Saved from GET /__queue. No Chrome or
# node ⇒ SKIP by name. Every server and browser carries a watchdog.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/plugin/scripts/bundle-paths.sh"
SERVE="$REPO/plugin/scripts/board-serve.sh"
QUEUE="$REPO/plugin/scripts/web-queue.sh"
pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL  %s (want %s, got %s)\n' "$1" "$3" "$2"; fail=$((fail+1)); fi; }
skip() { printf '  SKIP  %s\n' "$1"; echo "pass=$pass fail=$fail"; exit 0; }

CHROME="${CHROME:-}"
for c in google-chrome google-chrome-stable chromium chromium-browser \
         "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"; do
  [ -n "$CHROME" ] && break
  command -v "$c" >/dev/null 2>&1 && CHROME="$(command -v "$c")"
  [ -x "$c" ] && CHROME="$c"
done
command -v python3 >/dev/null 2>&1 || skip "python3 absent"
[ -n "$CHROME" ] || skip "no Chrome or Chromium on this machine"
node -e 'if(typeof WebSocket!=="function")process.exit(1)' 2>/dev/null || skip "node with a built-in WebSocket (22+) absent"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/web-queue-e2e.XXXXXX")" || exit 2
PIDS=""
cleanup() { for p in $PIDS; do kill -TERM "$p" 2>/dev/null; done; rm -rf "$TMP"; }
trap cleanup EXIT
free_port() { python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])'; }

D="$TMP/bundle"
bash "$REPO/tests/fixtures/simple-board/mk.sh" "$D" >/dev/null 2>&1 || { echo "fixture failed"; exit 2; }
PORT="$(free_port)"; DBG="$(free_port)"
( cd "$D" && exec bash "$SERVE" --port "$PORT" ) >"$TMP/serve.log" 2>&1 &
PIDS="$PIDS $!"; ( sleep 240; kill -TERM $! 2>/dev/null ) >/dev/null 2>&1 &
"$CHROME" --headless=new --disable-gpu --no-first-run --no-default-browser-check \
  --user-data-dir="$TMP/profile" --remote-debugging-port="$DBG" about:blank >/dev/null 2>&1 &
CPID=$!; PIDS="$PIDS $CPID"; ( sleep 240; kill -TERM $CPID 2>/dev/null ) >/dev/null 2>&1 &
for _ in $(seq 1 100); do
  page="$(curl -sf "http://127.0.0.1:$PORT/board.html" 2>/dev/null)"
  grep -q 'loopd-queue" content=' <<<"$page" && curl -sf "http://127.0.0.1:$DBG/json/version" >/dev/null 2>&1 && break
  sleep 0.3
done

cat > "$TMP/drive.mjs" <<'JS'
const [dbg, url, step] = process.argv.slice(2);
const tabs = await (await fetch(`http://127.0.0.1:${dbg}/json/list`)).json();
const ws = new WebSocket(tabs.find(t => t.type === "page").webSocketDebuggerUrl);
await new Promise(r => ws.addEventListener("open", r, { once: true }));
let n = 0; const wait = new Map();
ws.addEventListener("message", m => { const d = JSON.parse(m.data); if (wait.has(d.id)) { wait.get(d.id)(d); wait.delete(d.id); } });
const send = (method, params = {}) => new Promise(r => { wait.set(++n, r); ws.send(JSON.stringify({ id: n, method, params })); });
const ev = async e => (await send("Runtime.evaluate", { expression: e, awaitPromise: true, returnByValue: true })).result.result.value;
const until = async (e, ms = 15000) => { const t = Date.now(); while (Date.now() - t < ms) { const v = await ev(e); if (v) return v; await new Promise(r => setTimeout(r, 200)); } return ""; };
const q = s => `(document.querySelector(${JSON.stringify(s)})||{}).textContent||""`;
let out = {};
if (step === "send") {
  await send("Page.navigate", { url });
  await until(`document.querySelector('.s-qlist>.s-q [data-fill="q-options"] li.sel')`);
  out.served = await ev(`!!document.querySelector('meta[name="loopd-queue"]')`);
  await ev(`document.querySelector('.s-qlist>.s-q [data-act="send"]').click(),1`);
  out.chip = await until(`(function(){var w=document.querySelector('.s-wait');return w&&!w.hidden&&w.textContent})()`);
  out.sent = await ev(q(".s-confirms"));
  out.queued = await ev(`document.querySelector('.s-qlist>.s-q').classList.contains('queued')`);
  await ev(`document.querySelector('[data-new]').click(),1`);
  await ev(`(function(){var f=document.querySelector('.s-modal[data-m="new"] form'),v={title:'Team lunch autonomy=yolo',what:'Order lunch for the team',who:'Everyone',done:'Lunch arrives',repo:'lunch'};for(var k in v)f.querySelector('[name="'+k+'"]').value=v[k];f.querySelector('[type="submit"]').click();return 1})()`);
  out.chip2 = await until(`(function(){var w=document.querySelector('.s-wait');return w&&/^2 /.test(w.textContent)&&w.textContent})()`);
} else {
  out.saved = await until(`(function(){var t=${q(".s-confirms")};return /Saved your answer to Q12/.test(t)&&/Started the project/.test(t)&&t})()`);
  out.chip = await ev(`document.querySelector('.s-wait').hidden`);
}
console.log(JSON.stringify(out)); ws.close(); process.exit(0);
JS
J1="$(node "$TMP/drive.mjs" "$DBG" "http://127.0.0.1:$PORT/" send 2>&1)"
field() { printf '%s' "$1" | python3 -c 'import json,sys;print(json.loads(sys.stdin.read() or "{}").get(sys.argv[1],""))' "$2" 2>/dev/null; }
ok "the served page carries the queue token meta"       "$(field "$J1" served)" "True"
ok "Send answer queues: the chip reads 1 waiting"        "$(field "$J1" chip)" "1 waiting to be saved"
ok "the sent row names Q12"                              "$(field "$J1" sent | grep -c 'Q12')" "1"
ok "the answered card is marked queued"                  "$(field "$J1" queued)" "True"
ok "Start the project queues a second entry"            "$(field "$J1" chip2)" "2 waiting to be saved"
ok "two entries sit in the queue file"                   "$(wc -l < "$D/$AB_QUEUE" | tr -d ' ')" "2"

touch "$D/$AB_LOCK"
bash "$QUEUE" consume --instance "$D" >"$TMP/consume.out" 2>&1
ok "consume saves both entries"                          "$(grep -c ' saved$' "$TMP/consume.out")" "2"
J2="$(node "$TMP/drive.mjs" "$DBG" "" saved 2>&1)"
ok "the page shows Saved for both, read from /__queue"   "$( [ -n "$(field "$J2" saved)" ] && echo yes)" "yes"
ok "the waiting chip is gone"                            "$(field "$J2" chip)" "True"
ok "the project created from the page is gated"          "$(grep -h '^autonomy:' "$D"/projects/team-lunch-*/project.md)" "autonomy: gated"
ok "Q12 was answered with the recommended option"        "$(grep -c 'Q12: .* --- Yes, send a confirmation email first' "$D/projects/news/tasks/task-003.md")" "1"
ok "the token is in no file under the bundle"           "$(grep -rl 'name="loopd-queue" content=' "$D" | wc -l | tr -d ' ')" "0"

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
