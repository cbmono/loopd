#!/usr/bin/env bash
#
# comment-check.test.sh — plugin/scripts/comment-check.sh reports an added explanatory
# comment and lets a section header, an http(s) link and a machine-read line through, reads
# only added lines against origin/<default>, and exits 0 on every path (D2). Fixture: a
# bare origin whose default branch is `trunk`, so nothing passes by assuming `main`.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
CC="$REPO/plugin/scripts/comment-check.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/commentcheck.XXXXXX")" || {
  echo "comment-check.test: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
has() { grep -qF -- "$1" <<<"$OUT" && echo yes || echo no; }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
g() { git -C "$W" -c user.name=t -c user.email=t@example.com "$@" >/dev/null 2>&1; }
git init -q --bare -b trunk "$TMP/origin.git"
W="$TMP/w"; git clone -q "$TMP/origin.git" "$W" 2>/dev/null
cat > "$W/old.sh" <<'EOF'
#!/usr/bin/env bash
# This base comment explains a lot of things at once, and it is not new here.
# Removing this explanatory line must not be reported either, since it is gone.
echo old
EOF
g checkout -q -b trunk; g add -A; g commit -q -m base; g push -q origin trunk
git -C "$W" remote set-head origin trunk >/dev/null 2>&1
g checkout -q -b feat

sed -i.bak '3d' "$W/old.sh" && rm "$W/old.sh.bak"
cat > "$W/new.sh" <<'EOF'
#!/usr/bin/env bash
# shellcheck disable=SC2086
# SPDX-License-Identifier: MIT
# Helpers
# See https://github.com/example-user-007/x/issues/12 for why this wraps the upstream call.
echo "a # b is a string, not a comment"
# Retry once because the upstream API flakes under load.
retry=1
# The cache key includes the user
# so that two sessions never share an entry
x=1  # bump this when the upstream server changes its rate limits.
y=2  # px
EOF
cat > "$W/app.ts" <<'EOF'
// eslint-disable-next-line no-console
// @ts-expect-error
const z = 1; // noqa: the linter is wrong about this one, see the issue
/*
 * We cannot use the builtin here. It silently drops the trailing record.
 */
EOF
cat > "$W/doc.md" <<'EOF'
# A markdown heading is not a comment
<!-- inline: plugin/seed/CONVENTIONS.md -->
<!-- This block is kept because the renderer strips it otherwise. -->
EOF
g add -A; g commit -q -m feat

OUT="$(bash "$CC" -C "$W")"; rc=$?
echo "== a branch adding headers, links, directives and explanations =="
ok "exit 0 with explanatory comments present"           "$rc" 0
ok "default range is origin/<default>, not main"        "$(has 'in origin/trunk...HEAD')" yes
ok "count of reported lines"                            "$(awk 'NR == 1 { print $2 }' <<<"$OUT")" 6
ok "explanatory comment reported, with path:line"       "$(has 'new.sh:7: # Retry once because the upstream API flakes under load.')" yes
ok "wrapped prose: first short line reported too"       "$(has 'new.sh:9: # The cache key includes the user')" yes
ok "wrapped prose: second line reported"                "$(has 'new.sh:10: # so that two sessions')" yes
ok "trailing explanatory comment reported"              "$(has 'new.sh:11:')" yes
ok "block comment's prose line reported"                "$(has 'app.ts:5:')" yes
ok "markdown explanatory comment reported"              "$(has 'doc.md:3:')" yes
ok "section header not reported"                        "$(has '# Helpers')" no
ok "http(s) link not reported"                          "$(has 'issues/12')" no
ok "shebang not reported"                               "$(has 'new.sh:1:')" no
ok "shellcheck directive not reported"                  "$(has 'shellcheck')" no
ok "licence header not reported"                        "$(has 'SPDX')" no
ok "eslint-disable not reported"                        "$(has 'eslint-disable')" no
ok "@ts-expect-error not reported"                      "$(has '@ts-expect-error')" no
ok "trailing noqa not reported"                         "$(has 'noqa')" no
ok "short trailing title not reported"                  "$(has '# px')" no
ok "a # inside quotes is not a comment"                 "$(has 'new.sh:6:')" no
ok "<!-- inline: --> marker not reported"               "$(has 'inline:')" no
ok "markdown heading not a comment"                     "$(has 'markdown heading')" no
ok "removed and base comments not reported"             "$(has 'old.sh')" no

echo "== every path exits 0 =="
OUT="$(bash "$CC" --range trunk...trunk -C "$W")"; rc=$?
ok "an empty range reports 0, exit 0"                   "$rc:$(has 'comment-check: 0 added')" 0:yes
git -C "$W" remote set-head origin -d >/dev/null 2>&1
OUT="$(bash "$CC" -C "$W")"; rc=$?
ok "no origin/HEAD is UNKNOWN, exit 0"                  "$rc:$(has 'UNKNOWN')" 0:yes
OUT="$(bash "$CC" --bogus)"; rc=$?
ok "a bad argument is UNKNOWN, exit 0"                  "$rc:$(has 'UNKNOWN')" 0:yes
OUT="$(bash "$CC" -C "$TMP/nowhere" --range a...b)"; rc=$?
ok "an unreadable diff is UNKNOWN, exit 0"              "$rc:$(has 'UNKNOWN')" 0:yes

echo
echo "comment-check: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
