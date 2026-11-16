#!/usr/bin/env bash
# A full tick reporting `noop: true` still renders AWAITING.md, so an answered `👉 do` row in a
# paused project leaves the page while its merge row and trailer stay (awaiting-rows-clear-on-
# idle-ticks/task-003). It drives build-awaiting.sh with the arguments step 8 passes and pins
# step 8's rule; the idle fast path staying render-free is tests/quiet-tick.test.sh's.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SH="$REPO/plugin/scripts/build-awaiting.sh"
S8R="$REPO/plugin/tick-steps/step-8-render.md"
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$(dirname "$0")/../plugin/scripts/bundle-paths.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/awaiting-noop.XXXXXX")" || {
  echo "awaiting-noop-tick.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi }
rows() { grep -c "$2" "$1/$AB_AWAITING" | tr -d ' '; }

A="$TMP/inst"; P="$A/projects/held"
mkdir -p "$P/tasks" "$A/$AB_DIR"
printf '{ "org": "demo" }\n' > "$A/instance.config.json"
printf '# SCHEMA\n' > "$A/$AB_SCHEMA"
printf -- '---\ntype: Project\ntitle: "Held"\nstatus: paused\n---\n' > "$P/project.md"
Q1='Q1: do: deploy demo/web — https://github.com/demo/web/pull/9 merged, not deployed; answer done once it is live'
Q2='Q2: do: deploy demo/api — https://github.com/demo/api/pull/4 merged, not deployed; answer done once it is live'
done_task() { printf -- '---\ntype: Task\ntitle: "Shipped"\nstatus: done\nopen_questions: [ "%s", "%s" ]\n---\n' "$1" "$2" > "$P/tasks/task-001-a.md"; }
done_task "$Q1" "$Q2"
printf -- '---\ntype: Task\ntitle: "Green"\nstatus: in-review\nopen_questions: [ ]\n---\n' > "$P/tasks/task-002-b.md"
: > "$A/$AB_AWAITING"
MERGE="$P/tasks/task-002-b.md=[demo#7](https://github.com/demo/web/pull/7)"
TRAIL="$P/tasks/task-002-b.md=7/7 checks green at a069721"
render() { bash "$SH" --instance "$1" --merge "$MERGE" --trailer "$TRAIL"; }

echo "== the full tick before the answer =="
render "$A" >/dev/null 2>&1
ok "both do rows render in the paused project" "$(rows "$A" '^\* 👉 \*\*do\*\*')" 2

echo "== the answer's commit makes a full tick that reports noop: true, and it renders =="
done_task "$Q1 --- done" "$Q2"
t0=$(date +%s)
render "$A" >/dev/null 2>&1
echo "  render wall time: $(( $(date +%s) - t0 ))s"
ok "the answered row is gone"          "$(rows "$A" 'deploy demo/web')" 0
ok "the unanswered row survives"       "$(rows "$A" '^\* 👉 \*\*do\*\* — \[Shipped\].*Q2: do: deploy demo/api')" 1
ok "the merge row keeps link + trailer" \
   "$(rows "$A" '^\* 🔀 \*\*merge\*\* — \[Green\].*\[demo#7\](https://github.com/demo/web/pull/7) · 7/7 checks green at a069721$')" 1

echo "== step 8 renders on every full tick, noop: true included =="
flat="$(tr '\n' ' ' < "$S8R" | tr -s ' ')"
has() { case "$flat" in *"$1"*) echo yes ;; *) echo no ;; esac; }
ok "the noop: false gate is gone"     "$(has 'and this tick will report `noop: false`')" no
ok "it renders on every full tick"    "$(has 'only if it already exists, on every full tick.')" yes
ok "…noop: true ticks included"       "$(has '**`noop: true` ticks included**')" yes
ok "…passing the same merge rows"     "$(has 'tick still passes every `--merge` and `--trailer`')" yes

echo "== no AWAITING.md: no render creates one =="
N="$TMP/off"; cp -R "$A" "$N"; rm "$N/$AB_AWAITING"
MERGE="$N/projects/held/tasks/task-002-b.md=[demo#7](https://github.com/demo/web/pull/7)"
ok "a render with merge and trailer exits 0" "$(render "$N" >/dev/null 2>&1; echo $?)" 0
ok "…and writes no AWAITING.md"             "$([ -e "$N/$AB_AWAITING" ] && echo yes || echo no)" no

echo "== exit 3 on an unparseable doc leaves the page and names the doc =="
MERGE="$P/tasks/task-002-b.md=[demo#7](https://github.com/demo/web/pull/7)"
mkdir -p "$A/projects/live/tasks"
printf -- '---\ntype: Project\ntitle: "Live"\nstatus: active\n---\n' > "$A/projects/live/project.md"
printf -- '---\ntype: Task\ntitle: "Broken"\nstatus: draft\nopen_questions: [ "Q1: unterminated\n---\n' > "$A/projects/live/tasks/task-001-x.md"
cp "$A/$AB_AWAITING" "$TMP/before"
err="$(render "$A" 2>&1 >/dev/null)"; rc=$?
ok "the render exits 3"               "$rc" 3
ok "…leaving AWAITING.md byte-equal"  "$(cmp -s "$A/$AB_AWAITING" "$TMP/before" && echo yes || echo no)" yes
names() { case "$1" in 'build-awaiting: '*'/projects/live/tasks/task-001-x.md'*) echo yes ;; *) echo no ;; esac; }
ok "…its line names the doc"          "$(names "$err")" yes
ok "step 8 puts that line in the report" "$(has 'its `build-awaiting:` line goes in the tick report verbatim')" yes

printf '\npass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
