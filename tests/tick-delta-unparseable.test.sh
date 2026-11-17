#!/usr/bin/env bash
#
# tick-delta-unparseable.test.sh — `plugin/scripts/tick-delta.sh` and `plugin/scripts/design-inputs.sh`
# when a document's list cannot be parsed: the digest names and skips it and still answers,
# `check` never reads IDLE on it, every fingerprint failure names its own cause, and
# `record --close` carries the digest's stderr. Fixtures live under mktemp; `gh` is a stub.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/plugin/scripts/bundle-paths.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tdunparse.XXXXXX")" || exit 2
trap 'chmod -R u+rw "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
GIT() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -c user.email=t@example.com -c user.name=Test \
          -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }

INST="$TMP/inst"; S="$INST/scripts"
mkdir -p "$INST/projects/proj-a/tasks" "$INST/projects/proj-b/tasks"
cp -R "$REPO/plugin/scripts" "$S"; cp -R "$REPO/plugin/tick-steps" "$INST/tick-steps"
# Every parser call is logged, so `check` can be shown to re-parse no task.
mv "$S/fold-answers.sh" "$S/fold-answers.real.sh"
cat > "$S/fold-answers.sh" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FOLDLOG"
[ -n "${FOLD_EXIT2:-}" ] && { echo "fold-answers: python3 is required" >&2; exit 2; }
exec bash "$(dirname "$0")/fold-answers.real.sh" "$@"
EOS
FOLDLOG="$TMP/fold.log"; export FOLDLOG
BIN="$TMP/bin"; mkdir -p "$BIN"
printf '#!/usr/bin/env bash\necho "HTTP 401: Bad credentials (https://api.github.com/graphql)" >&2\necho "second line" >&2\nexit 1\n' > "$BIN/gh"
chmod +x "$S"/*.sh "$BIN/gh"
SH="$S/tick-delta.sh"; TD() { PATH="$BIN:$PATH" "$SH" "$@" --instance "$INST"; }
REASON="$INST/$AB_TICK_START/digest-stderr"

GOODP=$'---\ntype: Project\nstatus: active\nadvisor_notes: [ "2026-11-16T00:00:00Z · advisor: project critique — no concerns · saw: " ]\nautonomy: gated\ndecisions: [ "D1: keep it small" ]\n---\n'
BADP=$'---\ntype: Project\nstatus: active\nadvisor_notes: [ "2026-11-16T00:00:00Z · advisor: project critique — no concerns · saw: " ]\nautonomy: gated\ndecisions:\n  - "D1: keep it small" trailing\n---\n'
GOODT=$'---\ntype: Task\nkind: build\nstatus: blocked\nopen_questions: [ "Q1: which store?" ]\n---\n'
BADT=$'---\ntype: Task\nkind: build\nstatus: blocked\nopen_questions: [ "Q1: unterminated\n---\n'
put() { printf '%s' "$2" > "$INST/$1"; }
settle() { GIT -C "$INST" add -A && GIT -C "$INST" commit -qm "$1"; }
tick() { rm -rf "$INST/$AB_TICK_START"; TD digest >/dev/null 2>&1; TD record >/dev/null 2>&1; }

put projects/proj-a/project.md "$GOODP"; put projects/proj-b/project.md "$GOODP"
put projects/proj-b/tasks/task-001-good.md "$GOODT"; put projects/proj-b/tasks/task-002-bad.md "$GOODT"
printf -- '---\ntype: Design\ninputs_hash: %s\ntasks: [ ]\n---\n' "$(bash "$S/design-inputs.sh" "$INST/projects/proj-a")" \
  > "$INST/projects/proj-a/design.md"
printf '/%s\n' "$AB_STATE_DIR" > "$INST/.gitignore"
mkdir -p "$INST/$AB_DIR"; printf '* TICK 2026-11-16T10:00:00Z by example-user-007 open: tick-1\n' > "$INST/$AB_LEDGER"
GIT -C "$INST" init -q; settle init

echo "== 1. the clean fixture: digest answers, names no step, and check reads IDLE =="
out="$(TD digest 2>"$TMP/err")"; rc=$?
ok "digest exits 0" "$rc" 0
ok "…with no stderr" "$(wc -c < "$TMP/err" | tr -d ' ')" 0
ok "…and an empty steps: line (the step-2 assertion below is not vacuous)" "$(printf '%s\n' "$out" | grep -c '^steps:$')" 1
ok "…and an empty reason file" "$(wc -c < "$REASON" | tr -d ' ')" 0
tick
ok "check after a clean record ⇒ IDLE" "$(TD check >/dev/null 2>&1; echo $?)" 0

echo "== 2. one malformed decisions block (with a design inputs_hash) and one malformed open_questions =="
put projects/proj-a/project.md "$BADP"; put projects/proj-b/tasks/task-002-bad.md "$BADT"; settle broken
ok "fold-answers.sh --list refuses the task doc at exit 3" \
   "$(bash "$S/fold-answers.real.sh" --list "$INST/projects/proj-b/tasks/task-002-bad.md" open_questions >/dev/null 2>&1; echo $?)" 3
ok "design-inputs.sh passes the refusal on at exit 3" "$(bash "$S/design-inputs.sh" "$INST/projects/proj-a" >/dev/null 2>&1; echo $?)" 3
rm -rf "$INST/$AB_TICK_START"
out="$(TD digest 2>"$TMP/err")"; rc=$?
ok "digest exits 0" "$rc" 0
ok "stdout names the project.md with its reason" \
   "$(printf '%s\n' "$out" | grep -c '^unparseable projects/proj-a/project.md text after a quoted entry in decisions$')" 1
ok "stdout names the task doc with its reason" \
   "$(printf '%s\n' "$out" | grep -c '^unparseable projects/proj-b/tasks/task-002-bad.md unterminated double-quoted entry in open_questions$')" 1
ok "stderr names both, once each" "$(grep -c '^unparseable projects/' "$TMP/err")" 2
ok "the valid task is still listed" "$(printf '%s\n' "$out" | grep -c '^task projects/proj-b/tasks/task-001-good.md status=blocked')" 1
ok "steps: names step 2" "$(printf '%s\n' "$out" | grep '^steps:' | grep -c 'step-2-refine-drafts.md')" 1
ok "no path in either line is absolute" "$(grep -cF "$INST" "$TMP/err")" 0
ok "the reason file holds the digest's stderr" "$(cat "$REASON")" "$(cat "$TMP/err")"
ok "…and is gitignored" "$(GIT -C "$INST" check-ignore -q "$REASON" && echo ignored)" ignored

echo "== 3. check never reads IDLE on either doc, record still succeeds =="
out="$(TD check 2>/dev/null)"; rc=$?
ok "check before any record of them ⇒ a DELTA naming the project.md" \
   "$rc:$(printf '%s\n' "$out" | grep -c '^DELTA: projects/proj-a/project.md cannot be parsed (text after a quoted entry in decisions)')" 1:1
ok "record succeeds and carries both" "$(TD record >/dev/null 2>&1; echo $?):$(grep -c '^unparseable ' "$INST/$AB_STATE_DIR")" 0:2
ok "check after the record ⇒ still not IDLE" "$(TD check >/dev/null 2>&1; echo $?)" 1
put projects/proj-a/project.md "$GOODP"; settle "decisions repaired"; tick
ok "only the task doc left: the record carries it" "$(grep -c '^unparseable projects/proj-b/tasks/task-002-bad.md ' "$INST/$AB_STATE_DIR")" 1
: > "$FOLDLOG"; out="$(TD check 2>/dev/null)"; rc=$?
ok "check ⇒ DELTA naming it, not IDLE" "$rc:$(printf '%s\n' "$out" | grep -c '^DELTA: projects/proj-b/tasks/task-002-bad.md could not be parsed')" 1:1
ok "…without re-parsing any task (0 fold-answers.sh calls on a task)" "$(grep -c '/tasks/' "$FOLDLOG")" 0
put projects/proj-b/tasks/task-002-bad.md "$GOODT"; settle "task repaired"; tick
ok "both repaired: one full tick later ⇒ IDLE again" "$(TD check >/dev/null 2>&1; echo $?)" 0

echo "== 3b. a digest that skips a doc and then fails still hands record its set =="
put projects/proj-b/tasks/task-002-bad.md "$BADT"; settle "broken for 3b"
cp "$S/continue-checkpoint.sh" "$TMP/ckpt.keep"; printf '#!/usr/bin/env bash\nexit 2\n' > "$S/continue-checkpoint.sh"
: > "$INST/$AB_AWAITING"
rm -rf "$INST/$AB_TICK_START"; TD digest >/dev/null 2>"$TMP/err"; rc=$?
ok "the digest fails later (checkpoint) and names that cause" "$rc:$(grep -c 'fingerprint: continue-checkpoint.sh failed' "$TMP/err")" 2:1
ok "…after writing the skipped doc as it found it" "$(grep -c '^unparseable projects/proj-b/tasks/task-002-bad.md ' "$INST/$AB_TICK_START/unparseable")" 1
cp "$TMP/ckpt.keep" "$S/continue-checkpoint.sh"
ok "record carries it" "$(TD record >/dev/null 2>&1; echo $?):$(grep -c '^unparseable projects/proj-b/tasks/task-002-bad.md ' "$INST/$AB_STATE_DIR")" 0:1
out="$(TD check 2>/dev/null)"; rc=$?
ok "check ⇒ the named DELTA, not IDLE" "$rc:$(printf '%s\n' "$out" | grep -c '^DELTA: projects/proj-b/tasks/task-002-bad.md could not be parsed')" 1:1
rm -f "$INST/$AB_AWAITING"

echo "== 3c. an answered entry in a list the parser refuses is named too =="
put projects/proj-b/tasks/task-002-bad.md $'---\ntype: Task\nkind: build\nstatus: blocked\nopen_questions: [ "Q1: which? --- postgres ]\n---\n'
settle "answered and malformed"
ok "fold-answers.sh refuses it at exit 3" \
   "$(bash "$S/fold-answers.real.sh" --list "$INST/projects/proj-b/tasks/task-002-bad.md" open_questions >/dev/null 2>&1; echo $?)" 3
rm -rf "$INST/$AB_TICK_START"; out="$(TD digest 2>/dev/null)"
ok "the digest names it" "$(printf '%s\n' "$out" | grep -c '^unparseable projects/proj-b/tasks/task-002-bad.md ')" 1
TD record >/dev/null 2>&1
ok "record then check ⇒ not IDLE" "$(TD check >/dev/null 2>&1; echo $?)" 1
put projects/proj-b/tasks/task-002-bad.md "$GOODT"; settle "task repaired again"; tick
ok "repaired ⇒ IDLE" "$(TD check >/dev/null 2>&1; echo $?)" 0

echo "== 4. only exit 3 is skip-and-name; every other failure is a named CANNOT ANSWER =="
put projects/proj-b/tasks/task-002-bad.md "$BADT"; settle "broken again"
FOLD_EXIT2=1 TD digest >/dev/null 2>"$TMP/err"; rc=$?
ok "fold-answers.sh exit 2 ⇒ digest exits 2" "$rc" 2
ok "…naming the parser and its own reason" "$(grep -c '^CANNOT ANSWER: could not complete the fingerprint: fold-answers.sh exit 2 reading decisions in projects/proj-a/project.md: python3 is required' "$TMP/err")" 1
put projects/proj-b/tasks/task-002-bad.md "$GOODT"
printf -- '---\ntype: Task\nstatus: in-review\npr: ["https://github.com/example-org/example-repo/pull/7"]\n---\n' > "$INST/projects/proj-b/tasks/task-003-pr.md"
TD digest >/dev/null 2>"$TMP/err"; rc=$?
ok "gh failing ⇒ digest exits 2" "$rc" 2
ok "…naming the PR query and gh's first stderr line" "$(grep -c 'gh PR query failed for https://github.com/example-org/example-repo/pull/7: HTTP 401: Bad credentials' "$TMP/err"):$(grep -c 'second line' "$TMP/err")" 1:0
ok "…and the reason file carries it" "$(grep -c 'HTTP 401' "$REASON")" 1
rm -f "$INST/projects/proj-b/tasks/task-003-pr.md"; chmod 000 "$INST/projects/proj-b/tasks/task-001-good.md"
TD digest >/dev/null 2>"$TMP/err"
ok "an unreadable task names itself, not the PR query" "$(grep -c 'fingerprint: unreadable projects/proj-b/tasks/task-001-good.md' "$TMP/err"):$(grep -c 'gh PR' "$TMP/err")" 1:0
chmod 644 "$INST/projects/proj-b/tasks/task-001-good.md"
put projects/proj-b/tasks/task-002-bad.md "$BADT"

echo "== 5. the reason file: digest-only, and what record --close does with it =="
rm -rf "$INST/$AB_TICK_START"; TD digest >/dev/null 2>&1
printf 'SENTINEL\n' > "$REASON"
TD check >/dev/null 2>&1; TD record >/dev/null 2>&1
ok "check and record leave it untouched" "$(cat "$REASON")" SENTINEL
TD digest >/dev/null 2>&1
ok "a digest truncates it first" "$(grep -c SENTINEL "$REASON"):$(grep -c '^unparseable ' "$REASON")" 0:1
printf 'unparseable %s/projects/x.md one\nunparseable projects/y.md two\n' "$INST" > "$REASON"
TD record --close "a summary" --tick 2026-11-16T10:00:00Z >/dev/null 2>&1
line="$(grep ' close: ' "$INST/$AB_LEDGER")"
ok "the close line carries its lines joined with '; ', relative" \
   "${line#* close: }" "a summary · digest: unparseable projects/x.md one; unparseable projects/y.md two"
printf '* TICK 2026-11-16T11:00:00Z by example-user-007 open: tick-2\n' >> "$INST/$AB_LEDGER"
printf 'unparseable %s %s\n' "projects/p/tasks/t.md" "$(printf 'x%.0s' $(seq 400))" > "$REASON"
TD record --close "long" --tick 2026-11-16T11:00:00Z >/dev/null 2>&1
line="$(grep '2026-11-16T11:00:00Z .* close: ' "$INST/$AB_LEDGER")"; app="${line#* · digest: }"
ok "…capped at 300 characters" "${#app}" 300
printf '* TICK 2026-11-16T11:30:00Z by example-user-007 open: tick-2b\n' >> "$INST/$AB_LEDGER"
printf 'unparseable p.md %s\n' "$(printf '—%.0s' $(seq 400))" > "$REASON"
LC_ALL=C TD record --close "dashes" --tick 2026-11-16T11:30:00Z >/dev/null 2>&1
app="$(grep '2026-11-16T11:30:00Z .* close: ' "$INST/$AB_LEDGER")"; app="${app#* · digest: }"
ok "…in characters under a C locale, never a split one" \
   "$(printf '%s' "$app" | perl -CS -ne 'print length($_)'):$(printf '%s' "$app" | perl -MEncode -e 'local $/; my $b = <STDIN>; eval { decode("UTF-8", $b, 1); 1 } ? print "utf8" : print "broken"')" 300:utf8
printf '* TICK 2026-11-16T11:40:00Z by example-user-007 open: tick-2c\n' >> "$INST/$AB_LEDGER"
printf 'unparseable %s/projects/z.md three\n' "$(cd "$INST" && pwd -P)" > "$REASON"
TD record --close "physical" --tick 2026-11-16T11:40:00Z >/dev/null 2>&1
ok "…a physical path is stripped whole, whatever --instance spelled" \
   "$(grep '2026-11-16T11:40:00Z .* close: ' "$INST/$AB_LEDGER" | sed 's/.* · digest: //')" "unparseable projects/z.md three"
printf '* TICK 2026-11-16T12:00:00Z by example-user-007 open: tick-3\n' >> "$INST/$AB_LEDGER"
put projects/proj-b/tasks/task-002-bad.md "$GOODT"; TD digest >/dev/null 2>&1
TD record --close "quiet" --tick 2026-11-16T12:00:00Z >/dev/null 2>&1
ok "a digest with no stderr leaves the close line unchanged" \
   "$(grep '2026-11-16T12:00:00Z .* close: ' "$INST/$AB_LEDGER")" "* TICK 2026-11-16T12:00:00Z by example-user-007 close: quiet"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'unparseable projects/old.md from an earlier tick\n' > "$REASON"; touch -t 202001010000 "$REASON"
printf '* TICK %s by example-user-007 open: tick-4\n' "$now" >> "$INST/$AB_LEDGER"
TD record --close "no digest this tick" --tick "$now" >/dev/null 2>&1
ok "a reason file older than the tick's open line is not this tick's" \
   "$(grep "$now .* close: " "$INST/$AB_LEDGER")" "* TICK $now by example-user-007 close: no digest this tick"

echo; echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
