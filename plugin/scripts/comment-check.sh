#!/usr/bin/env bash
# comment-check.sh — report every comment line a branch adds that is not a section header,
# an http(s) link or a machine-read line, per plugin/seed/CONVENTIONS.md → "Write less".
#   comment-check.sh [-C <repo>] [--range <base>...<head>]   (default origin/<default>...HEAD)
# Report-only (D2): always exits 0; prints UNKNOWN when it cannot read the diff.
set -u
dir=.; range=
unknown() { echo "comment-check: UNKNOWN — $1"; exit 0; }
while [ $# -gt 0 ]; do
  case "$1" in
    -C) [ $# -ge 2 ] || unknown "usage: comment-check.sh [-C <repo>] [--range <base>...<head>]"; dir="$2"; shift 2 ;;
    --range) [ $# -ge 2 ] || unknown "usage: comment-check.sh [-C <repo>] [--range <base>...<head>]"; range="$2"; shift 2 ;;
    *) unknown "usage: comment-check.sh [-C <repo>] [--range <base>...<head>]" ;;
  esac
done
if [ -z "$range" ]; then
  def="$(git -C "$dir" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)" ||
    unknown "origin/HEAD is not set in $dir; pass --range <base>...<head>"
  range="$def...HEAD"
fi
diff="$(git -C "$dir" diff --no-color --no-ext-diff -U0 "$range" -- 2>/dev/null)" ||
  unknown "git diff $range failed in $dir"

printf '%s\n' "$diff" | LC_ALL=C awk -v range="$range" -v sq="'" '
function family(p,   b, e) {
  b = p; sub(/.*\//, "", b); e = b; if (e !~ /\./) e = ""; else sub(/.*\./, "", e)
  if (b ~ /^(Makefile|GNUmakefile|Dockerfile.*|Containerfile|Gemfile|Rakefile|Procfile|Brewfile|Vagrantfile|CODEOWNERS|\.gitignore|\.gitattributes|\.dockerignore|\.editorconfig|\.env.*)$/) return "#"
  if (e ~ /^(sh|bash|zsh|ksh|fish|py|pyi|rb|pl|pm|r|yml|yaml|toml|cfg|conf|ini|properties|mk|cmake|nix|ex|exs|ps1|jl|coffee|tfvars|bats)$/) return "#"
  if (e ~ /^(tf|hcl)$/) return "# // /*"
  if (e == "php") return "# // /*"
  if (e ~ /^(js|jsx|ts|tsx|mjs|cjs|mts|cts|go|rs|java|kt|kts|swift|c|h|cc|cpp|hpp|cxx|cs|scala|dart|groovy|gradle|jsonc|json5|proto|zig|sol)$/) return "// /*"
  if (e ~ /^(scss|less)$/) return "// /*"
  if (e ~ /^(css|sass)$/) return "/*"
  if (e ~ /^(sql|lua|hs|elm|ada|adb|ads)$/) return "--"
  if (e ~ /^(vue|svelte)$/) return "<!-- // /*"
  if (e ~ /^(html|htm|xhtml|xml|svg|md|markdown|mdx)$/) return "<!--"
  return ""
}
function has(m) { return index(" " fam " ", " " m " ") > 0 }
function trailing(s,   i, c, q, n) {
  q = ""; n = length(s)
  for (i = 2; i <= n; i++) {
    c = substr(s, i, 1)
    if (q != "") { if (c == q) q = ""; continue }
    if (c == "\"" || c == sq || c == "`") { q = c; continue }
    if (substr(s, i - 1, 1) !~ /[ \t]/) continue
    if (has("#") && c == "#") return substr(s, i)
    if (has("//") && substr(s, i, 2) == "//") return substr(s, i)
    if (has("/*") && substr(s, i, 2) == "/*") return substr(s, i)
    if (has("--") && substr(s, i, 2) == "--") return substr(s, i)
  }
  return ""
}
function body(s) {
  sub(/^[ \t]*/, "", s)
  sub(/^(#+|\/\/+|--+|<!--|\/\*+|\*+)/, "", s)
  sub(/(-->|\*+\/)[ \t]*$/, "", s)
  gsub(/^[ \t]+|[ \t]+$/, "", s)
  return s
}
function machine(raw, b, ln,   l) {
  if (ln == 1 && raw ~ /^#!/) return 1
  l = tolower(b)
  return l ~ /(spdx-license-identifier|copyright|licen[cs]e|eslint-|eslint |prettier-ignore|noqa|@ts-|type: *ignore|pylint: *(disable|enable)|shellcheck +(disable|enable|source|shell)|rubocop:|nolint|istanbul ignore|c8 ignore|biome-ignore|@flow|@jsx|frozen_string_literal|-\*-|^vim?:|pragma|^go:|swiftlint:|tslint:|stylelint-|markdownlint-|^syntax=|^escape=|^inline:|^\/inline$|^tool-mention:|^okf-verdict)/
}
function flush(   i, t, w) {
  t = 0
  for (i = 1; i <= nrun; i++) if (kind[i] == "text") { t++; w = i }
  if (t == 1 && split(rb[w], _w, /[ \t]+/) <= 8 && rb[w] !~ /\.([ \t]|$)/) t = 0
  if (t > 0) for (i = 1; i <= nrun; i++) if (kind[i] == "text") out[++nout] = rp[i] ":" rl[i] ": " rr[i]
  nrun = 0
}
function add(raw, b, ln) {
  nrun++; rp[nrun] = path; rl[nrun] = ln; rb[nrun] = b; rr[nrun] = raw
  sub(/^[ \t]+/, "", rr[nrun])
  if (machine(raw, b, ln) || b ~ /https?:\/\//) kind[nrun] = "ok"
  else if (b !~ /[A-Za-z0-9]/) kind[nrun] = "deco"
  else kind[nrun] = "text"
}
/^diff --git / { flush(); hdr = 1; path = ""; fam = ""; blk = ""; next }
hdr && /^\+\+\+ / { path = substr($0, 5); sub(/^b\//, "", path); fam = (path == "/dev/null") ? "" : family(path); next }
/^@@ / { flush(); hdr = 0; blk = ""; match($0, /\+[0-9]+/); ln = substr($0, RSTART + 1, RLENGTH - 1) + 0; next }
hdr { next }
/^\+/ {
  s = substr($0, 2); u = s; sub(/^[ \t]+/, "", u); cur = ln; ln++
  if (fam == "") next
  if (blk != "") { add(s, body(u), cur); if (index(u, blk)) blk = ""; next }
  if ((has("#") && u ~ /^#/) || (has("//") && u ~ /^\/\//) || (has("--") && u ~ /^--/)) { add(s, body(u), cur); next }
  if (has("/*") && u ~ /^\/\*/) { add(s, body(u), cur); if (!index(substr(u, 3), "*/")) blk = "*/"; next }
  if (has("<!--") && u ~ /^<!--/) { add(s, body(u), cur); if (!index(substr(u, 5), "-->")) blk = "-->"; next }
  flush()
  t = trailing(s)
  if (t != "") { add(s, body(t), cur); flush() }
  next
}
{ flush() }
END {
  flush()
  printf "comment-check: %d added comment line(s) neither a header, a link nor machine-read in %s (report only; repo conventions override)\n", nout, range
  for (i = 1; i <= nout; i++) print out[i]
}'
exit 0
