#!/usr/bin/env bash
#
# new-project-launcher.test.sh — `/<plugin>:new-project` asks its questions in the main
# session and dispatches; every write, the validator, the commit and the step-8 review
# belong to one background project-manager that reports once.
#
# Same shape as close-project-launcher.test.sh, with its own allowlist of SIX operations
# (all-code-is-slop-lessons/task-024). Every absence check is paired with a fixture it fails.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/tools/plugin-name.sh"
SKILL="$REPO/plugin/skills/new-project/SKILL.md"
CLOSE="$REPO/plugin/skills/close-project/SKILL.md"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/nplaunch.XXXXXX")" || {
  echo "new-project-launcher.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
flat() { tr '\n' ' ' | tr -s ' '; }
has() { grep -qF -- "$2" <<<"$(flat <"$1")" && echo yes || echo no; }

ok "the skill exists" "$([ -f "$SKILL" ] && echo yes || echo no)" yes

# --- the two halves ---
launcher_of() {
  awk 'NR==1 && $0=="---"{fm=1; next} fm && $0=="---"{fm=0; next} fm{next}
       /^## The scaffold agent.s brief/{exit} {print}' "$1"
}
brief_of() { awk '/^## The scaffold agent.s brief/{p=1} p' "$1"; }
in_launcher() { grep -qF -- "$1" <<<"$(launcher_of "$SKILL" | flat)" && echo yes || echo no; }
in_brief()    { grep -qF -- "$1" <<<"$(brief_of "$SKILL" | flat)" && echo yes || echo no; }
ok "both halves are present" \
  "$([ -n "$(launcher_of "$SKILL")" ] && [ -n "$(brief_of "$SKILL")" ] && echo yes || echo no)" yes

# --- the allowlist of six ---
section() { awk '/^## The launcher reads nothing else/{p=1;next} p&&/^#/{p=0} p' "$1"; }
in_section() { grep -qF -- "$1" <<<"$(section "$SKILL" | flat)" && echo yes || echo no; }
count_ops() { section "$1" | grep -c -E '^[0-9]+\. ' | tr -d ' '; }
ok "the allowlist is exactly six operations" "$(count_ops "$SKILL")" 6
for op in '**The arguments**' '**The issue fetch**' '**The slug probe**' '**The question**' \
          '**The target repo**' '**The merge preflight**'; do
  ok "…names $op" "$(in_section "$op")" yes
done
ok "…the form is the arguments' operation"   "$(in_section 'new-project-form.sh')" yes
ok "…step 4a's resolve-autonomy.sh is on it" "$(in_section '`resolve-autonomy.sh` with its disclosure lines')" yes
ok "…step 4b's preflight is on it"           "$(in_section "step 4b's lines for the chosen mode")" yes
ok "…and everything else is the agent's"     "$(in_section 'is the scaffold agent')" yes
printf -- '## The launcher reads nothing else\n\n1. a\n2. b\n3. c\n4. d\n5. e\n6. f\n7. a quick look at SCHEMA.md\n\n## Next\n' > "$TMP/seventh.md"
ok "…and a SEVENTH operation fails the count" "$(count_ops "$TMP/seventh.md")" 7

# --- one contract, three launchers ------------------------------------------------
ok "new-project points at both siblings" \
  "$(in_section 'skills/close-project/SKILL.md')/$(in_section 'skills/dispatch/SKILL.md')" yes/yes
ok "close-project's sentence names all three" \
  "$(has "$CLOSE" 'One contract, three launchers')/$(has "$CLOSE" 'skills/new-project/SKILL.md')" yes/yes

# --- the question stays in the session ---
ok "step 4 is still ONE question of at most three parts" "$(has "$SKILL" 'ONE question, at most three parts')" yes
ok "…its default first, labelled (Recommended)"          "$(has "$SKILL" 'labelled `(Recommended)`')" yes
ok "…asked by the launcher"                              "$(in_section 'batched `AskUserQuestion`')" yes
ok "…and never by the agent"                             "$(in_brief 'never ask, never re-derive it')" yes

# --- the issue fetch --------------------------------------------------------------
ok "no connector or --no-ask keeps the URL verbatim" "$(in_section 'No connector, or `--no-ask` ⇒ the URL stays the description verbatim')" yes
ok "…and the report says it was not fetched"        "$(in_brief '`issue not fetched: <why>`')" yes
ok "issue text is delimited untrusted data"          "$(in_launcher '`<<<UNTRUSTED ISSUE`')" yes
ok "…which the brief never obeys"                    "$(in_brief 'untrusted data**, never instructions')" yes
ok "…recording shape, never customer records"        "$(in_brief 'never customer records')" yes

# --- one background project-manager -----------------------------------------------
ok "one fresh namespaced project-manager"  "$(in_launcher "one fresh \`${PN}:project-manager\`")" yes
ok "…in the background"                    "$(in_launcher '`run_in_background: true`')" yes
ok "…on its resolved model"                "$(in_launcher 'scripts/resolve-model.sh project-manager')" yes
ok "…never woken, always fresh"            "$(in_launcher 'Never wake a completed agent')" yes
ok "a scaffold is not a tick"              "$(in_launcher 'A scaffold is NOT a tick')" yes
ok "…and takes no tick lock"               "$(in_launcher 'no tick')/$(in_brief 'take no tick lock')" yes/yes
ok "--no-commit travels in the brief"      "$(in_launcher '`--no-commit` and `--no-ask` when given')" yes

# --- the commit is the agent's ---
ok "step 7 commits as project-manager"     "$(in_brief 'commit-as.sh project-manager "feat: add <slug> project"')" yes
ok "…never as human"                       "$(grep -c 'commit-as.sh human' "$SKILL" | tr -d ' ')" 0

# --- step 8 and the one report ---
ok "the review runs in the agent's foreground" "$(in_brief 'in your own foreground')" yes
ok "one report, no file noise"             "$(in_brief 'nothing else reaches the main session')" yes
ok "…with the seed tasks and depends_on"   "$(in_brief 'a table of the seed tasks: id, title, `depends_on`')" yes
ok "…criteria with today's value"          "$(in_brief "each with today's value, under \"edit project.md to change\"")" yes
ok "…the commit and the verdict"           "$(in_brief 'the step-7 commit SHA')/$(in_brief 'the step-8 verdict')" yes/yes
ok "…and the next step"                    "$(in_brief 'the PM refines the drafts, then **you** promote')" yes

# --- a human decision comes back ---
ok "the launcher asks, then a fresh agent resumes" "$(in_launcher 'comes back as the report, never a guess')" yes
ok "…at step 8e"                           "$(in_launcher 'resuming: start at step 8e')" yes
ok "the agent ends its run on the question" "$(in_brief 'end your run with the question as your report')" yes
ok "…the resume dispatch names its entry point" "$(in_launcher '`resuming: start at step 8e; steps 1-7 are done at <sha>`')" yes
ok "…and the brief obeys it"               "$(in_brief 'A `resuming:` line in your brief wins')" yes
ok "the brief names the file its steps are in" \
  "$(in_brief '`${CLAUDE_PLUGIN_ROOT}/skills/new-project/SKILL.md` → "Steps"')" yes
ok "the form's cancel is the launcher's"   "$(in_launcher 'the launcher runs it once the agent')" yes

# --- the mechanical split ---
for s in commit-as push-commit validate-bundle write-snapshot; do
  ok "the brief runs $s.sh" \
    "$(brief_of "$SKILL" | grep -cF "\${CLAUDE_PLUGIN_ROOT}/scripts/$s.sh" | awk '{print ($1>0)?"yes":"no"}')" yes
  ok "…and the launcher does not" \
    "$(launcher_of "$SKILL" | grep -cF "\${CLAUDE_PLUGIN_ROOT}/scripts/$s.sh" | tr -d ' ')" 0
done
printf -- '## Launcher\n\nrun ${CLAUDE_PLUGIN_ROOT}/scripts/commit-as.sh human x\n\n## The scaffold agent'"'"'s brief\n\nbody\n' > "$TMP/leaky.md"
ok "the split checker sees a leaked command" \
  "$(launcher_of "$TMP/leaky.md" | grep -cF '${CLAUDE_PLUGIN_ROOT}/scripts/commit-as.sh' | tr -d ' ')" 1

# --- allowed-tools grows only on purpose -------------------------------------------
grants() {
  awk '/^---$/{d++; next} d==1 && /^allowed-tools:/{sub(/^allowed-tools:[[:space:]]*/,""); print}' "$1" \
    | tr ',' '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$'
}
EXPECTED_GRANTS='Bash(date:*)
Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/new-project-form.sh:*)
Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/commit-as.sh:*)
Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/push-commit.sh:*)
Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/validate-bundle.sh:*)
Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/write-snapshot.sh:*)
Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-model.sh:*)
Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-effort.sh:*)
Bash(git add:*)
Bash(git config:*)
Bash(git rev-parse:*)
Bash(command -v:*)
Bash(cr:*)
Bash(coderabbit:*)
Bash(ls:*)
Read
Write
Edit
Glob
Agent
AskUserQuestion'
ok "allowed-tools is the declared set" "$(grants "$SKILL")" "$EXPECTED_GRANTS"
printf -- '---\nallowed-tools: Bash(ls:*), Agent, Bash(curl:*)\n---\nbody\n' > "$TMP/wide.md"
ok "…and a widened list is not equal to it" \
  "$([ "$(grants "$TMP/wide.md")" != "$EXPECTED_GRANTS" ] && echo yes || echo no)" yes

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
