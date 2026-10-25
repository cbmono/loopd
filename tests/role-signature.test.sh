#!/usr/bin/env bash
#
# role-signature.test.sh — the `— <login>-<role>` line every agent PR comment and review
# ends with: one helper prints it, the prompts name it, the comment gate still clears a
# signed reply, and no gate reads it (configurable-review-rounds/task-004).
#
# The PROMPTS and NO-GATE checks are driven over fixtures first, so neither can pass by
# matching nothing.
# shellcheck disable=SC2016  # backticks below are markdown, never an expansion
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$REPO/plugin/scripts/role-signature.sh"
COMMENT_GATE="$REPO/plugin/scripts/pr-comment-clearance.sh"
[ -x "$HELPER" ] || { echo "role-signature.test: missing $HELPER" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/role-signature.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

echo "== ONE SOURCE: the helper, from inside and outside the bundle =="
BUNDLE="$TMP/bundle"; mkdir -p "$BUNDLE" "$TMP/elsewhere"
printf '{ "ownerGithubUser": "example-user-007" }\n' > "$BUNDLE/instance.config.json"
EMPTY="$TMP/empty"; mkdir -p "$EMPTY"; printf '{ }\n' > "$EMPTY/instance.config.json"

for pair in qa-reviewer:qa software-engineer:dev devops-engineer:ops project-manager:pm; do
  role="${pair%%:*}"; short="${pair#*:}"
  ok "$role -> -$short, called from outside the bundle" \
     "$(cd "$TMP/elsewhere" && "$HELPER" "$role" --instance "$BUNDLE")" "— example-user-007-$short"
done
ok "inside the bundle, no --instance needed" \
   "$(cd "$BUNDLE" && "$HELPER" qa-reviewer)" "— example-user-007-qa"
ok "no ownerGithubUser -> <unknown> as-is" "$("$HELPER" software-engineer --instance "$EMPTY")" "— <unknown>-dev"
ok "…and still exit 0, so the line is posted" "$("$HELPER" software-engineer --instance "$EMPTY" >/dev/null; echo $?)" 0
ok "outside the bundle with no --instance -> <unknown>" \
   "$(cd "$TMP/elsewhere" && "$HELPER" devops-engineer)" "— <unknown>-ops"
ok "an unknown role is a usage error" "$("$HELPER" cataloguer --instance "$BUNDLE" >/dev/null 2>&1; echo $?)" 2
ok "no role is a usage error"         "$("$HELPER" >/dev/null 2>&1; echo $?)" 2

echo
echo "== PROMPTS: every file that tells an agent to post names the signature =="
# A file with a posting instruction must name the signature; naming the trailer as well
# is fine. File-level on purpose: the instruction and the rule are paragraphs apart.
POSTS='gh pr (comment|review)|[Pp]ost (via|a|the|your|one|every)[^.]{0,30}(comment|review|reply|verdict)|PR comment and review'
SIGNS='role-signature[.]sh|role signature'
unsigned() { # <file> -> yes when it tells an agent to post and never names the signature
  if grep -qE "$POSTS" "$1" && ! grep -qE "$SIGNS" "$1"; then echo yes; else echo no; fi
}
printf 'Post via `gh pr review` as a **comment**.\n' > "$TMP/bare.md"
ok "fixture: a posting instruction alone is caught" "$(unsigned "$TMP/bare.md")" yes
printf 'Post via `gh pr review`.\nEnd it with your role signature, then the `okf-verdict v1` trailer.\n' > "$TMP/both.md"
ok "fixture: signature AND trailer named is tolerated" "$(unsigned "$TMP/both.md")" no

for f in plugin/agents/qa-reviewer.md plugin/agents/software-engineer.md \
         plugin/agents/devops-engineer.md plugin/agents/project-manager.md plugin/seed/CONVENTIONS.md; do
  ok "$f tells its reader to post" "$(grep -qE "$POSTS" "$REPO/$f" && echo yes || echo no)" yes
  ok "…and names the signature"    "$(unsigned "$REPO/$f")" no
done
for pair in qa-reviewer software-engineer devops-engineer project-manager; do
  ok "$pair.md calls the helper by its plugin path with its own role" \
     "$(grep -cF "\${CLAUDE_PLUGIN_ROOT}/scripts/role-signature.sh $pair --instance <bundle>" "$REPO/plugin/agents/$pair.md")" 1
done
ok "qa-reviewer.md puts the trailer after the signature" \
   "$(grep -c 'role signature line.*then the$' "$REPO/plugin/agents/qa-reviewer.md")" 1

echo
echo "== EXEMPT: PR bodies and the bare @coderabbitai review request =="
ok "CONVENTIONS.md exempts both" \
   "$(grep -c 'Exempt:\*\* a PR body, and the tick.s bare `@coderabbitai review`' "$REPO/plugin/seed/CONVENTIONS.md")" 1
ok "project-manager.md exempts both" \
   "$(grep -c 'a PR body, and step 4.s bare' "$REPO/plugin/agents/project-manager.md")" 1
ok "the tick's review request carries no signature" \
   "$(grep 'by commenting `@coderabbitai review`' "$REPO/plugin/tick-steps/step-4-advance.md" | grep -cE "$SIGNS")" 0
ok "pr-body-clearance.sh knows nothing of it" "$(grep -cE "$SIGNS" "$REPO/plugin/scripts/pr-body-clearance.sh")" 0

echo
echo "== CLEARANCE UNHARMED: a signed reply clears the comment gate =="
SIG="— $(printf 'a%.0s' $(seq 39))-dev"   # the longest login GitHub allows
pad()   { printf '%*s' "$1" '' | tr ' ' 'x'; }
entry() { printf -- '- fixed: %s' "$(pad "$(( $1 - 9 ))")"; }
signed() { # <entry-bytes> [tail] -> a reply whose last visible line is the signature
  { printf 'Round 1 addressed in `a1b2c3d`.\n\n%s\n' "$(entry "$1")"
    [ -z "${2:-}" ] || printf '\n%s\n' "$2"
    printf '%s\n' "$SIG"; } > "$TMP/reply.md"
}
clears() { "$COMMENT_GATE" --comment-file "$TMP/reply.md" >/dev/null 2>&1; echo $?; }
for n in 530 503; do
  signed "$n" 'Evidence: `foo.test.sh` 41/0.'; ok "the $n-byte fixture, evidence then signature" "$(clears)" 0
  signed "$n";                                 ok "the $n-byte fixture, signature under the entry" "$(clears)" 0
done
signed 618;                                   ok "control: a 618-byte entry plus the signature is refused" "$(clears)" 3
signed 530 'Evidence: `foo.test.sh` 41/0.'
printf '<!-- okf-verdict v1\nverdict: pass\nhead_sha: %s\nreviewer: qa-reviewer\nlenses: correctness=done security=done repro=done\nunverified_criteria: none\ncaveats: none\n-->\n' \
  "$(pad 40)" >> "$TMP/reply.md"
ok "…and with an okf-verdict trailer after the signature" "$(clears)" 0
"$HELPER" software-engineer --instance "$BUNDLE" > "$TMP/sig"
signed 530 'Evidence: `foo.test.sh` 41/0.'; sed -i.bak '$d' "$TMP/reply.md"; cat "$TMP/sig" >> "$TMP/reply.md"
ok "the helper's own line, appended" "$(clears)" 0

echo
echo "== NO GATE READS IT =="
# A READER is code that matches the signature in a comment body — the regex
# `— [^ ]+-(qa|dev|ops|pm)` or any alternation of the short names — or that calls the
# helper. Comment lines are skipped, so prose saying it is not evidence passes.
READER='role-signature[.]sh"?[[:space:]]+(qa-reviewer|software-engineer|devops-engineer|project-manager)|[(](qa|dev|ops|pm)([|](qa|dev|ops|pm))+[)]|— *[.[][^[:space:]]*-(qa|dev|ops|pm)'
readers() { grep -vE '^[[:space:]]*(#|<!--)' "$1" | grep -E "$READER"; }
printf '%s\n' "body_has_sig() { grep -qE '— [^ ]+-(qa|dev|ops|pm)' \"\$1\"; }" > "$TMP/reads.sh"
ok "fixture: a regex over a body is caught" "$(readers "$TMP/reads.sh" | grep -c .)" 1
printf '%s\n' "is_qa() { grep -q -- '— .*-qa' \"\$1\"; }" > "$TMP/reads1.sh"
ok "fixture: a one-role regex is caught" "$(readers "$TMP/reads1.sh" | grep -c .)" 1
printf '%s\n' 'sig="$(bash "$HERE/role-signature.sh" qa-reviewer)"' > "$TMP/calls.sh"
ok "fixture: a call to the helper is caught" "$(readers "$TMP/calls.sh" | grep -c .)" 1
printf '%s\n' '# the `— <login>-qa` line is not evidence' \
  'A `— <login>-qa` signature (`role-signature.sh`) is a label, never evidence.' > "$TMP/prose.md"
ok "fixture: prose saying it is not evidence passes" "$(readers "$TMP/prose.md" | grep -c .)" 0

GATES="$(sed -n '/^GATE_FILES="$/,/^"$/p' "$REPO/plugin/scripts/required-checks.sh" | grep -v '"')"
ok "GATE_FILES parsed from required-checks.sh" "$([ "$(grep -c . <<<"$GATES")" -ge 10 ] && echo yes || echo no)" yes
for f in $GATES $(cd "$REPO" && ls plugin/scripts/*-clearance.sh); do
  hits="$(readers "$REPO/$f")"
  [ -z "$hits" ] || printf '        %s\n' "$hits"
  ok "$f reads no signature" "$(grep -c . <<<"$hits")" 0
done

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
