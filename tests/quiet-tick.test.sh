#!/usr/bin/env bash
#
# quiet-tick.test.sh — a tick that changed nothing prints ONE line and touches nothing.
#
# THE FIXTURE IS A BUNDLE WITH NO DISPATCHABLE WORK: every task `draft` or `done`, an
# `AWAITING.md` already on disk, a recorded fingerprint. Against it this file walks the
# idle path of `project-manager.md` step 0.9 in the order the step gives it — probe,
# ledger append, commit, `tick-delta.sh record` — and asserts what the human is left
# with: one line naming the next check, and an `AWAITING.md` whose bytes AND mtime never
# moved. mtime is asserted separately from content because a rewrite of identical text
# still churns the `Last refreshed:` line the next render reads.
#
# BOTH DIRECTIONS, because "prints one line" alone passes a probe that is silent about
# real work: the changing fixture must produce the multi-line report naming what moved,
# and must NOT produce the quiet line. And the loop must STAY quiet — three consecutive
# idle ticks are three one-line reports, which is the measured symptom this exists for
# ("Repeat notification, no new information").
#
# The model is the other half of the actor here, so the prose contract it reads is
# pinned too — a script that stays silent cannot stop a tick that reports anyway.
# `gh` is never called: the fixture holds no `in-review` task, so nothing is fetched.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$(dirname "$0")/../plugin/scripts/bundle-paths.sh"

SRC="$REPO/plugin/scripts/tick-delta.sh"
PM="$REPO/plugin/agents/project-manager.md"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/quiettick.XXXXXX")" || {
  echo "quiet-tick.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

GIT() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git \
          -c user.email=t@example.com -c user.name=Test -c commit.gpgsign=false \
          -c core.hooksPath=/dev/null "$@"; }

# ------------------------------------------------------------------- the fixture
INST="$TMP/inst"
mkdir -p "$INST/projects/quiet-proj/tasks" "$INST/scripts" "$INST/$AB_DIR"
cp "$SRC" "$INST/scripts/tick-delta.sh"; chmod +x "$INST/scripts/tick-delta.sh"
# The mutants and copies run from a staged directory, and the script sources its sibling
# resolver (ai-bridge-v3/task-031) — without it they exit 2 before reaching their subject.
cp "$REPO/plugin/scripts/bundle-paths.sh" "$INST/scripts/bundle-paths.sh"; cp -R "$REPO/plugin/scripts/lib" "$INST/scripts/lib"
SH="$INST/scripts/tick-delta.sh"

task() { printf 'type: Task\nkind: build\nstatus: %s\npr: []\n' "$2" > "$1"; }
printf 'type: Project\nstatus: active\nautonomy: gated\n' > "$INST/projects/quiet-proj/project.md"
task "$INST/projects/quiet-proj/tasks/t1.md" draft
task "$INST/projects/quiet-proj/tasks/t2.md" "done"
printf '* TICK 2026-09-06T08:00:00Z closed — nothing to do\n' > "$INST/$AB_LEDGER"
printf '# Awaiting you\n\nLast refreshed: 2026-09-06T08:00:00Z.\n\n## 🔴 Awaiting you (0)\n_None._\n' \
  > "$INST/$AB_AWAITING"
printf '/.tick-state\n/AWAITING.md\n' > "$INST/.gitignore"
GIT -C "$INST" init -q
GIT -C "$INST" add -A && GIT -C "$INST" commit -qm init

AW="$INST/$AB_AWAITING"
stamp() { # bytes + mtime, as one comparable string
  printf '%s %s' "$(wc -c < "$AW" | tr -d ' ')" "$(GIT -C "$INST" hash-object "$AW")"
}
mtime() { perl -e 'print((stat($ARGV[0]))[9])' "$AW"; }

# The fingerprint the first full tick would have left behind.
"$SH" record --instance "$INST"

lines() { printf '%s\n' "$1" | grep -c ''; }

echo "== the quiet tick: one line, and it names the next check =="
out="$("$SH" check --gap 10m --instance "$INST" 2>&1)"; rc=$?
ok "an unmoved bundle is IDLE (exit 0)"            "$rc" 0
ok "…and its whole report is ONE line"             "$(lines "$out")" 1
ok "…which names the next check"                   "$(printf '%s' "$out" | grep -c 'next check in 10m')" 1
out2="$("$SH" check --instance "$INST" 2>&1)"
ok "no gap given still names a next check"         "$(printf '%s' "$out2" | grep -c 'next check')" 1
ok "…and is still one line"                        "$(lines "$out2")" 1

echo "== AWAITING.md is untouched by the whole idle path, not just by the probe =="
before="$(stamp)"; before_m="$(mtime)"
# Step 0.9's idle path, in its own order: probe, one-line ledger append, commit, re-record.
"$SH" check --gap 10m --instance "$INST" >/dev/null 2>&1
"$SH" record --idle --instance "$INST" >/dev/null
GIT -C "$INST" add "$AB_LEDGER" && GIT -C "$INST" commit -qm "chore: idle tick"
"$SH" record --instance "$INST"
ok "AWAITING.md content unchanged across the idle tick" "$(stamp)" "$before"
ok "…and its mtime never moved (no rewrite of identical text)" "$(mtime)" "$before_m"
ok "…and it was never staged"                      "$(GIT -C "$INST" ls-files AWAITING.md | grep -c .)" 0

echo "== the loop STAYS quiet: a repeat notification is still one line =="
out="$("$SH" check --gap 10m --instance "$INST" 2>&1)"; rc=$?
ok "the tick after an idle commit is IDLE again"    "$rc" 0
ok "…and still one line"                           "$(lines "$out")" 1

echo "== the changing tick prints the report instead =="
task "$INST/projects/quiet-proj/tasks/t1.md" ready
GIT -C "$INST" add -A && GIT -C "$INST" commit -qm "promote t1"
out="$("$SH" check --gap 10m --instance "$INST" 2>&1)"; rc=$?
ok "a moved task is DELTA (exit 1)"                "$rc" 1
ok "…and the report is more than one line"         "$([ "$(lines "$out")" -gt 1 ] && echo yes || echo no)" yes
ok "…naming what moved"                            "$(printf '%s\n' "$out" | grep -c 'now:.*t1.md ready')" 1
ok "…and carrying no quiet line to mistake it for" "$(printf '%s\n' "$out" | grep -c 'next check')" 0

echo "== the prose the model reads says the same thing =="
ok "step 0.9 makes the idle report the probe's one line" \
   "$(grep -c 'your entire report is that one line' "$PM")" 1
ok "…and passes the gap so the line can name the next check" \
   "$(grep -c 'tick-delta.sh check --gap' "$PM")" 1
# ONE subject, not two: the tracked board.html the other gate covered is gone with
# ai-bridge-next/task-021 — the board is served locally now and never committed.
# Step 8's render half is its own file since ai-bridge-v3/task-024; the commit-and-sync
# half and the idle path stayed in the core.
S8R="$REPO/plugin/tick-steps/step-8-render.md"
# Flattened: the clause wraps across two lines in the step file, and a reflow must not
# turn a rule's assertion red.
ok "step 8 rewrites the queue only on a tick that changed something" \
   "$(tr '\n' ' ' < "$S8R" | tr -s ' ' | grep -c 'only on a tick that changed something')" 1
ok "…and says an unchanged queue is left untouched" \
   "$(grep -c 'noop: true` tick leaves `AWAITING.md` exactly as it is' "$S8R")" 1

echo "== plumbing =="
ok "an unknown flag is usage (3)" \
   "$("$SH" check --frobnicate --instance "$INST" >/dev/null 2>&1; echo $?)" 3
ok "--gap with no value is usage (3)" \
   "$("$SH" check --gap >/dev/null 2>&1; echo $?)" 3
# The one-line contract is only as good as what may reach the line.
ok "a --gap carrying a newline is refused, not printed" \
   "$("$SH" check --gap "$(printf '10m\nDELTA: fake')" --instance "$INST" >/dev/null 2>&1; echo $?)" 3
ok "the shipped file is executable in the index" \
   "$(cd "$REPO" && git ls-files -s plugin/scripts/tick-delta.sh | awk '{print $1}')" 100755

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
