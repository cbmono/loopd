#!/usr/bin/env bash
#
# resource-gate.test.sh — plugin/scripts/resource-gate.sh, the free-disk and free-memory
# floor step 3 checks before it spawns. df, vm_stat and uname are shimmed first on PATH;
# Linux memory reads a fixture meminfo. One unshimmed run proves the real probes parse.
set -uo pipefail

TPL="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$TPL/plugin/scripts/resource-gate.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/resource-gate.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL  %s\n        got:  %s\n        want: %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
has() { case "$2" in *"$3"*) ok "$1" yes yes ;; *) ok "$1" "$2" "contains: $3" ;; esac; }

BIN="$TMP/bin"; INST="$TMP/inst"; REPOS="$TMP/repos"; CALLS="$TMP/calls"
mkdir -p "$BIN" "$INST" "$REPOS/_wt"
cat > "$BIN/df" <<'SH'
#!/usr/bin/env bash
echo "df $*" >> "$CALLS"
[ -n "${DF_KB:-}" ] || exit 1
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/x 999999999 1 %s 1%% /\n' "$DF_KB"
SH
cat > "$BIN/vm_stat" <<'SH'
#!/usr/bin/env bash
echo "vm_stat" >> "$CALLS"
[ -n "${VM_FREE:-}" ] || exit 1
printf 'Mach Virtual Memory Statistics: (page size of 16384 bytes)\nPages free:  %s.\nPages active:  900000.\nPages inactive:  %s.\nPages speculative:  800.\nPages wired down:  280000.\nPages purgeable:  %s.\n' \
  "$VM_FREE" "$VM_INACTIVE" "$VM_PURGEABLE"
SH
printf '#!/usr/bin/env bash\necho "${UNAME:-Darwin}"\n' > "$BIN/uname"
chmod +x "$BIN"/*

config() { printf '{ "org": "o", "reposRoot": "%s"%s }\n' "$REPOS" "${1:+, $1}" > "$INST/instance.config.json"; rm -f "$INST/instance.config.local.json"; }
run() { : > "$CALLS"; OUT="$(PATH="$BIN:$PATH" CALLS="$CALLS" bash "$SCRIPT" --instance "$INST" 2>&1)"; RC=$?; }
export DF_KB VM_FREE VM_INACTIVE VM_PURGEABLE UNAME LOOPD_MEMINFO
DF_KB=50000000; VM_FREE=5000; VM_INACTIVE=500000; VM_PURGEABLE=600; UNAME=Darwin

echo "== both keys absent: no gate, nothing measured (today's behaviour) =="
config; run
ok "exit 0" "$RC" 0
ok "two off lines" "$OUT" "$(printf 'disk: off — minFreeDiskGb absent\nmem: off — minFreeMemGb absent')"
ok "no probe ran" "$(wc -l < "$CALLS" | tr -d ' ')" 0
config '"minFreeDiskGb": null, "minFreeMemGb": null'; run
ok "a null key is absent too" "$RC:$(grep -c ': off — ' <<<"$OUT")" "0:2"

echo "== disk below and above the floor, on <reposRoot>/_wt when worktreeRoot is absent =="
config '"minFreeDiskGb": 60'; run
ok "below: exit 1" "$RC" 1
has "below: value, floor and key" "$OUT" "disk: 51.2 GB free at $REPOS/_wt, below minFreeDiskGb 60 GB — dispatch refused"
has "below: mem key absent is still off" "$OUT" "mem: off — minFreeMemGb absent"
config '"minFreeDiskGb": 40.5'; run
ok "above: exit 0" "$RC" 0
has "above: ok line" "$OUT" "disk: 51.2 GB free at $REPOS/_wt, floor minFreeDiskGb 40.5 GB — ok"
config "\"worktreeRoot\": \"$TMP/not-yet/wt\", \"minFreeDiskGb\": 1"; run
has "worktreeRoot not created yet: its nearest existing ancestor is measured" "$(cat "$CALLS")" "df -Pk $TMP"

echo "== memory below and above: free + inactive + purgeable, never Pages free alone =="
config '"minFreeMemGb": 9'; run
ok "below: exit 1" "$RC" 1
has "below: value, floor and key" "$OUT" "mem: 8.3 GB available, below minFreeMemGb 9 GB — dispatch refused"
config '"minFreeMemGb": 1'; run
ok "above (Pages free alone is 0.08 GB): exit 0" "$RC" 0
has "above: ok line" "$OUT" "mem: 8.3 GB available, floor minFreeMemGb 1 GB — ok"
printf 'MemTotal: 16000000 kB\nMemFree: 100000 kB\nMemAvailable: 3000000 kB\n' > "$TMP/meminfo"
UNAME=Linux LOOPD_MEMINFO="$TMP/meminfo"
config '"minFreeMemGb": 4'; run
has "Linux below: MemAvailable" "$OUT" "mem: 3.1 GB available, below minFreeMemGb 4 GB — dispatch refused"
config '"minFreeMemGb": 2'; run
ok "Linux above: exit 0" "$RC" 0
UNAME=Darwin; unset LOOPD_MEMINFO

echo "== a failed measurement is UNKNOWN and allows the dispatch =="
config '"minFreeDiskGb": 60, "minFreeMemGb": 9'
DF_KB="" VM_FREE="" run
ok "exit 0" "$RC" 0
has "disk UNKNOWN names key and floor" "$OUT" "disk: UNKNOWN (df failed at $REPOS/_wt) — dispatch allowed, minFreeDiskGb 60"
has "mem UNKNOWN names key and floor" "$OUT" "mem: UNKNOWN (vm_stat gave no free, inactive and purgeable page counts) — dispatch allowed, minFreeMemGb 9"
UNAME=Plan9 run
has "an OS with no probe is UNKNOWN" "$OUT" "mem: UNKNOWN (no memory probe for Plan9)"

mkdir -p "$TMP/nopy"; printf '#!/bin/sh\nexit 3\n' > "$TMP/nopy/python3"; chmod +x "$TMP/nopy/python3"
config '"minFreeDiskGb": 60, "minFreeMemGb": 9'; : > "$CALLS"
OUT="$(PATH="$TMP/nopy:$BIN:$PATH" CALLS="$CALLS" bash "$SCRIPT" --instance "$INST" 2>&1)"; RC=$?
ok "a config that cannot be read: exit 0" "$RC" 0
has "…disk is UNKNOWN, not off" "$OUT" "disk: UNKNOWN (could not read minFreeDiskGb: resolve-config.sh exit 3) — dispatch allowed"
has "…and memory is still evaluated" "$OUT" "mem: UNKNOWN (could not read minFreeMemGb: resolve-config.sh exit 3) — dispatch allowed"

echo "== per-machine: the local file wins, and a bad value is no gate =="
config '"minFreeDiskGb": 1'
printf '{ "minFreeDiskGb": 60 }\n' > "$INST/instance.config.local.json"; run
ok "local floor refuses over a tracked one that would pass" "$RC" 1
config '"minFreeDiskGb": "60", "minFreeMemGb": 0'; run
ok "a quoted or zero floor: exit 0" "$RC" 0
has "…and says why" "$OUT" 'disk: off — minFreeDiskGb is not a positive number of GB ("60")'

echo "== the real probes parse on this machine (no shims) =="
config "\"worktreeRoot\": \"$TMP\", \"minFreeDiskGb\": 0.001, \"minFreeMemGb\": 0.001"
OUT="$(bash "$SCRIPT" --instance "$INST")"; RC=$?
ok "real run: exit 0" "$RC" 0
ok "real df parses" "$(grep -c '^disk: .* — ok$' <<<"$OUT")" 1
case "$(uname -s)" in
  Darwin) probe=$(command -v vm_stat >/dev/null && echo yes) ;;
  Linux)  probe=$([ -r /proc/meminfo ] && echo yes) ;;
  *)      probe="" ;;
esac
if [ -n "$probe" ]; then ok "real memory probe parses" "$(grep -c '^mem: .* — ok$' <<<"$OUT")" 1
else printf '  SKIP  real memory probe: none on %s\n' "$(uname -s)"; fi

echo "== step 3 runs the gate before the wave =="
ok "step-3-dispatch.md names resource-gate.sh" \
  "$(grep -c 'scripts/resource-gate.sh' "$TPL/plugin/tick-steps/step-3-dispatch.md" | tr -d ' ')" 1

printf '\nresource-gate.test: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
