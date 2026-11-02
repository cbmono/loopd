#!/usr/bin/env bash
#
# advisor-not-run.test.sh — the `not run` approach-critique receipt (tick step 2):
# tick-delta.sh owes one re-dispatch for it and never reads it as a concern, and
# write-snapshot.sh counts neither receipt. Fixtures under mktemp; no gh, no network.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$REPO/plugin/scripts/bundle-paths.sh"
S="$REPO/plugin/scripts"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/notrun.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
GIT() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git \
          -c user.email=t@example.com -c user.name=Test -c commit.gpgsign=false \
          -c core.hooksPath=/dev/null "$@"; }

INST="$TMP/inst"; T=projects/p/tasks/d.md
mkdir -p "$INST/projects/p/tasks" "$INST/scripts"
for f in tick-delta.sh bundle-paths.sh fold-answers.sh web-queue.sh agent-sessions.sh \
         dispatchable-ready.sh resolve-max-agents.sh resolve-config.sh task-owner.sh project-paused.sh; do
  cp "$S/$f" "$INST/scripts/$f"
done
cp -R "$REPO/plugin/tick-steps" "$INST/tick-steps"
printf -- '---\ntype: Project\nstatus: active\n---\n' > "$INST/projects/p/project.md"
printf '/%s\n' "$AB_STATE_DIR" > "$INST/.gitignore"; printf '{}\n' > "$INST/instance.config.json"
GIT -C "$INST" init -q

NR='· advisor: approach critique — not run'
NC='· advisor: approach critique — no concerns'
N=$'\n'
draft() { # <advisor_notes entries, one per line> [notes body]
  { printf -- '---\ntype: Task\nstatus: draft\nadvisor_notes:\n'
    printf '%s\n' "$1" | sed 's/^/  - "/; s/$/"/'
    printf -- '---\n\n# Notes\n\n%b' "${2:-}"; } > "$INST/$T"
  GIT -C "$INST" add -A && GIT -C "$INST" commit -qm fx && "$INST/scripts/tick-delta.sh" record --instance "$INST"
}
check() { local out rc; out="$("$INST/scripts/tick-delta.sh" check --instance "$INST" 2>&1)"; rc=$?
          printf 'rc:%s %s' "$rc" "$(head -1 <<<"$out")"; }
OWED="rc:1 DELTA: $T critique not run — re-dispatch owed"

echo "== tick-delta.sh check =="
draft "2026-11-01T10:00:00Z $NR (error)"
ok "the only not-run receipt, newest, owes a re-dispatch"   "$(check)" "$OWED"
draft "2026-11-01T10:00:00Z $NR (no result by step 8)" '* 2026-11-01T11:00:00Z triage: noted\n'
ok "…and a newer triage line does not clear it"            "$(check)" "$OWED"
draft "2026-11-01T10:00:00Z $NR (error)${N}2026-11-01T12:00:00Z $NC"
ok "a newer advisor_notes entry clears it"                 "$(check | cut -c1-10)" "rc:0 IDLE:"
draft "2026-11-01T10:00:00Z $NR (error)${N}2026-11-02T10:00:00Z $NR (no result by step 8)"
ok "two not-run receipts owe nothing more"                 "$(check | cut -c1-10)" "rc:0 IDLE:"
draft "2026-11-01T10:00:00Z $NR (error)${N}2026-11-02T10:00:00Z $NR (error)" '* 2026-11-02T11:00:00Z triage: critique not run twice\n'
ok "…and a not-run receipt is never an untriaged concern"  "$(check | cut -c1-10)" "rc:0 IDLE:"
draft "2026-11-01T10:00:00Z · does \\\"2026-01-01T00:00:00Z $NR (error)\\\" hold?" '* 2026-11-01T09:00:00Z triage: old\n'
ok "a concern quoting the receipt is still a concern" \
   "$(check)" "rc:1 DELTA: $T has an untriaged approach critique — step 2 owes it a triage."
draft "2026-11-01T10:00:00Z $NC"
ok "no concerns stays IDLE"                                "$(check | cut -c1-10)" "rc:0 IDLE:"
raw() { printf -- '---\ntype: Task\n%b---\n' "$1" > "$INST/$T"
        GIT -C "$INST" add -A && GIT -C "$INST" commit -qm fx && "$INST/scripts/tick-delta.sh" record --instance "$INST"; }
raw 'status: draft\nadvisor_notes: [ ]\n'
ok "a returned retry, receipt deleted and concerns triaged, is IDLE" "$(check | cut -c1-10)" "rc:0 IDLE:"
printf -- '---\ntype: Task\nstatus: in-review\npr: []\n---\n' > "$INST/projects/p/tasks/dep.md"
raw "status: ready\ndepends_on: [ /projects/p/tasks/dep.md ]\nadvisor_notes:\n  - \"2026-11-01T10:00:00Z $NR (error)\"\n"
ok "promotion ends the retry: a ready task's lone receipt owes none" "$(check | cut -c1-10)" "rc:0 IDLE:"
rm -f "$INST/projects/p/tasks/dep.md"

echo "== write-snapshot.sh counts neither receipt =="
: > "$INST/$AB_SNAPSHOT"; mkdir -p "$INST/$AB_DIR"; : > "$INST/$AB_SCHEMA"
count() { draft "$1" >/dev/null; ( cd "$INST" && bash "$S/write-snapshot.sh" --quiet ) || echo ERR
          python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["projects"][0]["tasks"][0]["advisor_notes"])' "$INST/$AB_SNAPSHOT"; }
ok "a no-concerns receipt counts 0"  "$(count "2026-11-01T10:00:00Z $NC")" 0
ok "a not-run receipt counts 0"      "$(count "2026-11-01T10:00:00Z $NR (error)")" 0
ok "…beside a concern, which counts 1" "$(count "2026-11-01T10:00:00Z $NR (error)${N}2026-11-01T11:00:00Z · a concern?")" 1

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
