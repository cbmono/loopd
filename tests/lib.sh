#!/usr/bin/env bash
#
# lib.sh — helpers a harness SOURCES: `. "$REPO/tests/lib.sh"`. Not a harness itself.
# Spell the path with `tests/lib.sh` in it: run.sh selects a harness that NAMES a changed
# path, so that spelling is what re-runs every user of this file when it changes.
#
#   ok <name> <actual> <expected>   one assertion, house style, counted in $pass/$fail
#   finish                          prints `pass=N fail=N`; non-zero on any failure
#   fixture_bundle <dest>           a freshly STAMPED bundle at <dest>, from a cache
#   fixture_stamp_real <dest>       the real stamp the cache is built from
#
# WHEN NOT TO USE fixture_bundle. It is for a harness that needs a stamped bundle as
# SETUP — something to mutate, re-stamp, or point another script at. A harness whose
# SUBJECT is plugin/scripts/init-bundle.sh itself (what a first stamp writes or prints, a
# re-stamp, --uninstall, the team prompt, any flag) must keep calling the real script: a
# copy cannot fail the way the stamp can. So must one that stamps from a template it has
# edited — the cache is keyed on THIS checkout's plugin/, not on a fixture's copy.
#
# WHAT A COPY IS. One real stamp of an absent directory, taken with no identity to derive
# (`gh` fails, no git user.email — what CI's runner has), cached under
# ${TMPDIR:-/tmp}/loopd-test-cache.<uid>/<key>/ and copied with `cp -R`. The key hashes
# every file under plugin/ and this file, so an edit to the stamp or the seed misses the
# cache. Three things in a stamp depend on where it landed, and each is redone rather
# than cached:
#   * the absolute paths it writes (the statusLine command, the workspace's terminal cwd,
#     the derived reposRoot) are rewritten from the cache's location to <dest>'s;
#   * the workspace file is named after the bundle's group, so it is renamed to what
#     bundle-paths.sh's own ab_group answers for <dest>;
#   * the repos/ view links <dest>'s SIBLING repos, so link-repos.sh is re-run there.
# A copy that still names the cache anywhere is refused, never served.
# A <dest> that is not empty gets the real stamp instead — do NOT reorder a harness to
# stamp first and populate after: a pre-made projects/ changes what the stamp seeds. So
# does a <dest> whose path has a character outside [A-Za-z0-9._/+-]. tests/lib.test.sh diffs a copy against a real stamp in each
# shape a caller uses; FIXTURE_BUNDLE_NO_CACHE=1 turns every call into the real one.

: "${pass:=0}" "${fail:=0}"
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
finish() { echo "pass=$pass fail=$fail"; [ "$fail" -eq 0 ]; }

LIB_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The directory name the cached stamp is taken under. Distinctive on purpose: it must not
# occur in a stamped file for any other reason, because a copy that contains it is refused.
FX_ORIGIN=loopd-fixture-origin

_fx_sha() { if command -v shasum >/dev/null 2>&1; then shasum; else sha1sum; fi; }

# fixture_key — content, not `git ls-files -s`: an UNSTAGED edit to the stamp
# has to miss the cache too, and a fixture copy of this repo has no index at all.
fixture_key() {
  ( cd "$LIB_REPO" || exit 1
    { find plugin -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum 2>/dev/null \
        || find plugin -type f -print0 | LC_ALL=C sort -z | xargs -0 sha1sum
      find plugin -type f -perm -u+x | LC_ALL=C sort
      find plugin -type l | LC_ALL=C sort
      _fx_sha < tests/lib.sh
    } | _fx_sha | cut -c1-40 )
}

# `cd && pwd`, as the stamp spells its own target: a TMPDIR with a trailing slash would
# otherwise give a path no stamped file contains, and the leak check below would be blind.
fixture_cache_home() {
  local t; t="$(cd "${TMPDIR:-/tmp}" 2>/dev/null && pwd)" || t="${TMPDIR:-/tmp}"
  printf '%s/loopd-test-cache.%s' "${t%/}" "$(id -u)"
}

# The stamp, with nothing to derive an identity from and no network to wait on.
fixture_stamp_real() { # <dest>  (stdout/stderr are the stamp's own)
  local env rc=0
  env="$(mktemp -d "${TMPDIR:-/tmp}/loopd-fixture-env.XXXXXX")" || return 2
  printf '#!/bin/sh\nexit 1\n' > "$env/gh"; chmod +x "$env/gh"
  ( unset CLAUDE_PLUGIN_ROOT TEAM_SETUP_STDIN NORMALISE_CONFIG_STDIN
    PATH="$env:$PATH" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
    CLAUDE_CONFIG_DIR="$env/claude" \
      bash "$LIB_REPO/plugin/scripts/init-bundle.sh" "$1" </dev/null ) || rc=$?
  rm -rf "$env"
  return "$rc"
}

_fx_has_sibling_repo() { # <parent> <dest> — link-repos.sh's own rule for what it links
  local d
  for d in "$1"/* "$1"/.[!.]*; do
    [ -e "$d/.git" ] || continue
    case "${d##*/}" in _*) continue ;; esac
    [ "$d" = "$2" ] || return 0
  done
  return 1
}

fixture_bundle() { # <dest>
  local dest="${1:-}" full parent home slot tmp origin f ws
  [ -n "$dest" ] || { echo "fixture_bundle: usage: fixture_bundle <dest>" >&2; return 2; }
  if [ -e "$dest" ] && { [ ! -d "$dest" ] || [ -n "$(ls -A "$dest" 2>/dev/null)" ]; }; then
    fixture_stamp_real "$dest" >/dev/null 2>&1; return
  fi
  mkdir -p "$dest" || return 2
  full="$(cd "$dest" && pwd)" || return 2
  parent="${full%/*}"
  home="$(fixture_cache_home)"
  if [ -n "${FIXTURE_BUNDLE_NO_CACHE:-}" ] || [ -z "$parent" ] \
     || ! ( LC_ALL=C; case "$full" in *[!A-Za-z0-9._/+-]*) exit 1 ;; esac ) \
     || ! mkdir -p -m 700 "$home" 2>/dev/null || [ ! -O "$home" ] || [ -L "$home" ]; then
    fixture_stamp_real "$dest" >/dev/null 2>&1; return
  fi
  slot="$home/$(fixture_key)"
  if [ ! -f "$slot/origin" ]; then
    # Build beside the slot and rename(2) into place: a rename onto an existing slot
    # fails instead of nesting (which `mv` would do), so a concurrent builder loses
    # cleanly and both read the one that won.
    tmp="$(mktemp -d "$home/.build.XXXXXX")" || return 2
    mkdir -p "$tmp/root"
    if fixture_stamp_real "$tmp/root/$FX_ORIGIN" >"$tmp/stamp.out" 2>&1; then
      ( cd "$tmp/root" && pwd ) > "$tmp/origin"
      perl -e 'exit(rename($ARGV[0], $ARGV[1]) ? 0 : 1)' "$tmp" "$slot" 2>/dev/null || rm -rf "$tmp"
    else
      echo "fixture_bundle: the real stamp failed — see $tmp/stamp.out" >&2; return 1
    fi
    [ -f "$slot/origin" ] || { echo "fixture_bundle: no cache slot at $slot" >&2; return 1; }
  fi
  origin="$(cat "$slot/origin")"
  # Asked while <dest> is still empty, which is when the stamp asks: before the seed config.
  ws="$( . "$LIB_REPO/plugin/scripts/bundle-paths.sh" && ab_group "$full" )" || return 1
  cp -R "$slot/root/$FX_ORIGIN/." "$dest/" || return 1
  # The bundle's own path first, then what is left of its parent (reposRoot).
  find "$dest" -type f -exec grep -lF -- "$origin" {} + 2>/dev/null | while IFS= read -r f; do
    FROM="$origin" FULL="$full" TO="$parent" B="$FX_ORIGIN" perl -pi -e \
      's/\Q$ENV{FROM}\E\/\Q$ENV{B}\E(?![A-Za-z0-9._+-])/$ENV{FULL}/g; s/\Q$ENV{FROM}\E/$ENV{TO}/g' "$f"
  done
  if [ -f "$dest/$FX_ORIGIN.code-workspace" ]; then
    mv "$dest/$FX_ORIGIN.code-workspace" "$dest/$ws.code-workspace" || return 1
  fi
  if _fx_has_sibling_repo "$parent" "$full"; then
    ( cd "$dest" && bash "$LIB_REPO/plugin/scripts/link-repos.sh" ) >/dev/null 2>&1 || return 1
  fi
  if grep -rqF -e "$home" -e "$FX_ORIGIN" "$dest" 2>/dev/null \
     || find "$dest" -name "*$FX_ORIGIN*" | grep -q . \
     || find "$dest" -type l -exec readlink {} \; | grep -qF -e "$home" -e "$FX_ORIGIN"; then
    echo "fixture_bundle: $dest still names the cache ($home) — refusing to serve it" >&2
    return 1
  fi
}
