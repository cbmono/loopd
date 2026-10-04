#!/usr/bin/env bash
#
# deliverable-paths-vs-yaml.test.sh — the deliverables panel, measured against a REAL
# YAML PARSER rather than against anyone's reading of the spec.
#
# WHY THIS FILE EXISTS, and it is not a style preference. `deliverable_paths:` is parsed
# by hand: write-snapshot.sh ships to instances on machines we never see and may not
# depend on python3, PyYAML or Ruby, so it reads its own frontmatter with awk and sed.
# A hand parser is a CLAIM about a data format, and six review rounds of this one were
# each settled by argument — each round closed the reported shape and opened another of
# the same class, because a property argued for is only as good as the shapes whoever
# argued it thought of. Round 6 was measured against Psych instead and found, in one
# pass, a shape that the harness ITSELF was asserting backwards.
#
# So this is the assertion that could not be written as prose: FOR EACH SHAPE, WHAT THE
# BOARD RENDERS EQUALS WHAT A REAL PARSER READS, FILTERED THROUGH THE RENDERER'S OWN
# PREDICATE. Both sides run for real —
#   · the "board" side is the shipped write-snapshot.sh and build-board.sh, run
#     end-to-end over a fixture instance, read back off the rendered page's `data-copy`
#     attributes. Nothing is re-implemented, so nothing can drift from what ships;
#   · the "parser" side is PyYAML or Ruby's Psych over the same project.md, filtered
#     through DELIV_SEG / DELIV_PATH / bundle_deliverable() EXTRACTED VERBATIM from
#     build-board.sh at runtime (see extract_predicate below) — again, not copied here,
#     because a copied predicate is a second implementation that goes stale silently.
#
# IT SKIPS, IT NEVER FALSELY FAILS. A machine with neither PyYAML nor Psych has no
# oracle, and an oracle-less run must not turn red — that would make a missing optional
# dependency look like a defect in the shipped scripts. It reports SKIP and exits 0.
# THE SAME HOLDS PER SHAPE, and it did not until this was written: the two oracles
# disagree about `flow-comment-tab`, so the file read 56/0 on CI (Psych) and 54/2 on a
# machine with PyYAML, at one commit. An oracle is now chosen by conformance and a shape
# it cannot read is SKIPped, so the verdict is the board's and never the machine's.
#
# THREE CLASSES OF SHAPE, and the third is the honest part:
#   agree   the parser has an answer and the board must match it exactly, in order.
#   gap     a KNOWN, pre-existing disagreement (see GAPS below). Asserted only in
#           aggregate, via AGREE_FLOOR: a gap that gets FIXED must not turn this file
#           red — that would be a test that fails on an improvement — but a NEW gap
#           drops the count below the floor and does.
#   noyaml  not valid YAML at all (an unterminated quote or flow list), so the parser
#           refuses the document and there is no reading to be faithful to. The
#           documented fallback is asserted explicitly instead, per shape.
#
# Verified alongside tests/snapshot.test.sh, which pins the same behaviours as unit
# assertions; this file is what stops the two of them agreeing with each other and both
# being wrong.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$(dirname "$0")/../plugin/scripts/bundle-paths.sh"

TPL="$(cd "$HERE/.." && pwd)"
WRITER="$TPL/plugin/scripts/write-snapshot.sh"
BOARD="$TPL/plugin/scripts/build-board.sh"

pass=0; fail=0; skip=0
assert()  { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
            else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
skipped() { printf '  SKIP  %s\n' "$1"; skip=$((skip+1)); }
eq()      { [[ "$1" == "$2" ]] && echo 0 || echo 1; }
summary() { echo; echo "pass=$pass fail=$fail skip=$skip"; [[ "$fail" == 0 ]] || exit 1; exit 0; }

for f in "$WRITER" "$BOARD"; do
  [[ -f "$f" ]] || { echo "deliverable-paths-vs-yaml: missing $f" >&2; exit 2; }
done
command -v python3 >/dev/null 2>&1 || {
  echo "deliverable-paths-vs-yaml: needs python3 (build-board.sh does too)." >&2; exit 2; }

# ---------------------------------------------------------------------- fixtures
# Two steps, never one — see tests/harness-temp-safety.test.sh for what the
# one-expression form deletes. Before the oracle, because choosing one needs a file.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/deliv-yaml.XXXXXX")" || {
  echo "deliverable-paths-vs-yaml: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}." >&2; exit 2; }
TMP="$(cd "$TMP" && pwd)"
trap 'rm -rf "$TMP"' EXIT

# ------------------------------------------------------------------ the oracle
# Either parser answers the same question: parse this project.md's frontmatter and print
# `deliverable_paths` as a JSON array, or the word UNPARSEABLE.
#
# THEY DO NOT AGREE, AND PICKING THE FIRST IMPORTABLE ONE PICKED A VERDICT PER MACHINE.
# YAML 1.2 rules 32/33/66: `s-separate-in-line` is `s-white+` and `s-white` includes TAB,
# so a tab before a trailing comment is legal and `flow-comment-tab` has a reading. Psych
# returns it; PyYAML's scanner refuses any tab that cannot start a token — measured
# identical at 6.0, 6.0.1, 6.0.2 and 6.0.3, so it is a deviation and not a regression.
# CI has Psych and no PyYAML and was green; a machine with PyYAML read 54/2 on the same
# commit. So the oracle is CHOSEN by conformance on that construct, not by import order,
# and a shape the chosen oracle cannot read is reported unmeasurable rather than failed.
yaml_read_with() { # <oracle> <project.md> -> JSON array, or UNPARSEABLE
  case "$1" in
    pyyaml) python3 - "$2" <<'PY'
import sys, json, yaml
t = open(sys.argv[1], encoding="utf-8").read().split("\n---\n")[0]
t = t[4:] if t.startswith("---\n") else t
try:
    d = yaml.safe_load(t)
except Exception:
    print("UNPARSEABLE"); raise SystemExit(0)
v = (d or {}).get("deliverable_paths")
print(json.dumps(v if isinstance(v, list) else ([] if v is None else [v])))
PY
      ;;
    psych) ruby - "$2" <<'RB'
require 'psych'
require 'json'
t = File.read(ARGV[0])
t = t.split("\n---\n").first.to_s
t = t.sub(/\A---\n/, '')
begin
  d = Psych.load(t)
rescue Exception
  puts "UNPARSEABLE"; exit 0
end
v = d.is_a?(Hash) ? d['deliverable_paths'] : nil
puts JSON.generate(v.is_a?(Array) ? v : (v.nil? ? [] : [v]))
RB
      ;;
  esac
}

CANDIDATES=()
python3 -c 'import yaml' >/dev/null 2>&1 && CANDIDATES+=(pyyaml)
command -v ruby >/dev/null 2>&1 && ruby -rpsych -e 'Psych::VERSION' >/dev/null 2>&1 && CANDIDATES+=(psych)
if [[ "${#CANDIDATES[@]}" == 0 ]]; then
  skipped "no YAML parser on this machine (PyYAML or Ruby/Psych) — nothing to measure against"
  echo "  NOTE  install either one to run the differential check; the shipped scripts need neither."
  summary
fi

# The probe asserts the SPEC, not the board: `[ /a.md ]<TAB># c` is legal YAML 1.2 and
# reads as one entry. A parser that refuses it is tab-blind and is used only if it is the
# only one here.
printf -- '---\ndeliverable_paths: [ /a.md ]\t# a tab is s-white, so this is a comment\n---\n' > "$TMP/probe.md"
ORACLE=""; ORACLE_TAB_BLIND=""
for c in "${CANDIDATES[@]}"; do
  [[ "$(yaml_read_with "$c" "$TMP/probe.md")" == '["/a.md"]' ]] && { ORACLE="$c"; break; }
done
if [[ -z "$ORACLE" ]]; then ORACLE="${CANDIDATES[0]}"; ORACLE_TAB_BLIND=1; fi

yaml_read() { yaml_read_with "$ORACLE" "$1"; }

# --------------------------------------------------- the renderer's own predicate
# Lifted out of build-board.sh at runtime, never transcribed. Both extractions are
# checked for the names they must contain before anything runs on them: an extraction
# that silently returns nothing would make every comparison below pass against an empty
# filter, which is the vacuous-green failure this PR has already shipped once.
extract_predicate() {
  awk '/^DELIV_SEG = /{f=1} f{print} f && /^$/{exit}' "$BOARD"
  awk '/^def bundle_deliverable\(/{f=1} f && /^def [a-z_]+\(/ && !/^def bundle_deliverable\(/{exit} f{print}' "$BOARD"
}
PREDICATE="$(extract_predicate)"
assert "the renderer's predicate was extracted, not transcribed" \
  "$( { [[ "$PREDICATE" == *"DELIV_SEG = "* ]] && [[ "$PREDICATE" == *"DELIV_PATH = re.compile("* ]] \
       && [[ "$PREDICATE" == *"def bundle_deliverable("* ]] && [[ "$PREDICATE" == *"fullmatch"* ]]; } \
     && echo 0 || echo 1 )"

renderable() { # <json array> <slug> -> one path per line, in order
  PRED="$PREDICATE" python3 - "$1" "$2" <<'PY'
import sys, json, os, re, unicodedata
exec(os.environ["PRED"])
for e in json.loads(sys.argv[1]):
    keep = bundle_deliverable(e, sys.argv[2])
    if keep:
        print(keep)
PY
}

INST="$TMP/_ai-bridge-fixture"
mkdir -p "$INST" "$INST/$AB_DIR"
: > "$INST/$AB_SCHEMA"
cat > "$INST/instance.config.json" <<CFG
{ "org": "fixture-org", "reposRoot": "$TMP/repos", "worktreeRoot": "$TMP/wt",
  "authorEmail": "nobody@example.com" }
CFG

# name | class | expected | the deliverable_paths YAML, `\n` for a newline.
# The third field means one thing per class: for `noyaml` it is the documented fallback
# the board must render; for `gap` it is the entry that gap is KNOWN to FABRICATE, and
# empty means it fabricates nothing. Empty for `agree`, which is pinned exactly.
# `SLUG` is replaced by the shape's own slug, so every shape addresses its own project
# and a value that renders can only have come from the shape that wrote it.
#
# The absolute path planted in the hostile shapes is a sentinel, not a real one.
ABS="/Users/SENTINEL-HOME/.ssh/id_rsa"
# The same sentinel with only ORDINARY segments. `.ssh` is rejected by the rule that a
# segment may not begin with `.`, so a colon vector spelled with it stays green when `:`
# is re-admitted to the class — measured. This spelling isolates the `:` exclusion.
ORD="/Users/SENTINEL-HOME/Desktop/keys.txt"
SHAPES=(
  # --- the ordinary forms closeout actually writes ------------------------------
  "flow-one|agree||deliverable_paths: [ /projects/SLUG/deliverables/report.md ]"
  "flow-many|agree||deliverable_paths: [ /projects/SLUG/deliverables/a.md, /projects/SLUG/deliverables/b.md ]"
  "flow-empty|agree||deliverable_paths: [ ]"
  "flow-empty-tight|agree||deliverable_paths: []"
  "bare-key|agree||deliverable_paths:"
  "nested|agree||deliverable_paths: [ /projects/SLUG/deliverables/site/index.html ]"
  "unicode|agree||deliverable_paths: [ /projects/SLUG/deliverables/Übersicht.md ]"
  "unicode-hash|agree||deliverable_paths: [ /projects/SLUG/deliverables/roh-Ü#1.md, /projects/SLUG/deliverables/ok.md ]"
  "dotted|agree||deliverable_paths: [ /projects/SLUG/deliverables/v1.2+final.md ]"
  "block|agree||deliverable_paths:\n  - /projects/SLUG/deliverables/a.md\n  - /projects/SLUG/deliverables/b.md"
  # --- trailing comments, the form SCHEMA.md documents --------------------------
  "flow-comment|agree||deliverable_paths: [ /projects/SLUG/deliverables/a.md ]   # stamped by closeout"
  "flow-comment-bracket|agree||deliverable_paths: [ /projects/SLUG/deliverables/a.md ]   # \`[ ]\` means none were found"
  "flow-comment-comma|agree||deliverable_paths: [ /projects/SLUG/deliverables/a.md ]   # kept, and /projects/SLUG/deliverables/ghost.md was not"
  "flow-comment-abs|agree||deliverable_paths: [ /projects/SLUG/deliverables/a.md ]   # taken from $ABS"
  "flow-comment-tab|agree||deliverable_paths: [ /projects/SLUG/deliverables/a.md ]\t# after a tab"
  "block-comment|agree||deliverable_paths:\n  - /projects/SLUG/deliverables/a.md   # first\n  - /projects/SLUG/deliverables/b.md"
  "comment-only|agree||deliverable_paths: [ ]   # closeout found none"
  # --- a `#` that is NOT a comment ---------------------------------------------
  "hash-glued|agree||deliverable_paths: [ /projects/SLUG/deliverables/a#1.md ]"
  "hash-glued-abs|agree||deliverable_paths: [ /projects/SLUG/deliverables/see#$ABS ]"
  # --- double-quoted scalars ----------------------------------------------------
  "dq-plain|agree||deliverable_paths: [ \"/projects/SLUG/deliverables/a.md\" ]"
  "dq-many|agree||deliverable_paths: [ \"/projects/SLUG/deliverables/a.md\", \"/projects/SLUG/deliverables/b.md\" ]"
  "dq-hash-inside|agree||deliverable_paths: [ \"/projects/SLUG/deliverables/a #1.md\", \"/projects/SLUG/deliverables/b.md\" ]"
  "dq-bracket-inside|agree||deliverable_paths: [ \"/projects/SLUG/deliverables/a ] #1.md\", \"/projects/SLUG/deliverables/b.md\" ]"
  "dq-comment-after|agree||deliverable_paths: [ \"/projects/SLUG/deliverables/a.md\" ]   # note"
  "dq-escape|agree||deliverable_paths: [ \"/projects/SLUG/deliverables/a\\\\\"q.md\", \"/projects/SLUG/deliverables/b.md\" ]"
  # --- single-quoted scalars, and YAML's ONE single-quote escape ----------------
  "sq-plain|agree||deliverable_paths: [ '/projects/SLUG/deliverables/a.md' ]"
  "sq-many|agree||deliverable_paths: [ '/projects/SLUG/deliverables/a.md', '/projects/SLUG/deliverables/b.md' ]"
  "sq-hash-inside|agree||deliverable_paths: [ '/projects/SLUG/deliverables/a #1.md', '/projects/SLUG/deliverables/b.md' ]"
  "sq-escape|agree||deliverable_paths: [ '/projects/SLUG/deliverables/o''brien[draft].md #2', /projects/SLUG/deliverables/clean.md ]"
  "sq-escape-only|agree||deliverable_paths: [ '/projects/SLUG/deliverables/o''brien.md' ]"
  "sq-escape-comment|agree||deliverable_paths: [ '/projects/SLUG/deliverables/o''brien.md' ]   # from $ABS"
  "sq-block|agree||deliverable_paths:\n  - '/projects/SLUG/deliverables/a #1.md'\n  - /projects/SLUG/deliverables/b.md"
  # --- the flow sequence really does end at the first UNQUOTED `]` --------------
  "bracket-unquoted|agree||deliverable_paths: [ /projects/SLUG/deliverables/a] #1.md, /projects/SLUG/deliverables/b.md ]"
  "hash-on-bracket|gap||deliverable_paths: [ /projects/SLUG/deliverables/a.md ]#note"
  "hash-on-bracket-comma|gap|/projects/SLUG/deliverables/ghost.md|deliverable_paths: [ /projects/SLUG/deliverables/a.md ]#kept, /projects/SLUG/deliverables/ghost.md"
  "mixed-quoting|gap||deliverable_paths: [ \"/projects/SLUG/deliverables/a.md\", /projects/SLUG/deliverables/b.md ]"
  # --- values that must never render, comment or no comment ---------------------
  "two-paths|agree||deliverable_paths: [ /projects/SLUG/deliverables/report.md $ABS ]"
  "colon-glued|agree||deliverable_paths: [ \"/projects/SLUG/deliverables/deck.md:$ORD\" ]"
  "colon-dotfile|agree||deliverable_paths: [ \"/projects/SLUG/deliverables/deck.md:$ABS\" ]"
  "traversal|agree||deliverable_paths: [ /projects/SLUG/deliverables/../../../etc/passwd ]"
  "wrong-slug|agree||deliverable_paths: [ /projects/somebody-else/deliverables/a.md ]"
  "absolute|agree||deliverable_paths: [ $ABS ]"
  "trailing-slash|agree||deliverable_paths: [ /projects/SLUG/deliverables/a.md/ ]"
  "double-slash|agree||deliverable_paths: [ /projects/SLUG/deliverables//a.md ]"
  "prefix-only|agree||deliverable_paths: [ /projects/SLUG/deliverables/ ]"
  # --- not YAML at all: the parser refuses, so the fallback is asserted directly -
  "open-quote|noyaml|/projects/SLUG/deliverables/report.md|deliverable_paths: [ \"/projects/SLUG/deliverables/report.md ]   # hand-edited, from $ABS"
  "open-list|noyaml|/projects/SLUG/deliverables/b.md|deliverable_paths: [ /projects/SLUG/deliverables/a #1.md, /projects/SLUG/deliverables/b.md"
)

# GAPS — the disagreements that are KNOWN and pre-existing, named so the count below is
# not a number nobody can account for. Each is a limit of list_entries_from_region's
# SPLITTER, not of the comment cut, and each renders a bundle-relative path or nothing
# — never an out-of-bundle one, which is what the sweep at the end of this file pins:
#   hash-on-bracket `]#note` with no space is not a comment start for the cut (YAML
#                   ends the sequence at the `]` and reads `#note` as a comment), so the
#                   comment text survives into the split. Spelled with no comma the
#                   fragments are unrenderable and nothing appears.
#   hash-on-bracket-comma
#                   the same gap with a COMMA in the comment, which is the half that
#                   costs something: the splitter cuts there, so the text after it is a
#                   whole well-formed path and RENDERS while the real `a.md` — the only
#                   entry the parser returns — is dropped.
#   mixed-quoting   the splitter picks ONE separator for the whole line — a quote-comma
#                   seam if any quote is present — so a list mixing quoted and unquoted
#                   entries splits on the wrong one.
# AGREE_FLOOR is what stops a NEW gap hiding among them. Fixing one of these RAISES the
# count and stays green, deliberately.
#
# THE BOUND ON A GAP, CORRECTED. This file used to assert of every gap that "the gap
# drops entries — it never fabricates one". That bound is FALSE, and it read green only
# because the one gap that could have contradicted it was spelled without the comma:
# `]#note` renders nothing at all, so the assertion compared an empty list against an
# empty list and certified nothing. The comma variant above is the missing case, and it
# does fabricate. So the bound each gap is now held to is the one that is true and still
# worth having: a gap may DROP any entry, and may fabricate ONLY the entry named in its
# own row — anything else it renders fails. What no gap may do, comma or not, is put an
# out-of-bundle path on the page; that is the sentinel sweep at the end of this file,
# and it is the property the fabrication here does not touch (`ghost.md` is inside
# `/projects/<slug>/deliverables/`, which is why it is a defect worth a task rather than
# a leak worth a round). Attributed: identical at 30c0305, cd44aca and here — a splitter
# limit this PR neither introduced nor enlarged.
GAPS=" hash-on-bracket hash-on-bracket-comma mixed-quoting "
AGREE_FLOOR=42

slug_of() { printf '%s' "$1"; }

for s in "${SHAPES[@]}"; do
  name="${s%%|*}"; rest="${s#*|}"
  klass="${rest%%|*}"; rest="${rest#*|}"
  expected="${rest%%|*}"; yaml="${rest#*|}"
  slug="$(slug_of "$name")"
  mkdir -p "$INST/projects/$slug"
  {
    printf -- '---\n'
    printf 'type: Project\ntitle: %s\nkind: research\nstatus: done\nretain: true\n' "$name"
    printf '%b\n' "${yaml//SLUG/$slug}"
    printf -- '---\n'
    printf '# Context\nshape fixture\n'
  } > "$INST/projects/$slug/project.md"
done

: > "$INST/$AB_SNAPSHOT"
W_RC=0
W_ERR="$( cd "$INST" && SNAPSHOT_NOW=2026-08-22T00:00:00Z bash "$WRITER" --quiet 2>&1 )" || W_RC=$?
assert "the writer exits 0 over every shape at once" "$(eq "$W_RC" 0)"
# A parser that aborts mid-line takes the whole key with it and says so on stderr — the
# `Übersicht.md` case did exactly that until the scan stopped regex-matching single
# bytes. Silence here is part of the contract, not cosmetic.
assert "…and writes nothing to stderr"              "$(eq "$W_ERR" "")"

PAGE="$TMP/board.html"
B_RC=0
B_ERR="$( cd "$TMP" && bash "$BOARD" --out "$PAGE" "$INST" 2>&1 )" || B_RC=$?
assert "the board renders every shape without erroring" "$(eq "$B_RC" 0)"

rendered_for() { # <slug> -> the data-copy values under that project, in page order
  grep -o 'data-copy="[^"]*"' "$PAGE" \
    | sed -e 's/^data-copy="//' -e 's/"$//' \
    | grep -F "/projects/$1/deliverables/" || true
}

agreed=0; disagreed=""; unmeasurable=0; unreadable=""
for s in "${SHAPES[@]}"; do
  name="${s%%|*}"; rest="${s#*|}"
  klass="${rest%%|*}"; rest="${rest#*|}"
  expected="${rest%%|*}"
  slug="$(slug_of "$name")"
  got="$(rendered_for "$slug")"
  raw="$(yaml_read "$INST/projects/$slug/project.md")"

  if [[ "$klass" == "noyaml" ]]; then
    assert "$name: not YAML — the parser refuses it" "$(eq "$raw" "UNPARSEABLE")"
    assert "$name: …and the documented fallback renders" "$(eq "$got" "${expected//SLUG/$slug}")"
    continue
  fi

  # The oracle refusing a shape that IS valid YAML says nothing about the board, and
  # feeding `UNPARSEABLE` to renderable() made it say the opposite: json.loads died, the
  # parser side came back empty, and the shape read as a disagreement.
  if [[ "$raw" == "UNPARSEABLE" ]]; then
    skipped "$name: $ORACLE refuses this shape — unmeasurable here, not a disagreement"
    unmeasurable=$((unmeasurable+1)); unreadable="$unreadable$name "
    continue
  fi

  want="$(renderable "$raw" "$slug")"
  if [[ "$want" == "$got" ]]; then
    agreed=$((agreed+1))
  else
    disagreed="$disagreed$name "
  fi
  case "$GAPS" in
    *" $name "*)
      if [[ "$want" == "$got" ]]; then
        printf '  NOTE  %s: known gap now AGREES — remove it from GAPS and raise AGREE_FLOOR\n' "$name"
      else
        printf '  NOTE  %s: known gap (parser %s | board %s)\n' \
          "$name" "$(printf '%s' "$want" | tr '\n' ' ')" "$(printf '%s' "$got" | tr '\n' ' ')"
      fi
      # A gap is allowed to DROP an entry the parser returns. What it renders that the
      # parser did NOT return is a FABRICATED path — the difference between a missing
      # deliverable a human can see is missing and an invented one — so every gap is
      # held to the exact set of fabrications its own row declares, which for two of the
      # three is none at all. Pinning the set rather than forbidding it outright is what
      # keeps this honest: forbidding it was the false bound, and it stayed green only
      # over a shape that rendered nothing.
      extra=""
      while IFS= read -r got_line; do
        [[ -n "$got_line" ]] || continue
        grep -qxF -- "$got_line" <<<"$want" || extra="$extra$got_line "
      done <<< "$got"
      # `${x:+…}` and not `[[ -n ]] && …`, whose exit status would trip `set -e` on
      # every gap that declares nothing — i.e. on the common case.
      declared="${expected//SLUG/$slug}"
      declared="${declared:+$declared }"
      assert "$name: the gap fabricates exactly what its row declares, and no more" \
        "$(eq "$extra" "$declared")"
      ;;
    *) assert "$name: the board renders exactly what the parser reads" \
         "$( [[ "$want" == "$got" ]] && echo 0 || { printf '        parser: %s\n        board:  %s\n' \
              "$(printf '%s' "$want" | tr '\n' ' ')" "$(printf '%s' "$got" | tr '\n' ' ')" >&2; echo 1; } )" ;;
  esac
done

echo "== agreement with $ORACLE, pinned =="
printf '  INFO  %s of %s comparable shapes agree; disagreeing: %s\n' \
  "$agreed" "$(( ${#SHAPES[@]} - 2 - unmeasurable ))" "${disagreed:-none}"
# AGREE_FLOOR is pinned against a CONFORMANT oracle. A shape this one cannot read was
# never measured, so it is subtracted — printed, named, and only ever by shapes that
# printed a SKIP line above. The pinned constant itself never moves to buy green.
floor="$AGREE_FLOOR"; label="agreement is at or above the pinned floor ($AGREE_FLOOR)"
if [[ "$unmeasurable" != 0 ]]; then
  floor=$(( AGREE_FLOOR - unmeasurable ))
  label="agreement is at or above the pinned floor ($AGREE_FLOOR less $unmeasurable unreadable = $floor)"
  printf '  INFO  %s cannot read: %s— tab-blind=%s\n' "$ORACLE" "$unreadable" "${ORACLE_TAB_BLIND:-0}"
fi
assert "$label" "$( [[ "$agreed" -ge "$floor" ]] && echo 0 || echo 1 )"

# The property that survives every gap: whatever the hand parser makes of a shape, no
# value it renders may carry an out-of-bundle path. The sentinel is planted in six
# shapes above and in no legitimate one, so a hit names its own source.
echo "== and no shape, gap or not, puts the sentinel on the page =="
assert "no rendered data-copy value contains the sentinel path" \
  "$( grep -qF 'SENTINEL-HOME' <<<"$(grep -o 'data-copy="[^"]*"' "$PAGE")" && echo 1 || echo 0 )"
assert "…and none contains a bare /Users/ either" \
  "$( grep -qF '/Users/' <<<"$(grep -o 'data-copy="[^"]*"' "$PAGE")" && echo 1 || echo 0 )"

summary
