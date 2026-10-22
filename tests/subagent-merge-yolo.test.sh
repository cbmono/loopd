#!/usr/bin/env bash
#
# subagent-merge-yolo.test.sh — the one merge `AUTONOMY.md` delegates, the ways it is
# still refused, when an external review stands in for the checker table, and the opt-in merge at the review cap: `plugin/hooks/deny-destructive.sh` rule `subagent_merge`, the policy
# it defers to in `plugin/scripts/merge-permit.sh`, and the clearance record
# `plugin/scripts/clearance-receipt.sh` writes and reads.
#
# EVERY CASE ASSERTS THE HOOK'S MACHINE-READABLE DECISION, NEVER ITS PROSE. The hook's own
# exit status is 0 by design — a refusal is JSON on stdout (see its header) — so the
# decision field IS the code here, and `verdict()` maps it to `allow` / `deny:<rule>` and
# to `bad:…` for anything it cannot classify, so an unrecognised answer can never read as
# a pass.
#
# NOTHING HERE MERGES ANYTHING. The hook is a pure function from a PreToolUse payload to a
# decision; no `gh` is installed, invoked or stubbed, and the fixtures are a bundle and a
# repo under `mktemp -d`.
#
# ok() compares actual to expected, in that argument order — this directory's convention.
# Reasoning: ai-bridge-v3/task-044.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO/plugin/hooks/deny-destructive.sh"
RECEIPT="$REPO/plugin/scripts/clearance-receipt.sh"
PERMIT="$REPO/plugin/scripts/merge-permit.sh"
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$REPO/plugin/scripts/bundle-paths.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/mergeyolo.XXXXXX")" || {
  echo "subagent-merge-yolo.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed (the hook requires it)"; exit 0; }
[ -x "$PERMIT" ] && [ -x "$RECEIPT" ] || {
  echo "subagent-merge-yolo.test: merge-permit.sh / clearance-receipt.sh missing or not executable" >&2
  exit 2; }

res() { (cd "$1" 2>/dev/null && pwd -P); }
SHA="a30826d9c0ffee1234567890abcdef0123456789"
OTHER_SHA="cb20f95c11112222333344445555666677778888"
NWO="cbmono/ai-bridge"   # paired with the receipt filename asserted below; a fixture value, not prose
NWO2="example-user-007/widgets"   # a second repo the cwd's origin is NOT, so a URL case can be red
# shellcheck source=tools/plugin-name.sh
. "$REPO/tests/tools/plugin-name.sh"
PM="$PN:project-manager"   # the tick's agent_type, namespaced exactly as Claude Code sends it

# ------------------------------------------------------------------------------ fixtures
# A bundle (the instance root the hook reads from CLAUDE_PROJECT_DIR) and a product-repo
# worktree (the agent's cwd, whose `origin` is what resolves the PR's repository).
mkdir -p "$TMP/home" "$TMP/bundle" "$TMP/work/repo"
FIXHOME="$(res "$TMP/home")"
BUNDLE="$(res "$TMP/bundle")"
GITREPO="$(res "$TMP/work/repo")"
printf '{}\n' > "$BUNDLE/instance.config.json"
git -C "$GITREPO" init -q >/dev/null 2>&1
git -C "$GITREPO" symbolic-ref HEAD refs/heads/main
git -C "$GITREPO" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
git -C "$GITREPO" remote add origin "https://github.com/$NWO.git"

project() { # <slug> <autonomy> <pr-number>
  mkdir -p "$BUNDLE/projects/$1/tasks"
  cat > "$BUNDLE/projects/$1/project.md" <<EOF
---
type: Project
title: "$1"
autonomy: $2
---
EOF
  cat > "$BUNDLE/projects/$1/tasks/task-001.md" <<EOF
---
type: Task
title: "a task"
status: in-review
pr: [ https://github.com/$NWO/pull/$3 ]
---
EOF
}

# The capability file, at the bundle root — resolve-autonomy.sh's "root wins outright"
# branch, so no companion plugin has to be installed for this harness to be about the rule.
autonomy_on() {
  cat > "$BUNDLE/AUTONOMY.md" <<'MD'
# Mode: `yolo`
It delegates both gates.
## Merge under `yolo`
`gh pr merge --squash --match-head-commit <verified-sha> <pr>`
MD
}
autonomy_off() { rm -f "$BUNDLE/AUTONOMY.md"; }

record_all() { # <pr> <sha> [script...] — default: all four
  local pr="$1" sha="$2"; shift 2
  local list="$*" s
  [ -n "$list" ] || list="review-clearance.sh required-checks.sh pr-body-clearance.sh pr-verdict-clearance.sh"
  for s in $list; do
    "$RECEIPT" record "$s" --bundle "$BUNDLE" --repo "$NWO" --pr "$pr" --head "$sha" || return 1
  done
}
forget() { rm -rf "${BUNDLE:?}/$AB_RECEIPTS"; }

# -------------------------------------------------------------------------------- probes
payload() { # <cwd> <command> <agent_type>
  jq -n --arg d "$1" --arg c "$2" --arg t "$3" '{
    session_id: "sess-1", transcript_path: "/tmp/t.jsonl", cwd: $d,
    permission_mode: "bypassPermissions", hook_event_name: "PreToolUse",
    tool_name: "Bash", tool_use_id: "tu-1", tool_input: { command: $c }
  } + (if $t == "" then {} else { agent_id: "agent-xyz", agent_type: $t } end)'
}

verdict() { # <command> <agent_type> -> "allow" | "deny:<rule>" | "bad:<decision>"
  local out dec rule
  out="$(payload "$GITREPO" "$1" "${2:-}" \
         | HOME="$FIXHOME" CLAUDE_PROJECT_DIR="$BUNDLE" bash "$HOOK" 2>/dev/null)"
  [ -n "$out" ] || { printf 'allow'; return 0; }
  dec="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null)"
  [ "$dec" = deny ] || { printf 'bad:%s' "$dec"; return 0; }
  rule="$(head -1 <<<"$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null \
          | sed -n 's/.*rule `\([a-z0-9_]*\)`.*/\1/p')")"
  printf 'deny:%s' "${rule:-UNNAMED}"
}

MERGE="gh pr merge --squash --match-head-commit $SHA 226"

echo "== (a) delegating mode + the four-precondition record at the SAME head ⇒ ALLOWED =="
autonomy_on
project yolo-proj yolo 226
forget; record_all 226 "$SHA"
ok "the tick's own merge command is permitted" "$(verdict "$MERGE" "$PM")" "allow"
# Non-vacuity for the whole file: the permit is the NARROW shape and nothing near it.
ok "…without --match-head-commit it is refused" \
   "$(verdict 'gh pr merge --squash 226' "$PM")" "deny:subagent_merge"
ok "…with --merge instead of --squash"          \
   "$(verdict "gh pr merge --merge --match-head-commit $SHA 226" "$PM")" "deny:subagent_merge"
ok "…a bare gh pr merge"                        "$(verdict 'gh pr merge 226' "$PM")" "deny:subagent_merge"
ok "…and hidden behind an earlier stage it is still read" \
   "$(verdict "gh pr view 226 && $MERGE" "$PM")" "allow"
# The review verbs an agent MUST keep, at the same fixture state.
ok "gh pr create is untouched"        "$(verdict 'gh pr create --fill' software-engineer)" "allow"
ok "gh pr review --request-changes is untouched" \
   "$(verdict 'gh pr review --request-changes -b "needs work" 226' software-engineer)" "allow"

echo
echo "== (b) a gated project is still refused, and the human is still named the merger =="
project gated-proj gated 227
forget; record_all 227 "$SHA"
ok "gated ⇒ refused" "$(verdict "gh pr merge --squash --match-head-commit $SHA 227" "$PM")" "deny:subagent_merge"
REASON="$(payload "$GITREPO" "gh pr merge --squash --match-head-commit $SHA 227" "$PM" \
          | HOME="$FIXHOME" CLAUDE_PROJECT_DIR="$BUNDLE" bash "$HOOK" 2>/dev/null \
          | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')"
ok "…and the refusal names the human as the merger" \
   "$(grep -qF "merge is the human's under \`gated\`" <<<"$REASON" && echo yes || echo no)" yes

echo
echo "== (c) delegating mode, NO receipt ⇒ refused =="
forget
ok "no clearance record ⇒ refused" "$(verdict "$MERGE" "$PM")" "deny:subagent_merge"
echo "== …and a bare review receipt is not a merge permit (g) =="
record_all 226 "$SHA" review-clearance.sh
ok "review-clearance.sh alone ⇒ refused" "$(verdict "$MERGE" "$PM")" "deny:subagent_merge"
record_all 226 "$SHA" required-checks.sh pr-body-clearance.sh
ok "…three of the four ⇒ still refused"  "$(verdict "$MERGE" "$PM")" "deny:subagent_merge"
record_all 226 "$SHA" pr-verdict-clearance.sh
ok "…and the fourth is what permits it"  "$(verdict "$MERGE" "$PM")" "allow"
echo "== …and the role is the tick's, never the worker's (g) =="
ok "a software-engineer with the full record ⇒ refused" \
   "$(verdict "$MERGE" software-engineer)" "deny:subagent_merge"
ok "a qa-reviewer with the full record ⇒ refused" \
   "$(verdict "$MERGE" qa-reviewer)" "deny:subagent_merge"

echo
echo "== (d) the receipt's head must equal --match-head-commit =="
forget; record_all 226 "$OTHER_SHA"
ok "a record at an earlier head ⇒ refused" "$(verdict "$MERGE" "$PM")" "deny:subagent_merge"
ok "…and the merge at THAT head is permitted" \
   "$(verdict "gh pr merge --squash --match-head-commit $OTHER_SHA 226" "$PM")" "allow"
# The file is keyed by head AND says so inside: a rename must not turn one into the other.
mv "$BUNDLE/$AB_RECEIPTS/cbmono-ai-bridge__pr226__$OTHER_SHA" \
   "$BUNDLE/$AB_RECEIPTS/cbmono-ai-bridge__pr226__$SHA" 2>/dev/null
ok "…and a renamed record still names the head it was earned at" \
   "$(verdict "$MERGE" "$PM")" "deny:subagent_merge"

echo
echo "== (e) no AUTONOMY.md ⇒ refused (the companion is not installed) =="
forget; record_all 226 "$SHA"; autonomy_off
ok "capability file absent ⇒ refused" "$(verdict "$MERGE" "$PM")" "deny:subagent_merge"
autonomy_on
ok "…and restoring it is the only thing that changed" "$(verdict "$MERGE" "$PM")" "allow"

echo
echo "== (f) two tasks in differently-moded projects naming the same PR ⇒ refused =="
project gated-twin gated 226
ok "ambiguous PR → project mapping ⇒ refused" "$(verdict "$MERGE" "$PM")" "deny:subagent_merge"
rm -rf "$BUNDLE/projects/gated-twin"
ok "…and it is the ambiguity, not the second project" "$(verdict "$MERGE" "$PM")" "allow"
# A task that merely MENTIONS a PR in its prose owns nothing — only the `pr:` field counts.
mkdir -p "$BUNDLE/projects/gated-twin/tasks"
printf -- '---\ntype: Project\nautonomy: gated\n---\n' > "$BUNDLE/projects/gated-twin/project.md"
printf -- '---\ntype: Task\npr: [ ]\n---\n\n# Context\n\nhttps://github.com/%s/pull/226 merged by hand.\n' \
  "$NWO" > "$BUNDLE/projects/gated-twin/tasks/task-001.md"
ok "…a prose mention is not ownership" "$(verdict "$MERGE" "$PM")" "allow"
rm -rf "$BUNDLE/projects/gated-twin"

echo
echo "== (h) the REST merge endpoint is refused under a delegating mode too =="
ok "gh api PUT pulls/N/merge ⇒ refused" \
   "$(verdict "gh api --method PUT /repos/$NWO/pulls/226/merge -f sha=$SHA" "$PM")" "deny:subagent_merge"
ok "…and from a subagent"                \
   "$(verdict "gh api --method PUT /repos/$NWO/pulls/226/merge" software-engineer)" "deny:subagent_merge"
ok "gh api reading the PR is untouched"  \
   "$(verdict "gh api /repos/$NWO/pulls/226" "$PM")" "allow"

echo
echo "== (i) the role is the namespaced tick, matched exactly =="
ok "the bare project-manager ⇒ refused (a user-level agent of that name is not the tick)" \
   "$(verdict "$MERGE" project-manager)" "deny:subagent_merge"
for r in "evil:project-manager" "$PN:$PN:project-manager" " $PM" "$PM " "$PN: project-manager" \
         "$PN:software-engineer" "$PN:qa-reviewer" "$PN:project-manager-x" "$PN:Project-Manager"; do
  ok "…'$r' ⇒ refused" "$(verdict "$MERGE" "$r")" "deny:subagent_merge"
done
ok "merge-permit.sh itself: --role $PM ⇒ 0" \
   "$("$PERMIT" --bundle "$BUNDLE" --repo "$NWO" --pr 226 --head "$SHA" --role "$PM" >/dev/null 2>&1; echo $?)" 0
ok "…--role project-manager ⇒ 1" \
   "$("$PERMIT" --bundle "$BUNDLE" --repo "$NWO" --pr 226 --head "$SHA" --role project-manager >/dev/null 2>&1; echo $?)" 1

echo
echo "== (j) a PR URL names its own repo; a bare number still takes --repo or the cwd =="
# The cwd's origin is $NWO; this PR lives in $NWO2, so the cwd fallback can never permit it.
mkdir -p "$BUNDLE/projects/url-proj/tasks"
printf -- '---\ntype: Project\ntitle: "url-proj"\nautonomy: yolo\n---\n' > "$BUNDLE/projects/url-proj/project.md"
printf -- '---\ntype: Task\ntitle: "a task"\nstatus: in-review\npr: [ https://github.com/%s/pull/321 ]\n---\n' \
  "$NWO2" > "$BUNDLE/projects/url-proj/tasks/task-001.md"
record_nwo2() { # <sha>
  local s
  for s in review-clearance.sh required-checks.sh pr-body-clearance.sh pr-verdict-clearance.sh; do
    "$RECEIPT" record "$s" --bundle "$BUNDLE" --repo "$NWO2" --pr 321 --head "$1" || return 1
  done
}
URL="https://github.com/$NWO2/pull/321"
UMERGE="gh pr merge --squash --match-head-commit $SHA"
record_nwo2 "$SHA"
ok "a URL operand resolves to the URL's repo, not the cwd's" "$(verdict "$UMERGE $URL" "$PM")" "allow"
ok "…with --repo agreeing"                  "$(verdict "$UMERGE --repo $NWO2 $URL" "$PM")" "allow"
ok "…with --repo disagreeing ⇒ refused"     "$(verdict "$UMERGE --repo $NWO $URL" "$PM")" "deny:subagent_merge"
ok "…with -R disagreeing ⇒ refused"         "$(verdict "$UMERGE -R $NWO $URL" "$PM")" "deny:subagent_merge"
ok "a bare number with --repo takes --repo" "$(verdict "$UMERGE --repo $NWO2 321" "$PM")" "allow"
ok "…and without it, the cwd's origin"      "$(verdict "$UMERGE 321" "$PM")" "deny:subagent_merge"
ok "…which is what clears #226 by number"   "$(verdict "$MERGE" "$PM")" "allow"
# #226 is owned and cleared in $NWO; a URL naming #226 in ANOTHER repo merges that other PR.
ok "a URL to an uncleared repo's #226 is not cleared by \$NWO's #226" \
   "$(verdict "$UMERGE https://github.com/$NWO2/pull/226" "$PM")" "deny:subagent_merge"
for u in "https://example.com/$NWO/pull/226" "http://github.com/$NWO/pull/226" \
         "https://www.github.com/$NWO/pull/226" "github.com/$NWO/pull/226" "$NWO/226" "x/226" \
         "https://github.com/$NWO/pull/226/files" "https://github.com/$NWO/pull/226/" \
         "https://github.com/$NWO/issues/226" "https://github.com/../$NWO/pull/226"; do
  ok "…operand '$u' ⇒ refused" "$(verdict "$UMERGE $u" "$PM")" "deny:subagent_merge"
done
ok "a URL, the wrong role ⇒ refused"        "$(verdict "$UMERGE $URL" "$PN:software-engineer")" "deny:subagent_merge"
ok "a URL, a record at another head ⇒ refused" \
   "$(verdict "gh pr merge --squash --match-head-commit $OTHER_SHA $URL" "$PM")" "deny:subagent_merge"
forget; record_all 226 "$SHA"
ok "a URL, no record ⇒ refused"             "$(verdict "$UMERGE $URL" "$PM")" "deny:subagent_merge"
rm -rf "$BUNDLE/projects/url-proj"

echo
echo "== the check is not subagent-only: the MAIN thread carries no agent_id =="
# task-035's headless tick runs the project-manager in the main thread. A rule keyed on
# `agent_id` would never fire there — no mode check, no receipt, no SHA pin.
ok "main thread, no record ⇒ refused" "$(forget; verdict "$MERGE" '')" "deny:subagent_merge"
record_all 226 "$SHA"
ok "main thread, full record, no role ⇒ still refused" "$(verdict "$MERGE" '')" "deny:subagent_merge"
ok "…while the same command from the tick is permitted" "$(verdict "$MERGE" "$PM")" "allow"
# The approval half stays agent-scoped: an approval is the human's to give in their session.
ok "the human's own session may still approve" "$(verdict 'gh pr review --approve 226' '')" "allow"
ok "…and a dispatched agent may not"           "$(verdict 'gh pr review --approve 226' software-engineer)" "deny:subagent_merge"

echo
echo "== the autonomy field is read from the BUNDLE, never from the target repo =="
# The same yolo project document, planted in the repo the merge is being run from.
mkdir -p "$GITREPO/projects/yolo-proj/tasks"
cp "$BUNDLE/projects/yolo-proj/project.md" "$GITREPO/projects/yolo-proj/project.md"
cp "$BUNDLE/projects/yolo-proj/tasks/task-001.md" "$GITREPO/projects/yolo-proj/tasks/task-001.md"
cp "$BUNDLE/AUTONOMY.md" "$GITREPO/AUTONOMY.md"
printf '{}\n' > "$GITREPO/instance.config.json"
sed -i.bak 's/^autonomy: yolo$/autonomy: gated/' "$BUNDLE/projects/yolo-proj/project.md"
ok "a PR cannot raise its own project's autonomy from the target repo" \
   "$(verdict "$MERGE" "$PM")" "deny:subagent_merge"
sed -i.bak 's/^autonomy: gated$/autonomy: yolo/' "$BUNDLE/projects/yolo-proj/project.md"
ok "…and the bundle's own value is what decides" "$(verdict "$MERGE" "$PM")" "allow"
rm -f "$GITREPO/instance.config.json" "$GITREPO/AUTONOMY.md"

echo
echo "== the record is written by the clearance scripts, and read without network =="
ok "verify is exit 0 for a complete record" \
   "$("$RECEIPT" verify --bundle "$BUNDLE" --repo "$NWO" --pr 226 --head "$SHA" >/dev/null 2>&1; echo $?)" 0
ok "…exit 1 for a PR with none" \
   "$("$RECEIPT" verify --bundle "$BUNDLE" --repo "$NWO" --pr 999 --head "$SHA" >/dev/null 2>&1; echo $?)" 1
ok "…and record outside a bundle writes nothing and fails nobody" \
   "$("$RECEIPT" record review-clearance.sh --bundle "$TMP/work" --repo "$NWO" --pr 226 --head "$SHA" >/dev/null 2>&1; echo $?)" 0
ok "…having created no receipt directory there" \
   "$([ -e "$TMP/work/$AB_RECEIPTS" ] && echo yes || echo no)" no
ok "the four scripts each record their own line" \
   "$(grep -c '^pass ' "$BUNDLE/$AB_RECEIPTS/cbmono-ai-bridge__pr226__$SHA")" 4
for s in review-clearance required-checks pr-body-clearance pr-verdict-clearance; do
  ok "…$s.sh records the receipt on its clearing path" \
     "$(grep -c "record $s.sh" "$REPO/plugin/scripts/$s.sh")" 1
done
ok "the hook never reads the receipt directory itself" \
   "$(grep -c 'tick-receipts' "$HOOK")" 0
ok "…and merge-permit.sh never re-runs a clearance" \
   "$(grep -vE '^[[:space:]]*#' "$PERMIT" | grep -cE '(review-clearance|required-checks|pr-body-clearance|pr-verdict-clearance)\.sh')" 0

echo
echo "== the preflight names the hook as trap three, and probes the real command shape =="
AUTON="$REPO/plugin-yolo/companion/AUTONOMY.md"
DOCS="$REPO/docs/autonomy.md"
ok "AUTONOMY.md's preflight names the hook"        "$(grep -q 'deny-destructive.sh' "$AUTON" && echo yes || echo no)" yes
ok "…and the probe carries the REAL merge command" \
   "$(grep -c 'gh pr merge --squash --match-head-commit' "$AUTON")" 2
ok "…and the hook grows no --probe mode"           "$(grep -c -- '--probe' "$HOOK")" 0
ok "docs/autonomy.md names trap three"             "$(grep -c 'trap three' "$DOCS")" 1

echo
echo "== an EXTERNAL review stands in for the checker table, and nothing else does =="
# The writers run for real against review-clearance.lib.sh's gh stub, in a subshell because
# the lib owns its own TMP, PATH and counters; the tally comes back through a file.
YTALLY="$TMP/external.tally"
(
  # shellcheck source=review-clearance.lib.sh
  . "$REPO/tests/review-clearance.lib.sh"
  export CLAUDE_PROJECT_DIR="$BUNDLE"
  NWO="acme/widgets"; H="$CLEAN_HEAD"
  project ext-proj yolo 42
  RCPT="$("$RECEIPT" path --bundle "$BUNDLE" --repo "$NWO" --pr 42 --head "$H")"
  others() { record_all 42 "$H" required-checks.sh pr-body-clearance.sh; }
  permit() { "$PERMIT" --bundle "$BUNDLE" --repo "$NWO" --pr 42 --head "$H" --role "$PM" \
               >/dev/null 2>&1; echo $?; }
  is() { if [ "$2" = "$3" ]; then assert "$1" 0; else assert "$1 (got $2, want $3)" 1; fi; }
  trailer_body() {
    body_file '<!-- okf-verdict v1' 'verdict: pass' 'reviewer: qa-reviewer' "head_sha: $H" \
      'lenses: correctness=done security=done repro=done' 'unverified_criteria: none' 'caveats: none' '-->'
  }
  checker() { # <PASS|FAIL> — post a checker table from a non-author login, then run the comparison
    local w c; w="$(body_file '## Description' '' 'One sentence.' '' '| Criterion | ✓ | Verified by |' \
      '|---|---|---|' '| the retry backs off | ✓ | `foo.test.sh` 40/0 |')"
    c="$(body_file '| Criterion | Verdict | Evidence |' '|---|---|---|' \
      "| the retry backs off | $1 | \`foo.test.sh\` 40/0 |")"
    "$REAL_JQ" --rawfile b "$w" --rawfile c "$c" \
      '. + {body:$b, comments:[{author:{login:"qa-bot"}, body:$c}]}' "$FIX/pr_json" > "$FIX/pr_json.v" \
      && mv "$FIX/pr_json.v" "$FIX/pr_json"
    "$SCRIPTS/pr-verdict-clearance.sh" 42 >/dev/null 2>&1; echo $?
  }

  forget; setup "$H"; add_review coderabbitai COMMENTED "$H" "$CLEAN"
  expect "route A: a vendor review object at the head clears" 0
  is "…and is recorded external" "$(grep -c '^pass review-clearance.sh .* external$' "$RCPT")" 1
  others
  is "route A external, no pr-verdict pass ⇒ permitted" "$(permit)" 0

  is "…a checker FAIL exits 1" "$(checker FAIL)" 1
  is "…and is recorded as a fail line" "$(grep -c '^fail pr-verdict-clearance.sh ' "$RCPT")" 1
  is "external + a pr-verdict fail line ⇒ refused" "$(permit)" 1
  is "…a later agreeing checker replaces the fail line" "$(checker PASS)" 0
  is "…and the merge is permitted again" "$(permit)" 0
  is "…one pr-verdict line per head" "$(grep -c ' pr-verdict-clearance.sh ' "$RCPT")" 1

  setup "$H"; add_review qa-bot COMMENTED "$H" "$CLEAN"
  expect "an internal mint at the same head clears too" 0 --reviewer qa-bot
  is "…kept beside the external line, not over it" "$(grep -c '^pass review-clearance.sh ' "$RCPT")" 2
  is "internal mint after an external one ⇒ still permitted" "$(permit)" 0

  sed -i.bak 's/^autonomy: yolo$/autonomy: gated/' "$BUNDLE/projects/ext-proj/project.md"
  is "a gated project with a complete external receipt ⇒ refused" "$(permit)" 1
  sed -i.bak 's/^autonomy: gated$/autonomy: yolo/' "$BUNDLE/projects/ext-proj/project.md"

  forget; setup "$H"; add_comment coderabbitai "$CLEAN"
  expect "route C: the vendor's review marker naming the head clears" 0
  is "…and is recorded external" "$(grep -c '^pass review-clearance.sh .* external$' "$RCPT")" 1
  others
  is "route C external, no pr-verdict pass ⇒ permitted" "$(permit)" 0

  forget; setup "$H"; add_comment qa-bot "$(trailer_body)"
  expect "route B: a qa-reviewer trailer clears" 0 --reviewer qa-bot
  is "…and is recorded internal" "$(grep -c '^pass review-clearance.sh .* internal$' "$RCPT")" 1
  others
  is "trailer clearance, no pr-verdict pass ⇒ refused" "$(permit)" 1
  record_all 42 "$H" pr-verdict-clearance.sh
  is "…and its pr-verdict pass is what permits it" "$(permit)" 0

  forget; setup "$H"; add_review qa-bot COMMENTED "$H" "$CLEAN"
  expect "route A from a non-vendor --reviewer account clears" 0 --reviewer qa-bot
  others
  is "a non-vendor --reviewer account, no pr-verdict pass ⇒ refused" "$(permit)" 1

  forget; record_all 42 "$H" review-clearance.sh; others
  is "a kindless (legacy) review line, no pr-verdict pass ⇒ refused" "$(permit)" 1

  # The gate-file refusal, before required-checks.sh asks anything else of the host.
  RB="$TMP/rcbin"; mkdir -p "$RB"
  cat > "$RB/gh" <<STUB
#!/usr/bin/env bash
case "\$1 \$2" in
  "pr view") printf 'https://github.com/$NWO/pull/42\tmain\t$H\n' ;;
  "pr diff") cat "$TMP/rc.diff" ;;
  "pr checks") echo "no required checks reported on the 'topic' branch" >&2; exit 1 ;;
  *) exit 1 ;;
esac
STUB
  chmod +x "$RB/gh"
  rc_exit() { printf '%s\n' "$@" > "$TMP/rc.diff"
              PATH="$RB:$PATH" "$SCRIPTS/required-checks.sh" 42 >/dev/null 2>&1; echo $?; }
  is "a PR editing clearance-receipt.sh ⇒ required-checks.sh exit 4" \
     "$(rc_exit README.md plugin/scripts/clearance-receipt.sh)" 4
  is "…and AUTONOMY.md too" "$(rc_exit plugin-yolo/companion/AUTONOMY.md)" 4
  is "…while an ordinary diff reaches the required-set question (exit 3)" "$(rc_exit README.md)" 3
  is "a PR editing merge-permit.sh ⇒ required-checks.sh exit 4" \
     "$(rc_exit plugin/scripts/merge-permit.sh)" 4
  is "…and plugin-name.sh, which names the merging role" "$(rc_exit plugin/scripts/plugin-name.sh)" 4

  echo "== mergeAtReviewCap: exit 6 at the two-round cap, opt-in, yolo only =="
  THIRD="fedcba9876543210fedcba9876543210fedcba98"
  key() { printf '{"mergeAtReviewCap": %s}\n' "$1" > "$BUNDLE/instance.config.json"; }
  caps() { cat "$RCPT" 2>/dev/null | awk '$1 == "cap" && $2 == "review-clearance.sh" { n++ } END { print n + 0 }'; }
  reviewed_at() { # <sha>... — a vendor review at each, and one vendor thread still open
    local c; setup "$H"
    for c in "$@"; do add_review coderabbitai COMMENTED "$c" "$CLEAN"; done
    add_thread false a.sh 3 coderabbitai https://example.invalid/t/1 'fix this'
  }

  forget; printf '{}\n' > "$BUNDLE/instance.config.json"
  reviewed_at "$OTHER_SHA" "$H"
  expect "key absent: two rounds, threads open at the head ⇒ exit 6" 6
  is "…and no cap line is written" "$(caps)" 0
  record_all 42 "$H" required-checks.sh pr-body-clearance.sh
  is "key absent at the cap ⇒ refused" "$(permit)" 1

  forget; key true; reviewed_at "$OTHER_SHA" "$H"
  expect "key true: the same PR still answers exit 6" 6
  is "…and records one external cap line" "$(grep -c '^cap review-clearance.sh .* external$' "$RCPT")" 1
  is "…and no pass line" "$(grep -c '^pass review-clearance.sh ' "$RCPT")" 0
  others
  is "key true + yolo + cap + exit 6, external, no pr-verdict pass ⇒ permitted" "$(permit)" 0
  key false
  is "…key false ignores the recorded cap line" "$(permit)" 1
  key null
  is "…key null too" "$(permit)" 1
  key '"true"'
  is "…and the string \"true\" too" "$(permit)" 1
  key true
  sed -i.bak 's/^autonomy: yolo$/autonomy: gated/' "$BUNDLE/projects/ext-proj/project.md"
  is "key true + gated + cap line ⇒ refused" "$(permit)" 1
  sed -i.bak 's/^autonomy: gated$/autonomy: yolo/' "$BUNDLE/projects/ext-proj/project.md"
  "$RECEIPT" record pr-verdict-clearance.sh --fail --bundle "$BUNDLE" --repo "$NWO" --pr 42 --head "$H"
  is "an external cap line + a pr-verdict fail line ⇒ refused" "$(permit)" 1

  forget; reviewed_at "$OTHER_SHA" "$THIRD"
  expect "key true, two rounds on earlier heads, none at this one ⇒ exit 4" 4
  is "…writes no cap line" "$(caps)" 0
  others
  is "key true + yolo + cap + exit 4 ⇒ refused" "$(permit)" 1

  forget; reviewed_at "$OTHER_SHA" "$H"; MERGEABLE=CONFLICTING; MERGE_STATE=DIRTY
  expect "key true, at the cap, the PR conflicts ⇒ exit 7" 7
  is "…writes no cap line" "$(caps)" 0
  others
  is "key true + yolo + cap + exit 7 ⇒ refused" "$(permit)" 1

  forget; reviewed_at "$H"
  expect "key true, one round, threads open ⇒ exit 6" 6
  is "…below the cap writes no cap line" "$(caps)" 0
  others
  is "key true + yolo below the cap ⇒ refused" "$(permit)" 1

  forget
  "$RECEIPT" record review-clearance.sh --cap --kind internal --bundle "$BUNDLE" --repo "$NWO" --pr 42 --head "$H"
  others
  is "an internal cap line, no pr-verdict pass ⇒ refused" "$(permit)" 1
  record_all 42 "$H" pr-verdict-clearance.sh
  is "…and its pr-verdict pass is what permits it" "$(permit)" 0
  forget; key false
  "$RECEIPT" record review-clearance.sh --cap --kind external --bundle "$BUNDLE" --repo "$NWO" --pr 42 --head "$H"
  is "record --cap with the key off writes nothing" "$(caps)" 0
  printf '{}\n' > "$BUNDLE/instance.config.json"
  printf '%s %s\n' "$pass" "$fail" > "$YTALLY"
)
read -r ypass yfail < "$YTALLY" 2>/dev/null || { ypass=0; yfail=1; }
pass=$((pass + ypass)); fail=$((fail + yfail))

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
