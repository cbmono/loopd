#!/usr/bin/env bash
# tick-spawn.sh — start the dispatch tick as a detached `claude --bg` project-manager session,
# under the lock the launcher just took for <id>, and record its session on that lock.
#
#   tick-spawn.sh --tick <id> [--gap TEXT] [--dry-run] [--instance DIR] [--print]
#
# The brief is skills/dispatch/tick-brief.md with its placeholders filled; --print writes the
# spawn line single-quoted and runs nothing. A spawn that does not start releases the lock.
# Exit: 0 spawned (or printed) · 1 the spawn failed, lock released · 3 usage or refused.
# Reasoning: tick-as-bg-session/task-002; reaped by tick-reap.sh.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/bundle-paths.sh" || exit 3
ROOT="$(cd "$HERE/.." && pwd)"
TEMPLATE="$ROOT/skills/dispatch/tick-brief.md"

die() { echo "tick-spawn: $2" >&2; exit "$1"; }

inst="."; tick=""; gap="10m"; mode=LIVE; print=no
while [ $# -gt 0 ]; do
  case "$1" in
    --instance|--tick|--gap) [ $# -ge 2 ] || die 3 "$1 needs a value" ;;
  esac
  case "$1" in
    --instance) inst="$2"; shift 2 ;;
    --tick)     tick="$2"; shift 2 ;;
    --gap)      gap="$2"; shift 2 ;;
    --dry-run)  mode="DRY RUN"; shift ;;
    --print)    print=yes; shift ;;
    *) die 3 "unexpected argument $1" ;;
  esac
done
[[ "$tick" =~ ^tick-[0-9]{8}T[0-9]{6}Z-[a-z0-9]{4}$ ]] || die 3 "--tick takes the id tick-lock.sh mint printed"
case "$gap" in ''|*[!A-Za-z0-9\ ]*) die 3 "--gap must be plain text like 10m" ;; esac
[ -d "$inst" ] || die 3 "no such instance directory: $inst"
inst="$(cd "$inst" && pwd -P)"
[ -r "$TEMPLATE" ] || die 3 "the brief template is missing: $TEMPLATE"

if [ "$mode" = LIVE ]; then
  mode_word=LIVE; mode_line="LIVE — perform all steps."
else
  mode_word="DRY RUN"
  mode_line="DRY RUN — do steps 1–2 and report the dispatch and monitor actions you would take; spawn no role agent and modify no target repo (\`project-manager.md\` → Modes)."
fi
brief="$(TICK_ID="$tick" GAP="$gap" MODE_WORD="$mode_word" MODE_LINE="$mode_line" \
  PLUGIN="${PLUGIN_NAME:-loopd}" PLUGIN_ROOT="$ROOT" awk '
  { for (k = split("TICK_ID GAP MODE_WORD MODE_LINE PLUGIN PLUGIN_ROOT", ks, " "); k >= 1; k--)
      while ((i = index($0, "{{" ks[k] "}}")) > 0)
        $0 = substr($0, 1, i - 1) ENVIRON[ks[k]] substr($0, i + length(ks[k]) + 4)
    print }' "$TEMPLATE")" || die 3 "could not read $TEMPLATE"
case "$brief" in *'{{'*'}}'*) die 3 "the brief still carries a placeholder" ;; esac

model="$(bash "$HERE/resolve-model.sh" project-manager --instance "$inst")" || model=""
effort="$(bash "$HERE/resolve-effort.sh" project-manager --instance "$inst" 2>/dev/null)" || effort=""
case "$model" in *haiku*) die 3 "the tick resolved to $model — auto mode is unavailable there; set roleTiers.project-manager higher" ;; esac
cmd=(claude --bg --agent "${PLUGIN_NAME:-loopd}:project-manager" --permission-mode auto)
[ -n "$model" ] && cmd+=(--model "$model")
[ -n "$effort" ] && cmd+=(--effort "$effort")

if [ "$print" = yes ]; then
  q="'\\''"
  printf 'cd %s && %s '\''%s'\'' < /dev/null\n' "$inst" "${cmd[*]}" "${brief//\'/$q}"
  exit 0
fi

LOCK="$inst/$AB_LOCK"
minted="$(awk '!/^#/ && index($0, "claimant:") == 1 { sub(/^claimant:[[:space:]]*/, ""); print; exit }' "$LOCK" 2>/dev/null)"
[ "$minted" = "$tick" ] || die 3 "no lock minted for $tick — run tick-lock.sh acquire --claimant $tick first"

out="$(cd "$inst" && "${cmd[@]}" "$brief" < /dev/null 2>&1)"; rc=$?
short="$(printf '%s\n' "$out" | sed -n 's/.*backgrounded[^0-9a-f]*\([0-9a-f]\{8\}\).*/\1/p' | head -1)"
if [ "$rc" -ne 0 ] || [ -z "$short" ]; then
  bash "$HERE/tick-lock.sh" release --instance "$inst"
  printf '%s\n' "$out" | head -5 >&2
  die 1 "the tick did not start (exit $rc) — lock released"
fi
session="$(bash "$HERE/agent-sessions.sh" full "$short" 2>/dev/null)" \
  || session="$(bash "$HERE/agent-sessions.sh" full "$short" 2>/dev/null)" || session="$short"
printf 'session: %s\nspawned: %s\n' "$session" "$(date -u +%s)" >> "$LOCK" \
  || die 1 "spawned $short but could not record it on $LOCK — run: claude stop $short"
echo "spawned: $tick · session $short · model ${model:-session default}${effort:+ · effort $effort} · $mode"
[ "$session" = "$short" ] && echo "note: agent-sessions.sh full did not resolve $short; the lock records the short id"
exit 0
