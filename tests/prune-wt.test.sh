#!/usr/bin/env bash
#
# prune-wt.test.sh — plugin/scripts/prune-wt.sh, the remover behind /loopd:prune-wt.
#
# It acts only on what prune-worktrees.sh reports REMOVABLE, and only after re-checking
# each path itself, so most of this file proves refusals: a held tick lock, an ignored
# .env, a live process (reported, and one the report never showed), KEEP and RECLAIMABLE.
# Then the safe set goes, and `git worktree prune` runs once per repo it came from.
# gh and git are shimmed first on PATH; nothing outside an mktemp tree is touched.
set -uo pipefail

TPL="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${PRUNE_WT:-$TPL/plugin/scripts/prune-wt.sh}"
PRUNER="$TPL/plugin/scripts/prune-worktrees.sh"
die() { printf 'prune-wt.test: %s\n' "$*" >&2; exit 2; }
[ -f "$SCRIPT" ] || die "script not found at $SCRIPT"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/prune-wt.XXXXXX")" || die "mktemp failed"
TMP="$(cd "$TMP" && pwd -P)"
case "$TMP" in *Dropbox*|*iCloud*|*"Google Drive"*|*OneDrive*)
  rm -rf "$TMP"; die "refusing to build fixtures inside a synced folder ($TMP)" ;; esac
PIDS=""
trap 'for p in $PIDS; do kill "$p" 2>/dev/null; done; rm -rf "$TMP"' EXIT

REPOS="$TMP/repos"; WTROOT="$TMP/wt"; INSTANCE="$TMP/instance"; BIN="$TMP/bin"
FIXTURES="$TMP/gh-fixtures"; GITLOG="$TMP/git-prune.log"
mkdir -p "$REPOS" "$WTROOT" "$INSTANCE" "$BIN"
cat > "$INSTANCE/instance.config.json" <<JSON
{ "org": "fixture-org", "reposRoot": "$REPOS", "worktreeRoot": "$WTROOT" }
JSON

REAL_GIT="$(command -v git)"
cat > "$BIN/git" <<SHIM
#!/usr/bin/env bash
case " \$* " in *" worktree prune "*) printf '%s\n' "\$*" >> "$GITLOG" ;; esac
exec "$REAL_GIT" "\$@"
SHIM
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
br=""; prev=""
for a in "$@"; do [ "$prev" = --head ] && br="$a"; prev="$a"; done
[ -n "$br" ] || { echo "gh-stub: unhandled: $*" >&2; exit 1; }
awk -v b="$br" '$1 == b { print $2 }' "$GH_FIXTURES"
STUB
chmod +x "$BIN/git" "$BIN/gh"

mkrepo() { # <name>
  local r="$REPOS/$1" o="$TMP/$1.git"
  git init -q -b main "$r"
  git -C "$r" config user.email fixture@example.com; git -C "$r" config user.name Fixture
  git -C "$r" config commit.gpgsign false
  printf 'one\n' > "$r/tracked.txt"; printf '.env\nnode_modules/\n' > "$r/.gitignore"
  git -C "$r" add .; git -C "$r" commit -qm c1
  git init -q --bare -b main "$o"; git -C "$r" remote add origin "$o"
  git -C "$r" push -q -u origin main; git -C "$r" remote set-head origin -a >/dev/null
}
wt() { # <repo> <name> <pr-state> — a finished dispatch: own commit, pushed, clean
  local p="$WTROOT/$2"
  git -C "$REPOS/$1" worktree add -q "$p" -b "$2" origin/main >/dev/null 2>&1
  git -C "$p" config user.email fixture@example.com; git -C "$p" config user.name Fixture
  printf 'work\n' > "$p/feature.txt"; git -C "$p" add feature.txt; git -C "$p" commit -qm "$2"
  git -C "$p" push -q -u origin "$2" 2>/dev/null
  printf '%s %s\n' "$2" "$3" >> "$FIXTURES"
}
live() { # <name> — a process whose cwd is the worktree, bounded at the child
  ( cd "$WTROOT/$1" && exec sleep 120 ) >/dev/null 2>&1 & PIDS="$PIDS $!"
}

mkrepo alpha; mkrepo beta; mkrepo gamma
wt alpha a-rm1 MERGED
wt alpha a-cache MERGED; mkdir -p "$WTROOT/a-cache/node_modules/x"; : > "$WTROOT/a-cache/node_modules/x/i.js"
wt alpha a-env MERGED;   printf 'SECRET=1\n' > "$WTROOT/a-env/.env"
wt alpha a-open OPEN
wt alpha a-dirty MERGED; printf 'edit\n' >> "$WTROOT/a-dirty/tracked.txt"
wt alpha a-scaff MERGED; : > "$WTROOT/a-scaff/probe.txt"
wt alpha a-live MERGED;  live a-live
wt beta  b-rm MERGED
wt gamma c-open OPEN
sleep 1

pass=0; fail=0; OUT=""; RC=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1))
       else printf '  FAIL  %s — got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
there() { [ -d "$WTROOT/$1" ] && echo yes || echo no; }
run() { # <pruner> <args...> → OUT, RC
  local p=$1; shift; : > "$GITLOG"
  OUT="$(cd "$INSTANCE" && PATH="$BIN:$PATH" GH_FIXTURES="$FIXTURES" PRUNE_ACTIVE_MINUTES=0 \
         PRUNE_WT_PRUNER="$p" bash "$SCRIPT" "$@" 2>&1)"; RC=$?
}
prunes() { grep -c -- "-C $REPOS/$1 worktree prune" "$GITLOG" | tr -d ' '; }
ALL="a-rm1 a-cache a-env a-open a-dirty a-scaff a-live b-rm c-open"
all_there() { local n; for n in $ALL; do [ -d "$WTROOT/$n" ] || { echo no; return; }; done; echo yes; }

echo "== the report this runs on =="
REPORT="$(cd "$INSTANCE" && PATH="$BIN:$PATH" GH_FIXTURES="$FIXTURES" PRUNE_ACTIVE_MINUTES=0 bash "$PRUNER")"
ok "the pruner calls a-env REMOVABLE (it cannot see ignored files)" "$(grep -c "^REMOVABLE .*/a-env  " <<<"$REPORT")" 1
ok "the pruner prints a-live BOTH REMOVABLE and LIVE PROCESS" \
   "$(grep -c "^REMOVABLE .*/a-live  " <<<"$REPORT")$(grep -c "^LIVE PROCESS .*/a-live  " <<<"$REPORT")" 11
ok "a-open is KEEP and a-scaff RECLAIMABLE" \
   "$(grep -c "^KEEP (pr open)  .*/a-open  " <<<"$REPORT")$(grep -c "^RECLAIMABLE .*/a-scaff  " <<<"$REPORT")" 11

echo "== a held tick lock refuses everything =="
( cd "$INSTANCE" && bash "$TPL/plugin/scripts/tick-lock.sh" acquire --as launcher --instance "$INSTANCE" >/dev/null 2>&1 )
ok "fixture: the lock is held" "$(cd "$INSTANCE" && bash "$TPL/plugin/scripts/tick-lock.sh" status --instance "$INSTANCE" >/dev/null 2>&1; echo $?)" 1
run "$PRUNER" --yes
ok "--yes under the lock exits non-zero" "$([ "$RC" -ne 0 ] && echo yes || echo no)" yes
ok "…and says the lock is why" "$(grep -c 'tick' <<<"$OUT" | awk '{print ($1>0)?"yes":"no"}')" yes
ok "…and removed nothing" "$(all_there)" yes
ok "…and pruned nothing" "$(wc -l < "$GITLOG" | tr -d ' ')" 0
( cd "$INSTANCE" && bash "$TPL/plugin/scripts/tick-lock.sh" release --instance "$INSTANCE" >/dev/null 2>&1 )

echo "== the preview touches nothing =="
run "$PRUNER"
ok "preview exits 0" "$RC" 0
ok "preview lists the three it would remove" "$(grep -c '^would remove: ' <<<"$OUT")" 3
ok "preview removed nothing" "$(all_there)" yes

echo "== one confirmation: exactly the safe set goes =="
run "$PRUNER" --yes
ok "--yes exits 0" "$RC" 0
for n in a-rm1 a-cache b-rm; do ok "$n (REMOVABLE, passes every guard) is gone" "$(there "$n")" no; done
ok "a-cache's ignored node_modules was a known cache, not a refusal" "$(grep -c "^removed: .*/a-cache" <<<"$OUT")" 1
ok "a-env (REMOVABLE, only an ignored .env) is spared" "$(there a-env)" yes
ok "…and its .env is intact" "$([ -f "$WTROOT/a-env/.env" ] && echo yes || echo no)" yes
ok "…with the ignored file named as the reason" "$(grep -c "^skip: .*/a-env .*\.env" <<<"$OUT")" 1
ok "a-live (REMOVABLE + LIVE PROCESS) is spared" "$(there a-live)" yes
for n in a-open a-dirty c-open; do ok "$n (KEEP) is intact" "$(there "$n")" yes; done
ok "a-scaff (RECLAIMABLE) is intact" "$(there a-scaff)" yes
ok "worktree prune ran once for alpha" "$(prunes alpha)" 1
ok "worktree prune ran once for beta"  "$(prunes beta)" 1
ok "worktree prune never ran for gamma (nothing removed there)" "$(prunes gamma)" 0
ok "the removed paths are deregistered too" \
   "$(git -C "$REPOS/alpha" worktree list --porcelain | grep -c "/a-rm1$")" 0

echo "== the live-process check is re-run at removal time =="
cat > "$BIN/blind-pruner.sh" <<STRIP
#!/usr/bin/env bash
bash "$PRUNER" "\$@" | grep -v '^LIVE PROCESS'
STRIP
run "$BIN/blind-pruner.sh" --yes
ok "with no LIVE PROCESS line in the report, a-live is still spared" "$(there a-live)" yes
ok "…by the check made at removal time" "$(grep -c "^skip: .*/a-live .*running in it now" <<<"$OUT")" 1
for p in $PIDS; do kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; done; PIDS=""
run "$BIN/blind-pruner.sh" --yes
ok "the process was the reason: once it is gone, a-live is removed" "$(there a-live)" no
ok "a-env is still spared on every run" "$(there a-env)" yes

echo "== the pruner stays report-only; the remover never forces =="
ok "prune-worktrees.sh still refuses --reclaim with exit 2" \
   "$(cd "$INSTANCE" && bash "$PRUNER" --reclaim >/dev/null 2>&1; echo $?)" 2
ok "prune-wt.sh never passes a forced-removal flag" "$(grep -cE -- '--force|remove -f' "$SCRIPT" | tr -d ' ')" 0
allow() { sed -n '/^IGNORE_OK="/,/"$/p' "$1" | tr -s ' \\\n' ' '; }
ok "its ignored-content allowlist is reclaim-worktree.sh's, exactly" \
   "$(allow "$SCRIPT")" "$(allow "$TPL/plugin/scripts/reclaim-worktree.sh")"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
