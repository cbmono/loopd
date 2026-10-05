#!/usr/bin/env bash
#
# kb-usage.test.sh — plugin/scripts/kb-usage.sh: the citation store, and the archive sweep
# that rides inside kb-propose.sh and lands only through kb-apply.sh.
#
# SILENCE ALONE NEVER ARCHIVES. Each qualifier gets a fixture that fails only it, beside one
# that passes them all, so a sweep that archives everything and a sweep that archives
# nothing both go red. Dates are pinned with --today. Reasoning: knowledge-base-reflector/task-005.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
USAGE="$REPO/plugin/scripts/kb-usage.sh"
PROPOSE="$REPO/plugin/scripts/kb-propose.sh"
APPLY="$REPO/plugin/scripts/kb-apply.sh"
BUILD="$REPO/plugin/scripts/build-kb-index.sh"
VALIDATE="$REPO/plugin/scripts/validate-bundle.sh"
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$REPO/plugin/scripts/bundle-paths.sh"
for f in "$USAGE" "$PROPOSE" "$APPLY"; do
  [ -x "$f" ] || { echo "kb-usage.test: $f is missing or not executable" >&2; exit 2; }
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/kbusage.XXXXXX")" || { echo "kb-usage.test: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
code() { grep -vE '^[[:space:]]*#' "$1"; }

TODAY=2026-10-03
D="$TMP/bundle"
mkdir -p "$D/knowledge/findings" "$D/$AB_DIR"
item() { # <slug> <category|-> <timestamp> [provenance]
  { printf -- '---\ntype: Finding\ntitle: Title %s\ndescription: d\nlesson: l %s\n' "$1" "$1"
    [ "$2" = - ] || printf 'category: %s\n' "$2"
    printf 'tags: [ ]\nstatus: current\nprovenance: %s\ntimestamp: %sT00:00:00Z\n---\n\n# Finding\n\nThe claim of %s.\n' \
      "${4:-machine}" "$3" "$1"
  } >"$D/knowledge/findings/$1.md"
}
item stale-learning  learning 2025-01-01   # past every qualifier
item young-learning  learning 2026-09-23   # under the age threshold
item stale-gotcha    gotcha   2025-01-01   # under the category threshold: a rare failure
item stale-nocat     -        2025-01-01   # uncategorised is never archivable
item cited-learning  learning 2025-01-01   # old, but a brief cited it recently
item cited-measure   measurement 2025-01-01
item stale-human     learning 2025-01-01 human
cp "$REPO/plugin/seed/knowledge/vocab.md" "$D/knowledge/vocab.md"
: >"$D/knowledge/log.md"
printf '{ "org": "example-org" }\n' >"$D/instance.config.json"
cp "$REPO/plugin/seed/SCHEMA.md" "$D/$AB_DIR/SCHEMA.md"
cd "$D" || exit 2
bash "$BUILD" >/dev/null 2>&1
git init -q . && git config user.name example-user-007 && git config user.email u@example.com
git add -A && git commit -qm init

echo "== criterion 1: one citation reaches the store =="
printf 'Fixed it per [[cited-learning]] and [[stale-gotcha]], not [[nope]].\n' >"$TMP/result.md"
out="$("$USAGE" record --source task-001.result --text-file "$TMP/result.md" --brief cited-learning 2>/dev/null)"; rc=$?
STORE="$D/$AB_DIR/citations/task-001.result.txt"
ok "record passes cite-check's exit code through (3: dropped)" "$rc" 3
ok "…and its report"                                  "$(grep -c '^KEPT cited-learning ' <<<"$out")" 1
ok "the store file is named for the source"           "$([ -f "$STORE" ] && echo yes || echo no)" yes
ok "a KEPT citation is stored"                        "$(grep -cx 'KEPT cited-learning' "$STORE")" 1
ok "an UNREAD one is stored: a real doc someone wanted" "$(grep -cx 'UNREAD stale-gotcha' "$STORE")" 1
ok "a FABRICATED one is not: it names no document"    "$(grep -c 'nope' "$STORE")" 0
cp "$STORE" "$TMP/first"
"$USAGE" record --source task-001.result --text-file "$TMP/result.md" --brief cited-learning --today 2027-01-01 >/dev/null 2>&1
ok "a re-run is idempotent: same file, same recorded date" "$(cmp -s "$TMP/first" "$STORE" && echo same || echo differs)" same
ok "record with no index stores nothing (exit 2)" \
  "$(cd "$TMP" && mkdir -p bare/knowledge && "$USAGE" --instance bare record --source x --text-file "$TMP/result.md" --brief a >/dev/null 2>&1; echo "$?/$(ls "$TMP/bare/$AB_DIR/citations" 2>/dev/null | wc -l | tr -d ' ')")" 2/0
ok "a source id carrying a path is refused" \
  "$("$USAGE" record --source ../x --text-file "$TMP/result.md" --brief a >/dev/null 2>&1; echo $?)" 2
rm -f "$STORE"

echo
echo "== the store floor: on today's data (no citations anywhere) nothing archives =="
sweep() { "$USAGE" sweep --today "$TODAY" "$@"; }
ok "an empty store archives nothing, however old"      "$(sweep | grep -c '^ARCHIVE')" 0
ok "…and says the store is why"                         "$(sweep | grep '^KEEP stale-learning ' | grep -c 'fails texts,store$')" 1

# Ten texts and twenty citations: exactly the default floors.
for n in 1 2 3 4 5 6 7 8 9 10; do
  printf 'recorded: 2026-09-%02d\nKEPT cited-learning\nUNREAD cited-measure\n' "$n" >"$D/$AB_DIR/citations/pr-$n.txt"
done
echo
echo "== criterion 4: under age OR category is kept; past both is archived =="
out="$(sweep)"
verdict() { awk -v s="$1" '$2 == s { print $1 }' <<<"$out"; }
ok "past both thresholds: ARCHIVE"                     "$(verdict stale-learning)" ARCHIVE
ok "under the age threshold: KEEP"                     "$(verdict young-learning)" KEEP
ok "…because of age alone"                             "$(grep '^KEEP young-learning ' <<<"$out" | sed 's/.*fails //')" age,texts
ok "under the category threshold: KEEP"                "$(verdict stale-gotcha)" KEEP
ok "…because of category alone"                        "$(grep '^KEEP stale-gotcha ' <<<"$out" | sed 's/.*fails //')" category
ok "no category: KEEP"                                 "$(verdict stale-nocat)" KEEP
ok "old but cited 23 days ago: KEEP (the clock restarts)" "$(verdict cited-learning)" KEEP
ok "…an UNREAD citation counts as use too"              "$(verdict cited-measure)" KEEP
grep -q '^KEEP stale-learning .*fails texts$' <<<"$("$USAGE" sweep --today "$TODAY" --min-texts 11)"
ok "one text short of the floor: KEEP"                 "$?" 0
ok "the thresholds are printed"                        "$(grep -c '^thresholds: category in {learning measurement} · uncited >= 180d' <<<"$out")" 1

echo
echo "== criterion 9: grace is derived from disk, so a re-run is the same answer =="
ok "remaining grace is printed per item (180 - 10 days)" "$(grep -c '^KEEP young-learning .* grace 170d ' <<<"$out")" 1
ok "a second sweep is byte-identical"                  "$([ "$out" = "$(sweep)" ] && echo same || echo differs)" same
ok "the sweep wrote nothing"                           "$(git status --porcelain knowledge/ | wc -l | tr -d ' ')" 0

echo
echo "== criterion 8: the sweep rides inside kb-propose.sh, the command that derives the next id =="
export KB_USAGE_TODAY="$TODAY"
SWEEPLINE="$(head -1 <<<"$(code "$PROPOSE" | grep -n 'kb-usage\.sh')" | cut -d: -f1)"
IDLINE="$(head -1 <<<"$(code "$PROPOSE" | grep -n '^id=')" | cut -d: -f1)"
ok "kb-propose.sh calls the sweep before it derives the report id" \
  "$([ -n "$SWEEPLINE" ] && [ -n "$IDLINE" ] && [ "$SWEEPLINE" -lt "$IDLINE" ] && echo yes || echo no)" yes
"$PROPOSE" --proposer 'echo kaputt; exit 7' >/dev/null 2>&1
ok "an interrupted run (the proposer died) writes no report" "$(ls projects 2>/dev/null | wc -l | tr -d ' ')" 0
BEFORE="$(find knowledge -type f -exec cksum {} + | sort)"
out="$("$PROPOSE" 2>"$TMP/propose.err")"; rc=$?
ok "with NO proposer configured, the sweep still proposes"   "$rc" 0
REPORT="$(sed -n 's/.* in \(projects[^ ]*\.md\) .*/\1/p' <<<"$out")"
ok "the report proposes archiving the stale learning"  "$(grep -c '^P[0-9]* · status · stale-learning · status=archived · - · ' "$REPORT")" 1
ok "…and nothing else that a person wrote"             "$(grep -c 'stale-human' "$REPORT")" 0
ok "…the human-written one is dropped by name"         "$(grep -c 'stale-human is not provenance: machine' "$TMP/propose.err")" 1
ok "proposing changed no byte of knowledge/"           "$([ "$BEFORE" = "$(find knowledge -type f -exec cksum {} + | sort)" ] && echo yes || echo no)" yes

echo
echo "== criterion 5: archive is status: archived, nothing deleted, nothing moved =="
cp knowledge/findings/stale-learning.md "$TMP/before.md"
FILES_BEFORE="$(find knowledge -type f ! -name index.md ! -name .ledger-floor | sort)"
"$APPLY" --by example-user-007 "$REPORT" >/dev/null 2>"$TMP/apply.err"; rc=$?
ok "the human applies it through kb-apply.sh"          "$rc" 0
ok "status: archived"                                  "$(sed -n 's/^status: //p' knowledge/findings/stale-learning.md)" archived
ok "…the reason is in its ledger entry"                "$(grep -c '^ledger: \[ "L1 · .* · status · by example-user-007 · items stale-learning · uncited in 10 text(s) over 640 days, category learning" \]' knowledge/findings/stale-learning.md)" 1
ok "every other line is byte-identical"                "$(diff <(grep -vE '^(status|ledger):' "$TMP/before.md") <(grep -vE '^(status|ledger):' knowledge/findings/stale-learning.md) >/dev/null && echo yes || echo no)" yes
ok "no file under knowledge/ was removed or moved"     "$([ "$FILES_BEFORE" = "$(find knowledge -type f ! -name index.md ! -name .ledger-floor | sort)" ] && echo yes || echo no)" yes
ok "build-kb-index --check accepts it"                 "$(bash "$BUILD" --check >/dev/null 2>&1; echo $?)" 0
ok "…and renders it as history"                        "$(awk '/^### Archived/{a=1} a && /stale-learning\.md/{print "yes"; exit}' knowledge/index.md)" yes
ok "validate-bundle accepts it"                        "$(bash "$VALIDATE" knowledge/findings/stale-learning.md 2>&1 | sed -n 's/.* \([0-9]*\) errors.*/\1/p')" 0
ok "an archived Finding is not swept again"            "$(sweep | grep -c ' stale-learning ')" 0
# Every line that could remove or move a file is pinned: the temp-file pair in `record`, and
# nothing else. A new delete path anywhere in the archiver fails here, named.
DELETES="$(code "$USAGE" | grep -nE '(^|[^a-z])(rm|unlink|mv|truncate|shred|rmdir)([^a-z]|$)|os\.remove|git (rm|mv)' | sed 's/^[0-9]*://; s/^[[:space:]]*//')"
ok "kb-usage.sh's only rm/mv are its own temp file"    "$(printf '%s\n' "$DELETES" | grep -cv '"\$t"')" 0
ok "kb-propose.sh has no delete or move"               "$(code "$PROPOSE" | grep -cE '(^|[^a-z])(rm|unlink|mv|truncate|rmdir)[[:space:]]|os\.remove|git (rm|mv)')" 0

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
