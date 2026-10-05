#!/usr/bin/env bash
#
# subagent-merge-yolo.test.sh — the one merge `AUTONOMY.md` delegates, and the eight ways
# it is still refused: `plugin/hooks/deny-destructive.sh` rule `subagent_merge`, the policy
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
ok "the tick's own merge command is permitted" "$(verdict "$MERGE" project-manager)" "allow"
# Non-vacuity for the whole file: the permit is the NARROW shape and nothing near it.
ok "…without --match-head-commit it is refused" \
   "$(verdict 'gh pr merge --squash 226' project-manager)" "deny:subagent_merge"
ok "…with --merge instead of --squash"          \
   "$(verdict "gh pr merge --merge --match-head-commit $SHA 226" project-manager)" "deny:subagent_merge"
ok "…a bare gh pr merge"                        "$(verdict 'gh pr merge 226' project-manager)" "deny:subagent_merge"
ok "…and hidden behind an earlier stage it is still read" \
   "$(verdict "gh pr view 226 && $MERGE" project-manager)" "allow"
# The review verbs an agent MUST keep, at the same fixture state.
ok "gh pr create is untouched"        "$(verdict 'gh pr create --fill' software-engineer)" "allow"
ok "gh pr review --request-changes is untouched" \
   "$(verdict 'gh pr review --request-changes -b "needs work" 226' software-engineer)" "allow"

echo
echo "== (b) a gated project is still refused, and the human is still named the merger =="
project gated-proj gated 227
forget; record_all 227 "$SHA"
ok "gated ⇒ refused" "$(verdict "gh pr merge --squash --match-head-commit $SHA 227" project-manager)" "deny:subagent_merge"
REASON="$(payload "$GITREPO" "gh pr merge --squash --match-head-commit $SHA 227" project-manager \
          | HOME="$FIXHOME" CLAUDE_PROJECT_DIR="$BUNDLE" bash "$HOOK" 2>/dev/null \
          | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')"
ok "…and the refusal names the human as the merger" \
   "$(grep -qF "merge is the human's under \`gated\`" <<<"$REASON" && echo yes || echo no)" yes

echo
echo "== (c) delegating mode, NO receipt ⇒ refused =="
forget
ok "no clearance record ⇒ refused" "$(verdict "$MERGE" project-manager)" "deny:subagent_merge"
echo "== …and a bare review receipt is not a merge permit (g) =="
record_all 226 "$SHA" review-clearance.sh
ok "review-clearance.sh alone ⇒ refused" "$(verdict "$MERGE" project-manager)" "deny:subagent_merge"
record_all 226 "$SHA" required-checks.sh pr-body-clearance.sh
ok "…three of the four ⇒ still refused"  "$(verdict "$MERGE" project-manager)" "deny:subagent_merge"
record_all 226 "$SHA" pr-verdict-clearance.sh
ok "…and the fourth is what permits it"  "$(verdict "$MERGE" project-manager)" "allow"
echo "== …and the role is the tick's, never the worker's (g) =="
ok "a software-engineer with the full record ⇒ refused" \
   "$(verdict "$MERGE" software-engineer)" "deny:subagent_merge"
ok "a qa-reviewer with the full record ⇒ refused" \
   "$(verdict "$MERGE" qa-reviewer)" "deny:subagent_merge"

echo
echo "== (d) the receipt's head must equal --match-head-commit =="
forget; record_all 226 "$OTHER_SHA"
ok "a record at an earlier head ⇒ refused" "$(verdict "$MERGE" project-manager)" "deny:subagent_merge"
ok "…and the merge at THAT head is permitted" \
   "$(verdict "gh pr merge --squash --match-head-commit $OTHER_SHA 226" project-manager)" "allow"
# The file is keyed by head AND says so inside: a rename must not turn one into the other.
mv "$BUNDLE/$AB_RECEIPTS/cbmono-ai-bridge__pr226__$OTHER_SHA" \
   "$BUNDLE/$AB_RECEIPTS/cbmono-ai-bridge__pr226__$SHA" 2>/dev/null
ok "…and a renamed record still names the head it was earned at" \
   "$(verdict "$MERGE" project-manager)" "deny:subagent_merge"

echo
echo "== (e) no AUTONOMY.md ⇒ refused (the companion is not installed) =="
forget; record_all 226 "$SHA"; autonomy_off
ok "capability file absent ⇒ refused" "$(verdict "$MERGE" project-manager)" "deny:subagent_merge"
autonomy_on
ok "…and restoring it is the only thing that changed" "$(verdict "$MERGE" project-manager)" "allow"

echo
echo "== (f) two tasks in differently-moded projects naming the same PR ⇒ refused =="
project gated-twin gated 226
ok "ambiguous PR → project mapping ⇒ refused" "$(verdict "$MERGE" project-manager)" "deny:subagent_merge"
rm -rf "$BUNDLE/projects/gated-twin"
ok "…and it is the ambiguity, not the second project" "$(verdict "$MERGE" project-manager)" "allow"
# A task that merely MENTIONS a PR in its prose owns nothing — only the `pr:` field counts.
mkdir -p "$BUNDLE/projects/gated-twin/tasks"
printf -- '---\ntype: Project\nautonomy: gated\n---\n' > "$BUNDLE/projects/gated-twin/project.md"
printf -- '---\ntype: Task\npr: [ ]\n---\n\n# Context\n\nhttps://github.com/%s/pull/226 merged by hand.\n' \
  "$NWO" > "$BUNDLE/projects/gated-twin/tasks/task-001.md"
ok "…a prose mention is not ownership" "$(verdict "$MERGE" project-manager)" "allow"
rm -rf "$BUNDLE/projects/gated-twin"

echo
echo "== (h) the REST merge endpoint is refused under a delegating mode too =="
ok "gh api PUT pulls/N/merge ⇒ refused" \
   "$(verdict "gh api --method PUT /repos/$NWO/pulls/226/merge -f sha=$SHA" project-manager)" "deny:subagent_merge"
ok "…and from a subagent"                \
   "$(verdict "gh api --method PUT /repos/$NWO/pulls/226/merge" software-engineer)" "deny:subagent_merge"
ok "gh api reading the PR is untouched"  \
   "$(verdict "gh api /repos/$NWO/pulls/226" project-manager)" "allow"

echo
echo "== the check is not subagent-only: the MAIN thread carries no agent_id =="
# task-035's headless tick runs the project-manager in the main thread. A rule keyed on
# `agent_id` would never fire there — no mode check, no receipt, no SHA pin.
ok "main thread, no record ⇒ refused" "$(forget; verdict "$MERGE" '')" "deny:subagent_merge"
record_all 226 "$SHA"
ok "main thread, full record, no role ⇒ still refused" "$(verdict "$MERGE" '')" "deny:subagent_merge"
ok "…while the same command from the tick is permitted" "$(verdict "$MERGE" project-manager)" "allow"
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
   "$(verdict "$MERGE" project-manager)" "deny:subagent_merge"
sed -i.bak 's/^autonomy: gated$/autonomy: yolo/' "$BUNDLE/projects/yolo-proj/project.md"
ok "…and the bundle's own value is what decides" "$(verdict "$MERGE" project-manager)" "allow"
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
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
