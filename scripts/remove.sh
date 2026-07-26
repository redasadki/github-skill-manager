#!/usr/bin/env bash
# Cleanly remove an installed skill submodule.
#
# Usage:
#   remove.sh <name>
#
# Refuses to remove a submodule that has:
#   - uncommitted local changes, or
#   - local commits not present on the origin remote.
#
# If the origin remote cannot be reached to verify the second condition,
# the script FAILS CLOSED and refuses to proceed. This prevents silent
# data loss when the network is flaky.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

require_cmd git

[ $# -eq 1 ] || die "usage: remove.sh <name>"
name="$1"
validate_skill_name "${name}"

root="$(workspace_root)"
cd "${root}"

rel_path="$(skill_rel_path "${root}" "${name}")"
is_submodule_path "${rel_path}" || die "'${name}' is not an installed submodule at '${rel_path}'."

# Safety checks on the submodule working tree.
if [ -d "${root}/${rel_path}/.git" ] || [ -f "${root}/${rel_path}/.git" ]; then
  # 1. Uncommitted changes.
  ( cd "${root}/${rel_path}" && git diff --quiet && git diff --cached --quiet ) \
    || die "submodule '${rel_path}' has uncommitted changes. commit or stash them, then rerun."

  # 2. Unpushed commits, verified against the origin remote.
  #
  # Fetch origin first so we have up-to-date refs for the ancestry check.
  # If the fetch fails, fail closed: we cannot verify unpushed state.
  if ! ( cd "${root}/${rel_path}" && git fetch --quiet origin 2>/dev/null ); then
    die "cannot fetch from origin for '${rel_path}'. refusing to remove because unpushed commits cannot be verified. fix the network or auth, then rerun."
  fi

  local_head="$(cd "${root}/${rel_path}" && git rev-parse HEAD)"

  # Prefer the tracked upstream branch when one is set; fall back to the
  # branch recorded in .gitmodules; fall back to origin/HEAD as a last resort.
  upstream_ref="$(cd "${root}/${rel_path}" && git rev-parse --abbrev-ref '@{u}' 2>/dev/null || true)"
  if [ -z "${upstream_ref}" ]; then
    branch="$(git config -f .gitmodules --get "submodule.${rel_path}.branch" 2>/dev/null || echo "")"
    if [ -n "${branch}" ]; then
      upstream_ref="origin/${branch}"
    else
      upstream_ref="origin/HEAD"
    fi
  fi

  remote_head="$(cd "${root}/${rel_path}" && git rev-parse "${upstream_ref}" 2>/dev/null || true)"
  if [ -z "${remote_head}" ]; then
    die "cannot resolve upstream ref '${upstream_ref}' for '${rel_path}'. refusing to remove because unpushed commits cannot be verified."
  fi

  # local_head is safe to remove iff it is an ancestor of remote_head
  # (i.e., origin already has every commit local has).
  if ! ( cd "${root}/${rel_path}" && git merge-base --is-ancestor "${local_head}" "${remote_head}" 2>/dev/null ); then
    die "submodule '${rel_path}' has local commits not on origin. push them first (cd ${rel_path} && git push), then rerun."
  fi
fi

info "deinitializing ${rel_path}"
git submodule deinit -f -- "${rel_path}"

info "removing ${rel_path} from index and working tree"
git rm -f "${rel_path}"

mod_dir="${root}/.git/modules/${rel_path}"
if [ -d "${mod_dir}" ]; then
  rm -rf "${mod_dir}"
fi

git commit -m "Remove ${name} skill"

info ""
info "removed: ${rel_path}"
info "next:    git push"
