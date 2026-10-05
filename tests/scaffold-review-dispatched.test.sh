#!/usr/bin/env bash
#
# scaffold-review-dispatched.test.sh — `/new-project` step 8 stage 2 (the external-reviewer
# CLI run) no longer instructs the main session to wait on it.
#
# WHY. Step 8 stage 2 used to read "Run it scoped to the new project and wait for it (a
# review takes ~1-2 min; run it synchronously...)" — the one place in the create-a-project
# flow where the main session sat idle (ai-bridge-v5/task-032). This pins the fix: stage 2's
# own block dispatches the review (`run_in_background: true`) instead of blocking on it.
#
# NON-VACUOUS BY CONSTRUCTION. A check that only ever sees the post-fix wording proves
# nothing — it would pass identically on a file that had never been fixed. So this harness
# runs the SAME extraction + check logic on two inputs: the real, current stage-2 block
# (expected PASS) and a fixture holding the ORIGINAL blocking wording verbatim (expected
# FAIL). Restoring the blocking sentence to the real file reproduces the fixture and turns
# this harness RED, which is the mutation check the task's acceptance criteria ask for.
#
# WHAT IS NOT TOUCHED. Step 8 stage 1 (`validate-bundle.sh`) and stage 3 (the `qa-reviewer`
# fallback, letter e) are out of scope for task-032 — task-033 owns stage 3's own wording —
# so this harness only ever looks at the stage-2 block (between the file's second "**b."
# marker and its one "**c." marker), never at the file as a whole.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CMD="$REPO/plugin/skills/new-project/SKILL.md"
[ -f "$CMD" ] || { echo "scaffold-review-dispatched.test: missing $CMD" >&2; exit 2; }

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

# Extract step 8's stage-2 block: from the SECOND "**b." marker in the file (the first is
# step 4's "**b. Kind-specific fields.") up to (not including) the one "**c." marker.
extract_stage2() {
  awk '
    /^[[:space:]]*\*\*b\./ { c++ }
    c==2 && /^[[:space:]]*\*\*c\./ { exit }
    c>=2 { print }
  ' "$1"
}

# The check under test: PASS (0) means the block dispatches instead of blocking.
# FAIL (1) means it still tells the reader to wait, or never says how the dispatch happens.
check_dispatches_not_waits() {
  local block="$1"
  # "and wait for it" is the original blocking phrase verbatim — matched narrowly so a
  # negated form ("don't wait for it", the fixed wording) does not self-trip the check.
  grep -qi 'and wait for it' <<<"$block"      && return 1
  grep -qi 'run it synchronously' <<<"$block" && return 1
  grep -q  'run_in_background' <<<"$block"    || return 1
  return 0
}

# --- Case 1: the real, current file ---------------------------------------------------
real_block="$(extract_stage2 "$CMD")"
ok "stage-2 block was found in the real file" "$([ -n "$real_block" ] && echo yes || echo no)" yes

if check_dispatches_not_waits "$real_block"; then real_verdict=pass; else real_verdict=fail; fi
ok "real file: stage 2 dispatches, does not wait" "$real_verdict" pass

# --- Case 2: a fixture holding the ORIGINAL, pre-fix wording (non-vacuity) ------------
TMP="$(mktemp -d "${TMPDIR:-/tmp}/scaffold-review-dispatched.XXXXXX")" || {
  echo "scaffold-review-dispatched.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2
  exit 2
}
trap 'rm -rf "$TMP"' EXIT

fixture="$TMP/new-project.md"
cat > "$fixture" <<'EOF'
   **a. Capabilities (flags-first, else ask).** placeholder so extract_stage2's counter
   sees a first "**b." marker before this one.

   **b. Kind-specific fields.** placeholder.

   **a. Gate on applicability, then run stage 1.** placeholder.

   **b. Run it scoped to the new project and wait for it** (a review takes ~1–2 min; run it
   synchronously and capture stdout — the triage in step c reads that output). Use the `<cli>`
   resolved in step a in place of `cr` below:

   ```bash
   cr review --agent --committed --base-commit <sha-from-step-7> \
             --dir <instance-root>/projects/<slug> -c CLAUDE.md SCHEMA.md
   ```

   **c. Triage before applying.** placeholder.
EOF

bad_block="$(extract_stage2 "$fixture")"
ok "fixture: stage-2 block was found" "$([ -n "$bad_block" ] && echo yes || echo no)" yes

if check_dispatches_not_waits "$bad_block"; then bad_verdict=pass; else bad_verdict=fail; fi
ok "fixture (pre-fix wording): check goes RED" "$bad_verdict" fail

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
