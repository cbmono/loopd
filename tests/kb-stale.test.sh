#!/usr/bin/env bash
# kb-stale.test.sh — plugin/scripts/kb-stale.sh against fixture clones: threshold, path vs
# whole repo, prose path:, feature-branch checkout, dangling origin/HEAD, missing clone,
# impossible timestamp:, shallow clone, trailing # comments in applies_to:,
# Runbooks via one/two/no Services, deprecated; that it writes and fetches nothing; and the
# step-7 / cataloguer / config wiring. Reasoning: kb-retrieval-and-papercut-fixes/task-006.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SH="$REPO/plugin/scripts/kb-stale.sh"
STEP7="$REPO/plugin/tick-steps/step-7-knowledge-base.md"
CAT="$REPO/plugin/agents/cataloguer.md"
SEED="$REPO/plugin/seed/instance.config.json"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/kb-stale.XXXXXX")" || { echo "mktemp -d failed" >&2; exit 2; }
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
has() { printf '%s\n' "$1" | grep -cF -- "$2" | tr -d ' '; }
GIT() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -c user.name=t \
  -c user.email=t@example.com -c commit.gpgsign=false -c core.hooksPath=/dev/null \
  -c init.defaultBranch=main "$@"; }
commit() { # <repo> <date> <file> — one commit touching <file>, dated <date>
  mkdir -p "$1/$(dirname "$3")"; echo "$2" >> "$1/$3"
  GIT -C "$1" add -A
  GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" GIT -C "$1" commit -qm "$3 $2"
}

# Upstream: 1 base commit, then 3 on svc/ and 2 on other/ after 2026-01-15.
UP="$TMP/upstream/app"; mkdir -p "$UP"; GIT init -q "$UP"
commit "$UP" 2026-01-01T00:00:00Z svc/a.txt
for d in 02 03 04; do commit "$UP" "2026-02-${d}T00:00:00Z" svc/a.txt; done
for d in 10 11; do commit "$UP" "2026-02-${d}T00:00:00Z" other/b.txt; done

RR="$TMP/repos"; mkdir -p "$RR"
GIT clone -q "$UP" "$RR/app"
# Checked out on a feature branch with 10 more commits on svc/: none may be counted.
GIT -C "$RR/app" checkout -qb feature
for i in 01 02 03 04 05 06 07 08 09 10; do commit "$RR/app" "2026-03-${i}T00:00:00Z" svc/a.txt; done
# Upstream moves on after the clone: a fetch would change the clone's refs.
commit "$UP" 2026-02-20T00:00:00Z svc/a.txt
GIT clone -q "$UP" "$RR/dangle"
GIT -C "$RR/dangle" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/gone
GIT clone -q --depth 1 "file://$UP" "$RR/shallow"

B="$TMP/bundle"; mkdir -p "$B/knowledge/services" "$B/knowledge/runbooks"
printf '{ "org": "x", "reposRoot": "%s", "kbStaleCommits": 3 }\n' "$RR" > "$B/instance.config.json"
svc() { # <slug> <title> <repo> <path|-> <status> <timestamp>
  { printf -- '---\ntype: Service\ntitle: %s\nrepo: %s\n' "$2" "$3"
    [ "$4" = - ] || printf 'path: %s\n' "$4"
    printf 'status: %s\ntimestamp: %s\n---\n\n# Overview\n' "$5" "$6"; } > "$B/knowledge/services/$1.md"
}
rb() { # <slug> <timestamp> <applies_to line(s)>
  printf -- '---\ntype: Runbook\ntitle: %s\n%s\ntimestamp: %s\n---\n\n# Steps\n' "$1" "$3" "$2" \
    > "$B/knowledge/runbooks/$1.md"
}
T0=2026-01-15T00:00:00Z
svc at-threshold "At Threshold" example-org/app svc active "$T0"
svc below        "Below"        example-org/app other active "$T0"
svc whole        "Whole App"    example-org/app - active "$T0"
svc prose        "Prose"        example-org/app "(whole repo; everything is under svc/)" active "$T0"
svc fresh        "Fresh"        example-org/app svc/ active 2026-02-05T00:00:00Z
svc old-gone     "Old Gone"     example-org/app svc deprecated "$T0"
svc no-clone     "No Clone"     example-org/missing - active "$T0"
svc dangling     "Dangling"     example-org/dangle - active "$T0"
svc bad-date     "Bad Date"     example-org/app svc active 2026-02-30T00:00:00Z
svc bad-time     "Bad Time"     example-org/app svc active 2026-01-15T25:00:00Z
svc shallow      "Shallow"      example-org/shallow - active "$T0"
rb rb-one        "$T0" 'applies_to: [ at-threshold ]'
rb rb-two        "$T0" "$(printf 'applies_to:\n  - "Whole App"\n  - at-threshold\n  - whole')"
rb rb-fresh      2026-02-05T00:00:00Z 'applies_to: [ at-threshold, Whole App ]'
rb rb-none       "$T0" 'applies_to: [ example-org/app, deploy.sh, release area ]'
rb rb-deprecated "$T0" 'applies_to: [ old-gone ]'
rb rb-bad-date   2026-13-01T00:00:00Z 'applies_to: [ at-threshold ]'
rb rb-comment    "$T0" "$(printf 'applies_to:\n  - at-threshold  # the main one')"
rb rb-flow-cmt   "$T0" 'applies_to: [ at-threshold ]  # the main one'

snap() { # everything kb-stale must not touch
  ( cd "$B" && find knowledge -type f -exec cksum {} + | sort )
  for c in app dangle; do
    GIT -C "$RR/$c" for-each-ref --format='%(refname) %(objectname) %(symref)'
    cat "$RR/$c/.git/HEAD"; ls "$RR/$c/.git"
  done
}
BEFORE="$(snap)"
OUT="$(bash "$SH" --instance "$B" 2>&1)"; RC=$?
AFTER="$(snap)"
line() { printf '%s\n' "$OUT" | grep -F -- "$1"; }

echo "== Services =="
ok "exit 0: something listed" "$RC" 0
ok "at threshold (3 on svc/) is listed" "$(has "$OUT" 'knowledge/services/at-threshold.md — 3 commits on origin/main')" 1
ok "below threshold (2 on other/) is not listed" "$(has "$OUT" 'services/below.md')" 0
ok "no path: counts the whole repo (5)" "$(has "$OUT" 'services/whole.md — 5 commits on origin/main since 2026-01-15T00:00:00Z in the whole repo')" 1
ok "feature-branch commits are not counted" "$(has "$OUT" '15 commits')" 0
ok "prose path: is UNKNOWN, path not in clone" "$(line services/prose.md | grep -c '^UNKNOWN .*path not in clone' | tr -d ' ')" 1
ok "a timestamp after the commits is not listed" "$(has "$OUT" 'services/fresh.md')" 0
ok "missing clone is UNKNOWN" "$(line services/no-clone.md | grep -c '^UNKNOWN .*no clone at' | tr -d ' ')" 1
ok "dangling origin/HEAD is UNKNOWN" "$(line services/dangling.md | grep -c '^UNKNOWN .*does not resolve' | tr -d ' ')" 1
ok "no UNKNOWN doc ever reads 0 commits" "$(has "$OUT" ' 0 commits')" 0
ok "impossible date (02-30) is UNKNOWN, not 0" "$(line services/bad-date.md | grep -c '^UNKNOWN .*not a valid date' | tr -d ' ')" 1
ok "impossible time (25:00) is UNKNOWN, not 0" "$(line services/bad-time.md | grep -c '^UNKNOWN .*not a valid date' | tr -d ' ')" 1
ok "shallow clone is UNKNOWN, not an under-count" "$(line services/shallow.md | grep -c '^UNKNOWN .*shallow clone' | tr -d ' ')" 1
ok "deprecated over threshold is not listed" "$(has "$OUT" 'old-gone.md')" 0
ok "…and is tallied on one skipped line" "$(has "$OUT" 'skipped (deprecated): 1 Service(s)')" 1

echo "== Runbooks =="
ok "via one Service: listed" "$(has "$OUT" 'runbooks/rb-one.md — commits since its 2026-01-15T00:00:00Z: at-threshold 3')" 1
ok "via two Services (title + slug, block list): listed once naming both" \
  "$(has "$OUT" 'runbooks/rb-two.md — commits since its 2026-01-15T00:00:00Z: whole 5, at-threshold 3')" 1
ok "…exactly once" "$(has "$OUT" 'rb-two.md')" 1
ok "impossible Runbook date (month 13) is UNKNOWN" "$(line runbooks/rb-bad-date.md | grep -c '^UNKNOWN .*not a valid date' | tr -d ' ')" 1
ok "a trailing # comment on a block item still resolves" "$(has "$OUT" 'runbooks/rb-comment.md — commits since its 2026-01-15T00:00:00Z: at-threshold 3')" 1
ok "a trailing # comment after a flow list still resolves" "$(has "$OUT" 'runbooks/rb-flow-cmt.md — commits since its 2026-01-15T00:00:00Z: at-threshold 3')" 1
ok "counted from the Runbook's own timestamp" "$(has "$OUT" 'rb-fresh.md')" 0
ok "unresolvable and deprecated-only on one unchecked line" \
  "$(has "$OUT" 'unchecked: 2 Runbook(s) resolve to no active Service — rb-deprecated rb-none')" 1
ok "threshold is the configured kbStaleCommits" "$(has "$OUT" 'at kbStaleCommits 3')" 1

echo "== report-only: writes and fetches nothing =="
ok "knowledge/ and the clones' refs are byte-identical" "$([ "$BEFORE" = "$AFTER" ] && echo yes || echo no)" yes
ok "no FETCH_HEAD appeared" "$([ -e "$RR/app/.git/FETCH_HEAD" ] && echo yes || echo no)" no
ok "the script names no fetch" "$(grep -cE 'git[^|]* fetch' "$SH" | tr -d ' ')" 0
ok "build-kb-index.sh --check never calls it" "$(grep -c 'kb-stale' "$REPO/plugin/scripts/build-kb-index.sh" | tr -d ' ')" 0

echo "== default threshold, and nothing listed =="
sed 's/, "kbStaleCommits": 3//' "$B/instance.config.json" > "$TMP/c" && mv "$TMP/c" "$B/instance.config.json"
rm "$B"/knowledge/services/{prose,no-clone,dangling,bad-date,bad-time,shallow}.md "$B"/knowledge/runbooks/rb-bad-date.md
OUT="$(bash "$SH" --instance "$B" 2>&1)"; RC=$?
ok "absent key ⇒ 20" "$(has "$OUT" 'at kbStaleCommits 20')" 1
ok "below 20 nothing listed, exit 1" "$RC|$(has "$OUT" 'STALE')" "1|0"
sed 's/^{ /{ "kbStaleCommits": 0, /' "$B/instance.config.json" > "$TMP/c" && mv "$TMP/c" "$B/instance.config.json"
OUT="$(bash "$SH" --instance "$B" 2>&1)"
ok "kbStaleCommits 0 ⇒ 20, and says so" "$(has "$OUT" "kbStaleCommits '0' is not a positive integer; using 20")" 1
ok "no knowledge/ is a usage error" "$(bash "$SH" --instance "$TMP/none" >/dev/null 2>&1; echo $?)" 2

echo "== wiring =="
ok "seeded kbStaleCommits 20" "$(jq -c '.kbStaleCommits' "$SEED")" 20
ok "\$kbStaleCommits doc line" "$(jq -r 'has("$kbStaleCommits")' "$SEED")" true
ok "literal resolve-config.sh call site" "$(grep -c 'resolve-config.sh" --instance "$inst" kbStaleCommits' "$SH" | tr -d ' ')" 1
ok "step 7 runs it only alongside an existing cataloguer dispatch" \
  "$(grep -c 'never a reason to dispatch one' "$STEP7" | tr -d ' ')" 1
ok "step 7 pastes its list into that brief" "$(grep -c 'paste its output into that one brief' "$STEP7" | tr -d ' ')" 1
ok "cataloguer bumps timestamp: on a no-change review" \
  "$(grep -c 'even when the body is unchanged' "$CAT" | tr -d ' ')" 1

printf '\npass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
