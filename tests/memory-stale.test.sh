#!/usr/bin/env bash
# memory-stale.test.sh — plugin/scripts/memory-stale.sh against fixture memory dirs.
# Reasoning: article-batch-8-hygiene/task-004 (project.md D2, D3, D7).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SH="$HERE/../plugin/scripts/memory-stale.sh"
WELCOME="$HERE/../plugin/scripts/welcome.sh"
[ -f "$SH" ] || { echo "memory-stale.test: missing $SH" >&2; exit 2; }
CUR="$(tr -d '[:space:]' < "$HERE/../plugin/VERSION")"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/memory-stale.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-64s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-64s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
task() { mkdir -p "$(dirname "$1")"; printf -- '---\ntype: Task\nstatus: %s\n---\n' "$2" > "$1"; }

# The bundle path carries `.` and `_`: Claude Code maps every non-alphanumeric to `-`.
B="$TMP/my_bundle.v2"; mkdir -p "$B"
task "$B/projects/alpha/tasks/task-001-shipped.md" done
task "$B/projects/alpha/tasks/task-002-open.md" in-progress
task "$B/projects/beta/tasks/task-003.md" cancelled
export CLAUDE_CONFIG_DIR="$TMP/home"
MEM="$CLAUDE_CONFIG_DIR/projects/$(cd "$B" && pwd -P | tr -c 'A-Za-z0-9\n' '-')/memory"
mkdir -p "$MEM"
w() { printf '%s\n' "$2" > "$MEM/$1"; }
w done-task.md      'SECRET-BODY alpha/task-001 is the fix to wait for'
w cancelled-task.md 'see projects/beta/tasks/task-003 for the plan'
w active-task.md    'alpha/task-002 still owes the rewrite'
w bare-ids.md       'task-001 and task-003 are done; alpha is a word'
w closed-project.md 'notes live in projects/gamma/deliverables'
w live-project.md   'notes live in projects/alpha/project.md'
w old-version.md    'loopd 3.0.0 step 4 treats blocked as parked'
w old-v.md          'the status line (v2.4.0) prints ?'
w shielded.md       'fixed since 3.0.0; FIXED by loopd 3.0.0; since loopd 3.1.0; as of loopd 3.13.0; measured on v4.2.1'
w newer-version.md  "loopd 99.0.0 is the future; loopd $CUR is fine too"
w root-project.md   'see /projects/delta/project.md'
w foreign-paths.md  'kept in ~/projects/x, /Users/me/projects/foo and subprojects/y'

before="$(cd "$MEM" && ls -la; cat ./*)"
OUT="$(bash "$SH" --instance "$B")"; rc=$?
has() { printf '%s\n' "$OUT" | grep -c "^$1 · " | tr -d ' '; }

echo "== 1. a done or cancelled task is listed, in both qualified forms =="
ok "<slug>/task-NNN of a done task"                 "$(has done-task.md)" 1
ok "…with its reason"                               "$(printf '%s\n' "$OUT" | grep -c '^done-task.md · task alpha/task-001 is done$' | tr -d ' ')" 1
ok "projects/<slug>/tasks/task-NNN of a cancelled"  "$(printf '%s\n' "$OUT" | grep -c '^cancelled-task.md · task beta/task-003 is cancelled$' | tr -d ' ')" 1

echo "== 2. an active task, a bare id or a bare word is not =="
ok "active task not listed"                         "$(has active-task.md)" 0
ok "bare task-NNN never matched"                    "$(has bare-ids.md)" 0

echo "== 3. a closed project is listed, a live one is not =="
ok "projects/<slug> with no folder"                 "$(printf '%s\n' "$OUT" | grep -c '^closed-project.md · projects/gamma has no folder' | tr -d ' ')" 1
ok "projects/<slug> that exists"                    "$(has live-project.md)" 0
ok "a bundle-root /projects/<slug> is matched"      "$(printf '%s\n' "$OUT" | grep -c '^root-project.md · projects/delta has no folder' | tr -d ' ')" 1
ok "~/projects, /Users/…/projects, subprojects are not" "$(has foreign-paths.md)" 0

echo "== 4. an older loopd version is listed, a shielded one is not =="
ok "loopd <x.y.z> older than plugin/VERSION"        "$(printf '%s\n' "$OUT" | grep -c '^old-version.md · names loopd 3.0.0, older than ' | tr -d ' ')" 1
ok "v<x.y.z> older than plugin/VERSION"             "$(has old-v.md)" 1
ok "since/fixed by/as of/measured on not listed"    "$(has shielded.md)" 0
ok "current or newer version not listed"            "$(has newer-version.md)" 0

echo "== 5. report-only: names and reasons, never content; writes nothing =="
ok "resolved dir exits 0"                           "$rc" 0
ok "one line per stale note"                        "$(printf '%s\n' "$OUT" | grep -c .)" 6
ok "no note content printed"                        "$(printf '%s\n' "$OUT" | grep -c 'SECRET-BODY\|parked\|wait for' | tr -d ' ')" 0
ok "memory dir unchanged"                           "$([ "$(cd "$MEM" && ls -la; cat ./*)" = "$before" ] && echo yes || echo no)" yes
mkdir -p "$TMP/clean"; CM="$CLAUDE_CONFIG_DIR/projects/$(cd "$TMP/clean" && pwd -P | tr -c 'A-Za-z0-9\n' '-')/memory"
mkdir -p "$CM"; printf 'nothing stale here\n' > "$CM/MEMORY.md"
co="$(bash "$SH" --instance "$TMP/clean")"; crc=$?
ok "a clean dir exits 0 and lists nothing"          "$crc:${co}" "0:"

echo "== 6. a missing dir is UNKNOWN, exit 2 =="
mkdir -p "$TMP/nomem"
uo="$(bash "$SH" --instance "$TMP/nomem")"; urc=$?
ok "missing memory dir exits 2"                     "$urc" 2
ok "…and prints UNKNOWN"                            "$(printf '%s\n' "$uo" | grep -c '^UNKNOWN' | tr -d ' ')" 1
urc2=0; bash "$SH" --instance "$TMP/does-not-exist" >/dev/null || urc2=$?
ok "an unresolvable bundle root exits 2"            "$urc2" 2
urc3=0; bash "$SH" --bogus >/dev/null 2>&1 || urc3=$?
ok "an unknown flag is a usage error (3)"           "$urc3" 3

echo "== 7. welcome check renders the row =="
row() { bash "$WELCOME" check --instance "$1" --style plain "${@:2}" 2>/dev/null | grep -A6 -E '^(⚠|✓) .*(auto-memory|memory notes)'; }
wo="$(row "$B")"
ok "⚠ with the count when notes are listed"         "$(printf '%s\n' "$wo" | grep -c '^⚠ 6 auto-memory note' | tr -d ' ')" 1
ok "…kept under --only-problems"                    "$(row "$B" --only-problems | grep -c '^⚠ 6 auto-memory note' | tr -d ' ')" 1
ok "✓ when none"                                    "$(row "$TMP/clean" | grep -c '^✓ memory notes: none' | tr -d ' ')" 1
ok "a note line on UNKNOWN"                         "$(row "$TMP/nomem" | grep -c '^    UNKNOWN' | tr -d ' ')" 1
ok "the row is memory-stale|human|no"               "$(bash "$WELCOME" check --list | grep -c "^memory-stale	human	no$" | tr -d ' ')" 1

echo
echo "memory-stale.test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
