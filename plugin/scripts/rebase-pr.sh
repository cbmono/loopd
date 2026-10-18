#!/usr/bin/env bash
#
# rebase-pr.sh — rebase a CONFLICTING pull request onto its base and resolve ONLY the
# known merge-magnet shapes, then push and let CI verify. No local suite, no agent.
#
#   Usage: rebase-pr.sh <pr> [--repo <owner>/<name>] [--dir <clone>] [--dry-run]
#          rebase-pr.sh --self-test
#
#   0 rebased and pushed (or already current)   4 a resolution failed its own check
#   1 usage                                     5 refused (fork, base, closed, not CONFLICTING)
#   2 cannot answer (no gh, UNKNOWN state)      6 lease stale — the remote head moved
#   3 UNCLASSIFIED CONFLICT — an agent round; names the file
#
# 3, 4, 5 and 6 all leave the branch and the remote exactly as they were. Reasoning,
# measurements and the rejected designs: ai-bridge-v3/task-043.
set -uo pipefail

# git exports these into every hook and into `git rebase -x`, and `git -C` overrides none
# of them — an inherited GIT_DIR redirects this script's fetch, rebase and lease-protected
# push into whatever repo the caller was in. Same set tests/run.sh clears, same reason.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE \
      GIT_CONFIG GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT

PR=""; REPO_SLUG=""; DIR="$PWD"; DRY=0; SELFTEST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) [ $# -ge 2 ] || { echo "rebase-pr: --repo requires a value" >&2; exit 1; }
            REPO_SLUG="$2"; shift 2 ;;
    --dir)  [ $# -ge 2 ] || { echo "rebase-pr: --dir requires a value" >&2; exit 1; }
            DIR="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --self-test) SELFTEST=1; shift ;;
    -h|--help) sed -n '3,14p' "$0"; exit 0 ;;
    -*) echo "rebase-pr: unknown option $1" >&2; exit 1 ;;
    *) PR="$1"; shift ;;
  esac
done

# ---------------------------------------------------------------------------------------
# the classifier

# Comment share, tenths of a percent — the same measurement concision-contract.test.sh
# makes, so a recomputed ratchet row is the value that harness will read back.
share() {
  LC_ALL=C awk '
    NR == 1 && /^#!/ { total++; next }
    { total++; if ($0 ~ /^[[:space:]]*#/) c++ }
    END { if (total == 0) print 0; else printf "%d\n", c * 1000 / total }
  ' "$1"
}

# Rewrite one diff3-marked file in place. stdout carries a line per resolved magnet:
# `counter <IDENT>` or `ratchet <path>`. Exit 9 = a block it cannot classify, with the
# block's first content line on stderr.
resolve_file() {
  local f="$1" tmp="$1.rebase-pr"
  awk -v out="$tmp" '
    function flush_block(   i, j, k, seen, n, name, ov, tv, bv, bc, bvals, rbad, marks) {
      blocks++
      # counter: comment lines plus exactly one IDENT=<int> on each side.
      name = ""; oc = 0; tc = 0
      for (i = 1; i <= no; i++) if (O[i] ~ /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=[0-9]+[[:space:]]*$/) {
        split(O[i], p, "="); gsub(/^[[:space:]]+/, "", p[1]); name = p[1]; ov = p[2] + 0; oc++
      }
      for (i = 1; i <= nt; i++) if (T[i] ~ /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=[0-9]+[[:space:]]*$/) {
        split(T[i], p, "="); gsub(/^[[:space:]]+/, "", p[1]); if (p[1] != name) name = "!"; tv = p[2] + 0; tc++
      }
      if (name != "" && name != "!" && oc == 1 && tc == 1 && only_comment_or_assign()) {
        # ONE base assignment, or this is not the shape. An add/add block has no base
        # section at all, and `ours + theirs - ours` is just theirs — the sum would drop
        # the OURS delta while still looking like the three-way answer.
        bc = 0; for (i = 1; i <= nb; i++) if (B[i] ~ "^[[:space:]]*" name "=[0-9]+[[:space:]]*$") {
          split(B[i], p, "="); bv = p[2] + 0; bc++
        }
        if (bc == 1) {
          for (i = 1; i <= no; i++) if (O[i] ~ /^[[:space:]]*#/) { print O[i] > out; seen[O[i]] = 1 }
          for (i = 1; i <= nt; i++) if (T[i] ~ /^[[:space:]]*#/ && !(T[i] in seen)) print T[i] > out
          printf "%s=%d\n", name, ov + tv - bv > out
          print "counter " name
          oc = 0; tc = 0; bc = 0; return
        }
      }
      oc = 0; tc = 0; bc = 0
      # comment history: every line on both sides is a comment. Keep both, in order.
      if (all_comments(O, no) && all_comments(T, nt)) {
        for (i = 1; i <= no; i++) { print O[i] > out; seen[O[i]] = 1 }
        for (i = 1; i <= nt; i++) if (!(T[i] in seen)) print T[i] > out
        return
      }
      # ratchet table: every line on every side is `<int> <path>`. Union by path; a path
      # both sides lowered is emitted at its OURS value and named for recomputation.
      if (all_rows(O, no) && all_rows(T, nt) && (nb == 0 || all_rows(B, nb))) {
        n = 0; rbad = 0; marks = ""
        for (i = 1; i <= nb; i++) { split(B[i], p, " "); bvals[p[2]] = p[1] + 0 }
        for (i = 1; i <= no; i++) { split(O[i], p, " "); if (!(p[2] in val)) { n++; order[n] = p[2] }; val[p[2]] = p[1] + 0 }
        for (i = 1; i <= nt; i++) {
          split(T[i], p, " ")
          if (!(p[2] in val)) { n++; order[n] = p[2]; val[p[2]] = p[1] + 0 }
          # BOTH sides lowered, against a base that carries the row, or it is not this
          # shape: a side that RAISED the row loosened the ratchet on purpose, and the
          # recomputation below would silently take that decision back.
          else if (val[p[2]] != p[1] + 0) {
            if ((p[2] in bvals) && val[p[2]] < bvals[p[2]] && p[1] + 0 < bvals[p[2]]) marks = marks "ratchet " p[2] "\n"
            else rbad = 1
          }
        }
        if (rbad) {
          for (i = 1; i <= n; i++) delete val[order[i]]
          printf "%s\n", O[1] > "/dev/stderr"
          bad = 1; return
        }
        printf "%s", marks
        for (i = 1; i < n; i++) for (j = 1; j <= n - i; j++)
          if (order[j] > order[j + 1]) { k = order[j]; order[j] = order[j + 1]; order[j + 1] = k }
        for (i = 1; i <= n; i++) { printf "%d %s\n", val[order[i]], order[i] > out; delete val[order[i]] }
        return
      }
      printf "%s\n", (no ? O[1] : (nt ? T[1] : "<empty conflict block>")) > "/dev/stderr"
      bad = 1
    }
    function only_comment_or_assign(   i) {
      for (i = 1; i <= no; i++) if (O[i] !~ /^[[:space:]]*#/ && O[i] !~ /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=[0-9]+[[:space:]]*$/) return 0
      for (i = 1; i <= nt; i++) if (T[i] !~ /^[[:space:]]*#/ && T[i] !~ /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=[0-9]+[[:space:]]*$/) return 0
      return 1
    }
    function all_comments(A, n,   i) { if (n == 0) return 0; for (i = 1; i <= n; i++) if (A[i] !~ /^[[:space:]]*#/) return 0; return 1 }
    function all_rows(A, n,   i) { if (n == 0) return 0; for (i = 1; i <= n; i++) if (A[i] !~ /^[0-9]+ [^ ]+$/) return 0; return 1 }
    /^<<<<<<< / { state = 1; no = 0; nb = 0; nt = 0; next }
    /^\|\|\|\|\|\|\| / && state == 1 { state = 2; next }
    /^=======$/ && state >= 1 { state = 3; next }
    /^>>>>>>> / && state >= 1 { flush_block(); state = 0; next }
    state == 1 { O[++no] = $0; next }
    state == 2 { B[++nb] = $0; next }
    state == 3 { T[++nt] = $0; next }
    { print > out }
    END {
      if (bad) exit 9
      if (blocks == 0) {
        print "no conflict block — a delete/modify, mode or binary conflict" > "/dev/stderr"
        exit 8
      }
    }
  ' "$f"
  local rc=$?
  if [ $rc -ne 0 ]; then rm -f "$tmp"; return $rc; fi
  mv "$tmp" "$f"
}

# ---------------------------------------------------------------------------------------
# the run

if [ $SELFTEST -eq 1 ]; then
  command -v git >/dev/null 2>&1 || { echo "rebase-pr: git not found" >&2; exit 2; }
  command -v awk >/dev/null 2>&1 || { echo "rebase-pr: awk not found" >&2; exit 2; }
  echo "rebase-pr: self-test ok"; exit 0
fi

case "$PR" in ''|*[!0-9]*) sed -n '3,14p' "$0" >&2; exit 1 ;; esac
command -v gh >/dev/null 2>&1 || { echo "rebase-pr: gh not found — cannot answer" >&2; exit 2; }
git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1 || {
  echo "rebase-pr: $DIR is not a git repository — cannot answer" >&2; exit 2; }

meta="$(gh pr view "$PR" ${REPO_SLUG:+--repo "$REPO_SLUG"} \
  --json state,baseRefName,headRefName,headRefOid,isCrossRepository,mergeable,mergeStateStatus \
  2>/dev/null)" || meta=""
[ -n "$meta" ] || { echo "rebase-pr: PR $PR metadata unreadable — cannot answer" >&2; exit 2; }
read -r state base head lease cross mergeable merge_state <<EOF
$(printf '%s' "$meta" | jq -r '[.state, .baseRefName, .headRefName, .headRefOid,
  (if .isCrossRepository then "fork" else "same" end),
  (if (.mergeable // "") == "" then "UNKNOWN" else .mergeable end),
  (if (.mergeStateStatus // "") == "" then "UNKNOWN" else .mergeStateStatus end)] | @tsv' 2>/dev/null)
EOF
[ -n "${lease:-}" ] || { echo "rebase-pr: PR $PR metadata incomplete — cannot answer" >&2; exit 2; }

[ "$state" = "OPEN" ] || { echo "rebase-pr: refuse — PR $PR is $state, not OPEN" >&2; exit 5; }
[ "$cross" = "same" ] || { echo "rebase-pr: refuse — PR $PR has a FORK head; a lease push" >&2
  echo "        needs write access this tick does not have" >&2; exit 5; }
[ "$head" != "$base" ] || { echo "rebase-pr: refuse — PR $PR's head IS its base ($base)" >&2; exit 5; }

# ONLY A CONFLICTING PR. A caller holding a stale exit 7, or a hand invocation, otherwise
# rewrites the head of a PR that merges fine — which spends its review and its green CI.
# UNKNOWN is a hold, not a state: the host computes mergeability lazily and answers UNKNOWN
# for seconds after the base moves. Same answer review-clearance.sh gives it, exit 2.
case "$mergeable/$merge_state" in
  UNKNOWN/*|*/UNKNOWN) echo "rebase-pr: PR $PR mergeability is UNKNOWN — the host is still" >&2
    echo "        computing it. Nothing touched; re-ask next tick." >&2; exit 2 ;;
esac
[ "$mergeable" = "CONFLICTING" ] || [ "$merge_state" = "DIRTY" ] || {
  echo "rebase-pr: refuse — PR $PR is $mergeable/$merge_state, not CONFLICTING/DIRTY." >&2
  echo "        A rebase here would rewrite the head of a PR that does not conflict." >&2
  exit 5; }

git -C "$DIR" fetch --quiet origin \
  "+refs/heads/$base:refs/remotes/origin/$base" \
  "+refs/heads/$head:refs/remotes/origin/$head" 2>/dev/null || {
  echo "rebase-pr: fetch failed for $base / $head — cannot answer" >&2; exit 2; }

remote_head="$(git -C "$DIR" rev-parse "refs/remotes/origin/$head" 2>/dev/null || true)"
[ "$remote_head" = "$lease" ] || {
  echo "rebase-pr: lease stale — the host reported $lease for $head but origin now has" >&2
  echo "        ${remote_head:-nothing}. Nothing touched; re-ask next tick." >&2; exit 6; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/rebase-pr.XXXXXX")" || {
  echo "rebase-pr: mktemp -d failed — cannot answer" >&2; exit 2; }
WT="$TMP/wt"
cleanup() {
  git -C "$WT" rebase --abort >/dev/null 2>&1 || true
  git -C "$DIR" worktree remove --force "$WT" >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

# A THROWAWAY worktree, never the task agent's: rebasing in that one can meet an
# uncommitted tree or a rebase somebody else started. The lease below is what keeps the
# two pushes honest in the other direction — an agent whose remote-tracking ref predates
# this push has its own --force-with-lease refused rather than clobbering us.
git -C "$DIR" worktree add --quiet --detach "$WT" "$lease" >/dev/null 2>&1 || {
  echo "rebase-pr: could not create a worktree at $lease — cannot answer" >&2; exit 2; }

if git -C "$WT" merge-base --is-ancestor "refs/remotes/origin/$base" HEAD 2>/dev/null; then
  echo "rebase-pr: PR $PR is already on top of $base — nothing to do"; exit 0
fi

git -C "$WT" -c rerere.enabled=false rebase "refs/remotes/origin/$base" >/dev/null 2>&1
resolved=""; counters=""; ratchets=""; rounds=0
while [ -n "$(git -C "$WT" ls-files --unmerged 2>/dev/null)" ]; do
  rounds=$((rounds + 1))
  [ $rounds -le 50 ] || { echo "rebase-pr: gave up after 50 conflicted commits" >&2; exit 3; }
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    git -C "$WT" checkout --conflict=diff3 -- "$f" >/dev/null 2>&1
    if ! marks="$(resolve_file "$WT/$f" 2>"$TMP/err")"; then
      echo "rebase-pr: UNCLASSIFIED CONFLICT in $f — this one earns an agent round." >&2
      sed -n '1,3p' "$TMP/err" | sed 's/^/        at: /' >&2
      exit 3
    fi
    resolved="$resolved$f"$'\n'
    while IFS=' ' read -r kind what; do
      [ -n "${what:-}" ] || continue
      case "$kind" in
        counter) counters="$counters$f $what"$'\n' ;;
        ratchet) ratchets="$ratchets$f $what"$'\n' ;;
      esac
    done <<EOF
$marks
EOF
    git -C "$WT" add -- "$f" >/dev/null 2>&1
  done <<EOF
$(git -C "$WT" diff --name-only --diff-filter=U 2>/dev/null)
EOF
  git -C "$WT" -c core.editor=true -c rerere.enabled=false rebase --continue >/dev/null 2>&1
done

GD="$(git -C "$WT" rev-parse --git-path rebase-merge 2>/dev/null)"
GA="$(git -C "$WT" rev-parse --git-path rebase-apply 2>/dev/null)"
if [ -d "${GD:-/nonexistent}" ] || [ -d "${GA:-/nonexistent}" ]; then
  echo "rebase-pr: the rebase stopped for something that is not a conflict — an agent" >&2
  echo "        round. Nothing pushed." >&2; exit 3
fi

# A row both sides lowered has no correct side: the merged file's share is neither. It is
# pure awk over a file we already hold, so it is computed rather than picked.
while IFS=' ' read -r tbl path; do
  [ -n "${path:-}" ] || continue
  if [ -f "$WT/$path" ]; then now="$(share "$WT/$path")"; else now=""; fi
  if [ -n "$now" ]; then
    LC_ALL=C awk -v p="$path" -v v="$now" '
      $2 == p { printf "%d %s\n", v, p; next } { print }' "$WT/$tbl" > "$WT/$tbl.rp" \
      && mv "$WT/$tbl.rp" "$WT/$tbl"
  else
    LC_ALL=C awk -v p="$path" '$2 != p' "$WT/$tbl" > "$WT/$tbl.rp" && mv "$WT/$tbl.rp" "$WT/$tbl"
  fi
  git -C "$WT" add -- "$tbl" >/dev/null 2>&1
done <<EOF
$ratchets
EOF
if [ -n "$ratchets" ] && ! git -C "$WT" diff --cached --quiet 2>/dev/null; then
  git -C "$WT" -c core.editor=true commit --amend --no-edit --no-verify >/dev/null 2>&1
fi

# THE FINDING'S FAILURE MODE, ASSERTED: a resolution that keeps every annotation and drops
# the one assignment is bash -n clean and fails only at execution.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -f "$WT/$f" ] || continue
  if grep -qE '^(<<<<<<< |=======$|>>>>>>> )' "$WT/$f"; then
    echo "rebase-pr: refuse — $f still carries conflict markers after resolution" >&2; exit 4
  fi
  case "$f" in *.sh)
    bash -n "$WT/$f" 2>/dev/null || {
      echo "rebase-pr: refuse — $f does not parse after resolution" >&2; exit 4; } ;;
  esac
done <<EOF
$(printf '%s' "$resolved" | sort -u)
EOF
while IFS=' ' read -r f name; do
  [ -n "${name:-}" ] || continue
  n="$(grep -cE "^[[:space:]]*$name=[0-9]+[[:space:]]*$" "$WT/$f" 2>/dev/null || true)"
  [ "${n:-0}" = "1" ] || {
    echo "rebase-pr: refuse — $f carries ${n:-0} assignments of $name, want exactly 1" >&2
    exit 4; }
done <<EOF
$counters
EOF

if [ $DRY -eq 1 ]; then
  printf 'rebase-pr: PR %s rebased onto %s at %s (dry run, not pushed)\n' \
    "$PR" "$base" "$(git -C "$WT" rev-parse --short HEAD)"
  exit 0
fi

git -C "$WT" push --force-with-lease="refs/heads/${head}:${lease}" \
  origin "HEAD:refs/heads/$head" >/dev/null 2>&1 || {
  echo "rebase-pr: push refused — the lease on $head no longer holds. Nothing changed" >&2
  echo "        on the remote; re-ask next tick." >&2; exit 6; }

printf 'rebase-pr: PR %s rebased onto %s and pushed as %s. CI verifies it.\n' \
  "$PR" "$base" "$(git -C "$WT" rev-parse HEAD)"
