#!/usr/bin/env bash
#
# seed-promoted-rules.test.sh — the three rules four stamped bundles had each written by
# hand now ship in the seed, and each one stays in the file that OWNS it.
#
# WHY THIS EXISTS. A 2026-09-08 sweep of four bundles found the same rules hand-written in
# individual CLAUDE.md files, one of them (`.scratch/`) surviving in no live doc at all.
# Promotion is only half the fix: a rule in the seed with nothing reading it is deleted by
# the next person tightening the file, and nobody learns it went. So each rule is asserted
# WITH ITS SECTION — a rule that survives as a sentence somewhere else in the file has
# stopped being where its reader looks.
#
# Rule 3 of the original four (`maxOpenPrs`) was NOT promoted and must not appear: the key
# was never the owner's policy, it traces to one session's self-imposed dispatch throttle,
# and it ships no reader. Section 4 keeps it out.
#
# Rule 4 has a second half that is not prose — `prune-worktrees.sh` has to RECOGNISE the
# directory the rule names, or a bundle that obeys the rule gets worktrees held forever by
# their own scratch dir. That half is exercised, not grepped.
#
# The path itself moved on 2026-09-09 (`.scratch/` -> `tmp/`): the old one is TRACKED in this
# repo. `scratch-path-is-ignored.test.sh` owns that invariant; this file pins the wording.
#
# Matching is done on a NEWLINE-SQUEEZED copy of each document, so a phrase that reflows
# across a line break still matches and a re-wrap does not turn this red for no change.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SEED="$REPO/plugin/seed/CLAUDE.md"
# The rule moved verbatim to the product-repo detail of CONVENTIONS.md (leaner-prompts/task-002).
CONV="$REPO/plugin/seed/conventions/repos.md"
PRUNE="$REPO/plugin/scripts/prune-worktrees.sh"
EVALS_DIR="$REPO/plugin/evals"
EVALS_README="$REPO/plugin/evals/README.md"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/seed-promoted-rules.XXXXXX")" || {
  echo "seed-promoted-rules.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

for f in "$SEED" "$CONV" "$PRUNE"; do
  [ -f "$f" ] || { echo "seed-promoted-rules.test: $f not found" >&2; exit 2; }
done

# One line, single-spaced: phrase matching survives a re-wrap.
flatten() { tr '\n' ' ' | tr -s ' '; }

# Here-string, never a pipe: `grep -q` exits early and under `pipefail` a pipe into it
# reports a MATCH as a failure (grep-q-under-pipefail-reports-a-match-as-a-failure).
saw() { # <haystack> <fixed string> -> yes|no
  grep -qF -- "$2" <<<"$1" && echo yes || echo no
}

# A `## ` section's body, flattened. POSITION, not presence: the whole point of promoting a
# rule is that it sits where its reader is already looking.
section() { # <file> <heading> -> flattened body
  awk -v h="$2" 'index($0, h) == 1 { insec=1; next }
                 insec && /^## / { insec=0 }
                 insec' "$1" | flatten
}

# One top-level bullet, from its marker to the line before the next `- `.
bullet() { # <file> <marker> -> flattened bullet
  awk -v m="$2" 'index($0, m) && /^- / { inb=1; print; next }
                 inb && /^- /          { inb=0 }
                 inb' "$1" | flatten
}

# Delete every line from <from> through the line before <to>, so a mutation arm can ask the
# identical question of a document with the rule taken out.
strip_range() { # <file> <from> <to>
  awk -v a="$2" -v b="$3" 'index($0, a) && !skip { skip=1 }
                           skip && index($0, b)  { skip=0 }
                           !skip                 { print }' "$1"
}

R1='**Never manufacture a decision out of a side effect that isn'"'"'t live yet.**'
R1TODAY='Establish the condition exists **today** before you raise it.'
R1NOTES='A deferred one-line mitigation goes on the task'"'"'s `# Notes` — never into a three-option architecture question'
R1PREBUILD='record "do NOT pre-build X", so a later session doesn'"'"'t resurrect it'

R2='**Generic browser labels are a Claude Code defect, not a misconfiguration.**'
R2ALL='send a connection request to **all** the open browsers and let the human pick'
R2NEVER='Never refuse the work first, and never advise renaming browsers.'

R4='**Scratch files go in `<worktree>/tmp/`, never a shared scratchpad.**'
R4WHY='Mutation scripts, probe output and throwaway configs collide when several agents run at once.'
R4VERIFIED='verified working with three concurrent agents on one tick'
R4PRUNE='`prune-worktrees.sh` recognises `tmp` as scaffolding'
R4IGNORED='**A scratch path that the repo does not IGNORE is not scratch.**'

# =======================================================================================
echo "== 1. rule 1 lives in seed/CLAUDE.md § Ad-hoc requests, where the main thread reads it =="
# =======================================================================================
ADHOC="$(section "$SEED" '## Ad-hoc requests vs. the project loop')"
ok "the section still exists"              "$([ -n "$ADHOC" ] && echo yes || echo no)" yes
ok "the rule is stated there"              "$(saw "$ADHOC" "$R1")" yes
ok "…the condition must be live TODAY"     "$(saw "$ADHOC" "$R1TODAY")" yes
ok "…the mitigation goes on \`# Notes\`, not into an options question" \
                                           "$(saw "$ADHOC" "$R1NOTES")" yes
ok "…and 'do NOT pre-build X' is recorded" "$(saw "$ADHOC" "$R1PREBUILD")" yes
# The originating organisation's own illustrative example is dropped in promotion: the seed
# carries the rule, never that bundle's sandbox canary.
ok "…with no borrowed example carried over" "$(saw "$ADHOC" 'sandbox canary')" no

# Rule 1's effect a grep cannot see, so it used to ship an eval case too. That case was
# RETIRED 2026-09-13 (ai-bridge-v3/task-033): it graded seed prose an eval scaffold never
# puts in front of the model, so it measured the missing bundle and read as a plugin defect.
# The prose above is now its only reader, which is exactly why this section asserts the rule
# WITH ITS SECTION rather than as a sentence — and the retirement stays written down, so the
# case is not quietly re-added in the same shape.
# Asked of the evals DIRECTORY and a bare case name, never as a root-rooted path to the
# case: harness-read-paths.test.sh proves such a path and fails it for not resolving, which
# is right for every harness but one asserting a deliberate ABSENCE.
ok "rule 1's eval case is retired, not silently dropped" \
   "$(ls "$EVALS_DIR" | grep -cx 'dormant-side-effect-is-not-a-decision' | tr -d ' ')" 0
ok "…and the eval README says why it went" \
   "$(grep -c 'dormant-side-effect-is-not-a-decision' "$EVALS_README" | tr -d ' ')" 1

# NON-VACUITY: the same question, of a seed with the rule removed, must answer no.
strip_range "$SEED" "$R1" '**Ad-hoc batches:**' > "$TMP/seed-no-r1.md"
ok "…and the identical check FAILS on a seed with rule 1 deleted" \
   "$(saw "$(section "$TMP/seed-no-r1.md" '## Ad-hoc requests vs. the project loop')" "$R1")" no

# =======================================================================================
echo "== 2. rule 2 lives on seed/CLAUDE.md's browser line, not in SCHEMA.md =="
# =======================================================================================
INV="$(section "$SEED" '## Conventions for role agents working in target repos')"
ok "the browser rule is stated in the seed's invariants" "$(saw "$INV" "$R2")" yes
ok "…all the open browsers are asked, the human picks"   "$(saw "$INV" "$R2ALL")" yes
ok "…never refuse first, never advise renaming"          "$(saw "$INV" "$R2NEVER")" yes
ok "…and it names the tool that returns the labels"      "$(saw "$INV" 'list_connected_browsers')" yes
# THE BARE SPELLING IS LOAD-BEARING. A backticked `mcp__claude-in-chrome__…` here is a tool
# MENTION, and tests/agent-tool-allowlist.test.sh audits every one in this file against the
# intersection of its readers' allowlists — so the full name would break the pinned browser
# budget rather than document it.
ok "…spelled bare, so it is not a tool mention" \
   "$(grep -c 'mcp__claude-in-chrome' "$SEED" | tr -d ' ')" 0
# One home, never two: SCHEMA.md § Browser access addresses background agents that INHERIT a
# connection and never pair, so the same rule written there as well is the drift this guards.
ok "…and SCHEMA.md was not given a second copy" \
   "$(grep -c 'list_connected_browsers' "$REPO/plugin/seed/SCHEMA.md" | tr -d ' ')" 0

strip_range "$SEED" "$R2" '## Knowledge base' > "$TMP/seed-no-r2.md"
ok "…and the identical check FAILS on a seed with rule 2 deleted" \
   "$(saw "$(section "$TMP/seed-no-r2.md" '## Conventions for role agents working in target repos')" "$R2")" no

# =======================================================================================
echo "== 3. rule 4 lives in seed/CONVENTIONS.md § Parallel-safety, with its recognition =="
# =======================================================================================
PS="$(bullet "$CONV" '**Parallel-safety:**')"
ok "the Parallel-safety bullet still exists" "$([ -n "$PS" ] && echo yes || echo no)" yes
ok "scratch goes in the worktree's own tmp/" "$(saw "$PS" "$R4")" yes
ok "…and the path must be git-ignored, not merely private" "$(saw "$PS" "$R4IGNORED")" yes
ok "…and says what collides"                 "$(saw "$PS" "$R4WHY")" yes
ok "…and keeps the evidence it was verified on" "$(saw "$PS" "$R4VERIFIED")" yes
ok "…and points at the recognition that makes it free" "$(saw "$PS" "$R4PRUNE")" yes

strip_range "$CONV" "$R4" '- **Browser (only if the project opts in)' > "$TMP/conv-no-r4.md"
ok "…and the identical check FAILS on a CONVENTIONS with rule 4 deleted" \
   "$(saw "$(bullet "$TMP/conv-no-r4.md" '**Parallel-safety:**')" "$R4")" no

# The half that is not prose, EXERCISED rather than grepped: `is_scaffolding` is lifted out
# of the script and called, because a case arm that is present but unreachable classifies
# nothing while reading as shipped.
sed -n '/^is_scaffolding() {/,/^}/p' "$PRUNE" > "$TMP/is_scaffolding.sh"
ok "is_scaffolding() was extractable from the script" \
   "$([ -s "$TMP/is_scaffolding.sh" ] && echo yes || echo no)" yes
# shellcheck disable=SC1091  # the extract above, written this run
. "$TMP/is_scaffolding.sh"
ok "…and it recognises the untracked tmp/ git reports" \
   "$(is_scaffolding 'tmp/' && echo yes || echo no)" yes
# Bundles stamped before 2026-09-09 still send scratch to .scratch/; the arm stays for them.
ok "…and still recognises the .scratch/ older bundles write" \
   "$(is_scaffolding '.scratch/' && echo yes || echo no)" yes
ok "…and a plain untracked file is still WORK" \
   "$(is_scaffolding 'notes.md' && echo yes || echo no)" no

# =======================================================================================
echo "== 4. the fourth rule of the sweep was NOT promoted, and stays unpromoted =="
# =======================================================================================
# `maxOpenPrs` came out of one session's self-imposed dispatch throttle in one bundle, never
# from the owner, and it ships no reader — a config key nothing counts against is the very
# defect this project is filing elsewhere. It is asserted absent so a later sweep re-reading
# the same four bundles does not promote it a second time.
ok "no maxOpenPrs key reached normalise-config.sh" \
   "$(grep -c 'maxOpenPrs' "$REPO/plugin/scripts/normalise-config.sh" | tr -d ' ')" 0
ok "…nor the seed config"     "$(grep -c 'maxOpenPrs' "$REPO/plugin/seed/instance.config.json" | tr -d ' ')" 0
ok "…nor the seed's SCHEMA"   "$(grep -c 'maxOpenPrs' "$REPO/plugin/seed/SCHEMA.md" | tr -d ' ')" 0

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
