#!/usr/bin/env bash
#
# resource-gate.sh [--instance DIR] — may step 3 spawn a role agent on this machine now?
# Prints one `disk:` and one `mem:` line. Free disk is measured on the filesystem holding
# worktreeRoot (absent, <reposRoot>/_wt; the nearest existing ancestor when not created yet);
# memory is AVAILABLE memory — macOS (free + inactive + purgeable) pages × page size, Linux
# MemAvailable. Floors are minFreeDiskGb / minFreeMemGb, decimal GB; a key absent is no gate
# for that resource, and a measurement that fails is UNKNOWN and allows the dispatch.
#   0 dispatch allowed   1 refused (below a floor)   2 usage
# Reasoning: ai-control-panel-guards/task-004. Verified by tests/resource-gate.test.sh.
set -uo pipefail

inst="."
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) [ $# -ge 2 ] || { echo "resource-gate: --instance needs a directory" >&2; exit 2; }
                inst="$2"; shift 2 ;;
    *) echo "Usage: $(basename "$0") [--instance DIR]" >&2; exit 2 ;;
  esac
done
[ -f "$inst/instance.config.json" ] || { echo "resource-gate: $inst is not a bundle" >&2; exit 2; }

self="${BASH_SOURCE[0]:-$0}"
[ -L "$self" ] && self="$(readlink "$self" 2>/dev/null || printf '%s' "$self")"
RC="$(cd "$(dirname "$self")" && pwd)/resolve-config.sh"

floor_disk="$(bash "$RC" --instance "$inst" --json minFreeDiskGb 2>/dev/null)" || floor_disk=""
floor_mem="$(bash "$RC" --instance "$inst" --json minFreeMemGb 2>/dev/null)" || floor_mem=""

disk_bytes() {
  local p v
  p="$(bash "$RC" --instance "$inst" worktreeRoot 2>/dev/null)" || p=""
  if [ -z "$p" ]; then
    p="$(bash "$RC" --instance "$inst" reposRoot 2>/dev/null)" || { WHY="worktreeRoot and reposRoot unset"; return 1; }
    p="${p%/}/_wt"
  fi
  p="${p/#\~/$HOME}"
  while [ ! -d "$p" ] && [ "$p" != "/" ] && [ -n "$p" ]; do p="$(dirname "$p")"; done
  WHY="df failed at $p"
  v="$(df -Pk "$p" 2>/dev/null | awk 'NR == 2 { print $4 }')"
  [[ "$v" =~ ^[0-9]+$ ]] || return 1
  BYTES=$(( v * 1024 )); AT=" at $p"
}

mem_bytes() {
  local v os
  os="$(uname -s 2>/dev/null)"; WHY="no memory probe for ${os:-this OS}"
  case "$os" in
    Darwin)
      WHY="vm_stat gave no free, inactive and purgeable page counts"
      v="$(vm_stat 2>/dev/null | awk '
        /page size of/ { for (i = 1; i <= NF; i++) if ($i == "of") ps = $(i + 1) }
        /^Pages (free|inactive|purgeable):/ { gsub(/\./, "", $NF); n += $NF; seen++ }
        END { if (ps > 0 && seen == 3) printf "%.0f\n", n * ps }')" ;;
    Linux)
      WHY="no MemAvailable in ${LOOPD_MEMINFO:-/proc/meminfo}"
      v="$(awk '/^MemAvailable:/ { printf "%.0f\n", $2 * 1024 }' "${LOOPD_MEMINFO:-/proc/meminfo}" 2>/dev/null)" ;;
  esac
  [[ "${v:-}" =~ ^[0-9]+$ ]] || return 1
  BYTES="$v"; AT=""
}

refused=0
gate() { # <label> <key> <floor-json> <measure-fn> <what>
  local label="$1" key="$2" floor="$3"
  if [ -z "$floor" ]; then echo "$label: off — $key absent"; return; fi
  if ! [[ "$floor" =~ ^[0-9]+(\.[0-9]+)?$ ]] || awk -v f="$floor" 'BEGIN { exit !(f <= 0) }'; then
    echo "$label: off — $key is not a positive number of GB ($floor)"; return
  fi
  WHY=""; BYTES=""; AT=""
  if ! "$4"; then
    echo "$label: UNKNOWN (${WHY:-could not measure}) — dispatch allowed, $key $floor"; return
  fi
  if awk -v b="$BYTES" -v f="$floor" 'BEGIN { exit !(b < f * 1e9) }'; then
    refused=1
    printf '%s: %s GB %s%s, below %s %s GB — dispatch refused\n' "$label" "$(gb "$BYTES")" "$5" "$AT" "$key" "$floor"
  else
    printf '%s: %s GB %s%s, floor %s %s GB — ok\n' "$label" "$(gb "$BYTES")" "$5" "$AT" "$key" "$floor"
  fi
}
gb() { awk -v b="$1" 'BEGIN { printf "%.1f", b / 1e9 }'; }

gate disk minFreeDiskGb "$floor_disk" disk_bytes free
gate mem minFreeMemGb "$floor_mem" mem_bytes available
exit "$refused"
