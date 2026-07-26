#!/usr/bin/env bash
# Fast-forward one or all installed skills to their default branch and bump
# the outer pointer.
#
# Usage:
#   update.sh <name>
#   update.sh --all
#
# Refuses to touch submodules with uncommitted local changes. In --all mode,
# per-skill failures are reported but do not stop the batch; the script
# exits non-zero if any skill failed.
#
# You still need to `git push` the outer repo yourself when this returns.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

require_cmd git

[ $# -ge 1 ] || die "usage: update.sh <name>|--all"

root="$(workspace_root)"
cd "${root}"

# Perform the update for one submodule. Returns 0 on success or no-op, 1 on
# per-skill failure. Never calls `die` so callers can iterate.
update_one() {
  local rel_path="$1"
  local name
  name="$(basename "${rel_path}")"

  if [ ! -e "${root}/${rel_path}/.git" ]; then
    echo "error: submodule '${rel_path}' is not initialized. run: git submodule update --init -- '${rel_path}'" >&2
    return 1
  fi

  if ! ( cd "${root}/${rel_path}" && git diff --quiet && git diff --cached --quiet ); then
    echo "error: submodule '${rel_path}' has uncommitted changes. commit or stash them first, then rerun." >&2
    return 1
  fi

  local before after
  before="$(cd "${root}/${rel_path}" && git rev-parse HEAD)"

  info "updating ${rel_path}"
  if ! ( cd "${root}/${rel_path}" && git fetch --tags origin && git pull --ff-only ); then
    echo "error: fast-forward failed for '${rel_path}'. resolve manually inside the submodule." >&2
    return 1
  fi

  after="$(cd "${root}/${rel_path}" && git rev-parse HEAD)"

  if [ "${before}" = "${after}" ]; then
    info "  already up to date (${after:0:7})"
    return 0
  fi

  git add "${rel_path}"
  git commit -m "Bump ${name} skill to ${after:0:7}"
  info "  bumped ${before:0:7} -> ${after:0:7}"
  return 0
}

if [ "$1" = "--all" ]; then
  mapfile -t all_paths < <(submodule_names)
  [ "${#all_paths[@]}" -gt 0 ] || die "no submodules found in .gitmodules."

  failed=()
  for p in "${all_paths[@]}"; do
    validate_gitmodules_path "${root}" "${p}"
    if ! update_one "${p}"; then
      failed+=("${p}")
    fi
  done

  info ""
  if [ "${#failed[@]}" -gt 0 ]; then
    info "failed skills:"
    for f in "${failed[@]}"; do
      info "  - ${f}"
    done
    info "next: fix the failures above, then rerun update.sh --all"
    exit 1
  fi
  info "next: git push"
else
  name="$1"
  validate_skill_name "${name}"
  rel_path="$(skill_rel_path "${root}" "${name}")"
  is_submodule_path "${rel_path}" || die "'${name}' is not an installed submodule at '${rel_path}'."
  update_one "${rel_path}" || exit 1
  info ""
  info "next: git push"
fi
