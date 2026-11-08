#!/usr/bin/env bash
# kb-sweep-due.sh — does THIS tick owe the cataloguer a knowledge/ sweep?
#
#   kb-sweep-due.sh --dispatched <n> [--in-flight <n>] [--cataloguer-in-flight] [--instance DIR]
#
# Due only when the tick dispatched nothing, no cataloguer is in flight, a slot is free
# under maxAgentsInFlight, and `build-kb-index.sh --check` reports >=1 ERROR; on 0 it prints
# the trigger line and the error list (the cataloguer's brief). Each walk is stamped in
# $AB_KB_STAMP until knowledge/ or the checker changes; with errors, kbSweepIntervalHours (24) at most.
# Exit: 0 due · 1 not due (reason on stderr; `KB SWEEP CACHED:` on stdout) · 2 unknown.
# Why: project-manager.md step 7, docs/pm-design.md#step-7.
set -uo pipefail

LIST_LIMIT=20
inst="."; dispatched=""; inflight=0; cat_inflight=0
usage() { echo "kb-sweep-due: $1" >&2; sed -n '4s/^#   /usage: /p' "$0" >&2; exit 2; }
need2() { [ "$1" -ge 2 ] || usage "$2 needs a value"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --instance)   need2 $# "$1"; inst="$2";       shift 2 ;;
    --dispatched) need2 $# "$1"; dispatched="$2"; shift 2 ;;
    --in-flight)  need2 $# "$1"; inflight="$2";   shift 2 ;;
    --cataloguer-in-flight) cat_inflight=1; shift ;;
    -h|--help) sed -n '2,11p' "$0" >&2; exit 2 ;;
    *) usage "unknown argument '$1'" ;;
  esac
done
int() { case "$2" in ""|*[!0-9]*) usage "--$1 <n> wants a non-negative integer ($3)" ;; esac; }
int dispatched "$dispatched" "agents spawned this tick"
int in-flight "$inflight" "role agents still running"
[ -d "$inst" ] || { echo "kb-sweep-due: no such instance directory: $inst" >&2; exit 2; }

not_due() { echo "kb-sweep-due: not due — $1" >&2; exit 1; }

# The self path is resolved through the symlink, not from $0: a stamped bundle's
# scripts/ holds absolute links into the template clone (resolve-max-agents.sh).
self="${BASH_SOURCE[0]:-$0}"
[ -L "$self" ] && self="$(readlink "$self" 2>/dev/null || printf '%s' "$self")"
here="$(cd "$(dirname "$self")" 2>/dev/null && pwd)" || here=""
[ -n "$here" ] && [ -f "$here/build-kb-index.sh" ] \
  || { echo "kb-sweep-due: build-kb-index.sh not found beside this script" >&2; exit 2; }
. "$here/bundle-paths.sh" || exit 2

# Cheapest gates first, so a busy tick never pays for the KB walk.
[ "$dispatched" -eq 0 ] || not_due "this tick dispatched $dispatched agent(s); the reflect path owns the KB"
[ "$cat_inflight" -eq 0 ] || not_due "a cataloguer is already in flight"
cap="$(bash "$here/resolve-max-agents.sh" --instance "$inst" 2>/dev/null)" || cap=4
[ "$inflight" -lt "$cap" ] || not_due "$inflight agent(s) in flight at the cap of $cap"
iv="$(bash "$here/resolve-config.sh" --instance "$inst" kbSweepIntervalHours 2>/dev/null)" || iv=""
case "$iv" in
  "") iv=24 ;;
  *[!0-9]*|0*) echo "kb-sweep-due: kbSweepIntervalHours '$iv' is not a positive integer; using 24" >&2; iv=24 ;;
esac

stamp="$inst/$AB_KB_STAMP"; ref=""
# A bundle whose .gitignore predates the stamp gets no cache: an untracked stamp is a dirty tree.
ignored() { ! git -C "$inst" rev-parse --git-dir >/dev/null 2>&1 \
  || { git -C "$inst" check-ignore -q "$AB_KB_STAMP" && git -C "$inst" check-ignore -q "$AB_KB_STAMP.$$"; }; }
# The reference is cut BEFORE the walk, so a doc edited while it runs is newer than the stamp.
if [ -d "$inst/knowledge" ] && ignored && mkdir -p "$inst/$AB_DIR" 2>/dev/null \
   && date -u '+%Y-%m-%dT%H:%M:%SZ %s' > "$stamp.$$" 2>/dev/null; then
  ref="$stamp.$$"; trap 'rm -f "$ref" "$stamp.$$.w"' EXIT
  [ -f "$stamp" ] && [ "$stamp" -nt "$ref" ] && rm -f "$stamp"
  # find, not `-nt`: bash 3.2's `-nt` compares whole seconds. The scripts are the checker's own.
  if [ -f "$stamp" ] && newer="$(find -H "$inst/knowledge" "$here/build-kb-index.sh" "$here/bundle-paths.sh" \
       "$here/plugin-name.sh" -newer "$stamp" -print -quit 2>/dev/null)" && [ -z "$newer" ]; then
    read -r st_at st_epoch < "$stamp"
    st_err="$(sed -n '2s/^errors=\([0-9]*\).*/\1/p' "$stamp")"
    [ "${st_err:-0}" -gt 0 ] \
      || not_due "cached, stamp $st_at — nothing under knowledge/ changed since that clean check"
    # The interval runs on the epoch inside the stamp, not its mtime, which the -newer gate owns.
    case "${st_epoch:-}" in ""|*[!0-9]*) age=-1 ;; *) age=$(( $(date -u +%s) - st_epoch )) ;; esac
    if [ "$age" -ge 0 ] && [ "$age" -lt $((iv * 3600)) ]; then
      printf 'KB SWEEP CACHED: %s error(s) at stamp %s; next walk %sh after it — no dispatch.\n' \
        "$st_err" "$st_at" "$iv"
      not_due "cached, stamp $st_at — $st_err error(s) open, inside kbSweepIntervalHours $iv"
    fi
  fi
fi

out="$(cd "$inst" && bash "$here/build-kb-index.sh" --check 2>&1)"; rc=$?
[ "$rc" -ne 2 ] || { printf '%s\n' "$out" >&2; echo "kb-sweep-due: build-kb-index.sh could not answer" >&2; exit 2; }
summary="$(printf '%s\n' "$out" | grep -E '^build-kb-index: [0-9]+ error' | tail -1)"
errors="$(printf '%s' "$summary" | sed -n 's/^build-kb-index: \([0-9]*\) error.*/\1/p')"
warns="$(printf '%s' "$summary" | sed -n 's/.*, \([0-9]*\) warning.*/\1/p')"
case "$errors" in ""|*[!0-9]*) echo "kb-sweep-due: build-kb-index.sh printed no error count" >&2; exit 2 ;; esac
errlist() { printf '%s\n' "$out" | awk -v lim="$1" '
  /^  ERROR  / { n++; if (lim == 0 || n <= lim) { print; if ((getline nxt) > 0) print nxt } next }
  END { if (lim > 0 && n > lim) printf "  ... and %d more.\n", n - lim }'; }
# touch -r keeps the pre-walk mtime, so a doc edited mid-walk stays newer than the stamp.
if [ -n "$ref" ] && { head -1 "$ref"; printf 'errors=%s warnings=%s\n' "$errors" "${warns:-0}"; errlist 0; } \
     > "$stamp.$$.w" && touch -r "$ref" "$stamp.$$.w"; then mv -f "$stamp.$$.w" "$stamp"; fi
[ "$errors" -gt 0 ] || not_due "$errors error(s) — the index and the documents agree"

printf 'KB SWEEP DUE: idle tick, %s error(s), %s warning(s) — dispatch the cataloguer.\n' \
  "$errors" "${warns:-0}"
errlist "$LIST_LIMIT"
if [ "$(printf '%s\n' "$out" | grep -c '^  ERROR  ')" -gt "$LIST_LIMIT" ]; then
  ab_say_run "  List them all with:" build-kb-index.sh --check
fi
exit 0
