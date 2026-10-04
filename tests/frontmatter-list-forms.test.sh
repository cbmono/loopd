#!/usr/bin/env bash
# frontmatter-list-forms.test.sh — ONE logical bundle, written once with flow lists and once
# with SCHEMA.md's block lists, run through every frontmatter-list reader; each reader's
# output must be byte-identical across the two. A reader that handles one form only fails
# here by name. Reasoning: dispatch-reporting-defects/task-027.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
P="$REPO/plugin"
. "$P/scripts/bundle-paths.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/fmlistforms.XXXXXX")" || { echo "mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1))
       else printf '  FAIL  %s\n        got:  %s\n        want: %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

GIT() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE \
          GIT_AUTHOR_DATE=2026-10-01T00:00:00Z GIT_COMMITTER_DATE=2026-10-01T00:00:00Z git \
          -c user.email=t@example.com -c user.name=Test -c commit.gpgsign=false \
          -c core.hooksPath=/dev/null "$@"; }

BIN="$TMP/bin"; mkdir -p "$BIN"
printf '#!/usr/bin/env bash\nexit 1\n' > "$BIN/gh"; chmod +x "$BIN/gh"

# <key> <form> <entry>... — one list in the requested form; no entries is `[ ]` in both.
list() {
  local k="$1" form="$2" e out=""; shift 2
  if [ $# -eq 0 ]; then printf '%s: [ ]\n' "$k"; return; fi
  if [ "$form" = flow ]; then
    for e in "$@"; do out="${out:+$out, }\"$e\""; done
    printf '%s: [ %s ]\n' "$k" "$out"
  else
    printf '%s:\n' "$k"; for e in "$@"; do printf '  - "%s"\n' "$e"; done
  fi
}

# The entries carry what has cut a hand-rolled split before: commas, backticks, brackets,
# a ` --- ` answer, a `Q<n>` label and a middle dot.
build() { # <dir> <flow|block>
  local d="$1" f="$2" t="$1/projects/demo/tasks"
  mkdir -p "$t" "$d/projects/demo/deliverables"
  printf '{ "org": "example-org", "reposRoot": "%s/repos" }\n' "$d" > "$d/instance.config.json"
  mkdir -p "$d/$AB_DIR"; cp "$P/seed/SCHEMA.md" "$d/$AB_SCHEMA"
  printf '# Awaiting you\n' > "$d/$AB_AWAITING"
  printf '{}\n' > "$d/$AB_SNAPSHOT"
  : > "$d/projects/demo/deliverables/report.md"; : > "$d/projects/demo/deliverables/deck.html"
  { printf -- '---\ntype: Project\ntitle: Demo\ndescription: d\nkind: build\nstatus: active\n'
    list deliverable_paths "$f" /projects/demo/deliverables/report.md /projects/demo/deliverables/deck.html
    printf 'timestamp: 2026-10-01T00:00:00Z\n---\n'; } > "$d/projects/demo/project.md"
  { printf -- '---\ntype: Task\ntitle: Dependency\nkind: build\nstatus: done\nassignee: software-engineer\n'
    list acceptance_criteria "$f" "it exists"
    list open_questions "$f"
    list open_caveats "$f" '2026-10-01T00:00:00Z · the rollout, `v2`, has not shipped [yet]'
    printf 'pr: [ ]\ntimestamp: 2026-10-01T00:00:00Z\n---\n'; } > "$t/task-001-dep.md"
  { printf -- '---\ntype: Task\ntitle: Draft with questions\nkind: build\nstatus: draft\nassignee: software-engineer\ntarget_repo: example-org/example-repo\n'
    list depends_on "$f" /projects/demo/tasks/task-001-dep.md /projects/demo/tasks/task-404-gone.md
    list acceptance_criteria "$f" 'returns `[a, b]`, not `a`' "a second, with a comma" "Q7 is named here [x]" \
      "four" "five — with a dash" "six"
    list open_questions "$f" "Q1: which region, \`eu\` or [us]?" "Q2: is this answered? --- yes, eu-central-1" \
      "Q3: grant access to the token store"
    list answered_questions "$f" "2026-09-30T00:00:00Z by example-user-007 · Q0: earlier? --- done"
    list advisor_notes "$f" "2026-10-01T00:00:00Z · does criterion 2, the comma one, contradict 1?"
    printf 'pr: [ ]\ntimestamp: 2026-10-01T00:00:00Z\n---\n\n# Context\n\nbody\n'; } > "$t/task-002-draft.md"
  { printf -- '---\ntype: Task\ntitle: Ready but blocked\nkind: build\nstatus: ready\nassignee: software-engineer\n'
    list depends_on "$f" /projects/demo/tasks/task-002-draft.md
    list acceptance_criteria "$f" "one" "two, too"
    list open_questions "$f"
    printf 'pr: [ ]\ntimestamp: 2026-10-01T00:00:00Z\n---\n'; } > "$t/task-003-ready.md"
  { printf -- '---\ntype: Task\ntitle: Ready and clear\nkind: build\nstatus: ready\nassignee: software-engineer\n'
    list depends_on "$f" /projects/demo/tasks/task-001-dep.md
    list acceptance_criteria "$f" "one"
    list open_questions "$f"
    printf 'pr: [ ]\ntimestamp: 2026-10-01T00:00:00Z\n---\n'; } > "$t/task-004-clear.md"
  { printf -- '---\ntype: Task\ntitle: In progress, asking\nkind: build\nstatus: in-progress\nassignee: software-engineer\n'
    list acceptance_criteria "$f" "one"
    list open_questions "$f" 'Q1: still open, `x`?'
    printf 'pr: [ ]\ntimestamp: 2026-10-01T00:00:00Z\n---\n'; } > "$t/task-005-asking.md"
  mkdir -p "$d/scripts"; cp "$P"/scripts/*.sh "$d/scripts/"; cp -R "$P/tick-steps" "$d/tick-steps"
  printf '/%s\n' "$AB_STATE_DIR" > "$d/.gitignore"
  GIT -C "$d" init -q && GIT -C "$d" add -A && GIT -C "$d" commit -qm init
}

FLOW="$TMP/flow/inst"; BLOCK="$TMP/block/inst"
build "$FLOW" flow; build "$BLOCK" block
ok "the two fixtures differ in form (block has entry lines)" \
   "$(grep -c '^  - "' "$BLOCK/projects/demo/tasks/task-002-draft.md")" 13
ok "…and the flow one has none" "$(grep -c '^  - ' "$FLOW/projects/demo/tasks/task-002-draft.md")" 0

# Each reader runs with the bundle as cwd; its root is rewritten to ROOT and the clock to
# NOW, so only a parse difference can make the two outputs disagree.
norm() { sed -e "s#$1#ROOT#g" -e "s#$(GIT -C "$1" rev-parse --short HEAD)#HEAD#g" -e 's/[0-9]\{4\}-[0-9][0-9]-[0-9][0-9]T[0-9:]*Z by <unknown>/NOW by <unknown>/g' \
                -e 's/^Last refreshed: [0-9TZ:-]*\./Last refreshed: NOW./'; }
run() { # <dir> <command...>
  local d="$1"; shift
  ( cd "$d" && PATH="$BIN:$PATH" SNAPSHOT_NOW=2026-10-01T00:00:00Z SNAPSHOT_QUESTION_TEXT=1 "$@" 2>&1; echo "rc=$?" ) | norm "$d"
}
same() { # <label> <command...> — run in both bundles, compare
  local label="$1" a b; shift
  a="$(run "$FLOW" "$@")"; b="$(run "$BLOCK" "$@")"
  if [ "$a" = "$b" ]; then ok "$label" same same
  else ok "$label" "$(head -6 <<<"$(diff <(printf '%s\n' "$a") <(printf '%s\n' "$b"))" | tr '\n' '|')" same; fi
}
T2=projects/demo/tasks/task-002-draft.md

echo "== fold-answers.sh --list (the parser build-awaiting and tick-delta delegate to) =="
for k in acceptance_criteria open_questions answered_questions depends_on advisor_notes; do
  same "fold-answers --list $k" bash scripts/fold-answers.sh --list "$T2" "$k"
done
same "fold-answers --list open_caveats"      bash scripts/fold-answers.sh --list projects/demo/tasks/task-001-dep.md open_caveats
same "fold-answers --list deliverable_paths" bash scripts/fold-answers.sh --list projects/demo/project.md deliverable_paths
ok "…and block form is parsed, not refused" \
   "$(run "$BLOCK" bash scripts/fold-answers.sh --list "$T2" acceptance_criteria | grep -c .)" 7

echo "== the other readers, each through its own entry point =="
same "dispatch-brief.sh (count_entries)"  bash scripts/dispatch-brief.sh "$T2"
ok "…counting all six block criteria"     "$(run "$BLOCK" bash scripts/dispatch-brief.sh "$T2" | grep -c '6 acceptance criteria')" 1
same "tick-delta.sh digest (fmlist/fmcount, answered_open)" \
     sh -c 'bash scripts/tick-delta.sh digest --instance . | grep -v "^head "'
ok "…reading deps=2 q=3 off the block lists" \
   "$(run "$BLOCK" bash scripts/tick-delta.sh digest --instance . | grep -c 'task-002-draft.md .*deps=2 q=3 crit=yes')" 1
ok "…and answering, not CANNOT ANSWER, for an unanswered block list (answered_open)" \
   "$(run "$BLOCK" bash scripts/tick-delta.sh digest --instance . | grep -c 'task-005-asking.md .*q=1')" 1
same "write-snapshot.sh (list_region, list_filled, yaml_list_entries, depends_ids, deliverable_path_entries)" \
     sh -c "bash scripts/write-snapshot.sh --quiet; cat $AB_SNAPSHOT"
ok "…carrying both deliverables and both dependency ids" \
   "$(run "$BLOCK" sh -c "bash scripts/write-snapshot.sh --quiet; cat $AB_SNAPSHOT" \
      | grep -cE 'deliverables/deck.html|"depends_on": \["task-001-dep", "task-404-gone"\]')" 2
same "build-awaiting.sh (entries)"        sh -c "bash scripts/build-awaiting.sh --instance .; cat $AB_AWAITING"
ok "…queueing the unanswered questions as answer and grant rows" \
   "$(run "$BLOCK" sh -c "bash scripts/build-awaiting.sh --instance .; cat $AB_AWAITING" | grep -cE '^\* (❓|🧰)')" 3
same "validate-bundle.sh (list_entries, refs_for)" bash scripts/validate-bundle.sh
ok "…holding the done task on its caveat and naming the dangling dependency" \
   "$(run "$BLOCK" bash scripts/validate-bundle.sh | grep -cE 'held by an open caveat|dangling reference: /projects/demo/tasks/task-404')" 2
same "migrate-bundle.sh (structural refs)" bash scripts/migrate-bundle.sh
ok "…reporting the dangling dependency" "$(run "$BLOCK" bash scripts/migrate-bundle.sh | grep -c 'task-404-gone.md')" 1
same "close-project-folder.sh (refs_for)" bash scripts/close-project-folder.sh demo
ok "…pinning both declared deliverables" \
   "$(run "$BLOCK" bash scripts/close-project-folder.sh demo | grep -c '2 deliverable(s) pinned')" 1
# The banner also relays the AWAITING.md built above, so a reader broken upstream shows here too.
same "session-banner.sh (depends_on, ready count)" \
     env CLAUDE_PROJECT_DIR=. bash "$P/hooks/session-banner.sh" --format json
ok "…offering only the task whose dependency is done" \
   "$(run "$BLOCK" env CLAUDE_PROJECT_DIR=. bash "$P/hooks/session-banner.sh" --format json | grep -c 'Ready to dispatch   1 ')" 1

echo "== the fold round-trips: same move, same lists, either form =="
same "fold-answers.sh moves the answered entry" bash scripts/fold-answers.sh --instance . "$T2"
for k in open_questions answered_questions; do
  same "…after the fold, --list $k" bash scripts/fold-answers.sh --list "$T2" "$k"
done

echo
echo "frontmatter-list-forms: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
