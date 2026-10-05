#!/usr/bin/env bash
#
# headless-role-agents-probe.sh — re-measures docs/spikes/headless-role-agents.md.
# Without --live it prints what it would run and exits: every probe spends haiku turns,
# uses your REAL CLAUDE_CONFIG_DIR (it needs auth and a trusted directory), and so is
# never part of the suite. Fixtures (a scratch repo and its bare remote) live under mktemp.
#
#   headless-role-agents-probe.sh --live <trusted-worktree>
#
# <trusted-worktree> is a linked worktree you have accepted the trust prompt in.
#
# PERMISSIONS, deliberately narrow. Probes 1, 2, 4 and 5 run in the DEFAULT headless mode
# with at most `--allowedTools Write`, and write only under the mktemp lab. Probe 3 is the
# one that needs `--permission-mode bypassPermissions`, because "the deny baseline refuses
# under bypass" is the claim it measures — so it is fenced three ways: it is SKIPPED unless
# the worktree's repo carries .git/loopd-bundle naming a real bundle (a bypass session with
# no hook behind it is exactly what this spike is about, and the probe must not be one);
# `--tools Bash` leaves that session no other tool; and the one command it is asked to run
# targets the lab's own bare remote, which the trap deletes.
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
run() { # <out> -- <claude args…>   (no permission mode here: each probe states its own)
  local out="$1"; shift 2
  ( cd "$WT" && claude -p "$@" --model haiku --add-dir "$LAB" --output-format json \
      < /dev/null > "$out" 2>/dev/null ); echo "exit=$?"
}
marked() { # is the worktree's repo marked with a bundle that exists? (the hook's own walk)
  local gd c b
  [ -f "$WT/.git" ] || return 1
  IFS= read -r gd < "$WT/.git"; gd="${gd#gitdir: }"
  [ -f "$gd/commondir" ] || return 1
  IFS= read -r c < "$gd/commondir"; case "$c" in /*) ;; *) c="$gd/$c" ;; esac
  [ -f "$c/loopd-bundle" ] || return 1
  IFS= read -r b < "$c/loopd-bundle"; [ -f "$b/instance.config.json" ]
}

echo "== 1. --session-id before the spawn"
S1="$(uuid)"; run "$LAB/1.json" -- "Reply with the single word READY. Use no tools." --session-id "$S1" --max-turns 2
echo "   $(env_of "$LAB/1.json" subtype session_id)  minted=$S1"

echo "== 2. --max-turns, then --resume"
S2="$(uuid)"
run "$LAB/2.json" -- "Use the Write tool FOUR times, strictly one call per turn, never combined: (1) create $LAB/t1 containing the single letter a (2) create $LAB/t2 containing b (3) create $LAB/t3 containing c (4) create $LAB/t4 containing d . Then say DONE." --session-id "$S2" --max-turns 3 --allowedTools Write
echo "   $(env_of "$LAB/2.json" subtype is_error num_turns)  files=$(ls "$LAB" | grep -c '^t[1-4]$')/4"
run "$LAB/2b.json" -- "Continue exactly where you stopped and finish. Then say DONE." --resume "$S2" --max-turns 8 --allowedTools Write
echo "   resumed: $(env_of "$LAB/2b.json" subtype session_id)  files=$(ls "$LAB" | grep -c '^t[1-4]$')/4"

echo "== 3. the deny baseline, under bypass — only with the hook's marker in place"
S3="$(uuid)"
if marked; then
run "$LAB/3.json" -- "Run exactly: git -C $LAB/repo push --force origin main . Report the full output. Run nothing else." --session-id "$S3" --max-turns 3 --permission-mode bypassPermissions --tools Bash
else
  echo "   SKIPPED: $WT is not a linked worktree of a repo carrying .git/loopd-bundle — a bypass session would have no deny hook behind it"
  : > "$LAB/3.json"
fi
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
