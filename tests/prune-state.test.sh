#!/usr/bin/env bash
#
# prune-state.test.sh — plugin/scripts/prune-state.sh, the age prune of a bundle's .loopd/ state.
#
# One fixture bundle in mktemp: a case per class (prune, kept, unowned) and per guard
# (tracked, .gitignore, open hand-off, live session, receipt PR state, newest backup,
# mtime re-check, emptied subdirectories, symlinks, nothing outside .loopd/). gh is a stub.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR

TPL="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$TPL/plugin/scripts/prune-state.sh"
die() { printf 'prune-state.test: %s\n' "$*" >&2; exit 2; }
[ -f "$SCRIPT" ] || die "script not found at $SCRIPT"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/prune-state.XXXXXX")" && [ -d "$TMP" ] || die "mktemp failed"
TMP="$(cd "$TMP" && pwd -P)" || die "cannot enter $TMP"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1))
       else printf '  FAIL  %s — got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
old() { local d="$1"; shift; perl -e '$t = time - 86400 * shift; utime $t, $t, @ARGV' "$d" "$@"; }
put() { mkdir -p "$(dirname "$B/$1")" && printf '%s\n' "${3:-x}" > "$B/$1" && old "$2" "$B/$1"; }
has() { [ -e "$B/$1" ] || [ -L "$B/$1" ] && echo yes || echo no; }

B="$TMP/bundle"; L=".loopd"; BIN="$TMP/bin"; export CLAUDE_CONFIG_DIR="$TMP/cfg"
mkdir -p "$B/$L" "$BIN" "$CLAUDE_CONFIG_DIR" "$TMP/outside"
echo '{}' > "$B/instance.config.json"
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
[ -n "${GH_TOUCH:-}" ] && touch "$GH_TOUCH"
[ -n "${GH_FAIL:-}" ] && exit 1
case "$3" in 1) echo MERGED ;; 2) echo OPEN ;; 3) echo CLOSED ;; esac
STUB
chmod +x "$BIN/gh"; export PATH="$BIN:$PATH"
LIVE="cccc3333"; DEAD="dddd4444"
printf '[{"sessionId":"%s-0000-0000-0000-000000000000","state":"working","pid":%s},{"sessionId":"%s-0000-0000-0000-000000000000","state":"done"}]\n' \
  "$LIVE" "$$" "$DEAD" > "$TMP/listing.json"
export AB_SESSIONS_LISTING="$TMP/listing.json"

put "$L/.scratch/old.txt" 20; put "$L/.scratch/new.txt" 10; put "$L/.scratch/tracked.txt" 20
put "$L/.scratch/sub/deep/x.txt" 20; put "$L/.scratch/$LIVE-notes.txt" 20; put "$L/.scratch/$DEAD-notes.txt" 20
put "$L/.scratch/touched.txt" 20
put "$L/.handoffs/aaaa1111-bbbb2222.txt" 20; put "$L/.handoffs/aaaa1111-eeee5555.txt" 20; put "$L/.handoffs/.gitignore" 20 '*'
mkdir -p "$B/projects/p/tasks"; echo '* needs handed off · hand-off aaaa1111-bbbb2222 · Q1' > "$B/projects/p/tasks/t.md"
for n in 1 2 3; do put "$L/.tick-receipts/o-r__pr${n}__h" 20 "$(printf 'repo o/r\npr %s\nhead h' "$n")"; done
put "$L/refresh/CLAUDE.md.100" 40; put "$L/refresh/CLAUDE.md.200" 40; put "$L/refresh/.claude/settings.json.300" 40
put "$L/refresh/AGENTS.md.900" 20
put "$L/.pr-cache/o__r__1.json" 90; put "$L/.sessions/listing.json" 90; put "$L/kb.git/HEAD" 90; put "$L/counts.json.4242" 90
put "$L/.mystery/blob" 90 abcdefghi
printf 'old\n' > "$TMP/outside/far.txt"; old 90 "$TMP/outside/far.txt"
ln -s "$TMP/outside" "$B/$L/tmp"; ln -s "$TMP/outside/far.txt" "$B/$L/.scratch/link"
put "tmp/root-scratch.txt" 90
put notes.md 90; put "$L/.scratch/a"$'\n'"notes.md" 90
git -C "$B" init -q && git -C "$B" add "$L/.scratch/tracked.txt" instance.config.json \
  && git -C "$B" -c user.name=F -c user.email=f@example.com -c commit.gpgsign=false commit -qm fixture || die "git fixture"

DRY="$(bash "$SCRIPT" "$B" 2>/dev/null)"
would() { grep -c "^would remove $L/$1 [0-9]" <<<"$DRY"; }
ok "dry run: an aged .scratch file is listed with its bytes" "$(would .scratch/old.txt)" 1
ok "dry run: removes nothing" "$(has "$L/.scratch/old.txt")" yes
ok "dry run: one total line" "$(grep -cE '^prune: [0-9]+ files, [0-9]+ bytes$' <<<"$DRY")" 1
ok "age: a 10-day .scratch file is not listed" "$(would .scratch/new.txt)" 0
ok "age: a 20-day refresh backup is not listed (30 days)" "$(would refresh/AGENTS.md.900)" 0
ok "kept: .pr-cache is not pruned, and printed kept" "$(would .pr-cache/o__r__1.json)$(grep -cx "kept $L/.pr-cache" <<<"$DRY")" 01
ok "kept: .sessions, kb.git and counts.json.<pid> are printed kept" \
   "$(grep -cxE "kept $L/(\.sessions|kb\.git|counts\.json\.4242)" <<<"$DRY")" 3
ok "unowned: an unknown directory is printed with its bytes" "$(grep -cx "unowned $L/.mystery 10" <<<"$DRY")" 1
ok "tracked: a tracked aged file is never listed" "$(would .scratch/tracked.txt)" 0
ok ".gitignore: a writer-seeded .gitignore is never listed" "$(would .handoffs/.gitignore)" 0
ok "hand-off: one a task doc names is kept at any age" "$(would .handoffs/aaaa1111-bbbb2222.txt)" 0
ok "hand-off: one no task doc names is listed" "$(would .handoffs/aaaa1111-eeee5555.txt)" 1
ok "session: a live session's file is kept" "$(would .scratch/$LIVE-notes.txt)" 0
ok "session: a done session's file is listed" "$(would .scratch/$DEAD-notes.txt)" 1
ok "session: an unreadable listing keeps every id-bearing file" \
   "$(AB_SESSIONS_LISTING="$TMP/missing.json" bash "$SCRIPT" "$B" 2>/dev/null | grep -cE "^would remove .*($DEAD-notes|aaaa1111-eeee5555)")" 0
ok "receipt: merged and closed PRs listed, the open one kept" \
   "$(would .tick-receipts/o-r__pr1__h)$(would .tick-receipts/o-r__pr2__h)$(would .tick-receipts/o-r__pr3__h)" 101
ok "receipt: --offline lists none" "$(bash "$SCRIPT" "$B" --offline 2>/dev/null | grep -c 'tick-receipts')" 0
ok "receipt: a failed gh read lists none" "$(GH_FAIL=1 bash "$SCRIPT" "$B" 2>/dev/null | grep -c 'tick-receipts')" 0
ok "refresh: the newest backup of each seed is kept, the older listed" \
   "$(would refresh/CLAUDE.md.200)$(would refresh/.claude/settings.json.300)$(would refresh/CLAUDE.md.100)" 001
ok "symlink: neither a link nor a symlinked table directory is listed" "$(grep -cE "^would remove $L/(tmp/|\.scratch/link)" <<<"$DRY")" 0

APP="$(GH_TOUCH="$B/$L/.scratch/touched.txt" bash "$SCRIPT" "$B" --apply 2>/dev/null)"
ok "apply: prints removed lines and removes them" "$(grep -c "^removed $L/.scratch/old.txt " <<<"$APP")$(has "$L/.scratch/old.txt")" 1no
ok "apply: a file touched after the scan is re-checked and kept" "$(has "$L/.scratch/touched.txt")" yes
ok "apply: an emptied subdirectory goes, the table directory stays" "$(has "$L/.scratch/sub")$(has "$L/.scratch")" noyes
ok "apply: a directory a table directory empties stays (.tick-receipts)" "$(has "$L/.tick-receipts")" yes
ok "apply: nothing kept, tracked or unowned is removed" \
   "$(has "$L/.pr-cache/o__r__1.json")$(has "$L/.mystery/blob")$(has "$L/.scratch/tracked.txt")$(has "$L/.handoffs/.gitignore")" yesyesyesyes
ok "apply: no symlink target and nothing outside .loopd/ is removed" \
   "$(has "$L/.scratch/link")$([ -f "$TMP/outside/far.txt" ] && echo yes)$(has tmp/root-scratch.txt)" yesyesyes
ok "newline: a file name carrying a newline never names a path outside .loopd/" "$(grep -c '^would remove notes.md' <<<"$DRY")$(has notes.md)" 0yes
ok "apply: every removed path is under .loopd/" "$(grep '^removed' <<<"$APP" | grep -vc "^removed $L/")" 0
ok "usage: a root with no .loopd exits 2" "$(bash "$SCRIPT" "$TMP/outside" >/dev/null 2>&1; echo $?)" 2

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
