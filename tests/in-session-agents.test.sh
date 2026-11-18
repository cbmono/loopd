#!/usr/bin/env bash
#
# in-session-agents.test.sh — `agent-sessions.sh in-session` and what shows it: counts.sh's
# counts.json and the status line's `N working`.
#
# THE PROPERTIES:
#   * AN IN-SESSION SUBAGENT IS SEEN BY ITS TRANSCRIPT MOVING. `claude agents` never lists an
#     Agent-tool subagent, so one whose <project dir>/<session>/subagents/agent-<id>.jsonl
#     changed inside the window (120 s) is listed `<agentType> TAB <description>`, the
#     description on one line; an older one is not.
#   * ABSENCE IS NOTHING: no project dir, no subagents dir, no meta, a broken meta — no line,
#     exit 0.
#   * DISPLAY ONLY. The status band and counts.json count it as working; `in-flight` and
#     `view --summary`, which the tick and the cap read, do not move.
# Every session here is a fixture under a fake CLAUDE_CONFIG_DIR; nothing real is read.
# Exit 0 pass, 1 fail, 2 setup.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SESS="$REPO/plugin/scripts/agent-sessions.sh"
SL="$REPO/plugin/scripts/status-line.sh"
for f in "$SESS" "$SL"; do [ -f "$f" ] || { echo "in-session-agents.test: $f not found" >&2; exit 2; }; done
command -v python3 >/dev/null 2>&1 || { echo "in-session-agents.test: python3 required" >&2; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/in-session.XXXXXX")" || { echo "in-session-agents.test: mktemp failed" >&2; exit 2; }
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export XDG_CACHE_HOME="$TMP/cache" CLAUDE_CONFIG_DIR="$TMP/cfg"

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

# A bundle with an underscore and a dot in its path: Claude Code's key turns both into `-`.
B="$TMP/_my.bundle"
mkdir -p "$B/.loopd" "$B/projects/p/tasks"
printf '{}\n' > "$B/instance.config.json"
# One open task recording a session the listing says is working: in-flight is 1, by it alone.
printf -- '---\ntype: Task\nstatus: in-progress\nsession: aaaa0001\n---\n' > "$B/projects/p/tasks/task-001.md"
printf '[{"sessionId":"aaaa0001-0000-0000-0000-000000000000","state":"working","status":"busy","pid":%s,"cwd":"%s"}]\n' "$$" "$B" \
  > "$TMP/listing.json"
export AB_SESSIONS_LISTING="$TMP/listing.json"

KEY="$(printf '%s' "$B" | LC_ALL=C sed 's/[^A-Za-z0-9]/-/g')"
case "$KEY" in *_*|*.*) echo "in-session-agents.test: key $KEY kept a _ or ." >&2; exit 2 ;; esac
SUB="$CLAUDE_CONFIG_DIR/projects/$KEY/11111111-2222-3333-4444-555555555555/subagents"

ins() { bash "$SESS" in-session "$B" "$@" </dev/null 2>/dev/null; }
rc()  { bash "$SESS" in-session "$B" "$@" </dev/null >/dev/null 2>&1; echo $?; }
flight() { bash "$SESS" in-flight "$B" </dev/null 2>/dev/null; }
summary() { bash "$SESS" view "$B" --summary </dev/null 2>/dev/null; }
sl() { rm -rf "$XDG_CACHE_HOME"; bash "$SL" --instance "$B" --color never </dev/null 2>/dev/null; }
band() { grep -oE '[0-9?]+ working · [0-9?]+ idle · [0-9?]+ dead' <<<"$1"; }
jget() { python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(eval(sys.argv[2], {"d": d}))' "$B/.loopd/counts.json" "$1" 2>&1; }

echo "== 1. absence is nothing, exit 0 =="
ok "no project dir: nothing"                 "$(ins)" ""
ok "…exit 0"                                 "$(rc)" 0
mkdir -p "$CLAUDE_CONFIG_DIR/projects/$KEY/11111111-2222-3333-4444-555555555555"
ok "a session with no subagents dir: nothing" "$(ins)" ""
mkdir -p "$SUB"
: > "$SUB/agent-a1.jsonl"
ok "a fresh transcript with no meta: nothing" "$(ins)" ""
printf 'not json' > "$SUB/agent-a1.meta.json"
ok "…a broken meta: nothing"                 "$(ins)" ""
ok "…exit 0"                                 "$(rc)" 0

BASE_FLIGHT="$(flight)"; BASE_SUMMARY="$(summary)"
rm -f "$SUB/agent-a1.meta.json" "$SUB/agent-a1.jsonl"
ok "baseline: in-flight counts the recorded session" "$BASE_FLIGHT" 1
ok "baseline: the band, with no subagent"    "$(band "$(sl)")" "1 working · 0 idle · 0 dead"
ok "baseline: counts.json in_session is 0"   "$(jget 'd["sessions"]["in_session"], d["in_session_agents"]')" "(0, [])"

echo "== 2. a fresh transcript is listed; a stale one is not =="
printf '{"agentType":"general-purpose","description":"Design owed line,\\n\\tDELTA and \\"approve\\" mark \\\\ x","toolUseId":"t"}\n' \
  > "$SUB/agent-fresh.meta.json"
: > "$SUB/agent-fresh.jsonl"
printf '{"agentType":"loopd:qa-reviewer","description":"Old review"}\n' > "$SUB/agent-stale.meta.json"
: > "$SUB/agent-stale.jsonl"
touch -t 202001010000 "$SUB/agent-stale.jsonl"
want="$(printf 'general-purpose\tDesign owed line, DELTA and "approve" mark \\ x')"
ok "fresh: listed, its description on one line" "$(ins)" "$want"
ok "stale: past the window, not listed"      "$(ins | grep -c qa-reviewer)" 0
ok "--window wide enough lists the stale one too" "$(ins --window 999999999 | grep -c 'qa-reviewer	Old review')" 1
ok "--window takes digits only"              "$(rc --window soon)" 2

echo "== 3. display only: the band counts it, the tick's numbers do not =="
ok "the band counts it as working"           "$(band "$(sl)")" "2 working · 0 idle · 0 dead"
ok "counts.json: sessions.working stays background-only" "$(jget 'd["sessions"]["working"]')" 1
ok "counts.json: sessions.in_session"        "$(jget 'd["sessions"]["in_session"]')" 1
ok "counts.json: the agent, escaped as JSON" "$(jget 'd["in_session_agents"]')" \
   "[{'type': 'general-purpose', 'description': 'Design owed line, DELTA and \"approve\" mark \\\\ x'}]"
ok "in-flight is unchanged by it"            "$(flight)" "$BASE_FLIGHT"
ok "view --summary is unchanged by it"       "$(summary)" "$BASE_SUMMARY"
# A failing listing stays `?`: an in-session agent never turns unknown into a number.
ok "an unknown listing stays ? on the band"  "$(band "$(AB_SESSIONS_LISTING="$TMP/missing.json" sl)")" "? working · ? idle · ? dead"

echo
echo "in-session-agents: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
