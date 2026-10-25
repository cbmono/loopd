#!/usr/bin/env bash
#
# role-signature.sh — the line a role agent ends every PR comment and review with:
# `— <login>-<short>`, the login from `decision-stamp.sh --self`.
#
#   Usage: role-signature.sh <qa-reviewer|software-engineer|devops-engineer|project-manager>
#                            [--instance <bundle>]
#
# A LABEL FOR HUMANS, NEVER EVIDENCE: every agent posts under one login, and the implementer
# can type this line too. Exit 0 printed (`<unknown>` when no ownerGithubUser), 2 usage.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
inst="."; role=""

usage() { sed -n '6,7p' "$0" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --instance) [ $# -ge 2 ] || usage; inst="$2"; shift 2 ;;
    -h|--help) sed -n '3,10p' "$0"; exit 0 ;;
    -*) usage ;;
    *) [ -z "$role" ] || usage; role="$1"; shift ;;
  esac
done

case "$role" in
  qa-reviewer) short=qa ;;
  software-engineer) short=dev ;;
  devops-engineer) short=ops ;;
  project-manager) short=pm ;;
  *) usage ;;
esac

login="$(bash "$HERE/decision-stamp.sh" --self --instance "$inst" 2>/dev/null)"
printf '— %s-%s\n' "${login:-<unknown>}" "$short"
