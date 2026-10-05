#!/usr/bin/env bash
# iced — the board is on hold (owner's decision, 2026-10-05). `run.sh --iced`, the nightly
# workflow and any PR whose diff names this file's subject still run it. Thaw: delete these lines.
#
# write-snapshot.test.sh — the snapshot's `awaiting` verbs agree with AWAITING.md on a
# paused project: `merge` survives, every other verb is emptied, and `counts.awaiting` falls
# by exactly the rows suppressed. The board's `N need you` rail reads these verbs directly.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO/plugin/scripts/write-snapshot.sh"
. "$REPO/plugin/scripts/bundle-paths.sh"
command -v python3 >/dev/null 2>&1 || { echo "write-snapshot.test: python3 required" >&2; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/write-snapshot.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { # <label> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL  %s (want %s, got %s)\n' "$1" "$3" "$2"; fail=$((fail+1)); fi; }

INST="$TMP/inst"
mkdir -p "$INST/$AB_DIR"
printf '{ "org": "o" }\n' > "$INST/instance.config.json"
printf 'stub\n' > "$INST/$AB_SCHEMA"
printf '{}\n' > "$INST/$AB_SNAPSHOT"
for p in live held; do
  d="$INST/projects/$p/tasks"; mkdir -p "$d"
  printf -- '---\ntype: Project\ntitle: %s\nstatus: active\n---\n' "$p" > "$INST/projects/$p/project.md"
  printf -- '---\ntype: Task\ntitle: a\nstatus: draft\nacceptance_criteria: [ "c" ]\nopen_questions: [ ]\n---\n' > "$d/t1.md"
  printf -- '---\ntype: Task\ntitle: b\nstatus: draft\nacceptance_criteria: [ "c" ]\nopen_questions: [ "Q1: which?" ]\n---\n' > "$d/t2.md"
  printf -- '---\ntype: Task\ntitle: c\nstatus: blocked\n---\n' > "$d/t3.md"
  printf -- '---\ntype: Task\ntitle: d\nstatus: in-review\npr_mergeable: MERGEABLE\npr: [ "https://github.com/o/r/pull/7" ]\n---\n' > "$d/t4.md"
done

snap() { ( cd "$INST" && bash "$SCRIPT" --quiet ) || echo "write-snapshot exited $?" >&2; }
verb() { # <project> <task> -> the task's awaiting verb, or <none>
  python3 -c 'import json,sys
d = json.load(open(sys.argv[1]))
p = [p for p in d["projects"] if p["slug"] == sys.argv[2]][0]
print([t for t in p["tasks"] if t["id"] == sys.argv[3]][0]["awaiting"] or "<none>")' "$INST/$AB_SNAPSHOT" "$1" "$2"; }
total() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["counts"]["awaiting"])' "$INST/$AB_SNAPSHOT"; }

snap; BEFORE="$(total)"
ok "both active: every verb present, 8 awaiting" "$BEFORE" 8

printf -- '---\ntype: Project\ntitle: held\nstatus: paused\n---\n' > "$INST/projects/held/project.md"
snap
ok "paused: the merge task keeps its verb"    "$(verb held t4)" merge
ok "paused: the clean draft carries no verb"  "$(verb held t1)" "<none>"
ok "paused: the questioned draft, none"       "$(verb held t2)" "<none>"
ok "paused: the blocked task, none"           "$(verb held t3)" "<none>"
ok "active: approve unchanged"                "$(verb live t1)" approve
ok "active: answer unchanged"                 "$(verb live t2)" answer
ok "active: unblock unchanged"                "$(verb live t3)" unblock
ok "active: merge unchanged"                  "$(verb live t4)" merge
ok "counts.awaiting falls by exactly the 3 suppressed" "$(total)" 5

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
