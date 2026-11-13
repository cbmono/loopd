# tick-close.sh — sourced, never run: the ONE reader of "did tick <id> close its ledger entry?".
# tick-reap.sh releases on it; tick-lock.sh status reports a lock whose claimant it answers as
# FINISHED. One grammar, so a reader can never call RUNNING what the reaper would reap.
# Needs AB_LEDGER (bundle-paths.sh) for tick_committed_close.

# <tick id>, ledger text on stdin -> "closed <line>" | "open <ts>" | "none". The id counts only
# as the token right after the line's FIRST marker, or in the exact `record --idle` grammar —
# never in free text, which agents write. A line carrying it whose first marker is not
# ` open: ` is closed.
tick_close_scan() {
  ID="$1" awk '
    function tok(at,   r) { r = substr($0, at); sub(/[[:space:]].*/, "", r); return r }
    function slot(   o, c, r) {
      o = index($0, " open: "); c = index($0, " close: ")
      if (o > 0 && (c == 0 || o < c)) return tok(o + 7) == ENVIRON["ID"]
      if (c > 0) return tok(c + 8) == ENVIRON["ID"]
      if (!match($0, /^\* TICK [^ ]+ by [^ ]+ idle — fingerprint unchanged \(tick-delta\) · /)) return 0
      r = substr($0, RSTART + RLENGTH)
      return r == ENVIRON["ID"] || index(r, ENVIRON["ID"] " · swept: ") == 1
    }
    /^\* TICK / {
      o = index($0, " open: "); c = index($0, " close: ")
      if (c > 0 && (o == 0 || c < o)) { cl[$3] = $0 }
      if (!slot()) next
      if (o > 0 && (c == 0 || o < c)) ots = $3; else done = $0
    }
    END {
      if (done != "") print "closed " done
      else if (ots != "" && (ots in cl)) print "closed " cl[ots]
      else if (ots != "") print "open " ots
      else print "none"
    }'
}

# <instance> <tick id> -> the close line on stdout and 0 when the COMMITTED ledger (HEAD) closes
# the id; 1 otherwise, an unreadable HEAD included. Only a committed close counts: an
# uncommitted one is a tick still writing.
tick_committed_close() {
  local r
  r="$(git -C "$1" show "HEAD:$AB_LEDGER" 2>/dev/null | tick_close_scan "$2")" || return 1
  case "$r" in closed\ *) printf '%s\n' "${r#closed }"; return 0 ;; esac
  return 1
}
