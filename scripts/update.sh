#!/usr/bin/env bash
# Fast-forward one or all installed skills to their default branch and bump
# the outer pointer.
#
# Usage:
#   update.sh <name>
#   update.sh --all
#
# Refuses to touch submodules with uncommitted local changes. You still need
# to `git push` the outer repo yourself when this returns.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

require_cmd git

[ $# -ge 1 ] || die "usage: update.sh <name>|--all"

root="$(workspace_root)"
cd "${root}"

update_one() {
  local rel_path="$1"
  local name
  name="$(basename "${rel_path}")"

  [ -d "${root}/${rel_path}/.git" ] || [ -f "${root}/${rel_path}/.git" ] \
    || die "submodule '${rel_path}' is not initialized. run: git submodule update --init -- '${rel_path}'"

  # Refuse to touch a submodule with local uncommitted work.
  ( cd "${root}/${rel_path}" && git diff --quiet && git diff --cached --quiet ) \
    || die "submodule '${rel_path}' has uncommitted changes. commit or stash them first, then rerun."

  local before after
  before="$(cd "${root}/${rel_path}" && git rev-parse HEAD)"

  info "updating ${rel_path}"
  ( cd "${root}/${rel_path}" && git fetch --tags origin && git pull --ff-only )

  after="$(cd "${root}/${rel_path}" && git rev-parse HEAD)"

  if [ "${before}" = "${after}" ]; then
    info "  already up to date (${after:0:7})"
    return 0
  fi

  git add "${rel_path}"
  git commit -m "Bump ${name} skill to ${after:0:7}"
  info "  bumped ${before:0:7} -> ${after:0:7}"
}

if [ "$1" = "--all" ]; then
  mapfile -t all_paths < <(submodule_names)
  [ "${#all_paths[@]}" -gt 0 ] || die "no submodules found in .gitmodules."
  for p in "${all_paths[@]}"; do
    update_one "${p}"
  done
else
  name="$1"
  rel_path="$(skill_rel_path "${root}" "${name}")"
  is_submodule_path "${rel_path}" || die "'${name}' is not an installed submodule at '${rel_path}'."
  update_one "${rel_path}"
fi

info ""
info "next: git push"
