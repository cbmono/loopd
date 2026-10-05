#!/usr/bin/env bash
#
# headless-role-agents-probe.sh — re-measures docs/spikes/headless-role-agents.md.
# Without --live it prints what it would run and exits: every probe spends haiku turns,
# uses your REAL CLAUDE_CONFIG_DIR (it needs auth and a trusted directory), and so is
# never part of the suite. Fixtures (a scratch repo and its bare remote) live under mktemp.
#
#   headless-role-agents-probe.sh --live <trusted-worktree>
#
# <trusted-worktree> is a linked worktree you have accepted the trust prompt in; for the
# deny-baseline probe its repo must carry .git/loopd-bundle (link-repos.sh writes it).
# Exit 0 always: this reports, it never gates.
set -uo pipefail

[ "${1:-}" = "--live" ] && [ -n "${2:-}" ] || {
  sed -n '3,12p' "$0"; echo "(no --live: nothing was run)"; exit 0; }
WT="$2"
[ -d "$WT" ] || { echo "probe: no such directory: $WT"; exit 0; }
command -v claude >/dev/null 2>&1 || { echo "probe: no claude on PATH"; exit 0; }
HERE="$(cd "$(dirname "$0")" && pwd)"
SU="$HERE/../../plugin/scripts/session-usage.sh"

LAB="$(mktemp -d)"; trap 'rm -rf "$LAB"' EXIT
git init -q --bare --initial-branch=main "$LAB/remote.git"
git clone -q "$LAB/remote.git" "$LAB/repo" 2>/dev/null
( cd "$LAB/repo" && git config user.email probe@example.com && git config user.name probe \
  && git checkout -q -b main && echo one > f && git add f && git commit -qm one \
  && git push -q origin main && echo two > f && git commit -qam two --amend )
ORIG="$(git -C "$LAB/remote.git" rev-parse main)"

uuid() { python3 -c 'import uuid; print(uuid.uuid4())'; }
env_of() { python3 -c 'import json,sys
try: j = json.load(open(sys.argv[1]))
except Exception: print("no envelope"); sys.exit()
print(" ".join("%s=%s" % (k, j.get(k)) for k in sys.argv[2:]))' "$@"; }
run() { # <out> -- <claude args…>
  local out="$1"; shift 2
  ( cd "$WT" && claude -p "$@" --model haiku --permission-mode bypassPermissions \
      --add-dir "$LAB" --output-format json < /dev/null > "$out" 2>/dev/null ); echo "exit=$?"
}

echo "== 1. --session-id before the spawn"
S1="$(uuid)"; run "$LAB/1.json" -- "Reply with the single word READY. Use no tools." --session-id "$S1" --max-turns 2
echo "   $(env_of "$LAB/1.json" subtype session_id)  minted=$S1"

echo "== 2. --max-turns, then --resume"
S2="$(uuid)"
run "$LAB/2.json" -- "Run these as FOUR SEPARATE Bash tool calls, one per turn, never combined: (1) echo a > $LAB/t1 (2) echo b > $LAB/t2 (3) echo c > $LAB/t3 (4) echo d > $LAB/t4 . Then say DONE." --session-id "$S2" --max-turns 3
echo "   $(env_of "$LAB/2.json" subtype is_error num_turns)  files=$(ls "$LAB" | grep -c '^t[1-4]$')/4"
run "$LAB/2b.json" -- "Continue exactly where you stopped and finish. Then say DONE." --resume "$S2" --max-turns 8
echo "   resumed: $(env_of "$LAB/2b.json" subtype session_id)  files=$(ls "$LAB" | grep -c '^t[1-4]$')/4"

echo "== 3. the deny baseline (needs .git/loopd-bundle on the worktree's repo)"
S3="$(uuid)"
run "$LAB/3.json" -- "Run exactly: git -C $LAB/repo push --force origin main . Report the full output. Run nothing else." --session-id "$S3" --max-turns 3
echo "   remote main $([ "$(git -C "$LAB/remote.git" rev-parse main)" = "$ORIG" ] && echo UNCHANGED || echo MOVED)  $(python3 -c 'import json,sys
try: print("permission_denials=%d" % len(json.load(open(sys.argv[1])).get("permission_denials") or []))
except Exception: print("no envelope")' "$LAB/3.json")"
T3="$(find "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects" -name "$S3.jsonl" 2>/dev/null | head -1)"
# A run in which the model never issued the command proves nothing either way, so say so.
echo "   attempted=$(grep -c '"name":"Bash"' "${T3:-/dev/null}" 2>/dev/null; true)  refusal_in_transcript=$(grep -c 'force_push_protected' "${T3:-/dev/null}" 2>/dev/null; true)"

echo "== 4. usage: the envelope against session-usage.sh"
python3 -c 'import json,sys
try: u = json.load(open(sys.argv[1])).get("usage") or {}
except Exception: u = {}
print("   envelope fresh=%d" % (u.get("input_tokens",0)+u.get("cache_creation_input_tokens",0)+u.get("output_tokens",0)))' "$LAB/1.json"
echo "   reader   $(bash "$SU" "$S1" 2>&1)"

echo "== 5. listed by claude agents?"
claude agents --json --all 2>/dev/null | python3 -c 'import json,sys
try: d = json.load(sys.stdin)
except Exception: d = []
d = d if isinstance(d, list) else d.get("agents", d.get("sessions", []))
ids = set(str(a.get("sessionId", "")) for a in d)
print("   listed %d of %d" % (sum(1 for s in sys.argv[1:] if s in ids), len(sys.argv) - 1))' "$S1" "$S2" "$S3"
